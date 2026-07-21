#!/usr/bin/env bash
# drain-cron-guard.sh (roadmap:23d8, children-of:2b23) — cron-safety guard for the
# apex-drain entry (D6: never headless-auto-spend the supervised Opus drain).
#
# WHY: `/relay . --drain` is a supervised apex driver — it must run attached to an
# interactive terminal. If a stray cron/at/systemd-timer invocation started it headless,
# it would silently auto-spend Opus turns with no human watching. This guard refuses to
# proceed unless stdin is a real tty, UNLESS an explicit override is given — an
# enforce-not-document guard, not a documentation comment.
#
# Contract:
#   stdin IS a tty                        → exit 0 (proceed)
#   stdin NOT a tty, no override           → exit nonzero + LOUD stderr
#   stdin NOT a tty, --allow-cron flag     → exit 0 (proceed)
#   stdin NOT a tty, DRAIN_ALLOW_CRON=1    → exit 0 (proceed)
#
# Usage: relay/scripts/drain-cron-guard.sh [--allow-cron]
set -euo pipefail

allow_cron=0
for arg in "$@"; do
  case "$arg" in
    --allow-cron) allow_cron=1 ;;
  esac
done

if [[ "${DRAIN_ALLOW_CRON:-0}" == "1" ]]; then
  allow_cron=1
fi

if [[ -t 0 ]]; then
  exit 0
fi

if [[ "$allow_cron" -eq 1 ]]; then
  exit 0
fi

echo "drain-cron-guard: refusing to start — stdin is not a tty (non-interactive/cron invocation)." >&2
echo "drain-cron-guard: the apex-drain entry is supervised-only (D6) and must not auto-spend Opus headless." >&2
echo "drain-cron-guard: pass --allow-cron or set DRAIN_ALLOW_CRON=1 to explicitly override this tty check." >&2
exit 1
