#!/usr/bin/env bash
# id:3795 -- Defect-fix test. NO `# roadmap:` header on purpose: this pins an OBSERVED
# defect, so its failures ALWAYS count.
#
# fails-against: the pre-fix primary_lane(), which reads the post-title lane slot LITERALLY
#   and so goes lane-dark on every line tools/ledger-shrink.py has trimmed.
# fails-against-mutation: sed -i '/rest="$(strip_detail_pointer "$rest")"/d' relay/scripts/unpromoted-scan.sh
# fails-against-assertion: [MECHANICAL] after an ASCII pointer
#   The mutation deletes ONLY the pointer-skip call in primary_lane()'s bold branch (one
#   line, the sole occurrence), restoring the exact pre-fix behaviour: `rest` still begins
#   with the pointer, no tag matches at its head, the branch returns empty, and every
#   pointer-then-lane item falls to `surface`.
#   This file uses a NON-EXITING accumulator, so several FAIL lines fire under the mutation:
#   cases (1)-(8), the positive lane-after-pointer fixtures, in that order. The negative
#   fixtures (9)-(12) and the immunity check still PASS under the mutation -- that is the
#   point of them -- so the LAST FAIL line is case (8), whose label is declared above. That
#   label occurs exactly once in the body (each case label is unique by construction), which
#   is what lets the runner say WHICH assertion fired.
#
# THE DEFECT (measured 2026-09-04 on this repo's live TODO.md, before the 46-repo migration
# of id:03a3, which this BLOCKS).
#
# `primary_lane()` anchors a bold-titled item's lane STRICTLY: the tag must sit immediately
# after the title's closing `**` (id:fb7f). That strictness is deliberate and must stay --
# it is what stops a lane token mentioned in PROSE deep in the body from setting the lane.
#
# `tools/ledger-shrink.py` plants its ` -- detail: `docs/ledger-notes/XXXX.md`` pointer in
# exactly that slot, pushing any lane tag that had been there one token to the right:
#
#     - [ ] **Some title** -- detail: `docs/ledger-notes/9999.md` [HARD] <!-- id:9999 -->
#
# Pre-fix that returned NOTHING, so a plainly pool-executable item dispositioned `surface`.
# Census over the live ledger: 19 open items changed lane once the pointer is skipped, 8 of
# them EXECUTABLE ([ROUTINE] x4, [HARD - pool] x3, [HARD] x1). Because classify-repo.sh
# folds `promote > 0` to `handoff` and `surface > 0 AND promote == 0` to `human`, the trim
# could silently convert pool-executable work into a human question -- the id:4b64
# silent-idle failure class arriving through a new door.
#
# SCOPE OF THE FIX, and the property it must NOT break: the pointer is a KNOWN, STRUCTURED
# token, so it is skipped EXACTLY. This is not "match a lane anywhere on the line".
# `classify-repo.sh` does take the first lane hit anywhere (id:4da4) and is IMMUNE to this
# bug; the two must NOT be made to agree by loosening this parser. Cases (9)-(11) below are
# the negative fixtures that pin it: a lane token in prose still sets NO lane.
#
# Hermetic: mktemp fixtures only; RELAY_DECISION_QUEUE and UNPROMOTED_SCAN_LOG are
# redirected into the scratch dir so neither ~/.config/relay nor ~/.claude is touched.
# No network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/relay/scripts/unpromoted-scan.sh"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"

fail=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

