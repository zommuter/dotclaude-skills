#!/usr/bin/env bash
# roadmap:3bd4
# fails-against-rev: 9d5048a62acbacbd3a918212341606a01dd25cae -- meeting/md-merge.py
# fails-against-assertion: (I) the refusal must name the MISSING pattern
#
# RED SPEC -- authored 2026-09-05 (handoff C3, run relay-20260905-083048-18379), NOT
# implemented. EXPECTED-RED while ROADMAP id:3bd4 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY -- `md-merge.py update-ids` is a SILENT NO-OP when an op's id IS found but the op
# changes nothing. The unmatched guard (meeting/md-merge.py:494) computes
# `regex_sub_ids - found`, so it only fires for an id that is not in the file AT ALL; a found
# id whose pattern misses writes the file back unchanged and exits 0. Measured against the
# rev named above: a missing pattern, an empty `append` and a whitespace-only `append` all
# exit 0 with the file untouched. Found live 2026-09-04 (kienzler-solutions id:9f11), where a
# caller believed the ledger had been updated for a full turn. Same class as the
# no-silent-swallow ban (id:4347) and the sibling append defect (id:e166).
#
# CONTRACT:
#   (1) A `regex_sub` whose id IS found but whose pattern does not match the line is a LOUD
#       failure: non-zero exit, NOTHING written, and BOTH the id and the offending pattern
#       named on stderr.
#   (2) An `append` whose payload resolves to appending nothing (empty or whitespace-only)
#       fails the same way, naming the id.
#   (3) The tracking is PER OP, not a whole-line before/after comparison. Since id:5d7e the
#       ops for one id are FOLDED, so a delta whose first op hits and whose second misses
#       leaves the line changed overall -- a whole-line comparison reports success while half
#       the caller's intent was dropped.
#   (4) A DELIBERATE no-op opts in explicitly (`--allow-noop`) instead of being the default.
#
# TRIANGULATION / ORDER: (A)-(D) are the no-regression cases a blanket "refuse anything that
# changes nothing" would break; (E)-(F) are the two `append` no-op shapes; (G) is the opt-in
# escape hatch; (H)-(I) are the flagship `regex_sub` cases, (I) being the fold that forbids
# the whole-line-comparison shortcut. The order is load-bearing: this file uses the repo's
# accumulator idiom (several FAIL lines can fire), so the `# fails-against-assertion:` above
# names the LAST one, per CLAUDE.md section Testing.
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

ITEM='- [ ] **An item** with stale prose here and a tail clause <!-- id:aaaa -->'

seed() {
  { printf '# TODO\n'
    printf '%s\n' "$ITEM"
    printf -- '- [x] a closed sibling <!-- id:bbbb -->\n'
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

# == (A) a regex_sub that DOES match still applies, in place, exit 0 ====================
seed
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"stale prose","repl":"fresh prose"}}]}'
(( RC == 0 )) || note "(A) a HITTING regex_sub must still succeed (id:f26d regression); stderr: ${ERR:-<empty>}"
grep -qF 'fresh prose' "$F" || note "(A) a hitting regex_sub did not apply"
grep -qE '^- \[ \] .*<!-- id:aaaa -->$' "$F" || note "(A) the hitting regex_sub broke the line's shape or its terminal id marker"

# == (B) an append with real text still applies, byte-preserving, exit 0 ================
seed
run_delta '{"updates":[{"id":"aaaa","append":"-- AMENDED 2026-09-05."}]}'
(( RC == 0 )) || note "(B) a REAL append must still succeed (id:0af4 regression); stderr: ${ERR:-<empty>}"
line="$(grep -F 'id:aaaa' "$F" || true)"
grep -qF 'AMENDED 2026-09-05.' <<<"$line" || note "(B) the appended text is absent; got: ${line:0:120}"
grep -qF 'and a tail clause' <<<"$line" || note "(B) the append destroyed part of the original line"

# == (C) the id:f26d unmatched-id refusal is unchanged ==================================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"9f9f","regex_sub":{"pattern":"anything","repl":"x"}}]}'
(( RC != 0 )) || note "(C) a regex_sub naming an id that is NOT in the file must still fail LOUD (id:f26d regression)"
[[ "$(cat "$F")" == "$before" ]] || note "(C) a refused unmatched-id delta must still write nothing"

