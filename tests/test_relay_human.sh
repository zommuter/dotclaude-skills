#!/usr/bin/env bash
# roadmap:2892 — /relay human mode: cross-repo human-backlog triage.
#
# Two parts: (1) static contract checks on SKILL.md + references/human.md (the
# mode is a prose-driven strong-turn procedure, like the front-door/review docs);
# (2) a hermetic behavioral test of scripts/gather-human-backlog.sh against fixture
# REVIEW_ME.md/ROADMAP.md files under a mktemp store with overridden roots.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/relay/SKILL.md"
HUMAN="$ROOT/relay/references/human.md"
GATHER="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# --- (1) SKILL.md documents the human mode + invocation ----------------------
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"

grep -qE '^/relay human ' "$SKILL" \
  || fail "SKILL.md invocation block has no '/relay human' line"
pass "SKILL.md documents /relay human invocation"

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

# --- (2b) human.md specifies the gated-HARD sweep (id:f6c9) -------------------
grep -qi 'gated_hard' "$HUMAN" || fail "human.md does not name the gated_hard kind (id:f6c9)"
grep -qi 'needs a /meeting' "$HUMAN" || fail "human.md missing the gated-HARD 'needs a /meeting' framing"
grep -qi 're-deriv' "$HUMAN" || fail "human.md does not state gated_hard is re-derived from ROADMAP"
grep -qi 'id:f6c9' "$HUMAN" || fail "human.md does not cite id:f6c9 for the gated-HARD sweep"
pass "human.md specifies the gated-HARD (kind=gated_hard) tier-(c) sweep (id:f6c9)"

grep -qiE 'downgrade a.*b|downgrade.*to .b.' "$HUMAN" \
  || fail "human.md missing the conservative downgrade-a→b anti-gaming rule"
pass "human.md states the conservative downgrade-a→b rule"

# --- (3) gather-human-backlog.sh: hermetic TSV emission + @manual flag -------
[[ -x "$GATHER" ]] || fail "gather-human-backlog.sh not found or not executable"

STORE="$(mktemp -d)"
trap 'rm -rf "$STORE"' EXIT
mkdir -p "$STORE/src/repoA" "$STORE/src/repoB" "$STORE/src/repoD" "$STORE/cfg"

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

# repoA also has a ROADMAP exercising the gated-HARD sweep (id:f6c9):
#   - a [HARD — decision gate] item  → gated_hard (decision-gate)
#   - an item under a "## Gated" section → gated_hard (gated-section)
#   - an executable [HARD — strong model] item → NOT emitted (negative control)
#   - a closed [x] gated item → NOT emitted
cat > "$STORE/src/repoA/ROADMAP.md" <<'EOF'
## Executable work
- [ ] [HARD — strong model] Refactor the parser core <!-- id:e0e0 -->
- [x] [HARD — decision gate] Already-resolved gate <!-- id:dead -->

## Open decision gates
- [ ] [HARD — decision gate] Pick the on-disk format: msgpack vs json <!-- id:9999 -->

## Gated
- [ ] [HARD — strong model] Build the thing once the gate opens <!-- id:8888 -->
EOF

# repoD is own but paused = true (on-hiatus): it has an open box that MUST NOT
# be swept. Guards the gather-human-backlog.sh paused-filter (commit 7456e1f).
cat > "$STORE/src/repoD/REVIEW_ME.md" <<'EOF'
# Human review queue
- [ ] paused.py::test_hiatus — should NOT be swept while repo is paused
EOF

# repoB is excluded? No — both own. A third clone repo must be skipped.
cat > "$STORE/cfg/relay.toml" <<'EOF'
[repos.repoA]
classification = "own"

[repos.repoB]
classification = "own"

[repos.repoC]
classification = "clone"

[repos.repoD]
classification = "own"
paused = true
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

# Non-@manual ROADMAP item is NOT collected (only review_me + @manual + gated_hard).
grep -q 'Routine thing' <<<"$OUT" && fail "plain ROADMAP routine item leaked into output"
pass "gather ignores non-@manual ROADMAP items"

# --- gated-HARD sweep (id:f6c9): kind=gated_hard from ROADMAP -----------------
# decision-gate item is emitted as gated_hard, with the why-gated reason embedded.
grep -qP '^repoA\t.*\tgated_hard\t.*msgpack vs json.*— gated: decision-gate' <<<"$OUT" \
  || fail "decision-gate [HARD] item not emitted as gated_hard with reason"
pass "gather emits [HARD — decision gate] item as kind=gated_hard with why-gated reason"

