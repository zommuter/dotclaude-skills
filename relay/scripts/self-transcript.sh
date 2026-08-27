#!/usr/bin/env bash
# self-transcript.sh (id:ff30) — resolve THE CALLING AGENT'S OWN transcript path.
#
# WHY THIS EXISTS: `context-budget.sh` (id:5eeb) was built, tested and green, and was
# nevertheless UNREACHABLE. Executor-contract rule 2c told a pooled executor to run
# `context-budget.sh --transcript <your transcript path>` — but NOTHING in the dispatch
# chain ever told a child that path, and the `--bytes N` alternative needed a size the
# child had no way to obtain either. `grep -rn 'transcript_path\|transcriptPath' relay/`
# returned nothing. This script is the missing half: the child resolves its own path
# itself, so no dispatcher change (and no relay-loop.js prompt-template edit, the
# loop-crash class) is required for rule 2c to actually run.
#
# LAYOUT (verified empirically 2026-08-26 on claude-code 2.1.246 and re-verified
# 2026-08-27 on 2.1.247 against the live tree, not inferred):
#
#   $HOME/.claude/projects/<cwd-slug>/<SESSION-ID>/subagents/agent-<agentid>.jsonl
#   $HOME/.claude/projects/<cwd-slug>/<SESSION-ID>/subagents/agent-<agentid>.meta.json
#   $HOME/.claude/projects/<cwd-slug>/<SESSION-ID>.jsonl        <- top-level session
#
#   ...and, for a WORKFLOW-dispatched child (id:c219) — which is what the relay pool
#   actually produces for handoff/execute units — one level deeper:
#
#   $HOME/.claude/projects/<cwd-slug>/<SESSION-ID>/subagents/workflows/wf_<id>/agent-<agentid>.jsonl
#   $HOME/.claude/projects/<cwd-slug>/<SESSION-ID>/subagents/workflows/wf_<id>/journal.jsonl
#
# A 2026-08-27 census of the live tree: 25,620 transcripts in the workflow shape vs
# 2,476 flat. Only `agent-*.jsonl` is ever a candidate, at either depth — `journal.jsonl`
# and `*.meta.json` are not transcripts.
#
# THE TWO FACTS THAT MAKE THIS SOLVABLE:
#   1. `$CLAUDE_SESSION_ID` inside a subagent resolves to the TOP-LEVEL session id (this
#      is exactly why rule 2c was unrunnable) — but that top-level id is precisely the
#      DIRECTORY NAME that contains the child's own `subagents/` dir. What looked like
#      the obstacle is the anchor. The `<cwd-slug>` component is globbed, so a child
#      whose cwd differs from the session's (a relay worktree) still resolves.
#   2. The FIRST LINE of a child's transcript is its verbatim dispatch prompt. So any
#      string the dispatcher already put in that prompt is a usable self-marker. For a
#      relay executor that is its WORKTREE PATH (`unitPrompt()` in relay-loop.js:
#      "Your worktree <wt> on branch <branch> was already created for you"), which is
#      unique per repo per run. No new nonce, and no dispatcher change, is needed.
#
# AMBIGUITY POLICY: with N children in flight, the marker is what disambiguates. If the
# marker still matches more than one transcript (e.g. an id:a4e9 resume child reusing the
# same worktree path as the child it replaced), the MOST RECENTLY MODIFIED wins — the
# calling agent is by definition actively writing its own transcript right now, so its
# file has the newest mtime among the matches — and EVERY candidate is named on stderr.
# Never silent (id:4347).
#
# Usage:
#   self-transcript.sh [--marker STR] [--session-id ID] [--projects-root DIR] [--bytes]
#
#   --marker STR        disambiguate among sibling children by a string that appears in
#                       THIS agent's dispatch prompt (relay executor: your worktree path).
#                       Omit only when you know you are the sole child.
#   --session-id ID     override $CLAUDE_SESSION_ID (testing).
#   --projects-root DIR override $HOME/.claude/projects (testing).
#   --bytes             print the SIZE in bytes instead of the path.
#   --list-candidates   print this resolver's OWN candidate set (one path per line,
#                       pre-marker-filter) and exit 0. For transcript-shape-preflight.sh
#                       (id:413c), so the coverage check asks the resolver what it
#                       searches instead of re-deriving the glob — a second copy of that
#                       knowledge is what made id:c219 possible.
#
# Output: exactly one line on stdout (the path, or the byte count with --bytes).
#
# Exit codes:
#   0  resolved (stdout carries the answer).
#   4  UNRESOLVED — nothing printed to stdout, a loud reason on stderr. Callers MUST
#      fail OPEN on 4 (a measurement failure must never block work); `context-budget.sh
#      --self` does exactly that, yielding verdict `unknown`.
#   2  MISUSE — bad/missing arguments.
#
# Pure read-only: never writes, creates, or removes a file; never touches git state.
set -euo pipefail

# How much of a transcript's head is scanned for --marker. The dispatch prompt is the
# whole of line 1 and the marker sits within its first few hundred bytes; 128 KiB is a
# generous bound that keeps this cheap on a half-megabyte transcript.
MARKER_SCAN_BYTES=131072

marker=""
session_id=""
projects_root=""
want_bytes=0
list_candidates=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --marker)         marker="${2:-}"; shift 2 ;;
    --session-id)     session_id="${2:-}"; shift 2 ;;
    --projects-root)  projects_root="${2:-}"; shift 2 ;;
    --bytes)          want_bytes=1; shift ;;
    --list-candidates) list_candidates=1; shift ;;
    *)
      echo "self-transcript.sh: unknown arg '$1'" >&2
      exit 2 ;;
  esac
done

if [[ -z "$session_id" ]]; then
  session_id="${CLAUDE_SESSION_ID:-}"
