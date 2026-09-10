#!/usr/bin/env bash
# RED SPEC for id:0246 -- "which token OWNS this inbox line" must be ONE shared extractor,
# `inbox_line_own_token` in relay/scripts/lib-anchored-id.sh, that all THREE live call sites
# adopt. Contract: docs/ledger-notes/0246.md (read the AMENDED section -- it is a three-way
# disagreement, not two).
#
# NO `# roadmap:` HEADER, ON PURPOSE: id:0246 is tracked in TODO.md, NOT in ROADMAP.md, so the
# EXPECTED-RED carve-out in tests/run-tests.sh (and the roadmap carve-out in
# tests/lint-vacuous-fixtures.py / tests/verify-negative-cases.py) must NOT apply. This file's
# failures ALWAYS count, which means `make test` is RED from the moment this lands until the
# shared extractor ships. That is deliberate and is the same shape as
# tests/test_inbox_twin_archive_1d83.sh.
#
# THE DEFECT -- three live rules, measured on
#   `- [ ] [tgt] cites \`routed:aaaa\` in prose <!-- routed:bbbb --> trailing note`:
#
#   relay/scripts/scan-routed.sh:226   FIRST anchored marker (`head -1`)        -> bbbb
#   meeting/append.sh:707 (`add`)      LAST anchored marker (`tail -1`)         -> bbbb
#   meeting/append.sh `inbox-done`     marker at END OF LINE (python `\s*$`)    -> NO TOKEN
#
# Two consequences, both live right now:
#   (a) FALSE SUCCESS REPORT. `scan-routed.sh --apply` resolves a token, finds its twin, calls
#       `append.sh inbox-done <tok>`, which finds no owning line, takes its "nothing to delete"
#       branch and exits 0. scan-routed swallows that (`2>/dev/null || true`) and prints
#       `RESOLVED ... removed from inbox` WHILE THE LINE SURVIVES -- id:4347's no-silent-swallow
#       ban and the id:d35a silent-no-op class in one line of output.
#   (b) A LEGAL LINE SHAPE IS UNRESOLVABLE BY CONSTRUCTION. Trailing prose after a marker is
#       EXPLICITLY legal (id:798d, e.g. `<!-- id:XXXX --> -- GATED (auto, id:3801)`), and
#       `token_own_checkbox_marker_in_text` in lib-anchored-id.sh already says so in its own
#       docstring. Such an inbox line is owned by NO token under `inbox-done`, so it can never
#       be drained, while scan-routed reports it RESOLVED.
#
# WHY A LIBRARY AND NOT A PATCHED REGEX AT ONE SITE: the anchoring has now been re-derived from
# scratch, wrongly, TWICE -- once by scan-routed.sh in production, once by an ad-hoc probe in
# this repo an hour before the item was filed (docs/ledger-notes/0246.md). lib-anchored-id.sh
# already owns the OWN-MARKER predicate; it does not yet own OWN-TOKEN EXTRACTION, and that gap
# is what both re-derivations fell into. So the spec asserts the BEHAVIOUR OF EACH SITE, not
# just the library: a library nobody calls fixes nothing (the id:ae08 built-but-unwired class).
#
# THE SPECCED SEMANTICS of `inbox_line_own_token <line> [context]`:
#   stdout `routed:XXXX` / exit 0 -- the line's OWN anchored `<!-- routed:XXXX -->` marker,
#                                   TOLERANT of trailing prose after it (id:798d);
#   exit 1                        -- no anchored routed marker, or the line is not a checkbox
#                                   line (the inbox's own `# Line format: ...` header comment
#                                   carries a marker-shaped string and owns nothing);
#   exit 3 ($OWN_ID_AMBIGUOUS)    -- MORE THAN ONE anchored routed marker: REFUSE, print
#                                   nothing, name every candidate on stderr. This is
#                                   own_routed_of_line's established id:6059 refusal, REUSED
#                                   rather than re-invented -- there is no safe positional rule
#                                   when `<!-- routed:X -->` means both "this line IS X" and
#                                   "this line REFERS to X".
#   A BARE prose citation (`\`routed:aaaa\``) NEVER wins, at any position (id:411d / id:c97c --
#   a run DELETED three inbox items it had never filed through exactly that class).
#
# THE CONTESTED CONSEQUENCE, FLAGGED RATHER THAN HIDDEN (cases 3, 7, 9). BOTH items currently in
# the live inbox carry their foreign citations as LITERAL HTML-comment markers, not backticked
# bare tokens -- so each line carries 2-3 anchored routed markers and the id:6059 refusal fires
# on BOTH. Under this spec neither live item can be drained until its citations are
# de-literalised, which is exactly the fix the `routed:3e13` item itself prescribes ("render the
# two citations as plain backticked text so they stop being markers").
#
# OWNER RULING 2026-09-10, recorded here because this file asked the question. The owner was
# asked "should the refusal extend to a line that merely CITES the token?" and DISSOLVED it
# rather than answering: such a line should not EXIST. So the refusal is kept AND paired with
# prevention -- `append.sh -t inbox` REJECTS a multi-marker entry at write time (case 8b),
# `todo-conformance.sh --inbox` LINTS the existing ones (class `multi-marker`), and the
# resolver refusal stays as the backstop (cases 3, 7b, 9). Consequence accepted with its cost:
# both live inbox lines must be de-literalised by hand before they can drain.
#
# SECOND OWNER RULING, same day: an INDENTED inbox line is REFUSED, and refused LOUDLY. The
# defect the review found there was the SILENT exit-0 no-op (a previously drainable shape
# became immortal without a word), not the strictness -- so the extractor returns a distinct
# status ($INBOX_LINE_INDENTED, 4) and names the line, and both consumers report it.
#
# fails-against: the three divergent rules -- scan-routed.sh:226 `head -1`, append.sh:707
#   `tail -1`, and append.sh inbox-done's end-of-line-anchored `own_marker` python regex -- with
#   no shared `inbox_line_own_token` in relay/scripts/lib-anchored-id.sh for them to agree on.
# fails-against-rev: d7861a6a664d39db4efd7c9b26a02818130da66e -- relay/scripts/lib-anchored-id.sh meeting/append.sh relay/scripts/scan-routed.sh
# fails-against-assertion: (10) SILENT NO-OP REPORTED AS SUCCESS
#   (NOTE, while id:0246 is OPEN: the declared rev IS today's unfixed tree, so
#   `make verify-negatives` reports this case's GREEN-NOW half as failing -- that is the
#   definition of a RED spec, and the 1d83 precedent. Once the fix lands, green-now passes and
#   red-there reproduces the defect from the three pinned paths. All three are pinned because
#   the fix may be spelled in the library or at either call site; reverting all three reproduces
#   the defect wherever it was written.)
#
# HERMETIC -- every path the code under test resolves is injected. This matters more than usual:
# on 2026-09-10 a test in this repo destroyed 19 live production units by inheriting ONE default
# path into real state (id:1975), and `inbox-done` DELETES lines from a local-only store that
# holds 2 live items right now. What is isolated, and why:
#   HOME            -- last-resort default of everything below, and the root of the real inbox
#                      ($HOME/.claude/projects/todo-inbox.md). resolve_inbox() also MIGRATES a
#                      legacy $HOME/.claude/todo-inbox.md with `mv`; under the real HOME that is
#                      a destructive move of the live queue.
#   RELAY_INBOX     -- the inbox store itself (inbox-done deletes from it; the add path appends).
#   SRC_DIR         -- target-repo resolution fallback ($SRC_DIR/<name>).
#   RELAY_TOML      -- target-repo resolution via relay.toml (the real one is the fleet set).
#   SCAN_ROUTED_LOG -- scan-routed.sh appends to ~/.claude/logs/scan-routed.log by default.
#   CLAIM_BASE      -- scan-routed.sh's `claim.sh peek` reads ~/.config/relay by default.
# Nothing is written outside $FIX; no network; no git repo is created (report mode and the
# twin-present RESOLVED path need none -- neither reaches commit-ledger.sh).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-anchored-id.sh"
APPEND="$ROOT/meeting/append.sh"
SCAN="$ROOT/relay/scripts/scan-routed.sh"

