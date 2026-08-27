#!/usr/bin/env bash
# transcript-shape-preflight.sh — is the `--self` transcript resolver actually LIVE?
# (id:413c, follow-on from id:c219.)
#
# WHY THIS EXISTS
# ---------------
# `self-transcript.sh` collected only `<session>/subagents/agent-*.jsonl` — one fixed
# level — while a Workflow-dispatched relay child writes one level deeper, under
# `subagents/workflows/wf_<id>/`. So executor-contract rule 2c's MANDATORY pre-first-edit
# budget check returned `verdict unknown` and failed OPEN for every pooled child, and it
# did so for a full day behind a completely green test suite (509/0/1). It was not caught
# by tests because the tests fed the resolver the one shape their author had seen.
#
# That is the defect class this guards: **a resolver that is inert against the live
# harness layout, while every hermetic test passes.** No `tests/` file can catch it,
# because the thing that changed is outside the fixture — it is the real
# `~/.claude/projects` tree. Hence a PREFLIGHT hop (alongside mech-preflight.sh,
# mech-currency.sh, check-install-drift.sh — all of which exist for the same reason: a
# component that reports healthy while being unreachable at runtime).
#
# NOTE the resolver ITSELF is still hermetically testable, and is tested: this script
# takes --projects-root/--session-id overrides, so tests/test_transcript_shape_preflight_413c.sh
# drives it against fixtures. The non-hermetic part is only the LIVE invocation at launch.
# ("A tests/ file structurally cannot cover it" — as id:413c was filed — is too strong;
# what a tests/ file cannot cover is the real tree, not the logic.)
#
# WHAT IT CHECKS
# --------------
# (A) SHAPE COVERAGE. Independently census every `agent-*.jsonl` under the session dir at
#     UNBOUNDED depth, then ask `self-transcript.sh --list-candidates` what IT collects.
#     Anything the census sees and the resolver does not is an UNCOVERED SHAPE — exactly
#     the c219 signature — and is reported loudly with the offending relative path.
#     The census is deliberately INDEPENDENT (its own `find`, no maxdepth) rather than a
#     copy of the resolver's glob: two copies of "where transcripts live" is what allowed
#     c219 in the first place, so this one is a cross-check, not a clone.
#
# (C) RETROSPECTIVE END-TO-END. Pick a real child transcript, recover the worktree marker
#     from its own dispatch prompt, and assert the resolver resolves that marker back to
#     that exact file. This exercises the whole path — search, marker match, selection —
#     on real data rather than a fixture.
#
# (A) proves the resolver can SEE every shape present; (C) proves it can actually PICK
# the right one. Neither alone is sufficient: c219 would have failed (A); a marker-scan
# regression (too small a window, a changed prompt wording) would pass (A) and fail (C).
#
# Usage:
#   transcript-shape-preflight.sh [--session-id ID] [--projects-root DIR] [--quiet]
#
# Exit codes:
#   0  OK — every present shape is covered, and the end-to-end sample resolved.
#   3  UNCOVERED SHAPE or END-TO-END FAILURE — rule 2c is (or will be) inert. LOUD.
#   4  INDETERMINATE — could not run the check at all (no session id, no projects root).
#      Deliberately DISTINCT from 3: "I could not look" must never read as "all clear",
#      and must never read as "definitely broken" either.
#
# The CALLER decides whether a non-zero exit blocks a launch. Per the owner's 2026-08-27
# ruling the rule-2c fail-open STAYS — a harness layout change must not wedge the pool —
# so the relay front door surfaces this LOUDLY and proceeds. Being loud at launch is the
# whole point: c219's failure was silent.

set -euo pipefail

session_id=""
projects_root=""
quiet=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id)    session_id="${2:-}"; shift 2 ;;
    --projects-root) projects_root="${2:-}"; shift 2 ;;
    --quiet)         quiet=1; shift ;;
    -h|--help)       sed -n '1,60p' "$0"; exit 0 ;;
    *)
      echo "transcript-shape-preflight.sh: unknown arg '$1'" >&2
      exit 2 ;;
  esac
done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$HERE/self-transcript.sh"

[[ -z "$session_id" ]]    && session_id="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
[[ -z "$projects_root" ]] && projects_root="${HOME:-}/.claude/projects"

say() { (( quiet )) || echo "$@"; }

if [[ -z "$session_id" ]]; then
  echo "transcript-shape-preflight: INDETERMINATE — no session id (CLAUDE_SESSION_ID unset, --session-id not given). Cannot check whether the --self resolver is live." >&2
  exit 4
fi
if [[ ! -d "$projects_root" ]]; then
  echo "transcript-shape-preflight: INDETERMINATE — projects root is not a directory: $projects_root" >&2
  exit 4
fi
if [[ ! -x "$RESOLVER" ]]; then
  echo "transcript-shape-preflight: INDETERMINATE — resolver not executable at $RESOLVER" >&2
  exit 4
fi

