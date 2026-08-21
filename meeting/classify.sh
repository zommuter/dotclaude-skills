#!/usr/bin/env bash
# classify.sh — mechanical per-project TODO pre-classifier
# Called by /meeting (no-arg) and /meeting-cross.
# Usage: classify.sh [project-root]   — defaults to git toplevel
# Output: TSV lines:  CLASS  ID  SUMMARY(≤80char)  NOTE-LINK  GATE
#   CLASS: C1 (link+Decisions), C2 (link-no-Decisions or keyword hint), C3 (no link),
#          RELAY (the relay ROADMAP mirror line — executor work, never
#          meeting-worthy; /meeting dispatch must skip it),
#          POOL / EXEC / MECH / HANDS / HUMAN (a lane-tagged item whose lane is
#          apex-pool / executor / daemon / hands-or-author / human-decision — see the lane
#          floor below. NONE are meeting-worthy — /meeting dispatch must skip all five,
#          exactly like RELAY, and print them under its "not meeting-worthy" note. MECH in
#          particular must be SURFACED, never silently dropped: a [MECHANICAL] item is both
#          pool-inert and human-inert and its daemon is not built, so this printout is
#          currently the only place a human sees it).
#   GATE:  GATED if body contains gate/condition/blocked vocabulary; empty otherwise.
#          HARD-NOLANE if a lane-bracketed item declares no recognized lane (id:78ff:
#          untagged = LOUD reject — surface it, don't silently treat as meeting work).
#          May combine, e.g. "GATED;HARD-NOLANE". Advisory; model judges satisfaction.
#   Lane floor, LANE-AWARE (D4, meeting note 2026-06-15-0715-…; lane split id:78ff):
#          a [HARD]/[INPUT — …] item needs a strong tier or a human, but WHICH surface
#          depends on its lane tag. The shared vocabulary contract is
#          relay/references/hard-lanes.md — parsed identically by
#          relay/scripts/gather-human-backlog.sh and project_manager's scan.py (id:b466);
#          keep the three readers in sync. CANONICAL (capability-keyed, id:4f02) and
#          ACCEPTED (venue-keyed; dual-vocab window id:4f02/id:8111 still OPEN):
#            [INPUT — meeting]      → C3    (a design session — the meeting-worthy lane)
#            [INPUT — decision]     → HUMAN (human decides, NO meeting — id:1f1c)
#            [INPUT — access]       → HANDS (human-manual work — /meeting skips it)
#            [INPUT — author]       → HANDS (human-authored content, id:2b0b)
#            [HARD]  (bare)         → POOL  (apex pool work, `hard` verdict — skipped)
#            [ROUTINE]              → EXEC  (executor-tier work — skipped, id:4e3b;
#                                            ALWAYS, even with link+## Decisions)
#            [MECHANICAL]           → MECH  (daemon-run, no LLM — skipped but SURFACED)
#            [HARD — meeting]       → C3    (old, accepted)
#            [HARD — decision gate] → C3    (old, accepted; auto-gate alias id:3801)
#            [HARD — pool]          → POOL  (old, accepted)
#            [HARD — hands]         → HANDS (old, accepted)
#            unrecognized lane      → C3 + GATE=HARD-NOLANE (loud; id:78ff)
#          This stops POOL/HANDS/HUMAN items surfacing as meeting candidates (the
#          /meeting over-claim: a pool-executable item was floored to C3 and
#          recommended for a redundant design meeting). The tag stays in SUMMARY.

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
    if grep -qE '^Relay: [0-9]+ open ROADMAP items[[:space:]]*$' < <(printf '%s' "$body") ; then
        printf '%s\t%s\t%s\t%s\t%s\n' "RELAY" "$id" "$summary" "" ""
        continue
    fi

    # Find first meeting-note link in line
    note_link=$(head -1 < <(printf '%s' "$line" \
        | grep -oE 'docs/meeting-notes/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-[^)> .,`]+\.md') \
        || true)

    # Classify
    if [[ -n "$note_link" ]]; then
        if grep -q '^## Decisions' "$ROOT/$note_link" 2>/dev/null; then
            class="C1"
        else
            class="C2"
        fi
    else
        # Keyword hint: signals planning work
        if grep -qiE '(design|investigate|decide|evaluate|plan|deferred|forward-flag)' < <(printf '%s' "$body") ; then
            class="C2"
        else
            class="C3"
        fi
    fi

    # Gate-text check (advisory): detect gate/condition/blocked vocabulary in body
    gate=""
    grep -qiE '\bgated?\b|\bgate:|reopen (gate|trigger)|condition-triggered|blocked on' < <(printf '%s' "$body") \
        && gate="GATED" || true

    # Lane floor, LANE-AWARE (D4 + id:78ff): a [HARD]/[INPUT — …] item needs a strong
    # tier or a human, but its lane decides the SURFACE. Only the MEETING lane is
    # meeting-worthy; pool work is relay-executor work, hands/author work is
    # human-manual, and a decision lane is a human call with NO design session — all
    # three must be SKIPPED by /meeting (never proposed as a meeting/impl candidate).
    # An item carrying a lane bracket but NO recognized lane is surfaced LOUDLY
    # (HARD-NOLANE) rather than silently treated as a meeting. This override runs LAST
    # so it wins over the link/keyword class above.
    #
    # VOCABULARY — the shared contract is relay/references/hard-lanes.md, parsed
    # identically by relay/scripts/gather-human-backlog.sh and project_manager's
    # scan.py (id:b466). CANONICAL (new, capability-keyed, id:4f02) and ACCEPTED (old,
    # venue-keyed — the dual-vocab migration window id:4f02/id:8111 is still OPEN):
    #   [HARD]  (bare, no dash-lane)   → POOL   (renamed [HARD — pool])
    #   [INPUT — meeting]              → C3     (a design session)
    #   [INPUT — decision]             → HUMAN  (human decides, NO meeting — id:1f1c)
    #   [INPUT — access]               → HANDS
    #   [INPUT — author]               → HANDS  (human-expert-authored content, id:2b0b)
    #   [HARD — pool]                  → POOL   (old, accepted)
    #   [HARD — meeting]               → C3     (old, accepted)
    #   [HARD — decision gate]         → C3     (old, accepted; auto-gate alias id:3801)
    #   [HARD — hands]                 → HANDS  (old, accepted)
    #   🚧 route:meeting|decision-gate → C3     (auto-gate alias, id:3801)
    #   🚧 route:human / needs /relay human → HUMAN (id:1f1c)
    # Old dash-lane vocab is matched FIRST so a dash-lane tag always wins over the
    # bare-[HARD] new-vocab branch. Before this, the extractor only saw /\[HARD[^]]*\]/,
    # so bare [HARD] (the ratchet-MANDATED spelling — hooks/pre-commit-lane-vocab.sh
    # DENIES a newly added [HARD — pool]) fell to the default and every compliant pool
    # item read as C3 + HARD-NOLANE: surfaced as a redundant meeting candidate AND
    # permanently reported "needs a lane". The whole [INPUT — …] family was invisible.
    # (routed:f1e1, /relay human 2026-07-30.)
    #
    # ANCHORING (id:0d58/id:4da4): read the lane ONLY from the item's HEAD — the first 120
    # chars of the body. A real lane tag sits at the very start (before / inside / just after
    # the opening bold `**title**`); a `[HARD — pool]` cited in the PROSE of a long single-line
    # item is hundreds of chars deep (observed ≥327 in the live corpus) and must NOT count —
    # else an [INPUT — meeting] umbrella that merely discusses pool executors reads as POOL.
    # The lane word must sit INSIDE the bracket (not a bare title word like a
    # "MEETING:"-prefixed title), so route on the extracted tag, not a substring of the head.
    # Backtick-quoted prose is stripped FIRST (id:306d/id:1bbd) so a lane tag that exists
    # only inside backticks (e.g. a note "re-laned `[HARD — pool]`→`[ROUTINE]`") never
    # counts as this item's own lane.
    lead=$(printf '%s' "$body" | cut -c1-120 | sed -E 's/`[^`]*`//g')
    lane_tag=$(head -1 < <(printf '%s' "$lead" | grep -oE '\[(HARD|INPUT|ROUTINE|MECHANICAL)[^]]*\]') || true)
    # Normalize for matching: lowercase, collapse runs of whitespace.
    lane_norm=$(printf '%s' "$lane_tag" | tr 'A-Z' 'a-z' | tr -s '[:space:]' ' ')
    # Auto-gate route: aliases are annotations that may sit anywhere in the item body
    # (not just the head), matching gather-human-backlog.sh's whole-line scan.
    body_low=$(printf '%s' "$body" | sed -E 's/`[^`]*`//g' | tr 'A-Z' 'a-z')
    if [[ -n "$lane_norm" ]]; then
        case "$lane_norm" in
            # OLD vocab (venue-keyed) first — a dash-lane wins over bare [HARD].
            *pool*)             class="POOL" ;;
            *"decision gate"*)  class="C3" ;;
            *meeting*)          class="C3" ;;
            *hands*)            class="HANDS" ;;
            # NEW vocab (capability-keyed, id:4f02).
            *decision*)         class="HUMAN" ;;
            *access*|*author*)  class="HANDS" ;;
            "[hard]"|"[hard ]") class="POOL" ;;
            # id:4e3b (owner-ratified 2026-07-30) — the OTHER two capability lanes. Before
            # this they fell through the lane floor entirely into the link/keyword heuristic,
            # so every open executor/daemon-lane item was a pick-eligible /meeting candidate.
            # MEASURED on this repo, anchored (31 [ROUTINE] + 1 [MECHANICAL] = 32 items):
            # BEFORE 19 C3 + 11 C2 + 2 C1 → AFTER 31 EXEC + 1 MECH. That C3/C2 mass is a
            # FALSE signal, not a design need: C1/C2/C3 grades the DESIGN MATURITY of
            # meeting-lane work by whether a meeting-note link exists, so a perfectly
            # well-specified [ROUTINE] item lands in C3 purely for lacking a link, and a C2
            # is often just prose containing a planning verb ("evaluate"/"plan"). A lane tag
            # is a deliberate human capability claim and dominates an incidental link-absence.
            #
            # NB the anchoring below is load-bearing for these two lanes in particular: a
            # naive `grep -cE '^- \[ \].*\[ROUTINE\]'` over this repo returns 47, but 16 of
            # those are OTHER-lane items merely DISCUSSING [ROUTINE] in prose (id:4e3b's own
            # line is one). The anchored count is 31. Counting without the head-anchor
            # overstated this change by ~50% during its own design — the id:5648 trap.
            #
            # [ROUTINE] → EXEC, ALWAYS — including a link + ## Decisions section. Deliberately
            # NOT C1-eligible (Fable second-opinion, 2026-07-30): bare [HARD] with
            # link+Decisions is already POOL — skipped even when impl-ready — so making
            # [ROUTINE] C1-eligible would grant the CHEAPER-tier lane MORE meeting access than
            # the apex lane, inverting the capability logic ([ROUTINE] means a cheap executor
            # suffices, so the pool is its home a fortiori). It would also route the highest-
            # collision-probability items through SKILL.md step 4's C1 path, which does real
            # CODE work (full suite green) while /meeting's advisory claim sits on the DISTINCT
            # key `meeting:<repo>` precisely so a parallel executor is NEVER refused — a
            # non-blocking design justified by claim.sh's SCOPE INVARIANT "a meeting is
            # ledger-only" (id:0ee1/id:179e). Under single-id-two-views the same id can be
            # live in ROADMAP, so a pool executor could be working it concurrently.
            # Nothing is orphaned: unpromoted-scan.sh (id:2dea) surfaces open TODO items and
            # handoff C2 promotes them — /meeting was never how [ROUTINE] work reached an
            # executor. An explicit `/meeting <topic>` still reaches any item on demand.
            #
            # [MECHANICAL] → MECH, its own SURFACED class — NOT folded into POOL and never a
            # silent drop. A [MECHANICAL] item is pool-inert (the classifier verdict is never
            # dispatched) AND human-inert (gather-human-backlog.sh keeps it out of every
            # human-triage bucket), and its host daemon is "A3, gated — not built"
            # (hard-lanes.md §[MECHANICAL]). So /meeting's bucket printout is currently the
            # ONLY surface where a human sees these items; dropping them silently would
            # strand them nowhere-visible (the id:4347 no-silent-swallow anti-pattern).
            "[routine]"|"[routine ]")       class="EXEC" ;;
            "[mechanical]"|"[mechanical ]") class="MECH" ;;
            *)                  class="C3"; gate="${gate:+${gate};}HARD-NOLANE" ;;
        esac
    elif [[ "$body_low" == *"route:meeting"* || "$body_low" == *"route:decision-gate"* ]]; then
        class="C3"
    elif [[ "$body_low" == *"route:human"* || "$body_low" =~ needs[[:space:]]+/relay[[:space:]]+human ]]; then
        class="HUMAN"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$class" "$id" "$summary" "$note_link" "$gate"
done < "$TODO"
