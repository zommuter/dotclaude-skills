#!/usr/bin/env bash
# roadmap:4f0f
# fails-against-rev: 9d5048a62acbacbd3a918212341606a01dd25cae -- meeting/md-merge.py
# fails-against-assertion: (F) an item-scoped regex_sub must rewrite the matching text on the item's CONTINUATION lines
#
# RED SPEC -- authored 2026-09-05 (handoff C3, run relay-20260905-083048-18379), NOT
# implemented. EXPECTED-RED while ROADMAP id:4f0f is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY -- `update-ids` reaches only the single physical line carrying the id marker, but real
# ledger items wrap over 5-15 continuation lines and the stale prose is usually down there.
# Found 2026-09-04 (kienzler-solutions id:9f11: every wrong phrase sat on a continuation line,
# so the helper could reach none of them). The CLAUDE.md rule "shared non-union ledgers go
# through the flock'd helper, never Edit" therefore has no compliant path for the commonest
# edit there is.
#
# CONTRACT:
#   (1) `{"id":"XXXX","scope":"item","regex_sub":{…}}` applies the substitution to the item's
#       BLOCK -- the head line plus its continuation lines.
#   (2) The block is the one `tools/ledger-continuations.py:1334-1338` already defines: the
#       head line plus consecutive following lines that are non-blank and start with
#       whitespace. A blank line ends it; so does the next column-0 line. Two tools with two
#       answers for "where does this item end" is the id:4983 defect class.
#   (3) `scope` DEFAULTS to "line": every existing delta keeps its present meaning.
#   (4) The id:e166 constraint survives -- after the rewrite the head line still carries its
#       anchored <!-- id:XXXX --> marker terminally.
#   (5) Both degradation paths are LOUD, never a silent fall-back to line scope: `scope:item`
#       with an unsupported op, and an unrecognised `scope` value.
#
# The JSON key `scope` is the SPEC's choice, not the owner's -- see REVIEW_ME.md.
#
# TRIANGULATION / ORDER: (A) pins the default; (B)+(C) are the two loud refusals; (D)+(E) are
# the block boundaries a greedy implementation would overrun; (F) is the flagship. The order
# is load-bearing: this file uses the repo's accumulator idiom (several FAIL lines can fire),
# so the `# fails-against-assertion:` above names the LAST one, per CLAUDE.md section Testing.
#
# Hermetic: mktemp -d only. No git, no network, no ~/.claude writes.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDMERGE="$ROOT/meeting/md-merge.py"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$MDMERGE" ]] || { echo "FAIL: md-merge.py missing at $MDMERGE" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
F="$tmp/TODO.md"

# HEADMARK sits on the head line, on a post-blank indented line, and on the NEXT item's head
# line -- so a boundary overrun is visible. STALEWORD sits only on continuation lines: of the
# target item, and of the neighbouring item.
seed() {
  { printf '# TODO\n'
    printf -- '- [ ] **Wrapped item** with HEADMARK and a tail <!-- id:aaaa -->\n'
    printf -- '  first continuation carrying STALEWORD and more prose\n'
    printf -- '  second continuation, also STALEWORD, plus a tail clause\n'
    printf -- '\n'
    printf -- '  an indented line after a BLANK, carrying HEADMARK\n'
    printf -- '- [ ] **Next item** with HEADMARK outside the block <!-- id:bbbb -->\n'
    printf -- '  its own continuation with STALEWORD\n'
  } > "$F"
}

# run_delta <json> [extra args...] -> sets RC and ERR; never aborts the test.
RC=0; ERR=""
run_delta() {
  local json="$1"; shift
  set +e
  ERR="$(printf '%s' "$json" | python3 "$MDMERGE" update-ids --file "$F" "$@" 2>&1 >/dev/null)"
  RC=$?
  set -e
}

# nth_line <n> -> that line of the fixture
nth_line() { sed -n "${1}p" "$F"; }

