#!/usr/bin/env bash
# roadmap:ca14
# Spec for the DECIDED-ANSWER marker `@owner-answered:YYYY-MM-DD` + its mandatory
# anchored `<!-- answer-src:SRC -->` citation, and the roadmap-lint.sh rule that
# validates them (id:ca14).
#
# WHY THIS EXISTS (the incident, not an abstraction): loderite `id:ed3a` carried the
# owner's own answer to the genre question, quoted verbatim in its own body, from
# 2026-08-14. Over the next 13 days a later author wrote the OPPOSITE assertion into
# the ROADMAP line, a meeting agenda re-opened the question, and a session put it to
# the owner a third time. Nothing noticed, because a recorded answer was only PROSE.
# rule 3(b) DECIDED-LEFT-OPEN could not catch it: it is WARN-only unless --strict, and
# its lexeme set (RESOLVED|SUPERSEDED|DONE|CLOSED|DEFERRED plus "decided <date>") does
# not match an owner's answer quoted as prose.
#
# WHAT EACH CASE ASSERTS (spelled out so a reviewer can check intent, not just exits):
#   A  a well-formed marker whose path source EXISTS is accepted, silently, exit 0.
#   B  a marker with NO source comment is a LOUD error -- a citation-less marker is
#      just another unfalsifiable claim, which is the failure this whole thing fixes.
#   C  a malformed date is a LOUD error (no sloppy `2026-8-1`).
#   D  a marker whose cited PATH does not exist is a LOUD error (dangling citation:
#      the rot mode).
#   E  an `answer-src:` comment with NO `@owner-answered` marker is a LOUD error
#      (orphan citation, nothing says who answered or when).
#   F  the ledger-id source form (`id:XXXX`) resolves through the ledgers and is
#      accepted.
#   G  a ledger-id source resolving NOWHERE is a LOUD error.
#   H  a BACKTICKED mention of the marker is documentation prose, not a live marker,
#      and must not fire anything (anchoring discipline; the id:4da4/0d58 trap).
#   I  the `ed3a` shape: an item legitimately STAYS OPEN while one question inside it
#      is answered. The marker must neither imply a tick nor trip DECIDED-LEFT-OPEN.
#   J  a `#fragment` on the path source (e.g. `...md#Decisions`) is stripped before
#      the existence check.
#   K  the marker is DOCUMENTED in relay/references/hard-lanes.md beside its siblings,
#      and documented as OWNER-ONLY to write (the id:8089 `@owner-accepted` precedent).
#
# This is a defect-fix/design spec traced to a TODO id promoted to ROADMAP with the
# same id (single-id-two-views), hence the `# roadmap:ca14` header.
#
# Hermetic: every fixture in mktemp -d; never touches ~/.claude, ~/.config, the network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
LANES="$ROOT/relay/references/hard-lanes.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/docs/meeting-notes"
cat >"$tmp/docs/meeting-notes/2026-08-14-genre-call.md" <<'MD'
# Genre call
## Decisions
- D1: base engine now, genres later via the addon mechanism.
MD

cat >"$tmp/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:fa01 -->
- [ ] twin stub <!-- id:fa02 -->
- [ ] twin stub <!-- id:fa03 -->
- [ ] twin stub <!-- id:fa04 -->
- [ ] twin stub <!-- id:fa05 -->
- [ ] twin stub <!-- id:fa06 -->
- [ ] twin stub <!-- id:fa07 -->
- [ ] twin stub <!-- id:fa08 -->
- [ ] twin stub <!-- id:fa09 -->
- [ ] the answer lives here <!-- id:fb01 -->
MD

cat >"$tmp/TODO.archive.md" <<'MD'
# TODO archive
MD

# run_case <item-line> -> writes $tmp/ROADMAP.md, runs the lint, sets rc/err
rc=0
run_case() {
  {
    echo "# Roadmap"
    echo
    echo "## Items"
    echo
    echo "$1"
  } >"$tmp/ROADMAP.md"
  set +e
  bash "$LINT" "$tmp/ROADMAP.md" >"$tmp/out" 2>"$tmp/err"; rc=$?
  set -e
}

show() { sed 's/^/    /' "$tmp/err"; }

SRC='docs/meeting-notes/2026-08-14-genre-call.md'

# --- A: well-formed, existing path source -> accepted, exit 0 -----------------
run_case "- [ ] [ROUTINE] base engine work; the genre question is settled @owner-answered:2026-08-14 <!-- answer-src:${SRC}#Decisions --> <!-- id:fa01 -->"
[[ $rc -eq 0 ]] || { show; fail "A: a well-formed marker with an existing source must exit 0, got $rc"; }
if grep -q 'ANSWER-SRC' "$tmp/err"; then show; fail "A: a well-formed marker must not be flagged"; fi
pass "A: well-formed marker with an existing path source is accepted"

# --- B: marker, no source comment -> LOUD, nonzero ----------------------------
run_case "- [ ] [ROUTINE] the genre question is settled @owner-answered:2026-08-14 <!-- id:fa02 -->"
[[ $rc -ne 0 ]] || { show; fail "B: a marker with NO source must exit nonzero (got 0)"; }
grep -q 'ANSWER-SRC' "$tmp/err" || { show; fail "B: a marker with NO source must emit an ANSWER-SRC finding"; }
grep -q 'fa02' "$tmp/err" || { show; fail "B: the finding must name the item id"; }
pass "B: a citation-less marker fails loudly"

