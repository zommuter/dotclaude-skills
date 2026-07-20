#!/usr/bin/env bash
# append.sh — append a line or block to a meeting-skill registry file
#
# Usage:
#   append.sh -t {discoveries|personas|inbox} -e "line text"
#   append.sh -t {discoveries|personas|inbox} -f entry.txt
#   echo "line" | append.sh -t {discoveries|personas|inbox}
#   append.sh -t inbox --route-to <target-repo> -e "<description>"
#                                         — mint the token INSIDE append.sh, build the
#                                           conforming line, append it, print the token
#                                           (id:34c2 — the caller never builds the marker
#                                           itself, so a reported token is always the one
#                                           actually written).
#   append.sh inbox-done <4-hex-token>   — REMOVE a routed inbox item once adopted
#   append.sh new-id [<root>] | new-ids N [<root>]  — mint collision-free token(s)
#   append.sh scan-ids [<root>]          — list every existing token (sorted unique)
#   append.sh scan-routed-tokens <target-repo>
#                                         — list the routed-namespace collision set for
#                                           <target-repo> (inbox own-markers + the target
#                                           repo's `routed:` citations), bare 4-hex, one
#                                           per line, sorted unique — mirrors scan-ids.
#
# `-t inbox` ALWAYS prints the routed token actually written to disk on success — for
# `--route-to`, the one it minted; for the raw `-e`/`-f`/stdin form, the one parsed back
# out of the appended line. It also VALIDATES: a non-conforming `-t inbox` entry (missing
# the `- [ ]/[x] [<target>] … <!-- routed:XXXX -->` shape) is rejected (non-zero, nothing
# appended) rather than silently written — see docs/meeting-notes/2026-07-17-1450-acc7-*.
# `-t discoveries` / `-t personas` are UNCHANGED: free prose, no validation, no echo.
#
# No git operations — the caller (git-diary-workflow) commits the result.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

# resolve_inbox: emit the path to the cross-project inbox store.
#   * RELAY_INBOX set non-empty  → use it VERBATIM, no migration (injected path is
#     authoritative; hermetic tests rely on this).
#   * else default = $HOME/.claude/projects/todo-inbox.md — the git-tracked private
#     sessions worktree (free history/recovery, stays private). If the LEGACY path
#     $HOME/.claude/todo-inbox.md exists and the new one does NOT, migrate once via `mv`
#     under a dedicated flock, re-checking the condition INSIDE the lock (race-safe).
#   Relocation decided 2026-07-11 (meeting D4, id:9fdb). RELAY_INBOX stays THE injection
#   point — a public-repo script must never hardcode a private repo name.
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
      # Re-check inside the lock: a concurrent resolver may have migrated already.
      if [[ -f "$legacy" && ! -f "$new" ]]; then
        mv "$legacy" "$new"
      fi
    ) 7>"$HOME/.claude/projects/.todo-inbox-migrate.lock"
  fi
  printf '%s\n' "$new"
}

# resolve_target <name>: emit the on-disk path of a routed target repo.
#   Resolution order mirrors scan-routed.sh resolve_target():
#     1. RELAY_TOML `# path: <abspath>` comment under a `[repos.<name>]` block
#     2. ${SRC_DIR:-$HOME/src}/<name>
#   SRC_DIR and RELAY_TOML are injectable for hermetic tests. Exit 1 if unresolvable.
resolve_target() {
  local name="$1"
  local src_dir="${SRC_DIR:-$HOME/src}"
  local toml="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
  if [[ -f "$toml" ]]; then
    local p
    p="$(python3 - "$toml" "$name" <<'PYEOF'
import re, sys
toml_path, want = sys.argv[1], sys.argv[2]
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
found = ""
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1); continue
        if cur == want:
            pm = path_re.match(line)
            if pm:
                found = pm.group(1); break
print(found)
PYEOF
)"
    if [[ -n "$p" ]]; then
      # expand ~ and env vars
      p="${p/#\~/$HOME}"
      printf '%s\n' "$p"
      return 0
    fi
  fi
  local maybe="$src_dir/$name"
  if [[ -d "$maybe" ]]; then
    printf '%s\n' "$maybe"
    return 0
  fi
  return 1
}

