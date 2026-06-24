#!/usr/bin/env bash
# roadmap:2147 — atomic per-repo commit of a main-checkout relay ledger edit.
# The gate-detection (id:3801) + /relay review|human prose write ROADMAP/TODO/
# REVIEW_ME in the MAIN checkout; an interrupted run left those edits dirty-
# uncommitted, tripping the dirty-guard (id:aa93) so the pool deferred the repo
# forever. commit-ledger.sh makes each such write commit atomically (or leave
# the tree untouched) — never dirty-uncommitted.
#
# Hermetic: temp git repo under mktemp; no ~/.claude, no network, no push.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/relay/scripts/commit-ledger.sh"

fail=0
ok()  { echo "  ok  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -x "$HELPER" ] || { echo "commit-ledger.sh missing/not-executable: $HELPER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@e.x
git -C "$REPO" config user.name t
printf '# ROADMAP\n\n- [ ] [HARD — pool] thing <!-- id:aaaa -->\n' > "$REPO/ROADMAP.md"
printf '# TODO\n\n- [ ] a todo <!-- id:aaaa -->\n' > "$REPO/TODO.md"
printf 'code\n' > "$REPO/unrelated.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

echo "== 1. a scoped ledger edit commits atomically (tree clean after) =="
# Simulate gate-detection: re-tag the ROADMAP item in the main checkout.
sed -i 's/\[HARD — pool\]/[HARD — decision gate]/' "$REPO/ROADMAP.md"
"$HELPER" "$REPO" -m "roadmap: gate id:aaaa (id:3801)" ROADMAP.md >/dev/null 2>&1
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then ok "tree clean after commit (no dirty residue)"; else bad "tree still dirty after commit: $(git -C "$REPO" status --porcelain)"; fi
if git -C "$REPO" log -1 --pretty=%s | grep -qF 'gate id:aaaa'; then ok "commit landed with the message"; else bad "commit message missing"; fi
if git -C "$REPO" show --stat HEAD | grep -qF 'ROADMAP.md'; then ok "ROADMAP.md is in the commit"; else bad "ROADMAP.md not committed"; fi

echo "== 2. an UNRELATED concurrent edit is left untouched (scoped stage, no git add -A) =="
sed -i 's/\[HARD — decision gate\]/[HARD — pool]/' "$REPO/ROADMAP.md"   # another ledger edit
printf 'concurrent foreign work\n' >> "$REPO/unrelated.txt"            # foreign dirty, NOT a ledger
"$HELPER" "$REPO" -m "roadmap: revert gate (id:3801)" ROADMAP.md >/dev/null 2>&1
# the foreign file must STILL be dirty + uncommitted (never swept into the commit, never stashed)
if git -C "$REPO" status --porcelain | grep -q 'unrelated.txt'; then ok "foreign unrelated.txt left dirty (not staged/committed/stashed)"; else bad "foreign edit was swallowed (git add -A / stash hazard)"; fi
if ! git -C "$REPO" show --stat HEAD | grep -qF 'unrelated.txt'; then ok "unrelated.txt NOT in the ledger commit"; else bad "unrelated.txt leaked into the scoped commit"; fi
if git -C "$REPO" show --stat HEAD | grep -qF 'ROADMAP.md'; then ok "only ROADMAP.md committed"; else bad "ROADMAP edit not committed"; fi
# no stash was created (id:aa93: never stash a foreign-dirty tree)
if [ -z "$(git -C "$REPO" stash list)" ]; then ok "no stash created (foreign work not swept)"; else bad "a stash was created — foreign-dirty sweep (id:aa93 violation)"; fi
# clean up the foreign edit so later cases start clean
git -C "$REPO" checkout -- unrelated.txt

echo "== 3. multi-file ledger commit (ROADMAP + TODO together) =="
sed -i 's/a todo/a todo (gated)/' "$REPO/TODO.md"
sed -i 's/\[HARD — pool\]/[HARD — decision gate]/' "$REPO/ROADMAP.md"
"$HELPER" "$REPO" -m "ledger: sync id:aaaa across ROADMAP+TODO" ROADMAP.md TODO.md >/dev/null 2>&1
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then ok "both ledgers committed, tree clean"; else bad "residue after multi-file commit"; fi
if git -C "$REPO" show --stat HEAD | grep -qF 'TODO.md' && git -C "$REPO" show --stat HEAD | grep -qF 'ROADMAP.md'; then ok "both files in one commit"; else bad "multi-file commit incomplete"; fi

echo "== 4. clean no-op when the named ledger has no change =="
before="$(git -C "$REPO" rev-parse HEAD)"
"$HELPER" "$REPO" -m "ledger: nothing to do" ROADMAP.md >/dev/null 2>&1
rc=$?
after="$(git -C "$REPO" rev-parse HEAD)"
if [ "$before" = "$after" ]; then ok "no empty commit created"; else bad "an empty commit was made"; fi
if [ "$rc" = 0 ]; then ok "clean no-op exits 0"; else bad "no-op exited nonzero ($rc)"; fi

echo "== 5. absolute ledger path is accepted (resolved repo-relative) =="
sed -i 's/\[HARD — decision gate\]/[HARD — pool]/' "$REPO/ROADMAP.md"
"$HELPER" "$REPO" -m "ledger: abs path" "$REPO/ROADMAP.md" >/dev/null 2>&1
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then ok "absolute path committed, tree clean"; else bad "absolute path not handled"; fi

echo "== 6. misuse is a loud nonzero (no commit message) =="
sed -i 's/\[HARD — pool\]/[HARD — decision gate]/' "$REPO/ROADMAP.md"
if "$HELPER" "$REPO" ROADMAP.md >/dev/null 2>&1; then bad "missing -m did not fail"; else ok "missing -m exits nonzero"; fi
# the ledger stays as the caller left it (dirty) — misuse never half-commits
if git -C "$REPO" status --porcelain | grep -q 'ROADMAP.md'; then ok "misuse left the edit uncommitted (no partial commit)"; else bad "misuse mutated the commit graph"; fi
git -C "$REPO" checkout -- ROADMAP.md

echo "== 7. a path escaping the repo root is rejected =="
if "$HELPER" "$REPO" -m "evil" ../escape.md >/dev/null 2>&1; then bad "path traversal not rejected"; else ok "out-of-repo path rejected"; fi

echo "== 8. the helper NEVER USES destructive git verbs (static guard, id:aa93) =="
# Strip comment lines first — the header documents the prohibition in prose;
# the guard is about CODE that runs, not the doc that explains it.
if grep -vE '^[[:space:]]*#' "$HELPER" | grep -Eq 'git[[:space:]]+(stash|reset|clean)\b|checkout[[:space:]]+--|git[[:space:]]+add[[:space:]]+-A\b'; then
  bad "helper USES a destructive/blanket git verb (stash/reset/clean/checkout --/add -A)"
else
  ok "no stash/reset/clean/checkout --/add -A in executable code"
fi

echo "== 9. wired into the relay prose (review.md + human.md reference commit-ledger) =="
for doc in references/review.md references/human.md; do
  if grep -qF 'commit-ledger.sh' "$ROOT/relay/$doc"; then ok "$doc calls commit-ledger.sh after a main-checkout ledger edit"; else bad "$doc does not wire commit-ledger.sh"; fi
done

echo "== 10. registered in the Makefile install manifest =="
# Extract each VAR := ... (continuation lines end with a backslash) and check membership.
block() { awk -v v="$1" '
  $0 ~ "^"v"[[:space:]]*:?=" { inblk=1 }
  inblk { print; if ($0 !~ /\\[[:space:]]*$/) exit }
' "$ROOT/Makefile"; }
for var in relay_FILES relay_EXEC relay_ALLOW; do
  if block "$var" | grep -qF 'commit-ledger.sh'; then
    ok "$var lists commit-ledger.sh"
  else
    bad "$var missing commit-ledger.sh"
  fi
done

echo
[ "$fail" -eq 0 ] && echo "test_relay_commit_ledger: PASS" || echo "test_relay_commit_ledger: FAIL"
exit "$fail"