# --- C: malformed date -> LOUD, nonzero ---------------------------------------
run_case "- [ ] [ROUTINE] settled @owner-answered:2026-8-1 <!-- answer-src:${SRC} --> <!-- id:fa03 -->"
[[ $rc -ne 0 ]] || { show; fail "C: a malformed date must exit nonzero (got 0)"; }
grep -q 'ANSWER-SRC' "$tmp/err" || { show; fail "C: a malformed date must emit an ANSWER-SRC finding"; }
pass "C: a malformed date fails loudly"

# --- D: dangling path source -> LOUD, nonzero ---------------------------------
run_case "- [ ] [ROUTINE] settled @owner-answered:2026-08-14 <!-- answer-src:docs/meeting-notes/nope.md --> <!-- id:fa04 -->"
[[ $rc -ne 0 ]] || { show; fail "D: a dangling path citation must exit nonzero (got 0)"; }
grep -q 'ANSWER-SRC' "$tmp/err" || { show; fail "D: a dangling path citation must emit an ANSWER-SRC finding"; }
grep -q 'nope.md' "$tmp/err" || { show; fail "D: the finding must name the unresolvable source"; }
pass "D: a dangling path citation fails loudly and names the source"

# --- E: orphan answer-src, no marker -> LOUD, nonzero -------------------------
run_case "- [ ] [ROUTINE] plain item <!-- answer-src:${SRC} --> <!-- id:fa05 -->"
[[ $rc -ne 0 ]] || { show; fail "E: an orphan answer-src must exit nonzero (got 0)"; }
grep -q 'ANSWER-SRC' "$tmp/err" || { show; fail "E: an orphan answer-src must emit an ANSWER-SRC finding"; }
pass "E: an answer-src with no owner marker fails loudly"

# --- F: ledger-id source form resolves ----------------------------------------
run_case "- [ ] [ROUTINE] settled @owner-answered:2026-08-14 <!-- answer-src:id:fb01 --> <!-- id:fa06 -->"
[[ $rc -eq 0 ]] || { show; fail "F: a ledger-id source that resolves must exit 0, got $rc"; }
if grep -q 'ANSWER-SRC' "$tmp/err"; then show; fail "F: a resolving ledger-id source must not be flagged"; fi
pass "F: a ledger-id source resolving in TODO.md is accepted"

# --- G: ledger-id source resolving nowhere -> LOUD, nonzero -------------------
run_case "- [ ] [ROUTINE] settled @owner-answered:2026-08-14 <!-- answer-src:id:dead --> <!-- id:fa07 -->"
[[ $rc -ne 0 ]] || { show; fail "G: an unresolvable ledger-id source must exit nonzero (got 0)"; }
grep -q 'ANSWER-SRC' "$tmp/err" || { show; fail "G: an unresolvable ledger-id source must emit an ANSWER-SRC finding"; }
grep -q 'dead' "$tmp/err" || { show; fail "G: the finding must name the unresolvable id"; }
pass "G: an unresolvable ledger-id source fails loudly"

# --- H: backticked mention is documentation, not a live marker ----------------
run_case "- [ ] [ROUTINE] document the \`@owner-answered:2026-08-14\` marker shape here <!-- id:fa08 -->"
[[ $rc -eq 0 ]] || { show; fail "H: a backticked marker mention must not fire (exit $rc)"; }
if grep -q 'ANSWER-SRC' "$tmp/err"; then show; fail "H: a backticked marker mention must not be treated as a live marker"; fi
pass "H: a backticked marker mention is prose, not a live marker"

# --- I: the ed3a shape -- answered question, item legitimately still open ------
run_case "- [ ] [ROUTINE] engine work, genre addon still gated @owner-answered:2026-08-14 <!-- answer-src:${SRC}#Decisions --> <!-- id:fa09 -->"
[[ $rc -eq 0 ]] || { show; fail "I: an answered-but-open item must not fail the lint (exit $rc)"; }
if grep -q 'DECIDED-LEFT-OPEN' "$tmp/err"; then show; fail "I: the marker must NOT imply 'tick me' -- DECIDED-LEFT-OPEN must not fire on it"; fi
pass "I: an item may stay open while one question inside it is answered"

# --- J: fragment on the path source is stripped before the existence check -----
run_case "- [ ] [ROUTINE] settled @owner-answered:2026-08-14 <!-- answer-src:${SRC}#Decisions --> <!-- id:fa01 -->"
[[ $rc -eq 0 ]] || { show; fail "J: a #fragment on the path source must be stripped before the existence check (exit $rc)"; }
pass "J: a #fragment on the path source is stripped"

# --- K: documented in the marker family, owner-only ---------------------------
grep -q '@owner-answered' "$LANES" || fail "K: the marker must be documented in relay/references/hard-lanes.md"
awk '/@owner-answered/,0' "$LANES" >"$tmp/lanes-tail"
grep -qi 'OWNER ONLY' "$tmp/lanes-tail" \
  || fail "K: hard-lanes.md must document @owner-answered as OWNER-ONLY to write"
grep -q 'answer-src' "$LANES" || fail "K: hard-lanes.md must document the answer-src citation half"
pass "K: the marker and its citation are documented in hard-lanes.md"

echo "ALL PASS: @owner-answered decided-answer marker + lint rule (id:ca14)"
