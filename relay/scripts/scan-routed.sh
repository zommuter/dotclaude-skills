#!/usr/bin/env bash
# scan-routed.sh — slice 1 of id:678e: a REPORT-ONLY dead-letter detector for the shared
# cross-project inbox (`~/.claude/todo-inbox.md`). The detection half of the inbox
# auto-reconcile contract decided 2026-06-25
# (`docs/meeting-notes/2026-06-25-2335-inbox-auto-reconcile-cross-repo.md`).
#
# WHY: a routed inbox item (`- [ ] [target] … <!-- routed:XXXX -->`) is a DEAD LETTER when
# its target repo never ingested it — its TODO+ROADMAP carry no `routed:XXXX`/`id:XXXX`
# twin. Live evidence 2026-06-25: 12 such items targeting dotclaude-skills sat stranded for
# days. Surface-only had no DETECTOR; this is it.
#
# WHAT IT REPORTS (report-only — exit 0 with findings; only MISUSE exits nonzero):
#   DEAD-LETTER   a conforming routed item whose target own-repo lacks the token — with a
#                 READY-TO-RUN file command (the action a human / the gated slice-2 takes).
#   UNRESOLVED    a routed item whose `[target]` is not an own-repo in relay.toml — surfaced,
#                 never silently dropped (the target may need a `# path:` override).
#   NON-CONFORMING an inbox line that is not a well-formed routed item (reuses
#                 `todo-conformance.sh --inbox`, no reimplementation) — token-less prose
#                 `inbox-done` can never resolve.
# It NEVER writes (slice-2 class-A auto-write is gated — see id:678e). Class B (token-less
# prose / unresolvable target) is forever surface-only — never guessed.
#
# Usage:
#   scan-routed.sh [--exclude <repo>]… [<inbox-path>]
#     <inbox-path> default = $RELAY_INBOX or ~/.claude/todo-inbox.md
#     --exclude <repo>  drop that target repo from the dead-letter scan (repeatable; honors
#                       the same intent as relay's --exclude — e.g. a repo a parallel
#                       session holds). relay.toml `paused` own-repos are also excluded.
#   Unknown flag / unreadable inbox = LOUD reject (nonzero). No silent 2>/dev/null swallow.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFORMANCE="$SCRIPTS_DIR/todo-conformance.sh"
LOG="${SCAN_ROUTED_LOG:-$HOME/.claude/logs/scan-routed.log}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
INBOX_DEFAULT="${RELAY_INBOX:-$HOME/.claude/todo-inbox.md}"
APPEND_SH="$(cd "$SCRIPTS_DIR/../.." && pwd)/meeting/append.sh"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s scan-routed.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# --- own repos from relay.toml (same parser as relay-doctor / unpromoted-scan) ---------
# Emits "<name>\t<path>" for each classification="own", non-paused repo (honors `# path:`).
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
            cur = m.group(1); continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)
def expand(p): return os.path.expanduser(os.path.expandvars(p))
for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own": continue
    if entry.get("paused"): continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- parse args ----------------------------------------------------------------
declare -A exclude=()
inbox=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude) shift; [[ $# -gt 0 ]] || { echo "scan-routed.sh: --exclude needs a repo name" >&2; exit 2; }
               exclude["$1"]=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    --*) echo "scan-routed.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) [[ -n "$inbox" ]] && { echo "scan-routed.sh: only one inbox path may be given" >&2; exit 2; }
       inbox="$1"; shift ;;
  esac
done
inbox="${inbox:-$INBOX_DEFAULT}"
[[ -f "$inbox" ]] || { echo "scan-routed.sh: inbox not found: $inbox" >&2; exit 2; }
[[ -r "$inbox" ]] || { echo "scan-routed.sh: inbox not readable: $inbox" >&2; exit 2; }

# --- build the own-repo name→path map ------------------------------------------
declare -A repo_path=()
while IFS=$'\t' read -r rname rpath; do
  [[ -n "$rname" ]] && repo_path["$rname"]="$rpath"
done < <(own_repos)

findings=0

# --- pass 1: non-conforming inbox entries (reuse todo-conformance --inbox) ------
echo "=== non-conforming inbox entries (todo-conformance.sh --inbox) ==="
if [[ -x "$CONFORMANCE" ]]; then
  nc="$(bash "$CONFORMANCE" --inbox "$inbox" 2>>"$LOG" || true)"
  nc="$(printf '%s' "$nc" | grep -vE '^[[:space:]]*$' || true)"
  if [[ -n "$nc" ]]; then
    printf '%s\n' "$nc"
    n="$(printf '%s\n' "$nc" | grep -c . || true)"
    findings=$((findings + n))
  else
    echo "clean (every inbox line is a header, comment, or well-formed routed item)"
  fi
else
  echo "SKIP — todo-conformance.sh not found at $CONFORMANCE" >&2
fi
echo

# --- pass 2: dead letters (conforming routed item with no twin in its target) --
echo "=== routed dead-letters (target repo never ingested the item) ==="
dead=0
while IFS= read -r line; do
  # OPEN conforming routed item only: `- [ ] [target] … <!-- routed:XXXX -->`
  [[ "$line" =~ ^-\ \[\ \]\ \[ ]] || continue
  tok="$(grep -oP '(?<=<!-- routed:)[0-9a-f]{4}(?= -->)' <<<"$line" | head -1 || true)"
  [[ -z "$tok" ]] && continue
  target="$(grep -oP '^- \[ \] \[\K[^\]]+' <<<"$line" | head -1 || true)"
  [[ -z "$target" ]] && continue
  if [[ -n "${exclude[$target]:-}" ]]; then
    log "excluded target=$target routed=$tok"; continue
  fi
  src="$(grep -oP '\(from \K[^,)]+' <<<"$line" | head -1 || true)"
  desc="$(sed -E 's/^- \[ \] \[[^]]*\] +//; s/ *\(from [^)]*\)//; s/ *<!-- routed:[0-9a-f]{4} -->.*$//' <<<"$line")"

  tpath="${repo_path[$target]:-}"
  if [[ -z "$tpath" ]]; then
    echo "UNRESOLVED routed:$tok → [$target] — no own-repo named '$target' in relay.toml (add a [repos.$target] block or a # path: override, then re-scan)"
    findings=$((findings+1)); dead=$((dead+1)); continue
  fi
  # Twin = the token (routed: or id:) appears in the target's TODO or ROADMAP.
  if grep -qsF "$tok" "$tpath/TODO.md" "$tpath/ROADMAP.md" 2>/dev/null; then
    continue   # already ingested — not a dead letter
  fi
  echo "DEAD-LETTER routed:$tok → [$target] (absent from $tpath/TODO.md+ROADMAP.md): $desc"
  echo "  ↳ to file: add to $tpath/TODO.md — \"- [ ] [INBOUND routed:$tok from ${src:-?}] $desc <!-- id:NEW -->\" (mint NEW via \`$APPEND_SH new-id\`), then \`$APPEND_SH inbox-done $tok\`"
  findings=$((findings+1)); dead=$((dead+1))
done < "$inbox"
[[ "$dead" -eq 0 ]] && echo "clean (every routed inbox item has a twin in its target repo)"
echo

echo "=== summary ==="
echo "scan-routed: $findings finding(s) — $dead routed dead-letter/unresolved. REPORT-ONLY (slice-2 auto-write is gated, id:678e); class-B prose is surface-only."
log "inbox=$inbox findings=$findings dead=$dead"
exit 0
