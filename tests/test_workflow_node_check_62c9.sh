#!/usr/bin/env bash
# roadmap:62c9
#
# RED SPEC for id:62c9 -- the Workflow-aware parse guard for relay/scripts/relay-loop.js.
#
# WHY THIS FILE EXISTS
# --------------------
# relay-loop.js is a Workflow script: the runtime wraps its body in an async function, so it
# legitimately carries BOTH a top-level `await` (~line 4807) and a top-level `return`
# (~line 4811), plus exactly one ESM construct (`export const meta = {` on line 1) and zero
# `import` statements. `node --check` has no such wrapper and must pick a module goal:
# top-level `return` alone parses as CommonJS, top-level `await` alone is detected as ESM,
# and a file containing BOTH parses under NEITHER. Since the Node upgrade on this machine
# (26.7.0 -> 26.8.1, 2026-09-08 08:10) about 46 test files that guard the template with a
# bare `node --check "$JS"` are RED on an unmodified `main`.
#
# The owner ruled 2026-09-08: repair the INSTRUMENT, not the source. relay-loop.js is NOT to
# be restructured. Full detail + the measured wrapper prototype: docs/ledger-notes/62c9.md.
#
# WHAT THE EXECUTOR MUST BUILD (this file does NOT build it)
# ---------------------------------------------------------
#   tests/lib-workflow-check.sh -- a sourceable shell library exposing
#       workflow_node_check <file>
#   which models the Workflow runtime before parsing:
#       { printf 'async function __relay_wf__(){ '; sed -E '1s/^export //' "$f"; \
#         printf '\n}\n'; } > "$tmp"; node --check "$tmp"
#   The prologue is joined to line 1 with NO newline so reported line numbers still match the
#   source. Exit 0 on a clean parse; non-zero, LOUDLY, otherwise. Then migrate every
#   `tests/test_*.sh` site that runs a bare `node --check` on relay-loop.js to call it.
#
# `# roadmap:62c9` above means this file is EXPECTED-RED while the ROADMAP item is unticked
# (tests/run-tests.sh), and ROADMAP-SHADOWED in tests/verify-negative-cases.py -- both
# carve-outs expire the moment the item is ticked, at which point the declaration below is
# executed for real.
#
# fails-against: the tree as it stands at 6aa0a77efa10244a63134b0a700eefafe5b4bf91, where
#   tests/lib-workflow-check.sh does not exist at all. verify-negative-cases.py DELETES a path
#   that is absent at the declared revision, which is exactly the negative case here: with the
#   helper gone, assertion (a) is the one that must fire.
# fails-against-rev: 6aa0a77efa10244a63134b0a700eefafe5b4bf91 -- tests/lib-workflow-check.sh
# fails-against-assertion: (a) helper missing or incomplete

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"
HELPER="$ROOT/tests/lib-workflow-check.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

command -v node >/dev/null 2>&1 || fail "node is not on PATH -- this spec cannot be verified here"
[[ -f "$LOOP" ]] || fail "relay/scripts/relay-loop.js is missing; the spec's subject does not exist"

# ---------------------------------------------------------------------------------------
# (a) The shared helper exists, is sourceable, defines workflow_node_check, and parses the
#     pristine relay-loop.js green. This is the assertion that fires at the declared rev.
# ---------------------------------------------------------------------------------------
if [[ ! -f "$HELPER" ]]; then
  fail "(a) helper missing or incomplete: tests/lib-workflow-check.sh does not exist -- id:62c9's Workflow-aware node-check helper is the executor's deliverable"
fi
# shellcheck source=/dev/null
source "$HELPER"
declare -F workflow_node_check >/dev/null 2>&1 \
  || fail "(a2) tests/lib-workflow-check.sh does not define a workflow_node_check function"
workflow_node_check "$LOOP" \
  || fail "(a3) workflow_node_check rejects the PRISTINE relay/scripts/relay-loop.js -- the wrapper does not model the Workflow runtime"
pass "(a) helper present and parses the pristine relay-loop.js"

