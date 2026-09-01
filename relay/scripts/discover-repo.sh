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
#        • ONLY additive-marker entries — reason starts "suppressed re-dispatch:" (orphan-suppress,
#          id:1f53) or "parked-orphan (planned):" (this round's park of a dead run's leftover
#          worktree, id:689c/e7e4) →
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
#          LOUDNESS (id:e7e4): before returning, a mechanical classify probe annotates every
#          surfaced reason with "STARVED (N actionable: id:…, verdict=…) skipped because — " when
#          the blocked repo does carry open executor-actionable work, so a starved repo can never
#          again read like an idle one in RELAY_STATUS.md. GATED (id:f0ad(a)) on the probe's OWN
#          verdict being in POOL_ACTIONABLE = {execute,review,hard,handoff} — actionable_routine_open
#          is a raw ROADMAP count independent of verdict, so a diverged/dirty repo can carry a
#          nonzero count while genuinely non-dispatchable; the banner must never call that STARVED
#          (run-anomaly-scan.sh gates the identical signal the same way — the two tools must agree).
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
# ADDITIVE CLASS MARKERS (id:bc49 + id:e7e4). A surfaced entry is additive iff its reason starts
# with one of these prefixes. Prose matching is deliberately anchored to a PREFIX MARKER, never a
# substring of the human-facing sentence.
#   "suppressed re-dispatch:"   — orphan-suppress, item-scoped (id:1f53)
#   "parked-orphan (planned):"  — this rounds planned park of a dead runs leftover worktree
#                                 (id:689c). Also a parked orphan under D1, hence additive.
#   "unretirable-submodule:"    — a worktree git structurally REFUSES to remove because its
#                                 tree carries .gitmodules (roadmap:b02f). MUST be additive:
#                                 it is reported on EVERY round for as long as the worktree
#                                 exists, and it says nothing about whether the repo has
#                                 dispatchable work. Treating it as substitutive would suppress
#                                 the repo permanently — the loderite starvation shape (id:e7e4),
#                                 which would bite yinyang-puzzle (5 such worktrees) forever.
# (NOTE: no apostrophes in this block — it lives inside a single-quoted `python3 -c ...`.)
ADDITIVE = ("suppressed re-dispatch:", "parked-orphan (planned):", "unretirable-submodule:")
surf = json.load(sys.stdin).get("surfaced", [])
if not surf:
    print("clean")
elif all(s.get("reason", "").startswith(ADDITIVE) for s in surf):
    print("additive")
else:
    print("substitutive")
')"

  if [[ "$rec_disposition" == "substitutive" ]]; then
    # id:e7e4 STARVATION LOUDNESS — a repo-level block still means units:[], but a repo that is
    # blocked WHILE CARRYING ACTIONABLE WORK must not read like "nothing to do". classify-repo.sh
    # is mechanical and side-effect-free (no LLM, no git writes), so we run it purely to ANNOTATE:
    # if it says the repo has N open executor-actionable items, every surfaced reason is prefixed
    # "STARVED (N actionable: ids) — ". Silent starvation was the actual harm in the loderite
    # incident (2026-08-20/21): the RELAY_STATUS line was indistinguishable from an idle repo.
    # Fail-open: if classify errors, the annotation is skipped and the pre-existing JSON is emitted
    # verbatim — the block itself is NEVER made conditional on this probe.
    # stderr is deliberately NOT swallowed (no-silent-swallow, id:4347) — a classify failure
    # stays visible; only its stdout is optional here.
    starve_json="$("$CLASSIFY" --emit unit --repo "$repo" --path "$path" || true)"
    printf '%s' "$rec_json" | STARVE_JSON="$starve_json" python3 -c '
import sys, json, os
rec = json.load(sys.stdin)
# id:37f2 — an honest entry carries verdict:"" (reconcile never classifies, so there IS no
# verdict here) rather than omitting the field or fabricating one; priority_rank:0 for the
# same reason (no classify-verdict ranking was computed for a repo-level block).
surfaced = [dict(s, verdict=s.get("verdict", ""), priority_rank=s.get("priority_rank", 0)) for s in rec.get("surfaced", [])]
try:
    probe = json.loads(os.environ.get("STARVE_JSON") or "{}")
except Exception:
    probe = {}
n = int(probe.get("actionable_routine_open") or 0)
verdict = probe.get("verdict", "")
# id:f0ad(a) — actionable_routine_open is a RAW ROADMAP scan (classify-repo.sh folds it in
# regardless of verdict — it is always present at the top level), so a repo that is itself
# BLOCKED (diverged, dirty main tree, …) can carry a nonzero count while being genuinely
# undispatchable. Gating on n>0 ALONE produced a self-contradicting banner: "STARVED (N
# actionable …, verdict=blocked) skipped because — diverged … needs manual reconcile" — the
# same run classified it non-actionable via classify-verdict.sh yet this banner called it
# starved. run-anomaly-scan.sh (the sibling shipped the same day) gates the identical signal
# on verdict membership in POOL_ACTIONABLE = {execute,review,hard,handoff}; align here so the
# two tools never disagree about the same repo (id:4347 — two tools disagreeing on one run is
# how a signal stops being read). human/mechanical/idle/blocked are non-dispatchable BY
# DESIGN — a repo sitting at one of those is not starved, however many open items it lists.
POOL_ACTIONABLE = ("execute", "review", "hard", "handoff")
if n > 0 and verdict in POOL_ACTIONABLE:
    ids = [i for i in (probe.get("actionable_routine_ids") or []) if i]
    # id:f0ad(d) — cap the id list shown so the banner cannot itself overrun
    # run-anomaly-scan.sh:483s short(reason, n=110) and truncate away the actual cause
    # (the sibling reason this banner is prefixed onto, e.g. "diverged … id:c3f7").
    SHOWN = 4
    shown_ids, more = ids[:SHOWN], max(0, len(ids) - SHOWN)
    idtxt = (": " + ", ".join("id:" + i for i in shown_ids) + (" +%d more" % more if more else "")) if ids else ""
    prefix = "STARVED (%d actionable item%s%s, verdict=%s) skipped because — " % (
        n, "" if n == 1 else "s", idtxt, verdict)
    for s in surfaced:
        s["reason"] = prefix + s.get("reason", "")
        s["starved_actionable_open"] = n
        s["starved_actionable_ids"] = ids
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

# Collect the ADDITIVE surface entries from reconcile (notifications that ride ALONGSIDE the
# emitted unit) + the item ids the orphan-suppress subset names.
#   additive_surf  — EVERY entry reconcile surfaced on this path. Reaching this fold means the
#                    disposition was additive or clean, so every entry here is additive by
#                    construction; keeping them all is what stops the id:e7e4 "parked-orphan
#                    (planned):" notification from being silently dropped from the output.
#   suppress_surf  — the item-scoped orphan-suppress subset, which alone drives the SAME-ITEM
#                    carve-out and the do-NOT-work id list.
additive_surf = []
suppress_surf = []
suppressed_ids = set()
if rec_raw:
    try:
        rec = json.loads(rec_raw)
    except Exception:
        rec = {}
    for s in rec.get("surfaced", []):
        additive_surf.append(s)
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
if additive_surf:
    if suppress_surf and verdict == "execute" and units:
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
    surfaced = surfaced + additive_surf   # additive: surface every reconcile notification alongside

print(json.dumps({"units": units, "surfaced": surfaced, "skipped": skipped}))
' <<< "$unit_json"