fails=0
pass() { echo "PASS: $*"; }
note() { echo "FAIL: $*"; fails=$((fails + 1)); }
die() { echo "FAIL: $*"; exit 1; }

[[ -f "$LIB" ]] || die "precondition: lib-anchored-id.sh not found at $LIB"
[[ -f "$APPEND" ]] || die "precondition: append.sh not found at $APPEND"
[[ -x "$SCAN" ]] || die "precondition: scan-routed.sh not found or not executable at $SCAN"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# --- THE LINE SHAPES, defined ONCE ------------------------------------------------------
# Every site below is asked about the SAME text, which is the only way assertion 1 ("all
# three resolve the same token") can mean anything.
#   _CITE   -- a BARE backticked citation of a foreign token + the line's own trailing marker.
#              This is the shape the conventions mandate for a citation.
#   _PROSE  -- own marker FOLLOWED BY TRAILING PROSE (id:798d). Legal, and unresolvable today.
#   _QUOTED -- a foreign marker quoted LITERALLY (backticks do not de-literalise it for any
#              regex here) + own trailing marker. This is the shape of both LIVE inbox items.
#   _PLAIN  -- the ordinary conforming line: the no-regression control.
#   _NOOWN  -- a citation and NO own marker: owns nothing.
#   _HEADER -- a non-checkbox comment line carrying a marker-shaped string: owns nothing.
L_CITE='- [ ] [depot] cites `routed:a1a1` in prose (from meeting, n.md) <!-- routed:b1b1 -->'
L_PROSE='- [ ] [depot] the routed work (from meeting, n.md) <!-- routed:b2b2 --> -- GATED (auto, id:3801)'
L_QUOTED='- [ ] [depot] quotes a marker `<!-- routed:a3a3 -->` in prose (from meeting, n.md) <!-- routed:b3b3 -->'
L_PLAIN='- [ ] [depot] a plain conforming item (from meeting, n.md) <!-- routed:b4b4 -->'
L_NOOWN='- [ ] [depot] only cites `routed:a5a5` (from meeting, n.md)'
L_HEADER='# Line format: - [ ] [<target>] <desc> (from <src>, <note>) <!-- routed:a7a7 -->'
# The add path's shape: own marker FIRST, a literally-quoted foreign marker in the TRAILING
# prose. `tail -1` picks the citation, so the token echoed as "what was filed" is a foreign one.
L_ADD='- [ ] [depot] a newly routed item (from meeting, n.md) <!-- routed:b6b6 --> -- supersedes `<!-- routed:a6a6 -->`'
# The same shape with the citation spelled CONFORMINGLY (a bare backticked token): one
# anchored marker, so it files cleanly. This is case 8's positive control.
L_ADD_OK='- [ ] [depot] a newly routed item (from meeting, n.md) <!-- routed:b7b7 --> -- supersedes `routed:a6a6`'

