#!/usr/bin/env bash
# roadmap:1608
#
# RED SPEC for TODO id:1608 -- `meeting/orphan-scan.sh --shipped` is the SEVENTH consumer
# of item BODIES that breaks when the ledger line-shrink relocates an item's prose into
# `docs/ledger-notes/<id>.md` and leaves a slim head plus a pointer. Detail and the
# measured table live in `docs/ledger-notes/1608.md`.
#
# Six of the seven consumers found so far fail toward SILENCE. This one is the exception:
# `wait_re` (orphan-scan.sh:229) is an EXTERNAL-WAIT SUPPRESSOR matched against the ledger
# LINE, so relocating the body deletes the match, and losing a suppressor does not hide a
# finding -- it INVENTS one. Measured over the wave-1 shrink (`a21c126f` -> `3ef0be1d`),
# uncapped: `wait_re` matches on open TODO lines fell 265 -> 107 and `id:2b4b` flipped from
# silent to "TICK-READY ... ready to tick", while the prose it lost says *"Close or re-scope
# this item against the code rather than against its own prose."* TICK-READY is an ACTION
# RECOMMENDATION a human acts on directly, so this fails toward telling a reviewer to close
# live work.
#
# WHAT THIS FILE PINS
# -------------------
#   (a) EXTERNAL-WAIT lexeme relocated into the note  -> TICK-READY must NOT fire. [cases A1/A2]
#   (c) gate VOCABULARY relocated into the note       -> UNMARKED-GATE must still fire. [case C1]
#   (b) COMPLETION lexeme relocated into the note     -> GATE-STALE must still fire, when the
#       age threshold is not the thing being tested.  [case B1]
#
# ...plus a pointer that resolves to NOTHING [case D1]: the body is unreachable, so neither
# answer is knowable and the scan must refuse to recommend rather than guess (id:4347, the
# same branch `roadmap-lint.sh`'s `item_has_body_clause` reports as exit 2).
#
# EXEMPTION, WRITTEN DOWN RATHER THAN QUIETLY OMITTED -- the AGE half of (b).
# --------------------------------------------------------------------------
# `GATE-STALE` fell 13 -> 1 across the wave-1 shrink, and only PART of that is a body-reading
# defect. The class has two conjuncts: a COMPLETION lexeme (`REMAIN|pending|activation`) AND
# a line age of >= `ORPHAN_SCAN_SHIPPED_AGE_DAYS` (default 14) computed from `git blame`
# author-time on the TODO.md line (orphan-scan.sh:461-462).
#   * The LEXEME conjunct is a body-reading defect and IS specified here, as case B1.
#   * The AGE conjunct is NOT, and cannot be. A shrink REWRITES every line it touches, so
#     blame author-time resets to 0 and the class is suppressed for a fortnight regardless of
#     where the lexeme lives. The signal IS the line's git history, and rewriting the line
#     destroys it BY CONSTRUCTION -- no keep-pattern, no pointer-follow, and no amount of
#     reading the note can recover it. Writing a test for it would be inventing a passing
#     story for a defect this fix does not address.
#     Consequence for anyone baselining this scan after a shrink: force
#     `ORPHAN_SCAN_SHIPPED_AGE_DAYS=0`, or the green means nothing. This file does exactly
#     that, so case B1 isolates the lexeme conjunct and asserts nothing about age.
#     A durable fix would have to key age off something the shrink preserves (a `since:`
#     marker, or blaming the NOTE file); that is separate work, not this item.
#
# UNCAPPED, ALWAYS. `ORPHAN_SCAN_LIMIT` defaults to 10. Pre- and post-shrink runs BOTH
# return exactly 10 rows with different membership, which reads as a dramatic change in
# composition and is pure cap artifact -- a first pass at id:1608 concluded "4 new GATE-READY
# findings appeared" when uncapped GATE-READY was 14 -> 14, unchanged. Every invocation below
# sets `ORPHAN_SCAN_LIMIT=9999`.
#
# THE NOTES DIRECTORY IS DERIVED FROM THE POINTER, NEVER HARDCODED. This is the loderite
# finding of 2026-09-02, recorded in `relay/scripts/roadmap-lint.sh`'s `item_detail_path`:
# the first cut there built `"${LEDGER_NOTES_DIR}/${id}.md"` and compared that STRING against
# the line, so it did nothing at all in a repo whose pointers spell a different directory
# (loderite's say `docs/roadmap-notes/`) while reporting 19 findings that looked entirely
# real -- the id:d35a silent-no-op class. A symlink cannot fix a string comparison and a bare
# parameter only moves the failure from "wrong default" to "unset everywhere". So the fixture
# below uses TWO notes directories, NEITHER of them this repo's `docs/ledger-notes`: any
# implementation that hardcodes a default, or that derives one directory globally and applies
# it to every line, fails case A2. The path is on the line; read it from there.
#
# NEGATIVE-CASE DECLARATION. This is a roadmap-spec authored BEFORE its fix, so it is red
# against the current tree and `tests/verify-negative-cases.py` carves it into the
# ROADMAP-SPEC bucket rather than running it (GREEN-NOW cannot hold yet). The declaration
# below is nonetheless the real one and is checked statically today for unique-site: once
# the fix lands, `ba1880ba065a`'s `meeting/orphan-scan.sh` IS the ancestor this file fails
# against, and case A1 -- the manufactured recommendation, the only sub-defect that is
# actively harmful -- is deliberately asserted LAST so it is the final FAIL line to fire.
# fails-against: rev ba1880ba065a -- the pre-fix meeting/orphan-scan.sh, whose --shipped mode
#   reads the ledger LINE only and never follows an item's detail pointer.
# fails-against-rev: ba1880ba065a -- meeting/orphan-scan.sh
# fails-against-assertion: case A1: the EXTERNAL-WAIT lexeme moved into 2b4b's note, so the scan MANUFACTURED a tick recommendation
#
# NOTE ON THIS FILE'S OWN MARKERS: every fixture `# roadmap:` token below is BUILT at
# runtime via printf and never written out literally, because `tests/run-tests.sh` takes
# `head -1` of a WHOLE-FILE grep for `# roadmap:[0-9a-f]{4}` -- a literal anywhere, prose or
# heredoc included, can capture this file for the wrong item (the defect the id:4425 spec
# records in its own header).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/tests" "$repo/docs/item-notes" "$repo/notes/ledger"
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.archive.md"
: > "$repo/ROADMAP.md"

