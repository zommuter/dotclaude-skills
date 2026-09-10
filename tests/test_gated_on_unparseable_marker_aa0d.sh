#!/usr/bin/env bash
# RED SPEC for id:aa0d -- a `<!-- gated-on:... -->` marker whose payload the parser cannot
# fully parse must NEVER degrade to "this item has no gate". Contract + measurement:
# docs/ledger-notes/aa0d.md.
#
# NO `# roadmap:` HEADER, ON PURPOSE: id:aa0d is tracked in TODO.md, NOT in ROADMAP.md, so the
# EXPECTED-RED carve-out in tests/run-tests.sh (and the roadmap carve-out in
# tests/lint-vacuous-fixtures.py / tests/verify-negative-cases.py) must NOT apply. This file's
# failures ALWAYS count, which means `make test` reports this file RED from the moment it lands
# until the fix ships. That is deliberate and is the same shape as
# tests/test_inbox_own_token_extractor_0246.sh (a RED spec the suite already carries).
#
# THE DEFECT, measured (relay/scripts/lib-typed-edges.sh:20):
#
#     typed_edges_gated_of_line() { grep -oP '(?<=<!-- gated-on:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }
#
# The lookahead demands ` -->` IMMEDIATELY after the token list, so ANY unexpected payload
# breaks the WHOLE match rather than the unexpected part alone. Probed 2026-09-10 at
# 872abafca7dd:
#
#     <!-- gated-on:aa01 -->        rc=0 out=[aa01]   correct
#     <!-- gated-on:aa01=pass -->   rc=0 out=[]       NO GATE -- reads as ungated
#     <!-- gated-on:zzzz -->        rc=0 out=[]       NO GATE -- reads as ungated
#     <!-- gated-on: -->            rc=0 out=[]       NO GATE -- reads as ungated
#
# Empty means ungated to every caller, so resolve-gates.sh `continue`s the line, emits no row,
# and classify-repo.sh counts the item in actionable_routine_open -> the pool dispatches it.
# This is the id:d35a silent-no-op shape, and here it AUTHORISES DISPATCH.
#
# WHAT IT COST, LIVE: run relay-20260910-114832-18641 dispatched an execute unit onto
# leAIrn2learn id:89ef, whose line carries `<!-- gated-on:0d8e=pass -->` while id:0d8e is an
# OPEN `[INPUT - author]` item. The child refused and handed back; its judgment is the only
# thing that prevented work on an item whose contract cannot be satisfied yet. Fleet exposure:
# 11 suffixed edges, all in leAIrn2learn, 7 of them on OPEN items -- 7 currently-inert gates.
#
# WHAT THIS FILE DOES NOT SPEC -- read before "fixing" it
# ------------------------------------------------------
# It pins the FAILURE MODE, never the SEMANTICS of the `=pass` / `=either` conditions. That
# vocabulary is undefined anywhere (relay/references/hard-lanes.md and lib-typed-edges.sh both
# define `gated-on:a,b` with NO condition syntax) and deciding it belongs to leAIrn2learn's
# owner -- routed there as routed:784a. So:
#   * No case here asserts what `=pass` or `=either` MEAN, and no case is satisfied only by
#     one reading of them.
#   * Case 5's unparseable payload is `zzzz`, NOT `=pass`: `zzzz` is non-hex, so it can never
#     become a valid token under ANY later decision about condition syntax, which makes "refuse
#     it LOUDLY" safe to pin forever. Asserting a loud refusal of `=pass` instead would INVERT
#     the day that syntax is defined and parsed.
#   * Case 4 therefore asks of `=pass` only the weaker thing that holds under BOTH futures --
#     the item must not read as ungated. Its gate target is OPEN in the fixture, so every
#     plausible reading of `=pass` (gated until the target passes / closes / is waived) blocks
#     it, and so does a loud refusal. A future semantics that leaves an item with an OPEN gate
#     target dispatchable would be a different decision entirely, and should amend this case
#     explicitly rather than be reached by reinterpretation.
#   * Do NOT satisfy this file by widening the regex to swallow `=[a-z]+` and discarding the
#     condition. That makes `=pass` and `=either` behave identically -- silently picking one
#     reading of a syntax nobody has defined. Case 5 is what forbids it: a silent widening
#     leaves `zzzz` (and `<!-- gated-on: -->`) still silently ungated, and names nothing.
#
# WHY BOTH THE LIBRARY AND ITS CONSUMER ARE ASSERTED (the id:ae08 built-but-unwired class)
# ---------------------------------------------------------------------------------------
# Pinning lib-typed-edges.sh ALONE would fix nothing observable, and this is measured, not
# feared: relay/scripts/classify-repo.sh:69 reads
#
#     gates_tsv="$("$RESOLVE_GATES" "$path" 2>/dev/null || true)"
#
# which discards resolve-gates.sh's STDERR *and* its EXIT CODE. A fix spelled purely as "the
# library exits non-zero / warns on stderr" is swallowed twice over: gates_tsv comes back empty,
# no gate blocks anything, and the over-dispatch survives unchanged. So the dispatch-path
# consequence is asserted END TO END (cases 4b/5c) through classify-repo.sh's own
# actionable_routine_ids, not inferred from the library's return value.
#
# Case 6 exists for the opposite failure: a fix spelled as "die on the first unparseable
# marker" would, through that same `|| true`, throw away EVERY gate row in the file and
# re-create this exact defect for every OTHER item in the repo. Per-line, never whole-file.
#
# fails-against: lib-typed-edges.sh:20's ` -->` lookahead, which yields EMPTY for any
#   `<!-- gated-on:<unparseable> -->` marker, plus resolve-gates.sh:56's `[[ -z "$gated_csv" ]]
#   && continue` (empty == no gate) and classify-repo.sh:69's `2>/dev/null || true` (a loud
#   library refusal reaches no dispatch decision).
# fails-against-rev: 872abafca7dd1418292eb0ad77a821615355989f -- relay/scripts/lib-typed-edges.sh relay/scripts/resolve-gates.sh relay/scripts/classify-repo.sh
# fails-against-assertion: (6b) classify counts the unparseable-gate item as executor-actionable
#   (NOTE, while id:aa0d is OPEN: the declared rev IS today's unfixed tree, so
#   `make verify-negatives` reports this case's GREEN-NOW half as failing -- that is the
#   definition of a RED spec, and the id:0246 / id:1d83 precedent. Once the fix lands, green-now
#   passes and red-there reproduces the defect from the three pinned paths. All three are pinned
#   because the fix may be spelled in the library, in resolve-gates.sh's empty-means-ungated
#   branch, or in classify-repo.sh's swallow -- reverting all three reproduces the defect
#   wherever it was written.)
#
# HERMETIC -- every root the code under test resolves is injected. This matters more than usual:
# on 2026-09-10 a test in this repo destroyed 19 live production units by inheriting ONE default
# path into real state (id:1975). What is isolated, and why:
#   HOME                  -- last-resort default of everything below.
#   RELAY_TOML            -- gather-repo-state.sh's repo set; the real one is the fleet set.
#   RELAY_WORKTREE_BASE   -- gather-repo-state.sh's worktree scan root (~/.cache/relay/worktrees).
#   CLAIM_BASE            -- claim-state reads default to ~/.config/relay.
# Fixtures are real `git init` repos under one mktemp -d; no network; nothing is written outside
# it. Idiom: tests/test_gather_hard_pool_typed_gate_1022.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-typed-edges.sh"
RG="$ROOT/relay/scripts/resolve-gates.sh"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
die() { echo "FAIL: $1"; exit 1; }

