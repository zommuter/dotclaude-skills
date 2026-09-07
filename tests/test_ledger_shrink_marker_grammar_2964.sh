#!/usr/bin/env bash
# roadmap:2964
#
# fails-against: the pre-fix `tools/ledger-shrink.py`, whose structural keep-set catch-all
# was the unanchored `<!--[^>]*-->` and which did not mask markers quoted inside inline-code
# spans. Both halves are reverted by the mutation below; either one alone reproduces a
# distinct half of the defect.
# fails-against-mutation: sed -i -e 's|^_MARKER_RE = re.compile(_MARKER_RE_SRC)$|_MARKER_RE = re.compile(r"<!--[^>]*-->")|' -e 's|^_MASK_QUOTED_MARKERS = True$|_MASK_QUOTED_MARKERS = False|' tools/ledger-shrink.py
# fails-against-assertion: (A) a marker QUOTED inside an inline-code span was hoisted
#
# THE DEFECT (TODO id:2964). `tools/ledger-shrink.py`'s structural keep-set catch-all
# `<!--[^>]*-->` is not anchored to any marker SHAPE. Two consequences, both measured on the
# live `TODO.md` on 2026-09-07:
#
#   (1) A bare `<!--` appearing inside BACKTICKED PROSE -- which happens whenever an item is
#       ABOUT marker syntax -- starts a match that runs forward to the next `>` ANYWHERE in
#       the body, hoisting every character in between onto the head line. `TODO.md:722`
#       (id:5817) ended with a spliced mid-sentence fragment; `TODO.md:34` (id:ee62) ended
#       with five list items dragged out of its body.
#   (2) A WELL-FORMED marker quoted as an EXAMPLE (`<!-- id:XXXX -->`, `<!-- routed:XXXX -->`)
#       is shape-identical to a real one, so it is hoisted as if it were the item's own.
#
# WHAT THE FIX MAY NOT DO. The catch-all exists so that a marker type minted LATER cannot
# silently fall out of the keep-set (the id:d35a class -- `children:` and `xledger-ok:` were
# both lost exactly that way before it was added, and `CLAUDE.md` records it as a strength).
# A fixed enumeration of today's marker NAMES trades this bug for that regression. Case (E)
# below pins the open-ended property with a marker name that exists nowhere in the tree.
#
# Hermetic: mktemp only, no live ledger, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHRINK="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SHRINK" ]] || fail "setup: ledger-shrink.py not found at $SHRINK"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

PAD='Padding prose that pushes this item well past the default 500-char head-line budget so it is unambiguously a shrink candidate, repeated as needed. '

mkledger() {  # $1 = dir, $2 = the single item line
  mkdir -p "$1/docs/ledger-notes"
  { echo '# TODO'; echo; echo '## Current'; echo; printf -- '%s\n' "$2"; } > "$1/TODO.md"
}

# --------------------------------------------------------------------------------------
# fixture A: a well-formed marker quoted as an EXAMPLE inside inline-code spans
# --------------------------------------------------------------------------------------
A="$TMP/a"
mkledger "$A" "- [ ] [ROUTINE] **Marker syntax should be visible, not hidden in comments.** An item's id is written \`<!-- id:XXXX -->\` and its routing breadcrumb \`<!-- routed:XXXX -->\`, neither of which renders. ${PAD}${PAD}${PAD} <!-- id:aa01 -->"

python3 "$SHRINK" --file TODO.md --root "$A" --apply >/dev/null 2>&1 \
  || fail "setup: the shrinker exited non-zero on fixture A"
headA="$(grep -F 'id:aa01' "$A/TODO.md" || true)"
[[ -n "$headA" ]] || fail "setup: the aa01 item vanished from the ledger"

grep -qF 'id:XXXX' <<<"$headA" \
  && fail "(A) a marker QUOTED inside an inline-code span was hoisted onto the head line as if it were the item's own: $headA"
grep -qF 'routed:XXXX' <<<"$headA" \
  && fail "(A2) the quoted example \`<!-- routed:XXXX -->\` was hoisted onto the head line: $headA"
pass "(A) example markers quoted in inline-code spans are not hoisted"

# The fix must not ORPHAN the item -- losing the real anchor is far worse than a long line.
grep -qF '<!-- id:aa01 -->' <<<"$headA" \
  || fail "(B) the item's OWN id marker is gone from the head line -- the item is orphaned: $headA"
grep -qF 'docs/ledger-notes/aa01.md' <<<"$headA" \
  || fail "(B2) the detail pointer is missing from the head line: $headA"
pass "(B) the item's own marker and detail pointer survive"

# --------------------------------------------------------------------------------------
# fixture C: a BARE, unterminated `<!--` inside backticked prose
# --------------------------------------------------------------------------------------
C="$TMP/c"
mkledger "$C" "- [ ] [ROUTINE] **Cross-ledger suppression opener.** The opener is spelled \`<!-- xledger-ok:\"*\` at roughly L63; back-compat or a one-shot migrate. ${PAD}${PAD}TAIL_SENTINEL_2964 sits deep in the body and must stay there. ${PAD} <!-- id:aa02 -->"

python3 "$SHRINK" --file TODO.md --root "$C" --apply >/dev/null 2>&1 \
  || fail "setup: the shrinker exited non-zero on fixture C"
headC="$(grep -F 'id:aa02' "$C/TODO.md" || true)"
[[ -n "$headC" ]] || fail "setup: the aa02 item vanished from the ledger"

grep -qF 'TAIL_SENTINEL_2964' <<<"$headC" \
  && fail "(C) an unterminated \`<!--\` in prose let the keep-set match run across the body, splicing prose onto the head line: $headC"
(( ${#headC} < 500 )) \
  || fail "(C2) the head line is still ${#headC} chars -- the prose splice defeated the shrink entirely"
pass "(C) an unterminated \`<!--\` in prose does not splice body prose onto the head line"

grep -qF '[ROUTINE]' <<<"$headC" \
  || fail "(D) the lane tag was lost from the head line: $headC"
pass "(D) the lane tag is untouched"

# --------------------------------------------------------------------------------------
# fixture E: the OPEN-ENDED property -- a marker NAME nobody has enumerated
# --------------------------------------------------------------------------------------
# This is the regression the catch-all exists to prevent. `zz-unknown-marker` appears in no
# pattern list anywhere; it must still be kept on the head line purely because it has the
# SHAPE of a marker. A fix that swapped the catch-all for a fixed enumeration of today's
# names fails here.
E="$TMP/e"
mkledger "$E" "- [ ] [ROUTINE] **An item carrying a marker type minted after this tool was written.** ${PAD}${PAD}${PAD} <!-- zz-unknown-marker:7f3a --> <!-- id:aa03 -->"

python3 "$SHRINK" --file TODO.md --root "$E" --apply >/dev/null 2>&1 \
  || fail "setup: the shrinker exited non-zero on fixture E"
headE="$(grep -F 'id:aa03' "$E/TODO.md" || true)"
[[ -n "$headE" ]] || fail "setup: the aa03 item vanished from the ledger"

grep -qF '<!-- zz-unknown-marker:7f3a -->' <<<"$headE" \
  || fail "(E) an UNENUMERATED marker type was relocated off the head line -- the structural catch-all property was lost (do not replace it with a fixed list of today's marker names): $headE"
pass "(E) an unenumerated marker type is still kept by SHAPE"

echo "ALL PASS: id:2964 keep-set markers are matched by shape, not by running across prose"