# == (A) NO scope key ⇒ line-scoped, exactly as today ===================================
seed
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"HEADMARK","repl":"FRESHMARK"}}]}'
(( RC == 0 )) || note "(A) a scope-less regex_sub must keep working unchanged (id:f26d regression); stderr: ${ERR:-<empty>}"
grep -qF 'FRESHMARK' <<<"$(nth_line 2)" || note "(A) the scope-less regex_sub did not rewrite the head line"
grep -qF 'STALEWORD' <<<"$(nth_line 3)" || note "(A) a scope-less regex_sub must NOT reach continuation lines -- the default has to stay line-scoped or every existing caller's delta silently changes meaning"

# == (B) scope:item with an UNSUPPORTED op ⇒ LOUD refusal ===============================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","scope":"item","append":" -- a trailing note"}]}'
(( RC != 0 )) || note "(B) scope:item combined with an op this mode does not support was ACCEPTED -- an unsupported combination that quietly degrades to line scope is the silent-no-op class this helper keeps paying for (id:4347, id:3bd4)"
[[ "$(cat "$F")" == "$before" ]] || note "(B) a refused scope:item delta must write nothing"
grep -qF 'append' <<<"$ERR" || note "(B) the refusal must name the unsupported op on stderr; got: ${ERR:-<empty>}"

# == (C) an UNRECOGNISED scope value ⇒ LOUD refusal =====================================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","scope":"blokk","regex_sub":{"pattern":"HEADMARK","repl":"X"}}]}'
(( RC != 0 )) || note "(C) an unrecognised scope value was ACCEPTED -- a typo'd scope must never silently fall back to line scope, or a caller asking for a block rewrite gets a head-line rewrite and is told it succeeded"
[[ "$(cat "$F")" == "$before" ]] || note "(C) a delta with an unrecognised scope must write nothing"
grep -qF 'blokk' <<<"$ERR" || note "(C) the refusal must name the unrecognised scope value on stderr; got: ${ERR:-<empty>}"

# == (D) the block stops at a BLANK line ================================================
seed
run_delta '{"updates":[{"id":"aaaa","scope":"item","regex_sub":{"pattern":"HEADMARK","repl":"FRESHMARK"}}]}'
grep -qF 'HEADMARK' <<<"$(nth_line 6)" || note "(D) the item block must END at the blank line -- the post-blank indented line was rewritten, so the block scan ran past its boundary (tools/ledger-continuations.py:1334-1338 is the definition to reuse)"

# == (E) the block stops at the next COLUMN-0 line ======================================
grep -qF 'HEADMARK' <<<"$(nth_line 7)" || note "(E) the item block must END before the next column-0 item -- the neighbouring item id:bbbb was rewritten by a delta addressed to id:aaaa, which is a cross-item write on a shared non-union ledger"

# == (F) FLAGSHIP: the continuation lines are reachable ================================
seed
run_delta '{"updates":[{"id":"aaaa","scope":"item","regex_sub":{"pattern":"STALEWORD","repl":"FRESHWORD"}}]}'
(( RC == 0 )) || note "(F) an item-scoped regex_sub over a block that DOES match must succeed; stderr: ${ERR:-<empty>}"
grep -qE '^- \[ \] .*<!-- id:aaaa -->$' <<<"$(nth_line 2)" || note "(F) after an item-scoped rewrite the head line must still carry its anchored id marker TERMINALLY (id:e166) -- otherwise the item stops being addressable by the helper that just edited it"
grep -qF 'STALEWORD' <<<"$(nth_line 8)" || note "(F) the item-scoped rewrite leaked into the NEIGHBOUR item's continuation line -- the block must not extend past the next column-0 line"
{ grep -qF 'FRESHWORD' <<<"$(nth_line 3)" && grep -qF 'FRESHWORD' <<<"$(nth_line 4)"; } \
  || note "(F) an item-scoped regex_sub must rewrite the matching text on the item's CONTINUATION lines -- reaching only the id-bearing head line is the whole defect: real ledger items wrap, and the stale prose lives in the continuation"

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:4f0f not built yet" >&2; exit 1; }
echo "ALL PASS: md-merge update-ids supports an item-scoped block rewrite (id:4f0f)"
