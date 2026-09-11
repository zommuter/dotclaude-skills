#!/usr/bin/env bash
# Defect-fix / new-feature spec for id:6fda. No `# roadmap:` header (id:6fda lives only in
# TODO.md), so these failures always count.
#
# WHAT THIS PINS: the propose-then-confirm boundary, which is the mechanical half of the
# skill's one inviolable rule -- RECOMMEND, never decide.
#
# `@owner-answered:YYYY-MM-DD` plus its mandatory `<!-- answer-src:... -->` citation is
# OWNER-ONLY by contract (relay/references/executor-contract.md rule 8,
# relay/references/hard-lanes.md "Who may write it"). Its entire value is that only a
# genuine owner action writes it: an agent minting one manufactures an owner ruling out of
# nothing, which is the chidiai
# `2026-07-15-delegated-verdict-settled-without-owner-ratification` failure with a marker
# attached. So the write path must DEFAULT TO REFUSING, and the refusals must be
# distinguishable, because their remedies differ:
#
#   no --apply                        -> propose only, write nothing (exit 0)
#   --apply without --owner-confirmed -> exit 4  (get the owner's answer first)
#   --apply in an unattended context  -> exit 5, EVEN WITH --owner-confirmed
#
# The unattended refusal outranking the confirmation flag is the load-bearing part and the
# reason it is tested separately. Under --afk or in a pool there is no owner to answer an
# AskUserQuestion, so a confirmation flag there can only have been set by an agent -- the
# precise forgery the contract exists to prevent. A refusal that an agent can clear by
# passing one more flag is not a refusal.
#
# Every case asserts the LEDGER BYTES ARE UNCHANGED, not merely the exit code. An exit code
# says what the script reported; the bytes say what it did, and only the second is the
# property that matters here.
#
# HERMETIC: temp HOME and a fixture ledger under `mktemp -d`. Never touches ~/.claude,
# ~/.cache/relay, the real relay.toml, or the network. It also never invokes md-merge.py
# against anything outside the temp tree.
#
# fails-against-mutation: sed -i 's|^  if \[\[ -n "${RELAY_AFK:-}|  if [[ -z "${RELAY_AFK:-}|' decision-brief/docket.sh
# fails-against-assertion: (g) the sanctioned attended+confirmed write failed
#   The mutation INVERTS the unattended sentinel test, so the guard fires exactly when it
#   should not and stays quiet when it should. That reddens the four (c) cases, every
#   `unchanged` check after them, and finally case (g) -- the positive control, which is
#   refused with exit 5 in a perfectly attended session. (g) is the LAST line to fire, and
#   naming it is also the honest choice: an inverted guard's most damaging symptom is not
#   that it lets a pool write, it is that it blocks the owner.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/decision-brief/docket.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -x "$SCRIPT" ]] || { echo "FAIL: docket.sh not found or not executable at $SCRIPT"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/repo/docs/meeting-notes"

LEDGER="$tmp/repo/TODO.md"
cat > "$LEDGER" <<'EOF'
# TODO

## Current
- [ ] [INPUT - decision] **A decision the owner has not made yet** <!-- id:aaaa -->
- [ ] [INPUT - decision] **A line carrying two anchored markers** <!-- id:bbbb --> <!-- id:cccc -->

## Done
EOF
printf '# Decisions\n\nThe owner said yes.\n' > "$tmp/repo/docs/meeting-notes/note.md"

BEFORE="$(cksum < "$LEDGER")"

unchanged() {  # unchanged <label>
  local now; now="$(cksum < "$LEDGER")"
  if [[ "$now" != "$BEFORE" ]]; then
    fail "$1: THE LEDGER WAS MODIFIED -- a refused write must leave the bytes untouched"
    return 1
  fi
  return 0
}

draft() {  # draft <extra args...>
  HOME="$tmp/home" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  DECISION_BRIEF_MD_MERGE="$ROOT/meeting/md-merge.py" \
    bash "$SCRIPT" draft-answer \
      --repo-path "$tmp/repo" --id aaaa \
      --answer "the owner picked option B" \
      --answer-src "docs/meeting-notes/note.md#Decisions" \
      "$@" 2>"$tmp/err.txt"
}

# --- (a) PROPOSE: prints the exact line, writes nothing --------------------------------
out="$(draft)"; rc=$?
if [[ $rc -ne 0 ]]; then
  fail "(a) the propose path exited $rc, expected 0: $(cat "$tmp/err.txt")"
else
  pass "(a) the propose path succeeds"
fi

if ! grep -q '@owner-answered:' <<<"$out"; then
  fail "(a) the proposal does not show the @owner-answered line it would write"
elif ! grep -q 'answer-src:docs/meeting-notes/note.md#Decisions' <<<"$out"; then
  fail "(a) the proposal does not show the mandatory answer-src citation"
else
  pass "(a) the proposal shows the exact line, marker and citation, for the owner to approve"
fi

unchanged "(a)" && pass "(a) proposing wrote nothing"

# --- (b) --apply WITHOUT --owner-confirmed must refuse ---------------------------------
draft --apply >/dev/null; rc=$?
if [[ $rc -ne 4 ]]; then
  fail "(b) --apply without --owner-confirmed exited $rc, expected the refusal 4"
else
  pass "(b) --apply without --owner-confirmed is refused with exit 4"
fi
if ! grep -qi 'refus' "$tmp/err.txt"; then
  fail "(b) the refusal was silent on stderr"
else
  pass "(b) the refusal is loud on stderr"
fi
unchanged "(b)" && pass "(b) a refused --apply wrote nothing"

