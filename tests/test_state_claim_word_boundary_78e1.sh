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

# --- ground-truth regression: id:6b35's actual ROADMAP line must not fire -------
b35_line="$(grep -F 'id:6b35' "$ROOT/ROADMAP.md" | head -1)"
if [[ -n "$b35_line" ]]; then
  v_b35="$(state_claim_violation "$b35_line")"
  [[ "$v_b35" != *i* ]] || fail "id:6b35's own ROADMAP line still fires direction (i): '$v_b35' — line: $b35_line"
  pass "id:6b35's own ROADMAP line (fail-CLOSED prose) does not fire direction (i)"
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
