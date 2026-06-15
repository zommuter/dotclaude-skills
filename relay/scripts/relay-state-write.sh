#!/usr/bin/env bash
# relay-state-write.sh — flock'd single-writer for the relay's shared state files (id:ebfb).
# Concurrent relay runs can tear/clobber relay.toml and RELAY_STATUS.md mid-write. This
# helper serializes those writes behind ONE flock so each is atomic (temp file + mv).
#
# Subcommands:
#   toml-set <repo> <key> <value-literal>
#       Field-scoped, flock'd update of $BASE/relay.toml inside the [repos.<repo>] block:
#       set `<key> = <value-literal>`. The value is written VERBATIM — the caller supplies
#       quotes for strings (e.g. '"relay-ckpt-20260615-1200"') and bare for bool/number
#       (e.g. false). If <key> already exists in the block its line is REPLACED; if absent
#       it is ADDED as the last line of the block (before the next [...] header or EOF).
#       Every other byte is preserved. If relay.toml or the [repos.<repo>] block is missing,
#       exit non-zero and do NOT create/clobber.
#   status-write <abs-path>
#       Read full file CONTENT from STDIN and write it to <abs-path> atomically under the
#       SAME flock. <abs-path> must start with '/' (id:c34a: never a ~/$HOME/${...} literal).
#       mkdir -p the dir, write a temp file in the same dir, mv over the target.
#
# Paths: base = $FABLES_CONFIG (default ~/.config/fables-turn), lock = $BASE/.state-write.lock
# (flock fd 9, -w 30). Override $FABLES_CONFIG for hermetic tests.
set -euo pipefail

BASE="${FABLES_CONFIG:-$HOME/.config/fables-turn}"
TOML="$BASE/relay.toml"
LOCK="$BASE/.state-write.lock"
LOG="${RELAY_STATE_WRITE_LOG:-$HOME/.claude/logs/relay-state-write.log}"

mkdir -p "$BASE" "$(dirname "$LOG")"
: >>"$LOCK"

log() { printf '%s relay-state-write.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

cmd="${1:-}"; shift || true

case "$cmd" in
  toml-set)
    repo="${1:-}"; key="${2:-}"; value="${3:-}"
    [ -n "$repo" ] && [ -n "$key" ] && [ $# -ge 3 ] || {
      echo "relay-state-write.sh toml-set: <repo> <key> <value-literal> required" >&2; exit 2; }
    [ -f "$TOML" ] || { echo "relay-state-write.sh toml-set: $TOML does not exist" >&2; exit 1; }

    exec 9>"$LOCK"
    flock -w 30 9 || { echo "relay-state-write.sh toml-set: lock timeout" >&2; exit 1; }

    header="[repos.$repo]"
    # Pre-check: the block must exist (else abort without clobbering).
    if ! grep -qxF "$header" "$TOML"; then
      flock -u 9 || true
      echo "relay-state-write.sh toml-set: block $header not found in $TOML" >&2
      exit 1
    fi

    tmp="$(mktemp "$BASE/.relay.toml.XXXXXX")"
    # id:c8db — F1: pass value via ENVIRON (not awk -v) to avoid C-escape processing of
    # backslashes; F2: match key by literal prefix compare (substr + fixed-width) not regex,
    # so a key containing regex metacharacters never matches the wrong line.
    # Both hdr and key are still passed via -v (they are identifiers, not user data; no
    # backslash risk; regex is only used for hdr which is a safe `[repos.X]` literal).
    TOML_VAL="$value" awk -v hdr="$header" -v key="$key" '
      BEGIN {
        inblk=0; done=0
        val = ENVIRON["TOML_VAL"]
        klen = length(key)
      }
      # A new bracket header line: exact-string match for the target header.
      /^\[/ {
        if (inblk && !done) { print key " = " val; done=1 }
        inblk = ($0 == hdr) ? 1 : 0
        print
        next
      }
      {
        # id:c8db F2 — literal key-prefix match: substr(line, 1, klen) == key and
        # the next char is space, tab, or "=" (covers "key =" and "key=").
        if (inblk && !done && substr($0, 1, klen) == key) {
          rest = substr($0, klen + 1)
          if (rest ~ /^[ \t]*=/) { print key " = " val; done=1; next }
        }
        print
      }
      END { if (inblk && !done) { print key " = " val } }
    ' "$TOML" >"$tmp"

    mv "$tmp" "$TOML"
    flock -u 9 || true
    log "toml-set repo=$repo key=$key"
    ;;

  status-write)
    target="${1:-}"
    [ -n "$target" ] || { echo "relay-state-write.sh status-write: <abs-path> required" >&2; exit 2; }
    case "$target" in
      /*) ;;
      *) echo "relay-state-write.sh status-write: path must be absolute (got '$target')" >&2; exit 1 ;;
    esac

    exec 9>"$LOCK"
    flock -w 30 9 || { echo "relay-state-write.sh status-write: lock timeout" >&2; exit 1; }

    dir="$(dirname "$target")"
    mkdir -p "$dir"
    tmp="$(mktemp "$dir/.relay-status.XXXXXX")"
    cat >"$tmp"
    mv "$tmp" "$target"
    flock -u 9 || true
    log "status-write target=$target"
    ;;

  ""|-h|--help|help)
    sed -n '2,20p' "$0"
    ;;

  *)
    echo "relay-state-write.sh: unknown subcommand '$cmd' (use toml-set|status-write)" >&2
    exit 2
    ;;
esac
