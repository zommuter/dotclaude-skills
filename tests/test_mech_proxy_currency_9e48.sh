#!/usr/bin/env bash
# roadmap:9e48 — detect a RUNNING mechanical-proxy whose in-memory allowlist predates the source.
#
# RED SPEC authored at handoff 2026-08-11. The incident: the live proxy (pid 1131, started 13:32)
# predated commit 7437880 (19:22) which added provision-worktree.sh to ALLOWED_RELAY_SCRIPTS.
# Python binds the frozenset at import and the module has no reload path, so every provision hop
# was refused → fail-open passthrough → 404 on model="bash". 20 refusals across 4 runs, zero
# successes, and EVERY existing guard reported healthy throughout:
#   - test_mech_fence_allowlist_completeness_5bbb.sh cross-checks fences vs allowlist — but reads SOURCE
#   - probe-mech-proxy.sh:43-49 is a pure TCP connect (no HTTP, no model name, no command)
#   - mech-preflight.sh maps a mode to a token
# None can observe the live process's in-memory state. This spec closes that.
#
# FAIL-CLOSED ON THE UNKNOWN: a stale proxy predates the state-file feature itself, so a MISSING
# state file must read as STALE, never as healthy. That is the whole point — the very process this
# detects would not have written one.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROXY="$SRC_DIR/relay/scripts/mechanical-proxy.py"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$PROXY" ]] || fail "mechanical-proxy.py not found at $PROXY"

# The currency checker: a dedicated script, or a documented mode of mech-preflight.sh.
CHECK=""
for cand in "$SRC_DIR/relay/scripts/mech-currency.sh" "$SRC_DIR/relay/scripts/mech-preflight.sh"; do
  [[ -x "$cand" ]] && grep -q "allowlist_digest" "$cand" 2>/dev/null && { CHECK="$cand"; break; }
done
[[ -n "$CHECK" ]] \
  || fail "no currency checker found — expected mech-currency.sh (or a mech-preflight.sh mode) that reads allowlist_digest"
pass "a currency checker exists: $(basename "$CHECK")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/mech-proxy-state.json"

# ── (1) the proxy WRITES a state file at startup ─────────────────────────────────────────
grep -q "MECH_PROXY_STATE" "$PROXY" \
  || fail "mechanical-proxy.py has no MECH_PROXY_STATE path — it cannot publish what it loaded"
grep -q "allowlist_digest" "$PROXY" \
  || fail "mechanical-proxy.py never computes an allowlist_digest — staleness stays unobservable"
pass "mechanical-proxy.py publishes a state file with an allowlist digest"

# ── (2) the digest is a stable function of the SORTED allowlist ───────────────────────────
# Two independent computations from the same source must agree, or the comparison is noise.
d1="$(MECH_PROXY_STATE="$STATE" python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('mp', '$PROXY')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.stdout.write(m.allowlist_digest())
" 2>/dev/null)" || fail "mechanical-proxy.py exposes no callable allowlist_digest() for the checker to reuse"
d2="$(MECH_PROXY_STATE="$STATE" python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('mp', '$PROXY')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.stdout.write(m.allowlist_digest())
" 2>/dev/null)"
[[ -n "$d1" && "$d1" == "$d2" ]] || fail "allowlist_digest() is not stable across invocations (got '$d1' vs '$d2')"
pass "allowlist_digest() is stable and reusable by the checker"

# ── (3) MISSING state file ⇒ STALE (the fail-closed-on-unknown case) ──────────────────────
rc=0
MECH_PROXY_STATE="$TMP/does-not-exist.json" "$CHECK" --currency >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] \
  || fail "a MISSING state file reported healthy — the exact process this detects would not have written one"
pass "a missing state file reports STALE (fail-closed on the unknown)"

# ── (4) MISMATCHED digest ⇒ STALE ─────────────────────────────────────────────────────────
printf '{"pid": %s, "started_at": "2026-08-11T13:32:59", "allowlist_digest": "deadbeefdeadbeef"}\n' "$$" > "$STATE"
rc=0
MECH_PROXY_STATE="$STATE" "$CHECK" --currency >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "a state file whose digest differs from source reported healthy — this IS the incident"
pass "a digest mismatch reports STALE"

# ── (5) MATCHING digest + live pid ⇒ current ──────────────────────────────────────────────
printf '{"pid": %s, "started_at": "2026-08-11T23:30:00", "allowlist_digest": "%s"}\n' "$$" "$d1" > "$STATE"
MECH_PROXY_STATE="$STATE" "$CHECK" --currency >/dev/null 2>&1 \
  || fail "a matching digest with a live pid reported STALE — false positives make the check ignorable"
pass "a matching digest with a live pid reports current"

# ── (6) DEAD pid ⇒ STALE (a state file outliving its process must not certify anything) ───
dead=999999
while kill -0 "$dead" 2>/dev/null; do dead=$((dead-1)); done
printf '{"pid": %s, "started_at": "2026-08-11T23:30:00", "allowlist_digest": "%s"}\n' "$dead" "$d1" > "$STATE"
rc=0
MECH_PROXY_STATE="$STATE" "$CHECK" --currency >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "a state file naming a DEAD pid reported healthy — a stale file would certify a proxy that is not running"
pass "a dead pid reports STALE"

# ── (7) the report must NAME the problem, not just exit non-zero ──────────────────────────
printf '{"pid": %s, "started_at": "x", "allowlist_digest": "deadbeefdeadbeef"}\n' "$$" > "$STATE"
msg="$(MECH_PROXY_STATE="$STATE" "$CHECK" --currency 2>&1 || true)"
grep -qi "stale" <<<"$msg" || fail "the mismatch report never says STALE (got: '$msg') — a bare exit code is not a loud failure"
pass "the report names the condition in words"

echo "ALL PASS: a stale proxy allowlist is detectable (9e48)"