# == (D) --allow-new still appends a genuinely new item =================================
seed
run_delta '{"updates":[{"id":"dddd","line":"- [ ] genuinely new item <!-- id:dddd -->"}]}' --allow-new
(( RC == 0 )) || note "(D) --allow-new must still append a genuinely new well-formed item (id:1b1a/14d0 regression); stderr: ${ERR:-<empty>}"
grep -q '<!-- id:dddd -->' "$F" || note "(D) --allow-new did not append the new item"

# == (E) an EMPTY append is a silent no-op today; it must fail LOUD =====================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","append":""}]}'
(( RC != 0 )) || note "(E) an append whose payload appends NOTHING was accepted at exit 0 -- _append_to_line strips the payload and rebuilds the original line, so the caller is told its edit landed when nothing was written"
[[ "$(cat "$F")" == "$before" ]] || note "(E) the empty append must leave the file untouched"
grep -q 'aaaa' <<<"$ERR" || note "(E) the refusal must name the offending id (aaaa) on stderr; got: ${ERR:-<empty>}"

# == (F) a WHITESPACE-ONLY append is the same shape =====================================
seed
run_delta '{"updates":[{"id":"aaaa","append":"   "}]}'
(( RC != 0 )) || note "(F) a whitespace-only append is the same no-op as (E) -- the strip() makes them identical -- and must fail the same way"
grep -q 'aaaa' <<<"$ERR" || note "(F) the whitespace-only refusal must name the offending id on stderr; got: ${ERR:-<empty>}"

# == (G) a DELIBERATE no-op opts in explicitly ==========================================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"NOT_PRESENT_ANYWHERE","repl":"x"}}]}' --allow-noop
(( RC == 0 )) || note "(G) --allow-noop must make a deliberate no-op ACCEPTABLE -- without an opt-in, the guard in (H) leaves an idempotent caller no correct way to re-run its own delta; stderr: ${ERR:-<empty>}"
[[ "$(cat "$F")" == "$before" ]] || note "(G) an opted-in no-op must still write nothing"

# == (H) FLAGSHIP: id found, pattern misses ⇒ LOUD, names id AND pattern ================
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"NOT_PRESENT_ANYWHERE","repl":"x"}}]}'
(( RC != 0 )) || note "(H) a regex_sub whose id IS found but whose pattern does not match exited 0 -- md-merge.py:494 computes regex_sub_ids minus found, so the guard only ever fires for an id that is absent entirely, and this delta writes the file back unchanged while reporting success"
[[ "$(cat "$F")" == "$before" ]] || note "(H) a refused no-op regex_sub must write nothing"
grep -q 'aaaa' <<<"$ERR" || note "(H) the refusal must name the offending id (aaaa) on stderr; got: ${ERR:-<empty>}"
grep -qF 'NOT_PRESENT_ANYWHERE' <<<"$ERR" || note "(H) the refusal must quote the offending PATTERN on stderr -- the id alone does not tell a caller with several ops which one missed; got: ${ERR:-<empty>}"

# == (I) FLAGSHIP FOLD: one op hits, one misses ⇒ still LOUD, still writes nothing ======
# Forbids the whole-line before/after shortcut: the folded line HAS changed here.
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"stale prose","repl":"fresh prose"}},{"id":"aaaa","regex_sub":{"pattern":"MISSING_SECOND_PATTERN","repl":"y"}}]}'
(( RC != 0 )) || note "(I) a FOLDED delta whose first regex_sub hits and whose second misses exited 0 -- the composed line changed overall, so a whole-line before/after comparison cannot see the dropped op; the tracking has to be PER OP (the id:5d7e shape)"
[[ "$(cat "$F")" == "$before" ]] || note "(I) a refused fold must write NOTHING -- a partially-applied delta is exactly the half-updated ledger this item exists to prevent"
grep -qF 'MISSING_SECOND_PATTERN' <<<"$ERR" || note "(I) the refusal must name the MISSING pattern, not merely the id -- with several ops on one id the id alone cannot say which was dropped; got: ${ERR:-<empty>}"

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:3bd4 not built yet" >&2; exit 1; }
echo "ALL PASS: md-merge update-ids fails loud on a found-id no-op (id:3bd4)"
