#!/usr/bin/env bash
# classify.sh — mechanical per-project TODO pre-classifier
# Called by /meeting (no-arg) and /meeting-cross.
# Usage: classify.sh [project-root]   — defaults to git toplevel
# Output: TSV lines:  CLASS  ID  SUMMARY(≤80char)  NOTE-LINK  GATE
#   CLASS: C1 (link+Decisions), C2 (link-no-Decisions or keyword hint), C3 (no link),
#          RELAY (the relay ROADMAP mirror line — executor work, never
#          meeting-worthy; /meeting dispatch must skip it)
#   GATE:  GATED if body contains gate/condition/blocked vocabulary; empty otherwise
#          Advisory only — never reclassifies or skips; model judges satisfaction.
#   [HARD] floor (D4, meeting note 2026-06-15-0715-meeting-fables-interaction.md):
#          a TODO item tagged [HARD] needs a strong-model design session — it is
#          FLOORED to C3 (never C1/C2), so /meeting dispatch never proposes inline
#          impl on a weak/post-plan tier. The [HARD] tag stays visible in SUMMARY.

set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TODO="$ROOT/TODO.md"

[[ -f "$TODO" ]] || exit 0

while IFS= read -r line; do
    # Only unchecked items
    [[ "$line" =~ ^[[:space:]]*-\ \[\ \]  ]] || continue

    # Extract ID
    id=""
    if [[ "$line" =~ \<\!--\ id:([a-f0-9]+)\ --\> ]]; then
        id="id:${BASH_REMATCH[1]}"
    fi

    # Strip leading "- [ ] " and trailing ID comment for body text
    body=$(printf '%s' "$line" \
        | sed 's/^[[:space:]]*- \[ \] //' \
        | sed -E 's/ *<!-- (children|gated-on):[0-9a-f,]+ -->//g' \
        | sed 's/ *<!-- id:[a-f0-9]* -->//')
    summary=$(printf '%s' "$body" | cut -c1-80)

    # Relay mirror line (see ROADMAP.md template): executor work lives in
    # ROADMAP.md — classify as RELAY so dispatch never proposes a meeting on it.
    if printf '%s' "$body" | grep -qE '^Relay: [0-9]+ open ROADMAP items[[:space:]]*$'; then
        printf '%s\t%s\t%s\t%s\t%s\n' "RELAY" "$id" "$summary" "" ""
        continue
    fi

    # Find first meeting-note link in line
    note_link=$(printf '%s' "$line" \
        | grep -oE 'docs/meeting-notes/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-[^)> .,`]+\.md' \
        | head -1 || true)

    # Classify
    if [[ -n "$note_link" ]]; then
        if grep -q '^## Decisions' "$ROOT/$note_link" 2>/dev/null; then
            class="C1"
        else
            class="C2"
        fi
    else
        # Keyword hint: signals planning work
        if printf '%s' "$body" | grep -qiE '(design|investigate|decide|evaluate|plan|deferred|forward-flag)'; then
            class="C2"
        else
            class="C3"
        fi
    fi

    # Gate-text check (advisory): detect gate/condition/blocked vocabulary in body
    gate=""
    printf '%s' "$body" | grep -qiE 'gated?|gate:|reopen (gate|trigger)|condition-triggered|blocked on' \
        && gate="GATED" || true

    # [HARD] floor (D4): a [HARD]-tagged TODO item is strong-model design work — floor
    # to C3 regardless of link/keywords, so dispatch never proposes inline C1/C2 impl.
    if printf '%s' "$body" | grep -qE '\[HARD\]|\[HARD '; then
        class="C3"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$class" "$id" "$summary" "$note_link" "$gate"
done < "$TODO"
