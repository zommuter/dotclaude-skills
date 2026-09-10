#!/usr/bin/env bash
# RED SPEC for id:1d83 -- the cross-repo inbox TWIN CHECK must look in the LEDGER ARCHIVES.
#
# NO `# roadmap:` HEADER, ON PURPOSE: id:1d83 is tracked in TODO.md, NOT in ROADMAP.md, so
# the EXPECTED-RED carve-out in tests/run-tests.sh (and the roadmap carve-out in
# tests/lint-vacuous-fixtures.py / tests/verify-negative-cases.py) must NOT apply. This
# file's failures ALWAYS count.
#
# THE DEFECT (observed live 2026-09-10, twice in one session; see docs/ledger-notes/1d83.md).
# A routed inbox item is drained with `append.sh inbox-done XXXX`, which first REFUSES unless
# the token's durable TWIN landed in the target repo (the id:9fdb guard -- the inbox store is
# local-only and the delete is unrecoverable). The twin is looked for in exactly two files:
#
#   meeting/append.sh:258          token_marker_in_files "$token" "$tgt/TODO.md" "$tgt/ROADMAP.md"
#   relay/scripts/scan-routed.sh:268   (the same predicate, the same two files)
#
# Neither reads `TODO.archive.md` / `ROADMAP.archive.md`. `todo-update/archive-done.sh`
# archives aggressively -- the id:5355 date guard only protects a line carrying an explicit
# trailing date, so an UNDATED same-session close is swept by the prior-commit branch, which
# the mandated git-diary-workflow -> todo-update order guarantees will match. It swept
# `id:1975` (carrying `<!-- routed:1d58 -->`) within minutes of it being filed. The twin then
# becomes INVISIBLE and the peer's `inbox-done 1d58` refuses with exit 3 forever: the work
# demonstrably landed, the inbox line is stuck, and nothing says why.
#
# THE CONTRACT SPECCED HERE. An ARCHIVED closed item is a durable record of landing, which is
# exactly what the twin is supposed to attest -- so the twin check spans FOUR files:
# TODO.md, ROADMAP.md, TODO.archive.md, ROADMAP.archive.md. `token_marker_in_files` already
# greps with `-qs`, so naming an absent archive file is a silent skip and safe in repos that
# have none.
#
# BOTH CALL SITES ARE PINNED, deliberately. scan-routed.sh's own comment says the two "must
# agree or a successful write is followed by a refused drain"; a spec that pinned only one
# would permit exactly that divergence.
#
# MARKER FORMS COVERED: the HTML-comment owning form in both its spellings -- `<!-- routed:XXXX -->`
# (case 1, the shape of the live incident) and `<!-- id:XXXX -->` (case 2). The third owning
# form, the leading `[INBOUND routed:XXXX …]` ingest-stub tag, is NOT re-tested here: it is the
# same single `_own_marker_re` alternation, already covered by
# tests/test_scan_routed_own_marker_twin_c97c.sh, and nothing about it is archive-specific.
#
# THE CONTROL (case 3) IS LOAD-BEARING, not decoration. The guard exists to stop an
# unrecoverable wrong delete against a local-only store. A "fix" that widens the predicate
# into accepting everything is WORSE than the bug, so a token with NO twin in ANY of the four
# files must still be REFUSED with exit 3 and its inbox line must survive.
#
# fails-against: the two-file twin predicate at meeting/append.sh:258 and
#   relay/scripts/scan-routed.sh:268 (both calling token_marker_in_files with only TODO.md +
#   ROADMAP.md), which cannot see a `routed:` breadcrumb that archive-done.sh has moved into
#   TODO.archive.md / ROADMAP.archive.md.
# fails-against-rev: a01627fc2e5ded1061c626ecfe7b81bb559830b2 -- meeting/append.sh relay/scripts/scan-routed.sh relay/scripts/lib-anchored-id.sh
# fails-against-assertion: scan-routed.sh still reports an ARCHIVE-ONLY twin as a dead letter
#   (NOTE, while id:1d83 is OPEN: the declared rev is today's unfixed HEAD, so
#   `make verify-negatives` reports this case's GREEN-NOW half as failing -- that is the
#   definition of a RED spec. Once the fix lands, green-now passes and red-there reproduces
#   the defect from the three pinned paths. All three are pinned because the fix may be
#   spelled at the two call sites or inside lib-anchored-id.sh; reverting all three
#   reproduces the defect wherever it was written.)
#
# HERMETIC -- EVERY path the code under test resolves is injected, and this matters more than
# usual here: on 2026-09-10 a test in this repo destroyed 19 live production units by
# inheriting ONE default path into real state (id:1975). What is isolated, and why:
#   HOME             -- the LAST-RESORT default of every other variable below, and the root of
#                       the real inbox store ($HOME/.claude/projects/todo-inbox.md). Pointed
#                       at a scratch dir so that even a variable this comment has MISSED
#                       cannot reach real state. resolve_inbox() also MIGRATES a legacy
#                       $HOME/.claude/todo-inbox.md with `mv` -- under the real HOME that is a
#                       destructive move of the live queue.
#   RELAY_INBOX      -- the inbox store itself; inbox-done DELETES lines from it.
#   SRC_DIR          -- target-repo resolution fallback ($SRC_DIR/<name>); unset it and
#                       `[depot]` would resolve against ~/src.
#   RELAY_TOML       -- target-repo resolution via relay.toml; the real file is the fleet's
#                       own-repo set.
#   SCAN_ROUTED_LOG  -- scan-routed.sh appends to ~/.claude/logs/scan-routed.log by default.
#   CLAIM_BASE       -- scan-routed.sh's claim.sh peek reads ~/.config/relay by default.
# Nothing is written outside $FIX; no network; no git repo is created or touched (report mode
# needs none). Fixture repo/token names are neutral and share no string with any assertion.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
SCAN="$ROOT/relay/scripts/scan-routed.sh"

