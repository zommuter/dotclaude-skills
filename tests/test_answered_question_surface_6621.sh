#!/usr/bin/env bash
# roadmap:6621
#
# SPEC for id:6621 -- the CONSUMER side of the `@owner-answered` marker (id:ca14), plus
# the two owner-only ENFORCEMENT arms ca14 shipped without.
#
# WHY -- ca14 added the marker and a `roadmap-lint.sh` rule 3(h) that validates its
# GRAMMAR. An adversarial review rebuilt the loderite `id:ed3a` incident with a CONFORMING
# marker on it and got exit 0, zero findings: rule 3(h) never reads the cited answer, and
# nothing on the consumer side ever shows a recorded answer to the person about to re-ask
# the question. It also found the marker FORGEABLE -- `hard-lanes.md` called it owner-only
# citing `@owner-accepted` (id:8089) as precedent, but 8089's two enforcement arms
# (executor-contract rule 7, review.md step 7) had no `@owner-answered` twin, so an
# executor could mint one and nothing would flag it.
#
# WHAT THIS PINS
#   A  an open item carrying `@owner-answered` emits an `answered_question` row naming its
#      `answer-src:` citation
#   B  SURFACE, NEVER SUPPRESS -- the same item still emits every row it emitted before
#      (its lane bucket / review_me row is untouched)
#   C  an unmarked item emits NO `answered_question` row (no blanket flagging)
#   D  a backticked MENTION of the marker is not a marker (the id:05b0/af48 anchoring
#      class, inherited from is_manual_marker)
#   E  TODO.md and REVIEW_ME.md are covered too, not just ROADMAP.md
#   F  a marked line whose citation is MISSING is still surfaced, loudly labelled -- the
#      collector never drops an uncited claim (that is exactly what a re-asker must see)
#   G  executor-contract.md forbids an executor writing the marker (arm 1)
#   H  review.md greps the reviewed diff for it (arm 2)
#   I  review.md flags a diff that MODIFIES an already-marked line (re-ask (1))
#
# Hermetic: temp RELAY_TOML + temp own repo under mktemp -d; HOME/SRC_DIR redirected, the
# real registry and the real ~/.claude are never read or written. No network.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"
CONTRACT="$ROOT/relay/references/executor-contract.md"
REVIEW="$ROOT/relay/references/review.md"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -x "$SCRIPT" ]] || { echo "FAIL: gather-human-backlog.sh not found/executable at $SCRIPT" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src/repoA/docs"
echo "# Decisions" >"$tmp/src/repoA/docs/genre-call.md"

# ROADMAP.md
#   id:aa01  the ed3a shape: an OPEN [HARD] item with a recorded answer inside it.
#            Must emit answered_question AND keep its hard-lane row.
#   id:aa02  no marker at all                  -> no answered_question row
#   id:aa03  a backticked MENTION of the marker -> no answered_question row
cat >"$tmp/src/repoA/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [INPUT - meeting] engine work; the genre question is settled @owner-answered:2026-08-14 <!-- answer-src:docs/genre-call.md#Decisions --> <!-- id:aa01 -->
- [ ] [INPUT - meeting] pick a serialization format for the save file <!-- id:aa02 -->
- [ ] [INPUT - meeting] document how `@owner-answered:2026-08-14` markers are spelled <!-- id:aa03 -->
MD

# TODO.md -- id:aa04 marked, cited by ledger id (E)
cat >"$tmp/src/repoA/TODO.md" <<'MD'
# TODO

- [ ] [INPUT - decision] addon mechanism scope @owner-answered:2026-08-14 <!-- answer-src:id:aa01 --> <!-- id:aa04 -->
MD

# REVIEW_ME.md -- id:aa05 marked WITHOUT a citation (F); id:aa06 plain (C)
cat >"$tmp/src/repoA/REVIEW_ME.md" <<'MD'
# Review me

- [ ] Should genres ship as build-time content? @owner-answered:2026-08-14 <!-- id:aa05 -->
- [ ] Is this interpretation of the spec right? <!-- id:aa06 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoA]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" HOME="$tmp/home" bash "$SCRIPT" 2>"$tmp/err")"
rc=$?
set -e
(( rc == 0 )) || note "the fixture must collect cleanly (exit 0), got $rc; stderr: $(head -c 400 "$tmp/err")"

kinds_of() { awk -F'\t' -v tok="$1" 'index($4, tok) { printf "%s ", $3 }' <<<"$out"; }
has_kind() { grep -qw -- "$2" <<<"$(kinds_of "$1")"; }
row_of()   { awk -F'\t' -v tok="$1" '$3=="answered_question" && index($4, tok) { print $4 }' <<<"$out"; }

