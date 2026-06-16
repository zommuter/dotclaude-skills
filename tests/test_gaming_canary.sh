#!/usr/bin/env bash
# roadmap:414a — Tier B model canary harness PLUMBING guard.
#
# The Tier B harness itself (tests/gaming-canary/run.sh) spawns a real review agent
# and so is NOT in the default sweep (it costs tokens; run via `make gaming-canary`).
# This Tier A test is token-free: it drives run.sh with STUB agents (CANARY_AGENT) to
# pin the harness contract — FLAG fixtures require a non-empty gaming_flags reply,
# EMPTY (negative-control) fixtures require an empty reply, the claude envelope is
# unwrapped, and a no-agent run SKIPs rather than false-passing. It also pins the
# fixtures, README, and the `make gaming-canary` target exist.
#
# This is a GREEN regression-guard (handoff C3 D1): the harness is freshly built and
# this test passes on arrival. It freezes the harness's verdict CONTRACT, not model
# judgment — the model's actual detection is exercised on-demand by `make gaming-canary`.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$SRC_DIR/tests/gaming-canary"
RUN="$DIR/run.sh"

pass=0 fail=0
ok()   { echo "PASS: $*"; (( ++pass )); }
bad()  { echo "FAIL: $*"; (( ++fail )); }

# ── Structure ────────────────────────────────────────────────────────────────
[[ -x "$RUN" ]] && ok "run.sh exists and is executable" || bad "run.sh missing/non-exec at $RUN"

for fx in resurrection-rewrite fixture-special-casing negative-control-input-only; do
  [[ -f "$DIR/$fx/fixture.md" ]] && ok "fixture $fx/fixture.md present" || bad "fixture $fx/fixture.md MISSING"
  [[ -f "$DIR/$fx/expected"   ]] && ok "fixture $fx/expected present"   || bad "fixture $fx/expected MISSING"
done

# Exactly the two positive fixtures expect FLAG; the control expects EMPTY.
grep -qx FLAG  "$DIR/resurrection-rewrite/expected"            && ok "resurrection-rewrite expects FLAG"        || bad "resurrection-rewrite expected != FLAG"
grep -qx FLAG  "$DIR/fixture-special-casing/expected"          && ok "fixture-special-casing expects FLAG"      || bad "fixture-special-casing expected != FLAG"
grep -qx EMPTY "$DIR/negative-control-input-only/expected"     && ok "negative-control expects EMPTY"           || bad "negative-control expected != EMPTY"

