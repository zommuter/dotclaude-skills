#!/usr/bin/env bash
# roadmap:bc2b — suppression must DEMOTE the verdict, not DROP the unit.
#
# THE DEFECT, observed live on loderite (run relay-20260820-180056-4594):
# `classify-verdict.sh` is a strict elif cascade — blocked → review(chain-end) → execute →
# review → hard → handoff → human → mechanical → idle — so any `actionable_routine > 0` PINS
# the repo at `execute` (rank 1). Both anti-spin mechanisms are SUBSTITUTIVE: id:1432 no-work
# suppression (relay-loop.js:1235, "not re-dispatching THIS VERDICT until work_sig changes")
# and the id:365b >3x circuit breaker (:1196) DROP the unit and park the repo in Blocked. Net
# effect: the repo is simultaneously pinned to `execute` AND has `execute` suppressed, so it
# can reach NOTHING. loderite had actionable_routine_ids: ['57d1'] — ONE item, whose child had
# died on prompt size — while 9 promotable items sat unreachable behind it. They moved only
# because a human ran handoff by hand.
#
# THE FIX under test: on 1432/365b suppression, re-run the classifier with that verdict CLASS
# EXCLUDED and dispatch the next-ranked class; if none applies, idle exactly as today. No
# threshold heuristic, no new state (suppression state already persists per-run). The precedent
# to mirror is the ratified `chain_ended ∧ substantive_unaudited` branch at rank 2 (id:8123),
# which exists because review was starving "behind open [ROUTINE] work — total structural
# starvation": identical shape, identical remedy.
#
# The exclusion must live in the classifier, which is a PURE stdin→stdout function and is
# therefore drivable directly here. relay-loop.js itself cannot be imported in this harness
# (id:2ec4), so the loop-side wiring is pinned by structural greps only — stated honestly, the
# same limit as tests/test_prompt_size_gate_4f9b.sh.
#
# EXPECTED-RED while roadmap:bc2b is unticked.
# Hermetic: no repo, no git, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -x "$CV" ]] || { echo "FAIL: classify-verdict.sh not found at $CV"; exit 1; }

# verdict_of <json> [extra args...]
verdict_of() {
  local json="$1"; shift
  "$CV" "$@" <<<"$json" 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("verdict","<<ERR>>"))' 2>/dev/null \
    || echo "<<ERR>>"
}

base='"repo":"loderite","is_finished":false,"hasRoutine":true,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":10'

# The loderite state: ONE actionable [ROUTINE] item pinning the repo, 9 promotable behind it.
LODERITE='{'"$base"',"roadmap_actionable_open":1,"actionable_routine_open":1,"unpromoted":{"promote":9,"surface":0}}'

# ── (A) BASELINE — unchanged behaviour with no exclusion. A change that alters this is a
#        regression, not a fix. ─────────────────────────────────────────────────────────────
v="$(verdict_of "$LODERITE")"
[[ "$v" == "execute" ]] \
  && ok "baseline: actionable_routine=1 classifies as execute (unchanged)" \
  || bad "id:bc2b: baseline broke — expected execute, got '$v'"

# ── (B) THE FIX — with `execute` suppressed, the repo must DEMOTE to the next-ranked class
#        (handoff, promote=9), NOT go idle and NOT stay pinned at execute. ──────────────────
v="$(verdict_of "$LODERITE" --exclude execute)"
case "$v" in
  handoff) ok "suppressed execute DEMOTES to handoff — the 9 promotable items become reachable" ;;
  execute) bad "id:bc2b: --exclude execute still returned execute — the exclusion is not honoured" ;;
  idle)    bad "id:bc2b: suppressed execute went IDLE — this IS the starvation bug (the repo can reach nothing)" ;;
  '<<ERR>>') bad "id:bc2b: classify-verdict.sh does not accept --exclude (no re-classify primitive exists)" ;;
  *)       bad "id:bc2b: suppressed execute gave '$v', expected handoff" ;;
esac

# ── (C) CASCADING exclusion — the mechanism must compose, not special-case `execute`. ───────
v="$(verdict_of '{'"$base"',"roadmap_actionable_open":1,"actionable_routine_open":1,"substantive_unaudited":true,"unpromoted":{"promote":0,"surface":0}}' --exclude execute)"
[[ "$v" == "review" ]] \
  && ok "suppressed execute demotes to review when unaudited commits exist" \
  || bad "id:bc2b: expected review after excluding execute (unaudited commits present), got '$v'"

