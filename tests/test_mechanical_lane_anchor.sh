#!/usr/bin/env bash
# roadmap:0d58
# Spec for the [MECHANICAL] lane-anchor hotfix (id:0d58).
#
# classify-repo.sh has TWO disagreeing tag readers on an open `- [ ]` ROADMAP line:
#   - the PRIMARY-LANE derivation (id:4da4, ~line 102) is positionally ANCHORED: the item's
#     lane is the FIRST recognized LANE_TAGS token; a backtick/prose bracket-token further
#     right is history and must NOT set the lane.
#   - the open_mechanical counter (~line 93) is a BARE SUBSTRING test `if "[MECHANICAL]" in ln`.
#     "[MECHANICAL]" is NOT in LANE_TAGS and does NOT participate in the anchoring, so a mere
#     backtick'd `[MECHANICAL]` mention on a line whose REAL lane is [HARD — pool]/[ROUTINE]
#     falsely increments open_mechanical — which drives the priority-6 `mechanical` verdict
#     (classify-verdict.sh:146, open_mechanical >= 1).
#
# The fix must make the open_mechanical count LANE-ANCHORED like the primary-lane derivation:
# only a line whose PRIMARY lane is [MECHANICAL] counts. It must NOT over-correct to zero — a
# genuine [MECHANICAL]-primary item must still count and still yield the `mechanical` verdict.
#
# RED until id:0d58 lands. roadmap:0d58 box unticked ⇒ EXPECTED-RED (does not fail the suite);
# ticking it makes any failure real.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh not found (RED): $CR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Hermetic: empty relay.toml + isolated worktree base so gather-repo-state stays repo-local.
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"

mkrepo()      { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; }
commit_repo() { git -C "$1" add -A; git -C "$1" commit -qm init; }
ckpt_head()   { git -C "$1" tag -a "relay-ckpt-20260101-0000" -m ckpt; }  # mark HEAD audited (no unaudited commits ⇒ not `review`)

verdict_of()  { "$CR" --repo "$(basename "$1")" --path "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }
# open_mechanical is exposed as a schema-safe field on the --emit unit output (id:7616).
mech_of()     { "$CR" --emit unit --repo "$(basename "$1")" --path "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["open_mechanical"])'; }

# --- FALSE-POSITIVE (verdict): a [ROUTINE] item (drained via @manual so nothing higher fires)
# that merely MENTIONS `[MECHANICAL]` in backticks must NOT mis-fire the `mechanical` verdict,
# and must NOT count in open_mechanical. HEAD audited + clean TODO so no higher-priority class
# masks the (buggy) mechanical verdict — the correct verdict here is `idle`.
R1="$tmp/r_routine_mention"; mkrepo "$R1"
cat > "$R1/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] @manual eyeball the ghost preview; see the `[MECHANICAL]` runner note below <!-- id:1111 -->
EOF
printf '# TODO\n## Current\n' > "$R1/TODO.md"
commit_repo "$R1"; ckpt_head "$R1"
[[ "$(mech_of "$R1")" == "0" ]]        || { echo "FAIL: backtick'd [MECHANICAL] on a [ROUTINE] line must NOT count in open_mechanical, got $(mech_of "$R1")"; exit 1; }
[[ "$(verdict_of "$R1")" != "mechanical" ]] || { echo "FAIL: a [ROUTINE] line merely mentioning \`[MECHANICAL]\` must NOT classify mechanical, got mechanical"; exit 1; }

# --- FALSE-POSITIVE (count): a [HARD — pool] item that mentions `[MECHANICAL]` in backticks.
# Its real lane is hard-pool (verdict `hard`, priority 3, masks mechanical), but the bug still
# corrupts the open_mechanical COUNT — assert it directly via --emit unit.
R2="$tmp/r_hardpool_mention"; mkrepo "$R2"
cat > "$R2/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — pool] real strong-model work; superseded a `[MECHANICAL]` sub-step <!-- id:2222 -->
EOF
printf '# TODO\n## Current\n' > "$R2/TODO.md"
commit_repo "$R2"; ckpt_head "$R2"
[[ "$(mech_of "$R2")" == "0" ]]      || { echo "FAIL: backtick'd [MECHANICAL] on a [HARD — pool] line must NOT count in open_mechanical, got $(mech_of "$R2")"; exit 1; }
[[ "$(verdict_of "$R2")" == "hard" ]] || { echo "FAIL: the real [HARD — pool] item should classify hard, got $(verdict_of "$R2")"; exit 1; }

# --- GUARD (no over-correction): a GENUINE [MECHANICAL]-primary item MUST still count and MUST
# still yield the `mechanical` verdict. HEAD audited + clean TODO + no routine/hard so mechanical
# is the top live class.
R3="$tmp/r_genuine_mechanical"; mkrepo "$R3"
cat > "$R3/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [MECHANICAL] regenerate the derived index (pure compute) <!-- id:3333 -->
EOF
printf '# TODO\n## Current\n' > "$R3/TODO.md"
commit_repo "$R3"; ckpt_head "$R3"
[[ "$(mech_of "$R3")" == "1" ]]            || { echo "FAIL: a genuine [MECHANICAL]-primary item must count in open_mechanical, got $(mech_of "$R3") (fix over-corrected to zero)"; exit 1; }
[[ "$(verdict_of "$R3")" == "mechanical" ]] || { echo "FAIL: a genuine [MECHANICAL]-primary item must classify mechanical, got $(verdict_of "$R3")"; exit 1; }

# --- side-effect-free: running the wrapper leaves each fixture's git tree clean --------------
for r in "$R1" "$R2" "$R3"; do
  [[ -z "$(git -C "$r" status --porcelain)" ]] || { echo "FAIL: wrapper must be side-effect-free; $r dirtied"; exit 1; }
done

echo "PASS test_mechanical_lane_anchor"