# --- site 1: the shared library extractor -----------------------------------------------
# A tiny runner so a MISSING function is reported as a clean failure per case instead of
# aborting the file (the function does not exist yet -- that is the point).
cat >"$FIX/ask.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
source "$1"
declare -F inbox_line_own_token >/dev/null 2>&1 || {
  echo "inbox_line_own_token is NOT DEFINED in lib-anchored-id.sh" >&2; exit 9; }
inbox_line_own_token "$2" "${3:-}"
EOS

ASK_OUT=""; ASK_ERR=""; ASK_RC=0
ask() {  # ask <line> -- sets ASK_OUT / ASK_ERR / ASK_RC
  ASK_RC=0
  ASK_OUT="$(bash "$FIX/ask.sh" "$LIB" "$1" "fixture:1" 2>"$FIX/ask.err")" || ASK_RC=$?
  ASK_ERR="$(cat "$FIX/ask.err")"
}

# --- case 1: a BARE prose citation never wins; the own trailing marker does --------------
ask "$L_CITE"
if [[ $ASK_RC -ne 0 || "$ASK_OUT" != "routed:b1b1" ]]; then
  note "(1) inbox_line_own_token must resolve a line that CITES a foreign token to its OWN trailing marker: got rc=$ASK_RC out='$ASK_OUT' (want rc=0 out='routed:b1b1'). A prose citation winning is the id:c97c class that deleted three inbox items.