v="$(verdict_of '{'"$base"',"roadmap_actionable_open":1,"actionable_routine_open":1,"open_hard_pool":3,"unpromoted":{"promote":0,"surface":0}}' --exclude execute)"
[[ "$v" == "hard" ]] \
  && ok "suppressed execute demotes to hard when [HARD] pool work exists" \
  || bad "id:bc2b: expected hard after excluding execute (open_hard_pool=3), got '$v'"

v="$(verdict_of "$LODERITE" --exclude execute,handoff)"
[[ "$v" == "idle" ]] \
  && ok "excluding execute AND handoff with nothing else actionable falls through to idle" \
  || bad "id:bc2b: expected idle after excluding execute,handoff (promote=9 only), got '$v'"

v="$(verdict_of '{'"$base"',"roadmap_actionable_open":1,"actionable_routine_open":1,"unpromoted":{"promote":0,"surface":4}}' --exclude execute)"
[[ "$v" == "human" ]] \
  && ok "suppressed execute demotes past handoff to human on a surface-only backlog" \
  || bad "id:bc2b: expected human after excluding execute (surface=4, promote=0), got '$v'"

# Suppressing a class the repo does not hold must change NOTHING.
v="$(verdict_of "$LODERITE" --exclude hard)"
[[ "$v" == "execute" ]] \
  && ok "excluding an unrelated class (hard) leaves execute untouched" \
  || bad "id:bc2b: excluding hard changed the verdict to '$v' — exclusion is not class-scoped"

# ── (D) EXCLUSION MAY ONLY DEMOTE. If it can promote, a suppressed low class could lift a repo
#        ABOVE the work it actually has — a worse failure than the starvation being fixed. ──
v="$(verdict_of '{'"$base"',"roadmap_actionable_open":0,"actionable_routine_open":0,"unpromoted":{"promote":0,"surface":0}}' --exclude idle)"
[[ "$v" == "idle" ]] \
  && ok "excluding idle on an empty repo stays idle — exclusion never manufactures work" \
  || bad "id:bc2b: excluding idle produced '$v' — exclusion PROMOTED a repo with no work"

# ── (E) BLOCKED is rank 0 and is NOT a dispatch class — it must never be excludable away,
#        or a dirty/diverged tree would be dispatched into. ──────────────────────────────────
v="$(verdict_of '{'"$base"',"dirty":true,"roadmap_actionable_open":1,"actionable_routine_open":1,"unpromoted":{"promote":9,"surface":0}}' --exclude blocked)"
[[ "$v" == "blocked" ]] \
  && ok "blocked (rank 0) is not excludable — a dirty tree still refuses dispatch" \
  || bad "id:bc2b: --exclude blocked yielded '$v' — the safety verdict was excluded away"

# ── (F) PURITY — the classifier must stay side-effect-free under --exclude. ─────────────────
if grep -qE '^\s*(git |rm |mv |touch |>>)' "$CV"; then
  bad "id:bc2b: classify-verdict.sh gained a side effect — it must remain a pure function"
else
  ok "classify-verdict.sh stays side-effect-free"
fi

# ── (G) WIRING (structural only — relay-loop.js cannot be imported here, id:2ec4). Both
#        suppression sites must RE-CLASSIFY with the class excluded instead of dropping. ────
if [[ -f "$JS" ]]; then
  # NOTE: a bare `grep -- --exclude` / `grep -i demot` would FALSE-PASS here — relay-loop.js
  # already carries the unrelated id:d530 per-run `--exclude <repo>` pool arg and the
  # --fable-down review→execute demote block. Both checks are therefore anchored to bc2b.
  grep -q 'bc2b' "$JS" \
    && ok "relay-loop.js carries the id:bc2b demotion marker" \
    || bad "id:bc2b: relay-loop.js has no id:bc2b marker — the suppression sites were never rewired"
  if grep -nE '(classify|verdict)[^\n]*--exclude|--exclude[^\n]*(classify|verdict)' "$JS" >/dev/null; then
    ok "relay-loop.js passes --exclude to the verdict classifier (not the id:d530 repo filter)"
  else
    bad "id:bc2b: no classifier --exclude call in relay-loop.js — id:1432/id:365b suppression still DROPS the unit"
  fi
else
  bad "relay-loop.js missing at $JS"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: suppression demotes the verdict instead of dropping the unit (id:bc2b)"
