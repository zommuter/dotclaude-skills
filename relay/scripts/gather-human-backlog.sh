#!/usr/bin/env bash
# gather-human-backlog.sh — collect open human-triage backlog across relay.toml
# `classification = "own"` repos for /relay human. Read-only.
#
# Usage:
#   gather-human-backlog.sh                — all confirmed own repos in relay.toml
#   gather-human-backlog.sh repo [repo...] — only the named repos
#   gather-human-backlog.sh --needs-auth [repo...]
#                                          — OFFLINE @needs-auth lister (id:1750): a plain,
#                                            human-readable (NON-TSV) view of every open
#                                            `@needs-auth` REVIEW_ME box across own repos
#                                            (or the named repos), one block per box showing
#                                            repo · what-secret · where-it-goes · exact-command
#                                            · why. AI-free / offline (pure bash+awk, no model,
#                                            no network) — the whole point is a sweep the human
#                                            runs with no `claude -p` and no connectivity.
#
# Output (TSV, one open box per line — DEFAULT mode; `--needs-auth` prints plain blocks):
#   repo  path  kind  box_summary
#
# kind:
#   review_me  — an open `- [ ]` box in the repo's REVIEW_ME.md
#   manual     — an open `- [ ]` box tagged `@manual` (REVIEW_ME.md or ROADMAP.md);
#                a human must RUN it, so it is NEVER auto-tickable (surface only).
#   mechanical_orphan — an open `[MECHANICAL]` ROADMAP item with NO recipe anywhere in the
#                drop-dir (id:8a6b / id:1bd1): it will never run. Surface only — author a recipe
#                (or run mechanical-orphan-draft.sh) and promote drafts/ -> pending/.
#   mechanical_draft  — an auto-DRAFTED recipe skeleton (drafts/) awaiting an Opus/human to fill
#                its TODO cmd/est_wall/acceptance_artifact and deliberately promote it to
#                pending/ (id:8a6b). A draft is NEVER executed by the daemon. Surface only.
#   hard_pool      \  an open `- [ ]` `[HARD]`/`[INPUT — …]` ROADMAP item, bucketed by
#   hard_meeting    \ its EXPLICIT lane tag (id:78ff). The lane is READ from the bracket
#   human_decision  > tag, never inferred (decision 2026-06-21 "obviously explicit"). The
#   hard_hands     /  lane vocabulary is the shared contract in relay/references/hard-lanes.md.
#                CANONICAL (new, capability-keyed, id:4f02 north star):
#                  [HARD]  (bare, no dash-lane) → hard_pool       (/relay --afk pool runs it)
#                  [INPUT — meeting]            → hard_meeting     (/meeting decides it)
#                  [INPUT — decision]           → human_decision   (human decides, NO meeting)
#                  [INPUT — access]             → hard_hands       ("you run these")
#                  [INPUT — author]             → hard_hands       (human-expert-authored content, id:2b0b)
#                BUCKET vs ROUTE (id:1f1c): human_decision separates "a person decides
#                this directly (/relay human)" from hard_meeting ("a person + a /meeting
#                session"). A /meeting sweep reads ONLY the meeting bucket, so a
#                human-decision row ([INPUT — decision], or a note routed `route:human`
#                / "needs /relay human") never inflates the meeting overcount.
#                ACCEPTED (old, venue-keyed — dual-vocab migration window, still OPEN):
#                  [HARD — pool]                → hard_pool
#                  [HARD — meeting]             → hard_meeting
#                  [HARD — decision gate] / 🚧 route:meeting|human|decision-gate
#                                               → hard_meeting (auto-gate alias, id:3801)
#                  [HARD — hands]               → hard_hands
#                A `[HARD]`/`[INPUT — …]` item matching NEITHER form above is the
#                `untagged` ERROR (below), NOT silently bucketed. Replaces the old single
#                `gated_hard` lump that routed every HARD item to /meeting (id:f6c9
#                over-correction) — the pool-executable majority now bucket as hard_pool.
#                Only OPEN `- [ ]` items; `- [x]` never. box_summary keeps a
#                ` — gated: <reason>` suffix for meeting/hands lanes (pool items carry
#                ` — pool: <why>`).
#
# untagged HARD = LOUD REJECT (id:415b grammar-tightening-with-loud-rejection): an
# open `[HARD]`/`[INPUT — …]` item carrying no recognized lane prints an `ERROR:` line
# to stderr (repo, item id, the offending text) and forces the script to EXIT NONZERO
# at the end of the run. A missing lane is a contract gap to fix at the source, never a
# silent default disposition.
#
# RECOGNIZED markers (id:a505): besides `@manual` (a human must RUN a box) and
# `@container` (a DECOMPOSED parent, excluded), `@needs-auth` is a KNOWN marker on a
# REVIEW_ME.md box — it records work blocked on a human-held secret / interactive-auth
# wall (the four-field convention in relay/references/hard-lanes.md). This collector
# RECOGNIZES it (a `@needs-auth` box is never treated as an unknown token); it currently
# surfaces such a box as an ordinary review_me row. The AI-free OFFLINE lister that
# FILTERS `@needs-auth` boxes into a dedicated human-readable view is a separate item
# (id:1750) — this contract (id:a505) only pins the marker as a recognized token.
#
# box_summary is the box text with the leading `- [ ] ` stripped and whitespace
# collapsed (TSV-safe: tabs/newlines become spaces). Closed `- [x]` boxes are
# never emitted. The script never writes state and never spawns a model — it is
# the read-only collector; the strong turn does the classification/answering.
#
# Repo paths come from relay.toml's `[repos.<name>]` entries with
# classification = "own", honoring an optional `path = "..."` override per repo
# (default path is $SRC_DIR/<name>). Excluded/clone repos are skipped.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
# id:8a6b — mechanical-orphan / un-promoted-draft surfacer (sibling script). Surfaced kinds:
#   mechanical_orphan — an open [MECHANICAL] item with no recipe anywhere → author a recipe.
#   mechanical_draft  — an auto-drafted skeleton awaiting an Opus/human to fill + promote to pending/.
# Both are surface-only (never auto-tickable), so /relay human shows them.
MECH_SCAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mechanical-orphan-scan.sh"

