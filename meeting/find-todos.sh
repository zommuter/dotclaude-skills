#!/usr/bin/env bash
# Wrapper: find subdirectory TODO.md files.
# Called from meeting/SKILL.md and todo-update/SKILL.md to avoid
# the glob-in-allowlist permission prompt that fires on the bare find command.
find . -mindepth 2 -maxdepth 3 -name TODO.md \
  -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' -not -path '*/*/.git/*' 2>/dev/null |
while IFS= read -r f; do
  dir=$(dirname "$f")
  [ -e "$dir/.git" ] && continue
  echo "$f"
done