--- stderr ---
$ASK_ERR"
else
  pass "(1) library: a bare prose citation loses to the line's own trailing marker"
fi

# --- case 2: TRAILING PROSE after the marker still OWNS the token (id:798d) --------------
# This is the third row of the three-way table and the worse half of the defect: under
# inbox-done's end-of-line anchor such a line is owned by NOBODY.
ask "$L_PROSE"
if [[ $ASK_RC -ne 0 || "$ASK_OUT" != "routed:b2b2" ]]; then
  note "(2) inbox_line_own_token must honour id:798d -- a marker FOLLOWED BY TRAILING PROSE still owns its token: got rc=$ASK_RC out='$ASK_OUT' (want rc=0 out='routed:b2b2')
--- stderr ---
$ASK_ERR"
else
  pass "(2) library: trailing prose after the marker does not destroy ownership (id:798d)"
fi

# --- case 3: TWO anchored markers -> REFUSE loudly, never guess (id:6059) ----------------
# The live-inbox shape. See the CONTESTED CONSEQUENCE note in the header.
ask "$L_QUOTED"
if [[ $ASK_RC -ne 3 || -n "$ASK_OUT" ]]; then
  note "(3) a line carrying TWO anchored routed markers must REFUSE with exit 3 and print nothing: got rc=$ASK_RC out='$ASK_OUT' (want rc=3, empty stdout). Reuse own_routed_of_line's id:6059 refusal rather than inventing a second spelling
--- stderr ---
$ASK_ERR"
elif ! grep -q 'a3a3' <<<"$ASK_ERR" || ! grep -q 'b3b3' <<<"$ASK_ERR"; then
  note "(4) the refusal must NAME every candidate on stderr so an operator can fix the line: stderr did not mention both a3a3 and b3b3
--- stderr ---
$ASK_ERR"
else
  pass "(3+4) library: a multi-marker line is refused (exit 3) and both candidates are named"
fi

# --- case 5: CONTROL -- the ordinary shapes must not regress -----------------------------
# A fix that widens or narrows the predicate into uselessness is worse than the bug.
ctl=0
ask "$L_PLAIN"
[[ $ASK_RC -eq 0 && "$ASK_OUT" == "routed:b4b4" ]] || { ctl=1; ctl_why="plain conforming line gave rc=$ASK_RC out='$ASK_OUT' (want rc=0 routed:b4b4)"; }
ask "$L_NOOWN"
[[ $ASK_RC -eq 1 && -z "$ASK_OUT" ]] || { ctl=1; ctl_why="${ctl_why:-}; citation-only line gave rc=$ASK_RC out='$ASK_OUT' (want rc=1, empty)"; }
ask "$L_HEADER"
[[ $ASK_RC -eq 1 && -z "$ASK_OUT" ]] || { ctl=1; ctl_why="${ctl_why:-}; non-checkbox header line gave rc=$ASK_RC out='$ASK_OUT' (want rc=1, empty)"; }
if [[ $ctl -ne 0 ]]; then
  note "(5) CONTROL BROKEN -- ${ctl_why}. The extractor must still resolve a plain conforming line, and must own NOTHING on a citation-only line or a non-checkbox comment line (the inbox's own header carries a marker-shaped string)"
else
  pass "(5) control: plain line resolves; citation-only and non-checkbox lines own nothing"
fi

