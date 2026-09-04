#!/usr/bin/env bash
# roadmap:e567
#
# RED SPEC for ROADMAP id:e567 -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# WHAT IS ALREADY DONE, so nobody redoes it. `id:e567` measured that relocating prose under
# the ratified `id:0d7c` format moved ~9 KB of text and paid ~24.5 KB of generated note
# header, and that `relay/scripts/classify-repo.sh` counts those note bytes IN, deliberately
# (`id:f3d2`). The owner ratified OPTION 2 on 2026-09-04 -- shrink the header, do not reopen
# `f3d2` -- and the generator change plus the migration of all 779 notes landed the same day
# at `342b5c14` (387,292 -> 200,005 header bytes, 497 -> 255 B/note, 784 of 784 note bodies
# byte-identical).
#
# WHAT IS OWED, and it is the whole of this item's remaining scope. `id:e567`'s done-check
# reads: "the decision is recorded with the per-item header cost measured at the time of the
# decision, and `id:03a3` cites it BEFORE the fleet migration runs." `id:03a3` migrates 46
# repos and is the single largest application of the format so far. Its note does not cite
# `e567` at all today, so the scaling property that decision priced is not in front of
# whoever runs that migration.
#
# WHY A TEST RATHER THAN A ONE-LINE EDIT. `id:03a3`'s own gate is written as a citation, and
# a citation nothing checks is the class this repo keeps paying for: the `id:ca14` incident
# was an owner's recorded answer that existed only as prose, re-asked three times over
# thirteen days because nothing could see it. This pins the gate mechanically so the
# migration cannot run past it silently.
#
# Reads the live ledger notes; writes nothing, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTE="$ROOT/docs/ledger-notes/03a3.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$NOTE" ]] || fail "setup: docs/ledger-notes/03a3.md not found at $NOTE"

body="$(cat "$NOTE")"

# --- (A) THE CITATION ------------------------------------------------------------------
grep -qF 'e567' <<<"$body" || \
  fail "(A) docs/ledger-notes/03a3.md does not cite id:e567 -- the fleet migration of 46 repos is the largest application of the format and its per-note header cost is priced in e567, which the migration's own gate says it must cite first"
pass "(A) 03a3 cites id:e567"

# --- (B) THE CITATION IS SUBSTANTIVE ----------------------------------------------------
# A bare token is one more unfalsifiable claim. The gate exists so the migration carries the
# MEASURED per-note header cost, so the note must state a per-note byte figure.
grep -qE '[0-9]+[ ]?B/note|[0-9]+ bytes per note' <<<"$body" || \
  fail "(B) 03a3 cites e567 but records no per-note header figure -- the point of the gate is that the 46-repo migration prices the header cost it will pay, not that it names an id"
pass "(B) the citation carries a measured per-note header figure"

echo "ALL PASS: id:e567 the fleet migration cites the measured note-header cost"
