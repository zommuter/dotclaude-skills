#!/usr/bin/env bash
# classify.sh — mechanical per-project TODO pre-classifier
# Called by /meeting (no-arg) and /meeting-cross.
# Usage: classify.sh [project-root]   — defaults to git toplevel
# Output: TSV lines:  CLASS  ID  SUMMARY(≤80char)  NOTE-LINK  GATE
#   CLASS: C1 (link+Decisions), C2 (link-no-Decisions or keyword hint), C3 (no link),
#          RELAY (the relay ROADMAP mirror line — executor work, never
#          meeting-worthy; /meeting dispatch must skip it),
#          POOL / HANDS (a [HARD] item whose lane is pool / hands — see [HARD] floor
#          below; executor / human-manual work, NOT meeting-worthy — /meeting dispatch
#          must skip both, exactly like RELAY).
#   GATE:  GATED if body contains gate/condition/blocked vocabulary; empty otherwise.
#          HARD-NOLANE if a [HARD] item declares no recognized lane (id:78ff: untagged
#          [HARD] = LOUD reject — surface it, don't silently treat as meeting work).
#          May combine, e.g. "GATED;HARD-NOLANE". Advisory; model judges satisfaction.
#   [HARD] floor, LANE-AWARE (D4, meeting note 2026-06-15-0715-…; lane split id:78ff):
#          a [HARD] item needs a strong tier, but WHICH surface depends on its lane
#          tag `[HARD — pool|meeting|hands]`:
#            [HARD — meeting] → C3   (a design session — the ONLY meeting-worthy lane)
#            [HARD — pool]    → POOL  (relay-executor work — /meeting skips it)
#            [HARD — hands]   → HANDS (human-manual work — /meeting skips it)
#            [HARD] (no lane) → C3 + GATE=HARD-NOLANE (loud; needs a lane, id:78ff)
#          This stops [HARD — pool]/[HARD — hands] items surfacing as meeting
#          candidates (the /meeting over-claim: a pool-executable item was floored to
#          C3 and recommended for a redundant design meeting). The tag stays in SUMMARY.

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

    # [HARD] floor, LANE-AWARE (D4 + id:78ff): a [HARD] item is strong-tier work, but
    # its lane decides the SURFACE. Only [HARD — meeting] is meeting-worthy; [HARD — pool]
    # is relay-executor work and [HARD — hands] is human-manual work — both must be SKIPPED
    # by /meeting (never proposed as a meeting/impl candidate). A bare [HARD] with no
    # recognized lane is surfaced LOUDLY (HARD-NOLANE) rather than silently treated as a
    # meeting. This override runs LAST so it wins over the link/keyword class above.
    #
    # ANCHORING (id:0d58/id:4da4): read the lane ONLY from the item's HEAD — the first 120
    # chars of the body. A real lane tag sits at the very start (before / inside / just after
    # the opening bold `**title**`); a `[HARD — pool]` cited in the PROSE of a long single-line
    # item is hundreds of chars deep (observed ≥327 in the live corpus) and must NOT count —
    # else an [INPUT — meeting] umbrella that merely discusses pool executors reads as POOL.
    # The lane word must sit INSIDE the `[HARD …]` bracket (not a bare title word like a
    # "MEETING:"-prefixed title), so route on the extracted tag, not a substring of the head.
    lead=$(printf '%s' "$body" | cut -c1-120)
    hard_tag=$(printf '%s' "$lead" | grep -oE '\[HARD[^]]*\]' | head -1 || true)
    if [[ -n "$hard_tag" ]]; then
        case "$hard_tag" in
            *[Pp]ool*)    class="POOL" ;;
            *[Hh]ands*)   class="HANDS" ;;
            *[Mm]eeting*) class="C3" ;;
            *)            class="C3"; gate="${gate:+${gate};}HARD-NOLANE" ;;
        esac
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$class" "$id" "$summary" "$note_link" "$gate"
done < "$TODO"
