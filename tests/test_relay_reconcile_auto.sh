#!/usr/bin/env bash
# roadmap:7809 — auto-reconcile-on-restart: `relay-reconcile.sh --auto`. The CONSERVATIVE
# classifier auto-INTEGRATES a ledger-only orphan (via the SAME --no-ff+ckpt-tag+--ff-only
# recipe) but PARKS + SURFACES (REVIEW_ME.md) any code diff / dirty tree / empty-or-unrelated
# diff — the bar is never weaker than a human `/relay review` (meeting 2026-06-22). Hermetic:
# tmp git repos, push stubbed (no network), no ~/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/relay-reconcile.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not found/executable at $SCRIPT"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub the push so integrate never touches a network/remote (the recipe is otherwise real).
STUB="$TMP/true-stub.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"
export RELAY_LOCK_PUSH="$STUB"
export RECONCILE_LOG=/dev/null

# Build a repo with main + an initial commit, and a couple of parked orphans.
mk_repo() {
  local r="$1"; git init -q -b main "$r"
  ( cd "$r" \
    && printf '# ROADMAP\n\n- [ ] item\n' > ROADMAP.md \
    && printf '# Human review queue\n\n' > REVIEW_ME.md \
    && printf 'print("hi")\n' > app.py \
    && git add -A && git commit -qm init )
}

# Park a ledger-only orphan (touches only ROADMAP.md) → SAFE.
park_ledger_orphan() {
  local r="$1" name="$2"
  git -C "$r" branch "relay/orphan/$name" main
  git -C "$r" worktree add -q "$TMP/wt-$name" "relay/orphan/$name" >/dev/null 2>&1
  ( cd "$TMP/wt-$name" && printf -- '- [ ] another ledger item\n' >> ROADMAP.md \
    && git add ROADMAP.md && git commit -qm "ledger-only edit" )
  git -C "$r" worktree remove --force "$TMP/wt-$name"
}

# Park a code orphan (touches a .py file) → JUDGMENT.
park_code_orphan() {
  local r="$1" name="$2"
  git -C "$r" branch "relay/orphan/$name" main
  git -C "$r" worktree add -q "$TMP/wt-$name" "relay/orphan/$name" >/dev/null 2>&1
  ( cd "$TMP/wt-$name" && printf 'print("changed")\n' > app.py \
    && git add app.py && git commit -qm "code edit" )
  git -C "$r" worktree remove --force "$TMP/wt-$name"
}

# ── SAFE (ledger-only) is auto-integrated; JUDGMENT (code) is parked + surfaced ──
R1="$TMP/r1"; mk_repo "$R1"
park_ledger_orphan "$R1" ledger-a
park_code_orphan   "$R1" code-b
out="$(bash "$SCRIPT" "$R1" --auto)"
echo "$out" | grep -q "1 integrated, 1 surfaced" || fail "auto summary wrong: $out"
git -C "$R1" rev-parse -q --verify refs/heads/relay/orphan/ledger-a >/dev/null \
  && fail "SAFE ledger orphan was NOT integrated (ref still present)"
git -C "$R1" rev-parse -q --verify refs/heads/relay/orphan/code-b >/dev/null \
  || fail "JUDGMENT code orphan was wrongly consumed (should stay parked)"
grep -q "another ledger item" "$R1/ROADMAP.md" || fail "ledger orphan content not merged to main"
grep -q "code-b" "$R1/REVIEW_ME.md" || fail "code orphan was not surfaced into REVIEW_ME.md"
grep -Eq "^- \[ \] auto-reconcile parked orphan .*code-b" "$R1/REVIEW_ME.md" \
  || fail "REVIEW_ME surface is not an open '- [ ]' box"
[[ -z "$(git -C "$R1" status --porcelain)" ]] || fail "auto-reconcile left the main tree dirty"
pass "ledger-only orphan auto-integrated; code orphan parked + surfaced as an open box (id:7809)"

# ── a dirty main tree defers ALL integration (surfaces instead of auto-merging) ──
R2="$TMP/r2"; mk_repo "$R2"
park_ledger_orphan "$R2" ledger-c
printf 'dirty\n' >> "$R2/app.py"   # make main dirty (a foreign uncommitted edit)
out2="$(bash "$SCRIPT" "$R2" --auto)"
echo "$out2" | grep -q "0 integrated, 1 surfaced" || fail "dirty-tree auto summary wrong: $out2"
git -C "$R2" rev-parse -q --verify refs/heads/relay/orphan/ledger-c >/dev/null \
  || fail "dirty tree wrongly consumed the orphan (must stay parked)"
git -C "$R2" checkout -- app.py
grep -q "ledger-c" "$R2/REVIEW_ME.md" || fail "dirty-tree orphan not surfaced"
pass "a dirty main tree defers integration — SAFE orphan parked + surfaced, not merged (id:7809)"

# ── an empty/unrelated diff is surfaced, never silently consumed ──
R3="$TMP/r3"; mk_repo "$R3"
git -C "$R3" branch relay/orphan/empty-d main   # no commits beyond main → empty diff
out3="$(bash "$SCRIPT" "$R3" --auto)"
echo "$out3" | grep -q "0 integrated, 1 surfaced" || fail "empty-diff auto summary wrong: $out3"
git -C "$R3" rev-parse -q --verify refs/heads/relay/orphan/empty-d >/dev/null \
  || fail "empty-diff orphan wrongly consumed"
grep -q "empty-d" "$R3/REVIEW_ME.md" || fail "empty-diff orphan not surfaced"
pass "empty/unrelated-diff orphan is surfaced, never auto-consumed (id:7809)"

# ── no orphans → benign no-op ──
R4="$TMP/r4"; mk_repo "$R4"
out4="$(bash "$SCRIPT" "$R4" --auto)"
echo "$out4" | grep -q "no parked orphans" || fail "no-orphan repo did not report cleanly: $out4"
pass "a repo with no parked orphans is a benign no-op (id:7809)"

echo "ALL PASS: relay auto-reconcile-on-restart classifier + integrate/surface (id:7809)"
