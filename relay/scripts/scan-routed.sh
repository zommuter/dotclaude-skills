#!/usr/bin/env bash
# scan-routed.sh — dead-letter detector + class-A auto-writer for the shared cross-project
# inbox (default `~/.claude/projects/todo-inbox.md`, id:9fdb). Slice 1 + Slice 2 of id:678e.
# Slice 1 (SHIPPED): REPORT-ONLY dead-letter detection.
# Slice 2 (id:678e): --apply mode — class-A idempotent INBOUND stub writer.
#   Decided 2026-06-29 (`docs/meeting-notes/2026-06-29-1116-inbox-reconcile-slice2-gate-open.md`).
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
#
# --apply: for each class-A dead-letter (conforming token + repo resolves on disk),
#   write a reversible INBOUND stub into the target TODO.md (flock'd md-merge.py),
#   commit via commit-ledger.sh, mark inbox-done. Idempotent: grep target TODO for
#   `routed:XXXX` before writing — re-run is a no-op. Resolve by EXISTENCE (id:678e D2):
#   relay.toml first (incl. `# path:` polyrepo override), then $SRC_DIR/<name> on disk.
#   A repo on disk with no relay.toml block still resolves; only a target matching NO
#   repo on disk stays UNRESOLVED / class-B surface-only. claim.sh peek skips a target
#   a live pool worktree holds.
#
# --apply --dry-run: writes NOTHING, prints the inspectable plan/diff.
#
# Usage:
#   scan-routed.sh [--apply [--dry-run]] [--exclude <repo>]… [<inbox-path>]
#     <inbox-path> default = $RELAY_INBOX or ~/.claude/projects/todo-inbox.md
#     --apply           class-A auto-write (slice 2)
#     --dry-run         with --apply: print plan, write nothing
#     --exclude <repo>  drop that target repo from the dead-letter scan (repeatable)
#   Unknown flag / unreadable inbox = LOUD reject (nonzero). No silent 2>/dev/null swallow.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFORMANCE="$SCRIPTS_DIR/todo-conformance.sh"
COMMIT_LEDGER="$SCRIPTS_DIR/commit-ledger.sh"
CLAIM_SH="$SCRIPTS_DIR/claim.sh"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"
MD_MERGE="$SKILL_ROOT/meeting/md-merge.py"
APPEND_SH="$SKILL_ROOT/meeting/append.sh"
LOG="${SCAN_ROUTED_LOG:-$HOME/.claude/logs/scan-routed.log}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
# resolve_inbox: RELAY_INBOX verbatim (no migration), else the git-tracked private
# sessions worktree $HOME/.claude/projects/todo-inbox.md — migrating the legacy
# $HOME/.claude/todo-inbox.md once, race-safe under a dedicated flock (id:9fdb). Mirrors
# meeting/append.sh resolve_inbox() so both entry points agree on the store location.
resolve_inbox() {
  if [[ -n "${RELAY_INBOX:-}" ]]; then
    printf '%s\n' "$RELAY_INBOX"
    return 0
  fi
  local legacy="$HOME/.claude/todo-inbox.md"
  local new="$HOME/.claude/projects/todo-inbox.md"
  if [[ -f "$legacy" && ! -f "$new" ]]; then
    mkdir -p "$HOME/.claude/projects"
    (
      flock -x 7
      if [[ -f "$legacy" && ! -f "$new" ]]; then
        mv "$legacy" "$new"
      fi
    ) 7>"$HOME/.claude/projects/.todo-inbox-migrate.lock"
  fi
  printf '%s\n' "$new"
}
INBOX_DEFAULT="$(resolve_inbox)"

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
APPLY=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   APPLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --exclude) shift; [[ $# -gt 0 ]] || { echo "scan-routed.sh: --exclude needs a repo name" >&2; exit 2; }
               exclude["$1"]=1; shift ;;
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
    --*) echo "scan-routed.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) [[ -n "$inbox" ]] && { echo "scan-routed.sh: only one inbox path may be given" >&2; exit 2; }
       inbox="$1"; shift ;;
  esac
done
if [[ "$DRY_RUN" -eq 1 && "$APPLY" -eq 0 ]]; then
  echo "scan-routed.sh: --dry-run requires --apply" >&2; exit 2
fi
inbox="${inbox:-$INBOX_DEFAULT}"
[[ -f "$inbox" ]] || { echo "scan-routed.sh: inbox not found: $inbox" >&2; exit 2; }
[[ -r "$inbox" ]] || { echo "scan-routed.sh: inbox not readable: $inbox" >&2; exit 2; }

# --- registry-parse gate (loud-fail, never silent) -----------------------------
# A malformed relay.toml (e.g. a duplicate key from a concurrent writer) makes the
# strict tomllib parser throw, so own_repos() below would emit NOTHING — leaving the
# own-repo map empty and EVERY routed target falsely reported UNRESOLVED. That silent
# degradation hid a real corruption (dotclaude-skills id:2945, 2026-06-30). Fail loudly.
if [[ -f "$RELAY_TOML" ]]; then
  if ! perr="$(python3 - "$RELAY_TOML" <<'PY' 2>&1
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        tomllib.load(f)
except Exception as e:
    print(f"{type(e).__name__}: {e}"); sys.exit(2)
PY
  )"; then
    echo "scan-routed.sh: ERROR — relay.toml does not parse ($RELAY_TOML): $perr" >&2
    echo "  → the own-repo map would be EMPTY, so every routed target would falsely report" >&2
    echo "    UNRESOLVED. Fix the TOML (commonly a duplicate key) and re-run." >&2
    exit 2
  fi
