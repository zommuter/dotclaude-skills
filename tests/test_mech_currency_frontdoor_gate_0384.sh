#!/usr/bin/env bash
# fails-against: 1f402c1 (relay/SKILL.md step 0b runs only mech-preflight.sh preflight and never
#   the sibling currency check — verified red 2026-08-21 against `git show HEAD:relay/SKILL.md`:
#   2 assertions fail, "step 0b never invokes mech-currency.sh --currency" and "step 0b does not
#   make STALE a launch REFUSAL"; all 9 behavioural assertions stay green, since the checker
#   itself was already correct — it was the wiring that was missing)
# NO `# roadmap:` HEADER ON PURPOSE — this is a DEFECT-FIX test (id:0384), not the spec for an
# open ROADMAP item. The defect was a front door that ran `mech-preflight.sh preflight` and never
# the sibling `mech-currency.sh --currency`, so a proxy whose in-memory ALLOWED_RELAY_SCRIPTS
# predated the source passed step 0b, refused every newly-allowlisted hop, fell open to the real
# API and 404'd on model:"bash". Defect-fix tests carry no roadmap id, so their failures ALWAYS
# count — expected-red semantics must never apply here.
#
# WHAT THIS LOCKS. Step 0b's refusal is only as good as the signal it branches on, so this
# exercises the REAL checker against a REAL stale-vs-current state file and asserts that the two
# cases are actually distinguishable by the mechanism the prose now keys on:
#   * exit status                (1 = STALE, 0 = current)
#   * the word STALE on STDERR   (with both digests, so the operator can act)
#   * STDOUT stays EMPTY on STALE — the trap step 0b explicitly warns about: a caller that
#     watches stdout for trouble sees silence and reads it as calm.
# Plus the wiring assertion the defect itself was: step 0b must actually INVOKE the check and
# state the refusal. Behaviour first, wiring second; neither alone is the fix.
#
# Hermetic: mktemp -d, a fixture proxy source and a fixture state file, no network, no ~/.claude,
# and the RUNNING proxy on this host is never contacted (MECH_PROXY_SRC/MECH_PROXY_STATE are both
# overridden, so nothing here reads or writes the operator's real state file).

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$SRC_DIR/relay/scripts/mech-currency.sh"
SKILL="$SRC_DIR/relay/SKILL.md"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -f "$CHECK" ]] || { echo "FAIL: no mech-currency.sh at $CHECK"; exit 1; }
[[ -f "$SKILL" ]] || { echo "FAIL: no relay/SKILL.md at $SKILL"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── fixture proxy source: one module exposing allowlist_digest(), same seam the real one has ──
CURRENT_DIGEST="1111111111111111111111111111111111111111111111111111111111111111"
STALE_DIGEST="2222222222222222222222222222222222222222222222222222222222222222"
PROXY_SRC="$TMP/mechanical-proxy.py"
cat >"$PROXY_SRC" <<PY
ALLOWED_RELAY_SCRIPTS = frozenset({"ledger-slice.sh"})
def allowlist_digest():
    return "$CURRENT_DIGEST"
PY

STATE="$TMP/mech-proxy-state.json"
run_check() {  # -> writes $TMP/out, $TMP/err; echoes exit code
  MECH_PROXY_SRC="$PROXY_SRC" MECH_PROXY_STATE="$STATE" \
    bash "$CHECK" --currency >"$TMP/out" 2>"$TMP/err"
  echo "$?"
}
write_state() {  # write_state <pid> <digest>
  printf '{"pid": %s, "started_at": "2026-08-20T08:42:49", "allowlist_digest": "%s"}\n' \
    "$1" "$2" >"$STATE"
}

# A pid that is certainly NOT alive (for the dead-proxy case).
DEAD_PID="$(python3 -c '
import os
p = 30000
while p < 400000:
    if not os.path.isdir("/proc/%d" % p):
        print(p); break
    p += 1
')"
[[ -n "$DEAD_PID" ]] || fail "could not find a non-existent pid for the dead-proxy case"

# ── (1) CURRENT: live pid + matching digest → exit 0, "current" on stdout, no STALE ───────────
write_state "$$" "$CURRENT_DIGEST"
rc="$(run_check)"
if [[ "$rc" == 0 ]] && grep -qi "current" "$TMP/out" && ! grep -q "STALE" "$TMP/err"; then
  pass "a live proxy holding the on-disk allowlist reports current (exit 0)"
else
  fail "current case: expected exit 0 + 'current' on stdout, got exit $rc; out=[$(cat "$TMP/out")] err=[$(cat "$TMP/err")]"
fi

# ── (2) THE INCIDENT: live pid, digest predating source → STALE, distinguishable ──────────────
# This is run relay-20260821-164439-2279 in miniature: the process is alive and its socket is
# fine (which is all preflight ever probes), but it bound a different allowlist at import.
write_state "$$" "$STALE_DIGEST"
rc="$(run_check)"
if [[ "$rc" == 1 ]]; then
  pass "a live-but-stale proxy exits 1 (distinguishable from the current case by exit status)"
else
  fail "stale case: expected exit 1, got $rc — step 0b's refusal cannot fire"
fi
if grep -q "STALE" "$TMP/err"; then
  pass "the stale verdict says STALE on stderr"
else
  fail "stale case: stderr carries no STALE verdict; err=[$(cat "$TMP/err")]"
fi
if grep -q "$STALE_DIGEST" "$TMP/err" && grep -q "$CURRENT_DIGEST" "$TMP/err"; then
  pass "the stale report names BOTH digests (in-process and on-disk)"
else
  fail "stale case: stderr must name both digests so the operator can act; err=[$(cat "$TMP/err")]"
fi
if grep -qiE "restart|mechanical-proxy" "$TMP/err"; then
  pass "the stale report names the remedy (restart mechanical-proxy.py)"
else
  fail "stale case: stderr names no remedy; err=[$(cat "$TMP/err")]"
fi
if [[ ! -s "$TMP/out" ]]; then
  pass "STALE leaves STDOUT EMPTY — a stdout-only caller sees silence, which is why step 0b keys on the exit status / verdict"
else
  fail "stale case: stdout was expected empty, got [$(cat "$TMP/out")]"
fi

# ── (3) FAIL-CLOSED on the unknown: no state file at all is STALE, never health ───────────────
rm -- "$STATE"
rc="$(run_check)"
if [[ "$rc" == 1 ]] && grep -q "STALE" "$TMP/err"; then
  pass "an ABSENT state file is STALE (the pre-feature process this catches wrote none)"
else
  fail "absent-state case: expected exit 1 + STALE, got exit $rc; err=[$(cat "$TMP/err")]"
fi

# ── (4) a state file outliving its process certifies nothing ──────────────────────────────────
if [[ -n "$DEAD_PID" ]]; then
  write_state "$DEAD_PID" "$CURRENT_DIGEST"
  rc="$(run_check)"
  if [[ "$rc" == 1 ]] && grep -q "STALE" "$TMP/err"; then
    pass "a matching digest whose pid is DEAD is still STALE"
  else
    fail "dead-pid case: expected exit 1 + STALE, got exit $rc; err=[$(cat "$TMP/err")]"
  fi
fi

# ── (5) a malformed state file is STALE, not a crash ──────────────────────────────────────────
printf 'not json at all\n' >"$STATE"
rc="$(run_check)"
if [[ "$rc" == 1 ]] && grep -q "STALE" "$TMP/err"; then
  pass "an unreadable/malformed state file is STALE"
else
  fail "malformed-state case: expected exit 1 + STALE, got exit $rc; err=[$(cat "$TMP/err")]"
fi

# ── (6) THE DEFECT ITSELF: step 0b must INVOKE the check and REFUSE on STALE ──────────────────
# Behaviour above is worthless if nothing calls it — that WAS the bug (the id:4347 shape: a
# correct detector whose only invocation is someone remembering it). Scope the search to step
# 0b's own span so a mention elsewhere in SKILL.md cannot satisfy this.
step0b="$(awk '/^0b\. \*\*Mechanical-tier preflight/{f=1} f&&/^1\. /{f=0} f' "$SKILL")"
if [[ -z "$step0b" ]]; then
  fail "could not locate step 0b in $SKILL — the front-door preflight step was renamed or removed"
else
  if grep -q -- "mech-currency.sh --currency" <<<"$step0b"; then
    pass "step 0b invokes mech-currency.sh --currency"
  else
    fail "step 0b never invokes mech-currency.sh --currency — a stale proxy still passes the front door (id:0384)"
  fi
  if grep -qE "REFUSAL|refusal" <<<"$step0b" && grep -qi "STALE" <<<"$step0b"; then
    pass "step 0b treats a STALE verdict as a launch refusal"
  else
    fail "step 0b does not make STALE a launch REFUSAL — it must match the mode-b abort posture (id:0384)"
  fi
  if grep -qi "restart" <<<"$step0b" && grep -q "mechanical-proxy.py" <<<"$step0b"; then
    pass "step 0b names the remedy (restart mechanical-proxy.py)"
  else
    fail "step 0b names no remedy for a STALE proxy"
  fi
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails assertion(s)"
  exit 1
fi
echo "OK: mech-currency front-door gate (id:0384)"