# Set to 1 by emit_hard_lanes() when an open [HARD] item carries no recognized lane
# tag. A nonzero value forces a LOUD nonzero exit at the end of the run (id:78ff /
# id:415b) — an untagged HARD item is a contract gap to fix at the source, never a
# silent default disposition.
UNTAGGED_FOUND=0

# id:fa5c: untagged-lane ERROR lines are collected here (one per offending item,
# across ALL repos) and flushed as ONE distinct block at the very end of the run,
# rather than printed immediately per-repo — so a human/CI reader sees every
# reject together, and (more importantly) collecting-then-flushing can never
# itself abort the scan: each repo's boxes are always fully emitted before the
# block is printed. Never touched if no untagged item is seen.
REJECT_LOG="$(mktemp)"
trap 'rm -- "$REJECT_LOG"' EXIT

# --- own repos from relay.toml: lines of "<name>\t<path>" -------------------
# Honors `classification = "own"` and a per-repo path override.
#
# Path override resolution (in priority order):
#   1. a real `path = "..."` TOML key, if present;
#   2. the `# path: <p>` COMMENT convention — IN PRACTICE every override in
#      relay.toml is written this way (e.g. `# path: ~/src/zkm/plugins/zkm-scan`),
#      and tomllib strips comments, so a tomllib-only reader silently fell back to
#      ~/src/<name> for ALL of them. That mis-resolved the zkm-* plugin repos
#      (real path ~/src/zkm/plugins/<name>) to a non-existent ~/src/<name>, so the
#      whole zkm-* family vanished from /relay human. We re-parse the raw lines to
#      recover the comment form;
#   3. else the default $SRC_DIR/<name>.
# `~`/`$HOME` in either form is expanded.
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)

