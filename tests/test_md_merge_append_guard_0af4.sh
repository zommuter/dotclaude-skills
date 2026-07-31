#!/usr/bin/env bash
# roadmap:0af4
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:0af4 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY (INBOUND routed:c27e from loderite) — a MATCHED id with a malformed payload is a
# silent destructive write. `update_ids()` (meeting/md-merge.py:140-147) replaces the whole
# matched line with whatever `line` the caller passed, unconditionally. A caller that meant
# "append this text to the item" passed a partial line and WIPED a 1400-char TODO item down
# to the fragment — exit 0, reported success. Recovered only because the tree happened to be
# committed. id:1b1a fixed the sibling half (an UNMATCHED id used to fail-open into a
# duplicate append; it now fails loud, :150-159). This is the remaining half.
#
# CONTRACT (both deliverables, one change):
#   (1) REFUSE a replacement that cannot be the item's own line — missing the anchored
#       `<!-- id:XXXX -->` marker, or missing the leading `- [ ]`/`- [x]` when the TARGET
#       line has one. Non-zero, name the id AND what was wrong, write NOTHING.
#   (2) An APPEND mode — {"id":"XXXX","append":"<text>"} — that appends to the EXISTING line
#       preserving every byte of it. Without it, (1) merely leaves the wiping caller stuck.
#
# TRIANGULATION: (A)+(B) are the two malformed shapes; (C)+(D)+(E) are the no-regression
# cases a blanket "refuse everything" would break; (F) is the conditional nature of the
# checkbox rule (a `## [LANE] Title <!-- id -->` heading-as-item is a legal non-checkbox
# target); (G)+(H) pin the append mode's preservation property.
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

# A long item, so a truncating write is unmistakable — this mirrors the 1400-char wipe.
LONG="- [ ] **The long item** — $(printf 'evidence %s; ' {1..80})and the wanted fix <!-- id:aaaa -->"

seed() {
  { printf '# TODO\n'
    printf '%s\n' "$LONG"
    printf -- '- [x] a closed sibling <!-- id:bbbb -->\n'
    printf '## [ROUTINE] A heading-as-item <!-- id:cccc -->\n'
  } > "$F"
}

# run_delta <json> [extra args…] -> sets RC and ERR; never aborts the test.
RC=0; ERR=""
run_delta() {
  local json="$1"; shift
  set +e
  ERR="$(printf '%s' "$json" | python3 "$MDMERGE" update-ids --file "$F" "$@" 2>&1 >/dev/null)"
  RC=$?
  set -e
}

# ══ (A) replacement missing the item's own <!-- id:XXXX --> marker ⇒ REFUSED ═══════════
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","line":"- [ ] a replacement with no id marker at all"}]}'
(( RC != 0 )) \
  || note "(A) a replacement lacking the item's anchored <!-- id:aaaa --> marker was ACCEPTED (exit 0) — the resulting line is no longer findable by its own token, so the next update-ids call cannot match it and the item is effectively orphaned"
[[ "$(cat "$F")" == "$before" ]] \
  || note "(A) a REFUSED update must write NOTHING — the file changed"
grep -q 'aaaa' <<<"$ERR" || note "(A) the refusal must name the offending id (aaaa) on stderr; got: ${ERR:-<empty>}"

# ══ (B) THE INCIDENT: a partial-line payload against a checkbox target ⇒ REFUSED ═══════
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"aaaa","line":"APPEND: one more sentence <!-- id:aaaa -->"}]}'
(( RC != 0 )) \
  || note "(B) a replacement with NO leading '- [ ]'/'- [x]' against a CHECKBOX target was accepted — this is the exact payload that wiped a 1400-char item and still exited 0"
after="$(cat "$F")"
[[ "$after" == "$before" ]] \
  || note "(B) the malformed replacement was WRITTEN. File now: $(grep -c . <<<"$after") lines; the target line is $(grep -o 'id:aaaa' <<<"$after" | wc -l)x present"
grep -qF -- "$LONG" "$F" \
  || note "(B) the original 1400-char-class item is GONE from the file — a silent destructive write at exit 0 is the defect this item exists to close"