# mkspec <path> <token> -- a trivially green fixture test carrying the test-owns-item
# `# roadmap:` header for <token>. The marker is constructed, never literal (see header).
mkspec() {
  { printf '#!/usr/bin/env bash\n'
    printf '# roadmap:%s\n' "$2"
    printf 'set -euo pipefail\nexit 0\n'; } > "$1"
  chmod +x "$1"
}

# ---------------------------------------------------------------------------------------
# The ledger. Every head line is SLIM: title, a detail pointer where one applies, and the
# terminal id comment. No typed `children:`/`gated-on:` marker anywhere, so nothing takes
# the typed-predicate bypass and every case exercises the prose path this item is about.
# Two distinct notes directories, neither the repo default.
# ---------------------------------------------------------------------------------------
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] **The shrunk item whose suppressor moved.** -- detail: `docs/item-notes/2b4b.md` <!-- id:2b4b -->
- [ ] **A second shrunk item, notes filed elsewhere.** -- detail: `notes/ledger/aa01.md` <!-- id:aa01 -->
- [ ] **An item that really is finished and really has no caveat.** <!-- id:aa02 -->
- [ ] **An unshrunk item that still says on its own line that we must verify the result.** <!-- id:aa03 -->
- [ ] **A shrunk item whose gate phrasing moved.** -- detail: `docs/item-notes/aa04.md` <!-- id:aa04 -->
- [ ] **A shrunk item with nothing gate-shaped anywhere.** -- detail: `docs/item-notes/aa05.md` <!-- id:aa05 -->
- [ ] **A shrunk item whose completion clause moved.** -- detail: `docs/item-notes/aa06.md` <!-- id:aa06 -->
- [ ] **An unshrunk item whose completion clause is still pending on its own line.** <!-- id:aa07 -->
- [ ] **A shrunk item whose note was never written.** -- detail: `docs/item-notes/aa08.md` <!-- id:aa08 -->
EOF

# (a) case A1 -- the measured live instance. The sole EXTERNAL-WAIT lexeme is `verify`,
# and it is in the note, not on the line. Reproduces id:2b4b verbatim in shape.
cat > "$repo/docs/item-notes/2b4b.md" <<'EOF'
# id:2b4b

## From TODO

Close or re-scope this item against the code rather than against its own prose. We must
first verify the claim against the implementation; the item is legitimately open until
someone does.
EOF

# (a) case A2 -- same defect, a DIFFERENT notes directory. Kills a hardcoded default and
# kills a single globally-derived directory applied to every line.
cat > "$repo/notes/ledger/aa01.md" <<'EOF'
# id:aa01

## From TODO

Still awaiting the upstream release before this can be judged either way.
EOF

# (c) case C1 -- structured gate PHRASING relocated. `UNMARKED-GATE` keys on prose by
# definition (gate vocabulary present, no typed marker), so relocating prose is exactly
# what blinds it: 64 -> 16 across the wave-1 shrink, the largest single loss.
cat > "$repo/docs/item-notes/aa04.md" <<'EOF'
# id:aa04

