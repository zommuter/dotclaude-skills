#!/usr/bin/env bash
# (no roadmap token — new-feature/defect test for relay/scripts/archive-closed.sh.
#  This test always counts.)
#
# archive-closed.sh moves genuine top-level closed `- [x]` items from BOTH
# TODO.md and ROADMAP.md into their `*.archive.md` siblings, TWIN-SAFELY:
# an item bearing <!-- id:XXXX --> is only archived when its cross-ledger twin
# is also closed OR absent — never when the twin is still open `- [ ]` (that is
# the drift orphan-scan --cross-ledger guards). No-id items have no twin → safe.
# Multi-line item bodies move as a whole block; headings are preserved; --dry-run
# mutates nothing; a second run is a no-op.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/archive-closed.sh"

[[ -f "$SCRIPT" ]] || { echo "archive-closed.sh missing at $SCRIPT"; exit 1; }

# ---- seed a hermetic repo fixture -----------------------------------------
seed() {
  local repo="$1"
  mkdir -p "$repo"
  cat > "$repo/TODO.md" <<'EOF'
# TODO

## Current
- [x] closed both ledgers <!-- id:aaaa -->
- [ ] open twin here <!-- id:bbbb -->
- [x] closed no id item
- [x] multi-line closed item <!-- id:cccc -->
  - continuation sub-bullet of the multi-line item
    wrapped prose under the multi-line item
- [ ] plain open item stays
EOF
  cat > "$repo/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue
- [x] closed both ledgers <!-- id:aaaa -->
- [x] roadmap closed but twin open <!-- id:bbbb -->
- [ ] some open roadmap item stays
EOF
}

# =========================================================================
# Part A — --dry-run mutates nothing but reports would-move + skipped twin
# =========================================================================
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd" "$tmpr"' EXIT
repd="$tmpd/repo"; seed "$repd"
todo_before="$(cat "$repd/TODO.md")"
road_before="$(cat "$repd/ROADMAP.md")"

out="$(HOME="$tmpd" bash "$SCRIPT" --dry-run "$repd" 2>&1)" || {
  echo "--dry-run exited non-zero"; echo "$out"; exit 1; }

[[ ! -e "$repd/TODO.archive.md" ]]    || { echo "dry-run created TODO.archive.md"; exit 1; }
[[ ! -e "$repd/ROADMAP.archive.md" ]] || { echo "dry-run created ROADMAP.archive.md"; exit 1; }
[[ "$(cat "$repd/TODO.md")"    == "$todo_before" ]] || { echo "dry-run mutated TODO.md"; exit 1; }
[[ "$(cat "$repd/ROADMAP.md")" == "$road_before" ]] || { echo "dry-run mutated ROADMAP.md"; exit 1; }

grep -q 'bbbb' <<<"$out" || { echo "dry-run summary did not name skipped twin id bbbb"; echo "$out"; exit 1; }
grep -Eiq 'would.*(move|archiv)' <<<"$out" || { echo "dry-run summary lacks would-move count"; echo "$out"; exit 1; }

# =========================================================================
# Part B — real run archives twin-safely from both ledgers
# =========================================================================
tmpr="$(mktemp -d)"; repr="$tmpr/repo"; seed "$repr"
HOME="$tmpr" bash "$SCRIPT" "$repr" >/dev/null 2>&1 || { echo "real run exited non-zero"; exit 1; }

TA="$repr/TODO.archive.md"; RA="$repr/ROADMAP.archive.md"
TS="$repr/TODO.md";         RS="$repr/ROADMAP.md"
[[ -f "$TA" ]] || { echo "TODO.archive.md not created"; exit 1; }
[[ -f "$RA" ]] || { echo "ROADMAP.archive.md not created"; exit 1; }

# 1) id:aaaa closed in BOTH → archived from BOTH, gone from both sources.
grep -qF 'closed both ledgers' "$TA" || { echo "aaaa not in TODO archive"; exit 1; }
grep -qF 'closed both ledgers' "$RA" || { echo "aaaa not in ROADMAP archive"; exit 1; }
grep -qF 'closed both ledgers' "$TS" && { echo "aaaa still in TODO.md"; exit 1; }
grep -qF 'closed both ledgers' "$RS" && { echo "aaaa still in ROADMAP.md"; exit 1; }

# 2) id:bbbb — ROADMAP [x] but TODO [ ] open → twin-open protection:
#    NOT archived from ROADMAP; both sources keep their line.
grep -qF 'roadmap closed but twin open' "$RA" && { echo "bbbb wrongly archived (twin open!)"; exit 1; }
grep -qF 'roadmap closed but twin open' "$RS" || { echo "bbbb missing from ROADMAP.md"; exit 1; }
grep -qF 'open twin here' "$TS"                || { echo "bbbb open item missing from TODO.md"; exit 1; }

# 3) no-id closed item → archived from its ledger.
grep -qF 'closed no id item' "$TA" || { echo "no-id item not archived"; exit 1; }
grep -qF 'closed no id item' "$TS" && { echo "no-id item still in TODO.md"; exit 1; }

# 4) multi-line closed item (id:cccc, twin absent) → WHOLE block moves.
for frag in \
  'multi-line closed item' \
  'continuation sub-bullet of the multi-line item' \
  'wrapped prose under the multi-line item'; do
  grep -qF "$frag" "$TA" || { echo "multiline frag not archived: $frag"; cat "$TA"; exit 1; }
  grep -qF "$frag" "$TS" && { echo "multiline frag orphaned in TODO.md: $frag"; cat "$TS"; exit 1; }
done

# open items must stay put and NOT leak into archives.
grep -qF 'plain open item stays'      "$TS" || { echo "open item wrongly removed from TODO"; exit 1; }
grep -qF 'some open roadmap item stays' "$RS" || { echo "open item wrongly removed from ROADMAP"; exit 1; }
grep -qF 'plain open item stays' "$TA" && { echo "open item leaked into TODO archive"; exit 1; }

# 6a) headings preserved in the source ledgers.
grep -qF '## Current' "$TS" || { echo "TODO heading removed"; exit 1; }
grep -qF '## Queue'   "$RS" || { echo "ROADMAP heading removed"; exit 1; }
grep -qF '# TODO'     "$TS" || { echo "TODO H1 removed"; exit 1; }

# 6b) idempotent: second run archives nothing new (archive line counts stable).
ta1="$(grep -cF 'closed both ledgers' "$TA")"
HOME="$tmpr" bash "$SCRIPT" "$repr" >/dev/null 2>&1 || { echo "second run exited non-zero"; exit 1; }
ta2="$(grep -cF 'closed both ledgers' "$TA")"
[[ "$ta1" == "$ta2" ]] || { echo "second run duplicated archive entries ($ta1 -> $ta2)"; exit 1; }

echo ok
