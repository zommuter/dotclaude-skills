#!/usr/bin/env bash
# roadmap:7616 — the `[MECHANICAL]` capability tier (slice A, meeting 2026-07-02-1924).
#
# DECISION: add a fourth capability lane `[MECHANICAL]` for pure-compute work no LLM or
# human runs (local-LLM benchmarks, pytorch) — a host daemon runs it while an LLM session
# reviews the artifact. This RED spec pins the ADDITIVE tag+verdict plumbing only (the
# daemon consumer is A3, gated):
#   (a) roadmap-lint.sh ACCEPTS [MECHANICAL] standalone and composed with the orthogonal
#       [INTENSIVE — <res>] modifier; a [MECHANICAL]+[HARD — pool] item is a two-lane conflict.
#   (b) gather-human-backlog.sh keeps a MECHANICAL-only repo OUT of every human lane.
#   (c) classify-verdict.sh emits a NEW pool-inert `mechanical` verdict for open_mechanical>=1,
#       with intensive="" (id:5ac6 invariant intact); a co-existing [ROUTINE] still wins.
#   (d) hard-lanes.md documents the [MECHANICAL] capability tier.
#
# Hermetic: temp ROADMAP/relay.toml fixtures; no ~/.claude, no network.
# RED until roadmap-lint/gather-human-backlog/classify-verdict/hard-lanes.md learn [MECHANICAL].
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
GATHER="$ROOT/relay/scripts/gather-human-backlog.sh"
CV="$ROOT/relay/scripts/classify-verdict.sh"
VOCAB="$ROOT/relay/references/hard-lanes.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]]   || fail "roadmap-lint.sh not found/executable at $LINT"
[[ -x "$GATHER" ]] || fail "gather-human-backlog.sh not found/executable at $GATHER"
[[ -x "$CV" ]]     || fail "classify-verdict.sh not found/executable at $CV"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- (a) roadmap-lint accepts [MECHANICAL] standalone + composed --------------
ok="$tmp/ROADMAP_ok.md"
cat >"$ok" <<'MD'
# Roadmap

## Items

- [ ] [MECHANICAL] a pure-compute mechanical item <!-- id:aa01 -->
- [ ] [MECHANICAL] [INTENSIVE — local-llm] a mechanical intensive benchmark <!-- id:aa02 -->
- [ ] [ROUTINE] a normal routine item <!-- id:aa03 -->
MD
"$LINT" "$ok" >/dev/null 2>&1 \
  || fail "(a) roadmap-lint must ACCEPT [MECHANICAL] (standalone + [INTENSIVE] composed)"
pass "(a) roadmap-lint accepts [MECHANICAL] standalone and composed with [INTENSIVE]"

# A [MECHANICAL] + [HARD — pool] item carries TWO capability lanes → conflict (nonzero).
bad="$tmp/ROADMAP_bad.md"
cat >"$bad" <<'MD'
# Roadmap

## Items

- [ ] [MECHANICAL] [HARD — pool] two capability lanes on one item <!-- id:aa04 -->
MD
if "$LINT" "$bad" >/dev/null 2>&1; then
  fail "(a) roadmap-lint must REJECT a [MECHANICAL]+[HARD — pool] two-lane item (nonzero)"
fi
pass "(a) roadmap-lint rejects a [MECHANICAL]+[HARD — pool] two-lane conflict"

# --- (b) gather-human-backlog: a MECHANICAL-only repo yields NO human-lane line -
mkdir -p "$tmp/src/repoMech"
cat >"$tmp/src/repoMech/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [MECHANICAL] a compute-only item, no human/LLM lane <!-- id:aa05 -->
- [ ] [MECHANICAL] [INTENSIVE — local-llm] a mechanical benchmark <!-- id:aa06 -->
MD
cat >"$tmp/relay.toml" <<'TOML'
[repos.repoMech]
classification = "own"
confirmed = "2026-01-01"
TOML
# No recipe dir here → the two MECHANICAL items are ORPHANS. Point RELAY_RECIPE_DIR at an empty
# temp root so the id:8a6b orphan surfacer runs hermetically (never the real ~/.config/relay).
out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" RELAY_RECIPE_DIR="$tmp/recipes" bash "$GATHER" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "(b) MECHANICAL-only repo must NOT trip a LOUD reject (exit 0); got $rc, stderr: $(cat "$tmp/err")"
# A MECHANICAL item must NEVER surface as a HARD / human-decision / manual / review lane — that
# was the original bug this test guarded (mis-routing a pool-inert mechanical item to /meeting).
printf '%s\n' "$out" | grep -qE $'\t(hard_pool|hard_meeting|hard_hands|human_decision|manual|review_me)\t' \
  && fail "(b) MECHANICAL-only repo leaked into a HARD/human lane; got: $out" || true
pass "(b) gather-human-backlog keeps a MECHANICAL-only repo out of every HARD/human lane"
# id:8a6b: a MECHANICAL item with NO recipe MUST now surface as a mechanical_orphan so it can't
# rot silently (the resolution loop's LOUD-surface clause). This is the intended new behavior.
printf '%s\n' "$out" | grep -qE $'\tmechanical_orphan\t' \
  || fail "(b') an un-recipe'd MECHANICAL item must surface as mechanical_orphan (id:8a6b); got: $out"
pass "(b') gather-human-backlog surfaces an un-recipe'd MECHANICAL item as a mechanical_orphan (id:8a6b)"

# --- (c) classify-verdict emits a pool-inert `mechanical` verdict -------------
verdict() { "$CV" <<<"$1" | python3 -c "import sys,json;print(json.load(sys.stdin)['verdict'])"; }
field()   { "$CV" <<<"$1" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$2',''))"; }

mech='{"repo":"x","is_finished":false,"hasRoutine":false,"actionable_routine_open":0,"substantive_unaudited":false,"open_hard_pool":0,"open_mechanical":1,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":0,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict "$mech")" == "mechanical" ]] \
  || fail "(c) open_mechanical>=1 with nothing higher-priority must yield verdict=mechanical"
[[ "$(field "$mech" intensive)" == "" ]] \
  || fail "(c) mechanical verdict is pool-inert: intensive field must stay \"\" (id:5ac6 invariant)"
pass "(c) classify-verdict emits a pool-inert mechanical verdict (intensive=\"\")"

# A co-existing actionable [ROUTINE] still outranks mechanical (execute wins).
both='{"repo":"x","is_finished":false,"hasRoutine":true,"actionable_routine_open":1,"substantive_unaudited":false,"open_hard_pool":0,"open_mechanical":1,"top_intensive":"","roadmap_open":2,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict "$both")" == "execute" ]] \
  || fail "(c) an actionable [ROUTINE] must still win over a co-existing [MECHANICAL] item"
pass "(c) an actionable [ROUTINE] still outranks a co-existing [MECHANICAL] item"

# --- (d) hard-lanes.md documents the [MECHANICAL] capability tier -------------
grep -qF '[MECHANICAL]' "$VOCAB" \
  || fail "(d) hard-lanes.md must document the [MECHANICAL] capability tier"
pass "(d) hard-lanes.md names the [MECHANICAL] capability tier"

echo "ALL PASS: [MECHANICAL] capability tier (id:7616)"