fi

# --- build the own-repo name→path map ------------------------------------------
declare -A repo_path=()
while IFS=$'\t' read -r rname rpath; do
  [[ -n "$rname" ]] && repo_path["$rname"]="$rpath"
done < <(own_repos)

# resolve_target: relay.toml first, then $SRC_DIR/<name> by existence (id:678e D2).
# Returns the repo path on stdout and exits 0, or exits 1 if unresolvable.
# Only used in --apply mode (slice 1 uses relay.toml only).
resolve_target() {
  local name="$1"
  local p="${repo_path[$name]:-}"
  if [[ -n "$p" ]]; then echo "$p"; return 0; fi
  # Fallback: own repo on disk regardless of relay.toml membership.
  local maybe="$SRC_DIR/$name"
  if [[ -d "$maybe" ]] && { [[ -d "$maybe/.git" ]] || [[ -f "$maybe/.git" ]]; }; then
    echo "$maybe"; return 0
  fi
  return 1
}

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

# --- pass 2: dead letters (+ optional --apply) ---------------------------------
if [[ "$APPLY" -eq 1 ]]; then
  echo "=== routed dead-letters — APPLY mode$([[ "$DRY_RUN" -eq 1 ]] && echo ' (DRY-RUN)') ==="
else
  echo "=== routed dead-letters (target repo never ingested the item) ==="
