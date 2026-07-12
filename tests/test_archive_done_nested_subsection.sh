#!/usr/bin/env bash
# roadmap:0f7a — archive-done.sh must NOT prune a '## section' header as empty when
# its tasks live under a nested '### subsection'. The pruner splits into segments on
# ANY heading level >= 2 (## AND ###), so a '### subsection' starts its OWN segment
# and the parent '## section' is left with an empty body → pruned, orphaning the
# tasks under it (recurred twice on it-infra's '## Backup & storage strategy',
# 2026-07-11). A section whose nested subsections carry task lines is NOT empty.
#
# INBOUND routed:8b23 from it-infra. RED until id:0f7a ships.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/todo-update/archive-done.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name tester

todo="$repo/TODO.md"
{
  echo '# TODO'
  echo
  echo '## Backup & storage strategy'
  echo
  echo '### Nightly snapshots'
  echo '- [ ] configure snapshot retention window'
  echo '- [ ] verify off-site replication'
  echo
  echo '## Current'
  echo
  # padding to clear the >=50-line archive threshold
  for k in $(seq 1 60); do echo "- [ ] filler open item $k"; done
} > "$todo"

git -C "$repo" add TODO.md
git -C "$repo" commit -qm 'seed TODO with a section whose tasks live under a ### subsection'

( cd "$repo" && HOME="$tmp" bash "$SCRIPT" "$todo" ) >/dev/null 2>&1 || {
  echo "archive-done.sh exited non-zero"; exit 1; }

# 1) The parent '## section' header must survive — its nested subsection has tasks.
grep -q '^## Backup & storage strategy' "$todo" \
  || { echo "FAIL: '## Backup & storage strategy' was pruned despite nested-subsection tasks"; exit 1; }

# 2) The nested subsection + its tasks must survive too.
grep -q '^### Nightly snapshots' "$todo" \
  || { echo "FAIL: '### Nightly snapshots' subsection was dropped"; exit 1; }
grep -q 'configure snapshot retention window' "$todo" \
  || { echo "FAIL: task under the nested subsection was orphaned/dropped"; exit 1; }

echo ok