# ---------------------------------------------------------------------------------------
# (b) The helper still CATCHES a genuine syntax error. Three DISTINCT mutations, at three
#     different depths, so "make the check permissive" (always exit 0) cannot pass. Each is
#     applied to a COPY under $tmp; the real file is never touched.
# ---------------------------------------------------------------------------------------
mutate() {  # mutate <name> <awk-line-no> <text-to-insert-after-that-line>
  local name="$1" at="$2" text="$3" out="$tmp/$1.js"
  awk -v at="$at" -v txt="$text" 'NR==at{print; print txt; next} {print}' "$LOOP" > "$out"
  printf '%s' "$out"
}

m1="$(mutate stray_brace 2000 '}')"
workflow_node_check "$m1" >/dev/null 2>&1 \
  && fail "(b1) a stray closing brace injected at line 2000 was NOT caught -- the guard has been made permissive"
pass "(b1) stray closing brace is caught"

m2="$(mutate unterminated_string 2500 "const __x = 'unterminated;")"
workflow_node_check "$m2" >/dev/null 2>&1 \
  && fail "(b2) an unterminated string injected at line 2500 was NOT caught"
pass "(b2) unterminated string is caught"

m3="$(mutate bad_token 3000 'const = ;')"
workflow_node_check "$m3" >/dev/null 2>&1 \
  && fail "(b3) a malformed declaration injected at line 3000 was NOT caught"
pass "(b3) malformed declaration is caught"

# ---------------------------------------------------------------------------------------
# (c) The helper FAILS LOUDLY on a file whose module scope it cannot model. The wrapper only
#     strips a line-1 `export `; a line-initial `export `/`import ` anywhere else means the
#     file is a real ESM module and wrapping it silently mis-models it. Refusal must be
#     non-zero AND must name the file -- no silent fallback, no silent pass.
# ---------------------------------------------------------------------------------------
scope_case() {  # scope_case <name> <body>
  local out="$tmp/$1.js"; printf '%s\n' "$2" > "$out"; printf '%s' "$out"
}

c1="$(scope_case export_line5 'const a = 1;
const b = 2;
const c = 3;
const d = 4;
export const e = 5;')"
msg="$(workflow_node_check "$c1" 2>&1)" && fail "(c1) a line-initial \`export \` on line 5 was ACCEPTED -- an unmodellable module scope must be refused, not wrapped"
grep -qF "$(basename "$c1")" <<<"$msg" \
  || fail "(c1b) the refusal of $(basename "$c1") does not name the file: $msg"
pass "(c1) a non-line-1 export is refused, loudly, naming the file"

c2="$(scope_case import_line3 'const a = 1;
const b = 2;
import fs from "node:fs";')"
msg="$(workflow_node_check "$c2" 2>&1)" && fail "(c2) a line-initial \`import \` on line 3 was ACCEPTED -- an unmodellable module scope must be refused"
grep -qF "$(basename "$c2")" <<<"$msg" \
  || fail "(c2b) the refusal of $(basename "$c2") does not name the file: $msg"
pass "(c2) a non-line-1 import is refused, loudly, naming the file"

# Negative control for (c): the refusal must be NARROW. A line-1 `export ` is exactly what
# relay-loop.js has and must still be accepted, and a merely-mentioned `export`/`import`
# inside a string or a comment is not a module construct and must not trip the refusal.
c3="$(scope_case export_line1 'export const meta = { name: "x" };
const q = await Promise.resolve(1);
if (q) { return q; }')"
workflow_node_check "$c3" \
  || fail "(c3) a line-1 \`export \` plus top-level await+return was refused -- that is relay-loop.js's own shape and must be accepted"
pass "(c3) the line-1 export shape (relay-loop.js's own) is still accepted"

c4="$(scope_case export_mentioned 'const s = "export const x = 1;";
// import fs from "node:fs";
const q = await Promise.resolve(s);
if (q) { return q; }')"
workflow_node_check "$c4" \
  || fail "(c4) \`export\`/\`import\` mentioned inside a string and a comment tripped the refusal -- the guard must key on line-initial module constructs, not on the words"
pass "(c4) export/import inside a string or comment does not trip the refusal"

