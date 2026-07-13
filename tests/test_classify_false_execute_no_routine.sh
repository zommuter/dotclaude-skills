#!/usr/bin/env bash
# roadmap:2ab2
#
# RED spec for id:2ab2 — the discovery classifier emits a FALSE `execute` verdict
# ("Open executor-actionable [ROUTINE] ROADMAP items present") for repos that have
# NO open executor-actionable [ROUTINE] item.
#
# Observed 2026-07-13 (pool run relay-20260713-130624-24135): two repos were
# execute-dispatched and immediately handed back "no executor-actionable work",
# wasting a worktree + a model child each:
#   * isochrone — ZERO [ROUTINE] items at all (only [INPUT — meeting] + a gated
#                 [MECHANICAL] [INTENSIVE — r5-jvm] item).
#   * it-infra  — its only two [ROUTINE] items (id:935e, id:6e27) are BOTH `[x]`
#                 closed; the one open [INTENSIVE] item is a 🚧-gated
#                 [HARD — pool] [INTENSIVE — local-llm] route:human item.
#
# Root cause (traced): classify-repo.sh derives actionable_routine_open == 0 for
# BOTH repos CORRECTLY. The false `execute` is manufactured downstream: because
# gather-repo-state.sh's top_intensive filter (id:ad74/a707) excludes only
# `[HARD — hands|meeting|decision gate]` / `@manual` — but NOT `🚧`/`BLOCKED`-gated
# lines and NOT the pool-inert `[MECHANICAL]` lane — a non-executor-actionable
# INTENSIVE item still populates top_intensive. classify-verdict.sh fold (b) then
# promotes actionable_routine 0 -> 1 from that non-empty top_intensive and labels
# it as a `[ROUTINE]` execute (rank 1), out-ranking the correct verdict.
#
# Correct behaviour (per SKILL.md / references): executor-actionable = primary-lane
# [ROUTINE] AND open `- [ ]` AND NOT @manual/human-gated AND NOT 🚧/BLOCKED-gated.
# A repo with zero actionable [ROUTINE] must NOT classify `execute`.
#
# This test drives the FULL pipeline (classify-repo.sh -> gather + classify-verdict)
# against two hermetic fixtures reproducing BOTH real cases, and asserts neither is
# `execute`. It is RED against current code (both currently return execute); it is
# the spec for id:2ab2, whose ROADMAP checkbox is unticked => reported EXPECTED-RED.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh missing"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Hermetic: empty relay.toml, temp worktree base, and DISABLE the relay-core shadow
# (set-but-not-executable RELAY_CORE_BIN is the documented kill switch) so no log write leaks.
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_CORE_BIN=/nonexistent

verdict_of() {  # verdict_of <repo> <path>
  "$CR" --repo "$1" --path "$2" 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["verdict"])'
}

fail=0

# --- Case A (isochrone-like): ZERO [ROUTINE] items at all -------------------
# Only an [INPUT — meeting] item and a 🚧-gated [MECHANICAL] [INTENSIVE — r5-jvm]
# item. There is nothing an executor can act on => must NOT be `execute`.
A="$tmp/repoA"; mkdir -p "$A"
git -C "$A" init -q; git -C "$A" config user.email t@e; git -C "$A" config user.name t
cat > "$A/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [INPUT — meeting] design a thing that needs a human <!-- id:aaaa -->
- [ ] [MECHANICAL] ** ** @container [INTENSIVE — r5-jvm] crop + field-gen + emit — 🚧 GATED (auto) <!-- id:bbbb -->
EOF
git -C "$A" add -A; git -C "$A" commit -qm init
vA="$(verdict_of repoA "$A")"
if [[ "$vA" == "execute" ]]; then
  echo "FAIL case A (zero [ROUTINE]): got FALSE execute verdict — no open actionable [ROUTINE] exists"
  fail=1
else
  echo "ok   case A (zero [ROUTINE]): verdict=$vA (not execute)"
fi

# --- Case B (it-infra-like): [ROUTINE] present but ALL `[x]` closed ----------
# Both [ROUTINE] items are closed; the only open [INTENSIVE] item is a 🚧-gated
# [HARD — pool] route:human item. No open actionable [ROUTINE] => must NOT be `execute`.
B="$tmp/repoB"; mkdir -p "$B"
git -C "$B" init -q; git -C "$B" config user.email t@e; git -C "$B" config user.name t
cat > "$B/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [x] [ROUTINE] author-half toggle — already shipped <!-- id:cccc -->
- [x] [ROUTINE] launch wrapper folds in toggle — already shipped <!-- id:dddd -->
- [ ] [HARD — pool] [INTENSIVE — local-llm] GPU seed-hunt — 🚧 GATED (auto; route:human) needs /relay human <!-- id:eeee -->
EOF
git -C "$B" add -A; git -C "$B" commit -qm init
vB="$(verdict_of repoB "$B")"
if [[ "$vB" == "execute" ]]; then
  echo "FAIL case B (only [x]-closed [ROUTINE]): got FALSE execute verdict — every [ROUTINE] item is closed"
  fail=1
else
  echo "ok   case B (only [x]-closed [ROUTINE]): verdict=$vB (not execute)"
fi

[[ "$fail" -eq 0 ]] || { echo "test_classify_false_execute_no_routine: RED (id:2ab2 not yet fixed)"; exit 1; }
echo "PASS test_classify_false_execute_no_routine"