# Recover the `# path:` COMMENT override per repo (tomllib drops comments).
# Track the current [repos.<name>] section header and the first `# path:` in it.
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):          # on-hiatus repos are skipped in relay sweeps
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- emit open boxes for one file --------------------------------------------
# $1 repo name, $2 repo path, $3 file path, $4 default kind (review_me|manual)
emit_boxes() {
  local name="$1" path="$2" file="$3" default_kind="$4"
  [[ -f "$file" ]] || return 0
  # Read open boxes only ('- [ ]'); classify @manual lines as kind=manual.
  while IFS= read -r line; do
    local summary kind
    # strip leading '- [ ] ' and collapse whitespace (tabs/newlines → spaces)
    summary="$(printf '%s' "$line" | tr '\t\n' '  ' | sed -E 's/^[[:space:]]*- \[ \] //; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    kind="$default_kind"
    if printf '%s' "$line" | grep -qi '@manual'; then
      kind=manual
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "$kind" "$summary"
  done < <(grep -nE '^[[:space:]]*- \[ \] ' "$file" 2>/dev/null | sed -E 's/^[0-9]+://')
}

# --- warn on nested worktrees (the "wrong checkout" trap) --------------------
# A linked git worktree nested INSIDE the repo path means the relay may be reading
# a stale top-level checkout while the live branch lives in a sub-worktree (this
# bit /relay human on ai-codebench 2026-06-15). Warn to stderr so the human can
# fix the layout; never corrupts the TSV on stdout.
warn_nested_worktrees() {
  local name="$1" path="$2"
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local main_wt nested
  main_wt="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$main_wt" ]] || return 0
  # worktrees whose path is strictly under main_wt/ are nested inside the checkout —
  # the "stale tree" smell. EXCLUDE harness/internal worktrees under .claude/ or .git/
  # (those are ephemeral sandboxes, not a layout problem). `|| true` guards grep's
  # exit-1-on-no-match against `set -e`.
  nested="$(git -C "$path" worktree list --porcelain 2>/dev/null \
    | sed -n 's/^worktree //p' \
    | { grep -vxF "$main_wt" || true; } \
    | { grep -F "$main_wt/" || true; } \
    | { grep -vE '/\.(claude|git)/' || true; } \
    | tr '\n' ' ')"
  if [[ -n "$nested" ]]; then
    printf 'WARN: %s has nested worktree(s) inside its checkout: %s— relay may be reading a STALE tree; relocate worktrees out of the checkout.\n' \
      "$name" "$nested" >&2
  fi
}

