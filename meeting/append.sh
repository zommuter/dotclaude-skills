#!/usr/bin/env bash
# append.sh — append a line or block to a meeting-skill registry file
#
# Usage:
#   append.sh -t {discoveries|personas|inbox} -e "line text"
#   append.sh -t {discoveries|personas|inbox} -f entry.txt
#   echo "line" | append.sh -t {discoveries|personas|inbox}
#   append.sh -t personas [--replace] -e "line text"
#                                         — re-registering an already-listed **Name** EXTENDS
#                                           its entry losslessly (union of old + new text,
#                                           routed:81b8); `--replace` opts in to discarding
#                                           the prior text instead.
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

# lock_path_for <dest>: the flock file for a destination, derived from the RESOLVED target.
#
# id:244f — SKILL_DIR is `dirname "$0"`, i.e. the INVOCATION directory, so `$dest` for the
# same underlying registry differs between the install path
# (~/.claude/skills/meeting/personas.md, itself a per-file symlink) and the canonical path
# (~/src/dotclaude-skills/meeting/personas.md). Locking on the unresolved `"${dest}.lock"`
# therefore created TWO independent locks for ONE file (both were found on disk 2026-08-13),
# so an install-path writer and a repo-path writer were never mutually excluded — and
# personas.md is `merge=union`, where an interleaved write is unrecoverable.
#
# Canonicalising with `readlink -f` collapses both to one lock beside the resolved target.
# `readlink -f` succeeds for a not-yet-existing FILE as long as its directory exists (it
# canonicalises the parent), which is the "dest does not exist yet" case; if even that
# fails we fall back to the literal path rather than skipping the lock.
lock_path_for() {
  local p="$1" resolved
  resolved="$(readlink -f -- "$p" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || resolved="$p"
  printf '%s\n' "${resolved}.lock"
}

# --- post-write read-back (id:729c / routed:ece6) -----------------------------------------
# Every append path used to be a bare `printf … >> "$dest"` inside a flock'd subshell, after
# which the script echoed a routed token and exited 0 WITHOUT ever reading the file back. So
# a write that reached nothing — a store that swallows it, a redirect that went elsewhere, a
# concurrent non-flock writer clobbering the file (id:2be7 / routed:8eb5) — produced a
# perfect success: exit 0 plus a token receipt, and an inbox entry that exists nowhere. The
# inbox is vanish-on-resolve, so a loss BEFORE adoption leaves no trace in either ledger and
# no scanner can detect it. Hence: append, then verify the bytes are there, INSIDE the same
# lock, and fail LOUDLY if they are not (CLAUDE.md no-silent-swallow, id:4347).
#
# NOTE (verified 2026-08-14, before writing this): routed:ece6 reported `-t inbox` as
# "silently no-opping on some payloads", citing `git log -S routed:d4b3 -- todo-inbox.md`
# being empty. That premise is FALSE — d4b3 WAS written; the auto-ingest consumed and
# drained it inside one hourly-backup window (dotclaude-skills 502b8b5, "chore(inbox):
# ingest routed:d4b3", 10:28, between the 10:02 and 11:02 store commits), so the token never
# appeared in a commit. An add-then-drain cycle is invisible to `git log -S` on that store.
# No payload-dependent skip was reproducible. The read-back below is built anyway: it is the
# acceptance criterion of the item, and it closes the real (observed) clobber class id:2be7.

# verify_appended <dest> <block>: 0 iff <block> is present verbatim in <dest>.
# The whole block, not its first line — a partially-written multi-line entry is exactly the
# clobber shape a first-line grep would call success.
verify_appended() {
  local dest="$1" block="$2"
  APPEND_VERIFY_BLOCK="$block" python3 - "$dest" <<'PYEOF'
import os, sys, pathlib
path = pathlib.Path(sys.argv[1])
block = os.environ["APPEND_VERIFY_BLOCK"]
try:
    data = path.read_text(encoding="utf-8", errors="replace")
except OSError:
    sys.exit(1)
sys.exit(0 if block in data else 1)
PYEOF
}

