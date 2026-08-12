#!/usr/bin/env bash
# roadmap:4b8f — open_hard_pool must NOT count [HARD] items parked under a gated/deferred heading.
#
# Defect (observed live, run relay-20260812-122721-23819): zkWhale's 6 open `[HARD]` items all
# sit under `## Gated / deferred`, each carrying a gate note and an explicitly OPEN owner
# decision (id:320b, id:b3c4, id:638e); there are ZERO `[HARD]` items under the active
# `## Items` heading. gather-repo-state.sh nevertheless reported open_hard_pool=6, so the
# classifier emitted `Open [HARD — pool] items: 6` and the pool dispatched an Opus HARD child
# EVERY round. Each child read the ledger, correctly found nothing executable, and handed back,
# until the id:1432 no-work suppression caught it.
#
# The counter walked ROADMAP.md line-by-line with NO notion of the heading a line sits under —
# roadmap-lint.sh had the only `is_exempt_heading` in the repo, and it was lint-only.
#
# FIX SHAPE: share ONE predicate (lib-roadmap-sections.sh) between the lint and the counter, and
# track the in-effect heading while counting. UNDER-DISPATCH-SAFE by design, consistent with
# every other filter in that loop: when in doubt the item is skipped, never invented.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
LIB="$SRC_DIR/relay/scripts/lib-roadmap-sections.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$GATHER" ]] || fail "gather-repo-state.sh not found"
[[ -f "$LIB" ]] || fail "lib-roadmap-sections.sh not found — the shared predicate must exist, not be re-inlined"

# ── (1) ONE definition of the predicate, not two ────────────────────────────────────────
# A second inline copy is the exact defect class id:1022 came from.
inline_defs=$(grep -rlE '^is_exempt_heading\(\)' "$SRC_DIR/relay/scripts/" | grep -v 'lib-roadmap-sections.sh' || true)
[[ -z "$inline_defs" ]] \
  || fail "is_exempt_heading is defined outside the shared lib (a second copy will drift): $inline_defs"
grep -q 'lib-roadmap-sections.sh' "$SRC_DIR/relay/scripts/roadmap-lint.sh" \
  || fail "roadmap-lint.sh no longer sources the shared predicate"
grep -q 'lib-roadmap-sections.sh' "$GATHER" \
  || fail "gather-repo-state.sh does not source the shared predicate — the counter is still heading-blind"
pass "exactly one is_exempt_heading, shared by the lint and the counter"

# ── (2) the predicate itself ────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$LIB"
for h in "## Gated / deferred" "### Gated on OPEN owner decisions" "## Deferred (named reopen triggers)" \
         "## Done" "## Icebox" "## Archive" "## Parked"; do
  is_exempt_heading "$h" || fail "heading not recognised as parked: $h"
done
for h in "## Items" "## Current" "### Open (promoted 2026-08-11)" "## Roadmap"; do
  is_exempt_heading "$h" && fail "ACTIVE heading wrongly treated as parked: $h"
done
pass "parked headings match; active headings do not"

# ── (3) end-to-end: a synthetic repo reproducing the zkWhale shape ──────────────────────
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
cat > "$repo/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD] A genuinely active pool item <!-- id:aaaa -->
- [ ] [ROUTINE] A routine item <!-- id:bbbb -->

## Gated / deferred

> Items parked here are explicitly deferred.

- [ ] [HARD] Parked, gated on an open owner decision <!-- id:cccc -->
- [ ] [HARD] Also parked <!-- id:dddd -->

### Gated on OPEN owner decisions

- [ ] [HARD] Parked under a nested gated heading <!-- id:eeee -->
MD
git -C "$repo" add -A
git -C "$repo" commit -qm init

count="$("$GATHER" --repo synth --path "$repo" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["open_hard_pool"])')"
[[ "$count" == "1" ]] \
  || fail "open_hard_pool=$count, expected 1 (only the item under '## Items'; the 3 under gated headings must not count)"
pass "only the active-section [HARD] item is counted (1 of 4)"

# ── (4) a repo with NO parked heading is unaffected (no over-filtering) ─────────────────
cat > "$repo/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD] one <!-- id:1111 -->
- [ ] [HARD] two <!-- id:2222 -->
MD
git -C "$repo" add -A
git -C "$repo" commit -qm two
count2="$("$GATHER" --repo synth --path "$repo" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["open_hard_pool"])')"
[[ "$count2" == "2" ]] || fail "open_hard_pool=$count2, expected 2 — a ROADMAP with no parked heading must be unchanged"
pass "a ROADMAP with no parked heading counts exactly as before"

echo "ALL PASS: parked [HARD] items are not dispatched (4b8f)"