# inbox-done <token>: DELETE the routed checkbox line containing routed:<token>
# (vanish-on-resolve, user decision 2026-06-30). The inbox is a LOCAL-ONLY transient
# routing queue; the durable record is the `routed:<token>` breadcrumb in the TARGET
# repo's committed TODO/ROADMAP, so once adopted the inbox copy is pure redundancy —
# keeping a "- [x]" log only bloats the file (and was the source of the bare-token
# substring false-match in scan-routed). No-op exit 0 if the token is not found.
if [[ "${1:-}" == "inbox-done" ]]; then
  token="${2:-}"
  if [[ -z "$token" ]]; then
    echo "Usage: $0 inbox-done <4-hex-token>" >&2; exit 1
  fi
  # Sourced lazily (only for this destructive command, not at top-level import time) so
  # a copy of this script run standalone for -t inbox/-t discoveries (no sibling
  # relay/scripts/ tree, e.g. test_inbox_write_integrity.sh's $TMP/append.sh copy) never
  # trips on a missing lib-anchored-id.sh. token_marker_in_files anchors the twin check
  # (id:3743) — see lib-anchored-id.sh for the false-twin rationale.
  # shellcheck source=../relay/scripts/lib-anchored-id.sh
  source "$SKILL_DIR/../relay/scripts/lib-anchored-id.sh"
  # Honor RELAY_INBOX injection via resolve_inbox (default now the git-tracked private
  # sessions worktree $HOME/.claude/projects/todo-inbox.md, id:9fdb). The inbox path is
  # local-only; never hardcode a private repo name — same convention scan-routed.sh uses,
  # and required for hermetic tests now that inbox-done is destructive.
  inbox="$(resolve_inbox)"
  [[ -f "$inbox" ]] || exit 0

  # --- twin-check guard (id:9fdb) ------------------------------------------------
  # inbox-done is DESTRUCTIVE (vanish-on-resolve) against a LOCAL-ONLY store — a wrong
  # delete is unrecoverable. Before deleting, verify the durable `routed:<token>` twin
  # actually landed in the target repo's committed TODO/ROADMAP; REFUSE otherwise.
  # Find the token's OWN inbox line (anchored on its trailing marker, NOT a substring —
  # do not regress id:411d), extract its [<target>], resolve the repo, and require the
  # literal `routed:<token>` in that repo's TODO.md OR ROADMAP.md.
  own_line="$(python3 - "$inbox" "$token" <<'PYEOF'
import re, sys, pathlib
path, token = pathlib.Path(sys.argv[1]), sys.argv[2]
own_marker = re.compile(r'<!--\s*routed:' + re.escape(token) + r'\s*-->\s*$')
for l in path.read_text().splitlines():
    if own_marker.search(l.rstrip()) and l.lstrip().startswith("- ["):
        print(l)
        break