fails=0
pass() { echo "PASS: $*"; }
note() { echo "FAIL: $*"; fails=$((fails + 1)); }
die() { echo "FAIL: $*"; exit 1; }

[[ -f "$APPEND" ]] || die "precondition: append.sh not found at $APPEND"
[[ -x "$SCAN" ]] || die "precondition: scan-routed.sh not found or not executable at $SCAN"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# scenario <name> <target-repo> <token> -- build an isolated HOME + src tree holding one
# target repo whose LIVE TODO.md/ROADMAP.md do NOT carry <token>, all four ledger files
# present, plus an inbox with one conforming routed item for <token>. Sets the SC_* globals,
# so it is deliberately NOT called in a command substitution (a subshell would discard them).
scenario() {
  SC_TGT="$2"
  SC_TOK="$3"
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
  cat >"$SC_INBOX" <<EOF
# Cross-project TODO inbox

- [ ] [$SC_TGT] the routed work item (from meeting, note.md) <!-- routed:$SC_TOK -->
EOF
}

# run_done -- invoke `append.sh inbox-done <token>` against the current scenario, fully
# injected. Returns the script's exit status; stdout/stderr land in the scenario dir.
run_done() {
  HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    bash "$APPEND" inbox-done "$SC_TOK" >"$SC_DIR/done.out" 2>"$SC_DIR/done.err"
}

# inbox_line_survives -- is the routed item still in the inbox (i.e. was it NOT drained)?
inbox_line_survives() { grep -q "routed:$SC_TOK -->" "$SC_INBOX"; }

# --- case 1: twin ONLY in TODO.archive.md -> inbox-done must ACCEPT and drain -------------
# The live incident verbatim: the closed item carries `<!-- routed:XXXX -->` and has been
# swept into TODO.archive.md by archive-done.sh.
scenario arch_todo depot a1a1
printf '%s\n' '- [x] the closed item that carries the breadcrumb (from meeting) <!-- routed:a1a1 --> on 2026-09-10' \
  >>"$SC_REPO/TODO.archive.md"
rc1=0
run_done || rc1=$?
surv1=no
inbox_line_survives && surv1=yes
if [[ $rc1 -ne 0 || $surv1 == yes ]]; then
  note "(1) a twin present ONLY in TODO.archive.md was REFUSED: inbox-done exited $rc1 (want 0) and the inbox line survives=$surv1 (want no) -- archiving a closed item must not make its routed: breadcrumb invisible to the twin check