# --- fixture builder for the two behavioural sites --------------------------------------
# scenario <name> <target> -- isolated HOME + src tree with one target repo (all four ledger
# files present, none carrying any fixture token) and an empty inbox. Sets SC_* globals, so
# it must NOT be called in a command substitution.
scenario() {
  SC_TGT="$2"
  SC_DIR="$FIX/$1"
  SC_HOME="$SC_DIR/home"
  SC_SRC="$SC_DIR/src"
  SC_REPO="$SC_SRC/$SC_TGT"
  mkdir -p "$SC_HOME" "$SC_REPO" "$SC_DIR/claims"
  printf '# TODO\n\n- [ ] an unrelated live item <!-- id:9901 -->\n' >"$SC_REPO/TODO.md"
  printf '# ROADMAP\n\n- [ ] an unrelated live item <!-- id:9902 -->\n' >"$SC_REPO/ROADMAP.md"
  printf '# TODO archive\n' >"$SC_REPO/TODO.archive.md"
  printf '# ROADMAP archive\n' >"$SC_REPO/ROADMAP.archive.md"
  SC_TOML="$SC_DIR/relay.toml"
  cat >"$SC_TOML" <<EOF
[repos.$SC_TGT]
classification = "own"
path = "$SC_REPO"
EOF
  SC_INBOX="$SC_DIR/inbox.md"
  printf '# Cross-project TODO inbox\n\n' >"$SC_INBOX"
}
inbox_add() { printf '%s\n' "$1" >>"$SC_INBOX"; }          # seed a fixture inbox line
twin_add() { printf '%s\n' "- [x] the landed item <!-- routed:$1 --> on 2026-09-10" >>"$SC_REPO/TODO.md"; }
# is that exact line still there? `--` is load-bearing: every fixture line starts with `-`,
# which grep would otherwise read as an option bundle (and the resulting nonzero exit would
# read as "the line is gone", silently turning cases 6/7/10 green).
has_line() { grep -qF -- "$1" "$SC_INBOX"; }

run_done() {  # run_done <token> -- append.sh inbox-done, fully injected; echoes nothing
  DONE_RC=0
  HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    bash "$APPEND" inbox-done "$1" >"$SC_DIR/done.out" 2>"$SC_DIR/done.err" || DONE_RC=$?
}

run_scan() {  # run_scan [args...] -- scan-routed.sh, fully injected; stdout+stderr captured
  SCAN_RC=0
  HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    SCAN_ROUTED_LOG="$SC_DIR/scan.log" CLAIM_BASE="$SC_DIR/claims" \
    bash "$SCAN" "$@" >"$SC_DIR/scan.out" 2>"$SC_DIR/scan.err" || SCAN_RC=$?
  SCAN_OUT="$(cat "$SC_DIR/scan.out")"
  SCAN_ERR="$(cat "$SC_DIR/scan.err")"
}

# --- case 6: site 2 (inbox-done) must resolve the TRAILING-PROSE line -------------------
# The id:798d line with its twin present must DRAIN. Today inbox-done's `\s*$` anchor finds no
# owning line, silently takes the nothing-to-delete branch, exits 0, and the line is immortal.
scenario done_prose depot
inbox_add "$L_PROSE"
twin_add b2b2
run_done b2b2
surv=no; has_line "$L_PROSE" && surv=yes
if [[ $DONE_RC -ne 0 || $surv == yes ]]; then
  note "(6) inbox-done must drain a line whose marker is followed by TRAILING PROSE (id:798d): exit=$DONE_RC (want 0) line-survives=$surv (want no). A legal line shape that NO token owns can never be resolved, while scan-routed reports it RESOLVED
--- inbox line ---
$(cat "$SC_INBOX")
--- stderr ---
$(cat "$SC_DIR/done.err")"
else
  pass "(6) inbox-done drains the id:798d trailing-prose line"
fi

