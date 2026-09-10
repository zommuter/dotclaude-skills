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
#
# EXIT STATUS: 0 = the scan ran (findings alone do NOT make it nonzero -- it is a report);
#   1/2 = misuse; 4 = --apply asked `append.sh inbox-done` to drain a line and the drain
#   did NOT succeed (id:0246 D3). A failed drain is a state change that did not happen, so
#   it must be visible without parsing prose.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFORMANCE="$SCRIPTS_DIR/todo-conformance.sh"
COMMIT_LEDGER="$SCRIPTS_DIR/commit-ledger.sh"
CLAIM_SH="$SCRIPTS_DIR/claim.sh"
# token_marker_in_files — the shared OWN-MARKER twin predicate (id:3add, tightened by
# id:c97c). Sourced, never re-implemented: this script and `append.sh inbox-done` must
# ask the same question, or a stub this script writes is refused by the drain that follows.
# shellcheck source=./lib-anchored-id.sh
source "$SCRIPTS_DIR/lib-anchored-id.sh"
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
# Scratch file for the shared own-token extractor's stderr (id:0246). Created once, reaped
# on exit; see the capture in the dead-letter loop for why it is not `2>>"$LOG"`.
OWN_ERR="$(mktemp)"
trap '[ -e "$OWN_ERR" ] && rm -- "$OWN_ERR"' EXIT
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
# id:02fe -- a non-bare-key section name (zom.fi) is written quoted; tomllib returns it
# UNQUOTED, so strip the delimiters here or the two never agree. chr(34)/chr(39) avoid
# embedding a quote character in this shell heredoc.
def _sect_name(raw):
    n = raw.strip()
    if len(n) >= 2 and n[0] == n[-1] and n[0] in (chr(34), chr(39)):
        return n[1:-1]
    return n
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = _sect_name(m.group(1)); continue
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
# failed_drains (id:0246 D3): a drain that did not happen. It reaches the SUMMARY and the
# EXIT STATUS, because the only thing worse than a failed drain is a failed drain reported
# as a clean run.
failed_drains=0
# refusals (id:0246 D4): lines this pass REFUSED to attribute (multi-marker / indented).
# They are neither dead letters nor resolvable -- but a pass that refused to ask the
# question must never print `clean`, which is a claim about an answer it does not have.
refusals=0
# Read the inbox into memory BEFORE looping: in --apply mode we call `inbox-done`
# (which now DELETES lines, vanish-on-resolve), and a `done < "$inbox"` live-fd loop
# would have its read offset corrupted by the file shrinking mid-iteration — skipping
# later items. Iterating an in-memory snapshot decouples iteration from mutation.
mapfile -t _inbox_lines < "$inbox"
for line in "${_inbox_lines[@]}"; do
  # OPEN routed item only: `- [ ] [target] … <!-- routed:XXXX -->`. Leading whitespace is
  # ALLOWED THROUGH on purpose (id:0246 D5): an indented entry used to be dropped here
  # without a word, which is the silent no-op this item exists to kill. The shared
  # extractor below refuses it LOUDLY and it is reported as a finding.
  [[ "$line" =~ ^[[:space:]]*-\ \[\ \]\ \[ ]] || continue
  # id:0246 -- the shared extractor, not a bare `head -1` over every anchored marker on
  # the line. `head -1` attributed a line to whichever token it CITES first in prose
  # (both live inbox items do this), never its own trailing marker; inbox_line_own_token
  # tolerates trailing prose (id:798d) and REFUSES on a multi-marker line (id:6059).
  #
  # A REFUSAL IS A FINDING, not a `continue` (id:0246 D4): it used to `log; continue` with
  # nothing on stdout and no findings++, so a line the tool REFUSED TO ASK ABOUT could
  # vanish into `clean (no dead letters; nothing to drain)` -- a false clean, which is
  # worse than the wrong answer it replaced.
  own_rc=0
  # stderr goes to a scratch file, then into the log via log() -- NOT `2>>"$LOG"`, whose
  # redirection would itself fail (and be misread as "this line owns nothing") if the log
  # directory could not be created, and NOT `2>/dev/null`, which is the banned swallow.
  own_tok_out="$(inbox_line_own_token "$line" "$inbox" 2>"$OWN_ERR")" || own_rc=$?
  [[ -s "$OWN_ERR" ]] && log "own-token-stderr: $(tr '\n' ' ' < "$OWN_ERR")"
  if [[ $own_rc -eq "$OWN_ID_AMBIGUOUS" ]]; then
    echo "AMBIGUOUS-OWNER inbox line carries MORE THAN ONE anchored routed marker, so no verdict can be attributed to it (id:6059/id:0246); it can never be drained until the quoted marker is de-literalised: $line"
    log "ambiguous-own-token line=$line"
    findings=$((findings+1)); refusals=$((refusals+1)); continue
  elif [[ $own_rc -eq "${INBOX_LINE_INDENTED:-4}" ]]; then
    echo "INDENTED inbox line is not a conforming entry (must start at column 0) and no resolver can own it (id:0246 D5): $line"
    log "indented-inbox-line line=$line"
    findings=$((findings+1)); refusals=$((refusals+1)); continue
  elif [[ $own_rc -ne 0 ]]; then
    continue
  fi
  tok="${own_tok_out#routed:}"
  [[ -z "$tok" ]] && continue
  target="$(head -1 < <(grep -oP '^- \[ \] \[\K[^\]]+' <<<"$line") || true)"
  [[ -z "$target" ]] && continue
  if [[ -n "${exclude[$target]:-}" ]]; then
    log "excluded target=$target routed=$tok"; continue
  fi
  src_name="$(head -1 < <(grep -oP '\(from \K[^,)]+' <<<"$line") || true)"
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

  # Twin = the token is the OWN MARKER of some line in the target's TODO, ROADMAP, or
  # either ledger's archive (id:1d83 -- an archived closed item still carries its
  # `routed:XXXX`/`id:XXXX` breadcrumb and is a durable record of landing; archive-done.sh
  # archives aggressively enough that an undated same-session close can be swept before
  # this check ever runs) — either an `<!-- routed:XXXX -->`/`<!-- id:XXXX -->` HTML
  # comment, or the leading `[INBOUND routed:XXXX …]` tag of the ingest stub this very
  # script writes. Delegated to the shared `token_marker_in_files` primitive
  # (lib-anchored-id.sh, id:3add) — one predicate for this check and for `append.sh
  # inbox-done`'s id:9fdb refusal guard, which must agree or a successful write is
  # followed by a refused drain.
  #
  # Two false-match classes it rejects, both of which caused real damage:
  #   * a BARE SUBSTRING (the original `grep -F "$tok"`) matches the HHMM field of a
  #     meeting-note filename (`YYYY-MM-DD-HHMM-…`) or any longer hash containing those
  #     4 hex chars, silently UNDER-reporting dead letters (2026-06-30: routed:0928 in
  #     dotclaude-skills, routed:1328 in zkm, both masked by note timestamps);
  #   * a PROSE CITATION of a sibling item's token (`… the sibling item \`routed:XXXX\``)
  #     matched the prefix-anchored successor, so this loop DELETED inbox items it had
  #     never filed — three of them on 2026-08-14, recovered by hand from git (id:c97c).
  #     That one is self-inflicted and INTRA-RUN: the stub written for item A carries A's
  #     citation of B, and the check below re-reads the file on every iteration (grep
  #     re-opens it), so B is then read as "landed". The per-iteration fresh read is
  #     deliberately KEPT — it is what makes a concurrent/earlier write visible, and with
  #     an ownership-anchored predicate the citation no longer registers.
  if token_marker_in_files "$tok" "$tpath/TODO.md" "$tpath/ROADMAP.md" \
    "$tpath/TODO.archive.md" "$tpath/ROADMAP.archive.md"; then
    # Twin present → the item already LANDED in its target. Under vanish-on-resolve
    # (user decision 2026-06-30) an OPEN inbox line for an already-landed item is just
    # un-drained residue: close the loop and remove it. --apply deletes it now; report
    # mode surfaces it as RESOLVABLE so the drain is visible (NOT a dead letter).
    if [[ "$APPLY" -eq 1 ]]; then
      # id:0246 (D3, case 10) -- the drain's own exit status is PROPAGATED, and a FAILED
      # drain is NOT counted as resolved. The prior `2>/dev/null || true` swallowed both a
      # nothing-to-delete no-op (exit 0, line survives) and a refusal (nonzero), so this
      # script printed a false `RESOLVED` in either case; and `resolved++` sat OUTSIDE the
      # branch, so even after the message was withheld the SUMMARY still reported the item
      # as drained and the run still exited 0. Counting a failure as a success is the same
      # defect one layer up (id:4347 no-silent-swallow, id:d35a silent no-op).
      done_rc=0
      "$APPEND_SH" inbox-done "$tok" 2>"$OWN_ERR" || done_rc=$?
      [[ -s "$OWN_ERR" ]] && log "inbox-done-stderr routed=$tok: $(tr '\n' ' ' < "$OWN_ERR")"
      if [[ $done_rc -eq 0 ]]; then
        echo "RESOLVED routed:$tok → [$target] (twin present in $tpath; removed from inbox)"
        log "resolved-twinned routed=$tok target=$target path=$tpath"
        resolved=$((resolved+1))
      else
        echo "STILL-PRESENT routed:$tok → [$target] (twin present in $tpath, but the drain did NOT succeed -- rc=$done_rc; the inbox line survives, see $LOG)"
        log "resolved-twinned-drain-failed routed=$tok target=$target path=$tpath rc=$done_rc"
        failed_drains=$((failed_drains+1)); findings=$((findings+1))
      fi
    else
      echo "RESOLVABLE routed:$tok → [$target] (already landed in $tpath; run --apply to drain from inbox)"
      resolved=$((resolved+1))
    fi
    continue
  fi

  if [[ "$APPLY" -eq 0 ]]; then
    # Report-only (slice 1) — unchanged behaviour
    echo "DEAD-LETTER routed:$tok → [$target] (absent from $tpath/TODO.md+ROADMAP.md and their archives): $desc"
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

      # Mark inbox item as done. Same id:0246 D3 treatment as the twinned-drain call
      # above: the status is propagated and a failure is surfaced, not swallowed. The
      # stub HAS landed at this point, so a failed drain is not fatal to the ingest --
      # but it leaves an un-drained inbox line that a "clean" report would deny.
      done_rc=0
      "$APPEND_SH" inbox-done "$tok" 2>"$OWN_ERR" || done_rc=$?
      [[ -s "$OWN_ERR" ]] && log "inbox-done-stderr routed=$tok: $(tr '\n' ' ' < "$OWN_ERR")"
      if [[ $done_rc -ne 0 ]]; then
        echo "  ↳ STILL-PRESENT routed:$tok -- the stub landed but the inbox drain did NOT succeed (rc=$done_rc; see $LOG)"
        log "post-stub-drain-failed routed=$tok target=$target rc=$done_rc"
        failed_drains=$((failed_drains+1))
      fi
    fi
  fi
done
[[ "$dead" -eq 0 && "$resolved" -eq 0 && "$failed_drains" -eq 0 && "$refusals" -eq 0 ]] && echo "clean (no dead letters; nothing to drain)"
[[ "$dead" -eq 0 && "$resolved" -gt 0 ]] && echo "no dead letters ($resolved already-landed item(s) drained/drainable)"
[[ "$refusals" -gt 0 ]] && echo "NOT CLEAN: $refusals inbox line(s) could not be ATTRIBUTED at all (see AMBIGUOUS-OWNER/INDENTED above) -- their dead-letter question was never asked"
[[ "$failed_drains" -gt 0 ]] && echo "NOT CLEAN: $failed_drains drain(s) FAILED -- those inbox lines are still present"
echo

echo "=== summary ==="
fd_note=""
[[ "$refusals" -gt 0 ]] && fd_note=" $refusals unattributable line(s) REFUSED."
[[ "$failed_drains" -gt 0 ]] && fd_note="$fd_note $failed_drains FAILED drain(s) -- inbox line(s) still present."
if [[ "$APPLY" -eq 1 && "$DRY_RUN" -eq 1 ]]; then
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved, $resolved twinned-resolvable. APPLY DRY-RUN: no writes performed.$fd_note"
elif [[ "$APPLY" -eq 1 ]]; then
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved (class-A stubs written), $resolved twinned item(s) drained from inbox (vanish-on-resolve).$fd_note"
else
  echo "scan-routed: $findings finding(s) — $dead dead-letter/unresolved, $resolved twinned-resolvable. REPORT-ONLY (run --apply to write stubs + drain twinned items, id:678e).$fd_note"
fi
log "inbox=$inbox findings=$findings dead=$dead resolved=$resolved refusals=$refusals failed_drains=$failed_drains apply=$APPLY dry_run=$DRY_RUN"
# EXIT STATUS (id:0246 D3): findings alone stay exit 0 -- this is a report. A FAILED DRAIN
# is different in kind: --apply was asked to change the store and did not, so the caller
# must be able to tell without parsing prose. 4 keeps it distinct from the misuse exits.
[[ "$failed_drains" -gt 0 ]] && exit 4
exit 0
