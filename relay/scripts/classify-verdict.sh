#!/usr/bin/env bash
# relay/scripts/classify-verdict.sh — deterministic verdict classifier (id:85df)
#
# Pure function: reads ONE gather-repo-state JSON object (with `unpromoted` summary
# folded in) on stdin → emits ONE JSON object on stdout:
#   {verdict, reason, evidence, ambiguous, priority_rank, intensive}
# where verdict ∈ {blocked, execute, review, hard, handoff, human, idle, AMBIGUOUS}.
#
# Priority order (rank 0 = highest, never dispatched):
#   0: blocked     — dirty (non-lock-only) or diverged main tree; surface, do NOT dispatch (id:e424 parity)
#   1: execute     — open [ROUTINE] ROADMAP items
#   2: review      — substantive unaudited commits
#   3: hard        — open [HARD — pool] items (open_hard_pool >= 1)
#   4: handoff     — promotable TODO backlog (promote > 0)
#   5: human       — surface-only backlog (promote == 0, surface > 0); no apex dispatch (id:5eb3)
#   6: mechanical  — open [MECHANICAL] ROADMAP items (open_mechanical >= 1), nothing higher-
#                    priority; POOL-INERT (id:7616) — a host daemon dispatches it (A3, gated),
#                    never the LLM pool. intensive stays "" (id:5ac6 invariant untouched).
#   7: idle        — nothing actionable
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
# id:4da4 — the EXECUTE gate keys on ACTIONABLE [ROUTINE] work only (open, tag-anchored,
# @manual/human-gated EXCLUDED), NOT bare has_routine — else an @manual-only [ROUTINE] repo
# mis-fires execute and the executor sizes it out (yinyang-puzzle, /relay --once 2026-07-01).
# BACK-COMPAT: a caller predating the field (e.g. a historical backtest reconstruction) omits
# it → sentinel -1 → fall back to has_routine so its behaviour is unchanged.
actionable_routine    = int(data.get("actionable_routine_open", -1))
if actionable_routine < 0:
    actionable_routine = 1 if has_routine else 0
# id:7616 — [MECHANICAL] capability tier: pure-compute open items no LLM/human runs (a
# host daemon dispatches them, A3 gated). Absent on any caller that predates the field
# (sentinel default 0) — back-compat, no behaviour change for existing callers.
open_mechanical       = int(data.get("open_mechanical", 0))
# id:65f5 — SURFACED/no-RED-spec count: open executor-lane items carrying `⚠ SURFACED`
# (classify-repo excludes them from actionable_routine_open, so execute never fires for
# them). A repo with such an item and no higher-priority work routes to `handoff` (author
# the spec), never idle — the spec is missing, not the work. Absent on pre-field callers
# (sentinel 0 → no behaviour change).
surfaced_open         = int(data.get("surfaced_open", 0))
# id:5ac6 — INTENSIVE flag: copy top_intensive from gather VERBATIM (string, always present, "" when none).
# It is an orthogonal resource axis, never a verdict value. INVARIANT: intensive!="" => verdict in {execute,hard}
# (enforced by gather excluding human-gated items from top_intensive, id:a707).
top_intensive         = str(data.get("top_intensive", "") or "")

# id:c79e (a) — is_finished authority fold (native id:000d backstop): is_finished is an
# INDEPENDENTLY-derived, holistic signal (gather-repo-state.sh: roadmap present/non-empty +
# 0 open "- [ ]" items + no unaudited commits + clean/lock-only tree) — strictly stronger
# than actionable_routine/open_hard_pool alone. A genuinely finished repo can never have
# actionable execute/hard work, so is_finished overrides those two counts DEFENSIVELY: if an
# upstream derivation bug lets actionable_routine/open_hard_pool disagree with is_finished
# (the exact zelegator fire pattern in the 2026-07-04 forward window, TODO id:c79e), the
# cascade below still falls through to the promote/surface/idle branches instead of wrongly
# emitting execute/hard. DEMOTE-ONLY — never touches promote/surface/idle. The formerly
# JS-only id:000d guard (relay-loop.js) stays as a belt-and-suspenders backstop; this makes
# it fire 0x natively (id:c79e forward path, re-opens id:b50e deletion).
if is_finished:
    actionable_routine = 0
    open_hard_pool      = 0

