#!/usr/bin/env bash
# roadmap-tick.sh — tick the ROADMAP.md checkbox(es) for a set of worked item ids.
# Usage: roadmap-tick.sh <repo-root> <id1[,id2,...]>
#
# This is the DRIVER-SIDE tick (id:5b12, seam of id:ae08). Under the one-writer
# integrator model (meeting 2026-07-26-1922 D1), execute/hard children NO LONGER tick
# their own ROADMAP.md checkbox in their worktree — they return `worked_ids` and the
# serialized integrator ticks the box in the canonical checkout AFTER the merge. This
# removes the non-union `- [ ] → - [x]` collision that N parallel worktrees would
# otherwise contend on (id:dc5b C2), while keeping a single writer to main.
#
# Behaviour:
#   - For each id, find the FIRST open "- [ ] …" line whose OWN id is <id> and flip its
#     "[ ]" to "[x]". The own id is the LAST `<!-- id:XXXX -->` MARKER on the line.
#     ANCHORED-MARKER MATCH, never a bare-token search (cartulary 2026-08-14, routed:4a12).
#     The previous `index($0, "id:<id>")` containment test matched the id ANYWHERE, including
#     in PROSE — and the id:3801 auto hard-split writes "DECOMPOSED into seams id:AAAA,
#     id:BBBB" into the @container line. Combined with "FIRST open line", the container
#     (earlier in the file) beat its own seam every time: 4 mis-ticks in one day in cartulary
#     (b1f005f [a251]→55e6, 841245f [7b09]→6ed1, ace091e [b3f7]→9c14, 8039b10 [518a]→fc32),
#     leaving shipped work reading OPEN (so the pool re-dispatched it) and containers reading
#     DONE over open seams. This is define-vs-refer: `<!-- id:X -->` means "this line IS X",
#     prose `id:X` means "see X". Taking the LAST marker also makes a body that QUOTES another
#     item's marker non-matching (the id:cc7e first-vs-last lesson), so both are closed here.
#   - Idempotent: an id already ticked ("- [x] … id:<id>") or absent is a clean no-op.
#   - NEVER edits an item's Acceptance/Tests/Done-check/Context body — only the checkbox char.
#   - flock-guarded (shares nothing with archive); logs detail to ~/.claude/logs.
#   - Prints one short line: "roadmap-tick: ticked <ids>" (or "nothing to tick").
#
# The caller (the integrator) is responsible for `git add -- ROADMAP.md` + commit iff the
# file actually changed (scoped-staging invariant id:debf) — this script only edits the file.
set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel)}"
IDS_CSV="${2:-}"
ROADMAP_FILE="$REPO_ROOT/ROADMAP.md"
LOCK_FILE="$REPO_ROOT/.roadmap-tick.lock"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/roadmap-tick.log"

mkdir -p "$LOG_DIR"

if [[ -z "$IDS_CSV" ]]; then
    echo "roadmap-tick: no ids given — nothing to tick." >&2
    exit 0
fi
if [[ ! -f "$ROADMAP_FILE" ]]; then
    echo "roadmap-tick: $ROADMAP_FILE not found — skipping." >&2
    exit 0
fi

# flock-guard the whole read-modify-write (fd 9).
exec 9>"$LOCK_FILE"
if ! flock -n 9 2>/dev/null; then
    echo "roadmap-tick: another instance is running (lock $LOCK_FILE) — skipping." >&2
    exit 0
fi
trap 'rm -- "$LOCK_FILE"' EXIT

# Normalise the CSV into a newline id list (strip spaces + a stray leading "id:").
mapfile -t IDS < <(printf '%s' "$IDS_CSV" | tr ',' '\n' | sed -E 's/^[[:space:]]*(id:)?//; s/[[:space:]]*$//' | grep -E '^[0-9a-fA-F]{4}$' || true)
if [[ "${#IDS[@]}" -eq 0 ]]; then
    echo "roadmap-tick: no well-formed 4-hex ids in '$IDS_CSV' — nothing to tick." >&2
    exit 0
fi

TICKED=()
for id in "${IDS[@]}"; do
    # Only flip the FIRST open checkbox line carrying this id. awk edits in place via a temp.
    tmp=$(mktemp)
    if awk -v want="${id}" '
        # own_id(line): the LAST "<!-- id:XXXX -->" marker on the line, or "" if none.
        # Anchored on the marker, never a bare-token search — see the header note.
        function own_id(s,   last) {
            last = ""
            while (match(s, /<!-- id:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F] -->/)) {
                last = substr(s, RSTART + 8, 4)
                s = substr(s, RSTART + RLENGTH)
            }
            return last
        }
        BEGIN { done = 0; wl = tolower(want) }
        (!done && $0 ~ /^- \[ \]/ && tolower(own_id($0)) == wl) {
            sub(/^- \[ \]/, "- [x]")
            done = 1
        }
        { print }
        END { exit (done ? 0 : 1) }
    ' "$ROADMAP_FILE" > "$tmp"; then
        mv -- "$tmp" "$ROADMAP_FILE"
        TICKED+=("$id")
    else
        rm -- "$tmp"
        # Not found as an OPEN line: either already ticked, or not a ROADMAP checkbox id.
        printf '%s roadmap-tick: id:%s not an open ROADMAP checkbox in %s (already ticked or absent) — no-op\n' \
            "$(date -Iseconds)" "$id" "$ROADMAP_FILE" >> "$LOG_FILE"
    fi
done

if [[ "${#TICKED[@]}" -eq 0 ]]; then
    echo "roadmap-tick: nothing to tick (all ids already ticked or absent)."
    printf '%s roadmap-tick: nothing to tick for [%s] in %s\n' "$(date -Iseconds)" "$IDS_CSV" "$REPO_ROOT" >> "$LOG_FILE"
    exit 0
fi

echo "roadmap-tick: ticked ${TICKED[*]}"
printf '%s roadmap-tick: ticked [%s] in %s\n' "$(date -Iseconds)" "${TICKED[*]}" "$REPO_ROOT" >> "$LOG_FILE"
