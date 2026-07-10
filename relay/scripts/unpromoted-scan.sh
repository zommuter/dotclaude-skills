#!/usr/bin/env bash
# unpromoted-scan.sh — list OPEN TODO.md items whose id has NO twin in ROADMAP.md,
# REGARDLESS of whether the TODO line carries a lane tag (id:2dea).
#
# WHY (LIVE evidence 2026-06-25, truncocraft — SECOND instance; first was id:78ff):
# `/relay next`/`review`/handoff decide "is there work?" from OPEN ROADMAP items +
# unaudited commits ONLY. truncocraft's ROADMAP was fully `[x]`-closed while TODO.md
# held FIVE open executable items with no ROADMAP twin — so every prior `/relay` run
# read the repo as DRAINED and the un-promoted backlog sat idle for days, even though
# promoting TODO→ROADMAP is exactly handoff C2's job. "ROADMAP closed" != "nothing to
# hand off."
#
# GAP vs the existing d9b0 `orphan-scan.sh --promotion` check: that one only flags a TODO
# item ALREADY carrying an executable lane ([ROUTINE] / [HARD — pool]). truncocraft's
# stranded items carried NO lane tag at all (raw backlog prose) → they slipped past it.
# This scan is LANE-TAG-AGNOSTIC: it reports every un-twinned open TODO id and labels its
# disposition (promote vs surface) so the strong turn can triage — it NEVER auto-promotes
# an untagged item with a guessed lane.
#
# Output (TSV, report-only — exit 0 with findings; only MISUSE exits nonzero):
#   <repo>\t<id>\t<disposition>\t<title>
#     disposition = promote   → line carries an executable lane ([ROUTINE]/[HARD — pool]);
#                               directly handoff-promotable.
#                 = surface   → untagged / ambiguous → SURFACE for strong-turn triage,
#                               never auto-promote (acceptance #3). NOT emitted for a
#                               line whose lane question was already RESOLVED in the
#                               decision-queue (parked/not-an-item — 2026-07-02 fix).
#                 = laned     → carries a recognized HUMAN lane ([HARD — meeting]/
#                               [HARD — hands]/[HARD — decision gate]) as its PRIMARY
#                               tag: lane already decided — reported for visibility,
#                               verdict-neutral (classify counts only promote/surface),
#                               never filed to the decision-queue (2026-07-02 fix for
#                               the answer-then-re-ask loop).
#                 = untracked → an open `- [ ]` item with NO `<!-- id:XXXX -->` token
#                               (id column is `----`). Cannot be correlated to ROADMAP at
#                               all — the favicon-class blind spot from the truncocraft
#                               evidence. handoff C2 mints an id (append.sh new-id) first.
#
# SCOPE (what this does NOT catch — by design): the unit of TODO work is the well-formed
# top-level checkbox line `- [ ] …`. A TODO written as free prose, a non-`-` bullet
# (`* …`), an indented sub-bullet, or a bare line with no checkbox is NOT a tracked item
# and is intentionally ignored — trying to promote arbitrary prose would false-positive on
# every narrative line. The `untracked` disposition closes the one bounded gap that bit
# truncocraft (a real checkbox item that merely lacked an id); malformed-beyond-a-checkbox
# entries are a TODO-hygiene problem, not a routing signal this scan owns.
#
# Usage:
#   unpromoted-scan.sh [SCOPE]
#     (no arg)   → the cwd repo (git rev-parse --show-toplevel)
#     <repo-dir> → that repo
#     --all      → every relay.toml `classification = "own"` repo (reads $RELAY_TOML,
#                  honors `# path:` overrides, like relay-doctor.sh / relay-reconcile.sh)
#   An UNKNOWN flag / an explicit repo path that is missing or not a git repo is a LOUD
#   reject (nonzero exit). Under --all an unreadable repo is SURFACED on stderr and
#   skipped (never silently swallowed — id:4e14 / id:415b).
#
# Conventions: set -euo pipefail; short stdout; `2>/dev/null` only with a stated reason;
# details → ~/.claude/logs/unpromoted-scan.log.
set -euo pipefail