# write_failed <dest> <block> <rc>: LOUD, non-zero, names the payload and the store.
# Nothing is echoed on stdout — stdout is the caller's receipt (id:34c2 contract C) and must
# stay silent when there is nothing to receipt.
write_failed() {
  local dest="$1" block="$2" rc="$3"
  {
    echo "Error: append.sh FAILED to write the entry — it is NOT in the store (post-write read-back, id:729c)."
    echo "  store: $dest"
    echo "  entry:"
    printf '%s\n' "$block" | sed 's/^/    /'
    echo "  (append or read-back exit status: $rc)"
    echo "  NOTHING was filed and no token was printed — do NOT record this as routed/filed."
    echo "  Check the store is writable, and that no other session is writing it without the flock (id:2be7)."
  } >&2
  exit 4
}

# append_verified <dest> <lock> <block>: the ONLY sanctioned append. Takes the lock, appends,
# reads back under the SAME lock, and fails loudly if the bytes are not there.
append_verified() {
  local dest="$1" lock="$2" block="$3" rc=0
  (
    flock -x 9
    printf '\n%s\n' "$block" >> "$dest"
    verify_appended "$dest" "$block"
  ) 9>"$lock" || rc=$?
  (( rc == 0 )) || write_failed "$dest" "$block" "$rc"
}

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
  ) 9>"$(lock_path_for "$inbox")"
  exit 0
fi

# Ledger: the file set scanned for existing id:XXXX tokens. Any file class that
# ORIGINATES tokens must be listed here (TODO ledger, meeting notes, relay
# ROADMAP). Files that only cite existing tokens (RELAY_LOG.md, REVIEW_ME.md,
# tests' `# roadmap:` comments) are deliberately excluded.
#
# BOTH ledger archives are scanned, and the symmetry is load-bearing (id:3262). Archiving
# an item does NOT un-originate its token: an id that has moved into TODO.archive.md or
# ROADMAP.archive.md is still spoken for, and re-minting it creates a within-repo collision.
# ROADMAP.archive.md was missing here until 2026-08-13 while its TODO twin was present, so
# any id archived out of ROADMAP.md went invisible to the minter and could be handed out
# again — confirmed live in zkm-pdf, whose ROADMAP.archive.md:76 and :115 are two DISTINCT
# top-level items both tagged <!-- id:1a30 -->.
scan_ids() {
  local root="$1"
  # 2>/dev/null is deliberate and bounded (id:4347 no-silent-swallow): not every repo is
  # relay-managed, so a missing ROADMAP.md / ROADMAP.archive.md / TODO.archive.md /
  # docs-meeting-notes is a NORMAL state, not an error. The only thing suppressed is grep's
  # per-path "No such file or directory"; a token that exists in a readable file is never
  # hidden by it, and an unreadable-but-present file still yields grep's own nonzero exit.
  grep -rho 'id:[0-9a-f]\{4\}' \
    "$root/docs/meeting-notes" \
    "$root/TODO.md" \
    "$root/TODO.archive.md" \
    "$root/ROADMAP.md" \
    "$root/ROADMAP.archive.md" 2>/dev/null || true
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
# personas re-registration mode. Default "extend" = LOSSLESS union with the existing entry
# (routed:81b8). "replace" is the explicit opt-in for a deliberate rewrite — the only way to
# discard prior lens text, and it must be asked for.
persona_mode="extend"

# Manual parse (not getopts) so `-t inbox --route-to <repo> -e "<desc>"` (id:34c2, form B)
# can sit alongside the original short flags without getopts' lack of long-option support.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) target="${2:-}"; shift 2 ;;
    -e) entry="${2:-}"; shift 2 ;;
    -f) entry_file="${2:-}"; shift 2 ;;
    --route-to) route_to="${2:-}"; shift 2 ;;
    --replace) persona_mode="replace"; shift ;;
    *) echo "Usage: $0 -t {discoveries|personas|inbox} [-e text | -f file] [--route-to <target-repo>] [--replace]" >&2; exit 1 ;;
  esac
