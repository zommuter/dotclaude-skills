#!/usr/bin/env bash
# roadmap:4a76 — `drained` must distinguish FINISHED from HUMAN-BLOCKED.
#
# THE DEFECT, measured 2026-08-21: `classify-verdict.sh:235` emits `human` ONLY when
# `surface > 0` (a surface-only TODO backlog). A repo whose ENTIRE open backlog is human-lane
# but whose `surface == 0` falls through to `idle`; `control-board.sh:162` maps
# `idle → design-drained`, and `:237` computes waiting from ('needs-feedback','blocked') only —
# so it never appears under "Waiting on a human". Two repos, 31 open items between them, read
# as done:
#   helferli — 18 open, ALL [INPUT — …] (14 access / 4 meeting / 1 decision), zero poolable
#              → reported `design-drained`, "Waiting on a human: _(none)_".
#   csgebra  — 13 open; all 5 HARD/ROUTINE items carry gated-on: edges rooting in 940f
#              [INPUT — decision] → the same false-clean.
#
# THE FIX under test: UPSTREAM in classify-verdict.sh, NOT in the board. The board renders
# faithfully; fixing it there would leave `/relay human`'s scope and the pool's Skipped rollup
# still wrong. Emit `human` when roadmap_open > 0 AND every executable lane is zero AND >=1
# open item sits in a human lane ([INPUT — *], @manual). `human → needs-feedback` already
# lands in the right board section, so control-board.sh needs NO change.
#
# classify-verdict.sh is a pure stdin→stdout function and classify-repo.sh is a standalone
# host script, so BOTH halves are driven for real here — no import limitation applies to this
# item (unlike roadmap:b018 / bc2b / e68f, which must grep relay-loop.js).
#
# SHADOW-PARITY NOTE: classify-verdict.sh / gather-repo-state.sh are reimplemented by the
# relay-core Lean shadow binary. Bash stays authoritative, but parity goes RED until relay-core
# adopts this too — see [[classify-shadow-parity]]. That is expected and is NOT this test's job.
#
# EXPECTED-RED while roadmap:4a76 is unticked.
# Hermetic: mktemp -d fixture repo, git + python3 only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"
CR="$ROOT/relay/scripts/classify-repo.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -x "$CV" ]] || { echo "FAIL: classify-verdict.sh not found at $CV"; exit 1; }
[[ -x "$CR" ]] || { echo "FAIL: classify-repo.sh not found at $CR"; exit 1; }

verdict_of() { "$CV" <<<"$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("verdict","<<ERR>>"))'; }

# Every executable lane at zero; a surface-FREE unpromoted summary — this is the state that
# falls through to idle today.
drained='"repo":"helferli","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"open_mechanical":0,"surfaced_open":0,"top_intensive":"","roadmap_actionable_open":0,"actionable_routine_open":0,"unpromoted":{"promote":0,"surface":0}'

# ── (A) THE FIX — 18 open items, all human-lane, surface==0 ⇒ human, NOT idle. ──────────────
v="$(verdict_of '{'"$drained"',"roadmap_open":18,"open_human_lane":18}')"
case "$v" in
  human) ok "human-lane-only backlog (18 open, surface=0) classifies as human" ;;
  idle)  bad "id:4a76: 18 open human-lane items classified as IDLE — the repo reads as design-drained while 18 items wait on the owner" ;;
  *)     bad "id:4a76: expected human, got '$v'" ;;
esac

# The reason must NAME the human-lane fact, so /relay human and the board show WHY.
reason="$("$CV" <<<'{'"$drained"',"roadmap_open":18,"open_human_lane":18}' | python3 -c 'import sys,json;print(json.load(sys.stdin).get("reason",""))')"
grep -qiE 'human[- ]lane|INPUT|waiting on a human|owner' <<<"$reason" \
  && ok "reason names the human-lane cause: ${reason:0:70}..." \
  || bad "id:4a76: reason does not name the human-lane cause (got: '${reason:0:90}') — the board would still be unexplained"

# ── (B) TRIANGULATION — the csgebra shape (13 open, a single human-lane gate root). A
#        hard-coded 'all 18 are human' implementation is not a pass. ────────────────────────
v="$(verdict_of '{'"$drained"',"repo":"csgebra","roadmap_open":13,"open_human_lane":1}')"
[[ "$v" == "human" ]] \
  && ok "csgebra shape (13 open, ONE human-lane gate root) also classifies as human" \
  || bad "id:4a76: csgebra shape gave '$v', expected human — a single [INPUT — decision] gate root still blocks the repo"

# ── (C) NEGATIVE CONTROLS — the load-bearing half. Over-firing `human` would make every
#        genuinely-finished repo look blocked. ───────────────────────────────────────────────
v="$(verdict_of '{'"$drained"',"roadmap_open":0,"open_human_lane":0}')"
[[ "$v" == "idle" ]] \
  && ok "a genuinely empty repo (roadmap_open=0) is still idle" \
  || bad "id:4a76: empty repo gave '$v' — human over-fires and every drained repo reads as blocked"

