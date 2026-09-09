#!/usr/bin/env bash
# roadmap:8627
#
# RED SPEC for id:8627 -- `tests/lib-workflow-check.sh`'s refusal scan is a line-oriented
# regex heuristic, not the lexical scan its own header comment claims. Found 2026-09-08 by the
# review of id:1b0e/id:e044/id:ad67 (id:e044 residue -- that item narrowed the false-refusal
# class, it did not eliminate the mis-modelling class). Detail: docs/ledger-notes/8627.md
#
# THREE defects, all measured against the shipped (pre-fix) helper before this file was written:
#
#   (b) BLIND WINDOW (fail-OPEN) -- a `//` line comment containing a `/*`-looking substring
#       (e.g. the glob `relay/orphan/*`, live on relay-loop.js) is read as OPENING a block
#       comment, because the opener check is a whole-line regex (`line ~ /\/\*/`) with no
#       notion that the `/*` sits after an earlier `//`. Everything until the next line
#       containing `*/` becomes invisible to the refusal scan -- MEASURED at 1,251 of 4,930
#       lines on the live file at the time this was found. A real module-scope `export` inside
#       that window is silently accepted: a FALSE GREEN.
#   (c)/(d) ESCAPED BACKTICK (fail-CLOSED) -- the template-parity check counts EVERY backtick on
#       a line (`gsub(/`/, "", tmp)`), including one immediately preceded by `\`. An escaped
#       backtick on the template-OPENING line throws off the parity and leaves the template
#       state CLOSED when it should stay open; an escaped backtick on a CONTINUATION line (state
#       already open) unconditionally clears `in_template` (`line ~ /`/` is presence, not
#       parity-aware). Either way, prose inside a still-open template -- including a line-initial
#       `export` -- gets checked as real code and wrongly REFUSED.
#   (e) SAME-LINE CLOSE-THEN-OPEN (fail-CLOSED) -- the block-comment opener check is suppressed
#       by ANY `*/` anywhere on the line (`line !~ /\*\//`), even one that closed an EARLIER
#       comment on the same line. `const a = 1; /* x */ /*` genuinely opens a SECOND comment
#       that should carry into the next line; the shipped helper sees the line's `*/` and never
#       sets `in_comment`, so prose inside that second (real) comment on later lines is wrongly
#       REFUSED.
#
# WHAT THE EXECUTOR MUST NOT DO
# -----------------------------
# * Do not make the check permissive: every fixture below still ends with a GENUINE top-level
#   `export`/`import` that must be REFUSED. "Stop refusing anything" fails this file.
# * Do not special-case the three `relay/orphan/*` lines on the live file -- the fix must be a
#   general lexical rule (assertion (a) pins the live file only as a regression measurement).
# * Do not restructure relay/scripts/relay-loop.js -- out of scope, closed under id:62c9.
#
# `# roadmap:8627` above means this file is EXPECTED-RED while THAT item is unticked
# (tests/run-tests.sh reads the FIRST roadmap token), and ROADMAP-SHADOWED in
# tests/verify-negative-cases.py (id:7c82).
#
# fails-against: the tree as it stands at 67b1139ff2a942e27f2f1d7b0a2f9668a13b28e5, where
#   tests/lib-workflow-check.sh is the landed, defective version. `fail()` exits, so precisely
#   one FAIL line fires and it is the FIRST failing assertion: (0)/(0b) and (a1) all pass against
#   that helper (workflow_node_check already exists and the pristine file already parses). (b)'s
#   own top-level `&&` check does NOT fire there -- the blind window is fail-OPEN but backstopped
#   (docs/ledger-notes/8627.md "Severity"): the missed awk refusal still gets caught by the
#   `node --check` fallback because `export` is a SyntaxError inside a function body regardless,
#   so rc is still non-zero. What breaks is the CONTRACT that the refusal names the source file:
#   the fallback message names the wrapped TEMP path instead, so (b2) -- the file-naming check --
#   is the assertion that actually fires first, verified directly against the base helper before
#   this file was authored. (c)-(g) are unreached there (in particular (f0), since the base
#   helper does not define workflow_scan_stats at all); each of (c)-(e)'s cases was independently
#   reproduced by hand against the base helper too (each mis-reports the refused line number).
# fails-against-rev: 67b1139ff2a942e27f2f1d7b0a2f9668a13b28e5 -- tests/lib-workflow-check.sh
# fails-against-assertion: (b2) the refusal does not name the fixture file

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/tests/lib-workflow-check.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

