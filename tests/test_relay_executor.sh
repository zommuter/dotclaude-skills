#!/usr/bin/env bash
# roadmap:7691 — relay executor contract: lean reference doc, version consistency,
# loaded via /relay executor (merged from the old fables-executor skill, TODO id:1cb4).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$(mktemp -d)"
trap 'rm -rf "$DEST_DIR"' EXIT

CONTRACT="$SRC_DIR/relay/references/executor-contract.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# 1. The lean executor contract lives as a relay reference (not a standalone skill).
[[ -f "$CONTRACT" ]] || fail "relay/references/executor-contract.md missing in source"
pass "executor-contract.md exists under relay/references/"

# 2. It is a plain reference doc — NO skill frontmatter (it must not register as a skill).
head -1 "$CONTRACT" | grep -q '^---$' \
  && fail "executor-contract.md still has skill frontmatter (should be a lean reference)" || true
pass "executor-contract.md has no skill frontmatter"

# 3. Contract marker present, bumped to v6 (the id:08c0 structured size-out signal bump).
grep -q 'relay-executor contract v6' "$CONTRACT" \
  || fail "executor-contract.md missing '<!-- relay-executor contract v6 -->' marker"
pass "contract marker present (v6)"

# 3b. Rule 0 (id:ebfb): executor acquires the cross-session repo lease before working.
grep -qi 'Cross-session lease' "$CONTRACT" || fail "executor contract missing the cross-session lease rule (id:ebfb)"
grep -q 'claim.sh acquire' "$CONTRACT" || fail "executor contract rule 0 does not acquire the lease (claim.sh acquire)"
grep -q 'claim.sh release' "$CONTRACT" || fail "executor contract rule 0 does not release the lease at session end"
pass "executor honors the cross-session lease (rule 0, id:ebfb)"

# 4. SKILL.md handles the `executor` arg by pointing at the lean reference (not the orchestrator).
SKILL="$SRC_DIR/relay/SKILL.md"
grep -q '/relay executor' "$SKILL" || fail "SKILL.md does not document the '/relay executor' arg"
grep -q 'references/executor-contract.md' "$SKILL" \
  || fail "SKILL.md executor arg does not point at references/executor-contract.md"
pass "SKILL.md routes '/relay executor' to the lean contract reference"

# 5. make install-relay symlinks the contract reference (so /relay executor can read it).
make -C "$SRC_DIR" DEST_DIR="$DEST_DIR" install-relay >/dev/null 2>&1 \
  || fail "make install-relay failed"
[[ -L "$DEST_DIR/relay/references/executor-contract.md" ]] \
  || fail "executor-contract.md not symlinked after install"
[[ -e "$DEST_DIR/relay/references/executor-contract.md" ]] \
  || fail "executor-contract.md symlink is dangling"
pass "install-relay creates non-dangling executor-contract.md symlink"

# 6. Version consistency: vN in the contract matches vN in this repo's CLAUDE.md pointer.
CONTRACT_VER=$(grep -o 'relay-executor contract v[0-9]*' "$CONTRACT" | head -1 | grep -o 'v[0-9]*')
CLAUDE_VER=$(grep -o 'relay-executor contract v[0-9]*' "$SRC_DIR/CLAUDE.md" | head -1 | grep -o 'v[0-9]*')
[[ -n "$CONTRACT_VER" ]] || fail "Could not extract version from executor-contract.md"
[[ -n "$CLAUDE_VER" ]] || fail "Could not extract version from CLAUDE.md (pointer missing?)"
[[ "$CONTRACT_VER" == "$CLAUDE_VER" ]] \
  || fail "Version mismatch: contract=$CONTRACT_VER, CLAUDE.md=$CLAUDE_VER"
pass "version consistent: contract=$CONTRACT_VER, CLAUDE.md=$CLAUDE_VER"

# 7. conventions.md no longer carries an old fenced 5-rule block marker.
grep -q 'fables-turn contract v' "$SRC_DIR/relay/references/conventions.md" \
  && fail "conventions.md still contains old 'fables-turn contract v' marker" || true
pass "conventions.md has no old fables-turn contract marker"

# 8. fables-executor has been fully retired: the deprecated alias stub was untracked
# (commit 608800b — git rm --cached, .gitignore'd, removed from the Makefile SKILLS list)
# now that no cron/scheduled job or invocation references the old name. It must NOT be a
# tracked source file (a fresh clone / CI checkout has no fables-executor/ dir). A local
# untracked redirect dir may still exist for fat-finger convenience, so assert on git's
# tracked set, not the filesystem.
if git -C "$SRC_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$SRC_DIR" ls-files --error-unmatch fables-executor/SKILL.md >/dev/null 2>&1 \
    && fail "fables-executor/SKILL.md is still TRACKED — it was retired and untracked in 608800b" || true
  pass "fables-executor alias stub is untracked (skill fully retired to /relay executor)"
else
  # Not a git checkout (e.g. tarball) — fall back to absence on disk.
  [[ -f "$SRC_DIR/fables-executor/SKILL.md" ]] \
    && fail "fables-executor/SKILL.md present in a non-git checkout — should be retired" || true
  pass "fables-executor alias stub absent (skill fully retired to /relay executor)"
fi

echo "ALL PASS"
