#!/usr/bin/env bash
# TODO id:148b — Close scoop window (i): atomic ledger write+commit in md-merge.py.
# NOT a ROADMAP item (TODO-id feature) — no `# roadmap:` header, so failures always count.
# Contract (meeting D2, 2026-06-17-0953): after any ledger write-back there is no
# modified-but-uncommitted ledger file left in the main checkout. The --commit flag is
# opt-in, idempotent, scoped (never `git add -A`), and never disturbs a foreign-dirty file.
# Hermetic: a mktemp git repo, no network, no $HOME/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MM="$SRC_DIR/meeting/md-merge.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MM" ]] || fail "md-merge.py not found at $MM"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name Tester

cat > "$repo/TODO.md" <<'EOF'
# TODO
- [ ] first item <!-- id:aa01 -->
- [ ] second item <!-- id:bb02 -->
EOF
git -C "$repo" add TODO.md
git -C "$repo" commit -qm "seed TODO"

base_sha="$(git -C "$repo" rev-parse HEAD)"

# ── Test 1: default (no --commit) writes but does NOT commit ───────────────────
python3 "$MM" update-ids --file "$repo/TODO.md" <<'JSON'
{"updates": [{"id": "aa01", "line": "- [x] first item <!-- id:aa01 -->"}]}
JSON
grep -q '\[x\] first item' "$repo/TODO.md" || fail "default write did not apply"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$base_sha" ]] \
  || fail "default (no --commit) must NOT create a commit"
git -C "$repo" status --porcelain TODO.md | grep -q . \
  || fail "default mode should leave TODO.md modified-but-uncommitted (baseline behaviour)"
pass "default mode writes without committing (backward compatible)"

# Reset for the commit test.
git -C "$repo" checkout -q -- TODO.md

# ── Test 2: --commit commits JUST the edited ledger, leaving a clean tree ──────
python3 "$MM" update-ids --file "$repo/TODO.md" --commit "meeting: close aa01 (id:148b)" <<'JSON'
{"updates": [{"id": "aa01", "line": "- [x] first item <!-- id:aa01 -->"}]}
JSON
grep -q '\[x\] first item' "$repo/TODO.md" || fail "--commit write did not apply"
new_sha="$(git -C "$repo" rev-parse HEAD)"
[[ "$new_sha" != "$base_sha" ]] || fail "--commit did not create a commit"
git -C "$repo" status --porcelain TODO.md | grep -q . \
  && fail "--commit left TODO.md modified-but-uncommitted (scoop window NOT closed)" || true
git -C "$repo" log -1 --pretty=%s | grep -q 'id:148b' \
  || fail "--commit did not use the supplied commit message"
pass "id:148b: --commit commits the ledger atomically — no uncommitted residue"

# ── Test 3: scoped — a concurrent foreign-dirty file is left untouched ─────────
echo "scratch" > "$repo/OTHER.md"   # untracked foreign edit
git -C "$repo" add OTHER.md         # stage it to simulate a concurrent editor's index
python3 "$MM" update-ids --file "$repo/TODO.md" --commit "meeting: close bb02 (id:148b)" <<'JSON'
{"updates": [{"id": "bb02", "line": "- [x] second item <!-- id:bb02 -->"}]}
JSON
# The commit must contain ONLY TODO.md, never OTHER.md (no git add -A).
files="$(git -C "$repo" show --name-only --pretty=format: HEAD | grep -v '^$' || true)"
[[ "$files" == "TODO.md" ]] \
  || fail "id:148b/debf: commit captured more than TODO.md (scoped staging violated): [$files]"
# OTHER.md must still be staged-but-uncommitted (foreign edit preserved, not scooped).
git -C "$repo" diff --cached --name-only | grep -q '^OTHER.md$' \
  || fail "foreign staged file OTHER.md was disturbed by the scoped commit"
pass "id:148b: commit is scoped to the named ledger — foreign edit untouched"

# ── Test 4: idempotent clean no-op (no change → no new commit) ─────────────────
sha_before="$(git -C "$repo" rev-parse HEAD)"
python3 "$MM" update-ids --file "$repo/TODO.md" --commit "meeting: no-op (id:148b)" <<'JSON'
{"updates": [{"id": "bb02", "line": "- [x] second item <!-- id:bb02 -->"}]}
JSON
[[ "$(git -C "$repo" rev-parse HEAD)" == "$sha_before" ]] \
  || fail "id:148b: --commit made a commit when nothing changed (not idempotent)"
pass "id:148b: --commit is idempotent (clean no-op when unchanged)"

# ── Test 5: non-fatal outside a git repo (write still succeeds) ────────────────
mkdir -p "$tmp/nogit"
cat > "$tmp/nogit/TODO.md" <<'EOF'
# TODO
- [ ] lone item <!-- id:cc03 -->
EOF
python3 "$MM" update-ids --file "$tmp/nogit/TODO.md" --commit "should-skip (id:148b)" <<'JSON'
{"updates": [{"id": "cc03", "line": "- [x] lone item <!-- id:cc03 -->"}]}
JSON
grep -q '\[x\] lone item' "$tmp/nogit/TODO.md" \
  || fail "id:148b: write must still succeed even when commit is skipped (not a git repo)"
pass "id:148b: --commit is non-fatal outside a git repo (write preserved)"

echo "ALL PASS: md-merge.py atomic ledger write+commit (id:148b)"
