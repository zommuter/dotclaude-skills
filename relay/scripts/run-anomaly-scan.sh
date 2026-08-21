#!/usr/bin/env bash
# run-anomaly-scan.sh — END-OF-RUN ANOMALY CHECKER for the relay pool.
#
# It answers ONE question about a finished (or in-flight) pool run:
#   "did this run make the progress its own inputs predicted, and if not, where
#    did the work evaporate?"
#
# WHY (2026-08-21 session; all three failures observed the SAME day). The relay can
# silently do NOTHING in at least three structurally different ways, and all three
# render identically to a human reading RELAY_STATUS.md — as "no work available":
#
#   1. INSTALL DRIFT — integrate.sh + ledger-slice.sh were committed but never
#      `make install`-ed, so every hop resolving through
#      ~/.claude/skills/relay/scripts/ 404'd on model:"bash". Two rounds dispatched
#      ZERO units. A detector already existed (check-install-drift.sh); NOTHING
#      invoked it.
#   2. CLASSIFIER BLOCKS — [Self-Approval] on integrate, [Logging/Audit Tampering] on
#      the status hop. A DISPATCH-LAYER refusal creates no agent at all, so it leaves
#      NO trace in the journal, in per-agent transcripts, in RELAY_STATUS.md, or in
#      relay-events.jsonl. Only the Workflow's own failures summary has it
#      (id:f5d9(b), id:4917).
#   3. SKIP-ON-LEFTOVER-BRANCHES — loderite classified `execute` with SIX actionable
#      [ROUTINE] items and was skipped across two consecutive runs over a stale
#      worktree from a dead run. One line in RELAY_STATUS.md, indistinguishable
#      from idleness.
#
# DESIGN CONSTRAINTS honoured here:
#   * DERIVE, never invent bookkeeping. Every anomaly class below is computed from
#     state that ALREADY exists: relay-events.jsonl, RELAY_STATUS.md,
#     classify-repo.sh, and relay.toml (via the SHARED lib-own-repos.sh — relay.toml
#     is THE canonical own-repo set, `# path:` overrides honoured; NEVER a ~/src glob).
#   * REPORT-ONLY, exit 0 by default — same posture and flag vocabulary as
#     relay-doctor.sh (id:a883). `--strict` is the opt-in nonzero gate. The only
#     nonzero exits without --strict are MISUSE (bad args, unreadable inputs).
#   * A detector nobody reads is the id:4347 anti-pattern. Output is SHORT and names,
#     per finding: the repo, the anomaly class, the item count, and the NEXT COMMAND
#     a human would run. Clean classes collapse to one line.
#   * Say UNKNOWN when the evidence cannot distinguish causes. INTEGRATE-EVAPORATED
#     was ALWAYS a classifier block on 2026-08-21, but the handback message cannot
#     tell a block from a crash from a drift 404 (id:f5d9(b)) — so it is reported as
#     cause-unknown, with the candidate causes named, never as "blocked".
#
# ANOMALY CLASSES (each names the state it derives from):
#   STARVED                     classify-repo.sh says pool-actionable NOW, and the run
#                               left NO work-unit trace for that repo at all — no
#                               `dispatch`, no `integrate`, no `handback`.
#                               (relay.toml own-set x relay-events.jsonl x classify-repo.sh)
#   DISPATCHED-BUT-NO-OUTCOME   a `dispatch` (repo,mode) with no matching `integrate`
#                               or `handback`. Work evaporated mid-flight.
#                               (relay-events.jsonl only)
#   INTEGRATE-EVAPORATED        a `handback` whose reason is the EMPTY
#                               "no merged= line (unparseable integrator output):"
#                               signature — the integrator never actually ran.
#                               CAUSE UNKNOWN by construction (see above).
#                               (relay-events.jsonl only)
#   ZERO-YIELD-RUN              dispatched > 0 but integrated == 0. Run-level.
#                               SUPPRESSED while the run is still ALIVE (heartbeat.sh
#                               live-runs) and has `## In-flight` rows — a unit still
#                               executing has not yet had its chance to yield.
#                               (relay-events.jsonl x RELAY_STATUS `## In-flight`
#                                x heartbeat.sh live-runs)
#   SKIPPED-WITH-ACTIONABLE     a repo rendered into RELAY_STATUS.md's `Skipped` or
#                               `Blocked / HANDBACKs` section for this run that
#                               NONETHELESS classifies pool-actionable, with its item
#                               count. (RELAY_STATUS.md x classify-repo.sh)
#   STARVED-UNVERIFIED          a ZERO-work-unit-trace repo whose live classification
#                               could NOT be obtained this scan (classify-error, or its
#                               registered path is gone). Absence of evidence is never
#                               rendered as clean — this fires instead of the repo being
#                               silently dropped for failing the pool-actionable test.
#                               (relay.toml x relay-events.jsonl x classify-repo.sh)
#
#   STARVED and SKIPPED-WITH-ACTIONABLE are MUTUALLY EXCLUSIVE by construction:
#   STARVED means the run left no trace of a work unit for that repo (the loderite
#   case); SKIPPED-WITH-ACTIONABLE means the repo DID run at least one unit yet still
#   ends the run in a skip/blocked section with actionable work left. One repo never
#   appears in both.
#
#   Repos the run deliberately excluded (`excluded-by-config`, `excluded for this run`)
#   are NEVER anomalies and are not even re-classified — a paused/excluded repo doing
#   nothing is the configuration working. The same holds for a repo rendered into
#   `## Queued` (relay-loop.js:417/2451/4054 — a quota-stopped --afk run parks its
#   classified-but-undispatched units there): it was seen and accounted for, just not
#   given a turn. A scanner that reads only `Skipped`/`Blocked` renders a healthy
#   quota-stop as STARVED, because "no dispatch trace yet" and "starved" look identical
#   without that section.
#
# RUN SCOPE (the `--only` guard, and its deliberate limit).
#   relay-loop.js:2143-2145 emits exactly ONE `verdict` event per own repo IN SCOPE per
#   round, across units/surfaced/skipped. So WHEN a run emitted any verdict events at
#   all, that event set (plus anything with a dispatch/integrate/handback or a status
#   row) IS the run's scope, and an own repo outside it was never asked about — not
#   starved. That is what keeps a `--only <repo>` run (which drops out-of-scope repos
#   before sharding) from reporting the rest of the fleet STARVED.
#
#   The guard is RUN-LEVEL and FAIL-OPEN by construction: a run with ZERO verdict events
#   carries no scope evidence, so NO scope filtering is applied and every own repo stays
#   a candidate. Per-repo "no verdict event ⇒ out of scope" would be strictly wrong there
#   — it silences the exact class this tool exists for whenever the verdict rows are the
#   thing that went missing.
#
# Usage:
#   run-anomaly-scan.sh [RUN_ID] [--strict] [--json] [--fast] [--repo <name>]
#     RUN_ID       the run to audit; omit (or pass `latest`) for the most recent runId
#                  present in the event log.
#     --strict     exit nonzero when any finding is surfaced (default: always exit 0).
#     --json       emit one JSON object instead of the human report.
#     --fast       HYBRID, never fully recorded (id:87a7). A candidate with SOME work-unit
#                  trace this run reuses the run's own recorded `verdict` event, cheaply.
#                  A candidate with ZERO trace — the exact STARVED-candidate population,
#                  empirically a handful of repos, not the fleet — is STILL live-
#                  reclassified, because STARVED is the one class this tool exists for and
#                  a recorded verdict cannot answer "is this repo starved" by construction
#                  (a starved repo's recorded verdict is precisely what proved untrustworthy).
#                  A MODE THAT CANNOT CHECK A CLASS MUST NEVER PRINT THAT CLASS AS CLEAN:
#                  the earlier `--fast` printed `clean: … STARVED` for a class it never
#                  examined. The report names which repos were live vs recorded.
#     --repo <n>   restrict re-classification + per-repo findings to ONE repo.
#     --list-runs  print the runIds present in the event log (oldest first) and exit.
#
# Env overrides (hermetic tests; same spellings the siblings already use):
#   RELAY_EVENTS_PATH     default ~/.config/relay/relay-events.jsonl
#   RELAY_STATUS_PATH     default ~/.config/relay/RELAY_STATUS.md
#   RELAY_TOML            default ~/.config/relay/relay.toml
#   SRC_DIR               default ~/src
#   RUN_ANOMALY_CLASSIFY  override the classify-repo.sh path (stub it in tests)
#   RUN_ANOMALY_HEARTBEAT override the heartbeat.sh path (stub it in tests) — used ONLY to
#                         answer "is this run still alive", reusing the same live-runs
#                         query relay-status-publish.sh:158 already makes. Never a new
#                         liveness check, and fail-open: an unreadable heartbeat means
#                         "not known alive", so nothing is suppressed.
#   RUN_ANOMALY_LOG       default ~/.claude/logs/run-anomaly-scan.log
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
RELAY_EVENTS_PATH="${RELAY_EVENTS_PATH:-$HOME/.config/relay/relay-events.jsonl}"
RELAY_STATUS_PATH="${RELAY_STATUS_PATH:-$HOME/.config/relay/RELAY_STATUS.md}"
CLASSIFY_REPO="${RUN_ANOMALY_CLASSIFY:-$SCRIPT_DIR/classify-repo.sh}"
HEARTBEAT_SH="${RUN_ANOMALY_HEARTBEAT:-$SCRIPT_DIR/heartbeat.sh}"
LOG="${RUN_ANOMALY_LOG:-$HOME/.claude/logs/run-anomaly-scan.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true   # best-effort: never fail on a log dir
log() { printf '%s run-anomaly-scan.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# own_repos() — THE canonical confirmed-own set from relay.toml (id:0fa0). Sourced,
# never re-implemented, and NEVER replaced by a ~/src/* glob.
# shellcheck source=lib-own-repos.sh
source "$SCRIPT_DIR/lib-own-repos.sh"

# --- parse args ----------------------------------------------------------------
run_id=""
strict=0
as_json=0
fast=0
only_repo=""
list_runs=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)    strict=1; shift ;;
    --json)      as_json=1; shift ;;
    --fast)      fast=1; shift ;;
    --list-runs) list_runs=1; shift ;;
    --repo)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "run-anomaly-scan.sh: --repo requires a repo name" >&2; exit 2
      fi
      only_repo="$2"; shift 2 ;;
    -h|--help)
      # Compute the header range instead of hardcoding it: the literal '2,86p' had ALREADY
      # drifted past the end of the header block. No pipe into an early-exiting consumer
      # (banned): grep drains fully, and bash expansion takes the first match.
      _gn="$(grep -n '^set -euo pipefail' "$0")"
      _gn="${_gn%%$'\n'*}"
      sed -n "2,$(( ${_gn%%:*} - 1 ))p" "$0"
      exit 0 ;;
    --*) echo "run-anomaly-scan.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -n "$run_id" ]]; then
        echo "run-anomaly-scan.sh: only one RUN_ID may be given (got extra '$1')" >&2; exit 2
      fi
      run_id="$1"; shift ;;
  esac