# Locate the session directory. The <cwd-slug> component is globbed exactly as the
# resolver globs it, so a child whose cwd differs from the session's still resolves.
shopt -s nullglob
session_dirs=("$projects_root"/*/"$session_id")
shopt -u nullglob
if (( ${#session_dirs[@]} == 0 )); then
  echo "transcript-shape-preflight: INDETERMINATE — no session directory */$session_id under $projects_root (a brand-new session with no children yet is normal early in a run)." >&2
  exit 4
fi

# ---------------------------------------------------------------- (A) shape coverage
# Independent census: UNBOUNDED depth, so a shape nested deeper than the resolver's
# -maxdepth is still SEEN here and reported as uncovered rather than jointly missed.
census=()
while IFS= read -r -d '' f; do
  census+=("$f")
done < <(find "${session_dirs[@]}" -type f -name 'agent-*.jsonl' -print0 2>/dev/null || true)

if (( ${#census[@]} == 0 )); then
  echo "transcript-shape-preflight: INDETERMINATE — session $session_id has no agent-*.jsonl transcripts yet, so there is nothing to check coverage against. This is normal before the first child is dispatched." >&2
  exit 4
fi

# Ask the RESOLVER what it collects — never re-derive its glob here (see header).
resolver_list=""
resolver_rc=0
resolver_list="$("$RESOLVER" --list-candidates --session-id "$session_id" --projects-root "$projects_root" 2>/dev/null)" || resolver_rc=$?
if (( resolver_rc != 0 )); then
  echo "transcript-shape-preflight: FAIL — the resolver found NO candidates while an independent census found ${#census[@]} transcript(s) for session $session_id. Rule 2c is inert. (self-transcript.sh --list-candidates exited $resolver_rc)" >&2
  exit 3
fi

uncovered=()
for f in "${census[@]}"; do
  if ! grep -qxF -- "$f" <<<"$resolver_list"; then
    uncovered+=("$f")
  fi
done

if (( ${#uncovered[@]} > 0 )); then
  echo "transcript-shape-preflight: FAIL — ${#uncovered[@]} transcript shape(s) exist that the resolver does NOT search. Rule 2c's budget check is inert for any child writing there (this is the id:c219 signature). Uncovered:" >&2
  for f in "${uncovered[@]}"; do
    rel="$f"
    for d in "${session_dirs[@]}"; do rel="${rel#"$d"/}"; done
    echo "  $rel" >&2
  done
  echo "REMEDY: widen the candidate collection in self-transcript.sh to cover the shape above — depth-agnostically, NOT by adding another fixed glob (that is what made c219 recur-prone)." >&2
  exit 3
fi

resolver_count="$(grep -c . <<<"$resolver_list" || true)"
say "transcript-shape-preflight: (A) coverage OK — resolver sees all ${#census[@]} transcript(s) present for this session (${resolver_count} candidate(s))."

# ---------------------------------------------------------------- (C) end-to-end sample
# Recover a real dispatch marker from a real child's own prompt, then require the
# resolver to map that marker back to that same file. A relay worktree basename looks
# like `relay-<YYYYMMDD>-<HHMMSS>-<rand>-<verdict>-repo-<n>`; the dispatch prompt carries
# it verbatim ("Your worktree <wt> ..."), which is exactly why it is usable as a marker.
sample=""
sample_marker=""
for f in "${census[@]}"; do
  # NO pipes here: a producer piped into an early-exiting consumer (`head -1`, `grep -q`)
  # takes SIGPIPE, which `set -o pipefail` turns into a spurious failure — the id:81d5
  # shape the repo lints for. Capture once, then match in-shell, mirroring how
  # self-transcript.sh does its own marker scan.
  head_bytes="$(head -c 131072 -- "$f" 2>/dev/null || true)"
  m="$(grep -m1 -oE 'relay-[0-9]{8}-[0-9]{6}-[0-9]+-[a-z-]+-repo-[0-9]+' <<<"$head_bytes" || true)"
  # KEEP ONLY THE FIRST MATCH. `-m1` bounds matching LINES, not matches: `-o` still emits
  # every occurrence on that line, and a real dispatch prompt names the worktree basename
  # TWICE ("Your worktree <wt> ... on branch relay/<wt>"), so `m` arrives as two lines.
  # A multi-line `m` then matches no single-line transcript and (C) silently skips —
  # observed 2026-08-27 the moment `| head -1` was removed for the id:81d5 SIGPIPE fix.
  # Trim in-shell rather than piping into `head` (which is the banned early-exit shape).
  m="${m%%$'\n'*}"
  if [[ -n "$m" ]]; then
    # Only usable as an end-to-end probe if it identifies exactly ONE transcript;
    # a marker shared by siblings tests the tiebreak, not the resolution.
    hits=0
    for g in "${census[@]}"; do
      g_head="$(head -c 131072 -- "$g" 2>/dev/null || true)"
      [[ "$g_head" == *"$m"* ]] && hits=$((hits + 1))
    done
    if (( hits == 1 )); then
      sample="$f"; sample_marker="$m"; break
    fi
  fi
done

if [[ -z "$sample" ]]; then
  # NOT a pass and NOT a failure: say so explicitly rather than exiting 0 in silence.
  say "transcript-shape-preflight: (C) SKIPPED — no uniquely-identifying relay worktree marker found among ${#census[@]} transcript(s). Coverage (A) passed; the end-to-end path was NOT exercised this run."
  exit 0
fi

got=""
got_rc=0
got="$("$RESOLVER" --marker "$sample_marker" --session-id "$session_id" --projects-root "$projects_root" 2>/dev/null)" || got_rc=$?

if (( got_rc != 0 )) || [[ "$got" != "$sample" ]]; then
  echo "transcript-shape-preflight: FAIL — end-to-end resolution is broken. Marker '$sample_marker' occurs in exactly one transcript, but the resolver did not return it (rc=$got_rc, got='${got:-<nothing>}', expected '$sample'). Coverage (A) passed, so the search is fine and the MARKER MATCH or SELECTION is at fault — check MARKER_SCAN_BYTES and the dispatch-prompt wording." >&2
  exit 3
fi

say "transcript-shape-preflight: (C) end-to-end OK — marker '$sample_marker' resolved to its own transcript."
say "transcript-shape-preflight: OK — the --self resolver is live for session $session_id."
exit 0