[[ -f "$LIB" ]]      || die "precondition: lib-typed-edges.sh not found at $LIB"
[[ -x "$RG" ]]       || die "precondition: resolve-gates.sh missing/not executable at $RG"
[[ -x "$CLASSIFY" ]] || die "precondition: classify-repo.sh missing/not executable at $CLASSIFY"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"; mkdir -p "$HOME"
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"; mkdir -p "$RELAY_WORKTREE_BASE"
export CLAIM_BASE="$tmpdir/claim"; mkdir -p "$CLAIM_BASE"

# --- library probe: rc / stdout / stderr of the extractor for ONE line -------------------
# Written to a file pair rather than a pipe so stderr is captured separately; `set -e` is off
# in this file, so a non-zero rc is data, not death.
lib_out=""; lib_err=""; lib_rc=0
probe_lib() {
  local line="$1"
  lib_out="$(bash -c 'set -uo pipefail; source "$1"; typed_edges_gated_of_line "$2"' \
               _ "$LIB" "$line" 2>"$tmpdir/lib.err")"
  lib_rc=$?
  lib_err="$(cat "$tmpdir/lib.err")"
}

# --- fixture: a hermetic git repo with the given ROADMAP/TODO bodies --------------------
fixture_repo() {
  local name="$1" roadmap="$2" todo="${3:-}"
  local repo="$tmpdir/$name"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"
  git -C "$repo" config user.name "T"
  { printf '# Roadmap\n## Items\n'; printf '%s\n' "$roadmap"; } > "$repo/ROADMAP.md"
  { printf '# TODO\n## Current\n'; [[ -n "$todo" ]] && printf '%s\n' "$todo"; } > "$repo/TODO.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

# resolve-gates.sh stdout + stderr + rc, captured separately and in real order.
rg_out=""; rg_err=""; rg_rc=0
run_rg() {
  rg_out="$("$RG" "$1" 2>"$tmpdir/rg.err")"
  rg_rc=$?
  rg_err="$(cat "$tmpdir/rg.err")"
}

# classify-repo.sh's actionable_routine_ids, as a space-joined string.
aro_ids_of() {
  "$CLASSIFY" --emit unit --repo fixture --path "$1" 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin).get("actionable_routine_ids") or []))'
}

