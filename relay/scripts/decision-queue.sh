#!/usr/bin/env bash
# decision-queue.sh — durable file-backed human-decision-request queue (id:de31)
#
# Subcommands:
#   add --repo <r> --kind <k> --question <q> [--option <o>]... [--evidence <e>]
#     Mint a unique decision id, append ONE JSON record to $RELAY_DECISION_QUEUE,
#     print the id to stdout.
#   list [--repo <r>] [--all]
#     Print matching records ONE JSON per line. Default: open only. --all: include resolved.
#   resolve <id> --answer <a>
#     Set status:resolved, answer, resolved_at on the record; rewrite atomically under flock.
#
# Queue file: $RELAY_DECISION_QUEUE (default ~/.config/relay/decision-queue.jsonl)
# Lock file: <queue>.lock (transient, not committed)

set -euo pipefail

QUEUE="${RELAY_DECISION_QUEUE:-${HOME}/.config/relay/decision-queue.jsonl}"
LOCK_FILE="${QUEUE}.lock"

die() { echo "ERROR: $*" >&2; exit 1; }

# Ensure parent dir exists
mkdir -p "$(dirname "$QUEUE")"

# Acquire exclusive flock on fd 9; lock file next to the queue
_flock_acquire() {
  exec 9>"$LOCK_FILE"
  flock -x -w 30 9 || die "could not acquire decision-queue lock after 30s"
}

_flock_release() {
  exec 9>&-
}

# Mint a short unique id: dq- + 8 hex chars
_mint_id() {
  local hex
  hex="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  echo "dq-${hex}"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  add)
    repo=""
    kind=""
    question=""
    evidence=""
    options=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo)     shift; repo="${1:-}"     ;;
        --kind)     shift; kind="${1:-}"     ;;
        --question) shift; question="${1:-}" ;;
        --option)   shift; options+=("${1:-}") ;;
        --evidence) shift; evidence="${1:-}" ;;
        *) die "unknown flag: $1" ;;
      esac
      shift || true
    done

    [[ -n "$repo" ]]     || die "--repo is required"
    [[ -n "$kind" ]]     || die "--kind is required"
    [[ -n "$question" ]] || die "--question is required"

    id="$(_mint_id)"
    requested_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Build JSON safely with python3 — never string-concat (questions/evidence
    # can contain quotes, apostrophes, arbitrary text)
    record="$(python3 - "$id" "$repo" "$kind" "$question" "$evidence" "$requested_at" "${options[@]+"${options[@]}"}" <<'PYEOF'
import json, sys
args = sys.argv[1:]
id_, repo, kind, question, evidence = args[0], args[1], args[2], args[3], args[4]
requested_at = args[5]
options = args[6:]
rec = {
    "id": id_,
    "repo": repo,
    "kind": kind,
    "question": question,
    "options": list(options),
    "evidence": evidence,
    "requested_at": requested_at,
    "status": "open",
}
print(json.dumps(rec, ensure_ascii=False))
PYEOF
)"

    _flock_acquire
    echo "$record" >> "$QUEUE"
    _flock_release

    echo "$id"
    ;;

  list)
    show_all=0
    filter_repo=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all)  show_all=1 ;;
        --repo) shift; filter_repo="${1:-}" ;;
        *) die "unknown flag: $1" ;;
      esac
      shift || true
    done

    [[ -f "$QUEUE" ]] || exit 0

    python3 - "$show_all" "$filter_repo" "$QUEUE" <<'PYEOF'
import json, sys
show_all = sys.argv[1] == "1"
filter_repo = sys.argv[2]  # empty = no filter
queue_file = sys.argv[3]
with open(queue_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not show_all and rec.get("status") != "open":
            continue
        if filter_repo and rec.get("repo") != filter_repo:
            continue
        print(json.dumps(rec, ensure_ascii=False))
PYEOF
    ;;

  resolve)
    id="${1:-}"
    [[ -n "$id" ]] || die "usage: resolve <id> --answer <a>"
    shift || true

    answer=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --answer) shift; answer="${1:-}" ;;
        *) die "unknown flag: $1" ;;
      esac
      shift || true
    done

    [[ -n "$answer" ]] || die "--answer is required"
    [[ -f "$QUEUE" ]] || die "queue file not found: $QUEUE"

    resolved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    _flock_acquire

    # Read all, modify matching record, write back atomically via tmp+rename
    tmp_file="${QUEUE}.tmp.$$"
    python3 - "$id" "$answer" "$resolved_at" "$QUEUE" "$tmp_file" <<'PYEOF'
import json, sys
target_id = sys.argv[1]
answer = sys.argv[2]
resolved_at = sys.argv[3]
queue_file = sys.argv[4]
tmp_file = sys.argv[5]

found = False
out_lines = []
with open(queue_file) as f:
    for line in f:
        line_stripped = line.strip()
        if not line_stripped:
            continue
        rec = json.loads(line_stripped)
        if rec["id"] == target_id:
            rec["status"] = "resolved"
            rec["answer"] = answer
            rec["resolved_at"] = resolved_at
            found = True
        out_lines.append(json.dumps(rec, ensure_ascii=False))

if not found:
    raise SystemExit(f"ERROR: decision id not found: {target_id}")

with open(tmp_file, "w") as f:
    for line in out_lines:
        f.write(line + "\n")
PYEOF

    mv "$tmp_file" "$QUEUE"
    _flock_release
    ;;

  *)
    die "usage: decision-queue.sh <add|list|resolve> [args...]"
    ;;
esac
