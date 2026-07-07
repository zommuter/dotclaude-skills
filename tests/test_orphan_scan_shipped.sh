#!/usr/bin/env bash
# No roadmap header — this is the spec test for id:b3ee (see TODO.md and
# docs/meeting-notes/2026-07-07-1138-stale-ledger-root-cause.md), a new TOOL
# capability (orphan-scan.sh --shipped) rather than a fix gated on an existing
# ROADMAP item; there is no ROADMAP twin for b3ee to cite. Failures always count.
#
# orphan-scan.sh --shipped must reconcile stale-ledger drift (D1/D2 of the
# 2026-07-07 root-cause note) via two report-only classes:
#   - TICK-READY: open item, green linked test, no gating lexeme.
#   - GATE-STALE: open item, gating lexeme present, line >=14 days old (git blame).
# It must NEVER touch the checkbox itself — advisory text only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/docs/meeting-notes" "$repo/tests"
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

commit_line() {
  # commit_line <days-ago> <message>
  local days="$1" msg="$2"
  local d
  d="$(date -d "-${days} days" +%Y-%m-%dT12:00:00)"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git -C "$repo" commit -q -m "$msg"
}

: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.md"

# --- Case 4: genuinely open, no linked test — committed old, irrelevant (no gate lexeme) ---
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] just an open item with no linked test <!-- id:aaa4 -->
EOF
commit_line 30 "case4: open item no test"

# --- Case 5: already [x] — must never appear regardless of content ---
cat >> "$repo/TODO.md" <<'EOF'
- [x] done item, pending forever in prose but closed <!-- id:aaa5 -->
EOF
commit_line 25 "case5: closed item"

# --- Case 2: gating lexeme, aged >= 14 days -> GATE-STALE ---
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature Y activation pending on rollout <!-- id:aaa2 -->
EOF
commit_line 20 "case2: gated item, old"

# --- Case 3: gating lexeme, recent (<14 days) -> neither ---
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature Z awaiting verify before shipping <!-- id:aaa3 -->
EOF
commit_line 5 "case3: gated item, recent"

# --- Case 1: no gating lexeme, green linked test -> TICK-READY ---
cat > "$repo/tests/test_aaa1.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo ok
exit 0
EOF
chmod +x "$repo/tests/test_aaa1.sh"
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature X ships, see tests/test_aaa1.sh <!-- id:aaa1 -->
EOF
commit_line 1 "case1: tick-ready item + green test"

out="$(HOME="$tmp" "$ORPHAN" --shipped "$repo")"

# Case 1: TICK-READY
grep -q 'id:aaa1' <<<"$out" || { echo "case1: id:aaa1 must appear"; echo "$out"; exit 1; }
grep -q 'id:aaa1.*TICK-READY' <<<"$out" || { echo "case1: id:aaa1 must be TICK-READY"; echo "$out"; exit 1; }

# Case 2: GATE-STALE
grep -q 'id:aaa2' <<<"$out" || { echo "case2: id:aaa2 must appear"; echo "$out"; exit 1; }
grep -q 'id:aaa2.*GATE-STALE' <<<"$out" || { echo "case2: id:aaa2 must be GATE-STALE"; echo "$out"; exit 1; }

# Case 3: gated but recent -> neither class, must not appear at all
if grep -q 'id:aaa3' <<<"$out"; then
  echo "case3: id:aaa3 (recent gate) must NOT appear in either class"; echo "$out"; exit 1
fi

# Case 4: genuinely open, no test -> neither
if grep -q 'id:aaa4' <<<"$out"; then
  echo "case4: id:aaa4 (no linked test) must NOT appear"; echo "$out"; exit 1
fi

# Case 5: already closed -> never appears
if grep -q 'id:aaa5' <<<"$out"; then
  echo "case5: id:aaa5 (already [x]) must NEVER appear"; echo "$out"; exit 1
fi

# Report-only: the tool must not have touched TODO.md's checkboxes.
grep -q '^- \[ \] just an open item with no linked test' "$repo/TODO.md" || { echo "TODO.md checkbox for aaa4 was mutated"; exit 1; }
grep -q '^- \[x\] done item, pending forever in prose but closed' "$repo/TODO.md" || { echo "TODO.md checkbox for aaa5 was mutated"; exit 1; }

echo ok