# ══ (C) a well-formed replacement still applies, in place ═════════════════════════════
seed
run_delta '{"updates":[{"id":"aaaa","line":"- [x] **The long item** — now done <!-- id:aaaa -->"}]}'
(( RC == 0 )) || note "(C) a WELL-FORMED replacement must still succeed (regression); stderr: $ERR"
grep -q '^- \[x\] \*\*The long item\*\* — now done <!-- id:aaaa -->$' "$F" \
  || note "(C) the well-formed replacement did not apply in place"
[[ "$(sed -n '2p' "$F")" == "- [x] **The long item** — now done <!-- id:aaaa -->" ]] \
  || note "(C) position was not preserved — the replacement must stay on the target's own line"

# ══ (D) --allow-new append of a genuinely new well-formed item still works ════════════
seed
run_delta '{"updates":[{"id":"dddd","line":"- [ ] genuinely new item <!-- id:dddd -->"}]}' --allow-new
(( RC == 0 )) || note "(D) --allow-new must still append a genuinely new well-formed item (id:1b1a/14d0 regression); stderr: $ERR"
grep -q '<!-- id:dddd -->' "$F" || note "(D) --allow-new did not append the new item"

# ══ (E) the id:1b1a fail-loud on an UNMATCHED id is unchanged ═════════════════════════
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"9f9f","line":"- [ ] typo target <!-- id:9f9f -->"}]}'
(( RC != 0 )) || note "(E) an unmatched id must still fail LOUD without --allow-new (id:1b1a regression)"
[[ "$(cat "$F")" == "$before" ]] || note "(E) a failed unmatched-id update must still write nothing"

# ══ (F) the checkbox rule is CONDITIONAL on the target's shape ════════════════════════
# A `## [LANE] Title <!-- id -->` heading-as-item is a legal TODO.md item form. Replacing it
# with another heading must be allowed — an unconditional "must start with - [ ]" rule would
# break the ledger grammar this repo actually uses.
seed
run_delta '{"updates":[{"id":"cccc","line":"## [ROUTINE] A renamed heading-as-item <!-- id:cccc -->"}]}'
(( RC == 0 )) \
  || note "(F) replacing a NON-checkbox heading-as-item with another heading must be ALLOWED — the checkbox requirement is conditional on the TARGET line's shape, not absolute; stderr: $ERR"
grep -q '^## \[ROUTINE\] A renamed heading-as-item <!-- id:cccc -->$' "$F" \
  || note "(F) the heading-as-item replacement did not apply"

# ══ (G) APPEND mode preserves every byte of the original line ═════════════════════════
seed
run_delta '{"updates":[{"id":"aaaa","append":" — AMENDED 2026-07-29: one more clause."}]}'
(( RC == 0 )) \
  || note "(G) an APPEND mode must exist — {\"id\":…,\"append\":…} — or the refusal in (A)/(B) leaves the caller with no correct way to add text to an item; stderr: ${ERR:-<empty>}"
line="$(grep -F 'id:aaaa' "$F" || true)"
grep -qF 'AMENDED 2026-07-29: one more clause.' <<<"$line" \
  || note "(G) the appended text is absent from the item line; got: ${line:0:120}…"
grep -qF 'and the wanted fix' <<<"$line" \
  || note "(G) APPEND destroyed part of the original line — it must preserve every byte of it"
grep -qE '^- \[ \] ' <<<"$line" \
  || note "(G) APPEND must preserve the leading checkbox"
grep -qE '<!--[[:space:]]*id:aaaa[[:space:]]*-->' <<<"$line" \
  || note "(G) after APPEND the line must still carry its anchored own-id marker (otherwise the next update-ids cannot find it)"

# ══ (H) APPEND touches only its target; the file is otherwise byte-identical ══════════
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"bbbb","append":" (note)"}]}'
if (( RC == 0 )); then
  changed="$(diff <(printf '%s\n' "$before") "$F" | grep -c '^[<>]' || true)"
  (( changed == 2 )) \
    || note "(H) APPEND must change exactly ONE line (got $changed diff sides) — a line-scoped write is the whole point of this helper on a shared, non-union ledger"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:0af4 not built yet" >&2; exit 1; }
echo "ALL PASS: md-merge update-ids refuses malformed replacements and supports append (id:0af4)"