## From TODO

This is blocked on the vendor shipping their side, and there is no local token to point a
typed edge at.
EOF

# (c) negative control -- a note with no gate vocabulary at all must NOT produce an
# UNMARKED-GATE row. A fix that simply fires whenever a pointer exists fails here.
cat > "$repo/docs/item-notes/aa05.md" <<'EOF'
# id:aa05

## From TODO

Some ordinary explanatory prose about how the thing is put together. Nothing here is a
gate and nothing here is a wait.
EOF

# (b) case B1 -- the LEXEME conjunct of GATE-STALE, isolated. `pending` is a
# COMPLETION-pending word; no EXTERNAL-WAIT word appears on the line or in the note.
# The AGE conjunct is neutralised by ORPHAN_SCAN_SHIPPED_AGE_DAYS=0, per the exemption.
cat > "$repo/docs/item-notes/aa06.md" <<'EOF'
# id:aa06

## From TODO

The last step is still pending; it will finish quietly and nothing will announce it.
EOF

# Regression guards for the classes that already work today, so a fix cannot buy the new
# behaviour by weakening the old.
mkspec "$repo/tests/test_2b4b.sh" 2b4b
mkspec "$repo/tests/test_aa01.sh" aa01
mkspec "$repo/tests/test_aa02.sh" aa02
mkspec "$repo/tests/test_aa03.sh" aa03
mkspec "$repo/tests/test_aa08.sh" aa08

git -C "$repo" add -A
d="$(date -d '-30 days' +%Y-%m-%dT12:00:00)"
GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" \
  git -C "$repo" commit -q -m "fixture: shrunk ledger whose bodies live in per-id detail notes"

out="$(HOME="$tmp" \
      ORPHAN_SCAN_LIMIT=9999 \
      ORPHAN_SCAN_SHIPPED_AGE_DAYS=0 \
      ORPHAN_SCAN_TEST_TIMEOUT_S=10 \
      timeout 120 "$ORPHAN" --shipped "$repo")"

fail=0
report() { echo "FAIL: $1"; fail=1; }

# The scan emits an em dash between the token and the class name. This file may not contain
# one (fleet style rule), so every assertion matches around it rather than through it.
has_row() { grep -qE "^id:$1 .*$2" <<<"$out"; }

# --- regression guards, asserted FIRST -------------------------------------------------
# A scan that emits nothing at all, or that suppresses everything the moment it sees a
# pointer, must not be able to satisfy this file vacuously.
has_row aa02 'TICK-READY' \
  || report "guard: an item with no pointer, no gate word and a green owning test must still be TICK-READY"
has_row aa03 'TICK-READY' \
  && report "guard: an EXTERNAL-WAIT lexeme on the LINE must still suppress TICK-READY"
has_row aa07 'GATE-STALE' \
  || report "guard: a COMPLETION lexeme on the LINE must still produce GATE-STALE"
has_row aa05 'UNMARKED-GATE' \
  && report "guard: a note carrying no gate vocabulary must not produce an UNMARKED-GATE row"

# --- (c) UNMARKED-GATE recovered from the note -----------------------------------------
has_row aa04 'UNMARKED-GATE' \
  || report "case C1: gate vocabulary relocated into aa04's note is still a gate; UNMARKED-GATE must fire from the note"

# --- (b) GATE-STALE recovered from the note (lexeme conjunct only; see exemption) -------
has_row aa06 'GATE-STALE' \
  || report "case B1: the COMPLETION lexeme relocated into aa06's note must still produce GATE-STALE at age threshold 0"

# --- pointer that resolves to nothing ---------------------------------------------------
has_row aa08 'TICK-READY' \
  && report "case D1: aa08 points at a note that does not exist, so its body is unreachable and doneness is unknowable; refusing to recommend is the only safe answer"

# --- (a) the manufactured recommendation, asserted LAST ---------------------------------
# Ordered last deliberately: this file uses a non-exiting accumulator, and the declared
# negative-case assertion must match the LAST FAIL line to fire.
has_row aa01 'TICK-READY' \
  && report "case A2: aa01's EXTERNAL-WAIT lexeme lives in a note under a DIFFERENT directory; a hardcoded or globally-guessed notes path is inert here"
has_row 2b4b 'TICK-READY' \
  && report "case A1: the EXTERNAL-WAIT lexeme moved into 2b4b's note, so the scan MANUFACTURED a tick recommendation"

if (( fail )); then
  echo "--- scan output ---"
  echo "$out"
  exit 1
fi
echo "PASS: orphan-scan --shipped follows the per-id detail pointer (id:1608)"
