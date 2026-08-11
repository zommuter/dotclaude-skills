#!/usr/bin/env bash
# relay/scripts/discover-repo.sh — per-repo discovery composition (id:64b4)
#
# Composes reconcile-repo.sh (side-effecting git, id:5987) + classify-repo.sh --emit unit
# (full DISCOVER_SCHEMA unit, id:3d61) and applies the discovery ROUTING for ONE repo, so the
# mechanical runner can replace the LLM discovery shard (flip step b, id:a0b6).
#
# Usage: discover-repo.sh --repo <name> --path <abs> [--runid <id>]
#                          [--live-claims <comma-list>] [--main-branch <name>]
#                          [--no-reconcile]
#
# Emits ONE JSON object on stdout: {"units":[…0 or 1…],"surfaced":[…],"skipped":[…]}
#
# --no-reconcile (id:9d97 data-loss fix): SKIP reconcile-repo.sh entirely — run ONLY the
#   side-effect-free classify path (classify-repo.sh --emit unit). Reconcile-repo.sh performs
#   BOUNDED SIDE-EFFECTING git (fetch, ff-merge, uv.lock commit, and worktree reap/park =
#   `git worktree remove --force` + branch rename). That reap/park is CORRECT and load-bearing
#   for the LIVE dispatch loop (relay-loop.js), which protects in-flight worktrees by passing
#   --live-claims + --runid. But a READ-ONLY *snapshot* producer (discover-repos-mechanical.sh,
#   a 15-min timer) passes NO live-claims, so reconcile would treat every executor worktree as
#   stale and destroy it. --no-reconcile lets that producer classify without mutating anything.
#   The live loop NEVER passes this flag → its reconcile+reap behaviour is byte-for-byte unchanged.
#
# ROUTING (id:bc49 — orphan-suppress is ITEM-scoped/ADDITIVE, not REPO-scoped):
#   1. Unless --no-reconcile: run reconcile-repo.sh, then dispose its surfaced array by CLASS:
#        • ONLY orphan-suppress entries (reason starts "suppressed re-dispatch:", id:1f53) →
#          ADDITIVE: fall through to classify, emit the classify unit ALONGSIDE the suppress
#          surface (an orphan's mere existence NEVER blocks a repo's independent progress —
#          meeting 2026-07-23, D1). SAME-ITEM carve-out: if the classify unit is an execute
#          unit and EVERY open executable [ROUTINE] item is bound to a suppressed orphan, do
#          NOT emit a duplicate execute unit — reconcile-first (surface only, units:[]).
#          ENFORCEMENT (A4-ii): inject an item-scoped "orphan-parked, reconcile-first, do NOT
#          work id:X" note into the emitted unit.reason (the child prompt relays it).
#        • ANY repo-level class (in-flight/claimed id:ebfb, diverged id:c3f7, e3ad fail-closed
#          refusal, discover-error) → SUBSTITUTIVE: return surfaced verbatim (units:[],
#          skipped:[]) and STOP — an executor dispatched into a repo another live run holds is
#          the dc5b cross-run ledger collision. This is the pre-bc49 behaviour, preserved.
#   2. Else (reconcile clean, or --no-reconcile) run classify-repo.sh --emit unit and route by
#      unit.verdict:
#        blocked    → surfaced += {repo,reason}; no unit
#        AMBIGUOUS  → surfaced += {repo,reason: loud}; no unit (dormant hook, NO LLM call)
#        idle       → units += unit; skipped += {repo,reason}
#        else       → units += unit
#
# discover-repo.sh itself makes NO git calls and NO filesystem hunting (id:612f) — it only
# invokes the two sibling scripts and folds their JSON. RELAY_WORKTREE_BASE / RELAY_TOML are
# passed through to the sub-scripts unchanged via env (not stripped).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$SCRIPT_DIR/reconcile-repo.sh"
CLASSIFY="$SCRIPT_DIR/classify-repo.sh"