fi
if [[ -z "$session_id" ]]; then
  session_id="${CLAUDE_CODE_SESSION_ID:-}"
fi
if [[ -z "$projects_root" ]]; then
  projects_root="${HOME:-}/.claude/projects"
fi

if [[ -z "$session_id" ]]; then
  echo "self-transcript.sh: no session id (CLAUDE_SESSION_ID unset and --session-id not given) — cannot locate own transcript" >&2
  exit 4
fi
if [[ ! -d "$projects_root" ]]; then
  echo "self-transcript.sh: projects root not a directory: $projects_root — cannot locate own transcript" >&2
  exit 4
fi

# ---------------------------------------------------------------- collect candidates
# DEPTH-AGNOSTIC under subagents/ (id:c219). The original glob was
# `<session>/subagents/agent-*.jsonl` only — one fixed level — and a
# Workflow-dispatched child (which is what the relay pool actually produces for
# handoff/execute units) writes one level DEEPER:
#
#   <session>/subagents/workflows/wf_<id>/agent-<agentid>.jsonl
#
# so the resolver scanned a real directory, found only the unrelated flat sibling, and
# reported "marker matched none of the 1 transcript(s)" — making rule 2c's mandatory
# pre-first-edit budget check a silent no-op on every pool run. A census of the live
# tree on 2026-08-27 found 25,620 transcripts in the workflow shape against 2,476 flat:
# the missed shape was the DOMINANT one.
#
# Searching at ANY depth (rather than adding a second fixed glob for `workflows/*/`)
# dissolves the class instead of patching this one level, so the next harness nesting
# change cannot silently re-disable the check. It stays safe because the filename
# pattern is unchanged — only `agent-*.jsonl` is ever a candidate, so a sibling
# `journal.jsonl` or `*.meta.json` is still never picked up — and because the marker,
# not the search breadth, is what selects the winner.
#
# `-maxdepth 4` is measured against each `subagents/` root: the flat shape sits at
# depth 1 and the workflow shape at depth 3, so 4 leaves one level of headroom without
# turning this into an unbounded walk.
candidates=()
shopt -s nullglob
subagent_roots=("$projects_root"/*/"$session_id"/subagents)
shopt -u nullglob
if (( ${#subagent_roots[@]} > 0 )); then
  while IFS= read -r -d '' f; do
    [[ -f "$f" && -r "$f" ]] && candidates+=("$f")
  done < <(find "${subagent_roots[@]}" -maxdepth 4 -type f -name 'agent-*.jsonl' -print0)
fi

shopt -s nullglob

# A TOP-LEVEL session has no subagents/ dir of its own to be found in; its transcript is
# the sibling <session-id>.jsonl. Only fall back to it when there are no child
# transcripts at all, so a child never accidentally measures its parent.
if (( ${#candidates[@]} == 0 )); then
  for f in "$projects_root"/*/"$session_id".jsonl; do
    [[ -f "$f" && -r "$f" ]] && candidates+=("$f")
  done
fi
shopt -u nullglob

if (( ${#candidates[@]} == 0 )); then
  echo "self-transcript.sh: no transcript found for session $session_id under $projects_root (looked for agent-*.jsonl anywhere under */$session_id/subagents/ — flat and workflows/wf_*/ — then */$session_id.jsonl)" >&2
  exit 4
fi

# ---------------------------------------------------------------- report candidates
# `--list-candidates` prints the resolver's OWN candidate set, one path per line, before
# any marker filtering, and exits 0. It exists so a caller can ask THIS script what it
# searches rather than re-deriving the glob (id:413c). Re-deriving is precisely how
# id:c219 happened: a second copy of "where do transcripts live" drifted from the first.
# The preflight checker compares this list against an INDEPENDENT unbounded census of the
# session dir; anything the census sees and this list does not is an uncovered shape.
if (( list_candidates )); then
  printf '%s\n' "${candidates[@]}"
  exit 0
fi

# ---------------------------------------------------------------- filter by marker
if [[ -n "$marker" ]]; then
  matched=()
  for f in "${candidates[@]}"; do
    head_bytes="$(head -c "$MARKER_SCAN_BYTES" -- "$f" 2>/dev/null)" || head_bytes=""
    if [[ "$head_bytes" == *"$marker"* ]]; then
      matched+=("$f")
    fi
  done
  if (( ${#matched[@]} == 0 )); then
    echo "self-transcript.sh: marker '$marker' matched none of the ${#candidates[@]} transcript(s) for session $session_id — cannot identify which one is mine" >&2
    exit 4
  fi
  candidates=("${matched[@]}")
elif (( ${#candidates[@]} > 1 )); then
  echo "self-transcript.sh: no --marker given and ${#candidates[@]} sibling transcripts exist for session $session_id — pass --marker <a string from your own dispatch prompt> (relay executor: your worktree path)" >&2
fi

# ---------------------------------------------------------------- resolve to exactly one
winner="${candidates[0]}"
if (( ${#candidates[@]} > 1 )); then
  best_mtime=-1
  for f in "${candidates[@]}"; do
    m="$(stat -c '%Y' -- "$f" 2>/dev/null)" || m=""
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    if (( m > best_mtime )); then
      best_mtime="$m"
      winner="$f"
    fi
  done
  echo "self-transcript.sh: ${#candidates[@]} transcripts matched — choosing the most recently modified ($winner). Candidates: ${candidates[*]}" >&2
fi

if (( want_bytes )); then
  size="$(wc -c < "$winner" 2>/dev/null | tr -d '[:space:]')" || size=""
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    echo "self-transcript.sh: could not measure $winner" >&2
    exit 4
  fi
  echo "$size"
else
  echo "$winner"
fi
