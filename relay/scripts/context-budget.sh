#!/usr/bin/env bash
# context-budget.sh (id:5eeb) — mid-run context-budget decision function.
#
# WHY: two loderite executors (run relay-20260826-162405-7522) died mid-unit with the
# verbatim API error `Prompt is too long`, orphaning partial work and SUPPRESSING
# re-dispatch until a human ran `/relay reconcile`. The cause was pure transcript
# ACCUMULATION (linear growth over 166-193 turns), not an oversized initial dispatch —
# that gate (id:35b7 / id:4f9b) sized correctly and is NOT touched here. This script is
# the mid-run half: a PURE READ-ONLY check an executor calls periodically AND right
# before its first edit (see relay/references/executor-contract.md) to CHECKPOINT-AND-
# HANDBACK before hitting the wall, instead of dying and orphaning a worktree.
#
# Thresholds are calibrated on the two OBSERVED deaths (428,151 B / 477,574 B), not
# derived from the model's context window: transcript bytes UNDER-count true context
# (system prompt, tool defs, skill payloads, CLAUDE.md never appear in the transcript
# but occupy the window). Defaults: warn 200,000 B, handback 300,000 B (~70% of the
# smaller observed death). `est_tokens` (bytes/4, cross-referenced to prompt-size-
# gate.mjs's CHARS_PER_TOKEN) is REPORTING ONLY — never what the thresholds compare
# against (id:9eb7 measured 2.66 chars/tok for dense relay markdown).
#
# FAIL-OPEN, BUT LOUD (id:4347 no-silent-swallow): an unmeasurable transcript (missing
# or unreadable file) yields verdict `unknown`, exit 0 (never blocks the caller), and a
# NON-EMPTY stderr line — never a silent no-op.
#
# Usage:
#   context-budget.sh --bytes N [--warn-bytes W] [--handback-bytes H]
#   context-budget.sh --transcript PATH [--warn-bytes W] [--handback-bytes H]
#   context-budget.sh --self [--marker STR] [--warn-bytes W] [--handback-bytes H]
#
# `--self` (id:ff30) is THE form an executor actually uses, and the reason rule 2c is
# runnable at all. Neither --bytes nor --transcript could be satisfied by a dispatched
# child: nothing in the dispatch chain ever told it its own transcript path or size, so
# this script was built, tested, green and UNREACHABLE. `--self` delegates to the sibling
# `self-transcript.sh`, which resolves the CALLING agent's own
# `.../<session>/subagents/agent-<id>.jsonl` and disambiguates sibling children by
# `--marker` (relay executor: your worktree path, which your dispatch prompt already
# gives you). If that resolution fails it FAILS OPEN exactly like an unreadable
# transcript — verdict `unknown`, exit 0, loud stderr — never blocking the caller.
#
# Output (stdout, EXACTLY one line, always):
#   context-budget: <ok|warn|handback|unknown> bytes=<N> est_tokens=<T> warn_bytes=<W> handback_bytes=<H>
#
# Exit codes:
#   0  ok / warn / unknown — caller may proceed (warn is advisory; unknown is fail-open).
#   3  handback — the host-gate.sh "cannot proceed here" convention: caller MUST stop,
#      commit work already done (id:8b1f CUTOFF branch), and hand back cleanly.
#   2  MISUSE — bad/missing arguments.
#
# Pure read-only: never writes, creates, or removes a file; never touches git state.
set -euo pipefail

CHARS_PER_TOKEN=4
DEFAULT_WARN_BYTES=200000
DEFAULT_HANDBACK_BYTES=300000

bytes=""
transcript=""
self=0
marker=""
session_id=""
projects_root=""
warn_bytes="$DEFAULT_WARN_BYTES"
handback_bytes="$DEFAULT_HANDBACK_BYTES"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bytes)
      bytes="${2:-}"; shift 2 ;;
    --transcript)
      transcript="${2:-}"; shift 2 ;;
    --self)
      self=1; shift ;;
    --marker)
      marker="${2:-}"; shift 2 ;;
    --session-id)
      session_id="${2:-}"; shift 2 ;;
    --projects-root)
      projects_root="${2:-}"; shift 2 ;;
    --warn-bytes)
      warn_bytes="${2:-}"; shift 2 ;;
    --handback-bytes)
      handback_bytes="${2:-}"; shift 2 ;;
    *)
      echo "context-budget.sh: unknown arg '$1'" >&2
      exit 2 ;;
  esac
done

if (( self == 0 )) && [[ -z "$bytes" && -z "$transcript" ]]; then
  echo "context-budget.sh: one of --bytes N, --transcript PATH or --self is required" >&2
  exit 2
fi

emit() {
  local verdict="$1" b="$2" est_tokens
  est_tokens=$(( b / CHARS_PER_TOKEN ))
  echo "context-budget: $verdict bytes=$b est_tokens=$est_tokens warn_bytes=$warn_bytes handback_bytes=$handback_bytes"
}

# id:ff30 — resolve --self into a concrete --transcript path. An explicit --transcript
# always wins (it is the more specific statement). Resolution failure is NOT an error
# here: it degrades to the same fail-open `unknown` a missing transcript produces, so a
# harness/layout change can never turn the budget check into a work blocker.
if (( self )) && [[ -z "$transcript" ]]; then
  resolver="$(dirname "$0")/self-transcript.sh"
  if [[ ! -x "$resolver" ]]; then
    echo "context-budget.sh: --self needs $resolver (not found or not executable) (fail-open: verdict unknown)" >&2
    emit unknown 0
    exit 0
  fi
  resolver_args=()
  [[ -n "$marker" ]] && resolver_args+=(--marker "$marker")
  [[ -n "$session_id" ]] && resolver_args+=(--session-id "$session_id")
  [[ -n "$projects_root" ]] && resolver_args+=(--projects-root "$projects_root")
  if resolved="$("$resolver" "${resolver_args[@]+"${resolver_args[@]}"}")"; then
    transcript="$resolved"
  else
    echo "context-budget.sh: --self could not resolve this agent's own transcript (see self-transcript.sh above) (fail-open: verdict unknown)" >&2
    emit unknown 0
    exit 0
  fi
fi

# --transcript takes precedence when both are somehow given (--bytes wins only if
# --transcript was never passed at all).
if [[ -n "$transcript" ]]; then
  if [[ ! -e "$transcript" ]]; then
    echo "context-budget.sh: transcript not found: $transcript (fail-open: verdict unknown)" >&2
    emit unknown 0
    exit 0
  fi
  if [[ ! -r "$transcript" ]]; then
    echo "context-budget.sh: transcript not readable: $transcript (fail-open: verdict unknown)" >&2
    emit unknown 0
    exit 0
  fi
  measured="$(wc -c < "$transcript" 2>/dev/null | tr -d '[:space:]')" || measured=""
  if [[ -z "$measured" ]]; then
    echo "context-budget.sh: could not measure transcript size: $transcript (fail-open: verdict unknown)" >&2
    emit unknown 0
    exit 0
  fi
  bytes="$measured"
fi

if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
  echo "context-budget.sh: --bytes must be a non-negative integer, got '$bytes'" >&2
  exit 2
fi

if (( bytes >= handback_bytes )); then
  emit handback "$bytes"
  exit 3
elif (( bytes >= warn_bytes )); then
  emit warn "$bytes"
  exit 0
else
  emit ok "$bytes"
  exit 0
fi
