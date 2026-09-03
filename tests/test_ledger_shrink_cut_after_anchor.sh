#!/usr/bin/env bash
# Defect-fix test -- NO `# roadmap:` header on purpose, so its failures ALWAYS count.
#
# fails-against-mutation: sed -i 's/ and _ok(m.end())//' tools/ledger-shrink.py
# fails-against-assertion: (1) the item was NOT shrunk
#   The mutation removes ONLY the anchor clamp from the bold-run branch, restoring the exact
#   pre-fix behaviour. The cut then lands at the end of the trailing annotation (= end of
#   line), leaving 0 residue, so the tool refuses with `too-little-to-move` and NOTHING
#   shrinks -- which is assertion (1), not (2). (2) is the split-direction discriminator and
#   is only reached once something shrinks at all.
#   The declared text is the FAIL branch's wording, which occurs exactly once in the body:
#   the PASS branch reads "(1) the item SHRANK", a different string. A declaration matching
#   two sites is a CONFIG ERROR because it cannot say which branch fired. Narrow, never loosen.
#   `fail()` exits, so the first FAIL line is also the last.
#
# THE DEFECT (found 2026-09-03 on the live ROADMAP.md:58, id:931c, 994 chars).
#
# `find_cut()` took "the end of the first bold run" as the title boundary. That assumes the
# bold run IS the title, near the start of the line. It is FALSE for the
# `grammar-item-after-id` shape:
#
#     - [ ] [LANE] plain unbolded title <!-- id:XXXX --> **a huge trailing annotation**
#
# Here the real title is unbolded text BEFORE the anchor, and the only bold run is an
# annotation appended AFTER it. Measured on the live line: the id marker sat at offset 102,
# the first bold run began at 119, so the cut landed at 994 -- the end of the line -- and the
# tool reported `too-little-to-move` (0 residue) while silently treating 875 chars of
# annotation as "title". The item then sits over budget forever and NOTHING reports why:
# the refusal counter says "under 25 chars would move", which is true and completely
# misleading.
#
# THE RULE: an item's own `<!-- id:XXXX -->` is its ANCHOR. A title cannot follow the anchor
# that names it, so no cut may land after it. Whatever follows the anchor is annotation --
# which is exactly what should move.
#
# WHY THE ANCHOR IS SAFE TO CUT AT: the id marker is a MUST_KEEP token, so it is lifted out
# of the moved residue and re-emitted on the head line. The id never leaves the ledger. This
# test asserts that, because getting it wrong would ORPHAN the item (the id:6059 /
# md-merge-unwritable class) -- a far worse outcome than a long line.
#
# Hermetic: mktemp only, no live ledger, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHRINK="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SHRINK" ]] || fail "sanity: ledger-shrink.py not found at $SHRINK"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/docs/ledger-notes"

TITLE='Custom agent types per relay subcommand'
ANNO='**[2026-07-21 -- evaluate UNDER the id:cae2 audit as candidate #2, not piecemeal. Scope narrowed to the JUDGMENT roles (executor, reviewer, handoff, discover-shard); the mechanical variant is SUPERSEDED by the proxy, which already dispatches those hops without an agent at all. Primary value is RELIABILITY, not token cost, and the audit must price both halves before anything is built on it. Note the prior estimate counted the shard as an inference hop, which it has not been since the mechanical conversion landed, so the figure it produced was wrong in the expensive direction.]**'
LINE="- [ ] [INPUT - meeting] ${TITLE} -- see TODO.md <!-- id:ab12 --> ${ANNO}"

{ echo '# ROADMAP'; echo; echo '## Current'; echo; echo "$LINE"; } > "$TMP/ROADMAP.md"

(( ${#LINE} > 500 )) || fail "(fixture) the line must be over the 500-char budget to be a candidate; it is ${#LINE}"
_anchor=$(python3 -c "import sys;print(sys.argv[1].find('<!-- id:ab12 -->'))" "$LINE")
_bold=$(python3 -c "import re,sys;print(re.search(r'\*\*[^*]+\*\*', sys.argv[1]).start())" "$LINE")
(( _bold > _anchor )) \
  && pass "(fixture) armed: the only bold run (offset $_bold) starts AFTER the id anchor (offset $_anchor)" \
  || fail "(fixture) broken: the bold run must start AFTER the anchor or this proves nothing"

out="$(python3 "$SHRINK" --file "$TMP/ROADMAP.md" --root "$TMP" --apply 2>&1)" || fail "shrink failed: $out"

grep -qE 'items to shrink +: 1' <<<"$out" \
  && pass "(1) the item SHRANK -- it is no longer refused as 'too-little-to-move'" \
  || fail "(1) the item was NOT shrunk; the after-anchor bold run is still being read as the title. Output:"$'\n'"$out"

new="$(grep -F 'id:ab12' "$TMP/ROADMAP.md")"

# (2) THE DISCRIMINATOR. A cut in the wrong place could shrink the line by moving the TITLE
# and keeping the annotation. Assert the split went the right way round.
if grep -qF "$TITLE" <<<"$new" && ! grep -qF 'Primary value is RELIABILITY' <<<"$new"; then
  pass "(2) the ANNOTATION is what moved; the title stayed on the ledger line"
else
  fail "(2) the ANNOTATION is what moved -- wrong split. Head line is now:"$'\n'"$new"
fi

grep -qF '<!-- id:ab12 -->' <<<"$new" \
  && pass "(3) the id anchor is STILL on the head line -- the item was not orphaned" \
  || fail "(3) the id marker left the ledger line; that orphans the item (id:6059 class):"$'\n'"$new"

grep -qF 'Primary value is RELIABILITY' "$TMP/docs/ledger-notes/ab12.md" \
  && pass "(4) the moved annotation landed in docs/ledger-notes/ab12.md" \
  || fail "(4) the annotation is not in the note -- it was DELETED, not relocated"

(( ${#new} < 500 )) \
  && pass "(5) the head line is now under budget (${#new} chars, was ${#LINE})" \
  || fail "(5) the head line is still over budget at ${#new} chars"

grep -qF '[INPUT - meeting]' <<<"$new" \
  && pass "(6) the lane tag is unchanged on the head line -- no computed-lane change" \
  || fail "(6) the lane tag did not survive the cut:"$'\n'"$new"

echo "ALL PASS"