# At least one negative control exists (spec requirement (c)).
ctrl=0
for d in "$DIR"/*/; do grep -qx EMPTY "$d/expected" 2>/dev/null && ctrl=1; done
(( ctrl == 1 )) && ok "at least one negative control (EMPTY) fixture exists" || bad "no negative control fixture"

# Each fixture diff stays minimal (spec: ≤20 lines of diff). Count lines inside the
# diff fences of fixture.md.
for fx in resurrection-rewrite fixture-special-casing negative-control-input-only; do
  difflines="$(awk '/^```diff$/{f=1;next} /^```$/{f=0} f' "$DIR/$fx/fixture.md" | wc -l)"
  (( difflines <= 20 )) && ok "fixture $fx diff is minimal ($difflines lines)" || bad "fixture $fx diff too large ($difflines > 20)"
done

# Makefile target + help + phony.
grep -qE '^gaming-canary:' "$SRC_DIR/Makefile"                  && ok "Makefile has gaming-canary target"        || bad "Makefile missing gaming-canary target"
grep -q 'gaming-canary/run.sh' "$SRC_DIR/Makefile"             && ok "gaming-canary target invokes run.sh"      || bad "gaming-canary target does not invoke run.sh"

# run.sh excluded from the default sweep: not named test_*.sh and lives in a subdir.
case "$(basename "$RUN")" in test_*) bad "run.sh is named test_* (would join default sweep)";; *) ok "run.sh not in default sweep (subdir, non-test_* name)";; esac

# ── Behavioural: drive the harness with STUB agents (token-free) ──────────────

# 1) FLAG fixture + always-flagging stub → PASS.
out="$(CANARY_AGENT='echo "{\"gaming_flags\":[\"resurrection\"]}"' bash "$RUN" resurrection-rewrite 2>&1)"
rc=$?
{ [[ $rc -eq 0 ]] && grep -q 'PASS   resurrection-rewrite' <<<"$out"; } \
  && ok "FLAG fixture passes when agent returns a non-empty gaming_flags" \
  || bad "FLAG-path failed (rc=$rc): $out"

# 2) FLAG fixture + empty-flags stub → harness must FAIL (the detector missed it).
out="$(CANARY_AGENT='echo "{\"gaming_flags\":[]}"' bash "$RUN" resurrection-rewrite 2>&1)"
rc=$?
{ [[ $rc -ne 0 ]] && grep -q 'FAIL   resurrection-rewrite' <<<"$out"; } \
  && ok "FLAG fixture fails when agent returns empty gaming_flags (no false pass)" \
  || bad "empty-on-FLAG should fail (rc=$rc): $out"

# 3) Negative control + empty-flags stub → PASS (specificity).
out="$(CANARY_AGENT='echo "{\"gaming_flags\":[]}"' bash "$RUN" negative-control-input-only 2>&1)"
rc=$?
{ [[ $rc -eq 0 ]] && grep -q 'PASS   negative-control-input-only' <<<"$out"; } \
  && ok "negative control passes when agent returns empty gaming_flags" \
  || bad "control-empty should pass (rc=$rc): $out"

# 4) Negative control + flagging stub → FAIL (false positive caught).
out="$(CANARY_AGENT='echo "{\"gaming_flags\":[\"bogus\"]}"' bash "$RUN" negative-control-input-only 2>&1)"
rc=$?
{ [[ $rc -ne 0 ]] && grep -q 'FAIL   negative-control-input-only' <<<"$out"; } \
  && ok "negative control fails when agent flags it (false positive caught)" \
  || bad "flag-on-control should fail (rc=$rc): $out"

# 5) Claude-CLI JSON envelope ({"result":"...json..."}) is unwrapped.
envelope='echo "{\"type\":\"result\",\"result\":\"{\\\"gaming_flags\\\":[\\\"x\\\"]}\"}"'
out="$(CANARY_AGENT="$envelope" bash "$RUN" resurrection-rewrite 2>&1)"
rc=$?
{ [[ $rc -eq 0 ]] && grep -q 'PASS   resurrection-rewrite' <<<"$out"; } \
  && ok "claude --output-format json envelope is unwrapped" \
  || bad "envelope unwrap failed (rc=$rc): $out"

# 6) Deterministic: identical stub input → identical verdict twice (not flaky).
a="$(CANARY_AGENT='echo "{\"gaming_flags\":[\"r\"]}"' bash "$RUN" resurrection-rewrite 2>&1 | grep -E '^(PASS|FAIL)')"
b="$(CANARY_AGENT='echo "{\"gaming_flags\":[\"r\"]}"' bash "$RUN" resurrection-rewrite 2>&1 | grep -E '^(PASS|FAIL)')"
[[ "$a" == "$b" && -n "$a" ]] && ok "harness is deterministic on identical input" || bad "non-deterministic verdict: '$a' vs '$b'"

# 7) No agent available → SKIP, never a silent pass. Build a PATH with the tools
# run.sh needs but NO `claude` binary, so `command -v claude` fails.
nobin="$(mktemp -d)"
for t in bash sh python3 cat tr grep sed awk basename dirname mktemp wc env head; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$nobin/$t" 2>/dev/null || true
done
out="$(env -i HOME="$HOME" PATH="$nobin" CANARY_AGENT= bash "$RUN" resurrection-rewrite 2>&1)"
grep -q 'SKIP   resurrection-rewrite' <<<"$out" \
  && ok "no-agent run SKIPs (no false pass)" \
  || bad "no-agent should SKIP: $out"
rm -rf "$nobin"

# 8) Unparseable agent reply → FAIL, not pass.
out="$(CANARY_AGENT='echo "not json at all"' bash "$RUN" resurrection-rewrite 2>&1)"
rc=$?
{ [[ $rc -ne 0 ]] && grep -q 'FAIL   resurrection-rewrite' <<<"$out"; } \
  && ok "unparseable reply fails (no parseable gaming_flags)" \
  || bad "unparseable reply should fail (rc=$rc): $out"

echo
echo "test_gaming_canary: $pass passed, $fail failed"
(( fail == 0 ))