LOG="${UNPROMOTED_SCAN_LOG:-$HOME/.claude/logs/unpromoted-scan.log}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
# Sibling decision-queue helper (id:47f1 case-g exclusion). Resolves alongside this
# script whether run via the canonical path or the ~/.claude/skills symlink (both dirs
# carry the sibling). Fail-open if absent.
DQ="$(dirname "${BASH_SOURCE[0]}")/decision-queue.sh"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s unpromoted-scan.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# primary_lane <line> — echo the item's genuine lane tag, or nothing if it has none.
# Mirrors classify-repo.sh's id:4da4 primary-lane parse: a lane tag clusters right after
# the title; any bracket-token further right is prose/history and must NOT set the lane.
# Used for the promote-vs-surface disposition (id:ed2e).
#
# id:fb7f — bold-titled items (the TODO.md convention, `- [ ] **title** [TAG] ...`) anchor
# STRICTLY: the tag must sit immediately after the title's closing `**` (+ optional
# whitespace), or the item has NO genuine lane (return empty → surface). A bare leftmost-tag
# scan mislabeled bold-titled items whose ONLY bracket-tag mention was prose deep in the body
# (backtick'd or bare) as `promote` — 33c2/a505/7b23/b8ae, 2026-07-02. Non-bold items (no
# `**title**`) fall back to the leftmost-tag-anywhere scan (ROADMAP.md's own convention puts
# the tag right after the checkbox, before any title text, so "leftmost" is already correct
# there and TODO.md's non-bold prose-summary items carry no genuine tag either way).
primary_lane() {
  local line="$1" tag prefix pos best_pos=-1 best_tag="" rest=""
  if [[ "$line" =~ ^-\ \[\ \]\ \*\*[^*]*\*\*[[:space:]]*(.*)$ ]]; then
    rest="${BASH_REMATCH[1]}"
    for tag in "[ROUTINE]" "[HARD — pool]" "[HARD — hands]" "[HARD — meeting]" "[HARD — decision gate]"; do
      case "$rest" in
        "$tag"*) printf '%s' "$tag"; return ;;
      esac
    done
    printf ''
    return
  fi
  for tag in "[ROUTINE]" "[HARD — pool]" "[HARD — hands]" "[HARD — meeting]" "[HARD — decision gate]"; do
    case "$line" in
      *"$tag"*)
        prefix="${line%%"$tag"*}"; pos=${#prefix}
        if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
          best_pos=$pos; best_tag="$tag"
        fi ;;
    esac
  done
  printf '%s' "$best_tag"
}

# --- own repos from relay.toml (same parser as relay-doctor.sh) -----------------
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
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
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- per-repo scan -------------------------------------------------------------
# Emits one TSV line per un-twinned open TODO id. Honors a missing ledger gracefully
# (a repo with no TODO.md is simply nothing to promote). Returns 1 (LOUD on stderr)
# only when the path is not a readable git repo, so --all can keep going.
findings=0
repos_with_findings=0

