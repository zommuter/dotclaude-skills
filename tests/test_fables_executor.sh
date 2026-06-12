#!/usr/bin/env bash
# roadmap:7691 — fables-executor skill: install, registration, version consistency

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$(mktemp -d)"
trap 'rm -rf "$DEST_DIR"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# 1. Skill directory and SKILL.md exist in source
[[ -f "$SRC_DIR/fables-executor/SKILL.md" ]] || fail "fables-executor/SKILL.md missing in source"
pass "source SKILL.md exists"

# 2. Frontmatter name field
grep -q '^name: fables-executor' "$SRC_DIR/fables-executor/SKILL.md" \
  || fail "SKILL.md missing 'name: fables-executor' frontmatter"
pass "frontmatter name present"

# 3. Contract marker present
grep -q 'fables-executor contract v' "$SRC_DIR/fables-executor/SKILL.md" \
  || fail "SKILL.md missing '<!-- fables-executor contract vN -->' marker"
pass "contract marker present in SKILL.md"

# 4. make install-fables-executor creates a non-dangling symlink
make -C "$SRC_DIR" DEST_DIR="$DEST_DIR" install-fables-executor >/dev/null 2>&1 \
  || fail "make install-fables-executor failed"
[[ -L "$DEST_DIR/fables-executor/SKILL.md" ]] \
  || fail "SKILL.md not symlinked after install"
[[ -e "$DEST_DIR/fables-executor/SKILL.md" ]] \
  || fail "SKILL.md symlink is dangling"
pass "install creates non-dangling symlink"

# 5. make help lists fables-executor (capture first to avoid broken-pipe with pipefail)
HELP_OUT=$(make -C "$SRC_DIR" help 2>/dev/null)
echo "$HELP_OUT" | grep -q 'fables-executor' \
  || fail "make help does not list fables-executor"
pass "make help lists fables-executor"

# 6. make status-fables-executor reports the skill
STATUS_OUT=$(make -C "$SRC_DIR" DEST_DIR="$DEST_DIR" status-fables-executor 2>/dev/null)
echo "$STATUS_OUT" | grep -q 'SKILL.md' \
  || fail "make status-fables-executor does not mention SKILL.md"
pass "make status-fables-executor reports SKILL.md"

# 7. Version consistency: vN in SKILL.md matches vN in CLAUDE.md pointer
SKILL_VER=$(grep -o 'fables-executor contract v[0-9]*' \
  "$SRC_DIR/fables-executor/SKILL.md" | head -1 | grep -o 'v[0-9]*')
CLAUDE_VER=$(grep -o 'fables-executor contract v[0-9]*' \
  "$SRC_DIR/CLAUDE.md" | head -1 | grep -o 'v[0-9]*')
[[ -n "$SKILL_VER" ]] || fail "Could not extract version from SKILL.md"
[[ -n "$CLAUDE_VER" ]] || fail "Could not extract version from CLAUDE.md (pointer missing?)"
[[ "$SKILL_VER" == "$CLAUDE_VER" ]] \
  || fail "Version mismatch: SKILL.md=$SKILL_VER, CLAUDE.md=$CLAUDE_VER"
pass "version consistent: SKILL.md=$SKILL_VER, CLAUDE.md=$CLAUDE_VER"

# 8. conventions.md no longer has the old fenced 5-rule block
grep -q 'fables-turn contract v' \
  "$SRC_DIR/fables-turn/references/conventions.md" \
  && fail "conventions.md still contains old 'fables-turn contract v' marker" || true
pass "conventions.md has no old fables-turn contract marker"

echo "ALL PASS"
