#!/usr/bin/env bash
# roadmap:6217
# RED SPEC for id:6217 — ONE definition of isDryRound/isBlockedRound + the workCreated
# predicate, and the "keep the two in sync" admission DELETED rather than left lying.
#
# Verified state at authoring (2026-07-31):
#   relay/scripts/drain.mjs:91,102        export function isBlockedRound / isDryRound
#   relay/scripts/relay-loop.js:1068,1071 byte-identical inline copies
#   relay/scripts/drain.mjs:21            "keep the two in sync" — for THESE functions
#   relay/scripts/relay-loop.js:1067      "(keep byte-equivalent)" — the mirror admission
#   relay/scripts/drain.mjs:157           a SEPARATE, similarly-worded sync comment belonging
#                                         to classifyRepeatHandbacks — NOT this item's target.
# TODO.md:57 cited :157 as the isDryRound admission; that is a mis-cite, corrected in the
# ROADMAP entry. Assertion 5 below PINS :157 so a careless grep-and-delete cannot remove it.
#
# ⚠ JUDGEMENT CALL flagged to REVIEW_ME (id:6217): relay-loop.js is Workflow-sandbox JS and
# CANNOT `import` — that is precisely why the inline copies exist. "Exactly one definition"
# across drain.mjs AND relay-loop.js therefore needs a mechanism (generation step, or the loop
# ceasing to need its own copy). This spec asserts the contract AS RATIFIED; if the executor
# concludes it is unreachable under the sandbox constraint, HAND BACK rather than weaken the
# test.
#
# SCOPE, do not widen: drain-driver.mjs is FROZEN (ROADMAP.md:32, superseded 2026-07-24;
# go-forward is the id:7488 Workflow re-wire), so its `workCreated: undefined -> 0` gap is
# MOOT-BY-RETIREMENT and must NOT be "fixed" by importing anything into it (assertion 6).
#
# TRIANGULATION (id:108e): seven assertions over four concerns (single definition ×2 functions,
# comment deleted-not-left-lying, a NEGATIVE assertion that an out-of-scope comment SURVIVES,
# frozen-driver untouched) — a blanket sweep fails assertion 5, a cosmetic comment edit fails
# assertions 1-2.
#
# RED until the extraction lands. roadmap:6217 unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
MJS="$ROOT/relay/scripts/drain.mjs"
DRV="$ROOT/relay/scripts/drain-driver.mjs"
[[ -f "$JS"  ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -f "$MJS" ]] || { echo "FAIL: drain.mjs not found at $MJS"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# deps: bash/grep/sed/node only — no bc, no jq (keeps the suite's zero-dependency contract).
defs_of() { grep -h "function $1(r)" "$JS" "$MJS" | wc -l | tr -d ' '; }

# 1-2. Exactly ONE definition of each predicate across the two files.
for fn in isDryRound isBlockedRound; do
  n="$(defs_of "$fn")"
  (( n == 1 )) \
    || fail "($fn) $n definitions of 'function $fn(r)' across relay-loop.js + drain.mjs — the meeting's contract is exactly one (id:6217). Sites: $(grep -rn "function $fn(r)" "$JS" "$MJS" | tr '\n' ' ')"
  pass "($fn) exactly one definition remains"
done

# 3. The extracted definition is a DELIBERATE, findable block — not an accidental survivor.
#    Require the id:6217 marker at the single-source site so the next reader knows why.
grep -q '6217' "$JS" \
  || fail "(3) relay-loop.js does not cite id:6217 at the single-source predicate block — the extraction must be marked, not incidental (id:6217)"
pass "(3) the single-source block is marked with id:6217"

# 4. Both isDryRound/isBlockedRound "keep in sync" admissions are DELETED (or rewritten to
#    state the new single-source relationship), not left lying.
if grep -q 'keep byte-equivalent' "$JS"; then
  fail "(4) relay-loop.js:1067's '(keep byte-equivalent)' admission still stands — it must be deleted or rewritten once there is one definition (id:6217)"
fi
if grep -q 'keep the two in sync' < <(sed -n '1,140p' "$MJS") ; then
  fail "(4) drain.mjs's isDryRound-scoped 'keep the two in sync' admission (near :21) still stands (id:6217)"
fi
pass "(4) both isDryRound sync admissions are gone"

# 5. NEGATIVE assertion — drain.mjs's classifyRepeatHandbacks sync comment is a DIFFERENT
#    comment for a DIFFERENT function and must SURVIVE. A blanket grep-and-delete fails here.
grep -q 'classifyRepeatHandbacks' "$MJS" \
  || fail "(5) classifyRepeatHandbacks vanished from drain.mjs — this item's scope is isDryRound/isBlockedRound/workCreated only (id:6217)"
grep -q 'keep the two in sync' < <(sed -n '141,200p' "$MJS") \
  || fail "(5) drain.mjs's classifyRepeatHandbacks 'keep the two in sync' comment was deleted — it belongs to a DIFFERENT function and is out of scope; TODO.md:57 mis-cited it as the isDryRound admission (id:6217)"
pass "(5) the classifyRepeatHandbacks sync comment survives (correctly out of scope)"

# 6. drain-driver.mjs is FROZEN — it must not grow an import of the shared predicate.
if [[ -f "$DRV" ]]; then
  if grep -Eq '^import .*(isDryRound|isBlockedRound|workCreated)' "$DRV"; then
    fail "(6) drain-driver.mjs grew an import of the shared predicate — that driver is FROZEN (ROADMAP.md:32); the drain-path gap is MOOT-BY-RETIREMENT, not to be fixed (id:6217)"
  fi
  pass "(6) the frozen drain-driver.mjs was left alone"
else
  pass "(6) drain-driver.mjs absent — nothing to guard"
fi

# 7. The moot-by-retirement decision is RECORDED in-source, not only in the roadmap.
grep -q '7488' "$JS" \
  || fail "(7) relay-loop.js does not cite id:7488 — the drain-path gap being MOOT-BY-RETIREMENT must be recorded at the extraction site (id:6217)"
pass "(7) the moot-by-retirement rationale cites id:7488 in-source"

# 8. Both files still parse; relay-loop.js still lints clean.
node --check "$JS"  >/dev/null 2>&1 || fail "(8) node --check failed on relay-loop.js after the 6217 edit"
node --check "$MJS" >/dev/null 2>&1 || fail "(8) node --check failed on drain.mjs after the 6217 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(8) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(8) relay-loop.js has a template-literal violation after the 6217 edit:
$out"
fi
pass "(8) both files parse and relay-loop.js lints clean"

echo "PASS test_dryround_single_definition_6217"
