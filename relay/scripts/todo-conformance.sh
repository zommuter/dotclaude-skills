#!/usr/bin/env bash
# todo-conformance.sh — a POSITIVE grammar for TODO.md / the shared inbox, the sibling of
# roadmap-lint.sh (id:3441). So NO work hides in a malformed ledger line.
#
# WHY (user directive 2026-06-25, escalated twice): `/relay` is only reliable if every
# TODO/inbox entry is well-formed enough to be SEEN. roadmap-lint.sh already enforces a
# grammar on open ROADMAP items; this does the same for TODO.md (and the inbox). A scan
# of the dotclaude-skills TODO found a bare `placeholder` line and a checkbox-less pointer
# bullet that NO tool saw — exactly the silent backlog this closes.
#
# This script DETECTS (classes: missing-id / orphan). To RESOLVE a finding, apply the
# owner-approved policies P1–P4 in relay/references/todo-conversion-policies.md.
#
# THE TODO GRAMMAR — a top-level (NON-indented) non-blank line is CONFORMING iff it is:
#   • a markdown header            `^#{1,6} …`
#   • an HTML-comment-only line    `^<!-- … -->$`
#   • a well-formed checkbox item  `^- \[[ xX]\] …`
#       └ an OPEN `- [ ]` item must ALSO carry an `<!-- id:XXXX -->` (4-hex) token.
# Indented continuation lines (`^[[:space:]]…`) are NEVER linted (an item's body), exactly
# like roadmap-lint. EXEMPT (never flagged): any line bearing `<!-- lint-ok: <reason> -->`
# or an intentional cross-repo pointer `<!-- ref:XXXX -->`.
#
# CLASSES (output `<class>\t<lineno>\t<text>`):
#   missing-id  an open checkbox item with no id tag — AUTO-FIXABLE (`--fix` mints+appends).
#   orphan      anything else non-conforming (bare prose, a checkbox-less `-`/`*` bullet,
#               a numbered item) — SURFACE ONLY. `--fix` NEVER touches it: converting prose
#               to a task would fabricate work whose intent is unknowable.
#
# INBOX GRAMMAR (`--inbox`): a conforming entry is blank / a `#` comment / a well-formed
#   `- [ ]/[x] [<target>] … <!-- routed:XXXX -->` line; everything else (the token-less
#   prose blocks) is `orphan`. (Inbox auto-RECONCILE on cross-repo activity is the sibling
#   id:678e — this only DETECTS + surfaces here.)
#
# Usage:  todo-conformance.sh [--fix] [--inbox] [--strict] [<path>]
#   <path> default = <cwd repo>/TODO.md (git rev-parse --show-toplevel). REPORT-ONLY
#   (exit 0 with findings); `--strict` → nonzero when findings remain. An unreadable path
#   or unknown flag is a LOUD reject (nonzero). No silent `2>/dev/null` swallow (id:415b/4e14).
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# append.sh (the id mint) lives in meeting/ at the repo root; resolve via the scripts dir.
APPEND_SH="${TODO_CONFORMANCE_APPEND:-$(cd "$SCRIPTS_DIR/../.." && pwd)/meeting/append.sh}"
LOG="${TODO_CONFORMANCE_LOG:-$HOME/.claude/logs/todo-conformance.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s todo-conformance.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

fix=0 inbox=0 strict=0 path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    fix=1; shift ;;
    --inbox)  inbox=1; shift ;;
    --strict) strict=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    --*) echo "todo-conformance.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      [[ -n "$path" ]] && { echo "todo-conformance.sh: only one path may be given (got extra '$1')" >&2; exit 2; }
      path="$1"; shift ;;
  esac
done

