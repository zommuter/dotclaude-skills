#!/usr/bin/env bash
# roadmap:8372
#
# RED SPEC for ROADMAP id:8372 -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# THE DEFECT. `tools/ledger-shrink.py`'s keep-set carries a STRUCTURAL catch-all,
# `<!--[^>]*-->`, so a marker minted later survives relocation without the pattern list
# being updated. That rule is correct and was adopted deliberately. It cannot distinguish
# a REAL marker from a marker QUOTED AS AN EXAMPLE in prose, so when an item's body
# discusses marker syntax, the shrinker hoists the examples onto the head line as if they
# were the item's own.
#
# Measured on the live ledger: `id:ee62` -- whose subject is literally "use visible
# annotations, not HTML comments" -- came out carrying `<!-- id:XXXX -->`,
# `<!-- routed:XXXX -->` and a hoisted `@manual`, and an UNTERMINATED `<!-- xledger-ok:`
# example let the catch-all match through to a far-away `-->`, dragging ~300 chars of
# prose back onto the head line and defeating the shrink entirely. 30 ledger lines carry
# a placeholder marker of this shape (28 in TODO.md, 2 in ROADMAP.md).
#
# WHY NO EXISTING GUARD FIRES. The hoisted tokens are not valid ids (`XXXX` is not
# `[0-9a-f]{4}`), so no owning-marker check sees them and id:6059's multi-marker refusal
# does not fire. The corruption is invisible to every existing guard: it only degrades the
# ledger for a human reader, and it silently defeats the shrink.
#
# THE COUPLING, recorded so the fix is a stated decision rather than an accident of which
# file got edited: `relay/scripts/classify-repo.sh` deliberately does NOT mask backticks
# (id:1254), so a backticked lane bracket IS the computed lane today, and
# `tools/roundtrip-validate.py` mirrors that (id:ff7c). Masking markers here while leaving
# lanes unmasked there is defensible -- a lane and a marker are different objects -- but
# case (D) pins that the lane side is not changed by this fix.
#
# Hermetic: mktemp only, no live ledger, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHRINK="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SHRINK" ]] || fail "setup: ledger-shrink.py not found at $SHRINK"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

PAD='Padding prose that makes the item long enough to be a shrink candidate under the default 500-char budget, repeated so the head line is unambiguously over it. '

# --- fixture 1: the ee62 shape, examples inside inline-code spans ----------------------
A="$TMP/a"; mkdir -p "$A/docs/ledger-notes"
{
  echo '# TODO'
  echo
  echo '## Current'
  echo
  printf -- '- [ ] [INPUT - meeting] **Use VISIBLE annotations, not HTML comments, for metadata that should render.** An id is written `<!-- id:XXXX -->` and a routing breadcrumb `<!-- routed:XXXX -->`; a `@manual` marker is prose, not a comment. %s%s%s <!-- id:ee01 -->\n' \
    "$PAD" "$PAD" "$PAD"
} > "$A/TODO.md"

python3 "$SHRINK" --file TODO.md --root "$A" --apply >/dev/null 2>&1 || \
  fail "setup: the shrinker exited non-zero on fixture 1"
head1="$(grep -F 'id:ee01' "$A/TODO.md" || true)"
[[ -n "$head1" ]] || fail "setup: the ee01 item vanished from the ledger"

# --- (A) NO EXAMPLE MARKER IS HOISTED -------------------------------------------------
if grep -qF 'id:XXXX' <<<"$head1"; then
  fail "(A) the prose example \`<!-- id:XXXX -->\` was hoisted onto the head line as if it were the item's own marker: $head1"
fi
if grep -qF 'routed:XXXX' <<<"$head1"; then
  fail "(A2) the prose example \`<!-- routed:XXXX -->\` was hoisted onto the head line: $head1"
fi
if grep -qF '@manual' <<<"$head1"; then
  fail "(A3) the backticked \`@manual\` was hoisted out of prose onto the head line: $head1"
fi
pass "(A) markers quoted inside inline-code spans are not hoisted"

# --- (B) THE ITEM'S OWN MARKER IS STILL KEPT ------------------------------------------
# A fix that simply stopped hoisting would ORPHAN the item -- the id:6059 /
# md-merge-unwritable class, far worse than a long line.
grep -qF '<!-- id:ee01 -->' <<<"$head1" || \
  fail "(B) the item's OWN id marker is no longer on the head line -- the item is orphaned: $head1"
grep -qF 'docs/ledger-notes/ee01.md' <<<"$head1" || \
  fail "(B2) the detail pointer is missing from the head line: $head1"
pass "(B) the item's own marker and its detail pointer survive"

# --- (C) AN UNTERMINATED EXAMPLE DOES NOT DRAG PROSE BACK ------------------------------
B="$TMP/b"; mkdir -p "$B/docs/ledger-notes"
{
  echo '# TODO'
  echo
  echo '## Current'
  echo
  printf -- '- [ ] [ROUTINE] **Cross-ledger marker syntax.** The opener is spelled `<!-- xledger-ok:"*` at roughly L63; back-compat or a one-shot migrate. %sTHE-TAIL-SENTINEL and a closing --> far from the opener. %s <!-- id:ee02 -->\n' \
    "$PAD$PAD" "$PAD"
} > "$B/TODO.md"
python3 "$SHRINK" --file TODO.md --root "$B" --apply >/dev/null 2>&1 || \
  fail "setup: the shrinker exited non-zero on fixture 2"
head2="$(grep -F 'id:ee02' "$B/TODO.md" || true)"
[[ -n "$head2" ]] || fail "setup: the ee02 item vanished from the ledger"
if grep -qF 'THE-TAIL-SENTINEL' <<<"$head2"; then
  fail "(C) an UNTERMINATED example marker let the catch-all match through to a far-away \`-->\`, dragging body prose back onto the head line: $head2"
fi
(( ${#head2} < 500 )) || \
  fail "(C2) the head line is still ${#head2} chars -- the unterminated example defeated the shrink for this item"
pass "(C) an unterminated example marker does not drag prose onto the head line"

# --- (D) THE LANE SIDE IS NOT CHANGED BY THIS FIX -------------------------------------
# id:1254 / id:ff7c: `classify-repo.sh` deliberately does NOT mask backticks, so a
# backticked lane bracket IS the computed lane. This spec masks MARKERS in the shrinker;
# it must not quietly start masking lane brackets too, which would put the shrinker and
# the classifier into disagreement about the same line.
grep -qF '[ROUTINE]' <<<"$head2" || \
  fail "(D) the item's lane tag was lost from the head line: $head2"
pass "(D) the lane tag is untouched"

echo "ALL PASS: id:8372 example markers quoted in prose are not hoisted"
