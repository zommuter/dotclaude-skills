#!/usr/bin/env bash
# roadmap:1bbd — gather-human-backlog.sh emit_hard_lanes() must read the lane from the
# item's OWN bracket tag (the tag immediately after the title), NOT from a literal
# `[HARD — pool]` that merely appears in the item's body PROSE (e.g. a re-lane-criterion
# sentence). Reported by it-infra relay HARD child (inbox routed:6645): a genuinely
# `[HARD — hands]` item whose prose quoted `[HARD — pool]` mis-bucketed as hard_pool →
# it-infra open_hard_pool=2 false-positive → a wasted Opus HARD dispatch.
#
# RED until the fix lands (the lane-parse currently does a whole-line substring match with
# the pool branch checked FIRST, so any prose mention of [HARD — pool] wins). Acceptance:
# the hands item with [HARD — pool] in its prose buckets as hard_hands, not hard_pool.
#
# Hermetic: a temp RELAY_TOML + a temp own repo with a crafted ROADMAP.md.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoP"
cat >"$tmp/src/repoP/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] A genuinely hands item whose re-lane criterion quotes `[HARD — pool]` in prose [HARD — hands] <!-- id:9321 -->
- [ ] A real pool item [HARD — pool] <!-- id:5555 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoP]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "fixture should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1) the hands item must bucket as hard_hands, NOT hard_pool — the lane comes from its
#     own bracket tag, not the [HARD — pool] string in its prose.
grep -qP '\thard_hands\t.*genuinely hands item' <<<"$out" \
  || fail "hands item (prose mentions [HARD — pool]) not bucketed as hard_hands (out: $out)"
! grep -qP '\thard_pool\t.*genuinely hands item' <<<"$out" \
  || fail "hands item mis-bucketed as hard_pool because of a prose [HARD — pool] mention (out: $out)"

# (2) the genuine pool item still buckets as hard_pool (no regression).
grep -qP '\thard_pool\t.*A real pool item' <<<"$out" \
  || fail "genuine [HARD — pool] item not bucketed as hard_pool (out: $out)"

pass "emit_hard_lanes reads the lane from the item's own bracket tag, ignoring a [HARD — pool] mention in body prose (1bbd)"
