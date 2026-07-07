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

# --- Case 6: EXTERNAL-WAIT word, aged >= 14 days -> STILL neither (2026-07-07 split) ---
# A legitimately-gated item (observation window / external dep) must NOT surface as
# GATE-STALE no matter how old — only COMPLETION-pending clauses do.
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature W: let it run, then observe adoption before deciding <!-- id:aaa6 -->
EOF
commit_line 40 "case6: external-wait item, old"

# --- Case 1: no gating lexeme, green test that OWNS this item via `# roadmap:` -> TICK-READY ---
# TICK-READY trusts only the `# roadmap:<token>` reverse-link, not a bare inline path
# (the 2026-07-07 tightening — inline-path mentions produced umbrella false-positives).
cat > "$repo/tests/test_aaa1.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:aaa1
set -euo pipefail
echo ok
exit 0
EOF
chmod +x "$repo/tests/test_aaa1.sh"
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature X ships fully <!-- id:aaa1 -->
EOF
commit_line 1 "case1: tick-ready item + roadmap-linked green test"

# --- Case 7: inline test path only (no `# roadmap:` owner) -> NOT TICK-READY ---
# A partial/umbrella item that merely cites a sub-part's test must not be flagged ready.
cat > "$repo/tests/test_aaa7.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo ok
exit 0
EOF
chmod +x "$repo/tests/test_aaa7.sh"
cat >> "$repo/TODO.md" <<'EOF'
- [ ] umbrella: sub-part shipped, see tests/test_aaa7.sh; other parts open <!-- id:aaa7 -->
EOF
commit_line 1 "case7: inline-only path, not owned"

# --- Case 8: "investigated" substring-contains-"gated" but is NOT a real gate word ---
# (strong-model audit run 70 finding 3): a plain substring match on "gated" would wrongly
# fire on investi-gated and suppress this as EXTERNAL-WAIT even though it has a green,
# roadmap-owned test and no genuine gating clause — it must classify TICK-READY instead.
cat > "$repo/tests/test_aaa8.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:aaa8
set -euo pipefail
echo ok
exit 0
EOF
chmod +x "$repo/tests/test_aaa8.sh"
cat >> "$repo/TODO.md" <<'EOF'
- [ ] we investigated the root cause and shipped the fix <!-- id:aaa8 -->
EOF
commit_line 1 "case8: investigated (not a real gate word), tick-ready"

# --- Case 9: a hanging/non-hermetic discovered test must be BOUNDED, not hang the scan ---
# (strong-model audit run 70 finding 4): TICK-READY runs the discovered test with no
# timeout. Use a short override (ORPHAN_SCAN_TEST_TIMEOUT_S) so this test file itself stays
# fast, and assert the scan finishes promptly and does NOT claim TICK-READY for a test that
# never exits.
cat > "$repo/tests/test_aaa9.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:aaa9
sleep 300
EOF
chmod +x "$repo/tests/test_aaa9.sh"
cat >> "$repo/TODO.md" <<'EOF'
- [ ] feature Q, hanging test <!-- id:aaa9 -->
EOF
commit_line 1 "case9: hanging test, must be bounded"

start_s=$(date +%s)
out="$(HOME="$tmp" ORPHAN_SCAN_TEST_TIMEOUT_S=2 timeout 30 "$ORPHAN" --shipped "$repo")"
elapsed_s=$(( $(date +%s) - start_s ))

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

# Case 6: external-wait word + old -> must NOT appear (the 2026-07-07 lexeme split)
if grep -q 'id:aaa6' <<<"$out"; then
  echo "case6: id:aaa6 (external-wait, old) must NOT be GATE-STALE after the split"; echo "$out"; exit 1
fi

# Case 7: inline test path but no `# roadmap:` owner -> must NOT be TICK-READY
if grep -q 'id:aaa7' <<<"$out"; then
  echo "case7: id:aaa7 (inline-only path, unowned) must NOT be TICK-READY"; echo "$out"; exit 1
fi

# Case 8: "investigated" (substring-contains "gated") must NOT be treated as a gate word —
# must classify TICK-READY, not be silently suppressed as EXTERNAL-WAIT.
grep -q 'id:aaa8' <<<"$out" || { echo "case8: id:aaa8 (investigated, false gate substring) must appear"; echo "$out"; exit 1; }
grep -q 'id:aaa8.*TICK-READY' <<<"$out" || { echo "case8: id:aaa8 must be TICK-READY (word-boundary gate-word fix)"; echo "$out"; exit 1; }

# Case 9: hanging test must be bounded (2s timeout override) — scan must finish well under
# the 300s sleep, and must NOT report id:aaa9 as TICK-READY (a timed-out test is non-green).
if grep -q 'id:aaa9.*TICK-READY' <<<"$out"; then
  echo "case9: id:aaa9 (hanging test) must NOT be TICK-READY"; echo "$out"; exit 1
fi
if [[ "$elapsed_s" -gt 15 ]]; then
  echo "case9: scan took ${elapsed_s}s — the hanging test was not bounded by ORPHAN_SCAN_TEST_TIMEOUT_S"; exit 1
fi

# Report-only: the tool must not have touched TODO.md's checkboxes.
grep -q '^- \[ \] just an open item with no linked test' "$repo/TODO.md" || { echo "TODO.md checkbox for aaa4 was mutated"; exit 1; }
grep -q '^- \[x\] done item, pending forever in prose but closed' "$repo/TODO.md" || { echo "TODO.md checkbox for aaa5 was mutated"; exit 1; }

echo ok
