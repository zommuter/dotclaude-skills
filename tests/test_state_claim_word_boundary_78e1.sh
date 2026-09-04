#!/usr/bin/env bash
# roadmap:78e1 — Word-boundary-anchor the lib-state-claim.sh terminal-word regex.
#
# Defect: STATE_CLAIM_TERMINAL_RE had no word boundaries, so direction (i) fired
# inside compound words. Live false positive: this repo's own ROADMAP prose
# "fail-CLOSED is the key property" (id:6b35) trips the terminal-word match and
# reports a spurious DECIDED-LEFT-OPEN, even though the item is a plain open item
# whose prose merely uses "CLOSED" as part of a compound word, not a self-assertion
# of closure. The same class fires on "disclosed"/"enclosed"/"undone".
#
# Fix: anchor each terminal word with a word boundary at the two `=~` sites of
# lib-state-claim.sh. A standalone terminal word must still fire; existing id:8913
# and id:5533 tests must stay green.
#
# LEDGER READS ARE UNION-ANCHORED (id:37ea, 2026-09-04). The ground-truth probe at the
# bottom reads the LEDGER + `docs/ledger-notes/` UNION, resolving the detail pointer off
# the item line, because id:6b35's prose now lives in its detail note. It also REFUSES to
# pass when the guarded lexeme is in neither place. Do not narrow it back to `ROADMAP.md`.
#
# Hermetic: no ~/.claude, no network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-state-claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LIB" ]] || fail "lib-state-claim.sh not found at $LIB"
bash -n "$LIB" || fail "lib-state-claim.sh fails bash -n"
source "$LIB"

# --- must NOT fire: the real defect class — a terminal word HYPHEN-JOINED into a
#     compound (a plain `\b`/`\<...\>` boundary does NOT catch this: a hyphen is a
#     non-word character, so bare word-boundary anchoring alone still fires here —
#     the fix must specifically treat a hyphen as part of the "no boundary" class).
l_failclosed='- [ ] fail-CLOSED is the key property here <!-- id:aaa1 -->'
v_failclosed="$(state_claim_violation "$l_failclosed")"
[[ -z "$v_failclosed" ]] || fail "'fail-CLOSED' (compound word) wrongly fired direction (i): '$v_failclosed'"
pass "'fail-CLOSED' compound word does not fire"

l_wellformed='- [ ] a well-DONE deal is not the same as done <!-- id:aaa5 -->'
v_wellformed="$(state_claim_violation "$l_wellformed")"
[[ -z "$v_wellformed" ]] || fail "'well-DONE' (compound word) wrongly fired direction (i): '$v_wellformed'"
pass "'well-DONE' compound word does not fire"

# --- lowercase compounds (disclosed/enclosed/undone): these never matched the
#     ALL-CAPS terminal-word list even pre-fix (case-sensitive `=~`), so they are
#     not a regression risk from this change — kept here as a documented sanity
#     check, not as reproductions of the reported defect class. ------------------
l_disclosed='- [ ] the finding was disclosed to the team <!-- id:aaa2 -->'
v_disclosed="$(state_claim_violation "$l_disclosed")"
[[ -z "$v_disclosed" ]] || fail "'disclosed' wrongly fired direction (i): '$v_disclosed'"
pass "'disclosed' does not fire (case-sensitive, unaffected by this fix)"

l_enclosed='- [ ] the file is enclosed in the archive <!-- id:aaa3 -->'
v_enclosed="$(state_claim_violation "$l_enclosed")"
[[ -z "$v_enclosed" ]] || fail "'enclosed' wrongly fired direction (i): '$v_enclosed'"
pass "'enclosed' does not fire (case-sensitive, unaffected by this fix)"

l_undone='- [ ] revert leaves the change undone <!-- id:aaa4 -->'
v_undone="$(state_claim_violation "$l_undone")"
[[ -z "$v_undone" ]] || fail "'undone' wrongly fired direction (i): '$v_undone'"
pass "'undone' does not fire (case-sensitive, unaffected by this fix)"

