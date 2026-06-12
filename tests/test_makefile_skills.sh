#!/usr/bin/env bash
# roadmap:1ec1 — Makefile must cover the fables-turn and projects skills:
# install targets (with nested references/ + scripts/ dirs for fables-turn),
# inclusion in SKILLS (install/status/uninstall/help), allowlist generation
# for fables-turn scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
DEST="$tmp/skills"

# install-fables-turn target exists and works into an overridden DEST_DIR
make -C "$ROOT" -s DEST_DIR="$DEST" install-fables-turn \
  || { echo "make install-fables-turn failed or target missing"; exit 1; }

for f in SKILL.md \
         references/handoff.md references/review.md \
         references/conventions.md references/templates.md \
         scripts/discover-repos.sh scripts/ckpt-tag.sh; do
  [[ -L "$DEST/fables-turn/$f" ]] \
    || { echo "missing symlink: fables-turn/$f"; exit 1; }
  [[ -e "$DEST/fables-turn/$f" ]] \
    || { echo "dangling symlink: fables-turn/$f"; exit 1; }
done
[[ -x "$ROOT/fables-turn/scripts/ckpt-tag.sh" ]] \
  || { echo "ckpt-tag.sh not executable after install"; exit 1; }

# install-projects target
make -C "$ROOT" -s DEST_DIR="$DEST" install-projects \
  || { echo "make install-projects failed or target missing"; exit 1; }
[[ -L "$DEST/projects/SKILL.md" ]] \
  || { echo "missing symlink: projects/SKILL.md"; exit 1; }

# Both skills are first-class SKILLS members (help lists them → install/status/uninstall cover them)
help_out="$(make -C "$ROOT" -s help)"
grep -q 'fables-turn' <<<"$help_out" || { echo "make help does not list fables-turn"; exit 1; }
grep -q 'projects'    <<<"$help_out" || { echo "make help does not list projects"; exit 1; }

# status target handles nested paths
make -C "$ROOT" -s DEST_DIR="$DEST" status-fables-turn | grep -q 'references/handoff.md' \
  || { echo "status-fables-turn does not report nested files"; exit 1; }

# uninstall removes the symlinks (and only symlinks)
make -C "$ROOT" -s DEST_DIR="$DEST" uninstall-fables-turn
[[ ! -e "$DEST/fables-turn/SKILL.md" ]] \
  || { echo "uninstall-fables-turn left SKILL.md behind"; exit 1; }

# fables-turn scripts join allowlist generation
grep -qE 'fables-turn_ALLOW.*(ckpt-tag|discover-repos)' "$ROOT/Makefile" \
  || { echo "fables-turn scripts missing from allowlist generation"; exit 1; }

echo ok
