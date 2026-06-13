#!/usr/bin/env bash
# tests/test_fable_standin_marker.sh
# Static-grep checks for the fable-standin marker (id:0420).
# No roadmap item — defect-fix/feature test; failures always count.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---- relay-loop.js checks ----

JS="$ROOT/fables-turn/scripts/relay-loop.js"

# 1. fable-standin token appears in the JS source
grep -q 'fable-standin' "$JS" \
  && ok "relay-loop.js contains fable-standin token" \
  || fail "relay-loop.js missing fable-standin token"

# 2. fable-standin is in the non-execute (review/handoff) label branch
# The standInSuffix line must reference STRONG_MODEL being claude-opus and verdict !== execute
grep -q "unit\.verdict !== 'execute'" "$JS" \
  && ok "relay-loop.js guards fable-standin to non-execute units" \
  || fail "relay-loop.js missing non-execute guard for fable-standin"

# 3. execute label does NOT contain fable-standin
grep "executor (sonnet, relay-loop)" "$JS" | grep -qv 'fable-standin' \
  && ok "execute label does not contain fable-standin" \
  || fail "execute label unexpectedly contains fable-standin"

# 4. fable-standin is conditional on STRONG_MODEL === claude-opus-4-8
grep -q "claude-opus-4-8.*fable-standin\|fable-standin.*claude-opus-4-8\|STRONG_MODEL.*claude-opus-4-8" "$JS" \
  && ok "relay-loop.js gates fable-standin on claude-opus-4-8 model" \
  || fail "relay-loop.js fable-standin not gated on model ID"

# 5. STRONG_MODEL variable is still used in the reviewer label template
grep -q 'STRONG_MODEL.*relay-loop\|STRONG_MODEL.*fable-standin' "$JS" \
  && ok "reviewer label template still references STRONG_MODEL" \
  || fail "reviewer label template lost STRONG_MODEL reference"

# ---- ckpt-tag.sh checks ----

CKPT="$ROOT/fables-turn/scripts/ckpt-tag.sh"

# 6. ckpt-tag.sh carries $label into the tag message
grep -q 'tag -a.*-m.*label\|-m.*summary.*label\|-m.*\$summary' "$CKPT" \
  && ok "ckpt-tag.sh git tag command references label for message" \
  || fail "ckpt-tag.sh git tag command does not include label in message"

# 7. The tag message block in ckpt-tag.sh contains $label (the heredoc/multiline form)
grep -q '^\$label' "$CKPT" \
  && ok "ckpt-tag.sh tag message block includes \$label line" \
  || fail "ckpt-tag.sh tag message block missing \$label line"

# 8. ckpt-tag.sh still writes label into RELAY_LOG.md heading (unchanged)
grep -q 'stamp_human.*label\|label.*stamp_human' "$CKPT" \
  && ok "ckpt-tag.sh still embeds label in RELAY_LOG.md heading" \
  || fail "ckpt-tag.sh lost label in RELAY_LOG.md heading"

# ---- standInRank scheduler tiebreaker checks (user directive 2026-06-13) ----

# 9. standInRank function exists
grep -q 'function standInRank' "$JS" \
  && ok "relay-loop.js defines standInRank tiebreaker" \
  || fail "relay-loop.js missing standInRank function"

# 10. Fable-session gate (SESSION_IS_FABLE) exists and keys on the real Fable model
grep -q "SESSION_IS_FABLE = STRONG_MODEL === 'claude-fable-5'" "$JS" \
  && ok "relay-loop.js gates standin re-review on a real-Fable session" \
  || fail "relay-loop.js missing SESSION_IS_FABLE gate"

# 11. review-on-Fable ranks standin FIRST (return 0 for standin, 1 otherwise)
grep -q "verdict === 'review' && SESSION_IS_FABLE) return u.standin ? 0 : 1" "$JS" \
  && ok "standInRank: review on Fable session sorts standin first" \
  || fail "standInRank missing review-first-on-Fable branch"

# 12. default branch prefers Fable-vetted (non-standin) first
grep -q 'return u.standin ? 1 : 0' "$JS" \
  && ok "standInRank: execute/handoff (and non-Fable) prefer non-standin first" \
  || fail "standInRank missing non-standin-first default branch"

# 13. both sort sites apply the standInRank tiebreaker
[[ $(grep -c 'standInRank(a) - standInRank(b)' "$JS") -ge 2 ]] \
  && ok "both scheduler sort sites apply standInRank" \
  || fail "standInRank not wired into both sort sites"

# 14. DISCOVER_SCHEMA declares the standin property and classifier prompt detects it
grep -q 'standin: { type: .boolean. }' "$JS" \
  && grep -q 'standin per repo' "$JS" \
  && ok "discovery schema + classifier prompt cover standin" \
  || fail "discovery schema or classifier prompt missing standin"

# 15. tiebreaker is never a filter (slight-preference invariant): standInRank must not
#     appear inside a .filter predicate
! grep -q 'filter.*standInRank\|standInRank.*filter' "$JS" \
  && ok "standInRank used only as sort tiebreaker, never a filter" \
  || fail "standInRank leaked into a filter (would exclude standin repos)"

# ---- Fable-return re-review elevation (id:9821) ----

# 16. elevation is gated on a real-Fable, non-fable-down session
grep -q 'if (SESSION_IS_FABLE && !FABLE_DOWN) {' "$JS" \
  && ok "standin→review elevation gated on Fable session, not fable-down" \
  || fail "standin elevation missing SESSION_IS_FABLE && !FABLE_DOWN gate"

# 17. elevation promotes execute/idle standin repos to review
grep -q "u.standin && (u.verdict === 'execute' || u.verdict === 'idle')" "$JS" \
  && grep -q "u.verdict = 'review'" "$JS" \
  && ok "standin elevation promotes execute/idle standin repos to review" \
  || fail "standin elevation does not promote execute/idle repos to review"

# ---- summary ----
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