# ============================================================================
# REGRESSION GUARDS -- the plain `<!-- gated-on:a,b -->` form must be UNCHANGED.
# These are green today and must stay green: this parser has five live callers
# (resolve-gates.sh, meeting/orphan-scan.sh, roadmap-lint.sh, ledger-slice.sh and
# tools/roundtrip-validate.py's embedded copy), so a fix that disturbs the happy
# path breaks the umbrella/closure walk and the linter as well as dispatch.
# ============================================================================

# --- Case 1: single plain token, and a plain CSV set ------------------------------------
probe_lib '- [ ] [ROUTINE] plainly gated <!-- gated-on:aa01 --> <!-- id:bb01 -->'
if [[ "$lib_rc" -eq 0 && "$lib_out" == "aa01" && -z "$lib_err" ]]; then
  ok "(1) plain single-token gated-on still parses to aa01, quietly"
else
  bad "(1) plain single-token gated-on regressed: rc=$lib_rc out='$lib_out' err='$lib_err'"
fi

probe_lib '- [ ] [ROUTINE] plainly gated on two <!-- gated-on:aa01,aa02 --> <!-- id:bb02 -->'
if [[ "$lib_rc" -eq 0 && "$lib_out" == "aa01,aa02" && -z "$lib_err" ]]; then
  ok "(1b) plain CSV gated-on still parses to aa01,aa02, quietly"
else
  bad "(1b) plain CSV gated-on regressed: rc=$lib_rc out='$lib_out' err='$lib_err'"
fi