# --- emit HARD ROADMAP items, bucketed by EXPLICIT lane tag (id:78ff) ---------
# Re-derive (NOT read live RELAY_STATUS.md) every open `[HARD]` ROADMAP item and
# bucket it by its EXPLICIT lane tag. The lane is READ from the bracket tag, never
# inferred (decision 2026-06-21 "obviously explicit") — the shared lane vocabulary
# is the contract in relay/references/hard-lanes.md, parsed identically by
# project_manager's scan.py (id:b466). Re-derivation from ROADMAP is freshness-safe
# even when no pool is live (a stale RELAY_STATUS could lie).
#
# WHY explicit lanes replaced the old single `gated_hard` lump (id:f6c9 → id:78ff):
# the prior version routed EVERY open `[HARD]` item to "needs a /meeting", so ~40
# pool-executable HARD items read as 40 meetings. The pool-executable majority now
# bucket as hard_pool (the `/relay --afk` `hard` verdict runs them, id:da26) and only
# genuine decision/hands work surfaces to human triage.
#
# Buckets (kind), by the recognized lane tag. CANONICAL (new, capability-keyed,
# id:4f02) first; ACCEPTED (old, venue-keyed, dual-vocab migration window still OPEN)
# after:
#   [HARD]  (bare)                                           → hard_pool
#   [INPUT — meeting]                                        → hard_meeting
#   [INPUT — decision]                                       → human_decision (id:1f1c)
#   [INPUT — access]                                         → hard_hands
#   [INPUT — author]                                         → hard_hands     (human-authored content, id:2b0b)
#   [HARD — pool]                                            → hard_pool      (old, accepted)
#   [HARD — meeting]                                         → hard_meeting   (old, accepted)
#   [HARD — decision gate] / 🚧 route:meeting|decision-gate
#                                                            → hard_meeting   (old, accepted; alias, id:3801)
#   🚧 route:human / "needs /relay human"                    → human_decision (id:1f1c — human decides, NO meeting)
#   [HARD — hands]                                           → hard_hands     (old, accepted)
#   @container (on a DECOMPOSED parent)                      → SKIPPED (id:8504 — seams are the work)
#   [HARD]/[INPUT — …] matching NEITHER form above           → untagged (LOUD reject)
#
# An `untagged` open `[HARD]`/`[INPUT — …]` item is a CONTRACT GAP: it prints an
# `ERROR:` line to stderr and makes the awk exit with status 3, which scan_repo turns
# into a global
# UNTAGGED_FOUND=1 → the whole run exits nonzero (id:415b: never silently default a
# disposition). Recognized items emit kind + ` — <bucket>: <why>` on box_summary.
# Only OPEN `- [ ]` items; `- [x]` never.
# $1 repo name, $2 repo path.  Returns nonzero (3) if any untagged HARD item seen.
#
# id:4e67 — TODO.md human-lane scan + dedup. Extra optional args generalise this
# helper so it can ALSO scan a repo's TODO.md for open human-lane items and emit them
# alongside the ROADMAP output, deduped by id:
#   $3 file       — file to scan (default $path/ROADMAP.md; scan_repo passes TODO.md)
#   $4 todo_mode  — 1 to run in TODO mode (default 0 = ROADMAP mode)
#   $5 seen_ids   — space-separated `id:XXXX` tokens already emitted from ROADMAP; a
#                   TODO item whose id is in this set is skipped (dedup: an id in BOTH
#                   ledgers is listed ONCE — the ROADMAP row wins).
# In TODO mode the collector ONLY surfaces human-lane buckets (meeting/decision/access/
# author — NOT the pool lane, which the pool runs unattended) and NEVER loud-rejects an
# untagged item (TODO holds many non-lane items by design; an untagged reject there is
# noise, not a contract gap — the LOUD reject stays a ROADMAP-only invariant).
emit_hard_lanes() {
  local name="$1" path="$2"
  local file="${3:-$path/ROADMAP.md}"
  local todo_mode="${4:-0}"
  local seen_ids="${5:-}"
  [[ -f "$file" ]] || return 0
  awk -v name="$name" -v path="$path" -v todo_mode="$todo_mode" -v seen_ids="$seen_ids" '
    BEGIN {
      n = split(seen_ids, _sa, " ")
      for (i = 1; i <= n; i++) if (_sa[i] != "") seen[_sa[i]] = 1
    }
    # Open top-level checkbox items only (sub-bullets are continuation prose).
    /^[[:space:]]*- \[ \] / {
      line = $0
      # Strip backtick-quoted strings BEFORE the candidate-skip gate (id:306d) so a
      # non-HARD item (e.g. `[ROUTINE]`) whose prose merely MENTIONS a
      # backtick-quoted lane tag (e.g. "re-laned `[INPUT — decision]`->`[ROUTINE]`")
      # is not mistaken for a HARD/INPUT candidate at all. The candidate gate used
      # to read the RAW line while lane-detection ran on the backtick-stripped
      # `clean` (the id:1bbd fix) — a mismatch that let a prose-only mention pass
      # the raw gate, then find no real lane tag in the stripped text and fall into
      # the untagged LOUD-reject branch as a false positive. Also strips a prose
      # mention of `[HARD — pool]` etc. so it cannot shadow the item OWN bracket
      # tag (id:1bbd: pool branch was checked first, causing [HARD — hands] items
      # with a `[HARD — pool]` prose mention to mis-bucket as hard_pool).
      clean = line
      gsub(/`[^`]*`/, "", clean)
      low = tolower(clean)

      # Dual-vocab window (id:4f02/id:8111 B2a, OPEN): both the old venue-keyed
      # [HARD — <lane>] spelling AND the new capability-keyed [HARD]/[INPUT — <lane>]
      # spelling are recognized here. Skip lines carrying neither marker family —
      # checked on the backtick-STRIPPED text (id:306d) so a bracket tag that only
      # exists inside backtick-quoted prose does not count as a candidate.
      if (clean !~ /\[HARD/ && clean !~ /\[INPUT[[:space:]]*[—-]/) next

      # CONTAINER exclusion (id:8504): a DECOMPOSED parent explicitly marked
      # `@container` is not itself work — its seams are. Collectors skip it so a
      # decomposed parent that still carries a lane tag does not surface as a
      # phantom meeting/pool/hands row. (roadmap-lint.sh --strict enforces that a
      # DECOMPOSED open item is either ticked or carries this marker.)
      if (line ~ /@container/) next

      # Read the EXPLICIT lane from the bracket tag (never inferred). Em-dash "—"
      # or a plain "-" between HARD and the lane word are both accepted; surrounding
      # whitespace is flexible. Recognized auto-gate aliases map to the meeting lane.
      #
      # OLD vocab (venue-keyed, still accepted during the dual-vocab migration
      # window, id:4f02/id:8111) is checked FIRST — a dash-lane tag ([HARD — pool],
      # [HARD — meeting], etc.) always wins over the bare-[HARD] new-vocab branch.
      # NEW vocab (capability-keyed, id:4f02 north star): bare [HARD] (no dash-lane)
      # is the renamed [HARD — pool]; [INPUT — meeting]/[INPUT — decision] are both
      # the meeting lane; [INPUT — access] is the hands lane.
      # BUCKET vs ROUTE (id:1f1c/80e0): a HUMAN-DECIDES item — `[INPUT — decision]`
      # ("human decides, no meeting"), or an auto-gate note routed `route:human` /
      # "needs /relay human" — gets its OWN `human_decision` bucket, distinct from the
      # `hard_meeting` (a person + a /meeting session) bucket. A /meeting sweep reads
      # only the meeting bucket, so a human-decision row no longer inflates the meeting
      # count. The explicit venue lane tags ([HARD — meeting], [INPUT — meeting]) and
      # the meeting-routed aliases (route:meeting|decision-gate, [HARD — decision gate])
      # stay hard_meeting; only route:human / needs-/relay-human / [INPUT — decision]
      # move to human_decision.
      kind = ""; bucket = ""
      if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*pool[[:space:]]*\]/) {
        kind = "hard_pool"; bucket = "pool"
      } else if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*meeting[[:space:]]*\]/ \
                 || low ~ /\[hard[[:space:]]*[—-][[:space:]]*decision gate[[:space:]]*\]/ \
                 || low ~ /route:(meeting|decision-gate)/) {
        kind = "hard_meeting"; bucket = "meeting"
      } else if (low ~ /route:human/ || low ~ /needs[[:space:]]+\/relay[[:space:]]+human/) {
        kind = "human_decision"; bucket = "human-decision"
      } else if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*hands[[:space:]]*\]/) {
        kind = "hard_hands"; bucket = "hands"
      } else if (low ~ /\[input[[:space:]]*[—-][[:space:]]*meeting[[:space:]]*\]/) {
        kind = "hard_meeting"; bucket = "meeting"
      } else if (low ~ /\[input[[:space:]]*[—-][[:space:]]*decision[[:space:]]*\]/) {
        kind = "human_decision"; bucket = "human-decision"
      } else if (low ~ /\[input[[:space:]]*[—-][[:space:]]*access[[:space:]]*\]/) {
        kind = "hard_hands"; bucket = "hands"
      } else if (low ~ /\[input[[:space:]]*[—-][[:space:]]*author[[:space:]]*\]/) {
        kind = "hard_hands"; bucket = "author"
      } else if (low ~ /\[hard[[:space:]]*\]/) {
        kind = "hard_pool"; bucket = "pool"
      } else {
        kind = "untagged"; bucket = "untagged"
      }

      # id:4e67 — TODO-mode filtering + dedup. In TODO mode surface ONLY human-lane
      # buckets (never the pool lane — the pool runs those unattended — and never the
      # untagged LOUD reject, which stays a ROADMAP-only invariant), and skip any id
      # already emitted from ROADMAP so an item in BOTH ledgers is listed exactly once.
      if (todo_mode) {
        if (bucket == "pool" || bucket == "untagged") next
        itemid = ""
        if (match(line, /id:[0-9a-f]{4}/)) itemid = substr(line, RSTART, RLENGTH)
        if (itemid != "" && (itemid in seen)) next
      }

      # Strip "- [ ] " prefix and collapse whitespace (TSV-safe).
      summary = line
      sub(/^[[:space:]]*- \[ \] /, "", summary)
      gsub(/[\t]/, " ", summary)
      gsub(/[[:space:]]+/, " ", summary)
      sub(/^ /, "", summary); sub(/ $/, "", summary)

      if (bucket == "untagged") {
        # LOUD reject: stderr ERROR + force nonzero exit (id:415b).
        printf "ERROR: %s: open [HARD]/[INPUT — …] item carries NO recognized lane " \
               "tag ([HARD]/[INPUT — meeting|decision|access|author], or the old " \
               "[HARD — pool|meeting|hands]) — add one (see relay/references/hard-lanes.md): %s\n", \
               name, summary > "/dev/stderr"
        saw_untagged = 1
        next
      }

      # Emit the REAL route of the row on box_summary (id:80e0) — never a blanket
      # "needs a /meeting" on every row (that made the collector own output
      # ungreppable: 100% of rows matched "needs a /meeting" by construction, so the
      # backlog could not be measured from it). Each bucket states its actual route.
      if (bucket == "pool")
        why = "pool-executable HARD — the /relay --afk pool runs it (hard verdict, id:da26)"
      else if (bucket == "meeting")
        why = "meeting HARD — needs a /meeting to resolve/re-scope (id:3801)"
      else if (bucket == "human-decision")
        why = "human-decision — a person decides it directly (/relay human); NO meeting needed (id:1f1c)"
      else if (bucket == "author")
        why = "author HARD — human-expert-authored content/prose; you write this (id:2b0b)"
      else
        why = "hands HARD — hardware/sudo/secret/on-device; you run this (id:78ff)"

      printf "%s\t%s\t%s\t%s — %s: %s\n", name, path, kind, summary, bucket, why
    }
    END { if (saw_untagged) exit 3 }
  ' "$file"
}

# --- OFFLINE @needs-auth lister (id:1750) ------------------------------------
# Filter every OPEN `@needs-auth` box out of a repo's REVIEW_ME.md and print it as a
# plain, human-readable (NON-TSV) block: repo · what-secret · where-it-goes ·
# exact-command · why (the FOUR mandatory fields the a505 convention mandates, in
# relay/references/hard-lanes.md). AI-free / offline by construction — pure awk, no model,
# no network. A conforming box is an open `- [ ]` line carrying `@needs-auth`, followed by
# indented sub-bullets naming the four fields, e.g.:
#
#   - [ ] Link the Signal device @needs-auth <!-- id:e588 -->
#     - what-secret: the Signal linked-device QR code
#     - where-it-goes: scanned by signal-cli on zomni
#     - exact-command: `signal-cli link -n relay`
#     - why: zkm-signal ingest strands without a linked device
#
# Field names are matched leniently (`where` ≡ `where-it-goes`, `command` ≡
# `exact-command`); a missing field prints `(MISSING)` so a non-conforming box is LOUD,
# not silently dropped. Closed `- [x]` boxes are never listed. $1 repo name, $2 repo path.
list_needs_auth_repo() {
  local name="$1" path="$2"
  local file="$path/REVIEW_ME.md"
  [[ -f "$file" ]] || return 0
  awk -v repo="$name" '
    function trim(s){ sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
    function emit(){
      if(active){
        printf "\n%s — %s%s\n", repo, (title!=""?title:"(untitled)"), (id!=""?" ("id")":"")
        printf "  what-secret:   %s\n", (ws!=""?ws:"(MISSING)")
        printf "  where-it-goes: %s\n", (wg!=""?wg:"(MISSING)")
        printf "  exact-command: %s\n", (ec!=""?ec:"(MISSING)")
        printf "  why:           %s\n", (wy!=""?wy:"(MISSING)")
        found=1
      }
      active=0; ws=""; wg=""; ec=""; wy=""; title=""; id=""
    }
    # A markdown heading ends any open box.
    /^#/ { emit(); next }
    # Any checkbox line is a box boundary; start capturing only OPEN `- [ ]` @needs-auth boxes.
    /^[[:space:]]*- \[[ xX]\] / {
      emit()
      line=$0
      if(line ~ /^[[:space:]]*- \[ \] / && line ~ /@needs-auth/){
        active=1
        t=line
        sub(/^[[:space:]]*- \[ \] /,"",t)
        gsub(/@needs-auth/,"",t)
        if(match(t,/id:[0-9a-f]{4}/)) id=substr(t,RSTART,RLENGTH)
        gsub(/<!--[^>]*-->/,"",t)
        title=trim(t)
      }
      next
    }
    # Field sub-bullets inside an active box (strip indent + optional leading dash).
    active {
      f=$0
      sub(/^[[:space:]]*(- )?[[:space:]]*/,"",f)
      low=tolower(f)
      if(low ~ /^what-secret[[:space:]]*:/)          { sub(/^[^:]*:[[:space:]]*/,"",f); ws=trim(f) }
      else if(low ~ /^where(-it-goes)?[[:space:]]*:/) { sub(/^[^:]*:[[:space:]]*/,"",f); wg=trim(f) }
      else if(low ~ /^(exact-command|command)[[:space:]]*:/) { sub(/^[^:]*:[[:space:]]*/,"",f); ec=trim(f) }
      else if(low ~ /^why[[:space:]]*:/)              { sub(/^[^:]*:[[:space:]]*/,"",f); wy=trim(f) }
    }
    END { emit() }
  ' "$file"
}

# --- dispatch the offline @needs-auth lister over own (or named) repos --------
run_needs_auth_lister() {
  printf '=== @needs-auth backlog (offline; AI-free) — human-held secrets / interactive-auth walls ===\n'
  local any=0
  if (( $# > 0 )); then
    declare -A PATH_OF
    while IFS=$'\t' read -r n p; do
      [[ -n "$n" ]] && PATH_OF["$n"]="$p"
    done < <(own_repos)
    for name in "$@"; do
      local out
      out="$(list_needs_auth_repo "$name" "${PATH_OF[$name]:-$SRC_DIR/$name}")"
      [[ -n "$out" ]] && { printf '%s\n' "$out"; any=1; }
    done
  else
    while IFS=$'\t' read -r name path; do
      [[ -n "$name" ]] || continue
      [[ -d "$path" ]] || continue
      local out
      out="$(list_needs_auth_repo "$name" "$path")"
      [[ -n "$out" ]] && { printf '%s\n' "$out"; any=1; }
    done < <(own_repos)
  fi
  (( any )) || printf '\n(no open @needs-auth boxes found)\n'
}

# --- scan one repo -----------------------------------------------------------
scan_repo() {
  local name="$1" path="$2"
  # Path didn't resolve to a real directory (after the path-override resolution in
  # own_repos). Usually a stale/missing override or a not-yet-cloned repo — you
  # cannot human-triage files you don't have, so skip it, but say so on stderr,
  # else the human wonders why a RELAY_STATUS-blocked repo never appears. (If this
  # fires for a repo you DO have, its `# path:`/`path =` in relay.toml is wrong.)
  if [[ ! -d "$path" ]]; then
    printf 'NOTE: %s path not found (%s) — not a local checkout; skipped. Check its path override in relay.toml.\n' \
      "$name" "$path" >&2
    return 0
  fi
  warn_nested_worktrees "$name" "$path"
  # Open [HARD] ROADMAP items, bucketed by explicit lane tag (id:78ff). A nonzero
  # return (status 3) means an untagged HARD item was seen — record it for the LOUD
  # nonzero exit at end of run; `|| rc=$?` keeps `set -e` from aborting mid-scan.
  local rc=0 hard_out=""
  hard_out="$(emit_hard_lanes "$name" "$path" 2>>"$REJECT_LOG")" || rc=$?
  if (( rc == 3 )); then
    UNTAGGED_FOUND=1
  elif (( rc != 0 )); then
    return "$rc"
  fi
  [[ -n "$hard_out" ]] && printf '%s\n' "$hard_out"
  # id:4e67 — ALSO scan TODO.md for open human-lane items and emit them alongside the
  # ROADMAP/REVIEW_ME output, deduped by id against the ROADMAP hard-lane rows just
  # emitted (an id in BOTH ledgers is listed once). Closes the e9cd TODO-blindness gap:
  # human-gated items living only in TODO were invisible to /relay human.
  if [[ -f "$path/TODO.md" ]]; then
    local seen_ids
    seen_ids="$(printf '%s\n' "$hard_out" | grep -oE 'id:[0-9a-f]{4}' | sort -u | tr '\n' ' ')"
    emit_hard_lanes "$name" "$path" "$path/TODO.md" 1 "$seen_ids"
  fi
  # id:8a6b — mechanical-orphan / un-promoted-draft rows for this repo (surface-only). Translate
  # the scanner's `kind\tid\trepo\thost\tresource\tdetail` into a gather row with a clear summary.
  if [[ -x "$MECH_SCAN" ]]; then
    while IFS=$'\t' read -r mkind mid mrepo mhost mres mdetail; do
      [[ -n "$mkind" ]] || continue
      [[ "$mhost" == "-" ]] && mhost="?"; [[ "$mres" == "-" ]] && mres="?"
      case "$mkind" in
        orphan)
          printf '%s\t%s\t%s\t%s\n' "$name" "$path" mechanical_orphan \
            "[MECHANICAL] id:$mid has no recipe (host=${mhost:-?} resource=${mres:-?}) — author a recipe or run mechanical-orphan-draft.sh, then promote drafts/ -> pending/ (it will never run otherwise)" ;;
        draft)
          printf '%s\t%s\t%s\t%s\n' "$name" "$path" mechanical_draft \
            "[MECHANICAL] id:$mid has an un-promoted DRAFT ($mdetail) — fill its TODO cmd/est_wall/acceptance_artifact and move drafts/ -> pending/ to launch (a draft is never executed)" ;;
      esac
    done < <("$MECH_SCAN" "$name=$path" 2>/dev/null)
  fi
  # REVIEW_ME.md: every open box (default kind review_me; @manual upgrades to manual).
  emit_boxes "$name" "$path" "$path/REVIEW_ME.md" review_me
  # ROADMAP.md: only open boxes tagged @manual need a human to RUN them.
  if [[ -f "$path/ROADMAP.md" ]]; then
    while IFS= read -r line; do
      printf '%s' "$line" | grep -qi '@manual' || continue
      local summary
      summary="$(printf '%s' "$line" | tr '\t\n' '  ' | sed -E 's/^[[:space:]]*- \[ \] //; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
      printf '%s\t%s\t%s\t%s\n' "$name" "$path" manual "$summary"
    done < <(grep -nE '^[[:space:]]*- \[ \] ' "$path/ROADMAP.md" 2>/dev/null | sed -E 's/^[0-9]+://')
  fi
}

