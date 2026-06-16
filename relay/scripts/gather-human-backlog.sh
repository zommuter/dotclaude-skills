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
#   gated_hard — EVERY open `- [ ]` `[HARD]` ROADMAP item (a strong-model-or-human
#                decision by definition). The pool writes its non-executable HARD
#                backlog to RELAY_STATUS.md → Blocked as "needs a /meeting"; this
#                collector re-derives the full HARD set from ROADMAP (freshness-safe
#                even when no pool is live), routed as tier-(c) CHEWY → `/meeting
#                --cross`. box_summary embeds a refined why-reason after the item
#                text (` — gated: <reason>`). Earlier this emitted only two textual
#                gates and hid the rest — see the emit_gated_hard header (id:f6c9).
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
RELAY_TOML="${RELAY_TOML:-$HOME/.config/fables-turn/relay.toml}"

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

# --- emit GATED HARD ROADMAP items (id:f6c9) ---------------------------------
# Re-derive (NOT read live RELAY_STATUS.md) the pool's NON-executable GATED [HARD]
# backlog from ROADMAP.md, so /relay human surfaces the same "needs a /meeting"
# items the pool writes to RELAY_STATUS → Blocked (id:2d20). Re-derivation is
# freshness-safe even when no pool is live (a stale RELAY_STATUS could lie); the
# pool and this collector apply the SAME textual EXECUTABLE-HARD test, so they agree.
#
# COMPLETENESS over false-negatives (fix for "/relay human showed nothing"): a
# `[HARD]` item is BY DEFINITION a strong-model-or-human decision, so EVERY open
# `[HARD]` ROADMAP item is surfaced to human triage. The earlier version emitted
# only the two purely-textual gates ("decision gate" INSIDE the bracket, or a
# "## Gated" section heading) and dropped everything else as "executable HARD" —
# but real repos gate semantically (DECISION GATE: as a line *prefix*; plain
# `[HARD — strong model]` gated by sub-bullet acceptance text; inline BLOCKED /
# "do not start" / "NOT yet executor work" markers), so the collector returned
# almost nothing while RELAY_STATUS listed 20+ blocked repos. Over-surfacing to
# the human triage sweep is safe (the human reads + routes, and tier-(a/b/c)
# downgrades when unsure); under-surfacing hid the entire HARD backlog.
#
# A model is NOT available here, so the WHY-reason is refined from textual markers
# when present (decision-gate / gated-section / blocked-or-do-not-start), else a
# generic "strong-model or human decision (verify executability)". An item the
# pool would dispatch via its `hard` verdict may also appear here between pool
# runs; that is acceptable — the human routes it to /relay rather than /meeting.
#
# Emits kind=gated_hard, box_summary = "<item text> — gated: <why>". Only OPEN
# "- [ ]" items are emitted; "- [x]" never.
# $1 repo name, $2 repo path.
emit_gated_hard() {
  local name="$1" path="$2" roadmap="$path/ROADMAP.md"
  [[ -f "$roadmap" ]] || return 0
  awk -v name="$name" -v path="$path" '
    # Track whether the current section heading marks a gated region.
    /^#{1,6}[[:space:]]/ {
      h = tolower($0)
      gated_section = (h ~ /gated/ || h ~ /do not start/ || h ~ /deferred/) ? 1 : 0
    }
    # Open top-level checkbox items only (sub-bullets are continuation prose).
    /^[[:space:]]*- \[ \] / {
      line = $0
      is_hard = (line ~ /\[HARD/)
      if (!is_hard) next
      # Every open [HARD] item is a strong-model-or-human decision → surfaced.
      # Refine the WHY-reason from whatever marker is present (case-insensitive).
      low = tolower(line)
      decision_gate  = (low ~ /decision gate/)
      blocked_marker = (low ~ /blocked/ || low ~ /do not start/ || low ~ /not yet executor work/ || low ~ /forward-flag/)
      if (decision_gate)
        why = "decision-gate HARD — needs a /meeting to resolve (id:2d20)"
      else if (gated_section)
        why = "under a gated/deferred ROADMAP section — needs a /meeting to unblock/re-scope (id:2d20)"
      else if (blocked_marker)
        why = "marked blocked / do-not-start — needs a /meeting to unblock/re-scope (id:2d20)"
      else
        why = "open [HARD] item — strong-model or human decision (verify executability) (id:2d20)"
      # Strip "- [ ] " prefix and collapse whitespace (TSV-safe).
      summary = line
      sub(/^[[:space:]]*- \[ \] /, "", summary)
      gsub(/[\t]/, " ", summary)
      gsub(/[[:space:]]+/, " ", summary)
      sub(/^ /, "", summary); sub(/ $/, "", summary)
      printf "%s\t%s\t%s\t%s — gated: %s\n", name, path, "gated_hard", summary, why
    }
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
  # GATED [HARD] ROADMAP items: the pool's "needs a /meeting" backlog (id:f6c9).
  emit_gated_hard "$name" "$path"
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
