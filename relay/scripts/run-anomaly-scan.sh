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
#   ZERO-YIELD-RUN              dispatched > 0 but integrated == 0. Run-level. Suppressed
#                               when the run is confirmed still ALIVE (heartbeat.sh
#                               live-runs) and it has units in `## In-flight` — a unit
#                               still running has not yet had the chance to yield.
#                               (relay-events.jsonl x RELAY_STATUS.md `## In-flight` x
#                               heartbeat.sh live-runs)
#   SKIPPED-WITH-ACTIONABLE     a repo rendered into RELAY_STATUS.md's `Skipped` or
#                               `Blocked / HANDBACKs` section for this run that
#                               NONETHELESS classifies pool-actionable, with its item
#                               count — UNLESS the repo already has an `integrate` event
#                               THIS run (one-unit-per-repo-per-round means a landed repo
#                               is EXPECTED to show a stale/later-round Blocked or Skipped
#                               row; that is the accumulator/benign-per-round-skip case,
#                               not a defect). (RELAY_STATUS.md x classify-repo.sh x
#                               relay-events.jsonl)
#   STARVED-UNVERIFIED          a zero-work-unit-trace repo that classify-repo.sh could
#                               NOT classify this scan (classify-error / path missing).
#                               Absence of evidence is never rendered as "clean" — this
#                               fires instead of silently skipping the repo.
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
#   `## Queued` (id:baf1/quota-deferred classified-but-undispatched units, produced by a
#   quota-stopped --afk run) — it was seen and accounted for, just not this run's turn.
#
#   A repo that shows up NOWHERE in this run's data at all — no verdict event (id:e87d:
#   EVERY own repo in scope gets exactly one verdict event per round, so a repo with zero
#   verdict events was never IN this run's scope) and no dispatch/integrate/handback/
#   status row — is likewise never a candidate. This is what keeps a `--only <repo>`-
#   scoped run (relay-loop.js:1803-1812 drops out-of-scope repos before sharding) from
#   flagging the rest of the fleet STARVED: they were never asked about, not starved.
#
# Usage:
#   run-anomaly-scan.sh [RUN_ID] [--strict] [--json] [--fast] [--repo <name>]
#     RUN_ID       the run to audit; omit (or pass `latest`) for the most recent runId
#                  present in the event log.
#     --strict     exit nonzero when any finding is surfaced (default: always exit 0).
#     --json       emit one JSON object instead of the human report.
#     --fast       HYBRID, not fully recorded (id:87a7): a repo with ZERO work-unit trace
#                  this run (no dispatch/integrate/handback — the exact STARVED-candidate
#                  population, empirically a handful of repos, not the whole fleet) is
#                  STILL live-reclassified, because that is the one class this tool exists
#                  to catch and a recorded verdict cannot answer "is this repo starved" by
#                  construction (a starved repo has no recorded outcome to trust either).
#                  Every OTHER candidate (one with SOME trace — a status row, a dispatch)
#                  reuses the run's own recorded `verdict` event, cheaply. If a zero-trace
#                  repo's live reclassification itself fails (classify-error / path
#                  gone), it is reported STARVED-UNVERIFIED, never silently "clean" — a
#                  mode that cannot check a class must never print that class as clean.
#                  The report names which repos were live vs recorded.
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
#                         answer "is this run still alive" for the In-flight suppression;
#                         reuses relay-status-publish.sh:158's own live-runs query, never a
#                         new liveness check.
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
      # id:0fa0-style: compute the header range so a future header edit can't truncate
      # --help (the hardcoded '2,86p' had already drifted before this fix). No pipe into
      # an early-exiting consumer (banned): grep drains fully, bash expansion takes the
      # first match instead of `| head -1`.
      _gn="$(grep -n '^set -euo pipefail' "$0")"
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
# An ABSENT relay.toml is a distinct misuse case from a CORRUPT one: lib-own-repos.sh's
# own_repos() returns 0 with NO output when $RELAY_TOML does not exist at all (a valid
# "no registry yet" state for ITS callers, which mutate/build one) — but for a SCANNER
# that only ever reads, "no registry" means own-repos=0, no candidates, no findings,
# exit 0: a false-clean report, exactly the failure this tool's own header calls worse
# than no scanner. Check existence explicitly, before ever calling own_repos().
if [[ ! -f "$RELAY_TOML" ]]; then
  echo "run-anomaly-scan.sh: relay.toml not found: $RELAY_TOML" >&2
  echo "run-anomaly-scan.sh: refusing to report clean when the own-repo registry is unreadable (id:0fa0)." >&2
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
# an EMPTY tail means it produced nothing at all — the dispatch never landed. A SECOND,
# equally-"the-integrator-never-ran" signature (relay-loop.js:3219): the mechanical
# integrate.sh hop itself was REFUSED to dispatch (a classifier block, a missing-skill
# 404, …) before it could run at all — id:f5d9(b)'s cause-unknown set applies here too,
# and per the 2026-08-21 incident this branch, not the empty-tail one, was how three of
# four evaporations actually happened.
EVAP_RE = re.compile(
    r"no merged= line \(unparseable integrator output\):\s*$"
    r"|integrate\.sh mechanical hop failed to dispatch \("
)
EXCLUDED_RE = re.compile(r"excluded-by-config|excluded for this run")