# --- case 7: site 2 CONTROL + the multi-marker refusal ----------------------------------
# (a) A CITED foreign token must never drain the citing line, even when that token has a twin
#     of its own -- the id:c97c deletion class, which must stay fixed.
# (b) A multi-marker line must be REFUSED (nonzero), not drained on a positional guess, and
#     not silently no-op'd. See the CONTESTED CONSEQUENCE note.
scenario done_control depot
inbox_add "$L_CITE"
inbox_add "$L_QUOTED"
twin_add a1a1
twin_add a3a3
twin_add b3b3
run_done a1a1
ok7a=yes; has_line "$L_CITE" || ok7a=no
rc7a=$DONE_RC
run_done b3b3
ok7b=yes; has_line "$L_QUOTED" || ok7b=no
if [[ $ok7a != yes ]]; then
  note "(7a) CONTROL BROKEN -- \`inbox-done a1a1\` DELETED the line that merely CITES a1a1 (exit=$rc7a). That is the id:c97c class verbatim; the inbox is local-only and the delete is unrecoverable
--- inbox now ---
$(cat "$SC_INBOX")"
elif [[ $DONE_RC -eq 0 || $ok7b != yes ]]; then
  note "(7b) a multi-marker inbox line must be REFUSED LOUDLY by inbox-done, never drained on a positional guess and never a silent exit-0 no-op: exit=$DONE_RC (want nonzero) line-survives=$ok7b (want yes)
--- stderr ---
$(cat "$SC_DIR/done.err")"
else
  pass "(7) inbox-done: a cited token drains nothing, and a multi-marker line is refused loudly"
fi

# --- case 8: site 3 (the add path) -- POSITIVE receipt, and a LOUD refusal ---------------
# append.sh -t inbox echoes the token PARSED BACK OUT of the line it wrote, so a caller can
# say `filed routed:$(append.sh ...)`. With `tail -1`, a literally-quoted marker in the
# TRAILING prose wins and the echoed token names an item that was never filed.
#
# THIS CASE ASSERTS BOTH DIRECTIONS ON PURPOSE (adversarial review 2026-09-10, D9): it used
# to assert ONLY that stdout lacks the foreign token, which is satisfied by printing
# NOTHING -- including by deleting site 3's adoption entirely. A spec whose own header
# invokes the id:ae08 built-but-unwired class must not itself be passable by removing the
# wiring. So: (8a) a conforming entry must produce its OWN token on stdout, and (8b) the
# two-marker entry must be refused LOUDLY, nonzero, with nothing appended.
scenario add_path depot
add_entry() {  # add_entry <line> -- sets ADD_RC / ADD_OUT
  ADD_RC=0
  ADD_OUT="$(HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    bash "$APPEND" -t inbox -e "$1" 2>"$SC_DIR/add.err")" || ADD_RC=$?
}

# (8a) POSITIVE: the conforming entry's own token IS the receipt, and the line is on disk.
add_entry "$L_ADD_OK"
if [[ $ADD_RC -ne 0 || "$ADD_OUT" != "b7b7" ]] || ! has_line "$L_ADD_OK"; then
  note "(8a) the add path must echo the entry's OWN token as the filing receipt: rc=$ADD_RC stdout='$ADD_OUT' (want rc=0 stdout='b7b7'), line-on-disk=$(has_line "$L_ADD_OK" && echo yes || echo no). A receipt that prints NOTHING is not a pass -- it is site 3's adoption removed (id:ae08)
--- stderr ---
$(cat "$SC_DIR/add.err")"
else
  pass "(8a) the add path echoes the entry's own token (stdout='$ADD_OUT') and the line is on disk"
fi

# (8b) NEGATIVE: the two-marker entry is REFUSED, loudly, and nothing is appended.
add_entry "$L_ADD"
add_err="$(cat "$SC_DIR/add.err")"
if grep -q 'a6a6' <<<"$ADD_OUT"; then
  note "(8b) the add path echoed the FOREIGN token a6a6 as the filed token (stdout='$ADD_OUT'). stdout is contractually 'what landed on disk', so this is a false filing report: the line's own token is b6b6
--- stderr ---
$add_err"
elif [[ $ADD_RC -eq 0 ]]; then
  note "(8b) a two-marker inbox entry must be REFUSED, not filed silently: rc=$ADD_RC (want nonzero). No resolver can attribute it (id:6059), so once written it can never be drained
