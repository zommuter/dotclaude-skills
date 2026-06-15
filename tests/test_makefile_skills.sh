#!/usr/bin/env bash
# roadmap:1ec1 — Makefile must cover the relay and projects skills:
# install targets (with nested references/ + scripts/ dirs for relay),
# inclusion in SKILLS (install/status/uninstall/help), allowlist generation
# for relay scripts. Plus the deprecated fables-turn / fables-executor alias stubs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
DEST="$tmp/skills"

# install-relay target exists and works into an overridden DEST_DIR
make -C "$ROOT" -s DEST_DIR="$DEST" install-relay \
  || { echo "make install-relay failed or target missing"; exit 1; }

for f in SKILL.md \
         references/handoff.md references/review.md \
         references/conventions.md references/templates.md \
         references/executor-contract.md \
         scripts/discover-repos.sh scripts/ckpt-tag.sh; do
  [[ -L "$DEST/relay/$f" ]] \
    || { echo "missing symlink: relay/$f"; exit 1; }
  [[ -e "$DEST/relay/$f" ]] \
    || { echo "dangling symlink: relay/$f"; exit 1; }
done
[[ -x "$ROOT/relay/scripts/ckpt-tag.sh" ]] \
  || { echo "ckpt-tag.sh not executable after install"; exit 1; }

# install-projects target
make -C "$ROOT" -s DEST_DIR="$DEST" install-projects \
  || { echo "make install-projects failed or target missing"; exit 1; }
[[ -L "$DEST/projects/SKILL.md" ]] \
  || { echo "missing symlink: projects/SKILL.md"; exit 1; }

# relay is a first-class SKILLS member (help lists it → install/status/uninstall cover it)
help_out="$(make -C "$ROOT" -s help)"
grep -q 'relay'    <<<"$help_out" || { echo "make help does not list relay"; exit 1; }
grep -q 'projects' <<<"$help_out" || { echo "make help does not list projects"; exit 1; }

# status target handles nested paths
make -C "$ROOT" -s DEST_DIR="$DEST" status-relay | grep -q 'references/handoff.md' \
  || { echo "status-relay does not report nested files"; exit 1; }

# uninstall removes the symlinks (and only symlinks)
make -C "$ROOT" -s DEST_DIR="$DEST" uninstall-relay
[[ ! -e "$DEST/relay/SKILL.md" ]] \
  || { echo "uninstall-relay left SKILL.md behind"; exit 1; }

# relay scripts join allowlist generation
grep -qE 'relay_ALLOW.*(ckpt-tag|discover-repos)' "$ROOT/Makefile" \
  || { echo "relay scripts missing from allowlist generation"; exit 1; }

# Deprecated alias stubs still install (so in-flight invocations/cron/pointers survive)
for alias in fables-turn fables-executor; do
  make -C "$ROOT" -s DEST_DIR="$DEST" install-$alias \
    || { echo "make install-$alias (deprecated alias) failed or target missing"; exit 1; }
  [[ -L "$DEST/$alias/SKILL.md" && -e "$DEST/$alias/SKILL.md" ]] \
    || { echo "alias $alias/SKILL.md not symlinked"; exit 1; }
  grep -qi 'deprecated' "$ROOT/$alias/SKILL.md" \
    || { echo "alias $alias/SKILL.md does not say DEPRECATED"; exit 1; }
done

echo ok
