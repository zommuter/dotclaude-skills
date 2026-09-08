#!/usr/bin/env bash
# tests/lib-workflow-check.sh -- Workflow-aware `node --check` for relay/scripts/relay-loop.js
# (id:62c9; decision + measured prototype: docs/ledger-notes/62c9.md).
#
# relay-loop.js is a Workflow script: the runtime wraps its whole body in an async function,
# so top-level `await` and top-level `return` are BOTH legal where it actually executes. It
# also carries exactly one ESM construct -- `export const meta = {` on line 1 -- and zero
# `import` statements. A bare `node --check` has no such wrapper and must pick a module goal:
# top-level `return` alone parses as CommonJS, top-level `await` alone is detected as ESM, and
# a file with BOTH parses under neither (SyntaxError). The owner ruled: repair the instrument,
# not the source -- relay-loop.js is not to be restructured.
#
# workflow_node_check <file> models the runtime by wrapping the source in an async function
# and stripping a line-1 `export`, then runs `node --check` on the wrapped copy. It exits 0 on
# a clean parse and non-zero otherwise -- either because node --check itself rejected the
# wrapped source (a genuine syntax error), or because this function REFUSED to wrap the file
# at all (see below). Source this file, then call the function; nothing else is exported.

workflow_node_check() {
  local f="$1"

  if [[ ! -f "$f" ]]; then
    echo "workflow_node_check: no such file: $f" >&2
    return 1
  fi

  # Refuse LOUDLY -- rather than silently mis-model -- a file that carries a line-initial
  # `export `/`import ` on any line OTHER than line 1. The wrapper only strips a line-1
  # `export`; a real ESM module scope (a genuine import, or export declarations scattered
  # through the file) is outside what an async-function wrapper can model at all, and
  # wrapping it anyway would silently produce a false parse verdict. Anchored to
  # line-initial (start of line, only leading whitespace before the keyword, then a space)
  # so a mid-line mention inside a string or a comment (`// import fs from ...`, a quoted
  # `"export const x = 1;"`) never trips this -- those are not module constructs.
  local bad_line
  bad_line="$(awk 'NR>1 && /^[[:space:]]*(export|import)[[:space:]]/ { print NR; exit }' "$f")"
  if [[ -n "$bad_line" ]]; then
    echo "workflow_node_check: $f has a line-initial export/import on line $bad_line (only line 1 is modelled) -- module scope cannot be modelled by the Workflow-async wrapper, refusing rather than checking wrongly" >&2
    return 1
  fi

  # node --check dies with ERR_UNKNOWN_FILE_EXTENSION on an extension-less temp path
  # (measured on Node v26.8.1) -- the suffix is required, not cosmetic.
  local tmp
  tmp="$(mktemp --suffix=.js)" || {
    echo "workflow_node_check: mktemp failed while checking $f" >&2
    return 1
  }

  # Join the async-function prologue to line 1 with NO trailing newline, so every reported
  # line number in node --check's output still matches the source file. Strip only a line-1
  # `export` (relay-loop.js's own single ESM construct); everything else passes through
  # unchanged.
  {
    printf 'async function __relay_wf__(){ '
    sed -E '1s/^export //' "$f"
    printf '\n}\n'
  } > "$tmp"

  local rc=0
  node --check "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}