# item under a ## Gated section is emitted as gated_hard (gated-section reason).
grep -qP '^repoA\t.*\tgated_hard\t.*once the gate opens.*— gated: under a gated' <<<"$OUT" \
  || fail "item under ## Gated section not emitted as gated_hard"
pass "gather emits item under a ## Gated section as kind=gated_hard"

# executable [HARD — strong model] item (not gated) is NOT emitted (negative control).
grep -q 'Refactor the parser core' <<<"$OUT" \
  && fail "executable [HARD — strong model] item leaked into gated_hard output"
pass "gather does NOT emit executable [HARD — strong model] items (negative control)"

# closed [x] gated item is NOT emitted.
grep -q 'Already-resolved gate' <<<"$OUT" \
  && fail "closed [x] gated item leaked into output"
pass "gather skips closed [x] gated-HARD items"

# repoB review_me box present (named-repo + all-repo paths both covered).
grep -qP '^repoB\t.*\treview_me\t.*test_auth' <<<"$OUT" \
  || fail "missing repoB review_me box"
pass "gather covers multiple own repos"

# clone repo (repoC) is skipped — it has no files, but assert it never appears.
grep -q '^repoC' <<<"$OUT" && fail "clone repo repoC must be skipped"
pass "gather skips non-own (clone) repos"

# paused own repo (repoD) is skipped in the all-repos sweep even though it has an
# open box — regression guard for the relay.toml `paused = true` filter (7456e1f).
grep -q '^repoD' <<<"$OUT" && fail "paused own repo repoD must be skipped in sweep"
pass "gather skips paused (on-hiatus) own repos in the sweep"

# Named-repo invocation resolves the same paths.
OUT2="$(SRC_DIR="$STORE/src" RELAY_TOML="$STORE/cfg/relay.toml" bash "$GATHER" repoA)"
grep -qP '^repoA\t.*test_empty' <<<"$OUT2" || fail "named-repo invocation missed repoA box"
grep -q '^repoB' <<<"$OUT2" && fail "named-repo invocation should not include repoB"
pass "gather honors named-repo argument"

# --- (4) nested-worktree stderr WARN (the "stale checkout" trap) -------------
# A linked git worktree nested INSIDE a repo's checkout means /relay human may be
# reading a STALE top-level tree while the live branch sits in a sub-worktree (bit
# ai-codebench 2026-06-15). gather warns to stderr per such repo, leaving the TSV on
# stdout unchanged, and stays SILENT for a clean repo. Regression guard for commit
# 83d8614. Needs real git repos (the function early-returns on non-git dirs, which is
# why sections 1–3's plain-dir fixtures stay silent).
WTSTORE="$(mktemp -d)"
trap 'rm -rf "$STORE" "$WTSTORE"' EXIT

git init -q "$WTSTORE/nested"
git -C "$WTSTORE/nested" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WTSTORE/nested" worktree add -q "$WTSTORE/nested/sub" -b feat HEAD

git init -q "$WTSTORE/clean"
git -C "$WTSTORE/clean" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

cat > "$WTSTORE/relay.toml" <<EOF
[repos.nested]
classification = "own"
path = "$WTSTORE/nested"

[repos.clean]
classification = "own"
path = "$WTSTORE/clean"
EOF

# Capture stdout and stderr separately: TSV must stay on stdout, WARN on stderr.
WT_STDOUT="$(SRC_DIR="$WTSTORE" RELAY_TOML="$WTSTORE/relay.toml" bash "$GATHER" 2>"$WTSTORE/err")"
WT_STDERR="$(cat "$WTSTORE/err")"

# (a) the nested-worktree repo warns to stderr, naming the nested worktree path.
grep -q "WARN:.*nested has nested worktree" <<<"$WT_STDERR" \
  || fail "nested-worktree repo did not emit a WARN to stderr"
grep -qF "$WTSTORE/nested/sub" <<<"$WT_STDERR" \
  || fail "WARN did not name the nested worktree path"
pass "gather warns (stderr) on a worktree nested inside the checkout"

# (b) the clean repo must NOT warn — non-vacuous negative control.
grep -q "clean has nested worktree" <<<"$WT_STDERR" \
  && fail "clean repo wrongly flagged as nested"
pass "gather stays silent for a clean repo (no nested worktree)"

# (c) the WARN never contaminates the TSV on stdout.
grep -q 'WARN' <<<"$WT_STDOUT" \
  && fail "WARN leaked onto stdout (must go to stderr only)"
pass "nested-worktree WARN stays off stdout (TSV uncontaminated)"

echo "all checks passed"
