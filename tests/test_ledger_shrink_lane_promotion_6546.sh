#!/usr/bin/env bash
# No roadmap header -- defect-fix spec under TODO id:6546. Failures always count.
#
# Defect, MEASURED on loderite 2026-09-02 during a real (reverted) run: the wave-2
# "re-emit a relocated lane tag in the LEADING run" rule promoted EVERY lane token found
# in the moved region. But a lane token in an item's BODY is usually PROSE ABOUT a lane,
# not the item's lane, so three OPEN items were hoisted out of human lanes into
# pool/routine-carrying ones:
#
#   affd  [INPUT - access]  ->  [HARD - pool] [HARD - decision gate] [INPUT - access]
#   6e7a  [INPUT - access]  ->  [ROUTINE] [INPUT - access]
#   1e21  [INPUT - meeting] ->  [HARD] [INPUT - meeting]
#
# That is the OVER-DISPATCH direction. The bug it was written to fix (a relocated tag
# landing in the TAIL, after the detail pointer, invisible to leading-run detectors) is
# silently INVISIBLE; this one is silently WRONG. Given the choice, invisible is safer, so
# the refusal branch matters more than the promotion branch.
#
# Clause, after a SECOND round of evidence: the tool NEVER promotes. Round two tried
# "promote only when the leading run has no lane and the body offers exactly one", and that
# still gave three OPEN items in this repo a dispatch lane inferred from prose. loderite
# settles it independently -- its ROADMAP carries a literal
# `[HARD - decision gate|hands|meeting|pool]` enumeration, ONE well-formed token by any
# regex and pure prose by meaning, so even the "exactly one" test promotes nonsense.
# The token is always KEPT (in the tail, where it already was) and REPORTED. Not promoting
# is the STATUS QUO -- the tag is exactly as visible to leading-run detectors as before the
# shrink -- so nothing regresses, and only a human can place it deliberately.
#
# fails-against: the fix and this spec land in the same commit, so the negative case is a
# mutation restoring the unconditional promotion.
# fails-against-mutation: python3 -c "import io; p='tools/ledger-shrink.py'; s=io.open(p,encoding='utf-8').read(); s=s.replace('    head_prefix = prefix\n    tail_parts = tail_parts + lane_parts','    import re as _r; _m=TOP_ITEM_RE.match(prefix); _at=_m.end() if _m else 0; head_prefix = prefix[:_at] + \" \" + \" \".join(lane_parts) + prefix[_at:] if lane_parts else prefix',1); io.open(p,'w',encoding='utf-8').write(s)"
# fails-against-assertion: (a) an item that ALREADY has a lane must not gain one from body prose
#
# Hermetic: temp ledger + temp notes dir; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "sanity: $TOOL must exist"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/docs/ledger-notes"

filler="the rationale continues at length so that there is definitely enough prose here to be worth relocating into a detail file, repeated for bulk aaaa bbbb cccc dddd eeee ffff"

cat >"$tmp/TODO.md" <<MD
# TODO

## Current

- [ ] [INPUT - access] **Already laned, body mentions other lanes** -- we rejected doing this as [HARD - pool] and also as [HARD - decision gate]; $filler <!-- id:cc01 -->
- [ ] **No lane at all, body names exactly one** -- this belongs in [ROUTINE] once unblocked; $filler <!-- id:cc02 -->
- [ ] **No lane, body names several** -- could be [ROUTINE] or [HARD] depending on the call; $filler <!-- id:cc03 -->
MD

cp "$tmp/TODO.md" "$tmp/rep-src.md"   # pristine copy for case (e); --apply mutates in place

python3 "$TOOL" --file TODO.md --root "$tmp" --min-chars 200 --apply >/dev/null 2>&1 \
  || fail "sanity: the tool exited non-zero on the fixture"

line() { grep -F "id:$1 -->" "$tmp/TODO.md"; }
lead() { line "$1" | grep -oP '^- \[[ xX]\]\s*(\[[^]]+\]\s*)*'; }

# --- (a) THE DEFECT: an item that already has a lane must not gain one from prose -------
l="$(lead cc01)"
[[ "$l" != *"HARD"* ]] \
  || fail "(a) an item that ALREADY has a lane must not gain one from body prose -- leading run is now: $l"
[[ "$l" == *"INPUT - access"* ]] \
  || fail "(a) the item's OWN lane was lost from the leading run: $l"

# --- (b) the tag is still KEPT, just not promoted ---------------------------------------
# Not promoting must never mean dropping: the relocated body must not be the only place a
# lane token survives, or the shrink has silently un-laned a mention.
line cc01 | grep -q 'HARD - pool' \
  || fail "(b) a non-promoted lane token was DROPPED from the line entirely: $(line cc01)"

# --- (c) NO leading lane, exactly one in the body -> STILL not promoted ------------------
# The second cut of this rule promoted here, and it gave three OPEN items in this repo a
# dispatch lane inferred from prose. Position cannot distinguish "the item's real lane sits
# mid-body" from "the prose mentions a lane". loderite's ROADMAP settles it independently:
# it carries a literal `[HARD - decision gate|hands|meeting|pool]` enumeration, which is ONE
# well-formed token by any regex and pure prose by meaning, so even the "exactly one" test
# promotes nonsense. The tool never decides what an item's lane IS.
l="$(lead cc02)"
[[ "$l" != *"[ROUTINE]"* ]] \
  || fail "(c) a lane was inferred from body prose onto an item with no leading lane; got: $l"
line cc02 | grep -q 'ROUTINE' \
  || fail "(c) not promoting must still KEEP the token on the line: $(line cc02)"

# --- (d) ambiguous case: no leading lane, several in the body -> also kept, not picked ----
l="$(lead cc03)"
[[ "$l" != *"[ROUTINE]"* && "$l" != *"[HARD]"* ]] \
  || fail "(d) the tool GUESSED a lane from prose offering several; got: $l"
line cc03 | grep -q 'ROUTINE' \
  || fail "(d) refusing to promote must still KEEP the tokens on the line: $(line cc03)"

# --- (e) the population is SURFACED, not silently left ------------------------------------
# Refusing to act is only safe if it is LOUD. A human is the only actor that can place these,
# and they cannot place what they are not told about. Run against a FRESH copy: the tree
# above has already been split, so a re-run there reports nothing and would make this
# assertion vacuous -- the id:a73c unreached-fixture class.
fresh="$tmp/fresh"; mkdir -p "$fresh/docs/ledger-notes"
cp "$tmp/rep-src.md" "$fresh/TODO.md"
rep="$(python3 "$TOOL" --file TODO.md --root "$fresh" --min-chars 200 --dry-run 2>&1)"
grep -q 'LANE TOKEN OUTSIDE THE LEADING RUN' <<<"$rep" \
  || fail "(e) the lane-in-body population must be REPORTED, not silently left; got: $rep"
grep -qE 'id:cc0[123]' <<<"$rep" \
  || fail "(e) the report must name the items so a human can act on them; got: $rep"

pass "ledger-shrink NEVER promotes a body lane token into the leading run (id:6546) -- it never overrides an existing lane, never infers one for an item that lacks it, never guesses between several, and always keeps the token on the line"
