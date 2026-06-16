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
#   gated_hard — an open `- [ ]` ROADMAP item the relay pool classifies NON-executable
#                GATED per the id:2d20 EXECUTABLE-HARD test (a `[HARD — decision gate]`
#                item, or one under a "## Gated"/"do not start"/"deferred" section).
#                The pool writes these to RELAY_STATUS.md → Blocked as "needs a
#                /meeting" but /relay human never showed them (id:f6c9). Re-derived
#                here from ROADMAP (freshness-safe even when no pool is live), routed
#                as tier-(c) CHEWY → `/meeting --cross`. box_summary embeds the
#                why-gated reason after the item text (` — gated: <reason>`).
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
# Honors `classification = "own"` and an optional per-repo `path =` override
# (the `# path:` convention recorded as a real TOML key).
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, sys, tomllib
src = os.environ["SRC_DIR"]
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):          # on-hiatus repos are skipped in relay sweeps
        continue
    path = entry.get("path") or os.path.join(src, name)
    print(f"{name}\t{path}")
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
# A model is NOT available here, so we detect only the two PURELY-TEXTUAL gates of
# the id:2d20 EXECUTABLE-HARD test (the deterministic, false-positive-free ones):
#   • the item is tagged "[HARD — decision gate]" (vs "[HARD — strong model]"), OR
#   • it sits under a "## Gated" / "do not start" / "deferred" ROADMAP section.
# The acceptance-text gates ("blocked on …", "hold a scoping meeting first",
# multi-session/cross-repo) need semantic judgment — that is exactly the /meeting
# the tier-(c) route hands them to; we do not guess them statically.
#
# Emits kind=gated_hard, box_summary = "<item text> — gated: <why>", where <why>
# reuses the classifier's reason vocabulary so the human reads the same wording the
# pool logged. Only OPEN "- [ ]" items are emitted; "- [x]" never.
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
      decision_gate = (line ~ /\[HARD[^]]*decision gate/)
      if (!decision_gate && !gated_section) next   # executable HARD — not ours
      # Build the why-gated reason (matches the id:2d20 classifier vocabulary).
      if (decision_gate)
        why = "decision-gate HARD — needs a /meeting to resolve (id:2d20)"
      else
        why = "under a gated/deferred ROADMAP section — needs a /meeting to unblock/re-scope (id:2d20)"
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
  [[ -d "$path" ]] || return 0
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