done

case "$target" in
  discoveries) dest="$SKILL_DIR/discoveries.md" ;;
  personas)    dest="$SKILL_DIR/personas.md" ;;
  inbox)       dest="$(resolve_inbox)" ;;
  "")          echo "Error: -t is required" >&2; exit 1 ;;
  *)           echo "Error: -t must be 'discoveries', 'personas', or 'inbox'" >&2; exit 1 ;;
esac

# One lock per underlying file, regardless of invocation path (id:244f). Derived ONCE here
# so every write path below (route-to append, personas extend, plain append) shares it.
dest_lock="$(lock_path_for "$dest")"

if [[ -n "$route_to" && "$target" != "inbox" ]]; then
  echo "Error: --route-to is only valid with -t inbox" >&2
  exit 1
fi

if [[ "$persona_mode" == "replace" && "$target" != "personas" ]]; then
  echo "Error: --replace is only valid with -t personas" >&2
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
  # Verified append (id:729c): the token is echoed ONLY after the line is read back off disk,
  # so the mint-inside receipt can never name a line that is not in the store.
  append_verified "$dest" "$dest_lock" "$line"
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

# --- personas: EXTEND an already-registered name instead of appending a duplicate -----
# id:069b: .gitattributes sets `personas.md merge=union`, which can never reconcile a
# re-registration on its own (union keeps both sides forever) — the writer is the only
# place reconciliation can happen. `append.sh -t personas` is the sole sanctioned writer
# (see the usage note above), so this is a normal write path, not a rare edge case.
#
# TWO defects were fixed here on 2026-08-13 (both observed live 2026-08-12):
#
# routed:81b8 — the original awk was a whole-line REPLACE
#     index($0, needle) > 0 && !done { print newline; done=1; next }
#   which printed the caller's line and `next`ed past the old one, SILENTLY DISCARDING all
#   prior lens text unless the caller happened to retype it (exit 0, stderr still claiming
#   "extending"). Confirmed loss: Gil's RELEASE-TAG-PUSH-SEMANTICS, Hank's
#   PROMPT-PROSE-AS-CACHE, Dex's KIND-vs-ARITY text (repaired by hand in 624a7f8). Because
#   personas.md is `merge=union`, a lost fragment can NEVER be recovered by a later merge.
#   Fixed by making the extend LOSSLESS (merge_persona_line below): the surviving entry is
#   the UNION of old and new. `--replace` is the explicit opt-in for a deliberate rewrite —
#   destructive by request, never by default.
#
# routed:96da — the original wrote `tmp=$(mktemp)` then `mv -- "$tmp" "$dest"`. The installed
#   $dest (~/.claude/skills/meeting/personas.md) is a SYMLINK to the canonical checkout, so
#   the mv REPLACED the symlink with a detached regular file: the canonical file never got
#   the edit, the registry forked silently, perms dropped 0644→0600 and the write crossed
#   filesystems. Fixed by writing to the RESOLVED target — see id:00b1 below for the final
#   shape (the intermediate fix, an in-place `Path.write_text()`, followed the symlink but
#   gave up atomicity).
#
# id:00b1 — that in-place write is open-for-TRUNCATE-then-write, so a concurrent reader can
#   observe a PARTIAL registry rather than a stale-but-whole one — destructive rather than
#   merely lossy, on a `merge=union` file. Fixed by writing a temp file IN THE SAME DIRECTORY
#   as the resolved target and `os.replace()`ing onto that resolved path: one atomic rename,
#   no filesystem hop, and the symlink survives because the LINK is never the rename target.
#   The target's mode is copied onto the temp file first (mkstemp defaults to 0600 — the
#   exact perms regression routed:96da suffered).
#
# id:44c5 — the target line was located by SUBSTRING (`grep -qF "**Name**"` / `needle in
#   line`), so a persona whose prose legitimately CITES another persona's bolded name got
#   that other persona's merged text written into it. Fixed by anchoring on the registry's
#   own definition shape — `- <emoji> **Name** — lens…`, i.e. a list item whose FIRST bolded
#   token is the name (`PERSONA_DEF_RE` below, mirrored in the bash pre-check). A prose
#   citation is never the first bold on its line, so it can no longer be picked.
if [[ "$target" == "personas" ]]; then
  pname="$(grep -oP '\*\*\K[A-Za-z]+(?=\*\*)' <<<"$entry" | head -1)"
  # Definition-anchored (id:44c5): a list item whose FIRST `**bold**` token is this name.
  # `[^*]*` before the name is what forbids an earlier bold on the same line, so a prose
  # citation of `**Name**` inside someone else's entry does not match. Must stay in sync
  # with PERSONA_DEF_RE in the python block below.
  if [[ -n "$pname" ]] && grep -qP -- "^\s*-\s+[^*]*\*\*${pname}\*\*" "$dest"; then
    if [[ "$persona_mode" == "replace" ]]; then
      echo "persona '$pname' already registered, REPLACING its entry (--replace: prior text is discarded) (routed:81b8)" >&2
    else
      echo "persona '$pname' already registered, extending instead of appending a duplicate (id:069b)" >&2
    fi
    (
      flock -x 9
      # Guard the symlink topology explicitly (routed:96da): a plain regular file at the
      # INSTALL path where a symlink is expected means an earlier detaching write already
      # forked the registry. Say so — do not silently write into the fork.
      if [[ ! -L "$dest" && "$dest" == "$HOME/.claude/skills/"* ]]; then
        echo "warning: $dest is a regular file, not a symlink into the dotclaude-skills checkout — the registry may already be FORKED (routed:96da); reconcile it against \$dest's canonical twin." >&2
      fi
      # Atomic write onto the RESOLVED target (routed:96da + id:00b1): temp file in the
      # target's OWN directory, mode copied over, then one os.replace(). The symlink is
      # followed (never replaced), there is no /tmp→home hop, and no reader can observe a
      # half-written registry.
      PERSONA_NAME="$pname" PERSONA_NEW="$entry" PERSONA_MODE="$persona_mode" \
      python3 - "$dest" <<'PYEOF'
import os, re, stat, sys, tempfile, pathlib

path = pathlib.Path(sys.argv[1])
name = os.environ["PERSONA_NAME"]
new  = os.environ["PERSONA_NEW"].strip()
mode = os.environ.get("PERSONA_MODE", "extend")

# id:44c5 — the line that DEFINES the persona: a list item whose FIRST bolded token is the
# name (`- <emoji> **Name** — lens…`, the registry's documented format). A prose citation of
# another persona's name is never the first bold on its line, so it is never targeted.
# Mirrors the bash-side pre-check above; keep the two in sync.
PERSONA_DEF_RE = re.compile(r"^\s*-\s+[^*]*\*\*" + re.escape(name) + r"\*\*")

def squash(s):
    return re.sub(r"\s+", " ", s).strip()

def merge_persona_line(old, new):
    """LOSSLESS union of an existing registry entry and a re-registration (routed:81b8).

    Three cases, in order:
      * the new entry already CONTAINS the old text (the caller retyped it, as in e601f79)
        -> take the new line: it is a strict superset, nothing is lost and nothing repeats;
      * the new entry adds nothing the old line lacks -> keep the old line untouched;
      * otherwise -> APPEND the new entry's payload (its leading bullet/emoji/**Name**/dash
        prefix stripped) to the old line. Concatenation, never replacement: duplicated
        wording is a cosmetic cost, dropped wording is unrecoverable under merge=union.
    """
    o, n = squash(old), squash(new)
    if o and o in n:
        return new
    if n and n in o:
        return old
    tail = re.sub(r"^.*?\*\*" + re.escape(name) + r"\*\*\s*(?:[-—–:]\s*)?", "", new).strip()
    if not tail:
        tail = new.strip()
    return old.rstrip() + " " + tail

raw = path.read_text()
trailing_nl = raw.endswith("\n")
lines = raw.splitlines()
out, done = [], False
written_line = None
for line in lines:
    if not done and PERSONA_DEF_RE.match(line):
        written_line = new if mode == "replace" else merge_persona_line(line, new)
        out.append(written_line)
        done = True
    else:
        out.append(line)
if not done:
    # Defensive: the bash-side grep matched but this pass did not (should be unreachable —
    # both use the same definition anchor). Never write a file that silently lost the
    # caller's entry — fail loudly instead.
    sys.stderr.write("append.sh: internal error — a defining entry for '**%s**' matched but no line to extend; NOTHING written\n" % name)
    sys.exit(4)

data = "\n".join(out) + ("\n" if trailing_nl else "")

# Atomic replace of the RESOLVED target (id:00b1). realpath() first so a symlinked $dest
# resolves to the canonical file: the temp file is created in THAT file's directory (same
# filesystem, so the rename is atomic and there is no /tmp→home hop), and the rename lands
# on the canonical path — the symlink itself is never the target, so it survives.
target = pathlib.Path(os.path.realpath(path))
perm = stat.S_IMODE(target.stat().st_mode)
fd, tmpname = tempfile.mkstemp(dir=str(target.parent), prefix=".personas-", suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmpname, perm)          # mkstemp defaults to 0600 — restore the registry's mode
    os.replace(tmpname, str(target))  # atomic
    # Post-write read-back (id:729c), the extend path's twin of append_verified: re-read the
    # RESOLVED target and require the merged entry to actually be there. A rename that landed
    # somewhere nobody reads, or a file clobbered between write and now, must fail LOUDLY —
    # personas.md is merge=union, where a silently lost fragment is unrecoverable.
    # Assert the EXACT line that was written is there (not a regex re-derivation, which could
    # false-fire on a --replace payload that is not itself in definition form).
    back = pathlib.Path(os.path.realpath(path)).read_text(encoding="utf-8", errors="replace")
    if written_line is not None and written_line not in back.splitlines():
        sys.stderr.write(
            "append.sh: FAILED to write persona '%s' — the merged entry is NOT in %s after the "
            "atomic replace (post-write read-back, id:729c). NOTHING can be assumed filed:\n    %s\n"
            % (name, os.path.realpath(path), written_line))
        sys.exit(5)
except BaseException:
    try:
        os.unlink(tmpname)
    except FileNotFoundError:
        pass
    raise
PYEOF
    ) 9>"$dest_lock"
    exit 0
  fi
fi

# Always prepend a blank line — defensive against missing trailing newline.
# flock prevents concurrent calls from interleaving lines; append_verified additionally reads
# the entry back off disk under that same lock, so a write that stored nothing fails LOUDLY
# instead of returning exit 0 with a phantom token (id:729c / routed:ece6).
append_verified "$dest" "$dest_lock" "$entry"

# --- (C) echo what was written: `-t inbox`, raw -e/-f/stdin form --------------------------
# stdout is the token PARSED BACK OUT of the line just appended — never the caller's own
# variable — so `filed routed:$(append.sh …)` cannot lie about what landed on disk.
if [[ "$target" == "inbox" ]]; then
  written_token="$(grep -oP '<!--\s*routed:\K[0-9a-f]{4}(?=\s*-->)' <<<"$entry" | tail -1)"
  [[ -n "$written_token" ]] && printf '%s\n' "$written_token"
fi
