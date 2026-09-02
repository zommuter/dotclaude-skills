#!/usr/bin/env bash
# roadmap:64f9
#
# RED SPEC (authored by relay handoff C3, not implemented here).
#
# 257 ledger items (252 TODO.md, 5 ROADMAP.md, measured 2026-09-02 by the id:b048 grammar
# check) have a TITLE that is itself over budget. No relocation can shorten a title, so
# these are the residue after every mechanical lever is spent -- `ledger-shrink.py`
# refuses 45 of the 68 over-500 head lines because the line IS the title. They need
# REWRITING, which is writing, and a bad rewrite silently changes what an item is
# understood to be. That is why the item is batched and gated on the id:ff7c validator.
#
# WHAT A BATCH IS ACCEPTED ON, straight from the item's acceptance text:
#   * no `grammar-item-title-long` for the batch;
#   * the FULL ORIGINAL PROSE preserved VERBATIM in the item's `docs/ledger-notes/<id>.md`
#     -- "shortening the TITLE is not licence to drop content";
#   * the id, the lane, every marker and the checkbox state untouched;
#   * an item whose meaning cannot survive the cut is LEFT and REPORTED, never mangled.
#
# WHERE IT IS SPECIFIED, and why here rather than in a new tool: `tools/shrink-acceptance.py`
# is already this repo's BEFORE/AFTER ledger-tree comparator, already takes `--before` /
# `--after` / `--notes-dir`, and already owns the "did this pass preserve everything that
# matters" question. A title-rewrite batch is the same question with a different pass. A
# second comparator would be the drift shape this fleet keeps paying for.
#
# MEASURED AGAINST THE SHIPPED GATE, 2026-09-02, with `--skip-detectors`:
#   a batch that DELETED the entire original title prose instead of preserving it   -> SAFE TO LAND
#   a batch that FLIPPED an item's checkbox from `[ ]` to `[x]`                     -> SAFE TO LAND
# Both must refuse. Case (1) below is the green control that stops the fix from being
# "refuse everything".
#
# TRIANGULATION (id:108e): two independently-worded items are rewritten honestly and a
# third is deliberately left, so an implementation cannot pass by special-casing one
# fixture line.
#
# NOT SPECIFIED HERE, deliberately: the item's done-check also requires the id:ff7c
# directional round-trip validator to be clean (that is ff7c's own spec) and "a human
# spot-check of 10 rewritten titles against their notes agrees they still name the same
# item" -- which is not mechanisable at all, by construction. See the handoff report.
#
# Hermetic: mktemp trees only, `--skip-detectors` so nothing reads a git repo or another
# ledger, no ~/.claude, no network, no live ledger.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${SHRINK_ACCEPTANCE:-$ROOT/tools/shrink-acceptance.py}"
CONF="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$GATE" ]] || fail "sanity: shrink-acceptance.py not found at $GATE"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# ── the three BEFORE items. Each title is a paragraph; each is over the 200-char budget.
L1='- [ ] [ROUTINE] **Alpha** the title on this line is deliberately a whole paragraph rather than a title, running well past the two hundred character budget, which is the exact residue this item names and which no relocation can shorten by even one character <!-- id:a1a1 -->'
L2='- [ ] [HARD] **Bravo** this second one is worded quite differently on purpose, so that an implementation cannot satisfy the batch by pattern-matching a single fixture line, and it too is a paragraph masquerading as the title of a ledger item <!-- gated-on:a1a1 --> <!-- id:a2a2 -->'
L3='- [ ] [ROUTINE] **Charlie** this third title cannot be cut without changing what the item is understood to be, because every clause of it is load-bearing and the item would be misread as something else entirely if any of it were dropped <!-- id:a3a3 -->'

mkbefore() {
  local d="$1"
  mkdir -p "$d/docs/ledger-notes"
  { echo '# TODO'; echo; echo '## Current'; echo; echo "$L1"; echo "$L2"; echo "$L3"; } > "$d/TODO.md"
  printf '# id:a1a1\n\nExisting note body for alpha.\n' > "$d/docs/ledger-notes/a1a1.md"
  printf '# id:a2a2\n\nExisting note body for bravo.\n' > "$d/docs/ledger-notes/a2a2.md"
  printf '# id:a3a3\n\nExisting note body for charlie.\n' > "$d/docs/ledger-notes/a3a3.md"
}