done

# The event log is the ONE hard input: with no events there is no run to audit, and
# silently reporting "clean" would be exactly the false-green this tool exists to kill.
if [[ ! -f "$RELAY_EVENTS_PATH" ]]; then
  echo "run-anomaly-scan.sh: event log not found: $RELAY_EVENTS_PATH" >&2
  echo "run-anomaly-scan.sh: cannot audit a run without it (MISUSE, not a clean run)." >&2
  exit 2
fi

# --- own-repo enumeration -------------------------------------------------------
# An ABSENT relay.toml is a DISTINCT misuse case from a CORRUPT one, and only the corrupt
# one was guarded. own_repos() returns 0 with NO output when $RELAY_TOML does not exist —
# a valid "no registry yet" state for its mutating callers, but for a READ-ONLY scanner it
# yields `own-repos=0 … no anomalies … exit=0`: a FALSE CLEAN, the precise failure this
# tool's own header calls worse than no scanner. Check existence before calling own_repos().
if [[ ! -f "$RELAY_TOML" ]]; then
  echo "run-anomaly-scan.sh: relay.toml not found: $RELAY_TOML" >&2
  echo "run-anomaly-scan.sh: refusing to report clean when the own-repo registry is absent (id:0fa0)." >&2
  exit 2
fi

# lib-own-repos.sh's contract (id:0fa0 finding (a)): a bare
# `while read; do …; done < <(own_repos)` DISCARDS the subshell's exit status, so a
# CORRUPT relay.toml reads as "zero own repos" and everything downstream looks clean.
# Capture to a file and test the status EXPLICITLY.
# ONE scratch dir for every intermediate, so cleanup is a single recursive removal of a
# directory this script created (the repo's no-bare-`rm -f` lint) rather than a growing
# list of force-removed individual files.
wk="$(mktemp -d)"
trap 'rm -r -- "$wk"' EXIT
own_tsv="$wk/own.tsv"
cls_tsv="$wk/cls.tsv"
if ! own_repos > "$own_tsv"; then
  echo "run-anomaly-scan.sh: relay.toml failed to parse: $RELAY_TOML" >&2
  echo "run-anomaly-scan.sh: refusing to report on a registry we cannot read (id:0fa0)." >&2
  exit 2