tmp="$(mktemp -d)"
cleanup() { rm -r -- "$tmp"; }
trap cleanup EXIT

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }
cannot_run() { echo "ERROR: $*"; exit 3; }

command -v node >/dev/null 2>&1 || cannot_run "node is not on PATH -- this spec cannot be verified here"
[[ -f "$LOOP" ]] || cannot_run "relay/scripts/relay-loop.js is missing; the regression fixture's subject does not exist"
[[ -f "$HELPER" ]] || fail "(0) tests/lib-workflow-check.sh does not exist -- id:62c9's helper is this spec's subject"
# shellcheck source=/dev/null
source "$HELPER"
declare -F workflow_node_check >/dev/null 2>&1 \
  || fail "(0b) tests/lib-workflow-check.sh does not define a workflow_node_check function"

# write <name> <body> -> prints the path of the fixture
write() { local out="$tmp/$1.js"; printf '%s\n' "$2" > "$out"; printf '%s' "$out"; }

# ---------------------------------------------------------------------------------------
# (a1) REGRESSION GUARD -- the pristine relay/scripts/relay-loop.js must still parse green
#      under workflow_node_check, exactly as before this fix.
# ---------------------------------------------------------------------------------------
workflow_node_check "$LOOP" \
  || fail "(a1) workflow_node_check REJECTS the pristine relay/scripts/relay-loop.js -- a hardening change has reddened the one file the helper exists to guard"
pass "(a1) the pristine relay-loop.js still parses green"

# ---------------------------------------------------------------------------------------
# (b) id:8627 primary defect -- a `//` comment containing a `/*`-looking glob must not open a
#     block-comment state that swallows a later genuine top-level export. Note the defect is
#     fail-OPEN but backstopped, not a false green (docs/ledger-notes/8627.md "Severity"): an
#     `export` DECLARATION is a SyntaxError inside a plain function body regardless, so a missed
#     awk refusal still gets caught by the `node --check` fallback -- but the message then names
#     the WRAPPED TEMP FILE, not the source, because the intended awk refusal (which DOES name
#     the file) never fired. That silent loss of the contractual file-naming message is what
#     this fixture pins.
# ---------------------------------------------------------------------------------------
b="$(write glob_comment 'const a = 1;
// note about relay/orphan/* cleanup, see retireDeadWorktree()
const c = 2;
export const bad = 3;')"
b_msg="$(workflow_node_check "$b" 2>&1)" \
  && fail "(b) a genuine top-level export hidden behind a // glob comment was ACCEPTED (rc=0) -- the // line containing relay/orphan/* wrongly opened a block-comment state that swallowed the real export on line 4"
grep -qF "$(basename "$b")" <<<"$b_msg" \
  || fail "(b2) the refusal does not name the fixture file (it fell through to the node --check backstop and named a temp path instead) -- the // line containing relay/orphan/* wrongly opened a block-comment state that swallowed the awk refusal's line-4 export: $b_msg"
pass "(b) a // comment containing a /*-looking glob does not hide a later genuine export from the awk refusal"

# ---------------------------------------------------------------------------------------
# (c) escaped backtick on the template-OPENING line must not close the template early -- prose
#     (including a line-initial `export`) inside the still-open template is accepted, and the
#     genuine top-level export AFTER the template closes is still refused.
# ---------------------------------------------------------------------------------------
c="$(write escaped_backtick_open 'const t = `x \` y
export const stillProse = 1;
z`;
export const bad = 2;')"
c_msg="$(workflow_node_check "$c" 2>&1)" \
  && fail "(c) an escaped backtick on the template-opening line was ACCEPTED wholesale -- either the template never opened (prose export wrongly refused, but this file returned 0 for a DIFFERENT reason) or the trailing genuine export escaped detection entirely: $c_msg"
grep -q 'on line 4 ' <<<"$c_msg" \
  || fail "(c2) the refusal did not point at line 4 (the genuine trailing export) -- got: $c_msg"
pass "(c) an escaped backtick on the template-opening line keeps the template open (prose export accepted, trailing genuine export still refused)"

# ---------------------------------------------------------------------------------------
# (d) escaped backtick on a CONTINUATION line (template already open from a prior line) must
#     not close it either.
# ---------------------------------------------------------------------------------------
d="$(write escaped_backtick_continuation 'const t = `
line with an escaped \` backtick
export const stillProse = 1;
end`;
export const bad = 2;')"
d_msg="$(workflow_node_check "$d" 2>&1)" \
  && fail "(d) an escaped backtick on a template continuation line wrongly closed the template -- prose export on line 3 should have stayed hidden, and the trailing genuine export escaped detection entirely: $d_msg"