v="$(verdict_of '{'"$drained"',"roadmap_open":7,"open_human_lane":0}')"
[[ "$v" == "idle" ]] \
  && ok "open items with NO human-lane item is still idle (all three conditions required)" \
  || bad "id:4a76: roadmap_open>0 with open_human_lane=0 gave '$v' — the rule collapsed to 'any open item'"

# BACK-COMPAT: a caller predating open_human_lane must behave exactly as today (idle), never
# blocked on an absent field — same sentinel discipline as id:4da4 / id:7616.
v="$(verdict_of '{'"$drained"',"roadmap_open":18}')"
[[ "$v" == "idle" ]] \
  && ok "a pre-field caller (no open_human_lane) is unchanged — idle, not a guess" \
  || bad "id:4a76: absent open_human_lane changed the verdict to '$v' — back-compat broken"

# ── (D) RANKING — `human` stays rank 5. It must never outrank real dispatchable work, or a
#        human-lane item would starve the pool (the id:bc2b failure mode, inverted). ────────
exec_state='"repo":"x","is_finished":false,"hasRoutine":true,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","unpromoted":{"promote":0,"surface":0}'
v="$(verdict_of '{'"$exec_state"',"roadmap_open":9,"roadmap_actionable_open":1,"actionable_routine_open":1,"open_human_lane":8}')"
[[ "$v" == "execute" ]] \
  && ok "open [ROUTINE] work still outranks the human-lane backlog (execute, rank 1)" \
  || bad "id:4a76: human-lane items outranked dispatchable work (got '$v') — the pool would starve"

v="$(verdict_of '{'"$drained"',"repo":"y","open_hard_pool":2,"roadmap_open":9,"open_human_lane":7}')"
[[ "$v" == "hard" ]] \
  && ok "open [HARD] pool work still outranks the human-lane backlog" \
  || bad "id:4a76: expected hard, got '$v'"

v="$(verdict_of '{'"$drained"',"repo":"z","roadmap_open":9,"open_human_lane":7,"unpromoted":{"promote":3,"surface":0}}')"
[[ "$v" == "handoff" ]] \
  && ok "promotable backlog still outranks the human-lane backlog (handoff, rank 4)" \
  || bad "id:4a76: expected handoff, got '$v'"

# ── (E) The existing id:5eb3 surface-only branch must keep firing UNCHANGED. ────────────────
v="$(verdict_of '{'"$drained"',"roadmap_open":0,"open_human_lane":0,"unpromoted":{"promote":0,"surface":35}}')"
[[ "$v" == "human" ]] \
  && ok "id:5eb3 surface-only → human is unchanged" \
  || bad "id:4a76: regression — surface-only backlog gave '$v', must stay human"

# ── (F) PRODUCER — classify-repo.sh must derive open_human_lane from ROADMAP.md, or the new
#        branch is unreachable in production ([[relay-builtgreen-but-unreferenced]]). ───────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_WORKTREE_BASE="$TMP/wt"
export RELAY_TOML="$TMP/relay.toml"; printf '[repos]\n' > "$RELAY_TOML"
R="$TMP/helferli"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t
cat > "$R/ROADMAP.md" <<'EOF'
# ROADMAP

## Items

- [ ] [INPUT — access] plug in the device and run the probe <!-- id:aaa1 -->
- [ ] [INPUT — meeting] decide the storage shape <!-- id:aaa2 -->
- [ ] [INPUT — decision] owner picks the vendor <!-- id:aaa3 -->
- [ ] [ROUTINE] @manual walk the checklist by hand <!-- id:aaa4 -->
- [x] [ROUTINE] already done, must not count <!-- id:aaa5 -->
EOF
printf '# TODO\n\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A
git -C "$R" commit -qm init
# Tag HEAD as an audited checkpoint, else substantive_unaudited fires at rank 2 and this
# fixture would test the wrong branch (review, not the drained cascade).
git -C "$R" tag -a "relay-ckpt-20260821-0000" -m "review: fixture baseline (claude-opus-5)"

out="$("$CR" --repo helferli --path "$R" 2>/dev/null || true)"
if [[ -n "$out" ]]; then
  pv="$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("verdict","<<ERR>>"))')"
  [[ "$pv" == "human" ]] \
    && ok "END-TO-END: a 4-human-lane fixture repo classifies as human via classify-repo.sh" \
    || bad "id:4a76: fixture repo with 4 open human-lane items and zero poolable work classified as '$pv' — this is the helferli false-clean"
else
  bad "id:4a76: classify-repo.sh produced no JSON for the fixture"
fi
unit="$("$CR" --emit unit --repo helferli --path "$R" 2>/dev/null || true)"
if [[ -n "$unit" ]]; then
  n="$(printf '%s' "$unit" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("open_human_lane","<<MISSING>>"))')"
  [[ "$n" == "4" ]] \
    && ok "classify-repo.sh derives open_human_lane=4 (3 [INPUT — *] + 1 @manual; the [x] item excluded)" \
    || bad "id:4a76: classify-repo.sh open_human_lane is '$n', expected 4 — the producer does not count human-lane items"
else
  bad "id:4a76: classify-repo.sh --emit unit produced no JSON for the fixture"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: human-lane-only backlog is human, not idle/design-drained (id:4a76)"
