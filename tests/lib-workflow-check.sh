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
# The Workflow runtime itself is STRICT mode (probed 2026-09-08, docs/ledger-notes/ad67.md:
# `this` is undefined in a plain call and an implicit global throws ReferenceError), so the
# wrapper carries `'use strict';` as its first statement -- joined to line 1 with no newline,
# same as the rest of the prologue, so reported line numbers still match the source.
#
# workflow_node_check <file> models the runtime by wrapping the source in a strict async
# function and stripping a line-1 `export`, then runs `node --check` on the wrapped copy. It
# exits 0 on a clean parse and non-zero otherwise -- because node --check itself rejected the
# wrapped source (a genuine syntax error, including a strict-only one), or because this
# function REFUSED to wrap the file at all: the file could not be read, or it carries a
# line-initial `export `/`import <declaration>` module construct on a line other than line 1
# that a real lexical scan (not just a line-initial substring) confirms is NOT inside a
# backticked template literal or a `/* */` block comment, and is not a parenthesised dynamic
# `import(...)`/`import (...)` call. A `//` line comment, or a mid-line mention inside a string,
# never trips this refusal either way. Source this file, then call the function; nothing else
# is exported.

workflow_node_check() {
  local f="$1"

  if [[ ! -f "$f" ]]; then
    echo "workflow_node_check: no such file: $f" >&2
    return 1
  fi

  if [[ ! -r "$f" ]]; then
    echo "workflow_node_check: cannot read $f (permission denied?)" >&2
    return 1
  fi

  # Refuse LOUDLY -- rather than silently mis-model -- a file that carries a genuine line-initial
  # `export `/`import <declaration>` module construct on any line OTHER than line 1. The wrapper
  # only strips a line-1 `export`; a real ESM module scope (a genuine import, or export
  # declarations scattered through the file) is outside what an async-function wrapper can
  # model at all, and wrapping it anyway would silently produce a false parse verdict.
  #
  # This is a line-oriented scan with a small amount of lexical state, tracked across lines:
  # whether we are currently inside a backtick template literal, or inside a `/* */` block
  # comment. A line-initial `export `/`import ` while either state is open is prose, not code,
  # and must not trip the refusal -- a 4,930-line prompt-template file is mostly exactly this
  # shape. `import (...)`/`import(...)` -- with or without a space before the paren -- is a
  # legal dynamic import call, not an import declaration, and is excluded on that basis: after
  # stripping the `import` keyword and any following whitespace, the next character decides.
  # A `//` line comment or a mid-line mention inside a string never matches at all, because the
  # anchor requires the keyword at the start of the line (only leading whitespace before it).
  local bad_line awk_rc=0
  bad_line="$(awk '
    {
      line = $0
      if (in_comment) {
        if (line ~ /\*\//) { in_comment = 0 }
        next
      }
      if (in_template) {
        if (line ~ /`/) { in_template = 0 }
        next
      }
      if (NR > 1) {
        if (line ~ /^[[:space:]]*export[[:space:]]/) { print NR; exit }
        if (line ~ /^[[:space:]]*import[[:space:]]/) {
          rest = line
          sub(/^[[:space:]]*import[[:space:]]*/, "", rest)
          if (substr(rest, 1, 1) != "(") { print NR; exit }
        }
      }
      tmp = line
      n = gsub(/`/, "", tmp)
      if (n % 2 == 1) { in_template = 1 }
      if (line ~ /\/\*/ && line !~ /\*\//) { in_comment = 1 }
    }
  ' "$f")" || awk_rc=$?
  if (( awk_rc != 0 )); then
    echo "workflow_node_check: failed to scan $f for module syntax (awk exit $awk_rc)" >&2
    return 1
  fi
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
  # line number in node --check's output still matches the source file. `'use strict';` is
  # part of that same joined prologue line, so it costs no line number either. Strip only a
  # line-1 `export` (relay-loop.js's own single ESM construct); everything else passes through
  # unchanged. Both the read (`sed`) and the write are checked explicitly -- a brace group's
  # exit status is only its LAST command's, which previously discarded a failed `sed` (and thus
  # an unreadable-file failure) as a false success.
  local sed_rc=0
  {
    printf "async function __relay_wf__(){ 'use strict'; "
    sed -E '1s/^export //' "$f" || sed_rc=$?
    printf '\n}\n'
  } > "$tmp"
  if (( sed_rc != 0 )); then
    echo "workflow_node_check: failed to read $f while building the wrapper (sed exit $sed_rc)" >&2
    rm -f "$tmp"
    return 1
  fi

  local rc=0
  node --check "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}