--- inbox-done stderr ---
$(cat "$SC_DIR/done.err")"
else
  pass "(1) a twin in TODO.archive.md is accepted: inbox-done exited 0 and drained the line"
fi

# --- case 2: twin ONLY in ROADMAP.archive.md -> inbox-done must ACCEPT and drain ----------
# Same shape, the other archive and the other HTML-comment spelling (`<!-- id:XXXX -->`, the
# single-id-two-views case where the target adopted the routed token as its own id).
scenario arch_roadmap depot b2b2
printf '%s\n' '- [x] the closed roadmap item that owns the token <!-- id:b2b2 --> on 2026-09-10' \
  >>"$SC_REPO/ROADMAP.archive.md"
rc2=0
run_done || rc2=$?
surv2=no
inbox_line_survives && surv2=yes
if [[ $rc2 -ne 0 || $surv2 == yes ]]; then
  note "(2) a twin present ONLY in ROADMAP.archive.md was REFUSED: inbox-done exited $rc2 (want 0) and the inbox line survives=$surv2 (want no)
--- inbox-done stderr ---
$(cat "$SC_DIR/done.err")"
else
  pass "(2) a twin in ROADMAP.archive.md is accepted: inbox-done exited 0 and drained the line"
fi

# --- case 3: CONTROL -- NO twin in ANY of the four files -> must still REFUSE -------------
# The guard's whole purpose. A widening that accepts everything is worse than the bug: the
# inbox store is local-only and vanish-on-resolve, so a wrong delete is unrecoverable.
scenario no_twin depot c3c3
rc3=0
run_done || rc3=$?
surv3=no
inbox_line_survives && surv3=yes
if [[ $rc3 -ne 3 || $surv3 != yes ]]; then
  note "(3) CONTROL BROKEN -- a token with no twin in TODO.md, ROADMAP.md, TODO.archive.md or ROADMAP.archive.md must still be refused: inbox-done exited $rc3 (want 3) and the inbox line survives=$surv3 (want yes). Widening the twin check must not make it accept everything; this delete is unrecoverable
--- inbox-done stderr ---
$(cat "$SC_DIR/done.err")"
else
  pass "(3) control: no twin anywhere is still REFUSED (exit 3) and the inbox line survives"
fi

# --- case 4: the SECOND call site -- scan-routed.sh must not call it a dead letter --------
# Report mode only: non-destructive, writes nothing, needs no git repo. An archive-only twin
# must surface as RESOLVABLE (report) / RESOLVED (--apply), never DEAD-LETTER -- otherwise
# `--apply` writes a duplicate INBOUND stub for work that already landed and then hits the
# refused drain its own comment warns about.
scenario scan_report depot d4d4
printf '%s\n' '- [x] the closed item that carries the breadcrumb (from meeting) <!-- routed:d4d4 --> on 2026-09-10' \
  >>"$SC_REPO/TODO.archive.md"
scan_out="$(HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
  SCAN_ROUTED_LOG="$SC_DIR/scan.log" CLAIM_BASE="$SC_DIR/claims" \
  bash "$SCAN" 2>"$SC_DIR/scan.err")"
saw_dead=no
grep -qE "DEAD-LETTER routed:d4d4" <<<"$scan_out" && saw_dead=yes
saw_ok=no
grep -qE "(RESOLVABLE|RESOLVED) routed:d4d4" <<<"$scan_out" && saw_ok=yes
if [[ $saw_dead == yes || $saw_ok == no ]]; then
  note "(4) scan-routed.sh still reports an ARCHIVE-ONLY twin as a dead letter (DEAD-LETTER=$saw_dead, RESOLVABLE/RESOLVED=$saw_ok) -- the two call sites must ask the same question, or a successful write is followed by a refused drain
--- scan-routed.sh report ---
$scan_out
--- scan-routed.sh stderr ---
$(cat "$SC_DIR/scan.err")"
else
  pass "(4) scan-routed.sh classifies an archive-only twin as RESOLVABLE, not a dead letter"
fi

[[ $fails -eq 0 ]] || exit 1
echo "ALL PASS: id:1d83 twin check spans the ledger archives (4 cases)"
