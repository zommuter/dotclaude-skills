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
#   - TODO.md TWIN (single-id-two-views): whenever the id's ROADMAP line reads "[x]" after
#     this pass (flipped now OR already ticked), the SAME id's open TODO.md checkbox is
#     ticked too, so the two ledgers cannot disagree. This is the MECHANICAL owner of that
#     invariant: before it, contract-v12 moved the execute child's tick into the driver but
#     left "tick the TODO twin too" as prose in ONE LLM prompt (relay-loop.js's review
#     child), which `--exclude review` can disable — so every mechanical integrate silently
#     drifted another pair (live: id:e68f/bc2b/b018/4a76 all TODO:[ ] ROADMAP:[x]).
#     * A MISSING twin is NORMAL (a ROADMAP-only item such as id:087b) — clean no-op.
#     * An id absent from ROADMAP entirely NEVER ticks a TODO line: the ROADMAP is what
#       authorises the close, so a TODO-only id is left strictly alone.
#     * The write goes through the flock'd `meeting/md-merge.py update-ids` (NEVER a
#       hand-rolled sed/awk on a shared non-union ledger), as an in-lock `regex_sub` —
#       TOCTOU-free, and preferred over `--append`, whose multi-line payloads move the id
#       marker off the checkbox line and break run-tests.sh's item_open() (id:e166).
#     * Anchored on the id MARKER, same own_id() rule as the ROADMAP side — a bare-token
#       grep hits prose mentions of other items (id:c97c).
#     * LOUD on a real failure: if a twin EXISTS but the write or the post-write assertion
#       fails, this exits non-zero. Silence is the defect being fixed.
#   - NEVER edits an item's Acceptance/Tests/Done-check/Context body — only the checkbox char.
#   - flock-guarded (shares nothing with archive); logs detail to ~/.claude/logs.
#   - Prints one short line: "roadmap-tick: ticked <ids>" (or "nothing to tick").
#
# This script performs NO git mutation — it only EDITS files. The caller (the integrator)
# is responsible for `git add -- ROADMAP.md TODO.md` + commit iff a file actually changed
# (scoped-staging invariant id:debf — scoped paths only, never `-A`/`.`/`-u`). BOTH ledgers
# must be staged: the twin write below dirties TODO.md too, and staging ROADMAP.md alone
# stranded TODO.md uncommitted in the canonical checkout until the repo wedged (id:e82e).
set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel)}"
IDS_CSV="${2:-}"
ROADMAP_FILE="$REPO_ROOT/ROADMAP.md"
TODO_FILE="$REPO_ROOT/TODO.md"
LOCK_FILE="$REPO_ROOT/.roadmap-tick.lock"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/roadmap-tick.log"

# meeting/md-merge.py, resolved from this script's CANONICAL location (readlink -f, so the
# ~/.claude/skills/relay/scripts symlink install resolves back into the repo). Falls back to
# the installed skill path.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MD_MERGE="$SCRIPT_DIR/../../meeting/md-merge.py"
[[ -f "$MD_MERGE" ]] || MD_MERGE="$HOME/.claude/skills/meeting/md-merge.py"

# own_id(line): the LAST "<!-- id:XXXX -->" MARKER on the line, or "" if none.
# Shared verbatim by the ROADMAP tick and the TODO-twin probe so the two ledgers are
# addressed by exactly the same rule. Anchored on the marker, never a bare-token search:
# `<!-- id:X -->` means "this line IS X", prose `id:X` means "see X" (routed:4a12, id:c97c);
# taking the LAST marker also makes a body that QUOTES another item's marker non-matching
# (the id:cc7e first-vs-last lesson).
OWN_ID_AWK='
    function own_id(s,   last) {
        last = ""
        while (match(s, /<!-- id:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F] -->/)) {
            last = substr(s, RSTART + 8, 4)
            s = substr(s, RSTART + RLENGTH)
        }
        return last
    }
'

