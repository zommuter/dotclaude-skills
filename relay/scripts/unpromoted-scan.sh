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
#                 = surface   → untagged, [HARD — meeting]/[HARD — hands], or otherwise
#                               ambiguous → SURFACE for strong-turn triage, never
#                               auto-promote (acceptance #3).
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

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s unpromoted-scan.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

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

  local repo_findings=0 line token disposition title
  while IFS= read -r line; do
    # Exempt intentional non-items (consistent with todo-conformance.sh's exempt()): a line
    # marked <!-- lint-ok: … --> or an intentional cross-repo pointer <!-- ref:XXXX --> is a
    # deliberate non-task, not un-promoted work — never report it (incl. as `untracked`).
    [[ "$line" == *"<!-- lint-ok:"* ]] && continue
    grep -qP '<!-- ref:[0-9a-f]{4} -->' <<<"$line" && continue
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

    # Disposition: an executable lane tag means directly handoff-promotable; anything
    # else (untagged, [HARD — meeting]/[HARD — hands], blocked) SURFACES for triage.
    if grep -qE '\[ROUTINE\]|\[HARD — pool\]' <<<"$line"; then
      disposition="promote"
    else
      disposition="surface"
    fi
    # Title: the line's prose minus the leading "- [ ] " and the trailing id comment.
    title="$(sed -E 's/^- \[ \] +//; s/[[:space:]]*<!-- id:[0-9a-f]{4} -->[[:space:]]*$//' <<<"$line")"
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