PYEOF
)"
  if [[ -z "$own_line" ]]; then
    # No inbox line owns this marker → nothing to delete (unchanged no-op contract).
    exit 0
  fi
  # Extract the target repo name from the leading `[<target>]`.
  target="$(printf '%s\n' "$own_line" | grep -oP '^\s*- \[[ x]\] \[\K[^\]]+' | head -1 || true)"
  if [[ -z "$target" ]]; then
    echo "inbox-done: REFUSING to delete routed:$token — could not parse the leading [<target>] from its inbox line:" >&2
    echo "  $own_line" >&2
    echo "  The inbox is local-only and this deletion is unrecoverable; fix the line or use scan-routed.sh --apply." >&2
    exit 3
  fi
  tgt_path="$(resolve_target "$target" || true)"
  twin_found=0
  if [[ -n "$tgt_path" ]]; then
    if token_marker_in_files "$token" "$tgt_path/TODO.md" "$tgt_path/ROADMAP.md"; then
      twin_found=1
    fi
  fi
  if [[ "$twin_found" -ne 1 ]]; then
    echo "inbox-done: REFUSING to delete routed:$token — its durable twin (\`routed:$token\`) was NOT found in [$target]'s TODO.md/ROADMAP.md${tgt_path:+ ($tgt_path)}." >&2
    [[ -z "$tgt_path" ]] && echo "  (target repo '[$target]' could not be resolved on disk via RELAY_TOML # path: or \$SRC_DIR/$target)" >&2
    echo "  This delete is DESTRUCTIVE and UNRECOVERABLE for the local-only inbox store." >&2
    echo "  Safe path: run 'relay/scripts/scan-routed.sh --apply' (writes the twin, then resolves)," >&2
    echo "  or verify+add the routed:$token breadcrumb to the target's TODO/ROADMAP manually first." >&2
    exit 3
  fi

  (
    flock -x 9
    python3 - "$inbox" "$token" <<'PYEOF'
import re, sys, pathlib
path, token = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = path.read_text().splitlines(keepends=True)
# Anchor on the item's OWN trailing marker `<!-- routed:XXXX -->` (optional whitespace),
# not a bare substring — a sibling item's prose may legitimately CITE this token (e.g.
# "the contrast with routed:4fa9 is the signal") while its own marker is different. A
# substring test would delete that citing item too; the inbox is local-only and
# destructive (vanish-on-resolve), so a wrong match is unrecoverable (id:411d).
own_marker = re.compile(r'<!--\s*routed:' + re.escape(token) + r'\s*-->\s*$')
# Vanish: drop the routed checkbox line entirely (any "- [ ]" / "- [x]") whose OWN
# marker matches. Non-checkbox prose / sibling citations are left untouched.
new_lines = [l for l in lines
             if not (own_marker.search(l.rstrip('\n')) and l.lstrip().startswith("- ["))]
path.write_text("".join(new_lines))
PYEOF
  ) 9>"${inbox}.lock"
  exit 0
fi

# Ledger: the file set scanned for existing id:XXXX tokens. Any file class that
# ORIGINATES tokens must be listed here (TODO ledger, meeting notes, relay
# ROADMAP). Files that only cite existing tokens (RELAY_LOG.md, REVIEW_ME.md,
# tests' `# roadmap:` comments) are deliberately excluded.
scan_ids() {
  local root="$1"
  grep -rho 'id:[0-9a-f]\{4\}' \
    "$root/docs/meeting-notes" \
    "$root/TODO.md" \
    "$root/TODO.archive.md" \
    "$root/ROADMAP.md" 2>/dev/null || true
}

# scan-ids: print every existing token (bare 4-hex, one per line, sorted unique).
# Usage: append.sh scan-ids [<root-dir>]
if [[ "${1:-}" == "scan-ids" ]]; then
  ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  scan_ids "$ROOT" | sed 's/^id://' | sort -u
  exit 0
fi

# scan_routed_tokens <target-repo>: the ROUTED-namespace collision set for a --route-to
# mint (id:34c2, D3 fold-in). scan_ids greps `id:[0-9a-f]{4}` over <root> only, so it
# structurally cannot see `routed:XXXX` tokens — a mint that only consulted scan_ids would
# be checking the wrong namespace. The set = this repo's own inbox markers (every `-t
# inbox` entry already written) PLUS the target repo's `routed:` CITATIONS (the same file
# set scan_ids scans, mirrored via resolve_target — never re-derive the path). Bare 4-hex,
# one per line, sorted unique — same output contract as scan-ids.
scan_routed_tokens() {
  local name="$1" inbox tgt
  inbox="$(resolve_inbox)"
  {
    if [[ -f "$inbox" ]]; then
      grep -ho 'routed:[0-9a-f]\{4\}' "$inbox" 2>/dev/null || true
    fi
    # resolve_target may legitimately fail to resolve (unregistered/absent repo) — fall
    # back to the inbox-only set rather than erroring, mirroring inbox-done's tgt_path
    # handling above (append.sh:139-145).
    tgt="$(resolve_target "$name" 2>/dev/null || true)"
    if [[ -n "$tgt" ]]; then
      grep -rho 'routed:[0-9a-f]\{4\}' \
        "$tgt/docs/meeting-notes" \
        "$tgt/TODO.md" \
        "$tgt/TODO.archive.md" \
        "$tgt/ROADMAP.md" 2>/dev/null || true
    fi
  } | sed 's/^routed://' | sort -u
}