# mkafter <dir> <alpha-line> <bravo-line> <charlie-line> <preserve: yes|no>
mkafter() {
  local d="$1" a="$2" b="$3" c="$4" preserve="$5"
  mkdir -p "$d/docs/ledger-notes"
  { echo '# TODO'; echo; echo '## Current'; echo; echo "$a"; echo "$b"; echo "$c"; } > "$d/TODO.md"
  printf '# id:a1a1\n\nExisting note body for alpha.\n' > "$d/docs/ledger-notes/a1a1.md"
  printf '# id:a2a2\n\nExisting note body for bravo.\n' > "$d/docs/ledger-notes/a2a2.md"
  printf '# id:a3a3\n\nExisting note body for charlie.\n' > "$d/docs/ledger-notes/a3a3.md"
  if [[ "$preserve" == yes ]]; then
    { echo; echo '## Original title (verbatim, id:64f9 title rewrite)'; echo; echo "$L1"; } >> "$d/docs/ledger-notes/a1a1.md"
    { echo; echo '## Original title (verbatim, id:64f9 title rewrite)'; echo; echo "$L2"; } >> "$d/docs/ledger-notes/a2a2.md"
  fi
}

A1_OK='- [ ] [ROUTINE] **Alpha** the title is a paragraph, not a title <!-- id:a1a1 -->'
A2_OK='- [ ] [HARD] **Bravo** a second over-budget title, differently worded <!-- gated-on:a1a1 --> <!-- id:a2a2 -->'

BEFORE="$TMP/before"; mkbefore "$BEFORE"

run_gate() { # <after-dir> -> stdout+stderr; rc written to $TMP/gate.rc
  local rc=0 out
  out="$(python3 "$GATE" --before "$BEFORE" --after "$1" --skip-detectors --quiet --notes-dir docs/ledger-notes 2>&1)" || rc=$?
  printf '%s' "$rc" > "$TMP/gate.rc"
  printf '%s' "$out"
}
gate_rc() { cat "$TMP/gate.rc"; }

# ── fixture sanity, stated as a real assertion so a broken fixture cannot be mistaken for
#    a finding: the three BEFORE titles really are over budget, and the rewritten ones are not.
before_long="$("$CONF" "$BEFORE/TODO.md" 2>/dev/null | grep -c 'grammar-item-title-long' || true)"
[[ "$before_long" == 3 ]] \
  && pass "(0) fixture: all three BEFORE titles are grammar-item-title-long" \
  || fail "(0) fixture: expected 3 over-budget BEFORE titles, todo-conformance found $before_long"

# =====================================================================================
# (1) CONTROL -- an HONEST batch is ACCEPTED. Two items rewritten with their full original
#     titles preserved verbatim in their notes; the third deliberately LEFT untouched.
# =====================================================================================
OK="$TMP/after-ok"; mkafter "$OK" "$A1_OK" "$A2_OK" "$L3" yes
out="$(run_gate "$OK")"
[[ "$(gate_rc)" == 0 ]] \
  && pass "(1) an honest title-rewrite batch is ACCEPTED" \
  || fail "(1) an honest batch was REFUSED (rc=$(gate_rc)) -- the gate must not block a correct rewrite:"$'\n'"$out"

ok_long="$("$CONF" "$OK/TODO.md" 2>/dev/null | grep -c 'grammar-item-title-long' || true)"
[[ "$ok_long" == 1 ]] \
  && pass "(1) after the batch only the deliberately-LEFT item is still title-long" \
  || fail "(1) expected exactly 1 remaining grammar-item-title-long (the left item), found $ok_long"

OK_OUT="$out"   # kept for case (7): the LEFT item must be REPORTED in an ACCEPTED batch

# =====================================================================================
# (2) DROPPED PROSE IS REFUSED. Measured SAFE TO LAND on the shipped gate: the entire
#     original title vanished and nothing objected.
# =====================================================================================
DROP="$TMP/after-drop"; mkafter "$DROP" "$A1_OK" "$A2_OK" "$L3" no
out="$(run_gate "$DROP")"
[[ "$(gate_rc)" != 0 ]] \
  && pass "(2) a batch that DROPPED the original title prose is REFUSED" \
  || fail "(2) a batch that DELETED both original titles instead of preserving them in their notes was ACCEPTED (rc=$(gate_rc)) -- shortening a title is not licence to drop content, and nothing else in the toolchain checks this:"$'\n'"$out"