# -- (A) the marked ROADMAP item is surfaced, with its citation named -------------------
has_kind 'id:aa01' answered_question \
  || note "(A) an OPEN item carrying @owner-answered emitted NO answered_question row -- a human triage or a /meeting agenda still sees no sign the owner already answered, which is re-asks (2) and (3) of the loderite id:ed3a incident. Emitted kinds: $(kinds_of 'id:aa01')"
grep -q 'docs/genre-call.md#Decisions' <<<"$(row_of 'id:aa01')" \
  || note "(A) the answered_question row must NAME the answer-src citation so the reader can open the recorded answer without re-deriving it. Row: $(row_of 'id:aa01')"

# -- (B) SURFACE, NEVER SUPPRESS: the lane row must survive untouched -------------------
has_kind 'id:aa01' hard_meeting \
  || note "(B) the marked item LOST its hard_meeting lane row -- the marker says ONE QUESTION inside the item is answered, NOT that the item is done. Silently removing an answered item from a human's list is a worse failure than the re-ask being fixed. Emitted kinds: $(kinds_of 'id:aa01')"
has_kind 'id:aa05' review_me \
  || note "(B) the marked REVIEW_ME box LOST its review_me row -- same suppression failure on the REVIEW_ME path. Emitted kinds: $(kinds_of 'id:aa05')"

# -- (C) unmarked items are NOT flagged ------------------------------------------------
! has_kind 'id:aa02' answered_question \
  || note "(C) an item with NO marker was flagged as having a recorded answer -- blanket flagging destroys the signal"
! has_kind 'id:aa06' answered_question \
  || note "(C) an unmarked REVIEW_ME box was flagged as answered"

# -- (D) a backticked MENTION is not a marker ------------------------------------------
! has_kind 'id:aa03' answered_question \
  || note "(D) an item merely DISCUSSING the \`@owner-answered\` spelling was treated as carrying the marker -- the id:05b0/af48 unanchored-substring class; mask backticks before matching"

# -- (E) TODO.md is covered, not just ROADMAP.md ---------------------------------------
has_kind 'id:aa04' answered_question \
  || note "(E) a TODO.md item carrying the marker was invisible -- TODO-blindness is the id:4e67/e9cd gap; the marker must be surfaced from every ledger the collector already reads. Emitted kinds: $(kinds_of 'id:aa04')"

# -- (F) a marked line with NO citation is still surfaced, loudly -----------------------
has_kind 'id:aa05' answered_question \
  || note "(F) a marked line whose citation is MISSING was dropped -- an uncited owner-answer claim is precisely what a re-asker needs to see; surface it and label it"
grep -qi 'MISSING CITATION' <<<"$(row_of 'id:aa05')" \
  || note "(F) the uncited row must SAY the citation is missing (roadmap-lint rule 3(h)'s error), not present as a normal citation. Row: $(row_of 'id:aa05')"

# -- (G) arm 1: the executor contract forbids writing the marker -----------------------
grep -q '@owner-answered' "$CONTRACT" \
  || note "(G) relay/references/executor-contract.md never mentions @owner-answered -- an executor can mint the owner-only marker and no rule tells it not to, which makes the marker a forgeable claim (the id:8089 gaming class). Add the twin of rule 7."
grep -qiE 'Never write .@owner-answered' "$CONTRACT" \
  || note "(G) the executor contract must carry an explicit NEVER-WRITE rule for @owner-answered, worded like its @owner-accepted sibling (rule 7)"

# -- (H) arm 2: the reviewer greps the diff for an executor-introduced marker -----------
grep -q '@owner-answered' "$REVIEW" \
  || note "(H) relay/references/review.md has no @owner-answered check -- @owner-accepted's owner-only claim is real only because review.md step 7 greps the reviewed diff for it; without the twin, the executor-side ban is another prose rule that silently no-ops"
grep -qiE 'answer-src' "$REVIEW" \
  || note "(H) the review check must cover the answer-src: citation half too -- an executor forging the citation alone is the same fabrication"

# -- (I) a MODIFIED already-marked line is flagged for contradiction review -------------
grep -qiE 'MODIF(Y|IED).*@owner-answered|@owner-answered.*(MODIF(Y|IED)|contradiction)' "$REVIEW" \
  || note "(I) review.md has no check for a diff that MODIFIES a line already carrying @owner-answered -- that edit IS re-ask (1) of the loderite incident: a later author wrote the OPPOSITE assertion into the ROADMAP line and nothing noticed"

(( fail )) && exit 1
echo "ALL PASS: @owner-answered consumer surface + owner-only enforcement arms (id:6621)"