# scan-routed-tokens: print the routed-namespace collision set for <target-repo>.
# Usage: append.sh scan-routed-tokens <target-repo>
if [[ "${1:-}" == "scan-routed-tokens" ]]; then
  TARGET_NAME="${2:-}"
  [[ -n "$TARGET_NAME" ]] || { echo "Usage: $0 scan-routed-tokens <target-repo>" >&2; exit 1; }
  scan_routed_tokens "$TARGET_NAME"
  exit 0
fi

# new-children: mint N collision-free child tokens for a parent SPLIT and, in the same
# call, emit the parent's typed `children:` marker so the corpus stops accruing umbrella
# blindspots (id:06e3, typed-ledger-edges 2026-07-10). Prints each child token one per
# line (identical to new-ids), THEN a final line with the marker to attach at the
# parent's terminal id comment — form C: `<!-- children:t1,t2,…,tN --> <!-- id:PARENT -->`.
# Emit-only: writing the marker INTO TODO.md goes through md-merge.py (line-scoped, under
# flock); append.sh never edits ledgers, so no flock is taken here (mint only reads).
# Usage: append.sh new-children N [<root-dir>]
if [[ "${1:-}" == "new-children" ]]; then
  COUNT="${2:-1}"; ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  existing=$(scan_ids "$ROOT")
  emitted=0; toks=()
  while (( emitted < COUNT )); do
    token=$(python3 -c 'import secrets; print(secrets.token_hex(2))')
    if ! grep -qF "id:$token" <<< "${existing}"; then
      echo "$token"
      toks+=("$token")
      existing+=$'\nid:'"$token"  # guard against duplicates within this batch
      (( ++emitted ))
    fi
  done
  csv="$(IFS=,; echo "${toks[*]}")"
  printf '<!-- children:%s -->\n' "$csv"
  exit 0
fi

# new-id / new-ids: emit collision-free random 4-hex token(s) for meeting action items.
# Usage: append.sh new-id  [<root-dir>]     — emit 1 token
#        append.sh new-ids N [<root-dir>]   — emit N tokens, one per line (single scan)
if [[ "${1:-}" == "new-id" || "${1:-}" == "new-ids" ]]; then
  if [[ "${1}" == "new-ids" ]]; then
    COUNT="${2:-1}"; ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  else
    COUNT=1;        ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  fi
  existing=$(scan_ids "$ROOT")
  emitted=0
  while (( emitted < COUNT )); do
    token=$(python3 -c 'import secrets; print(secrets.token_hex(2))')
    if ! grep -qF "id:$token" <<< "${existing}"; then
      echo "$token"
      existing+=$'\nid:'"$token"  # guard against duplicates within this batch
      (( ++emitted ))
    fi
  done
  exit 0
fi

target=""
entry=""
entry_file=""
route_to=""

# Manual parse (not getopts) so `-t inbox --route-to <repo> -e "<desc>"` (id:34c2, form B)
# can sit alongside the original short flags without getopts' lack of long-option support.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) target="${2:-}"; shift 2 ;;
    -e) entry="${2:-}"; shift 2 ;;
    -f) entry_file="${2:-}"; shift 2 ;;
    --route-to) route_to="${2:-}"; shift 2 ;;
    *) echo "Usage: $0 -t {discoveries|personas|inbox} [-e text | -f file] [--route-to <target-repo>]" >&2; exit 1 ;;
  esac
done

case "$target" in
  discoveries) dest="$SKILL_DIR/discoveries.md" ;;
  personas)    dest="$SKILL_DIR/personas.md" ;;
  inbox)       dest="$(resolve_inbox)" ;;
  "")          echo "Error: -t is required" >&2; exit 1 ;;
  *)           echo "Error: -t must be 'discoveries', 'personas', or 'inbox'" >&2; exit 1 ;;
esac

if [[ -n "$route_to" && "$target" != "inbox" ]]; then
  echo "Error: --route-to is only valid with -t inbox" >&2
  exit 1
fi

if [[ -n "$entry_file" ]]; then
  entry_file="$(readlink -f "$entry_file")"
  entry="$(cat "$entry_file")"
  rm -- "$entry_file"
fi

if [[ -z "$entry" ]]; then
  entry="$(cat)"
fi