scan_repo() {
  local name="$1" path="$2"

  if [[ ! -d "$path" ]]; then
    printf 'ERROR: %s — path not found (%s); cannot scan.\n' "$name" "$path" >&2
    log "repo=$name path-missing=$path"
    return 1
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'ERROR: %s (%s) is not a readable git repo — check the path override in relay.toml.\n' "$name" "$path" >&2
    log "repo=$name not-git=$path"
    return 1
  fi

  local todo="$path/TODO.md" roadmap="$path/ROADMAP.md"
  # A repo with no TODO.md has no backlog to promote; no ROADMAP.md means every
  # id-bearing open TODO is un-twinned by definition (a not-yet-handed-off repo).
  [[ -f "$todo" ]] || { log "repo=$name no-todo"; return 0; }
  local roadmap_content=""
  [[ -f "$roadmap" ]] && roadmap_content="$(cat "$roadmap")" || true

  # case-g loop-breaker (id:47f1): a surface item already filed to the decision-queue
  # for OPEN human lane-triage is no longer fresh un-promoted backlog — exclude it so
  # `handoff` stops re-firing on it every round. `decision-queue.sh list` emits open
  # records only; we collect their `source_id` tokens. Fail-open: a missing helper or
  # empty queue simply excludes nothing (never a false-clean — the scan still reports).
  #
  # RESOLVED records matter too (2026-07-02 answer-then-re-ask fix): an UNTAGGED item
  # whose lane question was already RESOLVED in the queue (parked / not-an-item) must
  # not re-surface — otherwise the next human-verdict round re-files it and the queue
  # oscillates. Resolved ids are collected separately: they suppress `surface` for
  # untagged lines ONLY; a line that gained an executable lane tag still promotes.
  local filed_ids=" " resolved_ids=" "
  if [[ -x "$DQ" ]]; then
    filed_ids="$($DQ list --repo "$name" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        sid = json.loads(line).get("source_id", "")
    except json.JSONDecodeError:
        continue
    if sid:
        print(sid)
' | tr "\n" " " || true)"
    filed_ids=" $filed_ids "
    resolved_ids="$($DQ list --repo "$name" --all 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue
    if rec.get("status") == "resolved" and rec.get("source_id"):
        print(rec["source_id"])
' | tr "\n" " " || true)"
    resolved_ids=" $resolved_ids "
  fi

  local repo_findings=0 line token disposition title
  while IFS= read -r line; do
    # Exempt intentional non-items (consistent with todo-conformance.sh's exempt()): a line
    # marked <!-- lint-ok: … --> or an intentional cross-repo pointer <!-- ref:XXXX --> is a
    # deliberate non-task, not un-promoted work — never report it (incl. as `untracked`).
    [[ "$line" == *"<!-- lint-ok:"* ]] && continue
    grep -qP '<!-- ref:[0-9a-f]{4} -->' <<<"$line" && continue
    # Relay status-summary line (`- [ ] Relay: …`): the relay's own roll-up, regenerated
    # every review — never a promotable/backlog task. Its `[ROUTINE]`/`[HARD — pool]` tokens
    # are ALWAYS prose (a closed-item tally), so a substring match mis-labels it `promote`
    # → a wasteful handoff dispatch (id:ed2e — hit zkm-eml id:e662, zkm-claude-ai id:815c).
    # Mechanically exempt it here, which also removes the need for a hand-added lint-ok marker
    # on these lines (cf. meeting-rpg id:070c). Same prose-false-match family as id:4da4.
    grep -qE '^- \[ \] Relay: ' <<<"$line" && continue
    token="$(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$line" | head -1 || true)"
    if [[ -z "$token" ]]; then
      # No id token → cannot be correlated to ROADMAP at all (the favicon-class blind
      # spot from the truncocraft evidence). It is un-promoted by definition: report it
      # as `untracked` so handoff C2 mints an id (append.sh new-id) before promoting.
      # `id` column is `----` (no real token) to keep the TSV column count stable.
      title="$(sed -E 's/^- \[ \] +//' <<<"$line")"
      printf '%s\t%s\t%s\t%s\n' "$name" "----" "untracked" "$title"
      repo_findings=$((repo_findings + 1))
      continue
    fi
    # Twin = the id appears anywhere in ROADMAP.md (same correlation as --promotion).
    grep -qF "id:$token" <<<"$roadmap_content" && continue
    # Already filed for OPEN human lane-triage → not fresh backlog (case-g, id:47f1).
    [[ "$filed_ids" == *" $token "* ]] && { log "repo=$name filed=$token"; continue; }

    # Disposition: an executable lane tag means directly handoff-promotable; a recognized
    # HUMAN lane tag ([HARD — meeting]/[HARD — hands]/[HARD — decision gate]) means the
    # lane question is ANSWERED on the line itself → `laned` (reported for visibility,
    # verdict-neutral, never filed to the decision-queue — filing a lane-triage request
    # for an already-laned line is the answer-then-re-ask loop, 2026-07-02 fix); anything
    # untagged SURFACES for triage — unless its lane question was already resolved in the
    # decision-queue (parked / not-an-item), in which case it is skipped.
    # id:ed2e / id:4da4 — PRIMARY-LANE anchoring: the item's lane is the FIRST recognized
    # lane-tag on the line, NOT any substring match. A bare `grep [ROUTINE]` mis-promotes a
    # human-gated item that merely MENTIONS an executable lane later in its prose/history
    # (e.g. a `[HARD — meeting]` item whose body says "supersedes an earlier [ROUTINE] plan").
    local lane
    lane="$(primary_lane "$line")"
    if [[ "$lane" =~ ^(\[ROUTINE\]|\[HARD\ —\ pool\])$ ]]; then
      disposition="promote"
    elif [[ -n "$lane" ]]; then
      disposition="laned"
    elif [[ "$resolved_ids" == *" $token "* ]]; then
      log "repo=$name resolved=$token (lane question answered in decision-queue; not re-surfaced)"
      continue
    else
      disposition="surface"
    fi
    # Title: the line's prose minus the leading "- [ ] " and the trailing id comment.
    title="$(sed -E 's/^- \[ \] +//; s/[[:space:]]*<!-- (children|gated-on):[0-9a-f,]+ -->//g; s/[[:space:]]*<!-- id:[0-9a-f]{4} -->[[:space:]]*$//' <<<"$line")"
    printf '%s\t%s\t%s\t%s\n' "$name" "$token" "$disposition" "$title"
    repo_findings=$((repo_findings + 1))
  done < <(grep -E '^- \[ \] ' "$todo" 2>/dev/null || true)

  findings=$((findings + repo_findings))
  [[ "$repo_findings" -gt 0 ]] && repos_with_findings=$((repos_with_findings + 1)) || true
  log "repo=$name unpromoted=$repo_findings"
  return 0
}