--- stderr ---
$add_err"
elif has_line "$L_ADD"; then
  note "(8b) the refused two-marker entry was nevertheless APPENDED to the store (rc=$ADD_RC). A nonzero \`-t inbox\` exit means 'nothing appended' -- a caller that retries would DOUBLE-FILE it
--- inbox now ---
$(cat "$SC_INBOX")"
elif ! grep -q 'b6b6' <<<"$add_err" || ! grep -q 'a6a6' <<<"$add_err"; then
  note "(8b) the refusal must NAME the offending entry and its competing tokens on stderr so an operator can fix it: stderr did not mention both b6b6 and a6a6
--- stderr ---
$add_err"
else
  pass "(8b) a two-marker entry is refused loudly (rc=$ADD_RC), nothing is appended, both tokens are named"
fi

# --- case 9: site 4 (scan-routed report) must not attribute a line to a CITED token ------
# Own token b3b3 has NO twin; the quoted citation a3a3 DOES. Today `head -1` picks a3a3 and the
# line is reported RESOLVABLE -- the real dead-letter question is never asked for b3b3.
scenario scan_report depot
inbox_add "$L_QUOTED"
twin_add a3a3
run_scan
bad9=""
grep -qE '(RESOLVABLE|RESOLVED|DEAD-LETTER|APPLIED|UNRESOLVED) routed:a3a3' <<<"$SCAN_OUT" \
  && bad9="a verdict was attributed to the CITED token a3a3"
if [[ -z "$bad9" ]] && ! grep -qE 'b3b3|AMBIGU|REFUS' <<<"$SCAN_OUT$SCAN_ERR"; then
  bad9="the line vanished from the report entirely -- neither its own token b3b3 nor a refusal is mentioned"
fi
if [[ -n "$bad9" ]]; then
  note "(9) scan-routed.sh must not resolve an inbox line to a token it merely CITES: $bad9. The own token b3b3 has no twin, so this line is either a DEAD-LETTER for b3b3 or a loud multi-marker REFUSAL -- never a RESOLVABLE for a3a3, and never silently dropped
--- report ---
$SCAN_OUT
--- stderr ---
$SCAN_ERR"
else
  pass "(9) scan-routed does not attribute an inbox line to a cited foreign token"
fi

# --- case 10: the silent no-op must be LOUD (id:4347) -----------------------------------
# --apply on the id:798d line whose OWN token IS twinned: scan-routed resolves b2b2, calls
# inbox-done b2b2, which cannot find the owning line, exits 0, and scan-routed prints
# `RESOLVED ... removed from inbox` while the line is still there. The invariant specced here
# is weaker than "the drain must succeed" on purpose -- it holds however the sites are fixed:
# scan-routed may only claim RESOLVED if the line is actually gone.
scenario apply_loud depot
inbox_add "$L_PROSE"
twin_add b2b2
run_scan --apply
said_resolved=no
grep -qE 'RESOLVED routed:b2b2' <<<"$SCAN_OUT" && said_resolved=yes
surv10=no; has_line "$L_PROSE" && surv10=yes
if [[ $said_resolved == yes && $surv10 == yes ]]; then
  note "(10) SILENT NO-OP REPORTED AS SUCCESS -- scan-routed.sh --apply printed \`RESOLVED routed:b2b2 ... removed from inbox\` while the inbox line SURVIVES. inbox-done's no-op exit 0 is swallowed by \`2>/dev/null || true\`; either the drain must work or the RESOLVED claim must not be printed (id:4347, id:d35a)
--- report ---
$SCAN_OUT
--- inbox now ---
$(cat "$SC_INBOX")"
elif [[ $surv10 == yes ]]; then
  note "(10b) the twinned id:798d line was NOT drained by --apply (line still present), though scan-routed correctly withheld the RESOLVED claim. Honest, but the line is still immortal -- case 6 is the full fix
--- report ---
$SCAN_OUT"
else
  pass "(10) --apply actually drained the twinned id:798d line; no false RESOLVED claim"
fi

[[ $fails -eq 0 ]] || exit 1
echo "ALL PASS: id:0246 -- one shared inbox_line_own_token, adopted by all call sites"