if [[ -z "$entry" ]]; then
  echo "Error: no content provided (use -e, -f, or stdin)" >&2
  exit 1
fi

# --- (B) mint-inside: `-t inbox --route-to <target-repo>` --------------------------------
# append.sh mints the token itself and builds the WHOLE conforming line — the caller only
# supplies the description, never the marker, so there is no interpolation step for a
# caller to get wrong (the root cause of the acc7 incident). Collision-checked against the
# ROUTED namespace (scan_routed_tokens), not scan_ids's `id:` namespace.
if [[ -n "$route_to" ]]; then
  if [[ "$entry" == *'<!-- routed:'*'-->'* ]]; then
    echo "Error: --route-to builds the routed:XXXX marker itself — the description must not contain one:" >&2
    echo "  $entry" >&2
    exit 1
  fi
  existing_routed="$(scan_routed_tokens "$route_to")"
  mint_token=""
  while :; do
    cand="$(python3 -c 'import secrets; print(secrets.token_hex(2))')"
    if ! grep -qxF "$cand" <<<"$existing_routed"; then
      mint_token="$cand"
      break
    fi
  done
  line="- [ ] [$route_to] $entry <!-- routed:$mint_token -->"
  (
    flock -x 9
    printf '\n%s\n' "$line" >> "$dest"
  ) 9>"${dest}.lock"
  printf '%s\n' "$mint_token"
  exit 0
fi

# --- (A) validate on write: `-t inbox`, raw -e/-f/stdin form ------------------------------
# Reuse todo-conformance.sh's `--inbox` grammar (classify_inbox) rather than re-deriving the
# conforming-form regex here (CLAUDE.md: no NIH) — run the entry through the SAME classifier
# the repo's lint already uses, via a throwaway single-line file, and reject on "orphan".
if [[ "$target" == "inbox" ]]; then
  conf_sh="$(cd "$SKILL_DIR/.." && pwd)/relay/scripts/todo-conformance.sh"
  # id:bbb2 — fail LOUDLY when the relay skill's todo-conformance.sh is absent (meeting installed
  # without a sibling relay/). Without this probe the command substitution below dies with a bare
  # exit 127 and `set -e` DISCARDS its "No such file or directory" diagnostic (a silent swallow —
  # banned by CLAUDE.md no-silent-swallow). Probe FIRST so the missing runtime dependency (the
  # id:34c2 meeting→relay coupling) is named, and nothing is appended.
  if [[ ! -x "$conf_sh" ]]; then
    echo "Error: -t inbox validation requires the relay skill's todo-conformance.sh, which is missing or not executable:" >&2
    echo "  $conf_sh" >&2
    echo "Install the relay skill (e.g. 'make install-relay') so the inbox conforming-form check can run. NOTHING was appended (fail-closed — id:bbb2)." >&2
    exit 3
  fi
  tmp_check="$(mktemp)"
  printf '%s\n' "$entry" > "$tmp_check"
  conf_out="$("$conf_sh" --inbox "$tmp_check" 2>&1)"
  rm -- "$tmp_check"
  if grep -q $'^orphan\t' <<<"$conf_out"; then
    echo "Error: -t inbox entry does not match the conforming inbox form and was NOT appended:" >&2
    echo "  $entry" >&2
    echo "Expected form: - [ ]/[x] [<target-repo>] <description> <!-- routed:XXXX -->" >&2
    exit 1
  fi
fi

# Always prepend a blank line — defensive against missing trailing newline
# flock prevents concurrent calls from interleaving lines
(
  flock -x 9
  printf '\n%s\n' "$entry" >> "$dest"
) 9>"${dest}.lock"

# --- (C) echo what was written: `-t inbox`, raw -e/-f/stdin form --------------------------
# stdout is the token PARSED BACK OUT of the line just appended — never the caller's own
# variable — so `filed routed:$(append.sh …)` cannot lie about what landed on disk.
if [[ "$target" == "inbox" ]]; then
  written_token="$(grep -oP '<!--\s*routed:\K[0-9a-f]{4}(?=\s*-->)' <<<"$entry" | tail -1)"
  [[ -n "$written_token" ]] && printf '%s\n' "$written_token"
fi