# --- parse args ----------------------------------------------------------------
scope="cwd"
repo_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     scope="all"; shift ;;
    -h|--help) sed -n '2,46p' "$0"; exit 0 ;;
    --*)       echo "unpromoted-scan.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -n "$repo_arg" ]]; then
        echo "unpromoted-scan.sh: only one repo path may be given (got extra '$1')" >&2
        exit 2
      fi
      repo_arg="$1"; scope="repo"; shift ;;
  esac
done

case "$scope" in
  cwd)
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$root" ]]; then
      echo "unpromoted-scan.sh: cwd is not inside a git repo and no repo path was given" >&2
      exit 2
    fi
    scan_repo "$(basename "$root")" "$root" || true
    ;;
  repo)
    if [[ ! -d "$repo_arg" ]]; then
      echo "unpromoted-scan.sh: scope path not found: $repo_arg" >&2
      exit 2
    fi
    if ! git -C "$repo_arg" rev-parse --git-dir >/dev/null 2>&1; then
      echo "unpromoted-scan.sh: scope path is not a git repo: $repo_arg" >&2
      exit 2
    fi
    abspath="$(cd "$repo_arg" && pwd)"
    scan_repo "$(basename "$abspath")" "$abspath" || true
    ;;
  all)
    any=0
    while IFS=$'\t' read -r rname rpath; do
      [[ -n "$rname" ]] || continue
      any=1
      scan_repo "$rname" "$rpath" || true
    done < <(own_repos)
    if [[ "$any" -eq 0 ]]; then
      echo "unpromoted-scan.sh: --all found NO own repos in $RELAY_TOML (is it readable?)" >&2
    fi
    ;;
esac

log "summary findings=$findings repos_with_findings=$repos_with_findings scope=$scope"
exit 0
