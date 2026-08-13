#!/usr/bin/env bash
# roadmap:cd9c
#
# RED SPEC for ROADMAP item id:cd9c (owner ruled branch (a) on 2026-08-13):
#   teach the GENERIC archivers to LEAVE a one-line stub in the LIVE ledger for
#   every item they move, so archived ids keep resolving from ROADMAP.md alone
#   and `orphan-scan --cross-ledger` (which reads ONLY the live file) is no
#   longer silently blinded.
#
# Stub grammar — promoted by (a) from a borrowed loderite constant to the fleet
# standard, and ALREADY hard-coded in the shipped READER half (`stub_line_re` in
# relay/scripts/roadmap-archive.sh, commit 12e9825):
#   - [x] <title> <!-- id:XXXX --> (archived — see ROADMAP.archive.md)
#
# SCOPE — this file specs the WRITER half only (archiving EMITS a stub). The
# READER half (an already-archived stub classifies `keep`, not `arch`) is shipped
# and green; it is spec'd by tests/test_roadmap_archive_stub_guard.sh and is this
# item's PRECONDITION. That file's cross-run idempotence case uses a PRE-EXISTING
# stub; this file COMPOSES with it by closing the round-trip on a stub the
# archiver ITSELF emitted in run N — the property that actually matters fleet-wide.
#
# DELIBERATELY NOT ASSERTED (would each be a design choice this spec must not make):
#   * where the suffix goes on a header line that carries text AFTER its id comment;
#   * what an item with NO `<!-- id:XXXX -->` token gets (stub? nothing?);
#   * the stub text for the TODO.md / REVIEW_ME.md ledgers in archive-closed.sh
#     (the ratified grammar names ROADMAP.archive.md literally) — only the
#     ROADMAP ledger is asserted for that script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"
CLOSED_SCRIPT="$ROOT/relay/scripts/archive-closed.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$ARCHIVE_SCRIPT" ]] || fail "roadmap-archive.sh not found/executable at $ARCHIVE_SCRIPT"
[[ -x "$CLOSED_SCRIPT"  ]] || fail "archive-closed.sh not found/executable at $CLOSED_SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -r -- "$tmp"' EXIT

SUF=" (archived — see ROADMAP.archive.md)"

make_repo() {
    # make_repo <dir> <file> <content>  — seeds a git repo with one committed ledger
    local repo="$1" file="$2" content="$3"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name tester
    printf '%s' "$content" > "$repo/$file"
    git -C "$repo" add "$file"
    git -C "$repo" commit -qm "seed $file"
}

# stub_of <file> <id> — echo the single live line carrying that id, or empty.
stub_of() { grep -F "id:$2" "$1" 2>/dev/null || true; }

# assert_grammar <line> <id> — the line must satisfy the SHIPPED stub_line_re,
# i.e. `- [x] …<!-- id:XXXX -->` immediately followed by the suffix.
assert_grammar() {
    local line="$1" id="$2"
    [[ "$line" =~ ^-\ \[x\]\ .*\<!--\ *id:$id\ *--\>\ \(archived\ —\ see\ ROADMAP\.archive\.md\) ]] \
      || fail "stub for id:$id does not match the ratified grammar — got: >>>$line<<<"
}

# ─────────────────────────────────────────────────────────────────────────────
# Case 1 — roadmap-archive.sh, prior-commit-done item: a stub is LEFT BEHIND,
# it is exactly ONE line, it carries the item's title verbatim, and the item's
# BODY moves to the archive (the stub is a pointer, not a copy).
# ─────────────────────────────────────────────────────────────────────────────
repo1="$tmp/repo1"
make_repo "$repo1" ROADMAP.md "# Roadmap

## Items

- [x] **Prior-done thing** <!-- id:1a2b -->
  A continuation line that is the item's BODY.
  - **Acceptance**: something that must not stay in the live file.
- [ ] **An open item** <!-- id:5e6f -->
"

"$ARCHIVE_SCRIPT" "$repo1" >/dev/null 2>&1 || true

line1="$(stub_of "$repo1/ROADMAP.md" 1a2b)"
[[ -n "$line1" ]] \
  || fail "id:1a2b no longer resolves from the LIVE ROADMAP.md — archiving left NO stub (this is the id:cd9c defect)"
pass "archived id still resolves from the live ROADMAP.md"

[[ "$(printf '%s\n' "$line1" | wc -l)" == "1" ]] \
  || fail "expected exactly ONE live line for id:1a2b, got $(printf '%s\n' "$line1" | wc -l)"
assert_grammar "$line1" 1a2b
pass "the stub is one line and matches the ratified grammar"

[[ "$line1" == "- [x] **Prior-done thing** <!-- id:1a2b -->$SUF" ]] \
  || fail "stub does not preserve the item's title verbatim — got: >>>$line1<<<"
pass "stub preserves the item title verbatim"

grep -qF 'A continuation line that is the' "$repo1/ROADMAP.md" \
  && fail "the item BODY stayed in the live ROADMAP.md — a stub must be a one-line pointer, not a copy"
pass "the item body is gone from the live file"

grep -qF 'A continuation line that is the' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "the item body was not moved into ROADMAP.archive.md"
pass "the item body is in ROADMAP.archive.md"

grep -qF 'id:5e6f' "$repo1/ROADMAP.md" || fail "the open item was removed from ROADMAP.md"
grep -qF "$SUF" <<<"$(grep -F 'id:5e6f' "$repo1/ROADMAP.md")" \
  && fail "an OPEN item was given an archived-stub suffix"
pass "open items are untouched and get no stub"