# id:c79e (b) — top_intensive native promote (native id:ad74 backstop): gather-repo-state.sh
# already excludes human-gated lanes from top_intensive (id:a707), so a non-empty
# top_intensive is BY ITSELF sufficient evidence of an open, executor-actionable
# [INTENSIVE — <res>] item — independent of whether actionable_routine/open_hard_pool already
# reflect it. Promote natively when neither already covers it (defends against an upstream
# count that undercounts a freshly re-laned tag, the exact isochrone fire pattern in the
# 2026-07-04 forward window). PROMOTE-ONLY: only nudges the D3 inputs so the existing cascade
# reaches `execute`; never demotes a higher-priority verdict (execute/hard already fire first).
# The formerly JS-only id:ad74 guard (relay-loop.js) stays as a belt-and-suspenders backstop.
# GUARD (fold (a)/(b) interaction, Fable-review finding 3): a finished repo (is_finished=true)
# has no actionable work regardless of a stale/leftover top_intensive tag. Without
# `not is_finished` here, fold (a) above zeroes actionable_routine/open_hard_pool for a
# finished repo, then this fold would see top_intensive set + both counts 0 and PROMOTE,
# resurrecting the exact state fold (a) just demoted (verdict=execute instead of the demoted
# promote/surface/idle path). Fold (b) must never fire once is_finished has spoken.
if top_intensive and actionable_routine == 0 and open_hard_pool == 0 and not is_finished:
    actionable_routine = 1

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
elif actionable_routine > 0:
    verdict       = "execute"
    priority_rank = 1
    reason        = "Open executor-actionable [ROUTINE] ROADMAP items present — executor can act immediately"
    evidence.append({"field": "actionable_routine_open", "value": actionable_routine, "source": "classify-repo"})

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

elif promote > 0 or surfaced_open > 0:
    # Case (b) split 1/2 (id:5eb3): promotable backlog → full handoff (Opus apex promotion work).
    # Covers: drained @manual-only ROADMAP + promotable TODO items (case b); is_finished=true
    # with promote items (case h). promote>0 ALWAYS beats surface-only, never silenced as idle.
    # id:65f5 — a `⚠ SURFACED`/no-RED-spec item (surfaced_open>0) also routes here: the executor
    # cannot act without a RED spec, so the repo needs a handoff pass to AUTHOR one — never
    # `execute` (classify-repo already excluded it from actionable_routine_open) and never idle.
    verdict       = "handoff"
    priority_rank = 4
    reason        = (
        "Promotable TODO backlog: {} promote, {} surface; {} SURFACED/no-RED-spec item(s) -- "
        "handoff needed to populate ROADMAP / author the missing RED spec(s)"
    ).format(promote, surface, surfaced_open)
    evidence.append({"field": "unpromoted.promote", "value": promote,       "source": "unpromoted-scan"})
    evidence.append({"field": "unpromoted.surface", "value": surface,       "source": "unpromoted-scan"})
    evidence.append({"field": "surfaced_open",      "value": surfaced_open, "source": "classify-repo"})

elif surface > 0:
    # Case (b) split 2/2 (id:5eb3): surface-only backlog (promote==0 ∧ surface>0) → human.
    # No promotable work for Opus to act on; mechanical filing only (no apex dispatch).
    # The relay-loop wires file-surface-decisions.sh at the human verdict to file each
    # surface item to the decision-queue, preserving the anti-gaming invariant (loud, never idle).
    verdict       = "human"
    priority_rank = 5
    reason        = (
        "Surface-only TODO backlog: {} surface item(s), 0 promotable -- "
        "lane-triage filing needed; no apex dispatch (id:5eb3)"
    ).format(surface)
    evidence.append({"field": "unpromoted.promote", "value": 0,       "source": "unpromoted-scan"})
    evidence.append({"field": "unpromoted.surface", "value": surface,  "source": "unpromoted-scan"})

elif open_mechanical >= 1:
    # id:7616 — MECHANICAL-only backlog: pure-compute open items, nothing higher-priority
    # (no actionable routine / unaudited / hard-pool / promote / surface). POOL-INERT — a
    # host daemon dispatches this (A3, gated), never the LLM pool; intensive stays "" (the
    # id:5ac6 invariant intensive!="" => verdict in {execute,hard} holds unchanged).
    verdict       = "mechanical"
    priority_rank = 6
    reason        = (
        "Open [MECHANICAL] ROADMAP items: {} -- pure-compute work for a host daemon "
        "(A3, gated), not the LLM pool -- pool-inert"
    ).format(open_mechanical)
    evidence.append({"field": "open_mechanical", "value": open_mechanical, "source": "gather-repo-state"})

else:
    # Nothing in any D3 class — repository is idle.
    # (is_finished is a contributing signal, not the sole gate; the unpromoted check above
    # is the definitive "finished" predicate — if we reach here, both are clean.)
    verdict       = "idle"
    priority_rank = 7
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
    # id:5ac6 — INTENSIVE flag: verbatim copy of gather top_intensive, ONLY when the verdict
    # is executor-dispatchable (execute/hard). For all other verdicts (review/handoff/human/
    # idle/blocked) the flag is "" — the invariant intensive!="" => verdict in {execute,hard}
    # must hold so a regression of the dispatch partition cannot OOM-dispatch intensive work.
    "intensive":     top_intensive if verdict in ("execute", "hard") else "",
}

print(json.dumps(result))
'
