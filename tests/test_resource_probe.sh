#!/usr/bin/env bash
# roadmap:68dc — resource-probe.sh check-and-defer arbitration
# (slice A, meeting 2026-07-02-1924 decision 4).
#
# On top of the permit window (A4), auto-launch of an intensive mechanical run needs a
# LIVE-availability probe: measured VRAM/RAM/load AND no competing resource:<res> claim.
# CHECK-AND-DEFER, never preempt (a held claim → report unavailable, do NOT kill it).
#
# CONTRACT:
#   resource-probe.sh <resource>  →  one JSON object {resource, available, reason, ...}
#     on stdout; exit 0 when available, nonzero when not.
#   Sources: gpu via nvidia-smi (env-overridable RESOURCE_PROBE_NVIDIA_SMI; graceful
#     "unavailable" with a reason when absent, never a fatal crash); ram via /proc/meminfo;
#     cpu via loadavg; local-llm = claim-only. Thresholds env-overridable
#     (RESOURCE_PROBE_LOAD_MAX, RESOURCE_PROBE_RAM_MIN_MB). Reads `claim.sh peek` sharing
#     CLAIM_BASE — a live resource:<res> claim => available:false.
#
# Hermetic: temp CLAIM_BASE; nvidia-smi pointed at a nonexistent binary; no real GPU,
# no ~/.config, no network. RED until resource-probe.sh lands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/resource-probe.sh"
CLAIM="$ROOT/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]]    || fail "resource-probe.sh not found/executable at $SH (RED)"
[[ -x "$CLAIM" ]] || fail "claim.sh not found/executable at $CLAIM"

export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null
export RESOURCE_PROBE_NVIDIA_SMI="$CLAIM_BASE/no-such-nvidia-smi"   # deliberately absent
trap 'rm -rf "$CLAIM_BASE"' EXIT

avail() { python3 -c "import sys,json;print(str(json.load(sys.stdin).get('available')).lower())"; }

# --- (1) cpu with a generous load ceiling and no claim → available, exit 0 ---
out="$(RESOURCE_PROBE_LOAD_MAX=100000 "$SH" cpu 2>/dev/null)" && rc=0 || rc=$?
[[ "$(avail <<<"$out")" == "true" ]] || fail "(1) cpu under a huge load ceiling must be available (got: $out)"
[[ $rc -eq 0 ]] || fail "(1) an available resource must exit 0 (got $rc)"
pass "(1) cpu is available (exit 0) under a generous load ceiling with no claim"

# --- (2) a live resource:cpu claim → check-and-defer: unavailable + nonzero --
"$CLAIM" acquire resource:cpu --run other-RUN --mode intensive >/dev/null
out="$(RESOURCE_PROBE_LOAD_MAX=100000 "$SH" cpu 2>/dev/null)" && rc=0 || rc=$?
[[ "$(avail <<<"$out")" == "false" ]] || fail "(2) a held resource:cpu claim must make cpu unavailable (got: $out)"
[[ $rc -ne 0 ]] || fail "(2) an unavailable resource must exit nonzero"
"$CLAIM" release resource:cpu --run other-RUN
pass "(2) a live resource:<res> claim defers the probe (unavailable, never preempts)"

# --- (3) gpu with a missing nvidia-smi → graceful unavailable + reason -------
out="$("$SH" gpu 2>/dev/null)" && rc=0 || rc=$?
python3 -c 'import sys,json;json.load(sys.stdin)' <<<"$out" \
  || fail "(3) gpu output must be valid JSON even when nvidia-smi is absent (got: $out)"
[[ "$(avail <<<"$out")" == "false" ]] || fail "(3) gpu must be UNavailable when nvidia-smi is missing (got: $out)"
reason="$(python3 -c "import sys,json;print(json.load(sys.stdin).get('reason',''))" <<<"$out")"
[[ -n "$reason" ]] || fail "(3) a missing-nvidia-smi gpu probe must state a reason (graceful, no crash)"
pass "(3) gpu degrades gracefully to unavailable-with-reason when nvidia-smi is absent"

# --- (4) ram emits valid JSON with an `available` boolean --------------------
out="$("$SH" ram 2>/dev/null)" || true
python3 -c 'import sys,json;o=json.load(sys.stdin);assert isinstance(o.get("available"),bool)' <<<"$out" \
  || fail "(4) ram output must be valid JSON carrying a boolean `available` (got: $out)"
pass "(4) ram emits valid JSON with a boolean available field"

# --- (5) a RAM threshold override flips availability deterministically -------
lo="$(RESOURCE_PROBE_RAM_MIN_MB=1 "$SH" ram 2>/dev/null)" || true
hi="$(RESOURCE_PROBE_RAM_MIN_MB=999999999 "$SH" ram 2>/dev/null)" || true
[[ "$(avail <<<"$lo")" == "true" ]]  || fail "(5) ram must be available with a tiny min-MB threshold (got: $lo)"
[[ "$(avail <<<"$hi")" == "false" ]] || fail "(5) ram must be unavailable with an impossibly-high min-MB threshold (got: $hi)"
pass "(5) an env RAM threshold override flips availability deterministically"

# --- (6) a bespoke claim-only token (r5-jvm) with no claim → available, exit 0 ---
out="$("$SH" r5-jvm 2>/dev/null)" && rc=0 || rc=$?
[[ "$(avail <<<"$out")" == "true" ]] || fail "(6) r5-jvm claim-only token with no claim must be available (got: $out)"
[[ $rc -eq 0 ]] || fail "(6) an available claim-only bespoke token must exit 0 (got $rc)"
pass "(6) bespoke claim-only token r5-jvm is available (exit 0) with no competing claim"

# --- (7) a live resource:r5-jvm claim → check-and-defer: unavailable + nonzero ---
"$CLAIM" acquire resource:r5-jvm --run other-RUN --mode intensive >/dev/null
out="$("$SH" r5-jvm 2>/dev/null)" && rc=0 || rc=$?
[[ "$(avail <<<"$out")" == "false" ]] || fail "(7) a held resource:r5-jvm claim must make r5-jvm unavailable (got: $out)"
[[ $rc -ne 0 ]] || fail "(7) an unavailable bespoke token must exit nonzero"
"$CLAIM" release resource:r5-jvm --run other-RUN
pass "(7) a live resource:r5-jvm claim defers the probe (unavailable, never preempts)"

# --- (8) the other bespoke tokens (lean, xvfb-electron) are recognized, not usage errors ---
for tok in lean xvfb-electron; do
  out="$("$SH" "$tok" 2>/dev/null)" && rc=0 || rc=$?
  [[ "$(avail <<<"$out")" == "true" ]] || fail "(8) $tok claim-only token with no claim must be available (got: $out)"
  [[ $rc -eq 0 ]] || fail "(8) $tok must exit 0 when available (got $rc)"
done
pass "(8) lean + xvfb-electron are recognized claim-only tokens (available with no claim)"

# --- (9) an unknown token still rejects with a usage error + exit 2 ----------
out="$("$SH" not-a-real-resource 2>/dev/null)" && rc=0 || rc=$?
[[ "$(avail <<<"$out")" == "false" ]] || fail "(9) an unknown token must be unavailable (got: $out)"
[[ $rc -eq 2 ]] || fail "(9) an unknown token must exit 2 (usage error), got $rc"
pass "(9) an unknown resource token still rejects with a usage error (exit 2)"

echo "ALL PASS: resource-probe check-and-defer (id:68dc)"
