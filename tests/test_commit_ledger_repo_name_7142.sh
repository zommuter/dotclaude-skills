#!/usr/bin/env bash
# roadmap:7142 — commit-ledger.sh accepts a bare repo NAME (resolved via the canonical
# own-repo registry, relay/scripts/lib-own-repos.sh) IN ADDITION TO a path, so the
# invocation documented in relay/references/human.md §5 (`commit-ledger.sh <repo> ...`)
# actually works instead of hard-failing with "not a git repo". Path behaviour (relative,
# absolute, `.`) is unchanged — an existing directory is still treated as a path.
#
# Decided-here option (a): fix the SCRIPT, not the doc — every other relay front door takes
# a repo name, so `commit-ledger.sh` was the outlier. Resolution honours the canonical
# own-repo set (classification="own", `# path:` comment override, paused-skip) — never a
# re-derived `~/src/*` glob.
#
# Hermetic: mktemp'd fixture repos + a fixture relay.toml; RELAY_TOML/SRC_DIR/HOME
# overridden; never touches the real registry or ~/.claude.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/relay/scripts/commit-ledger.sh"

fail=0
ok()  { echo "  ok  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -x "$HELPER" ] || { echo "commit-ledger.sh missing/not-executable: $HELPER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
SRC="$TMP/src"; mkdir -p "$SRC"
export SRC_DIR="$SRC"

mk_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@e.x
  git -C "$dir" config user.name t
  printf '# ROADMAP\n\n- [ ] [ROUTINE] thing <!-- id:bbbb -->\n' > "$dir/ROADMAP.md"
  printf '# TODO\n' > "$dir/TODO.md"
  printf '# REVIEW_ME\n' > "$dir/REVIEW_ME.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
}

echo "== 1. bare NAME resolves via relay.toml's own-repo registry (the human.md §5 invocation form) =="
REPO_A="$SRC/repo_a"
mk_repo "$REPO_A"
export RELAY_TOML="$TMP/relay.toml"
cat > "$RELAY_TOML" <<EOF
[repos.repo_a]
classification = "own"
EOF
sed -i 's/\[ROUTINE\]/[ROUTINE] (gated)/' "$REPO_A/ROADMAP.md"
"$HELPER" repo_a -m "relay human: ledger flow-back (id:3801, id:2147)" ROADMAP.md TODO.md REVIEW_ME.md >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ]; then ok "documented invocation with a bare name exits 0"; else bad "documented invocation with a bare name failed (rc=$rc)"; fi
if grep -qF 'ledger flow-back' < <(git -C "$REPO_A" log -1 --pretty=%s 2>/dev/null) ; then ok "commit landed in the name-resolved repo"; else bad "no commit landed in repo_a"; fi
if [ -z "$(git -C "$REPO_A" status --porcelain 2>/dev/null)" ]; then ok "repo_a tree clean after name-resolved commit"; else bad "repo_a still dirty"; fi

echo "== 2. an existing directory PATH is still treated as a path, unchanged (no registry lookup) =="
REPO_B="$TMP/plain_path_repo"
mk_repo "$REPO_B"
sed -i 's/\[ROUTINE\]/[ROUTINE] (gated)/' "$REPO_B/ROADMAP.md"
"$HELPER" "$REPO_B" -m "path arg unchanged" ROADMAP.md >/dev/null 2>&1
if [ -z "$(git -C "$REPO_B" status --porcelain 2>/dev/null)" ]; then ok "absolute path still commits directly (no regression)"; else bad "absolute path regressed"; fi

echo "== 3. relative path '.' still works from inside the repo =="
REPO_C="$TMP/dot_repo"
mk_repo "$REPO_C"
sed -i 's/\[ROUTINE\]/[ROUTINE] (gated)/' "$REPO_C/ROADMAP.md"
( cd "$REPO_C" && "$HELPER" . -m "dot path unchanged" ROADMAP.md >/dev/null 2>&1 )
if [ -z "$(git -C "$REPO_C" status --porcelain 2>/dev/null)" ]; then ok "'.' path still commits directly (no regression)"; else bad "'.' path regressed"; fi

echo "== 4. a name that resolves to nothing fails LOUDLY, naming the name AND the registry =="
err="$("$HELPER" no_such_repo -m "x" ROADMAP.md 2>&1 >/dev/null)"
rc=$?
if [ "$rc" != 0 ]; then ok "unresolvable name exits nonzero"; else bad "unresolvable name did not fail"; fi
if grep -qF 'no_such_repo' < <(printf '%s' "$err") ; then ok "error names the unresolved repo name"; else bad "error does not name the repo name: $err"; fi
if grep -qF "$RELAY_TOML" < <(printf '%s' "$err") ; then ok "error names the registry it was looked up in"; else bad "error does not name the registry: $err"; fi
if grep -qiF 'not a git repo:' < <(printf '%s' "$err") ; then bad "error is the old bare 'not a git repo' message (doc/script drift not fixed)"; else ok "error is not the old bare 'not a git repo' message"; fi

echo "== 5. a repo carrying a '# path:' override resolves via the override, not ~/src/<name> =="
REPO_D="$TMP/elsewhere/actual_repo_d"
mk_repo "$REPO_D"
cat >> "$RELAY_TOML" <<EOF

[repos.repo_d]
# path: $REPO_D
classification = "own"
EOF
sed -i 's/\[ROUTINE\]/[ROUTINE] (gated)/' "$REPO_D/ROADMAP.md"
"$HELPER" repo_d -m "path-override resolved" ROADMAP.md >/dev/null 2>&1
if [ -z "$(git -C "$REPO_D" status --porcelain 2>/dev/null)" ]; then ok "# path: override resolved and committed"; else bad "# path: override not honoured"; fi

echo
[ "$fail" -eq 0 ] && echo "test_commit_ledger_repo_name_7142: PASS" || echo "test_commit_ledger_repo_name_7142: FAIL"
exit "$fail"