# --- (c) an UNATTENDED context refuses EVEN WITH the confirmation flag -----------------
# Each of the four sentinels is checked independently: an OR-chain that only reads its
# first element would pass a single-variable test and leak on the other three.
for sentinel in RELAY_AFK RELAY_RUN_ID RELAY_POOL DECISION_BRIEF_UNATTENDED; do
  rc=0
  env "$sentinel=1" \
    HOME="$tmp/home" \
    DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
    DECISION_BRIEF_MD_MERGE="$ROOT/meeting/md-merge.py" \
      bash "$SCRIPT" draft-answer \
        --repo-path "$tmp/repo" --id aaaa \
        --answer "the owner picked option B" \
        --answer-src "docs/meeting-notes/note.md#Decisions" \
        --apply --owner-confirmed >/dev/null 2>"$tmp/err.txt" || rc=$?
  if [[ $rc -ne 5 ]]; then
    fail "(c) an UNATTENDED context did not refuse: $sentinel=1 with --owner-confirmed exited $rc, expected 5"
  else
    pass "(c) $sentinel=1 refuses with exit 5 despite --owner-confirmed"
  fi
  unchanged "(c) $sentinel" || true
done

# --- (d) a multi-marker line is refused rather than handed to md-merge.py --------------
rc=0
HOME="$tmp/home" \
DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
DECISION_BRIEF_MD_MERGE="$ROOT/meeting/md-merge.py" \
  bash "$SCRIPT" draft-answer \
    --repo-path "$tmp/repo" --id bbbb \
    --answer "x" --answer-src "docs/meeting-notes/note.md" >/dev/null 2>"$tmp/err.txt" || rc=$?
if [[ $rc -eq 0 ]]; then
  fail "(d) a line carrying two anchored id markers was accepted (id:6059 says md-merge REFUSES it)"
else
  pass "(d) a multi-marker line is refused up front (exit $rc)"
fi
unchanged "(d)" && pass "(d) the multi-marker refusal wrote nothing"

# --- (e) the mandatory citation is mandatory ------------------------------------------
rc=0
HOME="$tmp/home" \
DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  bash "$SCRIPT" draft-answer --repo-path "$tmp/repo" --id aaaa \
    --answer "no citation given" >/dev/null 2>"$tmp/err.txt" || rc=$?
if [[ $rc -eq 0 ]]; then
  fail "(e) a proposal with no --answer-src was accepted -- a marker with no citation is worthless"
else
  pass "(e) a missing --answer-src is refused (exit $rc)"
fi
unchanged "(e)" && pass "(e) the missing-citation refusal wrote nothing"

# --- (f) an unknown id is refused rather than invented --------------------------------
rc=0
HOME="$tmp/home" \
DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  bash "$SCRIPT" draft-answer --repo-path "$tmp/repo" --id 9999 \
    --answer "x" --answer-src "docs/meeting-notes/note.md" >/dev/null 2>"$tmp/err.txt" || rc=$?
if [[ $rc -eq 0 ]]; then
  fail "(f) an id with no anchored line in the ledger was accepted -- the tool invented a target"
else
  pass "(f) an id with no anchored ledger line is refused (exit $rc)"
fi
unchanged "(f)" && pass "(f) the unknown-id refusal wrote nothing"

# --- (g) THE CONTROL ON THE CONTROLS: the write path actually works -------------------
# Every assertion above is satisfiable by a write path that is simply broken, and a broken
# write path passing a refusal suite is the unreached-fixture failure: the refusals would
# prove nothing. So the last case exercises the sanctioned path -- attended context,
# explicit owner confirmation -- and requires the marker to actually land.
rc=0
env -u RELAY_AFK -u RELAY_RUN_ID -u RELAY_POOL -u DECISION_BRIEF_UNATTENDED \
  HOME="$tmp/home" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  DECISION_BRIEF_MD_MERGE="$ROOT/meeting/md-merge.py" \
    bash "$SCRIPT" draft-answer \
      --repo-path "$tmp/repo" --id aaaa \
      --answer "the owner picked option B" \
      --answer-src "docs/meeting-notes/note.md#Decisions" \
      --date 2026-09-11 \
      --apply --owner-confirmed >/dev/null 2>"$tmp/err.txt" || rc=$?

if [[ $rc -ne 0 ]]; then
  fail "(g) the sanctioned attended+confirmed write failed (exit $rc): $(cat "$tmp/err.txt")"
else
  pass "(g) the sanctioned attended+confirmed write succeeds"
fi

target="$(grep -F -- '<!-- id:aaaa -->' "$LEDGER" || true)"
if [[ "$target" != *'@owner-answered:2026-09-11'* ]]; then
  fail "(g) the confirmed write did not land the @owner-answered marker -- every refusal above was vacuous"
elif [[ "$target" != *'<!-- answer-src:docs/meeting-notes/note.md#Decisions -->'* ]]; then
  fail "(g) the confirmed write landed the marker WITHOUT its mandatory citation"
elif [[ "$target" != *'<!-- id:aaaa -->' ]]; then
  fail "(g) the anchored id marker is no longer line-final after the write: $target"
else
  pass "(g) the confirmed write lands the marker, its citation, and keeps the id marker line-final"
fi

# The OTHER item on the ledger must be untouched: md-merge addresses ONE anchored line.
if ! grep -qF -- '- [ ] [INPUT - decision] **A line carrying two anchored markers** <!-- id:bbbb --> <!-- id:cccc -->' "$LEDGER"; then
  fail "(g) the write disturbed a neighbouring ledger line"
else
  pass "(g) the write touched only the addressed line"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "ALL PASS: decision-brief write refusals (id:6fda)"
  exit 0
fi
echo "$fails assertion(s) failed"
exit 1