# ---------------------------------------------------------------------------------------
# (d) MIGRATION: no tests/test_*.sh calls a bare `node --check` on relay-loop.js any more.
#     Detected mechanically -- a file is a violation when it invokes the bare checker, AT A
#     COMMAND POSITION and OUTSIDE any heredoc body, on an argument that this same file binds
#     to relay-loop.js (or names the path literally).
#
#     The two exclusions are not conveniences, they are correctness:
#       * heredoc bodies -- tests/test_source_grep_lint.sh writes a FIXTURE test containing
#         `node --check "$JS"` precisely to prove its lint treats a syntax gate as
#         non-execution. That fixture is not a guard site and must not be migrated.
#       * command position -- tests/test_version_bump.sh's `pass "(9) ... (node --check +
#         template lint) ..."` is a message, not an invocation.
#     Both were observed as false positives before these were added; they are named here so a
#     later reader does not "simplify" them away. This file itself is excluded by name (it
#     mentions the pattern only in prose); the helper is not a test_*.sh file.
# ---------------------------------------------------------------------------------------
CHECKER="node ""--check"          # split so this file's own body carries no bare invocation

# emit "LINENO:text" for every line of <file> that is NOT inside a heredoc body.
lines_outside_heredocs() {
  local f="$1" n=0 hd="" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if [[ -n "$hd" ]]; then
      [[ "$line" =~ ^[[:space:]]*${hd}[[:space:]]*$ ]] && hd=""
      continue
    fi
    # A heredoc opener ENDS its line (`cat > "$f" <<'EOF'`). Anchoring to end-of-line is not
    # cosmetic: without it, `print(d.get(sys.argv[1],"<<MISSING>>"))` in
    # tests/test_verdict_event_c7dc.sh:57 read as an opener for a delimiter that never
    # arrives, and every line below it -- including that file's real guard site at 119 --
    # vanished from this scan. A silent false NEGATIVE in the migration check.
    if [[ "$line" != *'<<<'* && "$line" =~ \<\<-?[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]?[[:space:]]*$ ]]; then
      hd="${BASH_REMATCH[1]}"
    fi
    printf '%d:%s\n' "$n" "$line"
  done < "$f"
}

# true when <text> has the checker at a command position (start of line, or right after a
# separator). `(` is deliberately NOT a separator here: it appears inside quoted messages.
at_command_position() {
  local prefix="${1%%"$CHECKER"*}"
  [[ "$prefix" =~ ^[[:space:]]*$ ]] && return 0
  [[ "$prefix" =~ [\;\&\|\{][[:space:]]*$ ]] && return 0
  [[ "$prefix" =~ (^|[[:space:]])(if|elif|while|until|then|do|else|!)[[:space:]]+$ ]] && return 0
  return 1
}

offenders=()
for f in "$ROOT"/tests/test_*.sh; do
  [[ "$(basename "$f")" == "$SELF" ]] && continue
  # variables this file binds to relay-loop.js, e.g. JS=".../relay-loop.js"
  mapfile -t vars < <(grep -oP '^\s*\K[A-Za-z_][A-Za-z0-9_]*(?==[^=].*relay-loop\.js)' "$f" | sort -u)
  while IFS= read -r numbered; do
    text="${numbered#*:}"
    [[ "$text" =~ ^[[:space:]]*# ]] && continue            # a comment, not an invocation
    [[ "$text" == *"$CHECKER"* ]] || continue
    at_command_position "$text" || continue
    if [[ "$text" == *'relay-loop.js'* ]]; then
      offenders+=("$(basename "$f"):$numbered"); continue
    fi
    for v in "${vars[@]}"; do
      [[ -n "$v" ]] || continue
      if [[ "$text" == *"\$$v"* || "$text" == *"\${$v}"* ]]; then
        offenders+=("$(basename "$f"):$numbered"); break
      fi
    done
  done < <(lines_outside_heredocs "$f")
done
if (( ${#offenders[@]} > 0 )); then
  printf '  unmigrated site: %s\n' "${offenders[@]}" >&2
  fail "(d) ${#offenders[@]} test site(s) still run a bare node-check on relay-loop.js instead of workflow_node_check -- these are exactly the sites that are RED under Node 26.8.1"
fi
pass "(d) every test site guards relay-loop.js through workflow_node_check"

echo "OK: tests/test_workflow_node_check_62c9.sh"