per = {}
def slot(repo):
    return per.setdefault(repo, {
        "dispatch": [], "integrate": [], "handback": [],
        "verdict": "", "verdict_reason": "", "excluded": False,
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
        s["verdict"] = d.get("verdict") or ""
        s["verdict_reason"] = d.get("reason") or ""
        if EXCLUDED_RE.search(d.get("reason") or ""):
            s["excluded"] = True

# --- RELAY_STATUS.md: the skip/blocked/queued/in-flight rows for THIS run -----
# The file is a concatenation of per-run sections delimited by
#   <!-- relay-run:<runId> --> … <!-- /relay-run:<runId> -->
# (id:0f9e merged per-run file). We read ONLY this run's section; a reason may wrap
# over continuation lines, so a row starts at a `- ` at column 0 and the first line
# of the reason is what we report.
#
# FOUR headings are read, not two: `## Skipped` / `## Blocked / HANDBACKs` were the
# original pair, but a quota-stopped --afk run puts classified-but-undispatched units in
# `## Queued` (relay-loop.js:3709 quota-deferred, :4054 end-of-run leftover queue) and a
# still-running unit in `## In-flight` — a scanner that never reads those two renders a
# healthy quota-stop or a healthy in-flight run as STARVED, because "no dispatch trace
# yet" looks identical to "starved" without them.
status_rows = {}     # repo -> {"section": "skipped"|"blocked", "reason": ...}
queued_rows = {}      # repo -> verdict text (classified, not yet dispatched this run)
inflight_rows = {}    # repo -> raw detail (mode=/agent=… — a unit still executing)
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
# dispatch this run, or ended in a skip/blocked section. Deliberately excluded/paused
# repos are dropped here — they are the configuration working, not a defect, and
# re-classifying them would burn time to produce guaranteed non-findings. So are
# Queued repos: they WERE classified and accounted for this run, just not yet given a
# turn (quota-stopped or end-of-run leftover) — that is the configuration working too,
# not a repo the run "starved".
#
# A repo with NO trace of any kind this run — no verdict event (id:e87d: every own
# repo IN SCOPE gets exactly one verdict event per round, across units/surfaced/
# skipped), no dispatch/integrate/handback, no status/queued/in-flight row — was never
# part of this run's own-repo scope at all, and is likewise never a candidate. This is
# what a `--only <repo>` scoped run needs (relay-loop.js:1803-1812 drops out-of-scope
# repos before sharding): without it, the other 52 repos in a 53-repo fleet would
# report STARVED for a run that never asked about them.
candidates = []
for name, path in own:
    if only_repo and name != only_repo:
        continue
    s = per.get(name)
    if s and s["excluded"]:
        continue
    if name in queued_rows:
        continue
    in_run_scope = (name in per) or (name in status_rows) or (name in inflight_rows)
    if not in_run_scope:
        continue
    dispatched = len(s["dispatch"]) if s else 0
    in_status = name in status_rows
    if dispatched == 0 or in_status:
        candidates.append(name)

# touched(repo) = 0 iff the repo has ZERO work-unit trace this run (dispatch, integrate,
# AND handback all empty) — the exact STARVED-candidate population. --fast's hybrid
# mode (id:87a7) needs this to decide which candidates are cheap+correct to always live-
# reclassify (typically a handful of repos, not the whole fleet); computed once here so
# bash and the report step (which recomputes the identical formula for its own STARVED
# test) never drift against each other in more than this one place.
def touched_count(name):
    s = per.get(name)
    if not s:
        return 0
    return len(s["dispatch"]) + len(s["integrate"]) + len(s["handback"])

# The bash classify loop reads this TSV directly — one file, no per-repo python spawn.
# Column 3 is "1" when the candidate has zero work-unit trace this run (see touched_count
# above), "0" otherwise — --fast uses it to restrict live reclassification.
with open(os.environ["CAND_TSV"], "w", encoding="utf-8") as f:
    for name in candidates:
        zero_trace = "1" if touched_count(name) == 0 else "0"
        f.write("%s\t%s\t%s\n" % (name, own_paths.get(name, ""), zero_trace))

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
    "candidates": candidates,
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
  local line="$1" name path out
  IFS=$'\t' read -r name path <<<"$line"
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
  classify_mode="recorded"
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
AS_JSON="$as_json" STRICT="$strict" ONLY_REPO="$only_repo" \
python3 - <<'PY_REPORT' || rc=$?
import json, os, sys

facts = json.load(open(os.environ["FACTS"], encoding="utf-8"))
as_json = os.environ.get("AS_JSON") == "1"
strict  = os.environ.get("STRICT") == "1"
mode    = os.environ.get("CLASSIFY_MODE", "live")
only_repo = os.environ.get("ONLY_REPO", "").strip()

per        = facts["per_repo"]
status_rows= facts["status_rows"]
own_paths  = facts["own_paths"]
totals     = facts["totals"]
run_id     = facts["run_id"]

# Verdicts the POOL can actually dispatch. `human`, `mechanical`, `idle` and `blocked`
# are non-dispatchable BY DESIGN — a repo sitting at one of those is not starved.
POOL_ACTIONABLE = {"execute", "review", "hard", "handoff"}

cls = {}
if mode == "live":
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
else:
    for name in facts["candidates"]:
        s = per.get(name) or {}
        cls[name] = {"verdict": s.get("verdict", ""), "count": 0, "ids": []}

findings = []
def add(cls_name, repo, detail, nxt, **extra):
    f = {"class": cls_name, "repo": repo, "detail": detail, "next": nxt}
    f.update(extra)
    findings.append(f)

def short(s, n=110):
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"

# --- ZERO-YIELD-RUN ------------------------------------------------------------
if totals["dispatched"] > 0 and totals["integrated"] == 0:
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
for repo in sorted(cls):
    c = cls[repo]
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
        add("SKIPPED-WITH-ACTIONABLE", repo,
            "ends the run in RELAY_STATUS '%s' (%s) but still classifies %s with %s"
            % (row["section"], reason, c["verdict"], item_txt),
            "bash relay/scripts/classify-repo.sh --repo %s --path %s" % (repo, path),
            verdict=c["verdict"], count=items, ids=c["ids"])

ORDER = ["ZERO-YIELD-RUN", "STARVED", "DISPATCHED-BUT-NO-OUTCOME",
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
        "reclassified": len(cls) if mode == "live" else 0,
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
    if mode == "recorded":
        print("NOTE: --fast — verdicts are the run's own RECORDED ones, blind to state "
              "that changed since; re-run without --fast for the authoritative answer.")
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