fi
dead=0
resolved=0
# Read the inbox into memory BEFORE looping: in --apply mode we call `inbox-done`
# (which now DELETES lines, vanish-on-resolve), and a `done < "$inbox"` live-fd loop
# would have its read offset corrupted by the file shrinking mid-iteration — skipping
# later items. Iterating an in-memory snapshot decouples iteration from mutation.
mapfile -t _inbox_lines < "$inbox"
for line in "${_inbox_lines[@]}"; do
  # OPEN conforming routed item only: `- [ ] [target] … <!-- routed:XXXX -->`
  [[ "$line" =~ ^-\ \[\ \]\ \[ ]] || continue
  tok="$(grep -oP '(?<=<!-- routed:)[0-9a-f]{4}(?= -->)' <<<"$line" | head -1 || true)"
  [[ -z "$tok" ]] && continue
  target="$(grep -oP '^- \[ \] \[\K[^\]]+' <<<"$line" | head -1 || true)"
  [[ -z "$target" ]] && continue
  if [[ -n "${exclude[$target]:-}" ]]; then
    log "excluded target=$target routed=$tok"; continue
  fi
  src_name="$(grep -oP '\(from \K[^,)]+' <<<"$line" | head -1 || true)"
  desc="$(sed -E 's/^- \[ \] \[[^]]*\] +//; s/ *\(from [^)]*\)//; s/ *<!-- routed:[0-9a-f]{4} -->.*$//' <<<"$line")"

  # Resolve target → repo path
  if [[ "$APPLY" -eq 1 ]]; then
    tpath="$(resolve_target "$target" || true)"
  else
    tpath="${repo_path[$target]:-}"
  fi

  if [[ -z "$tpath" ]]; then
    echo "UNRESOLVED routed:$tok → [$target] — no repo named '$target' found on disk (add a [repos.$target] block or a # path: override, then re-scan)"
    findings=$((findings+1)); dead=$((dead+1)); continue
  fi

  # Twin = the token appears in the target's TODO or ROADMAP as a `routed:`/`id:`
  # MARKER — anchored, NOT a bare-substring grep. A bare `grep -F "$tok"` (the
  # original) false-matches the HHMM field of meeting-note filename timestamps
  # (`YYYY-MM-DD-HHMM-…`) and any hash/id/number containing those 4 hex chars, so
  # a routed token like `1328`/`0928` reads as "already ingested" when it is not —
  # a SILENT false-clean that under-reports dead letters (observed 2026-06-30:
  # routed:0928 absent in dotclaude-skills, routed:1328 absent in zkm, both masked
  # by meeting-note timestamps). Require the `routed:`/`id:` prefix + a trailing
  # token boundary so only a real twin marker counts.
  if grep -qsE -- "(routed|id):$tok([^0-9a-f]|\$)" "$tpath/TODO.md" "$tpath/ROADMAP.md" 2>/dev/null; then
    # Twin present → the item already LANDED in its target. Under vanish-on-resolve
    # (user decision 2026-06-30) an OPEN inbox line for an already-landed item is just
    # un-drained residue: close the loop and remove it. --apply deletes it now; report
    # mode surfaces it as RESOLVABLE so the drain is visible (NOT a dead letter).
    if [[ "$APPLY" -eq 1 ]]; then
      "$APPEND_SH" inbox-done "$tok" 2>/dev/null || true
      echo "RESOLVED routed:$tok → [$target] (twin present in $tpath; removed from inbox)"
      log "resolved-twinned routed=$tok target=$target path=$tpath"
    else
      echo "RESOLVABLE routed:$tok → [$target] (already landed in $tpath; run --apply to drain from inbox)"
    fi
    resolved=$((resolved+1))
    continue
  fi

  if [[ "$APPLY" -eq 0 ]]; then
    # Report-only (slice 1) — unchanged behaviour
    echo "DEAD-LETTER routed:$tok → [$target] (absent from $tpath/TODO.md+ROADMAP.md): $desc"
    echo "  ↳ to file: add to $tpath/TODO.md — \"- [ ] [INBOUND routed:$tok from ${src_name:-?}] $desc <!-- id:NEW -->\" (mint NEW via \`$APPEND_SH new-id\`), then \`$APPEND_SH inbox-done $tok\`"
    findings=$((findings+1)); dead=$((dead+1))
  else
    # --apply mode: class-A idempotent INBOUND stub write
    target_todo="$tpath/TODO.md"
    if [[ ! -f "$target_todo" ]]; then
      echo "WARNING: no TODO.md in $tpath ([$target]) — skipping" >&2
      log "no-todo-md target=$target path=$tpath routed=$tok"
      findings=$((findings+1)); dead=$((dead+1)); continue
    fi

    # claim.sh peek: skip if a live pool worktree holds this target repo (id:678e D1)
    claim_held=0
    if [[ -x "$CLAIM_SH" ]]; then
      claims_out="$(CLAIM_BASE="${CLAIM_BASE:-$HOME/.config/relay}" "$CLAIM_SH" peek 2>/dev/null || true)"
      if [[ -n "$claims_out" ]]; then
        while IFS= read -r cjson; do
          [[ -z "$cjson" ]] && continue
          crep="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('repo',''))" "$cjson" 2>/dev/null || true)"
          if [[ "$crep" == "$target" ]]; then claim_held=1; break; fi
        done <<<"$claims_out"
      fi
    fi
    if [[ "$claim_held" -eq 1 ]]; then
      echo "SKIP-CLAIM routed:$tok → [$target] — live pool claim holds this repo (will auto-resolve next sweep)"
      log "claim-skip routed=$tok target=$target"
      continue
    fi

    # Mint a collision-free id for the new stub in the TARGET repo's namespace
    new_id="$("$APPEND_SH" new-id "$tpath" 2>/dev/null \
               || python3 -c 'import secrets; print(secrets.token_hex(2))')"
    stub="- [ ] [INBOUND routed:$tok from ${src_name:-?}] $desc <!-- id:$new_id -->"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] would write INBOUND stub for routed:$tok into $target_todo:"
      echo "+ $stub"
      findings=$((findings+1)); dead=$((dead+1))
    else
      # Write via md-merge.py (flock'd atomic append)
      jq -n --arg id "$new_id" --arg line "$stub" \
        '{"updates": [{"id": $id, "line": $line}]}' \
        | python3 "$MD_MERGE" update-ids --file "$target_todo" --allow-new \
        || { log "md-merge failed for $target routed=$tok (non-fatal)"; findings=$((findings+1)); dead=$((dead+1)); continue; }

      echo "APPLIED routed:$tok → [$target] @ $target_todo"
      echo "  ↳ $stub"
      log "applied routed=$tok target=$target path=$target_todo id=$new_id"
      findings=$((findings+1)); dead=$((dead+1))

      # Commit the stub (scoped git add, never git add -A) — non-fatal on error
      "$COMMIT_LEDGER" "$tpath" \
        -m "chore(inbox): ingest routed:$tok from cross-project inbox [id:678e]" \
        "TODO.md" \
        || log "commit-ledger non-fatal error for $target routed=$tok"

      # Mark inbox item as done (best-effort; default inbox path may differ)
      "$APPEND_SH" inbox-done "$tok" 2>/dev/null || true
    fi
  fi
done
[[ "$dead" -eq 0 && "$resolved" -eq 0 ]] && echo "clean (no dead letters; nothing to drain)"
[[ "$dead" -eq 0 && "$resolved" -gt 0 ]] && echo "no dead letters ($resolved already-landed item(s) drained/drainable)"
echo

echo "=== summary ==="
if [[ "$APPLY" -eq 1 && "$DRY_RUN" -eq 1 ]]; then
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved, $resolved twinned-resolvable. APPLY DRY-RUN: no writes performed."
elif [[ "$APPLY" -eq 1 ]]; then
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved (class-A stubs written), $resolved twinned item(s) drained from inbox (vanish-on-resolve)."
else
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved, $resolved twinned-resolvable. REPORT-ONLY (run --apply to write stubs + drain twinned items, id:678e)."
fi
log "inbox=$inbox findings=$findings dead=$dead resolved=$resolved apply=$APPLY dry_run=$DRY_RUN"
exit 0