[[ -x "$SCAN" ]] || { echo "FAIL: sanity: unpromoted-scan.sh not executable at $SCAN"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
export RELAY_DECISION_QUEUE="$TMP/decision-queue.jsonl"
export UNPROMOTED_SCAN_LOG="$TMP/unpromoted-scan.log"
# Same hooks neutralization tests/run-tests.sh applies suite-wide, repeated here so the file
# is hermetic when run standalone: the developer's global hooks must never fire in a fixture.
mkdir -p "$TMP/nohooks"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"

R="$TMP/fixture"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e.st
git -C "$R" config user.name t
# Nothing twinned, so every open TODO item is un-promoted and gets a disposition.
printf '# Roadmap\n\n## Items\n' > "$R/ROADMAP.md"

# The `docs/ledger-notes/XXXX.md` path is the pointer's own shape; the notes need not exist
# for the parse. Both pointer spellings appear: this repo's shrinker emits the ASCII `--`,
# the reference implementation emits an em dash (data, not prose -- the ban does not reach
# a fixture that must match the legacy spelling).
cat > "$R/TODO.md" <<'EOF'
# TODO

## Current
- [ ] **Pool lane, bare, ASCII pointer** -- detail: `docs/ledger-notes/2001.md` [HARD] <!-- id:2001 -->
- [ ] **Pool lane, bare, em-dash pointer** — detail: `docs/ledger-notes/2002.md` [HARD] <!-- id:2002 -->
- [ ] **Pool lane, old vocab, hyphen delimiter** -- detail: `docs/ledger-notes/2003.md` [HARD - pool] <!-- id:2003 -->
- [ ] **Pool lane, old vocab, em-dash delimiter** -- detail: `docs/ledger-notes/2004.md` [HARD — pool] <!-- id:2004 -->
- [ ] **Executor lane after a pointer** -- detail: `docs/ledger-notes/2005.md` [ROUTINE] <!-- id:2005 -->
- [ ] **Author lane after a pointer** -- detail: `docs/ledger-notes/2006.md` [INPUT — author] <!-- id:2006 -->
- [ ] **Meeting lane, hyphen delimiter, after a pointer** -- detail: `docs/ledger-notes/2007.md` [INPUT - meeting] <!-- id:2007 -->
- [ ] **Compute lane after a pointer** -- detail: `docs/ledger-notes/2008.md` [MECHANICAL] <!-- id:2008 -->
- [ ] **Prose after a pointer merely mentions a lane** -- detail: `docs/ledger-notes/2009.md` an earlier [ROUTINE] plan was dropped here <!-- id:2009 -->
- [ ] **Pointer, then nothing at all** -- detail: `docs/ledger-notes/200a.md` <!-- id:200a -->
- [ ] **No pointer, lane only in prose** — supersedes an earlier [ROUTINE] plan <!-- id:200b -->
- [ ] **Lane BEFORE the pointer still works** [HARD] -- detail: `docs/ledger-notes/200c.md` <!-- id:200c -->
EOF
git -C "$R" add -A
git -C "$R" commit -qm init

out="$("$SCAN" "$R" 2>"$TMP/scan.err")"; rc=$?
[[ "$rc" -eq 0 ]] || bad "sanity: unpromoted-scan exited $rc (report-only must exit 0 with findings): $(cat "$TMP/scan.err")"
[[ -n "$out" ]] || bad "sanity: unpromoted-scan reported NOTHING for a fixture where nothing is twinned -- the cases below would all be vacuous"

expect() { # <id> <want-disposition> <label>
  local got
  got="$(grep -P "\t$1\t" <<<"$out" | cut -f3)"
  if [[ "$got" == "$2" ]]; then
    ok "$3 -> $2"
  else
    bad "$3 (id:$1) dispositioned '${got:-<no row>}', want '$2'"
  fi
}

echo "== POSITIVE: a lane tag that FOLLOWS the detail pointer still sets the lane =="
expect 2001 promote '(1) bare [HARD] after an ASCII pointer'
expect 2002 promote '(2) bare [HARD] after an em-dash pointer'
expect 2003 promote '(3) [HARD - pool] after an ASCII pointer'
expect 2004 promote '(4) [HARD — pool] after an ASCII pointer'
expect 2005 promote '(5) [ROUTINE] after an ASCII pointer'
expect 2006 laned   '(6) [INPUT — author] after an ASCII pointer'
expect 2007 laned   '(7) [INPUT - meeting] after an ASCII pointer'
expect 2008 laned   '(8) [MECHANICAL] after an ASCII pointer'

echo "== NEGATIVE: a lane token in PROSE must still NOT set the lane =="
expect 2009 surface '(9) prose after the pointer that merely MENTIONS [ROUTINE]'
expect 200a surface '(10) a pointer with no lane tag after it'
expect 200b surface '(11) an untrimmed item whose only lane token is mid-prose'

echo "== REGRESSION: the pre-existing anchor position is untouched =="
expect 200c promote '(12) a lane tag that sits BEFORE the pointer'

echo "== CROSS-READER: classify-repo.sh was already immune and must stay so (id:4da4) =="
# The two parsers deliberately DIFFER on prose (classify takes the first hit anywhere).
# What must hold is that the trimmed pool items are visible to the dispatch-side reader too,
# so a repo of trimmed pool work never reads as idle.
if [[ -x "$CLASSIFY" ]]; then
  cp "$R/TODO.md" "$R/ROADMAP.md"
  git -C "$R" add -A
  git -C "$R" commit -qm 'roadmap view' >/dev/null 2>&1
  gather="$ROOT/relay/scripts/gather-repo-state.sh"
  if [[ -x "$gather" ]]; then
    ohp="$("$gather" --repo fixture --path "$R" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["open_hard_pool"])' 2>/dev/null)"
    if [[ "$ohp" =~ ^[0-9]+$ ]] && [[ "$ohp" -ge 3 ]]; then
      ok "gather-repo-state still sees the trimmed pool items (open_hard_pool=$ohp)"
    else
      bad "the trimmed pool items are invisible to the pool-dispatch reader: open_hard_pool='$ohp' (want >= 3)"
    fi
  else
    ok "gather-repo-state.sh absent -- cross-reader check skipped"
  fi
else
  ok "classify-repo.sh absent -- cross-reader check skipped"
fi

echo
[[ "$fail" -eq 0 ]] && echo "test_unpromoted_lane_after_detail_pointer_3795: PASS" \
                    || echo "test_unpromoted_lane_after_detail_pointer_3795: FAIL"
exit "$fail"
