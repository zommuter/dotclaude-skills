#!/usr/bin/env bash
# gather-human-backlog.sh — collect open human-triage backlog across relay.toml
# `classification = "own"` repos for /relay human. Read-only.
#
# Usage:
#   gather-human-backlog.sh                — all confirmed own repos in relay.toml
#   gather-human-backlog.sh repo [repo...] — only the named repos
#
# Output (TSV, one open box per line):
#   repo  path  kind  box_summary
#
# kind:
#   review_me  — an open `- [ ]` box in the repo's REVIEW_ME.md
#   manual     — an open `- [ ]` box tagged `@manual` (REVIEW_ME.md or ROADMAP.md);
#                a human must RUN it, so it is NEVER auto-tickable (surface only).
#   hard_pool    \  an open `- [ ]` `[HARD]` ROADMAP item, bucketed by its EXPLICIT
#   hard_meeting  > lane tag (id:78ff). The lane is READ from the bracket tag, never
#   hard_hands   /  inferred (decision 2026-06-21 "obviously explicit"). The lane
#                vocabulary is the shared contract in relay/references/hard-lanes.md:
#                  [HARD — pool]                → hard_pool    (/relay --afk pool runs it)
#                  [HARD — meeting]             → hard_meeting (/meeting decides it)
#                  [HARD — decision gate] / 🚧 route:meeting|human|decision-gate
#                                               → hard_meeting (auto-gate alias, id:3801)
#                  [HARD — hands]               → hard_hands   ("you run these")
#                A `[HARD]` with NO recognized lane is the `untagged` ERROR (below),
#                NOT silently bucketed. Replaces the old single `gated_hard` lump that
#                routed every HARD item to /meeting (id:f6c9 over-correction) — the
#                pool-executable majority now bucket as hard_pool. Only OPEN `- [ ]`
#                items; `- [x]` never. box_summary keeps a ` — gated: <reason>` suffix
#                for meeting/hands lanes (pool items carry ` — pool: <why>`).
#
# untagged HARD = LOUD REJECT (id:415b grammar-tightening-with-loud-rejection): an
# open `[HARD]` item carrying no recognized lane prints an `ERROR:` line to stderr
# (repo, item id, the offending text) and forces the script to EXIT NONZERO at the
# end of the run. A missing lane is a contract gap to fix at the source, never a
# silent default disposition.
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

# Set to 1 by emit_hard_lanes() when an open [HARD] item carries no recognized lane
# tag. A nonzero value forces a LOUD nonzero exit at the end of the run (id:78ff /
# id:415b) — an untagged HARD item is a contract gap to fix at the source, never a
# silent default disposition.
UNTAGGED_FOUND=0

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
# Buckets (kind), by the recognized lane tag:
#   [HARD — pool]                                            → hard_pool
#   [HARD — meeting]                                         → hard_meeting
#   [HARD — decision gate] / 🚧 route:meeting|human|decision-gate
#                                                            → hard_meeting (alias, id:3801)
#   [HARD — hands]                                           → hard_hands
#   [HARD] with NO recognized lane                           → untagged (LOUD reject)
#
# An `untagged` open `[HARD]` item is a CONTRACT GAP: it prints an `ERROR:` line to
# stderr and makes the awk exit with status 3, which scan_repo turns into a global
# UNTAGGED_FOUND=1 → the whole run exits nonzero (id:415b: never silently default a
# disposition). Recognized items emit kind + ` — <bucket>: <why>` on box_summary.
# Only OPEN `- [ ]` items; `- [x]` never.
# $1 repo name, $2 repo path.  Returns nonzero (3) if any untagged HARD item seen.
emit_hard_lanes() {
  local name="$1" path="$2" roadmap="$path/ROADMAP.md"
  [[ -f "$roadmap" ]] || return 0
  awk -v name="$name" -v path="$path" '
    # Open top-level checkbox items only (sub-bullets are continuation prose).
    /^[[:space:]]*- \[ \] / {
      line = $0
      if (line !~ /\[HARD/) next
      low = tolower(line)

      # Read the EXPLICIT lane from the bracket tag (never inferred). Em-dash "—"
      # or a plain "-" between HARD and the lane word are both accepted; surrounding
      # whitespace is flexible. Recognized auto-gate aliases map to the meeting lane.
      kind = ""; bucket = ""
      if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*pool[[:space:]]*\]/) {
        kind = "hard_pool"; bucket = "pool"
      } else if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*meeting[[:space:]]*\]/ \
                 || low ~ /\[hard[[:space:]]*[—-][[:space:]]*decision gate[[:space:]]*\]/ \
                 || low ~ /route:(meeting|human|decision-gate)/) {
        kind = "hard_meeting"; bucket = "meeting"
      } else if (low ~ /\[hard[[:space:]]*[—-][[:space:]]*hands[[:space:]]*\]/) {
        kind = "hard_hands"; bucket = "hands"
      } else {
        kind = "untagged"; bucket = "untagged"
      }

      # Strip "- [ ] " prefix and collapse whitespace (TSV-safe).
      summary = line
      sub(/^[[:space:]]*- \[ \] /, "", summary)
      gsub(/[\t]/, " ", summary)
      gsub(/[[:space:]]+/, " ", summary)
      sub(/^ /, "", summary); sub(/ $/, "", summary)

      if (bucket == "untagged") {
        # LOUD reject: stderr ERROR + force nonzero exit (id:415b).
        printf "ERROR: %s: open [HARD] item carries NO recognized lane tag " \
               "([HARD — pool|meeting|hands]) — add one (see relay/references/hard-lanes.md): %s\n", \
               name, summary > "/dev/stderr"
        saw_untagged = 1
        next
      }

      if (bucket == "pool")
        why = "pool-executable HARD — the /relay --afk pool runs it (hard verdict, id:da26)"
      else if (bucket == "meeting")
        why = "decision HARD — needs a /meeting to resolve/re-scope (id:3801)"
      else
        why = "hands HARD — hardware/sudo/secret/on-device; you run this (id:78ff)"

      printf "%s\t%s\t%s\t%s — %s: %s\n", name, path, kind, summary, bucket, why
    }
    END { if (saw_untagged) exit 3 }
  ' "$roadmap"
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
  local rc=0
  emit_hard_lanes "$name" "$path" || rc=$?
  if (( rc == 3 )); then
    UNTAGGED_FOUND=1
  elif (( rc != 0 )); then
    return "$rc"
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
# id:415b). The per-item ERROR lines already went to stderr; this makes the gap fatal
# so the contract violation is fixed at the source, never silently bucketed.
if (( UNTAGGED_FOUND )); then
  printf 'ERROR: one or more open [HARD] items carry no recognized lane tag — see the ERROR lines above and relay/references/hard-lanes.md. Exiting nonzero.\n' >&2
  exit 1
fi
