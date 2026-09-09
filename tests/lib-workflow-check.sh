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
# that a character-level scan (id:8627 -- NOT a full JS tokenizer; quoted strings are not
# modelled) confirms is NOT inside a backticked template literal or a `/* */` block comment,
# and is not a parenthesised dynamic `import(...)`/`import (...)` call. A `//` line comment
# never trips this refusal either -- everything after an UNESCAPED `//` on a line that is
# genuinely code (not itself inside an open template/comment) is ignored for the rest of that
# line, so a `//` comment that happens to contain a `/*`-looking substring (e.g. a glob like
# `relay/orphan/*`) does not open a block-comment state. Source this file, then call
# `workflow_node_check`; `workflow_scan_stats` (below) is a secondary, read-only entry point
# used only by the regression fixture that pins the scanner's behaviour on the real file.

# The shared awk program behind both entry points below. It is ONE state machine so the two
# consumers can never drift apart (id:8627 -- the bug this item fixes was exactly a mismatch
# between what the scanner claimed to do and what its line-oriented regexes actually did).
#
# States: "code" / "comment" (inside `/* ... */`) / "template" (inside a backtick template).
# `scan_line` walks a line character-by-character from a STARTING state and returns the ENDING
# state, handling multiple opens/closes on one line (fixes the same-line close-then-open bug:
# `const a = 1; /* x */ /*` now correctly ends the line still inside a comment) and treating an
# escaped backtick (`\``, odd number of immediately-preceding backslashes) as ordinary text
# rather than a template delimiter (fixes both the opening-line and the closing-continuation
# escaped-backtick bugs). A `//` encountered while genuinely in "code" state ends scanning for
# the rest of the line outright, so nothing after it -- including a `/*`-shaped substring inside
# a glob -- can open a comment state (fixes the blind-window bug: `// relay/orphan/*` no longer
# opens a comment that swallows hundreds of following lines).
WORKFLOW_SCAN_AWK='
function is_escaped(line, pos,    j, bscount) {
  bscount = 0
  j = pos - 1
  while (j >= 1 && substr(line, j, 1) == "\\") {
    bscount++
    j--
  }
  return (bscount % 2 == 1)
}

function scan_line(line, start_state,    len, i, c2, state) {
  len = length(line)
  i = 1
  state = start_state
  while (i <= len) {
    if (state == "code") {
      c2 = substr(line, i, 2)
      if (c2 == "//") {
        i = len + 1
      } else if (c2 == "/*") {
        state = "comment"
        i += 2
      } else if (substr(line, i, 1) == "`" && !is_escaped(line, i)) {
        state = "template"
        i += 1
      } else {
        i += 1
      }
    } else if (state == "comment") {
      c2 = substr(line, i, 2)
      if (c2 == "*/") {
        state = "code"
        i += 2
      } else {
        i += 1
      }
    } else if (state == "template") {
      if (substr(line, i, 1) == "`" && !is_escaped(line, i)) {
        state = "code"
        i += 1
      } else {
        i += 1
      }
    }
  }
  return state
}

BEGIN { state = "code"; total = 0; code_n = 0; template_n = 0; comment_n = 0 }
{
  total++
  line = $0
  start_state = state

  if (mode == "refuse" && NR > 1 && start_state == "code") {
    if (line ~ /^[[:space:]]*export[[:space:]]/) { print NR; exit }
    if (line ~ /^[[:space:]]*import[[:space:]]/) {
      rest = line
      sub(/^[[:space:]]*import[[:space:]]*/, "", rest)
      if (substr(rest, 1, 1) != "(") { print NR; exit }
    }
  }

  if (start_state == "code") { code_n++ }
  else if (start_state == "template") { template_n++ }
  else if (start_state == "comment") { comment_n++ }

  state = scan_line(line, start_state)
}
END {
  if (mode == "stats") {
    printf "total=%d scanned-as-code=%d skipped-in-template=%d skipped-in-comment=%d\n", total, code_n, template_n, comment_n
  }
}
'

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
  # `import (...)`/`import(...)` -- with or without a space before the paren -- is a legal
  # dynamic import call, not an import declaration, and is excluded on that basis: after
  # stripping the `import` keyword and any following whitespace, the next character decides.
  local bad_line awk_rc=0
  bad_line="$(awk -v mode=refuse "$WORKFLOW_SCAN_AWK" "$f")" || awk_rc=$?
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
    rm -- "$tmp"
    return 1
  fi

  local rc=0
  node --check "$tmp" || rc=$?
  rm -- "$tmp"
  return "$rc"
}

# workflow_scan_stats <file> -- read-only measurement entry point over the SAME state machine
# `workflow_node_check` uses for its refusal scan (id:8627). Prints one line:
#   total=<N> scanned-as-code=<N> skipped-in-template=<N> skipped-in-comment=<N>
# where each count is the number of *lines* that started in that state. Exists so a regression
# fixture can pin the scanner's behaviour on the real relay-loop.js directly, guarding against
# the blind-window class of bug returning silently.
workflow_scan_stats() {
  local f="$1"
  if [[ ! -f "$f" || ! -r "$f" ]]; then
    echo "workflow_scan_stats: cannot read $f" >&2
    return 1
  fi
  awk -v mode=stats "$WORKFLOW_SCAN_AWK" "$f"
}
