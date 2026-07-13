#!/usr/bin/env bash
# resource-probe.sh — check-and-defer live-availability probe for the mechanical-run
# daemon's auto-launch gate (id:68dc, A5; meeting 2026-07-02-1924 decision 4).
#
# On top of the permit window (A4), auto-launching an intensive mechanical run needs a
# LIVE-availability probe: measured VRAM/RAM/load AND no competing resource:<res> claim.
# CHECK-AND-DEFER, never preempt — a held claim reports unavailable, this script never
# kills or suspends a holder (routed:f506 covers active-suspend, out of scope here).
#
# Usage: resource-probe.sh <gpu|ram|cpu|local-llm>
#   Emits ONE JSON object {resource, available, reason, ...metrics} on stdout.
#   Exit 0 when available, nonzero when not.
#
# Sources:
#   gpu        — nvidia-smi (env-overridable RESOURCE_PROBE_NVIDIA_SMI, default
#                "nvidia-smi"); a missing/failing binary degrades GRACEFULLY to
#                available:false + a stated reason, never a crash (this host may have
#                no NVIDIA GPU at all).
#   ram        — /proc/meminfo MemAvailable vs RESOURCE_PROBE_RAM_MIN_MB (default 2048).
#   cpu        — /proc/loadavg (1-min) vs RESOURCE_PROBE_LOAD_MAX (default = nproc).
#   local-llm  — claim-only: no hardware metric, availability is purely "no competing
#                resource:local-llm claim".
#
# Every resource ALSO reads `claim.sh peek` (sharing $CLAIM_BASE): a LIVE
# resource:<res> claim held by another run makes this resource unavailable regardless
# of hardware headroom — the daemon and the pool share ONE claim registry, so a
# competing INTENSIVE job always wins the check-and-defer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIM="$ROOT/scripts/claim.sh"

resource="${1:-}"
case "$resource" in
  gpu|ram|cpu|local-llm|r5-jvm|lean|xvfb-electron) ;;
  *)
    echo '{"resource":null,"available":false,"reason":"usage: resource-probe.sh <gpu|ram|cpu|local-llm|r5-jvm|lean|xvfb-electron|...> — claim-only bespoke tokens allowed, see resource-claims.md"}'
    exit 2
    ;;
esac

# claim_held <res>: true if a LIVE resource:<res> claim is held by anyone right now.
claim_held() {
  local res="$1"
  "$CLAIM" peek 2>/dev/null | jq -e --arg key "resource:$res" 'select(.key == $key)' >/dev/null 2>&1
}

if claim_held "$resource"; then
  jq -n --arg resource "$resource" \
    --arg reason "a live resource:$resource claim is held (check-and-defer, never preempt)" \
    '{resource:$resource, available:false, reason:$reason}'
  exit 1
fi

case "$resource" in
  local-llm|r5-jvm|lean|xvfb-electron)
    # Claim-only (incl. bespoke open-ended tokens, see resource-claims.md): no hardware
    # metric — no competing claim (checked above) => available.
    jq -n --arg resource "$resource" --arg reason "no competing resource:$resource claim (claim-only token)" \
      '{resource:$resource, available:true, reason:$reason}'
    exit 0
    ;;

  cpu)
    load_max="${RESOURCE_PROBE_LOAD_MAX:-}"
    if [[ -z "$load_max" ]]; then
      load_max="$(nproc 2>/dev/null || echo 1)"
    fi
    if [[ ! -r /proc/loadavg ]]; then
      jq -n --arg resource "$resource" --arg reason "/proc/loadavg not readable" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    load1="$(awk '{print $1}' /proc/loadavg)"
    if ! ok="$(python3 -c "print('true' if float('$load1') <= float('$load_max') else 'false')" 2>/dev/null)"; then
      jq -n --arg resource "$resource" --arg reason "failed to parse loadavg ($load1)" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    if [[ "$ok" == "true" ]]; then
      jq -n --arg resource "$resource" --arg load1 "$load1" --arg ceiling "$load_max" \
        --arg reason "load1 ($load1) <= ceiling ($load_max)" \
        '{resource:$resource, available:true, reason:$reason, load1:($load1|tonumber), ceiling:($ceiling|tonumber)}'
      exit 0
    else
      jq -n --arg resource "$resource" --arg load1 "$load1" --arg ceiling "$load_max" \
        --arg reason "load1 ($load1) > ceiling ($load_max)" \
        '{resource:$resource, available:false, reason:$reason, load1:($load1|tonumber), ceiling:($ceiling|tonumber)}'
      exit 1
    fi
    ;;

  ram)
    min_mb="${RESOURCE_PROBE_RAM_MIN_MB:-2048}"
    if [[ ! -r /proc/meminfo ]]; then
      jq -n --arg resource "$resource" --arg reason "/proc/meminfo not readable" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
    if [[ -z "$avail_kb" ]]; then
      jq -n --arg resource "$resource" --arg reason "MemAvailable not found in /proc/meminfo" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    avail_mb=$(( avail_kb / 1024 ))
    if [[ "$avail_mb" -ge "$min_mb" ]]; then
      jq -n --arg resource "$resource" --argjson free_mb "$avail_mb" --argjson min_mb "$min_mb" \
        --arg reason "MemAvailable (${avail_mb}MB) >= min (${min_mb}MB)" \
        '{resource:$resource, available:true, reason:$reason, free_mb:$free_mb, min_mb:$min_mb}'
      exit 0
    else
      jq -n --arg resource "$resource" --argjson free_mb "$avail_mb" --argjson min_mb "$min_mb" \
        --arg reason "MemAvailable (${avail_mb}MB) < min (${min_mb}MB)" \
        '{resource:$resource, available:false, reason:$reason, free_mb:$free_mb, min_mb:$min_mb}'
      exit 1
    fi
    ;;

  gpu)
    nvidia_smi="${RESOURCE_PROBE_NVIDIA_SMI:-nvidia-smi}"
    smi_path="$(command -v "$nvidia_smi" 2>/dev/null || true)"
    if [[ -z "$smi_path" ]]; then
      jq -n --arg resource "$resource" \
        --arg reason "nvidia-smi ('$nvidia_smi') not found on this host — no NVIDIA GPU or driver" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    if ! smi_out="$("$smi_path" --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null)"; then
      jq -n --arg resource "$resource" --arg reason "nvidia-smi invocation failed" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    free_mb="$(printf '%s\n' "$smi_out" | head -n1 | tr -dc '0-9')"
    if [[ -z "$free_mb" ]]; then
      jq -n --arg resource "$resource" --arg reason "could not parse nvidia-smi output ('$smi_out')" \
        '{resource:$resource, available:false, reason:$reason}'
      exit 1
    fi
    min_mb="${RESOURCE_PROBE_VRAM_MIN_MB:-2048}"
    if [[ "$free_mb" -ge "$min_mb" ]]; then
      jq -n --arg resource "$resource" --argjson free_mb "$free_mb" --argjson min_mb "$min_mb" \
        --arg reason "free VRAM (${free_mb}MB) >= min (${min_mb}MB)" \
        '{resource:$resource, available:true, reason:$reason, free_mb:$free_mb, min_mb:$min_mb}'
      exit 0
    else
      jq -n --arg resource "$resource" --argjson free_mb "$free_mb" --argjson min_mb "$min_mb" \
        --arg reason "free VRAM (${free_mb}MB) < min (${min_mb}MB)" \
        '{resource:$resource, available:false, reason:$reason, free_mb:$free_mb, min_mb:$min_mb}'
      exit 1
    fi
    ;;
esac