fi

# --- pass 1: fold the event log + RELAY_STATUS into per-repo run facts -----------
# Emits: the resolved runId, run totals, and one line per repo the scan may need to
# re-classify. Kept separate from pass 2 so the (slower) classify loop below stays a
# plainly observable bash loop rather than hidden inside a python subprocess tree.
facts_json="$wk/facts.json"
cand_tsv="$wk/candidates.tsv"

RUN_ID_ARG="$run_id" LIST_RUNS="$list_runs" ONLY_REPO="$only_repo" CAND_TSV="$cand_tsv" \
EVENTS_PATH="$RELAY_EVENTS_PATH" STATUS_PATH="$RELAY_STATUS_PATH" OWN_TSV="$own_tsv" \
python3 - > "$facts_json" <<'PY_FOLD'
import json, os, re, sys

events_path = os.environ["EVENTS_PATH"]
status_path = os.environ["STATUS_PATH"]
own_tsv     = os.environ["OWN_TSV"]
run_arg     = os.environ.get("RUN_ID_ARG", "").strip()
only_repo   = os.environ.get("ONLY_REPO", "").strip()
list_runs   = os.environ.get("LIST_RUNS") == "1"

own = []
with open(own_tsv, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        name, _, path = line.partition("\t")
        own.append((name, path))
own_paths = dict(own)

# --- read events -------------------------------------------------------------
run_order = []           # runIds in file order (oldest first)
seen_runs = set()
rows = []
malformed = 0
with open(events_path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            malformed += 1     # surfaced in the report; never silently swallowed
            continue
        if not isinstance(d, dict):
            malformed += 1
            continue
        rid = d.get("runId") or ""
        if rid and rid not in seen_runs:
            seen_runs.add(rid)
            run_order.append(rid)
        rows.append(d)

if list_runs:
    print(json.dumps({"list_runs": run_order}))
    sys.exit(0)

if not run_arg or run_arg == "latest":
    run_id = run_order[-1] if run_order else ""
else:
    run_id = run_arg

if not run_id:
    print(json.dumps({"error": "no runId present in the event log"}))
    sys.exit(0)
if run_id not in seen_runs:
    print(json.dumps({"error": "unknown runId: %s" % run_id, "known": run_order[-8:]}))
    sys.exit(0)

ev = [d for d in rows if (d.get("runId") or "") == run_id]

# --- fold per repo -----------------------------------------------------------
# The empty-tail integrator signature. The TAIL is what matters: a NON-empty tail
# means integrate.sh ran and printed something unparseable (a different defect);
# an EMPTY tail means it produced nothing at all — the dispatch never landed.
# A SECOND, equally "the integrator never ran" signature (relay-loop.js:3219): the
# mechanical integrate.sh hop was REFUSED at dispatch (a classifier block, an
# install-drift 404, …) before it could run at all. Per the 2026-08-21 incident THIS
# branch, not the empty-tail one, is how three of four evaporations actually happened —
# and the empty-tail-only regex missed every one of them. Same cause-unknown set.
EVAP_RE = re.compile(
    r"no merged= line \(unparseable integrator output\):\s*$"
    r"|integrate\.sh mechanical hop failed to dispatch \("
)
EXCLUDED_RE = re.compile(r"excluded-by-config|excluded for this run")

# The one-word skip categories (relay-loop.js:430) that are BENIGN under
# one-unit-per-repo-per-round: the repo was passed over for a reason that is the pool
# working, not the pool failing. Matched as narrow literal tokens ON PURPOSE — a looser
# `worktree`/`claim` match would swallow the loderite reason ("stale worktree … from a
# dead run"), which is a REAL anomaly and must keep firing.
BENIGN_SKIP_RE = re.compile(r"claimed-elsewhere|dirty-worktree|\bintensive\b")

per = {}
def slot(repo):
    return per.setdefault(repo, {
        "dispatch": [], "integrate": [], "handback": [],
        "verdict": "", "verdict_reason": "", "excluded": False,
        # verdict_seen, not `verdict`: a verdict EVENT may carry an empty verdict string
        # (an excluded repo does). Scope is about the event existing, not its value.
        "verdict_seen": False,
    })

for d in ev:
    kind = d.get("kind") or ""
    repo = d.get("repo") or ""
    if not repo:
        continue
    s = slot(repo)
    if kind == "dispatch":
        s["dispatch"].append({"mode": d.get("mode") or "", "round": d.get("round") or 0,
                              "item": d.get("item") or ""})
    elif kind == "integrate":
        s["integrate"].append({"mode": d.get("mode") or "", "ckpt": d.get("ckpt") or "",
                               "ids": d.get("ids") or []})
    elif kind == "handback":
        reason = d.get("reason") or ""
        s["handback"].append({"mode": d.get("mode") or "", "reason": reason,
                              "evaporated": bool(EVAP_RE.search(reason))})
    elif kind == "verdict":
        # LAST verdict wins — a repo may be re-classified across rounds.
        s["verdict_seen"] = True
        s["verdict"] = d.get("verdict") or ""
        s["verdict_reason"] = d.get("reason") or ""
        if EXCLUDED_RE.search(d.get("reason") or ""):
            s["excluded"] = True

# --- RELAY_STATUS.md: the skip/blocked rows for THIS run ----------------------
# The file is a concatenation of per-run sections delimited by
#   <!-- relay-run:<runId> --> … <!-- /relay-run:<runId> -->
# (id:0f9e merged per-run file). We read ONLY this run's section; a reason may wrap
# over continuation lines, so a row starts at a `- ` at column 0 and the first line
# of the reason is what we report.
#
# FOUR headings are read, not two. `## Skipped` / `## Blocked / HANDBACKs` were the
# original pair; `## Queued` holds a quota-stopped run's classified-but-undispatched
# units and `## In-flight` holds units still executing. A scan that never reads those two
# reports a healthy quota-stop, and a healthy still-running run, as anomalies.
status_rows = {}     # repo -> {"section": "skipped"|"blocked", "reason": ...}
queued_rows = {}     # repo -> verdict text  (classified, not yet given a turn)
inflight_rows = {}   # repo -> detail text   (a unit still executing right now)
status_present = os.path.exists(status_path)
status_section_found = False
if status_present:
    with open(status_path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    start = text.find("<!-- relay-run:%s -->" % run_id)
    if start >= 0:
        end = text.find("<!-- /relay-run:%s -->" % run_id, start)
        section_text = text[start:end if end > start else len(text)]
        status_section_found = True
    else:
        # A single-run file predating the per-run delimiters, or a status write that
        # never landed for this run. Only trust it when the file names this run.
        section_text = text if run_id in text else ""
        status_section_found = bool(section_text)
    cur = None
    for line in section_text.splitlines():
        m = re.match(r"^##+\s+(.*?)\s*$", line)
        if m:
            head = m.group(1).lower()
            if head.startswith("skipped"):
                cur = "skipped"
            elif head.startswith("blocked"):
                cur = "blocked"
            elif head.startswith("queued"):
                cur = "queued"
            elif head.startswith("in-flight") or head.startswith("in flight"):
                cur = "inflight"
            else:
                cur = None
            continue
        if cur and line.startswith("- "):
            body = line[2:].strip()
            if not body or body.startswith("_("):
                continue
            parts = body.split(None, 1)
            repo = parts[0]
            reason = parts[1] if len(parts) > 1 else ""
            reason = re.sub(r"\s+worktree=\S*$", "", reason).strip()
            if cur == "queued":
                queued_rows.setdefault(repo, reason)
            elif cur == "inflight":
                inflight_rows.setdefault(repo, reason)
            else:
                # first row for a repo wins (a repo can be rendered twice across rounds)
                status_rows.setdefault(repo, {"section": cur, "reason": reason})

# --- candidate set for (re)classification ------------------------------------
# Only repos that could possibly BE an anomaly: an own repo that either got no
# dispatch this run, or ended in a skip/blocked section. Deliberately excluded /
# paused repos are dropped here — they are the configuration working, not a defect,
# and re-classifying them would burn time to produce guaranteed non-findings.
#
# SCOPE (see the header's RUN SCOPE block). `scope_known` is a RUN-level fact: this run
# emitted at least one verdict event, so relay-loop.js:2143-2145's one-verdict-per-
# in-scope-repo-per-round invariant makes the observed set authoritative. With no verdict
# events at all there is no scope evidence and NO filtering happens — fail-open, so a run
# whose verdict rows are themselves what went missing still gets every repo checked.
scope_known = any(bool(s["verdict"]) or s["excluded"] or s["verdict_seen"] for s in per.values())

candidates = []
dropped_out_of_scope = []
for name, path in own:
    if only_repo and name != only_repo:
        continue
    s = per.get(name)
    if s and s["excluded"]:
        continue
    # Queued = classified and accounted for, just not this run's turn (quota-stop /
    # end-of-run leftover). The configuration working, not a repo the run starved.
    if name in queued_rows:
        continue
    if scope_known:
        in_scope = (name in per) or (name in status_rows) or (name in inflight_rows)
        if not in_scope:
            dropped_out_of_scope.append(name)
            continue
    dispatched = len(s["dispatch"]) if s else 0
    in_status = name in status_rows
    if dispatched == 0 or in_status:
        candidates.append(name)

# touched(repo) == 0 iff the repo has ZERO work-unit trace this run — the exact
# STARVED-candidate population. --fast's hybrid mode needs it to decide which candidates
# must be live-reclassified regardless; the report step re-derives the identical number
# for its own STARVED test, so the formula lives in exactly these two places.
def touched_count(name):
    s = per.get(name)
    if not s:
        return 0
    return len(s["dispatch"]) + len(s["integrate"]) + len(s["handback"])

# The bash classify loop reads this TSV directly — one file, no per-repo python spawn.
# Column 3 is "1" when the candidate has zero work-unit trace this run, "0" otherwise.
with open(os.environ["CAND_TSV"], "w", encoding="utf-8") as f:
    for name in candidates:
        f.write("%s\t%s\t%s\n"
                % (name, own_paths.get(name, ""), "1" if touched_count(name) == 0 else "0"))

out = {
    "run_id": run_id,
    "events_path": events_path,
    "status_path": status_path,
    "status_present": status_present,
    "status_section_found": status_section_found,
    "malformed_event_lines": malformed,
    "own_count": len(own),
    "own_paths": own_paths,
    "per_repo": per,
    "status_rows": status_rows,
    "queued_rows": queued_rows,
    "inflight_rows": inflight_rows,
    "scope_known": scope_known,
    "dropped_out_of_scope": dropped_out_of_scope,
    "candidates": candidates,
    "zero_trace": [n for n in candidates if touched_count(n) == 0],
    "totals": {
        "dispatched": sum(len(v["dispatch"]) for v in per.values()),
        "integrated": sum(len(v["integrate"]) for v in per.values()),
        "handbacks":  sum(len(v["handback"]) for v in per.values()),
    },
}
print(json.dumps(out))
PY_FOLD

# --list-runs short-circuit ------------------------------------------------------
if [[ "$list_runs" -eq 1 ]]; then
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for r in d.get("list_runs", []): print(r)
' "$facts_json"
  exit 0
fi

# A resolution error (no runs / unknown runId) is MISUSE — loud, nonzero, never a
# quiet "clean" report.
err="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("error",""))
if d.get("known"): print("known runIds (most recent last): " + ", ".join(d["known"]), file=sys.stderr)
' "$facts_json")"
if [[ -n "$err" ]]; then
  echo "run-anomaly-scan.sh: $err" >&2
  exit 2
fi

# --- run liveness: is the run being audited STILL RUNNING? ----------------------
# Reuses relay-status-publish.sh:158's own live-runs query verbatim — no new liveness
# check, no second notion of "alive". FAIL-OPEN in the safe direction: any failure here
# leaves run_alive=0, which SUPPRESSES NOTHING. A false "alive" would hide real findings;
# a false "dead" merely reports an in-flight unit early.
resolved_run="$(python3 -c '
import json,sys
print(json.load(open(sys.argv[1]))["run_id"])' "$facts_json")"
run_alive=0
if [[ -x "$HEARTBEAT_SH" ]]; then
  # jq drains the whole stream; no early-exiting consumer anywhere in this pipeline.
  live_runs="$("$HEARTBEAT_SH" live-runs 2>>"$LOG" | jq -r 'select(.state=="alive") | .runId' 2>>"$LOG" || true)"
  while IFS= read -r _r; do
    [[ "$_r" == "$resolved_run" ]] && run_alive=1
  done <<<"$live_runs"
fi
log "run=$resolved_run alive=$run_alive"

# --- pass 1b: (re)classify each candidate --------------------------------------
# The LIVE verdict is the authority for STARVED / SKIPPED-WITH-ACTIONABLE — the whole
# point is that the run's own recorded verdict may be stale, or may have been correct
# while the dispatch still never happened (loderite recorded `execute` and was skipped
# anyway). --fast trades that for the recorded verdict and SAYS SO in the report.
: > "$cls_tsv"
classify_mode="live"

# One candidate -> one `<name>\t<verdict>\t<count>\t<ids-csv>` line appended to $CLS_TSV.
# Each line is a few hundred bytes, far under PIPE_BUF, and every writer opens with
# O_APPEND (`>>`), so the parallel appends below cannot interleave within a line.
classify_one() {
  local line="$1" name path zero_trace out
  # THREE columns since the --fast hybrid landed. Reading only two silently folds the
  # trailing field into $path, every path then fails `-d`, every candidate classifies
  # "unreadable", and STARVED stops firing entirely — which is exactly how an earlier
  # attempt at these guards broke the tool while looking like a formatting detail.
  IFS=$'\t' read -r name path zero_trace <<<"$line"
  [[ -n "$name" ]] || return 0
  if [[ -z "$path" || ! -d "$path" ]]; then
    # Surfaced, never swallowed (id:4e14): a registered repo whose path is gone is
    # itself worth knowing, but it cannot be classified.
    printf '%s\tunreadable\t0\t\n' "$name" >> "$CLS_TSV"
    printf '%s run-anomaly-scan.sh candidate=%s path-missing=%s\n' \
      "$(date '+%Y-%m-%dT%H:%M:%S')" "$name" "${path:-<none>}" >> "$LOG" 2>/dev/null || true
    return 0
  fi
  # classify-repo.sh's own stderr is log noise (a missing ROADMAP is normal for a fresh
  # repo); it goes to the log file, never to /dev/null.
  if out="$("$CLASSIFY_REPO" --repo "$name" --path "$path" 2>>"$LOG")"; then
    printf '%s\t%s\n' "$name" "$(printf '%s' "$out" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("classify-error\t0\t"); raise SystemExit(0)
ids=d.get("actionable_routine_ids") or []
print("%s\t%s\t%s" % (d.get("verdict",""), d.get("actionable_routine_open",0), ",".join(x for x in ids if x)))
')" >> "$CLS_TSV"
  else
    printf '%s\tclassify-error\t0\t\n' "$name" >> "$CLS_TSV"
    printf '%s run-anomaly-scan.sh candidate=%s classify-failed\n' \
      "$(date '+%Y-%m-%dT%H:%M:%S')" "$name" >> "$LOG" 2>/dev/null || true
  fi
}
export -f classify_one
export CLASSIFY_REPO CLS_TSV="$cls_tsv" LOG

if [[ "$fast" -eq 1 ]]; then
  # HYBRID (id:87a7), not "recorded". The zero-work-unit-trace candidates — column 3 == 1,
  # the STARVED-candidate population and empirically a handful of repos — are STILL
  # classified live, because a recorded verdict cannot answer "is this repo starved"
  # (loderite recorded `execute` and was skipped anyway). Everything else falls back to
  # the recorded verdict. The alternative, which this replaces, printed
  # `clean: … STARVED` for a class it had not examined.
  classify_mode="hybrid"
  fast_tsv="$wk/candidates-fast.tsv"
  awk -F'\t' '$3 == "1"' "$cand_tsv" > "$fast_tsv"
  jobs="${RUN_ANOMALY_JOBS:-$(nproc 2>/dev/null || echo 4)}"
  xargs -d '\n' -r -n 1 -P "$jobs" bash -c 'classify_one "$1"' _ < "$fast_tsv"
else
  # Fan out: a fleet-wide scan is ~50 independent read-only classify-repo.sh calls, and
  # serially that is minutes of wall time for an END-OF-RUN check nobody will wait for
  # (the id:4347 anti-pattern arrives via "too slow to run" just as surely as via "not
  # wired"). Bounded by nproc; RUN_ANOMALY_JOBS=1 restores the serial order for debugging.
  jobs="${RUN_ANOMALY_JOBS:-$(nproc 2>/dev/null || echo 4)}"
  xargs -d '\n' -r -n 1 -P "$jobs" bash -c 'classify_one "$1"' _ < "$cand_tsv"
fi

# --- pass 2: derive findings + render ------------------------------------------
rc=0
FACTS="$facts_json" CLS="$cls_tsv" CLASSIFY_MODE="$classify_mode" \
AS_JSON="$as_json" STRICT="$strict" ONLY_REPO="$only_repo" RUN_ALIVE="$run_alive" \
python3 - <<'PY_REPORT' || rc=$?
import json, os, re, sys

facts = json.load(open(os.environ["FACTS"], encoding="utf-8"))
as_json = os.environ.get("AS_JSON") == "1"
strict  = os.environ.get("STRICT") == "1"
mode    = os.environ.get("CLASSIFY_MODE", "live")
only_repo = os.environ.get("ONLY_REPO", "").strip()

run_alive = os.environ.get("RUN_ALIVE") == "1"

per        = facts["per_repo"]
status_rows= facts["status_rows"]
inflight_rows = facts.get("inflight_rows") or {}
zero_trace = set(facts.get("zero_trace") or [])
own_paths  = facts["own_paths"]
totals     = facts["totals"]
run_id     = facts["run_id"]

# Verdicts the POOL can actually dispatch. `human`, `mechanical`, `idle` and `blocked`
# are non-dispatchable BY DESIGN — a repo sitting at one of those is not starved.
POOL_ACTIONABLE = {"execute", "review", "hard", "handoff"}

# The one-word skip categories (relay-loop.js:430) that are benign under
# one-unit-per-repo-per-round. NARROW literal tokens on purpose: a looser `worktree` or
# `claim` match would swallow the loderite reason ("stale worktree … from a dead run"),
# a REAL anomaly that must keep firing.
BENIGN_SKIP_RE = re.compile(r"claimed-elsewhere|dirty-worktree|\bintensive\b")

cls = {}
live_names = set()      # candidates whose verdict came from a LIVE classify this scan
with open(os.environ["CLS"], encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        name = parts[0]
        verdict = parts[1]
        count = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
        ids = [x for x in (parts[3].split(",") if len(parts) > 3 and parts[3] else [])]
        cls[name] = {"verdict": verdict, "count": count, "ids": ids}
        live_names.add(name)
# hybrid (--fast): everything the live pass did NOT cover falls back to the run's own
# recorded verdict. In full LIVE mode the live pass covered every candidate, so this loop
# adds nothing — the fallback is not a second code path to keep in sync.
for name in facts["candidates"]:
    if name in cls:
        continue
    s = per.get(name) or {}
    cls[name] = {"verdict": s.get("verdict", ""), "count": 0, "ids": []}
recorded_names = [n for n in facts["candidates"] if n not in live_names]

findings = []
def add(cls_name, repo, detail, nxt, **extra):
    f = {"class": cls_name, "repo": repo, "detail": detail, "next": nxt}
    f.update(extra)
    findings.append(f)

def short(s, n=110):
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"

# in_flight_suppressed(repo): the run is CONFIRMED still alive AND this repo has a
# `## In-flight` row — the unit is executing right now, so "no outcome yet" is the
# expected state, not an evaporation. BOTH conjuncts are required: liveness alone would
# silence a repo whose unit really did evaporate in a run that is still going, and an
# In-flight row alone would silence every unit stranded by a dead run, which is precisely
# the DISPATCHED-BUT-NO-OUTCOME case this tool was built for.
def in_flight_suppressed(repo):
    return run_alive and repo in inflight_rows

# --- ZERO-YIELD-RUN ------------------------------------------------------------
# Same conjunction, at run level: a live run with units still in flight has not yet had
# its chance to yield. A DEAD run with nothing integrated still reports, in-flight rows
# and all — a dead run's in-flight rows are stranded units, not pending ones.
if run_alive and inflight_rows:
    pass
elif totals["dispatched"] > 0 and totals["integrated"] == 0:
    add("ZERO-YIELD-RUN", "-",
        "dispatched=%d but integrated=0 — every unit this run failed to land" % totals["dispatched"],
        "bash relay/scripts/check-install-drift.sh --canonical relay/scripts "
        "--installed ~/.claude/skills/relay/scripts")

# --- INTEGRATE-EVAPORATED ------------------------------------------------------
for repo in sorted(per):
    if only_repo and repo != only_repo:
        continue
    evap = [h for h in per[repo]["handback"] if h["evaporated"]]
    if not evap:
        continue
    modes = ",".join(sorted({h["mode"] for h in evap if h["mode"]})) or "-"
    add("INTEGRATE-EVAPORATED", repo,
        "%d handback(s) with an EMPTY 'no merged= line' signature (mode=%s) — the integrator "
        "produced no output at all. CAUSE UNKNOWN: a dispatch-layer classifier block, an "
        "install-drift 404, and an integrate.sh crash are indistinguishable here (id:f5d9(b))."
        % (len(evap), modes),
        "bash relay/scripts/check-install-drift.sh --canonical relay/scripts "
        "--installed ~/.claude/skills/relay/scripts   # rules out cause 2 of 3",
        count=len(evap))

# --- DISPATCHED-BUT-NO-OUTCOME -------------------------------------------------
# Matched per (repo, mode): a dispatch of mode M with no integrate/handback of mode M.
for repo in sorted(per):
    if only_repo and repo != only_repo:
        continue
    if in_flight_suppressed(repo):
        continue
    s = per[repo]
    from collections import Counter
    d_modes = Counter(x["mode"] for x in s["dispatch"])
    o_modes = Counter(x["mode"] for x in s["integrate"]) + Counter(x["mode"] for x in s["handback"])
    orphaned = []
    for m, n in d_modes.items():
        missing = n - o_modes.get(m, 0)
        if missing > 0:
            orphaned.append((m or "-", missing))
    if orphaned:
        desc = ", ".join("mode=%s x%d" % (m, n) for m, n in sorted(orphaned))
        add("DISPATCHED-BUT-NO-OUTCOME", repo,
            "dispatched with no integrate and no handback (%s) — the unit evaporated mid-flight" % desc,
            "grep '\"runId\":\"%s\"' %s | grep '\"repo\":\"%s\"'"
            % (run_id, facts["events_path"], repo),
            count=sum(n for _, n in orphaned))

# --- STARVED / SKIPPED-WITH-ACTIONABLE ----------------------------------------
UNVERIFIABLE = {"classify-error", "unreadable"}
for repo in sorted(cls):
    c = cls[repo]
    if c["verdict"] in UNVERIFIABLE and repo in zero_trace:
        # Absence of evidence is NEVER rendered as clean. A zero-trace repo whose live
        # classification failed is the one population where "not pool-actionable" cannot
        # be concluded — dropping it here is how a scanner reports a clean fleet it never
        # actually checked.
        add("STARVED-UNVERIFIED", repo,
            "zero work-unit trace this run AND its live classification failed (%s) — this "
            "repo could NOT be checked for STARVED; it is reported, never assumed clean"
            % c["verdict"],
            "bash relay/scripts/classify-repo.sh --repo %s --path %s"
            % (repo, own_paths.get(repo, "")),
            verdict=c["verdict"], count=0, ids=[])
        continue
    if c["verdict"] not in POOL_ACTIONABLE:
        continue
    s = per.get(repo) or {}
    # "The run dispatched nothing for it" is falsified by ANY work-unit trace, not just a
    # `dispatch` row: the event log does drop rows (csgebra, run …174757: dispatched,
    # rendered Completed with a ckpt, yet no `integrate` event was ever written), so
    # keying STARVED on the dispatch row ALONE manufactures a false positive for a repo
    # that plainly ran. Requiring zero dispatch AND zero integrate AND zero handback keeps
    # the loderite case (no trace of any kind) and drops the log-gap cases, which the
    # DISPATCHED-BUT-NO-OUTCOME class already owns.
    touched = (len(s.get("dispatch") or []) + len(s.get("integrate") or [])
               + len(s.get("handback") or []))
    dispatched = touched
    row = status_rows.get(repo)
    reason = short(row["reason"]) if row else ""
    items = c["count"]
    ids = ",".join(c["ids"][:8]) if c["ids"] else ""
    item_txt = "%d actionable [ROUTINE] item(s)%s" % (items, (" (%s)" % ids) if ids else "")
    if items == 0:
        item_txt = "verdict=%s (no [ROUTINE] count applies to this verdict)" % c["verdict"]
    path = own_paths.get(repo, "")
    if dispatched == 0:
        nxt = "bash relay/scripts/classify-repo.sh --repo %s --path %s" % (repo, path)
        if row and ("worktree" in row["reason"] or "branch" in row["reason"]):
            nxt = "git -C %s worktree list   # then: bash relay/scripts/relay-reconcile.sh %s" % (path, path)
        add("STARVED", repo,
            "classifies %s with %s, yet this run dispatched NOTHING for it%s"
            % (c["verdict"], item_txt, ("; RELAY_STATUS %s: %s" % (row["section"], reason)) if row else ""),
            nxt, verdict=c["verdict"], count=items, ids=c["ids"])
    elif row:
        # TWO false-positive sources, both of them the pool WORKING:
        #   (a) the handback accumulator — state.handbacks is push-only and never reset
        #       all run (relay-loop.js:425), so a repo handed back in round 1 and
        #       INTEGRATED in round 2 keeps its Blocked row for the rest of the run;
        #   (b) a benign per-round skip category — under one-unit-per-repo-per-round a
        #       backlog repo is EXPECTED to be passed over once its unit has landed.
        # Both are gated on the repo having actually got somewhere this run, so a repo
        # that was blocked or skipped and NEVER worked still reports. And neither guard
        # touches STARVED: a zero-trace repo carrying `claimed-elsewhere` may be sitting
        # behind a STALE claim, which is the loderite failure wearing a benign label.
        if per.get(repo, {}).get("integrate"):
            continue
        if BENIGN_SKIP_RE.search(row["reason"] or "") and touched > 0:
            continue
        add("SKIPPED-WITH-ACTIONABLE", repo,
            "ends the run in RELAY_STATUS '%s' (%s) but still classifies %s with %s"
            % (row["section"], reason, c["verdict"], item_txt),
            "bash relay/scripts/classify-repo.sh --repo %s --path %s" % (repo, path),
            verdict=c["verdict"], count=items, ids=c["ids"])

ORDER = ["ZERO-YIELD-RUN", "STARVED", "STARVED-UNVERIFIED", "DISPATCHED-BUT-NO-OUTCOME",
         "INTEGRATE-EVAPORATED", "SKIPPED-WITH-ACTIONABLE"]
findings.sort(key=lambda f: (ORDER.index(f["class"]) if f["class"] in ORDER else 99, f["repo"]))

if as_json:
    print(json.dumps({
        "run_id": run_id,
        "classify_mode": mode,
        "events_path": facts["events_path"],
        "status_path": facts["status_path"],
        "status_section_found": facts["status_section_found"],
        "malformed_event_lines": facts["malformed_event_lines"],
        "own_count": facts["own_count"],
        "reclassified": len(live_names),
        "live_classified": sorted(live_names),
        "recorded_verdicts": sorted(recorded_names),
        "run_alive": run_alive,
        "in_flight": sorted(inflight_rows),
        "queued": sorted(facts.get("queued_rows") or {}),
        "scope_known": facts.get("scope_known", False),
        "out_of_scope": sorted(facts.get("dropped_out_of_scope") or []),
        "totals": totals,
        "findings": findings,
        "strict": strict,
    }, indent=2))
else:
    print("=== run-anomaly-scan — run %s ===" % run_id)
    print("events=%s  status=%s%s"
          % (facts["events_path"], facts["status_path"],
             "" if facts["status_present"] else "  (MISSING)"))
    print("totals: dispatched=%d  integrated=%d  handbacks=%d  own-repos=%d  "
          "classified=%s (%s)"
          % (totals["dispatched"], totals["integrated"], totals["handbacks"],
             facts["own_count"], len(cls), mode))
    if mode == "hybrid":
        # Names WHICH repos were live vs recorded. A blanket "--fast is blind" note lets a
        # reader treat every class as unchecked; the point of the hybrid is that STARVED
        # was checked, live, for exactly the repos where it could apply.
        print("NOTE: --fast HYBRID — %d zero-work-unit-trace repo(s) were live-reclassified "
              "so the STARVED class is NOT skipped%s; the other %d candidate(s) reuse the "
              "run's RECORDED verdict and are blind to state changed since%s."
              % (len(live_names),
                 (" (%s)" % ", ".join(sorted(live_names))) if live_names else "",
                 len(recorded_names),
                 (" (%s)" % ", ".join(recorded_names[:8])) if recorded_names else ""))
    if facts.get("scope_known") and facts.get("dropped_out_of_scope"):
        print("NOTE: %d own repo(s) were NOT in this run's scope (no verdict event, no "
              "trace, no status row) and are not candidates: %s."
              % (len(facts["dropped_out_of_scope"]),
                 ", ".join(facts["dropped_out_of_scope"][:8])))
    if run_alive:
        print("NOTE: run %s is STILL ALIVE (heartbeat.sh live-runs) — %d in-flight unit(s) "
              "are exempt from the mid-flight anomaly classes." % (run_id, len(inflight_rows)))
    if not facts["status_section_found"]:
        print("NOTE: no RELAY_STATUS section for this run — the SKIPPED-WITH-ACTIONABLE "
              "class had nothing to read (a status-hop failure is itself worth checking).")
    if facts["malformed_event_lines"]:
        print("NOTE: %d malformed line(s) in the event log were skipped."
              % facts["malformed_event_lines"])
    print()
    if not findings:
        print("no anomalies: every own repo either got a dispatch, is deliberately "
              "excluded/paused, or classifies non-actionable.")
    else:
        cur = None
        for f in findings:
            if f["class"] != cur:
                cur = f["class"]
                print("--- %s ---" % cur)
            print("! %s: %s" % (f["repo"], f["detail"]))
            print("    next: %s" % f["next"])
        clean = [c for c in ORDER if not any(f["class"] == c for f in findings)]
        if clean:
            print()
            print("clean: " + ", ".join(clean))
    print()
    print("=== summary ===")
    print("%d finding(s) across %d repo(s) in run %s"
          % (len(findings), len({f["repo"] for f in findings if f["repo"] != "-"}), run_id))
    if strict:
        print("--strict: exits nonzero when any finding is surfaced.")
    else:
        print("REPORT-ONLY: exits 0 regardless of findings (use --strict for a "
              "nonzero-on-findings gate).")

if strict and findings:
    sys.exit(1)
sys.exit(0)
PY_REPORT

log "run=$run_id strict=$strict json=$as_json mode=$classify_mode rc=$rc"
exit "$rc"