# ─────────────────────────────────────────────────────────────────────────────
# Case 2 — TRIANGULATION (id:108e): two archived items via TWO DIFFERENT gate
# paths (prior-commit-done and the ≥30-day `done YYYY-MM-DD` age gate) each get
# their OWN stub, with their own title and id, in original document order.
# Hard-coding a single fixture line cannot satisfy this.
# ─────────────────────────────────────────────────────────────────────────────
repo2="$tmp/repo2"
OLD="$(date -d '90 days ago' '+%Y-%m-%d')"
make_repo "$repo2" ROADMAP.md "# Roadmap

## Items

- [x] **First archived thing** <!-- id:aa11 -->
  body of the first.
- [ ] **Still open** <!-- id:bb22 -->
- [x] **Second archived thing** <!-- id:cc33 -->
  body of the second.
"
# Age-gated third item, ticked only in the working tree (NOT in the prior commit),
# so it can only be archived via the date gate — a genuinely different codepath.
printf '%s\n' "- [x] **Age-gated thing** done $OLD <!-- id:dd44 -->" >> "$repo2/ROADMAP.md"
printf '%s\n' "  body of the age-gated one." >> "$repo2/ROADMAP.md"

"$ARCHIVE_SCRIPT" "$repo2" >/dev/null 2>&1 || true

for pair in "aa11:First archived thing" "cc33:Second archived thing" "dd44:Age-gated thing"; do
    id="${pair%%:*}"; title="${pair#*:}"
    l="$(stub_of "$repo2/ROADMAP.md" "$id")"
    [[ -n "$l" ]] || fail "no stub left for id:$id ($title) — the archiver dropped it from the live file"
    assert_grammar "$l" "$id"
    grep -qF "$title" <<<"$l" || fail "stub for id:$id lost its own title ($title) — got: >>>$l<<<"
done
pass "each archived item gets its OWN stub (3 items, 2 gate paths, distinct titles)"

order="$(grep -oE 'id:(aa11|bb22|cc33|dd44)' "$repo2/ROADMAP.md" | tr '\n' ' ')"
[[ "$order" == "id:aa11 id:bb22 id:cc33 id:dd44 " ]] \
  || fail "stubs are not in original document order — got: >>>$order<<<"
pass "stubs stay in original document order, interleaved with surviving open items"

grep -qF 'body of the first' "$repo2/ROADMAP.md" \
  && fail "an archived item's body survived in the live file"
pass "no archived body remains live"

# ─────────────────────────────────────────────────────────────────────────────
# Case 3 — ROUND-TRIP, the real contract: a stub EMITTED BY RUN N must classify
# `keep` in run N+1. Composes with test_roadmap_archive_stub_guard.sh case 3
# (which seeds a PRE-EXISTING stub); here the stub under test is the archiver's
# own output, so writer and reader halves must agree on one grammar.
# ─────────────────────────────────────────────────────────────────────────────
repo3="$tmp/repo3"
make_repo "$repo3" ROADMAP.md "# Roadmap

## Items

- [x] **Round-trip subject** <!-- id:c0de -->
  body that run 1 must move away.
- [ ] **Open** <!-- id:d00d -->
"

"$ARCHIVE_SCRIPT" "$repo3" >/dev/null 2>&1 || true
emitted="$(stub_of "$repo3/ROADMAP.md" c0de)"
[[ -n "$emitted" ]] || fail "run 1 emitted no stub for id:c0de — nothing to round-trip"

git -C "$repo3" add -A >/dev/null 2>&1 || true
git -C "$repo3" commit -qm 'after run 1' >/dev/null 2>&1 || true
before_live="$(cat "$repo3/ROADMAP.md")"
before_arch="$(cat "$repo3/ROADMAP.archive.md" 2>/dev/null || true)"

"$ARCHIVE_SCRIPT" "$repo3" >/dev/null 2>&1 || true
after_live="$(cat "$repo3/ROADMAP.md")"
after_arch="$(cat "$repo3/ROADMAP.archive.md" 2>/dev/null || true)"

[[ "$before_live" == "$after_live" ]] \
  || fail "run 2 mutated ROADMAP.md — the archiver ate the stub IT ITSELF wrote (writer/reader grammar disagree)"
[[ "$before_arch" == "$after_arch" ]] \
  || fail "run 2 grew ROADMAP.archive.md — the archiver re-archived its own stub"
pass "round-trip: a stub written by run N survives run N+1 untouched"

# ─────────────────────────────────────────────────────────────────────────────
# Case 4 — archive-closed.sh (the SECOND generic archiver named in the item's
# acceptance clause) must leave a stub too, on the ROADMAP ledger. Asserted for
# ROADMAP only; the TODO/REVIEW_ME stub wording is a design choice this spec
# does not make.
# ─────────────────────────────────────────────────────────────────────────────
repo4="$tmp/repo4"
make_repo "$repo4" ROADMAP.md "# Roadmap

## Items

- [x] **Closed via archive-closed** <!-- id:ee55 -->
  body that archive-closed must move.
- [ ] **Open** <!-- id:ff66 -->
"

"$CLOSED_SCRIPT" "$repo4" >/dev/null 2>&1 || true

l4="$(stub_of "$repo4/ROADMAP.md" ee55)"
[[ -n "$l4" ]] \
  || fail "archive-closed.sh left NO stub for id:ee55 — id stops resolving from the live ROADMAP.md"
assert_grammar "$l4" ee55
pass "archive-closed.sh leaves a grammar-conforming stub on the ROADMAP ledger"

grep -qF 'body that archive-closed must move' "$repo4/ROADMAP.md" \
  && fail "archive-closed.sh left the whole body live — the stub must be a one-line pointer"
grep -qF 'body that archive-closed must move' "$repo4/ROADMAP.archive.md" 2>/dev/null \
  || fail "archive-closed.sh did not move the body into ROADMAP.archive.md"
pass "archive-closed.sh moves the body and keeps only the stub"

echo "ALL PASS"