repo="" path="" runid="" live_claims="" main_branch="" no_reconcile=""   # main_branch empty ⇒ reconcile-repo.sh resolves it from HEAD (trunk-branch.sh)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    --no-reconcile) no_reconcile=1; shift ;;
    *) echo "discover-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "discover-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "discover-repo.sh: --path is required" >&2; exit 2; }

# Step 1 (SKIPPED under --no-reconcile — id:9d97): bounded side-effecting reconcile. The live
# dispatch loop always runs this (its reap/park is load-bearing); the read-only snapshot
# producer sets --no-reconcile so it never mutates a live executor's worktree.
rec_json=""
if [[ -z "$no_reconcile" ]]; then
  rec_json="$("$RECONCILE" --repo "$repo" --path "$path" --runid "$runid" \
              --live-claims "$live_claims" --main-branch "$main_branch")"

  # Dispose reconcile's surfaced array by CLASS (id:bc49). A surfaced entry is orphan-suppress
  # iff its reason starts with the "suppressed re-dispatch:" marker (reconcile-repo.sh:203, the
  # ONLY producer of that prefix). If ANY surfaced entry is NOT orphan-suppress, the repo carries
  # a repo-level block (in-flight/diverged/e3ad-refusal/discover-error) → SUBSTITUTIVE (units:[]).
  # If surfaced is non-empty AND every entry is orphan-suppress → ADDITIVE (fall through to
  # classify; the suppress entries are merged back in the final fold). Empty → normal classify.
  rec_disposition="$(printf '%s' "$rec_json" | python3 -c '
import sys, json
surf = json.load(sys.stdin).get("surfaced", [])
if not surf:
    print("clean")
elif all(s.get("reason", "").startswith("suppressed re-dispatch:") for s in surf):
    print("additive")
else:
    print("substitutive")
')"

  if [[ "$rec_disposition" == "substitutive" ]]; then
    printf '%s' "$rec_json" | python3 -c '
import sys, json
rec = json.load(sys.stdin)
# id:37f2 — an honest entry carries verdict:"" (reconcile never classifies, so there IS no
# verdict here) rather than omitting the field or fabricating one; priority_rank:0 for the
# same reason (no classify-verdict ranking was computed for a repo-level block).
surfaced = [dict(s, verdict=s.get("verdict", ""), priority_rank=s.get("priority_rank", 0)) for s in rec.get("surfaced", [])]
print(json.dumps({"units": [], "surfaced": surfaced, "skipped": []}))
'
    exit 0
  fi
fi

unit_json="$("$CLASSIFY" --emit unit --repo "$repo" --path "$path")"

# Final fold: route the classify verdict, then (id:bc49) merge any orphan-suppress surface
# ADDITIVELY and apply the SAME-ITEM carve-out + item-scoped reconcile-first note. REC_JSON is
# "" under --no-reconcile or when reconcile was clean → no suppress entries → identical to the
# pre-bc49 routing.
REPO_ARG="$repo" ROADMAP_PATH="$path/ROADMAP.md" REC_JSON="$rec_json" python3 -c '
import json, os, re, sys

repo = os.environ["REPO_ARG"]
roadmap_path = os.environ["ROADMAP_PATH"]
rec_raw = os.environ.get("REC_JSON", "")
unit = json.load(sys.stdin)
verdict = unit.get("verdict", "")

# Collect orphan-suppress surface entries from reconcile (additive notifications) + their ids.
suppress_surf = []
suppressed_ids = set()
if rec_raw:
    try:
        rec = json.loads(rec_raw)
    except Exception:
        rec = {}
    for s in rec.get("surfaced", []):
        reason = s.get("reason", "")
        if reason.startswith("suppressed re-dispatch:"):
            suppress_surf.append(s)
            suppressed_ids.update(re.findall(r"id:([0-9a-f]{4})", reason))

