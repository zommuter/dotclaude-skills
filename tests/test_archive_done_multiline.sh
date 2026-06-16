#!/usr/bin/env bash
# (no roadmap token — defect-fix test for cross-project inbox item routed:0076.
#  archive-done.sh is line-oriented and used to orphan a [x] bullet's indented
#  continuation lines (sub-bullets / wrapped prose) when it archived only the
#  header line. This test always counts.)
#
# A multi-line [x] bullet must move to TODO.archive.md as ONE UNIT: header line
# plus all its indented continuation lines. Nothing must be left orphaned in the
# source sections, and unrelated open ([ ]) bullets + their continuations stay.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/todo-update/archive-done.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A self-contained git repo so the prior-commit gate has a HEAD to compare to.
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name tester

# >=50 lines so archiving is enabled. The [x] item is "done in the prior commit"
# (count-based gate): we commit it as-is, then archive against that HEAD.
todo="$repo/TODO.md"
{
  echo '# TODO'
  echo
  echo '## Current'
  echo
  echo '- [ ] open multi-line bullet'
  echo '  - sub-bullet of the open item (must stay)'
  echo '    wrapped prose under the open item (must stay)'
  echo '- [x] done multi-line bullet'
  echo '  - first sub-bullet of the done item'
  echo '    wrapped continuation prose for the done item'
  echo '  - second sub-bullet of the done item'
  echo '- [ ] another open single-line bullet'
  # padding to clear the >=50-line archive threshold
  for k in $(seq 1 60); do echo "- [ ] filler open item $k"; done
} > "$todo"

git -C "$repo" add TODO.md
git -C "$repo" commit -qm 'seed TODO with a done multi-line bullet'

# archive-done.sh derives the prior-commit gate via `git rev-parse` in the cwd,
# so run it from inside the fixture repo.
( cd "$repo" && HOME="$tmp" bash "$SCRIPT" "$todo" ) >/dev/null 2>&1 || {
  echo "archive-done.sh exited non-zero"; exit 1; }

arch="$repo/TODO.archive.md"
[[ -f "$arch" ]] || { echo "TODO.archive.md was not created"; exit 1; }

# 1) The done header line moved.
grep -q 'done multi-line bullet' "$arch" \
  || { echo "done header not archived"; exit 1; }

# 2) Its continuation lines moved WITH it (the core bug).
for frag in \
  'first sub-bullet of the done item' \
  'wrapped continuation prose for the done item' \
  'second sub-bullet of the done item'; do
  grep -qF "$frag" "$arch" \
    || { echo "continuation line not archived: $frag"; echo "--- archive ---"; cat "$arch"; exit 1; }
done

# 3) No orphaned fragments left behind in TODO.md.
for frag in \
  'done multi-line bullet' \
  'first sub-bullet of the done item' \
  'wrapped continuation prose for the done item' \
  'second sub-bullet of the done item'; do
  if grep -qF "$frag" "$todo"; then
    echo "orphaned fragment left in TODO.md: $frag"; echo "--- todo ---"; cat "$todo"; exit 1
  fi
done

# 4) The OPEN multi-line bullet and its continuations are untouched.
for frag in \
  'open multi-line bullet' \
  'sub-bullet of the open item (must stay)' \
  'wrapped prose under the open item (must stay)' \
  'another open single-line bullet'; do
  grep -qF "$frag" "$todo" \
    || { echo "open bullet content wrongly removed: $frag"; echo "--- todo ---"; cat "$todo"; exit 1; }
done

# 5) Open content must NOT have leaked into the archive.
if grep -qF 'open multi-line bullet' "$arch"; then
  echo "open bullet wrongly archived"; exit 1
fi

echo ok