# --- ground-truth regression: id:6b35's actual ledger TEXT must not fire ---------
# RE-ANCHORED 2026-09-04 (id:37ea) to the LEDGER + NOTES UNION. This probe used to read
# `ROADMAP.md` alone. `tools/ledger-shrink.py` has since relocated id:6b35's body into
# `docs/ledger-notes/6b35.md`, so the bare item line no longer carries the `fail-closed`
# prose this regression exists to pin -- the assertion kept PASSING while testing nothing,
# which is the id:0b70 vacuous-check class and precisely the silent blindness id:9ce0 and
# id:1447 were filed against.
#
# The pointer path is READ OFF THE LINE, never hardcoded (the id:1608 shape that
# `meeting/orphan-scan.sh` uses): an item whose body was never relocated resolves to the
# line alone and behaves exactly as before.
#
# THE PROBE IS NOT ALLOWED TO GO QUIET AGAIN. The `fail-closed` lexeme must be found
# SOMEWHERE in the union, or this fails LOUDLY rather than reporting a pass for an item
# whose prose was deleted or reworded. A missing item line is still a non-fatal skip --
# that is a genuine "the item is gone" case, not a relocation.
b35_line="$(head -1 < <(grep -E '^- \[[ xX]\].*<!-- id:6b35 -->' "$ROOT/ROADMAP.md") )"
if [[ -n "$b35_line" ]]; then
  # `state_claim_violation` is a PER-ITEM-LINE predicate, so the union must be assembled
  # as ONE item line, not as a blob. Concatenating the WHOLE note is wrong and was measured
  # to be wrong: a note accumulates later sections whose prose legitimately says DECIDED /
  # RESOLVED / CLOSED about other things, and feeding those to a self-claim predicate makes
  # it fire. That is over-matching, the other half of the id:1447 hazard.
  #
  # The faithful reconstruction is exact rather than clever: `ledger-shrink.py` cuts ONE
  # item line into a slim head plus a residue, and writes that residue as the FIRST
  # non-blank line under the note's `## From <LEDGER>` heading. Head line + that line IS
  # the pre-shrink item line. Section headings are matched on the LOGICAL ledger name
  # (`## From ROADMAP`), the id:0d7c format, never on a physical path.
  b35_detail="$(head -1 < <(grep -oP 'detail:\s*`\K[^`]+' <<<"$b35_line") )"
  b35_text="$b35_line"
  if [[ -n "$b35_detail" && -f "$ROOT/$b35_detail" ]]; then
    b35_body="$(awk '/^## From ROADMAP[[:space:]]*$/{f=1;next} f && /^## /{exit} f && NF{print;exit}' \
                  "$ROOT/$b35_detail")"
    [[ -n "$b35_body" ]] && b35_text="$b35_line $b35_body"
  fi
  grep -qiF 'fail-closed' <<<"$b35_text" \
    || fail "id:6b35's 'fail-CLOSED' prose is absent from BOTH its ROADMAP.md line and the relocated body in ${b35_detail:-<no detail pointer>} -- this ground-truth probe would assert nothing; re-point it at prose that still exists"
  v_b35="$(state_claim_violation "$b35_text")"
  [[ "$v_b35" != *i* ]] || fail "id:6b35's own ledger text still fires direction (i): '$v_b35' -- text: $b35_text"
  pass "id:6b35's reassembled item line (ROADMAP head + relocated body, fail-CLOSED prose) does not fire direction (i)"
else
  pass "id:6b35 line not found in current ROADMAP.md (not fatal — inline fixture above already covers the class)"
fi

# --- must STILL fire: a standalone terminal word ---------------------------------
l_resolved='- [ ] foo — RESOLVED 2026-07-19 <!-- id:bbbb -->'
v_resolved="$(state_claim_violation "$l_resolved")"
[[ "$v_resolved" == *i* ]] || fail "standalone RESOLVED must still fire direction (i): '$v_resolved'"
pass "standalone 'RESOLVED' still fires"

l_closed='- [ ] foo is CLOSED now <!-- id:bbbc -->'
v_closed="$(state_claim_violation "$l_closed")"
[[ "$v_closed" == *i* ]] || fail "standalone CLOSED must still fire direction (i): '$v_closed'"
pass "standalone 'CLOSED' still fires"

l_superseded='- [ ] foo — SUPERSEDED by bar <!-- id:bbbd -->'
v_superseded="$(state_claim_violation "$l_superseded")"
[[ "$v_superseded" == *i* ]] || fail "standalone SUPERSEDED must still fire direction (i): '$v_superseded'"
pass "standalone 'SUPERSEDED' still fires"

l_done='- [ ] this task is DONE already <!-- id:bbbe -->'
v_done="$(state_claim_violation "$l_done")"
[[ "$v_done" == *i* ]] || fail "standalone DONE must still fire direction (i): '$v_done'"
pass "standalone 'DONE' still fires"

l_deferred='- [ ] item DEFERRED to next cycle <!-- id:bbbf -->'
v_deferred="$(state_claim_violation "$l_deferred")"
[[ "$v_deferred" == *i* ]] || fail "standalone DEFERRED must still fire direction (i): '$v_deferred'"
pass "standalone 'DEFERRED' still fires"

# --- direction (ii) comment-close path is unaffected (only direction-i regex site
#     is compound-word-sensitive prose text; comment bodies are still full matches) --
l_comment_close='- [ ] foo <!-- closed 2026-07-19 --> <!-- id:cccc -->'
v_ccl="$(state_claim_violation "$l_comment_close")"
[[ "$v_ccl" == *ii* ]] || fail "comment-only close must still fire direction (ii): '$v_ccl'"
pass "(ii) comment-only close still fires"

echo "ALL PASS: id:78e1 word-boundary anchoring on lib-state-claim.sh terminal-word regex"