grep -q 'on line 5 ' <<<"$d_msg" \
  || fail "(d2) the refusal did not point at line 5 (the genuine trailing export) -- got: $d_msg"
pass "(d) an escaped backtick on a template continuation line keeps the template open"

# ---------------------------------------------------------------------------------------
# (e) a same-line close-then-open block comment (`const a = 1; /* x */ /*`) genuinely opens a
#     SECOND comment that carries to the next line; prose inside it is accepted, and a genuine
#     export after the real close is still refused.
# ---------------------------------------------------------------------------------------
e="$(write close_then_open 'const a = 1; /* x */ /*
export const stillProse = 1;
*/
const q = 2;
export const bad = 3;')"
e_msg="$(workflow_node_check "$e" 2>&1)" \
  && fail "(e) a same-line close-then-open block comment was mishandled -- either the second /* never opened (prose export wrongly refused) or the trailing genuine export escaped detection entirely: $e_msg"
grep -q 'on line 5 ' <<<"$e_msg" \
  || fail "(e2) the refusal did not point at line 5 (the genuine trailing export) -- got: $e_msg"
pass "(e) a same-line close-then-open block comment still opens a real second comment"

# ---------------------------------------------------------------------------------------
# (f) DIRECT MEASUREMENT on the live file: the blind window was measured at 1,251 of 4,930
#     lines skipped-as-comment; after the fix, the // glob lines must never open a block-comment
#     state at all. `workflow_scan_stats` is a new, dedicated read-only entry point over the
#     SAME state machine `workflow_node_check` uses, so this pins the shipped scanner directly
#     rather than re-deriving a parallel implementation in the test.
# ---------------------------------------------------------------------------------------
declare -F workflow_scan_stats >/dev/null 2>&1 \
  || fail "(f0) tests/lib-workflow-check.sh does not define workflow_scan_stats -- no direct measurement entry point exists to pin the blind window on the live file"
stats="$(workflow_scan_stats "$LOOP")"
comment_n="$(sed -E 's/.*skipped-in-comment=([0-9]+).*/\1/' <<<"$stats")"
[[ "$comment_n" -lt 20 ]] \
  || fail "(f1) workflow_scan_stats reports skipped-in-comment=$comment_n on relay/scripts/relay-loop.js -- the blind window (previously measured at 1,251 lines) is still open: $stats"
pass "(f1) relay-loop.js's // glob comments no longer open a block-comment blind window ($stats)"

glob_line="$(grep -m1 -n 'relay/orphan/\*' "$LOOP" | cut -d: -f1)"
[[ -n "$glob_line" ]] || cannot_run "(f2) relay/scripts/relay-loop.js no longer contains a 'relay/orphan/*' // comment line -- the regression fixture's anchor is gone"
pass "(f2) found a live 'relay/orphan/*' // comment line at $glob_line to anchor the regression"

# ---------------------------------------------------------------------------------------
# (g) NEGATIVE CONTROL -- id:e044's four cases and id:1b0e/id:ad67 must still hold; re-running
#     the full hardening spec here would duplicate it, so just confirm it is still green.
# ---------------------------------------------------------------------------------------
if bash "$ROOT/tests/test_workflow_check_hardening.sh" >/dev/null 2>&1; then
  pass "(g) tests/test_workflow_check_hardening.sh (id:1b0e/e044/ad67) is still green"
else
  fail "(g) tests/test_workflow_check_hardening.sh regressed -- the id:8627 fix broke an earlier pinned behaviour"
fi

echo "OK: tests/test_workflow_scan_lexical_8627.sh"
