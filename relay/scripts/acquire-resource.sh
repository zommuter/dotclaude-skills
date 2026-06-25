#!/usr/bin/env bash
# acquire-resource.sh — make a STANDALONE intensive job visible to the relay's
# `--intensive` scheduler (id:a643). A long-running GPU/local-LLM job that runs
# OUTSIDE the relay pool (e.g. ~/.claude/logs/ai-codebench-drain.sh's detached
# `llama-server -ngl 99`) holds no relay claim, so a concurrent `/relay --intensive`
# run is BLIND to it and could spin up a SECOND model load → GPU OOM
# ([[oom-local-model-session-kills]], the Gemma-26B 6-session kill).
#
# The relay side ALREADY honors a held `resource:<name>` claim — an intensive child
# does `claim.sh acquire resource:<name>` and stops if busy (relay-loop.js ~L1200).
# The only missing half is the standalone job ACQUIRING the SAME key. This wrapper
# composes the existing claim.sh (id:ebfb) — it builds NO new lock — so the
# standalone job's claim and the relay's intensive-unit claim COLLIDE on one key.
#
# The `<resource>` token MUST be the SAME spelling an `[INTENSIVE — <resource>]` lane
# tag uses (e.g. `gpu`, `local-llm`) so the two claim keys are identical — see
# `relay/references/resource-claims.md` for the shared vocabulary.
#
# Usage:
#   acquire-resource.sh <resource> [--run RUNID] [-- ] <command> [args…]
#       Acquire `resource:<resource>` (mode=intensive), run <command>, then ALWAYS
#       release on exit (success, failure, or signal). If the resource is already
#       held by a live claim, exit 1 WITHOUT running the command (the relay-blind
#       double-load is exactly what we refuse). --run defaults to `standalone-<pid>`.
#       The claim anchors its liveness on this wrapper's own PID (id:1b11), so a job
#       that runs PAST the claim mtime-TTL is NOT reaped mid-run — yet a crashed job's
#       claim auto-expires the instant its PID dies (it never wedges the relay).
#
#   acquire-resource.sh <resource> --acquire [--run RUNID] [--pid PID]
#       Bare acquire (no wrapped command) for a job that manages its own lifetime —
#       prints the safekey on stdout, exit 0; exit 1 if busy. Pair with a matching
#       `claim.sh release resource:<resource> --run <runid>` (or --release below).
#       --pid PID (id:1b11) ADOPTS an ALREADY-RUNNING job: the claim stays live while
#       that PID lives (past the TTL), then auto-expires when it dies. This is how you
#       make a drain that is ALREADY running visible to the relay after the fact.
#   acquire-resource.sh <resource> --release [--run RUNID]
#       Bare release (run-scoped). Idempotent.
#
# Env: CLAIM_BASE / CLAIM_TTL / CLAIM_LOG pass straight through to claim.sh (for
# hermetic tests). RESOURCE_CLAIM_LOG (default ~/.claude/logs/acquire-resource.log).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLAIM="$HERE/claim.sh"
LOG="${RESOURCE_CLAIM_LOG:-$HOME/.claude/logs/acquire-resource.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() { printf '%s acquire-resource.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

usage() { sed -n '2,46p' "$0"; }

[ -x "$CLAIM" ] || { echo "acquire-resource.sh: claim.sh not found/executable at $CLAIM" >&2; exit 2; }

resource="${1:-}"; shift || true
case "$resource" in
  ""|-h|--help|help) usage; exit 0 ;;
  --*) echo "acquire-resource.sh: <resource> required as the first arg (got '$resource')" >&2; exit 2 ;;
esac

key="resource:$resource"
run=""
mode="cmd"   # cmd | acquire | release
pidarg=""    # id:1b11 — explicit PID to anchor the claim's liveness on

# Parse leading flags up to an optional `--`, then the wrapped command.
cmd=()
while [ $# -gt 0 ]; do
  case "$1" in
    --run)     run="${2:-}"; shift 2 ;;
    --pid)     pidarg="${2:-}"; shift 2 ;;
    --acquire) mode="acquire"; shift ;;
    --release) mode="release"; shift ;;
    --) shift; cmd=("$@"); break ;;
    --*) echo "acquire-resource.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) cmd=("$@"); break ;;
  esac
done

[ -n "$run" ] || run="standalone-$$"

# id:1b11 — the live_pid the claim anchors on (so a >TTL job isn't reaped mid-run):
#   --pid PID  → adopt an ALREADY-RUNNING job (e.g. a drain whose PID you looked up);
#   cmd form   → default to THIS wrapper's own $$ (it stays alive for the command's whole
#                lifetime under the trap), so wrapped long jobs are durable with no heartbeat;
#   bare --acquire with no --pid → none (falls back to mtime-TTL + manual heartbeat/release).
case "$mode" in
  cmd)     live_pid="${pidarg:-$$}" ;;
  acquire) live_pid="$pidarg" ;;
  *)       live_pid="" ;;
esac
pidopt=(); [ -n "$live_pid" ] && pidopt=(--pid "$live_pid")

case "$mode" in
  release)
    "$CLAIM" release "$key" --run "$run"
    log "release $key run=$run"
    exit 0
    ;;
  acquire)
    if ! "$CLAIM" acquire "$key" --run "$run" --mode intensive "${pidopt[@]}" >/dev/null; then
      echo "acquire-resource.sh: $key is BUSY (held by another job/relay run) — not acquiring" >&2
      log "acquire REFUSED $key run=$run (busy)"
      exit 1
    fi
    log "acquire $key run=$run live_pid=${live_pid:-none}"
    "$CLAIM" acquire "$key" --run "$run" --mode intensive "${pidopt[@]}"  # re-print safekey on stdout (re-entrant)
    exit 0
    ;;
  cmd)
    [ "${#cmd[@]}" -gt 0 ] || { echo "acquire-resource.sh: a <command> (or --acquire/--release) is required" >&2; exit 2; }
    if ! "$CLAIM" acquire "$key" --run "$run" --mode intensive "${pidopt[@]}" >/dev/null; then
      echo "acquire-resource.sh: $key is BUSY (held by another job/relay run) — refusing to run a SECOND intensive load" >&2
      log "wrap REFUSED $key run=$run (busy)"
      exit 1
    fi
    log "wrap acquire $key run=$run live_pid=${live_pid:-none} cmd=${cmd[*]}"
    # ALWAYS release on exit — success, failure, or signal (run-scoped, idempotent).
    trap '"$CLAIM" release "$key" --run "$run" >/dev/null 2>&1 || true; log "wrap release $key run='"$run"'"' EXIT INT TERM
    "${cmd[@]}"
    ;;
esac
