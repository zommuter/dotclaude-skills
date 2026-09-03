#!/usr/bin/env bash
# roadmap:cd9c  (SUPERSEDED BY id:2eba -- see below; the header is kept so the
#                expected-red bookkeeping for cd9c still resolves)
#
# HISTORY, stated because this file INVERTED its own contract on 2026-09-03.
#
# It was authored as the RED spec for id:cd9c: the generic archivers had to LEAVE a
# one-line stub in the live ledger for every item they moved, so an archived id kept
# resolving from ROADMAP.md alone. Its premise -- that `orphan-scan --cross-ledger`
# "reads ONLY the live file" -- was true when cd9c was ruled and is FALSE now:
# routed:42c9 widened every ROADMAP leg of orphan-scan to
# ROADMAP.md UNION ROADMAP.archive.md, which is verified in case 5 below rather
# than asserted in prose.
#
# id:2eba (owner-ratified 2026-09-03) therefore removed the stub entirely: 62 stub
# lines were 26,101 bytes, 36% of this repo's ROADMAP.md, every one of them a closed
# item already present in ROADMAP.archive.md.
#
# WHAT THIS FILE NOW SPECS -- the WRITER half of id:2eba:
#   1. archiving leaves NOTHING behind in the live ledger (roadmap-archive.sh);
#   2. the same for archive-closed.sh, on the ROADMAP ledger;
#   3. open items are still untouched;
#   4. the run is IDEMPOTENT without a stub -- the second run is a no-op and the
#      archive does not grow (the property the stub used to buy);
#   5. an archived id still resolves, from the ROADMAP.md U ROADMAP.archive.md union
#      that orphan-scan actually reads.
#
# The READER half (an already-archived item classifies `keep`, never `arch`) is spec'd
# by tests/test_roadmap_archive_stub_guard.sh and tests/test_roadmap_archive_stub_prose.sh,
# which still pin LEGACY stub recognition: no writer emits a stub any more, but stubs
# written before this change survive in this repo and across the fleet, and must never
# be re-archived.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"
CLOSED_SCRIPT="$ROOT/relay/scripts/archive-closed.sh"
ORPHAN_SCAN="$ROOT/meeting/orphan-scan.sh"

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

# ─────────────────────────────────────────────────────────────────────────────
# Case 1 — roadmap-archive.sh, prior-commit-done item: NOTHING is left behind in
# the live file, and the whole block (header + body) is in the archive.
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

grep -qF 'id:1a2b' "$repo1/ROADMAP.md" \
  && fail "id:1a2b still appears in the LIVE ROADMAP.md — id:2eba says archiving leaves NO stub"
pass "no stub is left behind in the live ledger"

grep -qF "$SUF" "$repo1/ROADMAP.md" \
  && fail "the archiver still writes the archive-stub suffix into ROADMAP.md"
pass "the stub suffix is never written"

grep -qF '**Prior-done thing**' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "the item's HEADER did not reach ROADMAP.archive.md"
grep -qF 'A continuation line that is the' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "the item body was not moved into ROADMAP.archive.md"
grep -qF 'A continuation line that is the' "$repo1/ROADMAP.md" \
  && fail "the item BODY stayed in the live ROADMAP.md"
pass "the whole block (header + body) moved to ROADMAP.archive.md"

grep -qF 'id:5e6f' "$repo1/ROADMAP.md" || fail "the open item was removed from ROADMAP.md"
pass "open items are untouched"

# ─────────────────────────────────────────────────────────────────────────────
# Case 2 — TRIANGULATION (id:108e): three archived items via TWO DIFFERENT gate
# paths (prior-commit-done and the ≥30-day `done YYYY-MM-DD` age gate). Each one
# leaves the live file entirely and lands in the archive with its own title; the
# surviving open item keeps its place. Hard-coding one fixture line cannot satisfy this.
# ─────────────────────────────────────────────────────────────────────────────
repo2="$tmp/repo2"
OLD="$(date -d '90 days ago' '+%Y-%m-%d')"
make_repo "$repo2" ROADMAP.md "# Roadmap

## Items

- [x] **First archived thing** <!-- id:aa11 -->
  body of the first.
- [ ] **Still open** <!-- id:bb22 -->
  body of the open one, so it is unambiguously ITS body (routed:71ed).
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
    grep -qF "id:$id" "$repo2/ROADMAP.md" \
      && fail "id:$id ($title) still has a live line — archiving must remove it entirely"
    grep -qF "$title" "$repo2/ROADMAP.archive.md" 2>/dev/null \
      || fail "id:$id lost its own title ($title) on the way to the archive"
done
pass "each archived item leaves the live file and lands in the archive with its own title (3 items, 2 gate paths)"

order="$(grep -oE 'id:(aa11|bb22|cc33|dd44)' "$repo2/ROADMAP.md" | tr '\n' ' ')"
[[ "$order" == "id:bb22 " ]] \
  || fail "the live file should now hold ONLY the open item — got: >>>$order<<<"
pass "only the open item survives in the live ledger"

grep -qF 'body of the first' "$repo2/ROADMAP.md" \
  && fail "an archived item's body survived in the live file"
pass "no archived body remains live"

# ─────────────────────────────────────────────────────────────────────────────
# Case 3 — IDEMPOTENCE, the property the stub used to buy. Run N+1 must be a
# no-op: the live file unchanged and the archive not grown. Without a stub this
# is carried by the ARCHIVE-MEMBERSHIP guard in lib-archive-idempotency.py.
# ─────────────────────────────────────────────────────────────────────────────
repo3="$tmp/repo3"
make_repo "$repo3" ROADMAP.md "# Roadmap

## Items

- [x] **Round-trip subject** <!-- id:c0de -->
  body that run 1 must move away.
- [ ] **Open** <!-- id:d00d -->
"

