#!/usr/bin/env bash
# roadmap:e875 — RED spec for memory-index.py resolving title:/hook: even when a
# writer has re-nested them under `metadata:` (observed twice 2026-07-17).
#
# When title:/hook: are relocated under metadata:, build_entries' top-level
# `fm.get("title")`/`fm.get("hook")` miss them and SILENTLY fall back to the file
# stem (name) and description (hook) — a verbose, wrong index line with no error.
#
# Spec (robust regardless of which writer re-nests, since some candidates are
# uncontrollable):
#   (a) resolve title:/hook: from `metadata.*` when absent at top level, and
#   (b) warn LOUDLY (stderr) when a file has metadata.hook but no top-level hook
#       ([[no-swallow-stderr]]) — never a silent description substitution.
# Hermetic: everything in a mktemp -d; the real ~/.claude memory dir is untouched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/memory-index.py"
[[ -f "$TOOL" ]] || { echo "FAIL: memory-index.py not found at $TOOL"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/sample.md" <<'EOF'
---
metadata:
  title: My Nice Title
  hook: "user: the terse hook line"
  type: project
description: "a much longer verbose description that should NOT be the hook"
---
body
EOF

rc=0
stderr="$TMP/err.txt"
python3 "$TOOL" --dir "$TMP" --write 2>"$stderr"
index="$TMP/MEMORY.md"
line="$(grep 'sample.md' "$index" 2>/dev/null || true)"

# (a) resolution — the metadata-nested hook and title must WIN over description/stem.
if ! printf '%s' "$line" | grep -qF 'the terse hook line'; then
  echo "FAIL: hook must resolve from metadata.hook, got line: $line"
  rc=1
fi
if printf '%s' "$line" | grep -qF 'should NOT be the hook'; then
  echo "FAIL: description leaked into the hook — metadata.hook was ignored: $line"
  rc=1
fi
if ! printf '%s' "$line" | grep -qF 'My Nice Title'; then
  echo "FAIL: display title must resolve from metadata.title (not the file stem): $line"
  rc=1
fi

# (b) loud fallback — a metadata-only hook must produce a stderr warning naming the file.
if ! grep -qi 'sample.md' "$stderr" || ! grep -qi 'hook' "$stderr"; then
  echo "FAIL: expected a LOUD stderr warning naming sample.md + 'hook' when hook lives"
  echo "      only under metadata:; got stderr:"
  sed 's/^/      | /' "$stderr"
  rc=1
fi

(( rc == 0 )) && echo "PASS: memory-index resolves metadata-nested title:/hook: and warns loudly"
exit "$rc"
