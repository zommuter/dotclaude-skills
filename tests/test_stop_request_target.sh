#!/usr/bin/env bash
# Defect-fix test (no roadmap: header — failures always count).
#
# id:cd94 — the WRITE side of the aimable stop. `/relay stop` must never silently pick a pool:
# with >1 live pool it REFUSES and lists them, because silently picking one is exactly the
# id:31ce incident (2026-07-31: a killed pool consumed the operator's stop and stopped itself
# while the intended pool ran on for 4 more hours).
#
# Hermetic: fake heartbeat registry + mktemp sentinel dir; never touches ~/.config/relay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQ_SH="$REPO_ROOT/relay/scripts/stop-request.sh"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -x "$REQ_SH" ]] || { echo "FAIL: $REQ_SH missing or not executable"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
stopdir="$tmpdir/cfg"; mkdir -p "$stopdir"
stopfile="$stopdir/STOP"
bindir="$tmpdir/bin"; mkdir -p "$bindir"

RUN_A="relay-20260731-174550-21952"
RUN_B="relay-20260731-221039-22914"

# Stub heartbeat.sh next to a COPY of stop-request.sh so SCRIPT_DIR resolution finds the stub.
cp "$REQ_SH" "$bindir/stop-request.sh"
make_hb() {  # make_hb <runId>...
  { echo '#!/usr/bin/env bash'
    echo '[[ "${1:-}" == "live-runs" ]] || exit 0'
    for r in "$@"; do
      printf 'echo %s\n' "'{\"runId\":\"$r\",\"state\":\"alive\"}'"
    done
    # the non-pool daemon is always present and must never be offered as a target
    printf 'echo %s\n' "'{\"runId\":\"discovery-producer\",\"state\":\"alive\"}'"
  } > "$bindir/heartbeat.sh"
  chmod +x "$bindir/heartbeat.sh"
}
req() { "$bindir/stop-request.sh" --path "$stopfile" "$@"; }

# ── Test 1: exactly one live pool → targeted sentinel, named ──────────────────
echo "Test 1: single live pool auto-targets"
make_hb "$RUN_A"
out="$(req 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && [[ -e "${stopfile}.${RUN_A}" ]] && [[ "$out" == *"$RUN_A"* ]]; then
  ok "targeted sentinel written for the one live pool, runId echoed"
else
  fail_msg "single-pool case did not write ${stopfile}.${RUN_A} (rc=$rc, out=$out)"
fi
[[ -e "$stopfile" ]] && fail_msg "wrote the broadcast file instead of a targeted one" \
                     || ok "broadcast file not written"
rm -f -- "${stopfile}.${RUN_A}"

# ── Test 2: two live pools → REFUSE, write nothing, list both ────────────────
echo "Test 2: ambiguous case refuses rather than guessing"
make_hb "$RUN_A" "$RUN_B"
set +e; out="$(req 2>&1)"; rc=$?; set -e
if [[ $rc -eq 4 ]]; then ok "exit 4 on ambiguity"; else fail_msg "expected exit 4, got $rc"; fi
if [[ "$out" == *"$RUN_A"* && "$out" == *"$RUN_B"* ]]; then
  ok "both candidate runIds listed"
else
  fail_msg "ambiguity message does not list both pools: $out"
fi
if [[ ! -e "$stopfile" && ! -e "${stopfile}.${RUN_A}" && ! -e "${stopfile}.${RUN_B}" ]]; then
  ok "NOTHING written on ambiguity (no pool silently stopped)"
else
  fail_msg "a sentinel was written despite ambiguity — the id:31ce failure mode"
fi

# ── Test 3: --run disambiguates ──────────────────────────────────────────────
echo "Test 3: --run targets explicitly"
out="$(req --run "$RUN_B" 2>&1)"
if [[ -e "${stopfile}.${RUN_B}" && ! -e "${stopfile}.${RUN_A}" ]]; then
  ok "--run wrote only the addressed pool's sentinel"
else
  fail_msg "--run wrote the wrong file(s): $out"
fi
rm -f -- "${stopfile}.${RUN_B}"

# ── Test 4: --run on a dead/unknown run refuses ──────────────────────────────
echo "Test 4: --run must name a LIVE pool"
set +e; out="$(req --run relay-nonexistent 2>&1)"; rc=$?; set -e
if [[ $rc -eq 3 && ! -e "${stopfile}.relay-nonexistent" ]]; then
  ok "unknown runId refused (exit 3), nothing written"
else
  fail_msg "expected exit 3 + no write, got rc=$rc"
fi

# ── Test 5: zero live pools → refuse (a stray sentinel false-stops the NEXT pool) ─
echo "Test 5: no live pool writes nothing"
make_hb
set +e; out="$(req 2>&1)"; rc=$?; set -e
if [[ $rc -eq 3 && ! -e "$stopfile" ]]; then
  ok "no-pool case wrote nothing (exit 3)"
else
  fail_msg "expected exit 3 + no write, got rc=$rc"
fi

# ── Test 6: --all is the explicit, named broadcast ───────────────────────────
echo "Test 6: --all broadcasts"
make_hb "$RUN_A" "$RUN_B"
req --all >/dev/null 2>&1
if [[ -e "$stopfile" ]]; then ok "--all wrote the broadcast sentinel"; else fail_msg "--all wrote nothing"; fi
rm -f -- "$stopfile"

# ── Test 6b: --all with NO live pool refuses (the landmine case) ─────────────
# A broadcast with nothing live is not a stop, it is a delayed false-stop of the NEXT pool.
# Observed for real 2026-07-31: a broadcast outlived its target and the pool started at
# 23:28:51 consumed it. The default path already refused; --all wrote unconditionally.
echo "Test 6b: --all refuses with no live pool"
make_hb
set +e; out="$(req --all 2>&1)"; rc=$?; set -e
if [[ $rc -eq 3 && ! -e "$stopfile" ]]; then
  ok "--all with zero live pools refuses (exit 3) and writes NOTHING"
else
  fail_msg "--all wrote a landmine sentinel with no pool live (rc=$rc, exists=$([[ -e $stopfile ]] && echo yes || echo no))"
fi

# ── Test 7: --after N writes the countdown ───────────────────────────────────
echo "Test 7: --after N countdown content"
make_hb "$RUN_A"
req --after 3 >/dev/null 2>&1
if [[ "$(cat "${stopfile}.${RUN_A}" 2>/dev/null)" == "3" ]]; then
  ok "--after 3 wrote '3' into the targeted sentinel"
else
  fail_msg "--after did not write the countdown"
fi
rm -f -- "${stopfile}.${RUN_A}"
set +e; req --after 0 >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 2 ]]; then ok "--after 0 rejected"; else fail_msg "--after 0 should exit 2, got $rc"; fi

# ── Test 8: the non-pool daemon is never a target ────────────────────────────
echo "Test 8: discovery-producer excluded"
make_hb "$RUN_A"          # stub always also emits discovery-producer
out="$(req --list 2>&1)"
if [[ "$out" != *"discovery-producer"* ]]; then
  ok "discovery-producer not offered as a stop target"
else
  fail_msg "discovery-producer listed — it never reads the sentinel, offering it is a lie"
fi

echo
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