"$ARCHIVE_SCRIPT" "$repo3" >/dev/null 2>&1 || true
grep -qF 'id:c0de' "$repo3/ROADMAP.archive.md" 2>/dev/null \
  || fail "run 1 archived nothing for id:c0de — the idempotence check below would be vacuous"

git -C "$repo3" add -A >/dev/null 2>&1 || true
git -C "$repo3" commit -qm 'after run 1' >/dev/null 2>&1 || true
before_live="$(cat "$repo3/ROADMAP.md")"
before_arch="$(cat "$repo3/ROADMAP.archive.md" 2>/dev/null || true)"

"$ARCHIVE_SCRIPT" "$repo3" >/dev/null 2>&1 || true
after_live="$(cat "$repo3/ROADMAP.md")"
after_arch="$(cat "$repo3/ROADMAP.archive.md" 2>/dev/null || true)"

[[ "$before_live" == "$after_live" ]] \
  || fail "run 2 mutated ROADMAP.md — archiving is not idempotent without the stub"
[[ "$before_arch" == "$after_arch" ]] \
  || fail "run 2 grew ROADMAP.archive.md — the archiver duplicated its own output"
[[ "$(grep -cF 'id:c0de' "$repo3/ROADMAP.archive.md")" == "1" ]] \
  || fail "id:c0de appears more than once in ROADMAP.archive.md after two runs"
pass "idempotent across runs with NO stub: run 2 changes nothing and duplicates nothing"

# ─────────────────────────────────────────────────────────────────────────────
# Case 4 — archive-closed.sh (the SECOND generic archiver) behaves the same way
# on the ROADMAP ledger: no stub, whole block moved.
# ─────────────────────────────────────────────────────────────────────────────
repo4="$tmp/repo4"
make_repo "$repo4" ROADMAP.md "# Roadmap

## Items

- [x] **Closed via archive-closed** <!-- id:ee55 -->
  body that archive-closed must move.
- [ ] **Open** <!-- id:ff66 -->
"

HOME="$tmp" "$CLOSED_SCRIPT" "$repo4" >/dev/null 2>&1 || true

grep -qF 'id:ee55' "$repo4/ROADMAP.md" \
  && fail "archive-closed.sh left a live line for id:ee55 — it must leave no stub either"
grep -qF "$SUF" "$repo4/ROADMAP.md" \
  && fail "archive-closed.sh still writes the archive-stub suffix"
grep -qF 'body that archive-closed must move' "$repo4/ROADMAP.archive.md" 2>/dev/null \
  || fail "archive-closed.sh did not move the body into ROADMAP.archive.md"
grep -qF 'id:ff66' "$repo4/ROADMAP.md" \
  || fail "archive-closed.sh removed the open item"
pass "archive-closed.sh moves the whole block and leaves no stub"

# and it is idempotent too.
snap_s="$(cat "$repo4/ROADMAP.md")"; snap_a="$(cat "$repo4/ROADMAP.archive.md")"
HOME="$tmp" "$CLOSED_SCRIPT" "$repo4" >/dev/null 2>&1 || true
[[ "$(cat "$repo4/ROADMAP.md")" == "$snap_s" ]] \
  || fail "archive-closed.sh run 2 mutated ROADMAP.md"
[[ "$(cat "$repo4/ROADMAP.archive.md")" == "$snap_a" ]] \
  || fail "archive-closed.sh run 2 grew ROADMAP.archive.md"
pass "archive-closed.sh is idempotent without a stub"

# ─────────────────────────────────────────────────────────────────────────────
# Case 5 — THE PREMISE CHECK. cd9c existed because orphan-scan --cross-ledger was
# believed to read only the live ROADMAP.md. routed:42c9 widened it to the archive.
# Verify that HERE rather than trusting the prose: with the ROADMAP twin archived
# and no stub, --cross-ledger must NOT report drift; and it still must report a
# genuine disagreement.
# ─────────────────────────────────────────────────────────────────────────────
repo5="$tmp/repo5"
mkdir -p "$repo5"
cat > "$repo5/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue
- [x] closed in both ledgers <!-- id:7002 -->
- [x] closed here, open in TODO <!-- id:7001 -->
EOF
cat > "$repo5/TODO.md" <<'EOF'
# TODO

## Current
- [x] closed over here too <!-- id:7002 -->
- [ ] still open over here <!-- id:7001 -->
EOF

os_before="$(bash "$ORPHAN_SCAN" --cross-ledger "$repo5" 2>&1 || true)"
grep -q '7001' <<<"$os_before" \
  || fail "case 5: fixture unreached — id:7001 drift was not reported BEFORE archiving"
grep -q '7002' <<<"$os_before" \
  && fail "case 5: fixture wrong — id:7002 agrees and must not be reported"

HOME="$tmp" "$CLOSED_SCRIPT" "$repo5" >/dev/null 2>&1 || true
grep -qF 'id:7002' "$repo5/ROADMAP.archive.md" 2>/dev/null \
  || fail "case 5: id:7002 was not archived — the comparison would be vacuous"
grep -qF 'id:7002' "$repo5/ROADMAP.md" \
  && fail "case 5: id:7002 left a live line"

os_after="$(bash "$ORPHAN_SCAN" --cross-ledger "$repo5" 2>&1 || true)"
grep -q '7002' <<<"$os_after" \
  && { echo "$os_after"; fail "case 5: archiving id:7002 with NO stub invented cross-ledger drift — the archive leg is missing"; }
grep -q '7001' <<<"$os_after" \
  || { echo "$os_after"; fail "case 5: the genuine id:7001 drift stopped being reported"; }
pass "case 5: orphan-scan --cross-ledger reads the archive — no stub is needed for an id to keep resolving"

echo "ALL PASS"