if [[ -z "$path" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$root" ]] || { echo "todo-conformance.sh: no path given and cwd is not a git repo" >&2; exit 2; }
  path="$root/TODO.md"
fi
[[ -f "$path" ]] || { echo "todo-conformance.sh: file not found: $path" >&2; exit 2; }
[[ -r "$path" ]] || { echo "todo-conformance.sh: file not readable: $path" >&2; exit 2; }

# id_tag_present <line> : true if the line carries an `<!-- id:XXXX -->` token. Accepts a
# bare 4-hex id AND a suffixed variant (`id:2dea-ref`, `id:abcd-A`) so --fix never
# double-tags an item that already has an id-namespaced token.
id_tag_present() { grep -qP '<!-- id:[0-9a-f]{4}[-a-z0-9]* -->' <<<"$1"; }
# exempt <line> : intentional opt-out (lint-ok) or an intentional cross-repo pointer (ref:).
exempt() { [[ "$1" == *"<!-- lint-ok:"* ]] || grep -qP '<!-- ref:[0-9a-f]{4} -->' <<<"$1"; }

# classify_todo <line> → echoes "" (conforming/skip) | "missing-id" | "orphan"
classify_todo() {
  local l="$1"
  [[ -z "${l//[[:space:]]/}" ]] && return 0            # blank
  [[ "$l" =~ ^[[:space:]] ]] && return 0               # indented continuation — never linted
  exempt "$l" && return 0
  [[ "$l" =~ ^#{1,6}[[:space:]] ]] && return 0         # header
  [[ "$l" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] && return 0   # html-comment-only line
  if [[ "$l" =~ ^-\ \[[\ xX]\]\  ]]; then              # a checkbox item
    if [[ "$l" =~ ^-\ \[\ \]\  ]] && ! id_tag_present "$l"; then
      echo "missing-id"; return 0
    fi
    return 0                                           # conforming item
  fi
  echo "orphan"                                        # anything else top-level
}

# classify_inbox <line> → "" | "orphan"
classify_inbox() {
  local l="$1"
  [[ -z "${l//[[:space:]]/}" ]] && return 0
  [[ "$l" =~ ^[[:space:]] ]] && return 0
  exempt "$l" && return 0
  [[ "$l" =~ ^# ]] && return 0                          # the inbox `#` comment header lines
  # conforming routed entry: checkbox + [target] + routed token
  if [[ "$l" =~ ^-\ \[[\ xX]\]\ \[.+\]\  ]] && grep -qP '<!-- routed:[0-9a-f]{4} -->' <<<"$l"; then
    return 0
  fi
  echo "orphan"
}

findings=0 fixed=0
out_lines=()
declare -a fix_lines=()   # 1-based line numbers needing a minted id

# scan_path: walk $path, populate out_lines[] / findings / fix_lines[]. Tracks the
# heading-as-item state (id:c095) so a `- [ ]/[x]` status sub-line under a
# `## [LANE] … <!-- id -->` heading-item is NOT flagged/auto-fixed (the heading owns
# the id). `$1`=collect-fix (1 → record missing-id line numbers for --fix).
scan_path() {
  local collect_fix="$1" line cls lineno=0 heading_is_item=0
  findings=0; out_lines=(); fix_lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno+1))
    if [[ "$inbox" -eq 0 ]]; then
      if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
        # Heading-as-item (id:c095) is signalled by a relay LANE tag in the heading
        # (`## [ROUTINE] …` / `## [HARD — pool] …`) — the heading IS an executable item
        # whose `- [ ]/[x]` children are status markers. A plain section heading
        # (`## Current`, `## [HUMAN] … <!-- id:1ef9 -->`) is NOT a heading-as-item even
        # if it carries an id for batch-tracking — its children are REAL items that must
        # be linted. So detect on the LANE tag ONLY (matches roadmap-lint), never on a
        # bare id token (the id-token branch wrongly hid real items under id'd sections).
        if [[ "$line" == *'[ROUTINE]'* || "$line" == *'[HARD —'* || "$line" == *'[HARD-'* ]]; then
          heading_is_item=1
        else
          heading_is_item=0
        fi
      elif [[ "$heading_is_item" -eq 1 && "$line" =~ ^-\ \[[\ xX]\]\  ]]; then
        continue   # status sub-line of a heading-as-item — not a separate item
      fi
    fi
    if [[ "$inbox" -eq 1 ]]; then cls="$(classify_inbox "$line")"; else cls="$(classify_todo "$line")"; fi
    [[ -z "$cls" ]] && continue
    findings=$((findings+1))
    out_lines+=("$(printf '%s\t%d\t%s' "$cls" "$lineno" "$line")")
    [[ "$cls" == "missing-id" && "$collect_fix" -eq 1 ]] && fix_lines+=("$lineno")
  done < "$path"
  return 0   # the while's EOF-exit status (1) must not become scan_path's return (set -e)
}

scan_path "$fix"

# --- AUTO-FIX: append a minted id to each well-formed open item missing one --------------
# Only the missing-id class (never orphan). flock the file; mint via append.sh new-id.
if [[ "$fix" -eq 1 && "${#fix_lines[@]}" -gt 0 ]]; then
  lock="$path.conformance.lock"
  exec 9>"$lock"
  if flock -w 30 9; then
    for ln in "${fix_lines[@]}"; do
      # Re-read the line under the lock (line numbers are stable — no prior edit reflows).
      cur="$(sed -n "${ln}p" "$path")"
      # Idempotency: already has a canonical token → nothing to do.
      id_tag_present "$cur" && continue
      # SAFETY: if the line carries a NON-canonical inline id (`(id:560c)` / bare `id:560c`,
      # as some repos use), do NOT mint — that would create a DUPLICATE id. Surface it for a
      # human/handoff to MIGRATE the notation to `<!-- id:XXXX -->` (reusing the same token).
      if grep -qP '\bid:[0-9a-f]{4}\b' <<<"$cur"; then
        echo "todo-conformance.sh: line $ln has a non-canonical inline id — NOT auto-minted (migrate to <!-- id:XXXX --> by hand to avoid a duplicate id)" >&2
        log "skip-inline-id line=$ln file=$path"
        continue
      fi
      tok="$(bash "$APPEND_SH" new-id 2>>"$LOG" | grep -oP '^[0-9a-f]{4}$' | head -1 || true)"
      if [[ -z "$tok" ]]; then
        echo "todo-conformance.sh: could not mint an id for line $ln (append.sh new-id failed)" >&2
        continue
      fi
      esc_tok="$tok"
      sed -i "${ln}s|[[:space:]]*\$| <!-- id:${esc_tok} -->|" "$path"
      fixed=$((fixed+1))
      log "fixed missing-id line=$ln id=$tok file=$path"
    done
    flock -u 9
  else
    echo "todo-conformance.sh: could not acquire fix lock on $path within 30s" >&2
  fi
  exec 9>&-
  rm -f "$lock" 2>/dev/null || true
fi

# --- report -----------------------------------------------------------------------------
if [[ "$findings" -gt 0 ]]; then
  # Re-derive the post-fix surface: missing-id lines that were just fixed are no longer
  # reported (so a --fix run shows only what remains for a human).
  if [[ "$fix" -eq 1 && "$fixed" -gt 0 ]]; then
    scan_path 0   # re-derive the post-fix surface (fixed missing-id lines now have ids)
    echo "todo-conformance: auto-fixed $fixed missing-id item(s) in $path" >&2
  fi
  [[ "${#out_lines[@]}" -gt 0 ]] && printf '%s\n' "${out_lines[@]}"
fi
log "path=$path inbox=$inbox findings=$findings fixed=$fixed strict=$strict"

if [[ "$strict" -eq 1 && "$findings" -gt 0 ]]; then
  exit 1
fi
exit 0