# Route the classify verdict (same shape/order as the pre-bc49 script). id:37f2 — the
# no-unit paths (blocked/AMBIGUOUS/idle) now carry verdict + priority_rank alongside reason,
# not just a bare reason, so a verdict-per-round consumer (id:e87d, the next seam) can read
# them without re-deriving anything. priority_rank is classify-verdicts own ranking (no
# apostrophes here — this whole block is inside a single-quoted `python3 -c ...`, see the
# NOTE below), passed through verbatim for every branch (id:258d does this for the unit).
priority_rank = unit.get("priority_rank", 0)
if verdict == "blocked":
    units, surfaced, skipped = [], [{"repo": repo, "verdict": verdict, "priority_rank": priority_rank, "reason": unit.get("reason", "")}], []
elif verdict == "AMBIGUOUS":
    units, surfaced, skipped = [], [{"repo": repo, "verdict": verdict, "priority_rank": priority_rank, "reason": "classifier returned AMBIGUOUS — needs LLM/human triage (loud, id:a0b6)"}], []
elif verdict == "idle":
    units, surfaced, skipped = [unit], [], [{"repo": repo, "verdict": verdict, "priority_rank": priority_rank, "reason": unit.get("reason", "")}]
else:
    units, surfaced, skipped = [unit], [], []

# Additive orphan-suppress handling (reached ONLY when reconcile surfaced solely orphan-suppress
# entries, or none at all — the substitutive class already returned above).
if suppress_surf:
    if verdict == "execute" and units:
        # SAME-ITEM carve-out (D1): collect open executable [ROUTINE] item ids; if EVERY one is
        # bound to a suppressed orphan (none free), drop the duplicate execute unit (reconcile-
        # first). Fail-open: if we parse no routine ids at all, keep the unit (never wrong-suppress).
        # id:0cf5 (routed:02d9) — @container is excluded alongside @manual, the THIRD copy of the
        # predicate classify-repo.sh:is_human and gather-repo-state.sh:top_intensive also carry.
        # Here the old behaviour was fail-OPEN (a stray @container id inflated routine_open, so
        # `routine_open - suppressed_ids` stayed non-empty and the SAME-ITEM carve-out declined to
        # drop a duplicate execute unit) — over-dispatch, not wrong-suppress. Fixed anyway: per the
        # lib-state-claim.sh header rule, twin consumers of one predicate must return one answer.
        # (NOTE: no apostrophes in this block — it lives inside a single-quoted `python3 -c '...'`.)
        routine_open = set()
        try:
            with open(roadmap_path) as f:
                for line in f:
                    if re.match(r"^\s*- \[ \]", line) and "[ROUTINE]" in line and "@manual" not in line and "@container" not in line:
                        m = re.search(r"id:([0-9a-f]{4})", line)
                        if m:
                            routine_open.add(m.group(1))
        except OSError:
            pass
        if routine_open and not (routine_open - suppressed_ids):
            units = []   # same-item only → reconcile-first, no duplicate execute unit
        else:
            # ENFORCEMENT (A4-ii): inject the item-scoped reconcile-first note into unit.reason.
            if suppressed_ids:
                names = ", ".join("id:" + i for i in sorted(suppressed_ids))
                note = "orphan-parked (%s) — reconcile-first, do NOT work %s" % (names, names)
            else:
                note = "orphan-parked (ambiguous binding) — reconcile-first"
            base = unit.get("reason", "")
            unit["reason"] = (base + " | " + note) if base else note
            # id:b09e — the reason says "do NOT work <ids>", and since b09e the dispatch NAMES an
            # item imperatively, so a suppressed id reaching the naming picker would actively
            # override that instruction (pre-b09e the plural instruction left the child free to
            # obey the reason). Publish the suppressed set as a FIELD so the relay-loop picker
            # can subtract it — never parse it back out of the prose. Deliberately does NOT filter
            # actionable_routine_ids itself: that list must keep matching actionable_routine_open
            # (the id:b09e count<->list invariant); suppression is a DISPATCH concern, not a
            # count concern.
            unit["suppressed_item_ids"] = sorted(suppressed_ids)
    surfaced = surfaced + suppress_surf   # additive: surface the suppress alongside

print(json.dumps({"units": units, "surfaced": surfaced, "skipped": skipped}))
' <<< "$unit_json"
