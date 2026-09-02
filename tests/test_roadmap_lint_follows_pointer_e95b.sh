#!/usr/bin/env bash
# roadmap-lint.sh rule 3(c) must follow per-id detail pointers (id:e95b).
#
# No `# roadmap:` header: this is a defect-fix test, not a roadmap item's spec, so
# its failures always count.
#
# Defect: the ratified ledger line-shrink (id:0d7c, meeting 2026-09-01-2226 D3)
# relocates an item's prose body into `docs/ledger-notes/<id>.md`, leaving a slim
# head plus a pointer. Rule 3(c) NO-ACCEPTANCE-NO-TWIN (id:213a) asks whether an
# open item has an Acceptance/Tests/Done-check clause IN ITS BODY -- so after the
# shrink a perfectly workable item reads as structurally un-workable. MEASURED on
# the real ledgers 2026-09-02: the acceptance gate's warning count went 1 -> 2,
# which is what blocked the shrink from landing. roadmap-lint is the FOURTH
# consumer of relocated bodies, after id:2ee1 (ledger-slice) and id:f3d2 (the byte
# gate); nobody had identified it.
#
# Clause: when an open item's head line or body names its OWN detail path, the
# clause search extends into that file. A pointer whose file is MISSING is its own
# LOUD finding (DETAIL-POINTER-MISSING) rather than being silently reported as an
# absent clause -- the body is unreachable, so neither answer is knowable, and
# blaming the item hides the broken pointer (id:4347 no-silent-swallow).
#
# Only the item's OWN id is followed: under D3 a body lives in exactly one file
# named for that id, so a mention of some other id's note is prose, not a spec.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so the
# negative case is the parent revision of roadmap-lint.sh alone. The script must be
# overlaid on the CURRENT tree, not extracted beside a bare fixture: it FATALs without
# `relay/references/hard-lanes.md`, its lane-vocabulary SSOT (id:71d6), and a run that
# dies at that probe is red for the wrong reason -- exactly as vacuous as green.
# fails-against-rev: HEAD~1 -- relay/scripts/roadmap-lint.sh
# fails-against-assertion: a shrunk item whose clause lives in its detail file still fired
#
# Hermetic: temp ROADMAP + TODO + docs/ledger-notes fixtures; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/docs/ledger-notes"
R="$tmp/ROADMAP.md"

# Every fixture item is deliberately TWIN-LESS: the twin check would otherwise
# exempt them all and the test would pass for the wrong reason.
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] a shrunk item, clause relocated -- detail: `docs/ledger-notes/f101.md` <!-- id:f101 -->
- [ ] [ROUTINE] a shrunk item whose note has NO clause either -- detail: `docs/ledger-notes/f102.md` <!-- id:f102 -->
- [ ] [ROUTINE] a shrunk item whose note is GONE -- detail: `docs/ledger-notes/f103.md` <!-- id:f103 -->
- [ ] [ROUTINE] an unshrunk item merely MENTIONING docs/ledger-notes/f101.md as prose <!-- id:f104 -->
MD

cat >"$tmp/TODO.md" <<'MD'
# TODO

- [ ] an unrelated design-ledger entry <!-- id:f999 -->
MD

cat >"$tmp/docs/ledger-notes/f101.md" <<'MD'
# id:f101

## From ROADMAP

  - **Acceptance**: the relocated clause, reachable only through the pointer.
MD

cat >"$tmp/docs/ledger-notes/f102.md" <<'MD'
# id:f102

## From ROADMAP

  - **Context**: prose only, genuinely no acceptance clause anywhere.
MD

set +e
bash "$LINT" "$R" 2>"$tmp/err" >/dev/null; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "default run must exit 0 (report-only), got $rc (err: $(cat "$tmp/err"))"

# (a) THE DEFECT: the clause lives in the detail file, so the rule must not fire.
! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f101' "$tmp/err" \
  || fail "a shrunk item whose clause lives in its detail file still fired NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# (b) Following the pointer must not blanket-exempt: a note with no clause still fires.
grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f102' "$tmp/err" \
  || fail "a shrunk item with no clause in its note failed to fire NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# (c) A missing note is its own LOUD finding, not an acceptance verdict.
grep -q 'DETAIL-POINTER-MISSING: open item id:f103' "$tmp/err" \
  || fail "a pointer at a missing detail file did not report DETAIL-POINTER-MISSING (err: $(cat "$tmp/err"))"
! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f103' "$tmp/err" \
  || fail "a missing detail file was reported as an absent acceptance clause, blaming the item for a broken pointer (err: $(cat "$tmp/err"))"

# (d) Only the item's OWN id is followed -- f104 mentions f101's note as prose and
#     must NOT inherit f101's clause.
grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f104' "$tmp/err" \
  || fail "an item mentioning ANOTHER id's note as prose inherited that note's clause (err: $(cat "$tmp/err"))"

# --- (e) the TWIN check follows relocated TODO bodies too -----------------------
# The real shape that refused the shrink (id:6958): an item's only twin was a PROSE
# MENTION inside ANOTHER item's TODO body, which the shrink relocated into that other
# item's note. The mention must still count as a twin from there -- and only from a
# `## From TODO` section, because a `## From ROADMAP` mention is ROADMAP prose and
# counting it would WIDEN the exemption rather than preserve it.
cat >>"$R" <<'MD'
- [ ] [ROUTINE] twinned only by a prose mention relocated out of TODO <!-- id:f105 -->
- [ ] [ROUTINE] mentioned only from a note's ROADMAP section, which is not a twin <!-- id:f106 -->
MD
cat >"$tmp/docs/ledger-notes/f107.md" <<'MD'
# id:f107

## From TODO

Filed while verifying the id:f105 migration; nothing else tracks it here.

## From ROADMAP

Separately, id:f106 came up during the same sweep.
MD

set +e
bash "$LINT" "$R" 2>"$tmp/err3" >/dev/null; rc3=$?
set -e
[[ $rc3 -eq 0 ]] || fail "(e) default run must exit 0, got $rc3 (err: $(cat "$tmp/err3"))"

! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f105' "$tmp/err3" \
  || fail "a twin relocated into a note's '## From TODO' section stopped counting as a twin (err: $(grep NO-ACCEPTANCE "$tmp/err3" | tr '\n' ' '))"
grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:f106' "$tmp/err3" \
  || fail "a mention in a note's '## From ROADMAP' section was counted as a TODO twin, widening the exemption (err: $(grep NO-ACCEPTANCE "$tmp/err3" | tr '\n' ' '))"

# --- --strict: both findings become hard violations -----------------------------
set +e
bash "$LINT" --strict "$R" 2>"$tmp/err2" >/dev/null; rc_strict=$?
set -e
[[ $rc_strict -ne 0 ]] || fail "--strict must exit nonzero when DETAIL-POINTER-MISSING fires, got 0 (err: $(cat "$tmp/err2"))"
grep -q 'ERROR — DETAIL-POINTER-MISSING' "$tmp/err2" \
  || fail "--strict report should be ERROR-labelled for DETAIL-POINTER-MISSING (err: $(cat "$tmp/err2"))"

pass "roadmap-lint rule 3(c) follows a per-id detail pointer into docs/ledger-notes/<id>.md (id:e95b), still fires when the note carries no clause, reports a MISSING note as its own loud finding, never follows another id's note, and recovers a TWIN from a relocated '## From TODO' body without counting a '## From ROADMAP' mention"
