#!/usr/bin/env bash
# roadmap:a7a3 — ckpt-tag.sh must degrade gracefully when .gitattributes is unaddable.
#
# Observed 2026-06-30 reviewing kienzler-homepage: a `.gitignore` `.*` dotfile catch-all
# swallowed `.gitattributes`, so ckpt-tag's `git add -- RELAY_LOG.md .gitattributes`
# exited non-zero and (under set -e) aborted the WHOLE checkpoint — no commit, no tag,
# RELAY_LOG.md left staged. The `RELAY_LOG.md merge=union` attribute is a nicety (only
# matters for parallel relay merges), not essential: a repo that can't track it must
# still get its checkpoint. This test pins the graceful-degradation behaviour and is RED
# until ckpt-tag.sh tolerates an unaddable .gitattributes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CKPT="$REPO_ROOT/relay/scripts/ckpt-tag.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
work="$tmpdir/work"
git init -q "$work"
git -C "$work" config user.email "test@test"
git -C "$work" config user.name "Test"
# .gitignore catch-all that swallows every dotfile, INCLUDING .gitattributes.
printf '.*\n' > "$work/.gitignore"
echo init > "$work/README"
git -C "$work" add README
git -C "$work" add -f .gitignore   # the .* catch-all ignores .gitignore itself
git -C "$work" commit -q -m init

# ckpt-tag.sh must NOT abort just because .gitattributes can't be staged.
set +e
tag="$("$CKPT" "$work" -m "degrade summary paragraph" -l "reviewer (test)" 2>"$tmpdir/err")"
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  ok "ckpt-tag.sh exited 0 despite unaddable .gitattributes"
else
  bad "ckpt-tag.sh aborted (exit $rc) when .gitattributes could not be staged"
  echo "    stderr: $(cat "$tmpdir/err")"
fi

case "$tag" in
  relay-ckpt-*) ok "a checkpoint tag was still produced ($tag)" ;;
  *)            bad "no relay-ckpt-* tag produced (got: '${tag:-<empty>}')" ;;
esac

# The checkpoint commit must exist and contain the RELAY_LOG.md entry.
if [[ -n "$tag" ]] && git -C "$work" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  if git -C "$work" show "$tag:RELAY_LOG.md" 2>/dev/null | grep -q "degrade summary paragraph"; then
    ok "RELAY_LOG.md entry was committed on the checkpoint"
  else
    bad "checkpoint commit is missing the RELAY_LOG.md entry"
  fi
else
  bad "tag does not resolve to a commit"
fi

# The working tree must not be left with RELAY_LOG.md staged-but-uncommitted residue.
if git -C "$work" diff --cached --quiet -- RELAY_LOG.md; then
  ok "no staged RELAY_LOG.md residue left behind"
else
  bad "RELAY_LOG.md left staged (the abort-mid-checkpoint residue)"
fi

echo
echo "  ckpt-gitattributes-degrade: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