# --- dispatch ----------------------------------------------------------------
# `--needs-auth` (id:1750): OFFLINE, AI-free plain-text listing of every open @needs-auth
# REVIEW_ME box; consumes the same own_repos enumeration but bypasses the TSV collector +
# the HARD-lane untagged-exit path (this is a focused human view, not the classifier feed).
if [[ "${1:-}" == "--needs-auth" ]]; then
  shift
  run_needs_auth_lister "$@"
  exit 0
fi

if (( $# > 0 )); then
  # Named repos: resolve each against relay.toml's path override, else $SRC_DIR/<name>.
  declare -A PATH_OF
  while IFS=$'\t' read -r n p; do
    [[ -n "$n" ]] && PATH_OF["$n"]="$p"
  done < <(own_repos)
  for name in "$@"; do
    scan_repo "$name" "${PATH_OF[$name]:-$SRC_DIR/$name}"
  done
else
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" ]] && scan_repo "$name" "$path"
  done < <(own_repos)
fi

# LOUD nonzero exit if any open [HARD] item carried no recognized lane tag (id:78ff /
# id:415b). Every repo's boxes were already fully emitted above (id:fa5c: a bad tag
# in one repo must never truncate the rest of the cross-repo scan) — the collected
# per-item ERROR lines are flushed here as ONE distinct end-of-run block so the gap
# is fixed at the source, never silently bucketed, and never scattered/lost mid-scan.
if (( UNTAGGED_FOUND )); then
  {
    printf '=== untagged [HARD]/[INPUT — …] lane rejects (id:fa5c/id:415b) ===\n'
    cat "$REJECT_LOG"
    printf 'ERROR: one or more open [HARD] items carry no recognized lane tag — see the block above and relay/references/hard-lanes.md. Exiting nonzero.\n'
  } >&2
  exit 1
fi