# --- Case 2: a BARE prose mention is still NOT an edge, and still SILENT -----------------
# The id:4da4/0d58 bare-substring trap. A fix that fires on the substring "gated-on" would
# scream on documentation, on this very repo's own comments, and on `(DEP: xxxx)` prose.
probe_lib '- [ ] [ROUTINE] discusses gated-on:aa01 in prose <!-- id:bb03 -->'
if [[ "$lib_rc" -eq 0 && -z "$lib_out" && -z "$lib_err" ]]; then
  ok "(2) a BARE prose 'gated-on:aa01' mention is still no edge, and says nothing"
else
  bad "(2) bare prose mention must stay a silent non-edge: rc=$lib_rc out='$lib_out' err='$lib_err'"
fi

# --- Case 3: end-to-end plain behaviour through resolve-gates + classify -----------------
# Gate targets live in TODO.md so the ROADMAP's own actionable count contains only the items
# under test. cc01 is OPEN (must block), cc02 is CLOSED (must not).
repo3="$(fixture_repo plain3 \
'- [ ] [ROUTINE] gated on an OPEN target <!-- gated-on:cc01 --> <!-- id:bb04 -->
- [ ] [ROUTINE] gated on a CLOSED target <!-- gated-on:cc02 --> <!-- id:bb05 -->' \
'- [ ] design work, still open <!-- id:cc01 -->
- [x] design work, landed <!-- id:cc02 -->')"
run_rg "$repo3"
if grep -qP '^bb04\t1\t' <<<"$rg_out"; then
  ok "(3) plain gated-on with an OPEN target still yields block=1"
else
  bad "(3) plain gated-on with an OPEN target must still block: out='$rg_out' err='$rg_err'"
fi
if grep -q 'bb05' <<<"$rg_out"; then
  bad "(3b) plain gated-on with a CLOSED target must emit NO row (clean pass): out='$rg_out'"
else
  ok "(3b) plain gated-on with a CLOSED target is still a clean pass"
fi
ids3="$(aro_ids_of "$repo3")"
if [[ " $ids3 " == *" bb05 "* && " $ids3 " != *" bb04 "* ]]; then
  ok "(3c) classify still excludes the open-gated item and still counts the closed-gated one (ids: $ids3)"
else
  bad "(3c) classify's actionable_routine_ids regressed on the plain form: got '$ids3', want bb05 present and bb04 absent"
fi

# ============================================================================
# THE DEFECT.
# ============================================================================

# --- Case 4: `<!-- gated-on:cc03=pass -->` with cc03 OPEN must not read as ungated -------
# SEMANTICS-FREE (see the header): this asks only that the gate be VISIBLE. Whether the fix
# refuses the payload loudly or a later decision gives `=pass` a meaning, an OPEN target
# cannot leave the item silently dispatchable.
repo4="$(fixture_repo cond4 \
'- [ ] [ROUTINE] gated with a CONDITION suffix on an open target <!-- gated-on:cc03=pass --> <!-- id:bb06 -->' \
'- [ ] the gate target, an open [INPUT - author] item <!-- id:cc03 -->')"
run_rg "$repo4"
if grep -qP '^bb06\t' <<<"$rg_out" || grep -q 'bb06' <<<"$rg_err"; then
  ok "(4) resolve-gates does not silently pass an item gated as 'cc03=pass' on an OPEN target"
else
  bad "(4) resolve-gates is SILENT on 'gated-on:cc03=pass' with cc03 OPEN -- the gate is invisible (rc=$rg_rc, stdout='$rg_out', stderr='$rg_err')"
fi
ids4="$(aro_ids_of "$repo4")"
if [[ " $ids4 " == *" bb06 "* ]]; then
  bad "(4b) classify counts bb06 as executor-actionable though its gate target cc03 is OPEN -- this is the live relay-20260910-114832-18641 over-dispatch (ids: $ids4)"
else
  ok "(4b) classify excludes the condition-suffixed gated item from actionable_routine_ids"
fi

