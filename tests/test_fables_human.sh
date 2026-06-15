#!/usr/bin/env bash
# roadmap:2892 — /fables-turn human mode: cross-repo human-backlog triage.
#
# Two parts: (1) static contract checks on SKILL.md + references/human.md (the
# mode is a prose-driven strong-turn procedure, like the front-door/review docs);
# (2) a hermetic behavioral test of scripts/gather-human-backlog.sh against fixture
# REVIEW_ME.md/ROADMAP.md files under a mktemp store with overridden roots.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/fables-turn/SKILL.md"
HUMAN="$ROOT/fables-turn/references/human.md"
GATHER="$ROOT/fables-turn/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# --- (1) SKILL.md documents the human mode + invocation ----------------------
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"

grep -qE '^/fables-turn human ' "$SKILL" \
  || fail "SKILL.md invocation block has no '/fables-turn human' line"
pass "SKILL.md documents /fables-turn human invocation"

grep -qE '^## Human mode' "$SKILL" || fail "SKILL.md has no '## Human mode' section"
pass "SKILL.md has a Human mode section"

grep -q 'references/human.md' "$SKILL" || fail "SKILL.md does not point at references/human.md"
pass "SKILL.md points at references/human.md"

grep -qi 'AskUserQuestion' "$SKILL" || fail "SKILL.md Human mode does not mention AskUserQuestion"
grep -qiE 'NOT (an )?autonomous Workflow|not a.* Workflow' "$SKILL" \
  || fail "SKILL.md does not state human mode is NOT a Workflow"
pass "SKILL.md frames human mode as interactive procedure (AskUserQuestion, not a Workflow)"

grep -qi 'review_me' "$SKILL" || fail "SKILL.md does not note it generalizes review_me"
grep -qiE 'Opus (is |= )?apex|apex tier' "$SKILL" || fail "SKILL.md missing Opus-apex framing"
pass "SKILL.md notes review_me generalization + Opus-apex framing"

# --- (2) references/human.md specifies the 3 tiers + rules -------------------
[[ -f "$HUMAN" ]] || fail "references/human.md not found at $HUMAN"
pass "references/human.md exists"

grep -qi 'AUTO-ANSWERABLE' "$HUMAN" || fail "human.md missing AUTO-ANSWERABLE tier"
grep -qi 'BATCH-DECIDABLE' "$HUMAN" || fail "human.md missing BATCH-DECIDABLE tier"
grep -qi 'CHEWY' "$HUMAN" || fail "human.md missing CHEWY tier"
pass "human.md specifies the 3 tiers (auto/batch/chewy)"

grep -qiE 'NEVER auto-tick.*@manual|@manual.*NEVER auto-tick|never auto-tick' "$HUMAN" \
  || fail "human.md does not state @manual boxes are never auto-ticked"
pass "human.md specifies @manual-never-auto-tick"

grep -q '/meeting --cross' "$HUMAN" || fail "human.md does not route tier-C to /meeting --cross"
pass "human.md routes tier-C → /meeting --cross"

grep -qiE 'downgrade a.*b|downgrade.*to .b.' "$HUMAN" \
  || fail "human.md missing the conservative downgrade-a→b anti-gaming rule"
pass "human.md states the conservative downgrade-a→b rule"

# --- (3) gather-human-backlog.sh: hermetic TSV emission + @manual flag -------
[[ -x "$GATHER" ]] || fail "gather-human-backlog.sh not found or not executable"

STORE="$(mktemp -d)"
trap 'rm -rf "$STORE"' EXIT
mkdir -p "$STORE/src/repoA" "$STORE/src/repoB" "$STORE/cfg"

cat > "$STORE/src/repoA/REVIEW_ME.md" <<'EOF'
# Human review queue
- [ ] parse.py::test_empty (roadmap:9f0a) — empty input: [] or raise?
- [x] already resolved — should not appear
- [ ] @manual run the on-device smoke test before release
EOF

cat > "$STORE/src/repoB/REVIEW_ME.md" <<'EOF'
# Human review queue
- [ ] api.py::test_auth (roadmap:1c2d) — reject or 401 on bad token?
EOF

cat > "$STORE/src/repoB/ROADMAP.md" <<'EOF'
## Items
- [ ] Routine thing [ROUTINE] <!-- id:aaaa -->
- [ ] Run the full BDD journey on real hardware @manual <!-- id:bbbb -->
EOF

# repoB is excluded? No — both own. A third clone repo must be skipped.
cat > "$STORE/cfg/relay.toml" <<'EOF'
[repos.repoA]
classification = "own"

[repos.repoB]
classification = "own"

[repos.repoC]
classification = "clone"
EOF

OUT="$(SRC_DIR="$STORE/src" RELAY_TOML="$STORE/cfg/relay.toml" bash "$GATHER")"

# 4 TSV columns per line.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  n="$(awk -F'\t' '{print NF}' <<<"$line")"
  [[ "$n" -eq 4 ]] || fail "TSV line does not have 4 columns: $line"
done <<<"$OUT"
pass "gather emits 4-column TSV"

# Open review_me box from repoA present.
grep -qP '^repoA\t.*\treview_me\t.*test_empty' <<<"$OUT" \
  || fail "missing repoA review_me box"
pass "gather emits open REVIEW_ME box (kind=review_me)"

# Closed [x] box must NOT appear.
grep -q 'already resolved' <<<"$OUT" && fail "closed [x] box leaked into output"
pass "gather skips closed [x] boxes"

# @manual REVIEW_ME box flagged kind=manual.
grep -qP '^repoA\t.*\tmanual\t.*on-device smoke test' <<<"$OUT" \
  || fail "@manual REVIEW_ME box not flagged kind=manual"
pass "gather flags @manual REVIEW_ME box as kind=manual"

# @manual ROADMAP box flagged kind=manual.
grep -qP '^repoB\t.*\tmanual\t.*real hardware' <<<"$OUT" \
  || fail "@manual ROADMAP box not flagged kind=manual"
pass "gather flags @manual ROADMAP box as kind=manual"

# Non-@manual ROADMAP item is NOT collected (only review_me + @manual).
grep -q 'Routine thing' <<<"$OUT" && fail "plain ROADMAP routine item leaked into output"
pass "gather ignores non-@manual ROADMAP items"

# repoB review_me box present (named-repo + all-repo paths both covered).
grep -qP '^repoB\t.*\treview_me\t.*test_auth' <<<"$OUT" \
  || fail "missing repoB review_me box"
pass "gather covers multiple own repos"

# clone repo (repoC) is skipped — it has no files, but assert it never appears.
grep -q '^repoC' <<<"$OUT" && fail "clone repo repoC must be skipped"
pass "gather skips non-own (clone) repos"

# Named-repo invocation resolves the same paths.
OUT2="$(SRC_DIR="$STORE/src" RELAY_TOML="$STORE/cfg/relay.toml" bash "$GATHER" repoA)"
grep -qP '^repoA\t.*test_empty' <<<"$OUT2" || fail "named-repo invocation missed repoA box"
grep -q '^repoB' <<<"$OUT2" && fail "named-repo invocation should not include repoB"
pass "gather honors named-repo argument"

echo "all checks passed"
