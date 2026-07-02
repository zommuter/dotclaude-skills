#!/usr/bin/env bash
# mechanical-daemon.sh — one processing tick over the relay recipe drop-dir (id:b3d0, A3;
# meeting 2026-07-02-1924 decision 3). The host `--user` `.path`-unit target: runs
# relay-authored recipes OUTSIDE the Workflow (pure mechanical script → no permission wall).
#
# For each recipe JSON in pending/:
#   1. VALIDATE (recipe-validate.sh). Invalid recipes are NEVER silently dropped — moved to
#      rejected/ with a loud sibling .error file and a log line (no-silent-swallow, id:4347).
#   2. HOST GATE (id:9cfa): a recipe's `host` field binds it to a specific machine (mirrors the
#      `[host:<name>]` ROADMAP tag). REUSES `host-gate.sh` (never a raw uname compare) by
#      synthesizing the `[host:<name>]` tag text it expects. CHECK-AND-DEFER: on a host
#      mismatch (exit 3) the recipe is left untouched in pending/ — another host's daemon
#      owns it — and the reason is logged. This is a SAFETY gate, not a launch-capacity gate:
#      it runs before the intensity/resource checks below.
#   3. CHECK the launch gate: `relay-intensity.sh permits <est_wall> <resource>` AND
#      `resource-probe.sh <resource>` must BOTH succeed. CHECK-AND-DEFER, never preempt: if
#      either denies, the recipe is left in pending/ untouched (no artifact, no inject) and
#      the reason is logged. There is no third state — a denied recipe is retried next tick.
#   4. On PERMIT: move pending → running, run `cmd` (which writes acceptance_artifact), move
#      running → done, and drop a review-request via `inject.sh add` so the pool reviews the
#      artifact. A `cmd` that fails still lands in done/ (with a sibling .error file) rather
#      than running/ — the daemon must never leave a permanently-"running" ghost — but does
#      NOT inject a review (nothing to review).
#
# Usage: mechanical-daemon.sh run|tick     perform ONE tick (run/tick are synonyms)
#
# Env overrides (hermetic testing — mirrors recipe-validate.sh / recipe-manifest.md):
#   RELAY_RECIPE_DIR    recipe root, default ~/.config/relay/recipes (holds pending/running/done/rejected)
#   RELAY_INTENSITY_FILE, CLAIM_BASE, CLAIM_LOG, INJECT_BASE, INJECT_LOG
#                       threaded straight to relay-intensity.sh / resource-probe.sh (via
#                       claim.sh) / inject.sh — this script never reads their state directly.
#   RELAY_HOSTNAME      threaded straight to host-gate.sh (its own override) — the "current
#                       host" for the host-binding gate; hermetic tests set this rather than
#                       depending on the real machine's hostname.
#
# Registry invariant (recipe-manifest.md): recipes are WHITELISTED/relay-authored only. This
# daemon NEVER scans ROADMAP.md/TODO.md to invent a recipe — it only ever consumes files
# already sitting in pending/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$ROOT/recipe-validate.sh"
HOSTGATE="$ROOT/host-gate.sh"
INTENSITY="$ROOT/relay-intensity.sh"
PROBE="$ROOT/resource-probe.sh"
INJECT="$ROOT/inject.sh"

RECIPE_DIR="${RELAY_RECIPE_DIR:-$HOME/.config/relay/recipes}"
PENDING="$RECIPE_DIR/pending"
RUNNING="$RECIPE_DIR/running"
DONE="$RECIPE_DIR/done"
REJECTED="$RECIPE_DIR/rejected"
LOG="${MECHANICAL_DAEMON_LOG:-$HOME/.claude/logs/mechanical-daemon.log}"

usage() { sed -n '2,29p' "$0"; }

log() { printf '%s mechanical-daemon.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

cmd_run() {
  mkdir -p "$PENDING" "$RUNNING" "$DONE" "$REJECTED" "$(dirname "$LOG")"
  shopt -s nullglob
  local ran=0 deferred=0 rejected=0 f base id repo cmd_str est_wall resource artifact err

  for f in "$PENDING"/*.json; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"

    # (1) validate — loud rejection, never a silent drop.
    if ! err="$("$VALIDATE" "$f" 2>&1)"; then
      mv "$f" "$REJECTED/$base"
      printf '%s\n' "$err" >"$REJECTED/$base.error"
      log "REJECTED $base: $err"
      echo "REJECTED: $base ($err)" >&2
      rejected=$((rejected + 1))
      continue
    fi

    id="$(jq -r '.id' "$f")"
    repo="$(jq -r '.repo' "$f")"
    cmd_str="$(jq -r '.cmd' "$f")"
    host="$(jq -r '.host' "$f")"
    est_wall="$(jq -r '.est_wall' "$f")"
    resource="$(jq -r '.resource' "$f")"
    artifact="$(jq -r '.acceptance_artifact' "$f")"

    # (2) host-binding gate (id:9cfa) — check-and-defer, never preempt. REUSE host-gate.sh
    # (never a raw uname compare) by synthesizing the `[host:<name>]` tag text it expects.
    # A mismatch (exit 3) means another host's daemon owns this recipe: leave it in pending/.
    if ! "$HOSTGATE" "[host:$host]" >/dev/null 2>&1; then
      log "DEFERRED $base id=$id repo=$repo reason=host-mismatch recipe-host=$host"
      deferred=$((deferred + 1))
      continue
    fi

    # (3) launch gate — check-and-defer, never preempt. Either denial leaves the recipe
    # untouched in pending/ for the next tick to retry.
    if ! "$INTENSITY" permits "$est_wall" "$resource" >/dev/null 2>&1; then
      log "DEFERRED $base id=$id repo=$repo reason=intensity-permit-denied est_wall=$est_wall resource=$resource"
      deferred=$((deferred + 1))
      continue
    fi
    if ! "$PROBE" "$resource" >/dev/null 2>&1; then
      log "DEFERRED $base id=$id repo=$repo reason=resource-unavailable resource=$resource"
      deferred=$((deferred + 1))
      continue
    fi

    # (4) permitted — pending -> running -> done, then inject a review-request.
    mv "$f" "$RUNNING/$base"
    if bash -c "$cmd_str"; then
      mv "$RUNNING/$base" "$DONE/$base"
      log "RAN $base id=$id repo=$repo artifact=$artifact"
      ran=$((ran + 1))
      "$INJECT" add "$repo" --item "$id" --verdict review \
        --prompt "mechanical run $id complete; review acceptance_artifact=$artifact" \
        >/dev/null 2>&1 || log "INJECT FAILED for $base id=$id repo=$repo"
    else
      mv "$RUNNING/$base" "$DONE/$base"
      echo "cmd exited non-zero" >"$DONE/$base.error"
      log "FAILED $base id=$id repo=$repo cmd exited non-zero (no review injected)"
    fi
  done

  echo "mechanical-daemon: ran=$ran deferred=$deferred rejected=$rejected"
}

case "${1:-}" in
  run|tick) cmd_run ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) echo "mechanical-daemon.sh: unknown subcommand '$1' (use run|tick)" >&2; exit 2 ;;
esac