# --- Case 5: a payload that can NEVER be valid must be refused LOUDLY, by NAME -----------
# `zzzz` is non-hex, so no later decision about condition syntax can make it a token. A
# marker the parser cannot understand must not degrade to "ungated": it must say so, naming
# BOTH the offending payload (so the author can fix the source line) and the item (so the
# operator knows which line). `<!-- gated-on: -->` is the same class with an empty payload.
probe_lib '- [ ] [ROUTINE] gated on garbage <!-- gated-on:zzzz --> <!-- id:bb07 -->'
if [[ "$lib_rc" -ne 0 || -n "$lib_err" || -n "$lib_out" ]]; then
  ok "(5) the library signals something for an unparseable gated-on payload (rc=$lib_rc out='$lib_out')"
else
  bad "(5) the library returns rc=0, empty stdout, empty stderr for '<!-- gated-on:zzzz -->' -- indistinguishable from NO GATE, which is the id:d35a silent no-op that authorises dispatch"
fi

probe_lib '- [ ] [ROUTINE] gated on nothing at all <!-- gated-on: --> <!-- id:bb08 -->'
if [[ "$lib_rc" -ne 0 || -n "$lib_err" || -n "$lib_out" ]]; then
  ok "(5b) the library signals something for an EMPTY gated-on payload (rc=$lib_rc out='$lib_out')"
else
  bad "(5b) the library returns rc=0, empty stdout, empty stderr for '<!-- gated-on: -->' -- a marker that means nothing must not mean 'ungated'"
fi

repo5="$(fixture_repo garbage5 \
'- [ ] [ROUTINE] gated on an unparseable payload <!-- gated-on:zzzz --> <!-- id:bb09 -->')"
run_rg "$repo5"
rg_all="$rg_out
$rg_err"
if grep -q 'bb09' <<<"$rg_all" && grep -q 'zzzz' <<<"$rg_all"; then
  ok "(5c) resolve-gates names both the item (bb09) and the offending payload (zzzz)"
else
  bad "(5c) resolve-gates does not name the item and the offending marker text for an unparseable gated-on payload (rc=$rg_rc, stdout='$rg_out', stderr='$rg_err') -- an operator cannot find the line to fix"
fi

# --- Case 6: per-LINE, never a whole-file bail-out ---------------------------------------
# A fix spelled "exit on the first unparseable marker" would, through classify-repo.sh:69's
# `2>/dev/null || true`, discard EVERY gate row in the repo and re-create this defect for
# every other item. The unparseable line must not cost its siblings their gates.
repo6="$(fixture_repo perline6 \
'- [ ] [ROUTINE] unparseable payload, listed FIRST <!-- gated-on:zzzz --> <!-- id:bb10 -->
- [ ] [ROUTINE] a plainly gated sibling BELOW it <!-- gated-on:cc04 --> <!-- id:bb11 -->' \
'- [ ] the sibling gate target, still open <!-- id:cc04 -->')"
run_rg "$repo6"
if grep -qP '^bb11\t1\t' <<<"$rg_out"; then
  ok "(6) an unparseable marker does not cost a LATER sibling its block row"
else
  bad "(6) the plainly-gated sibling bb11 lost its block row when an earlier line carried an unparseable marker -- whole-file bail-out, not per-line (rc=$rg_rc, stdout='$rg_out', stderr='$rg_err')"
fi
ids6="$(aro_ids_of "$repo6")"
if [[ " $ids6 " == *" bb10 "* ]]; then
  bad "(6b) classify counts the unparseable-gate item as executor-actionable -- bb10 carries '<!-- gated-on:zzzz -->', a marker nothing can resolve, yet it reaches the pool as an executor-ready [ROUTINE] (ids: $ids6)"
else
  ok "(6b) classify excludes the unparseable-gate item bb10 from actionable_routine_ids"
fi
if [[ " $ids6 " == *" bb11 "* ]]; then
  bad "(6c) classify counts bb11 as actionable though its plain gate target cc04 is OPEN (ids: $ids6)"
else
  ok "(6c) the plainly-gated sibling stays excluded from actionable_routine_ids"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
