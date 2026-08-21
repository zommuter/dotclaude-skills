#!/usr/bin/env python3
"""
lib-pool-runs.py (id:6f62) — THE single definition of "which live heartbeat runIds
are actually POOL runs".

WHY THIS EXISTS
---------------
`heartbeat.sh live-runs` emits one JSON line per live run marker, but not every marker
is a relay POOL. `discovery-producer` is a systemd-timer-driven background sampler
(`discover-repos-mechanical.sh`) with a FIXED runId and a 2100s domain-2 TTL (id:54fc):
it beats essentially forever on any machine where the timer is enabled, and it is NOT a
pool — nothing about it implies "no human is at the keyboard".

Two consumers need that distinction and they MUST NOT drift apart:
  * relay/scripts/stop-request.sh — offering the producer as a stop target would be a
    lie (it never reads the sentinel).
  * hooks/destructive-git-guard.py — treating the producer as an unattended-run signal
    hard-DENIED every interactive session (id:6f62; the guard's own reproduction).

So the predicate lives HERE, once, and both call it.

USE
---
  Python:  is_pool_run(run_id) -> bool
  Shell:   heartbeat.sh live-runs | python3 lib-pool-runs.py     # prints pool runIds,
                                                                 # one per line
"""
import json
import sys

# runIds that beat in the shared heartbeat registry but are NOT relay pools.
# Add here (and nowhere else) when another non-pool daemon joins the registry.
NON_POOL_RUN_IDS = frozenset({
    "discovery-producer",  # id:54fc — mechanical discovery sampler, systemd timer
})


def is_pool_run(run_id) -> bool:
    """True if `run_id` names a real relay pool run (not a non-pool daemon)."""
    if not isinstance(run_id, str):
        return False
    run_id = run_id.strip()
    return bool(run_id) and run_id not in NON_POOL_RUN_IDS


def main() -> None:
    """Filter `heartbeat.sh live-runs` JSON lines → pool runIds on stdout."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        run_id = obj.get("runId", "")
        if is_pool_run(run_id):
            print(run_id.strip())


if __name__ == "__main__":
    main()
