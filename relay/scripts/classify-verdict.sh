#!/usr/bin/env bash
# relay/scripts/classify-verdict.sh — deterministic verdict classifier (id:85df)
#
# Pure function: reads ONE gather-repo-state JSON object (with `unpromoted` summary
# folded in) on stdin → emits ONE JSON object on stdout:
#   {verdict, reason, evidence, ambiguous, priority_rank}
# where verdict ∈ {blocked, execute, review, hard, handoff, human, idle, AMBIGUOUS}.
#
# Priority order (rank 0 = highest, never dispatched):
#   0: blocked  — dirty (non-lock-only) or diverged main tree; surface, do NOT dispatch (id:e424 parity)
#   1: execute  — open [ROUTINE] ROADMAP items
#   2: review   — substantive unaudited commits
#   3: hard     — open [HARD — pool] items (open_hard_pool >= 1)
#   4: handoff  — unpromoted TODO backlog (promote > 0 OR surface > 0)
#   5: human    — human-lane-only, no executor path (reserved)
#   6: idle     — nothing actionable
#
# SIDE-EFFECT-FREE: no git, no filesystem writes, no ledger mutation, no lease/dispatch.
# The `AMBIGUOUS` verdict is reserved for states the mechanical rules cannot decide;
# it gates the LLM discover-shard (DP1, meeting 2026-06-30-1523).
#
# Seeded from the 2026-06-30 discovery failures (TODO id:4d8e corpus a/b/h).
set -euo pipefail

# Capture stdin first — we cannot use a bash heredoc (<<) for the Python code
# because that would replace stdin (our JSON input) with the heredoc content.
INPUT=$(cat)

printf '%s' "$INPUT" | python3 -c '
import sys
import json

data = json.load(sys.stdin)

has_routine           = bool(data.get("hasRoutine", False))
substantive_unaudited = bool(data.get("substantive_unaudited", False))
open_hard_pool        = int(data.get("open_hard_pool", 0))
unpromoted            = data.get("unpromoted", {})
promote               = int(unpromoted.get("promote", 0))
surface               = int(unpromoted.get("surface", 0))
is_finished           = bool(data.get("is_finished", False))
roadmap_actionable    = int(data.get("roadmap_actionable_open", 0))

# Verdict-parity guards (id:e424): a dirty or diverged main tree is NEVER dispatched — it
# surfaces as `blocked` (distinct from idle = clean+no-work). Outranks every D3 verdict.
# All fields already arrive from gather via classify-repo (full gather JSON passthrough).
dirty                 = bool(data.get("dirty", False))
dirty_lock_only       = bool(data.get("dirty_lock_only", False))
has_upstream          = bool(data.get("has_upstream", False))
_ab                   = str(data.get("upstream_ahead_behind", "") or "")
try:
    _parts  = _ab.split("\t")
    _ahead  = int(_parts[0]) if len(_parts) > 0 and _parts[0] != "" else 0
    _behind = int(_parts[1]) if len(_parts) > 1 and _parts[1] != "" else 0
except (ValueError, IndexError):
    _ahead, _behind = 0, 0
diverged    = has_upstream and _ahead > 0 and _behind > 0
dirty_block = dirty and not dirty_lock_only

evidence = []

# Parity guards (rank 0, never dispatched) first; then the D3 priority cascade.
if diverged:
    verdict       = "blocked"
    priority_rank = 0
    reason        = (
        "Diverged from origin (local +{} / origin +{}) -- needs manual reconcile; "
        "never dispatch or commit on a diverged repo (id:c3f7)"
    ).format(_ahead, _behind)
    evidence.append({"field": "upstream_ahead_behind", "value": _ab, "source": "gather-repo-state"})

elif dirty_block:
    verdict       = "blocked"
    priority_rank = 0
    reason        = "Dirty main working tree (uncommitted, non-lock-only) -- not dispatched until clean"
    evidence.append({"field": "dirty", "value": True, "source": "gather-repo-state"})

# D3 priority cascade — each branch appends its driving evidence pointers
elif has_routine:
    verdict       = "execute"
    priority_rank = 1
    reason        = "Open [ROUTINE] ROADMAP items present — executor can act immediately"
    evidence.append({"field": "hasRoutine", "value": True, "source": "gather-repo-state"})

elif substantive_unaudited:
    verdict       = "review"
    priority_rank = 2
    reason        = "Substantive unaudited commits present — reviewer pass needed before execution"
    evidence.append({"field": "substantive_unaudited", "value": True, "source": "gather-repo-state"})

elif open_hard_pool >= 1:
    verdict       = "hard"
    priority_rank = 3
    reason        = (
        "Open [HARD -- pool] items: {} -- "
        "pool-lane hard work pending (open_hard_pool count from gather-repo-state)"
    ).format(open_hard_pool)
    evidence.append({"field": "open_hard_pool", "value": open_hard_pool, "source": "gather-repo-state"})

elif promote > 0 or surface > 0:
    # Covers both case (b) — drained @manual-only ROADMAP with a real TODO backlog —
    # and case (h) — is_finished=true but unpromoted-scan reports backlog.
    # This MUST beat idle/human even when roadmap_actionable_open == 0 or is_finished.
    verdict       = "handoff"
    priority_rank = 4
    reason        = (
        "Unpromoted TODO backlog: {} promote, {} surface -- "
        "handoff needed to populate ROADMAP from TODO backlog"
    ).format(promote, surface)
    evidence.append({"field": "unpromoted.promote", "value": promote,  "source": "unpromoted-scan"})
    evidence.append({"field": "unpromoted.surface", "value": surface,  "source": "unpromoted-scan"})

else:
    # Nothing in any D3 class — repository is idle.
    # (is_finished is a contributing signal, not the sole gate; the unpromoted check above
    # is the definitive "finished" predicate — if we reach here, both are clean.)
    verdict       = "idle"
    priority_rank = 6
    reason        = "No actionable work found in any D3 priority class; backlog scan clean"
    evidence.append({"field": "is_finished",             "value": is_finished,      "source": "gather-repo-state"})
    evidence.append({"field": "unpromoted.promote",      "value": 0,                "source": "unpromoted-scan"})
    evidence.append({"field": "unpromoted.surface",      "value": 0,                "source": "unpromoted-scan"})
    evidence.append({"field": "roadmap_actionable_open", "value": roadmap_actionable, "source": "gather-repo-state"})

result = {
    "verdict":       verdict,
    "reason":        reason,
    "evidence":      evidence,
    "ambiguous":     False,
    "priority_rank": priority_rank,
}

print(json.dumps(result))
'