# has_own_line <file> <id> <open|done> — exit 0 iff <file> has a line whose OWN id is <id>
# and which STARTS with an open ("- [ ]") resp. ticked ("- [x]"/"- [X]") checkbox.
# The checkbox is matched by literal prefix, not a passed-in regex: awk's -v processes
# escape sequences, so a `^- \[ \]` argument silently degrades into a character class.
has_own_line() {
    [[ -f "$1" ]] || return 1
    awk -v want="$2" -v mode="$3" "$OWN_ID_AWK"'
        function is_box(s) {
            if (mode == "open") return (substr(s, 1, 5) == "- [ ]")
            return (substr(s, 1, 5) == "- [x]" || substr(s, 1, 5) == "- [X]")
        }
        BEGIN { wl = tolower(want); found = 0 }
        (is_box($0) && tolower(own_id($0)) == wl) { found = 1 }
        END { exit (found ? 0 : 1) }
    ' "$1"
}

# tick_todo_twin <id> — converge the id's TODO.md checkbox with its (now ticked) ROADMAP
# one. No twin ⇒ clean no-op; a twin that fails to write ⇒ LOUD exit 1.
tick_todo_twin() {
    local id="$1"
    if ! has_own_line "$TODO_FILE" "$id" open; then
        printf '%s roadmap-tick: id:%s has no OPEN TODO.md twin in %s (absent or already ticked) — no-op\n' \
            "$(date -Iseconds)" "$id" "$TODO_FILE" >> "$LOG_FILE"
        return 0
    fi
    if [[ ! -f "$MD_MERGE" ]]; then
        echo "roadmap-tick: FATAL: id:$id has an open TODO.md twin but md-merge.py is missing ($MD_MERGE) — refusing to hand-roll a write to a shared ledger." >&2
        exit 1
    fi
    # In-lock regex_sub (id:f26d): the substitution is applied to the line as read under
    # md-merge's OWN flock, never to a literal composed out here before the lock.
    if ! printf '{"updates":[{"id":"%s","regex_sub":{"pattern":"^- \\\\[ \\\\]","repl":"- [x]"}}]}' "$id" \
        | python3 "$MD_MERGE" update-ids --file "$TODO_FILE" >> "$LOG_FILE" 2>&1; then
        echo "roadmap-tick: FATAL: failed to tick the TODO.md twin of id:$id in $TODO_FILE (see $LOG_FILE)." >&2
        exit 1
    fi
    # Post-write assertion (id:e166): the marker must STILL sit on a line that starts with
    # a checkbox, and that checkbox must now be ticked. run-tests.sh's item_open() reads the
    # checkbox at line start, so a marker knocked onto a continuation line breaks
    # expected-red accounting silently.
    if ! has_own_line "$TODO_FILE" "$id" done; then
        echo "roadmap-tick: FATAL: after the twin write, id:$id no longer names a ticked checkbox line in $TODO_FILE — the id marker moved off its checkbox line (id:e166)." >&2
        exit 1
    fi
    TWINNED+=("$id")
}

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
TWINNED=()
for id in "${IDS[@]}"; do
    # Only flip the FIRST open checkbox line carrying this id. awk edits in place via a temp.
    tmp=$(mktemp)
    if awk -v want="${id}" "$OWN_ID_AWK"'
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

    # Single-id-two-views: converge the TODO twin whenever the ROADMAP line now reads [x]
    # (flipped just now, or already ticked on an earlier/hand pass — the repair path).
    # An id with NO ticked ROADMAP line never touches TODO.md.
    if has_own_line "$ROADMAP_FILE" "$id" done; then
        tick_todo_twin "$id"
    fi
done

if [[ "${#TWINNED[@]}" -gt 0 ]]; then
    echo "roadmap-tick: ticked TODO twins ${TWINNED[*]}"
    printf '%s roadmap-tick: ticked TODO twins [%s] in %s\n' \
        "$(date -Iseconds)" "${TWINNED[*]}" "$TODO_FILE" >> "$LOG_FILE"
fi

if [[ "${#TICKED[@]}" -eq 0 ]]; then
    echo "roadmap-tick: nothing to tick (all ids already ticked or absent)."
    printf '%s roadmap-tick: nothing to tick for [%s] in %s\n' "$(date -Iseconds)" "$IDS_CSV" "$REPO_ROOT" >> "$LOG_FILE"
    exit 0
fi

echo "roadmap-tick: ticked ${TICKED[*]}"
printf '%s roadmap-tick: ticked [%s] in %s\n' "$(date -Iseconds)" "${TICKED[*]}" "$REPO_ROOT" >> "$LOG_FILE"
