#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:5b1f, which has no ROADMAP
# twin (it was filed directly into TODO.md). Failures always count.
#
# id:5b1f -- `orphan-scan.sh --shipped` emits a bare GATE-READY ("unblocked now") for an
# item that is an `@container` TRACKING LINE, whose own text says the work lives in its
# CHILDREN and that the line itself is never actionable.
#
# OBSERVED LIVE in this repo's own 2026-09-01 scan: id:ebbe was reported
#   "id:ebbe -- GATE-READY (all gates [x]) -- unblocked now."
# while its ROADMAP line reads
#   "🚧 @container DECOMPOSED ... TRACKING LINE ONLY, work the children: ... id:5367 + id:2062".
# Both children were already [x], which is exactly WHY every gate resolved closed -- so the
# predicate is working correctly and its LABEL is what misleads. Acting on that line means
# dispatching a tracking stub; the real work sat in a different, unflagged item.
#
# WHY RELABEL RATHER THAN SUPPRESS. Dropping the line would make a detector that correctly
# found something resolve to nothing, which is the id:4347 no-silent-swallow anti-pattern
# this repo bans (cf. the `MECH` lane, which is printed precisely so it cannot be stranded
# invisibly). The container item stays VISIBLE and is labelled for what it is.
#
# Contract asserted here:
#   a. An item carrying `@container` is NEVER emitted as a bare GATE-READY.
#   b. It is still emitted, under a distinct container label -- never silently dropped.
#   c. The positive path survives: a non-container item whose gates are all [x] still
#      reports plain GATE-READY.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which reverts the
# container detection to the pre-fix behaviour (every item takes the bare GATE-READY branch).
# fails-against-mutation: sed -i 's/is_container=1/is_container=0/' meeting/orphan-scan.sh
# fails-against-assertion: case A: an @container item must NOT be reported as a bare GATE-READY
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/tests"
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.archive.md"

# Fixture ledger:
#   bb01 / bb02 -- closed gate targets, so every gated-on edge resolves CLOSED.
#   bb02x       -- the @container tracking line; gates all [x]  => today: bare GATE-READY.
#   bb03        -- ordinary item, gates all [x]                 => must STAY GATE-READY.
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [x] a finished gate target <!-- id:bb01 -->
- [x] another finished gate target <!-- id:bb02 -->
- [ ] [HARD] tracking stub, work the children <!-- gated-on:bb01 --> <!-- id:bb0c --> — 🚧 @container DECOMPOSED — TRACKING LINE ONLY, work the children.
- [ ] [HARD] a real unblocked item <!-- gated-on:bb02 --> <!-- id:bb03 -->
EOF

: > "$repo/ROADMAP.md"

git -C "$repo" add -A
d="$(date -d '-1 days' +%Y-%m-%dT12:00:00)"
GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" \
  git -C "$repo" commit -q -m "fixture: @container tracking line with all gates closed"

out="$(HOME="$tmp" ORPHAN_SCAN_TEST_TIMEOUT_S=10 ORPHAN_SCAN_LIMIT=0 timeout 60 "$ORPHAN" --shipped "$repo")"

fail=0
report() { echo "FAIL: $1"; fail=1; }

# (c) FIRST, so a scan that emits nothing at all cannot vacuously satisfy (a).
grep -q 'id:bb03 — GATE-READY (all gates' <<<"$out" \
  || report "case C: a non-container item with all gates [x] must still be plain GATE-READY"

# (b) the container item must still be reported -- never silently dropped (id:4347).
grep -q 'id:bb0c' <<<"$out" \
  || report "case B: the @container item must still be REPORTED, not silently swallowed"

# (a) the defect itself.
grep -q 'id:bb0c — GATE-READY (all gates' <<<"$out" \
  && report "case A: an @container item must NOT be reported as a bare GATE-READY"

if (( fail )); then
  echo "--- scan output ---"
  echo "$out"
  exit 1
fi
echo "PASS: orphan-scan --shipped labels @container tracking lines instead of calling them unblocked (id:5b1f)"