# =====================================================================================
# (3) A BOTCHED REWRITE IS REFUSED -- the item was TOUCHED but is still over budget. This
#     is what separates a failed rewrite from a deliberate leave (case 7): the left item's
#     title is byte-identical to BEFORE, a botched one is not.
# =====================================================================================
BOTCH="$TMP/after-botch"
A1_BOTCH='- [ ] [ROUTINE] **Alpha** the title on this line is still a whole paragraph rather than a title and remains well past the two hundred character budget, having been edited without actually being shortened at all <!-- id:a1a1 -->'
mkafter "$BOTCH" "$A1_BOTCH" "$A2_OK" "$L3" yes
out="$(run_gate "$BOTCH")"
[[ "$(gate_rc)" != 0 ]] \
  && pass "(3) a REWRITTEN-but-still-over-budget title is REFUSED" \
  || fail "(3) an item that was rewritten and is STILL grammar-item-title-long was ACCEPTED (rc=$(gate_rc)) -- 'zero grammar-item-title-long for the batch' is the done-check, and a touched-but-unfixed item is not a deliberate leave:"$'\n'"$out"

# =====================================================================================
# (4) A FLIPPED CHECKBOX IS REFUSED. Measured SAFE TO LAND on the shipped gate.
# =====================================================================================
TICK="$TMP/after-tick"
mkafter "$TICK" "${A1_OK/- \[ \]/- [x]}" "$A2_OK" "$L3" yes
out="$(run_gate "$TICK")"
[[ "$(gate_rc)" != 0 ]] \
  && pass "(4) a batch that changed a CHECKBOX state is REFUSED" \
  || fail "(4) a batch that flipped a1a1 from open to closed was ACCEPTED (rc=$(gate_rc)) -- 'the checkbox state is untouched' is acceptance text, and a title pass that silently closes an item removes work from the queue:"$'\n'"$out"

# =====================================================================================
# (5) A CHANGED LANE IS REFUSED. A lane is dispatch routing: [HARD] -> [ROUTINE] hands a
#     judgement item to an executor.
# =====================================================================================
LANE="$TMP/after-lane"
mkafter "$LANE" "$A1_OK" "${A2_OK/\[HARD\]/[ROUTINE]}" "$L3" yes
out="$(run_gate "$LANE")"
[[ "$(gate_rc)" != 0 ]] \
  && pass "(5) a batch that changed an item's LANE TAG is REFUSED" \
  || fail "(5) a batch that changed a2a2 from [HARD] to [ROUTINE] was ACCEPTED (rc=$(gate_rc)) -- 'the lane is untouched' is acceptance text, and a silently re-laned item is dispatched to the wrong substrate:"$'\n'"$out"

# =====================================================================================
# (6) A DROPPED TYPED EDGE IS REFUSED. `gated-on:` is an address, not decoration.
# =====================================================================================
EDGE="$TMP/after-edge"
mkafter "$EDGE" "$A1_OK" "${A2_OK/ <!-- gated-on:a1a1 -->/}" "$L3" yes
out="$(run_gate "$EDGE")"
[[ "$(gate_rc)" != 0 ]] \
  && pass "(6) a batch that dropped a typed gate edge is REFUSED" \
  || fail "(6) a batch that dropped a2a2's <!-- gated-on:a1a1 --> edge was ACCEPTED (rc=$(gate_rc)) -- 'every marker untouched' is acceptance text and a lost gate edge opens a gate nobody decided to open:"$'\n'"$out"

# =====================================================================================
# (7) THE LEFT ITEM IS REPORTED. "LEFT and reported rather than mangled" -- an item
#     silently skipped is indistinguishable from one nobody looked at, and 257 items is
#     far too many to re-derive that by eye. Asserted on the ACCEPTED batch from case (1):
#     being left is not a refusal, so the report is the only place it can surface.
# =====================================================================================
grep -q 'a3a3' <<<"$OK_OUT" \
  && pass "(7) the deliberately-LEFT item a3a3 is REPORTED in the accepted batch's output" \
  || fail "(7) the LEFT item a3a3 is named nowhere in the accepted batch's output -- 'left and reported' is half the acceptance, and an unreported skip is indistinguishable from an item nobody looked at:"$'\n'"$OK_OUT"

echo "ALL PASS"
