#!/usr/bin/env bash
# death-record.sh — durable, mechanically-distinguishable DEATH-CAUSE record for relay children.
#
# WHY THIS EXISTS (id:4f9b / id:93cc cluster, ROADMAP.md)
#   A pool child died `Prompt is too long` on 2026-08-01. The dispatch-time gate
#   (prompt-size-gate.mjs) CORRECTLY did not fire — its estimate landed near 77k against a
#   100k cap — and the child then created its worktree, produced 566 committed lines, and
#   died mid-work. The death was IN-SESSION CONTEXT GROWTH, not prompt assembly. id:4f9b
#   closes the dispatch-time half; the run-time half is uncovered. Without a death-cause
#   record the two halves are INDISTINGUISHABLE in the ledger, so the wrong remedy
#   (`roadmap-archive.sh`, which prompt-size-gate.mjs:72 prescribes for the dispatch-time
#   case) keeps getting recommended for a run-time death that archiving cannot touch.
#
#   Corroborating measurement (id:10dc, 2026-08-21, seven real transcripts): delegated
#   agents die at a ~175k effective ceiling; ~58.6k is spent before the first tool call;
#   growth is monotonic accumulation and the agent's own output often exceeds everything it
#   read. "Died at dispatch" and "died from accumulation" are genuinely different failures
#   needing different remedies, so the ledger must name which one happened.
#
# WHAT IT DOES
#   Derives a death record for every relay work unit from state that ALREADY EXISTS — it
#   invents no new instrumentation and asks no child to report anything:
#     * ~/.config/relay/relay-events.jsonl   the dispatch/integrate/handback event stream
#     * relay.toml (via lib-own-repos.sh)    the canonical repo->path map (NEVER a ~/src glob)
#     * the child's worktree + branches      the SALVAGE signal (below)
#
#   The discriminator is structural, not prose: `pushEvent('dispatch', …)` is emitted at
#   relay-loop.js:3802, AFTER the prompt-size gate (:3756), the stranded-branch guard (:3774)
#   and provisionWorktree (:3789). So a terminal handback with NO preceding `dispatch` event
#   for the same (runId, repo, mode) means NOTHING WAS DISPATCHED — no worktree, no work
#   lost. A terminal handback WITH one means a child ran and then died. That single fact
#   separates the safe case from the costly one without parsing a single sentence.
#
# CAUSE CLASSES (the `cause` field)
#   dispatch-refused  The gate fired (or a sibling pre-dispatch guard did). Nothing was
#                     dispatched, no worktree was created, no work was lost. `cause_detail`
#                     names WHICH guard: prompt-size-gate / stranded-branch / provision-failed
#                     / isolation-gate / dirty-main-checkout / redispatch-suppressed / ...
#                     REMEDY CLASS: shrink the dispatched payload (archive, split the item).
#   runtime-death     A child was dispatched, did work, and died mid-session with NO report
#                     (relay-loop.js:3024's null-report terminal failure). This is the costly
#                     case: work may sit uncommitted in its worktree. REMEDY CLASS:
#                     in-session context growth — archiving the ledger does NOT address it.
#   child-handback    A child was dispatched, ran to completion, and returned
#                     contract_met=false (relay-loop.js:3077/3394). Not a death; recorded so
#                     the classes are exhaustive and a handback is never miscounted as one.
#   cause-unknown     RECORDED AS UNKNOWN ON PURPOSE — never papered over (id:f5d9(b)).
#                     Two sub-cases:
#                       no-merged-line     `integrate.sh produced no merged= line`. That one
#                                        signature is emitted for a classifier block, a
#                                        dispatch failure AND a mute integrator alike; today
#                                        it cannot distinguish them, so this tool refuses to
#                                        guess and says so.
#                       no-terminal-event  A `dispatch` with neither integrate nor handback
#                                        anywhere in the log — the pool itself died or was
#                                        killed mid-unit.
#   (A `dispatch` followed by `integrate` is a HEALTHY unit and produces NO record at all.)
#
# THE SALVAGE SIGNAL (`salvage`)
#   Three agents died on 2026-08-20 holding 130-200k tokens of finished-but-uncommitted work
#   each, recovered only because a human went looking in their worktrees. A death record that
#   notes "this dead child's worktree holds uncommitted work / unmerged commits" is the
#   difference between recoverable and lost. Computed purely from git, for every record whose
#   cause is runtime-death or cause-unknown (--salvage-all probes every record):
#     worktrees[]  $RELAY_WORKTREE_BASE/<repo>/<runId>-*   (relay-loop.js:2537's layout),
#                  `git status --porcelain` line count -> dirty_files
#     branches[]   refs/heads/relay/<runId>-* AND refs/heads/relay/orphan/<runId>-*
#                  (relay-loop.js:2538 + the id:4df8 orphan park), `rev-list --count
#                  <trunk>..<branch>` -> unmerged_commits
#     recoverable  true iff any dirty_files>0 or any unmerged_commits>0
#   FAIL-OPEN: any git/filesystem error leaves `probed:false` + an `error` note, and
#   `recoverable` stays null. A probe that could not run NEVER reports `recoverable:false` —
#   an unknown is not a clean.
#
# STORE
#   Append-only JSONL at $RELAY_DEATH_RECORD_PATH (default $FABLES_CONFIG/relay-deaths.jsonl),
#   written ONLY through `relay-state-write.sh event-append` (the flock'd append primitive,
#   id:03a5) — never a bare `>>`. Records are keyed `<runId>|<repo>|<mode>|<seq>` and `record`
#   is IDEMPOTENT: a key already present in the store is never appended twice, so the same
#   run may be re-scanned any number of times. JSON is built by python3 (json.dumps), never
#   string concatenation — handback reasons carry quotes, newlines and apostrophes.
#
# Usage:
#   death-record.sh scan   [RUN_ID|latest|--all] [--repo <n>] [--no-salvage] [--salvage-all] [--json]
#   death-record.sh record [RUN_ID|latest|--all] [--repo <n>] [--no-salvage] [--salvage-all] [--dry-run]
#   death-record.sh list   [--run <id>] [--repo <n>] [--cause <c>]
#   death-record.sh --help
#     scan    derive records and PRINT them (text report, or --json for one JSON per line).
#             Read-only: never touches the store.
#     record  derive records and APPEND the new ones to the store (idempotent). Prints the
#             count appended. --dry-run prints what WOULD be appended and writes nothing.
#     list    print stored records (JSONL), optionally filtered.
#     RUN_ID  the run to examine; omit or `latest` for the newest runId in the event log;
#             `--all` for every run in the log.
#
# Env overrides (hermetic tests; same spellings the siblings already use):
#   RELAY_EVENTS_PATH        default ~/.config/relay/relay-events.jsonl
#   RELAY_TOML               default ~/.config/relay/relay.toml
#   SRC_DIR                  default ~/src
#   FABLES_CONFIG            default ~/.config/relay
#   RELAY_DEATH_RECORD_PATH  default $FABLES_CONFIG/relay-deaths.jsonl
#   RELAY_WORKTREE_BASE      default ~/.cache/relay/worktrees
#   RELAY_STATE_WRITE        override the relay-state-write.sh path (stub it in tests)
#   DEATH_RECORD_LOG         default ~/.claude/logs/death-record.log
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
FABLES_CONFIG="${FABLES_CONFIG:-$HOME/.config/relay}"
RELAY_EVENTS_PATH="${RELAY_EVENTS_PATH:-$HOME/.config/relay/relay-events.jsonl}"
RELAY_DEATH_RECORD_PATH="${RELAY_DEATH_RECORD_PATH:-$FABLES_CONFIG/relay-deaths.jsonl}"
RELAY_WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"
STATE_WRITE="${RELAY_STATE_WRITE:-$SCRIPT_DIR/relay-state-write.sh}"
LOG="${DEATH_RECORD_LOG:-$HOME/.claude/logs/death-record.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true   # best-effort: never fail on a log dir
log() { printf '%s death-record.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# own_repos() — THE canonical confirmed-own repo->path map from relay.toml (id:0fa0).
# Sourced, never re-implemented, and NEVER replaced by a ~/src/* glob (the use-existing-tools
# rule). Used only to resolve a repo NAME to the checkout the salvage probe inspects.
# shellcheck source=lib-own-repos.sh
source "$SCRIPT_DIR/lib-own-repos.sh"

usage() {
  # Compute the header range rather than hardcoding a line number (it drifts).
  # No pipe into an early-exiting consumer (banned): grep drains fully.
  local _gn _end
  _gn="$(grep -n '^set -euo pipefail' "$0" || true)"
  _end="${_gn%%:*}"
  [ -n "$_end" ] || _end=100
  sed -n "2,$((_end - 1))p" "$0"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  scan|record|list) ;;
  *) echo "death-record.sh: unknown subcommand '$cmd' (use scan|record|list)" >&2; exit 2 ;;
esac

run_sel="latest"
only_repo=""
only_cause=""
salvage_mode="default"   # default | none | all
as_json=0
dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)         run_sel="__all__"; shift ;;
    --run)         [[ $# -ge 2 && -n "${2:-}" ]] || { echo "death-record.sh: --run requires a run id" >&2; exit 2; }
                   run_sel="$2"; shift 2 ;;
    --repo)        [[ $# -ge 2 && -n "${2:-}" ]] || { echo "death-record.sh: --repo requires a repo name" >&2; exit 2; }
                   only_repo="$2"; shift 2 ;;
    --cause)       [[ $# -ge 2 && -n "${2:-}" ]] || { echo "death-record.sh: --cause requires a cause class" >&2; exit 2; }
                   only_cause="$2"; shift 2 ;;
    --no-salvage)  salvage_mode="none"; shift ;;
    --salvage-all) salvage_mode="all"; shift ;;
    --json)        as_json=1; shift ;;
    --dry-run)     dry_run=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --*)           echo "death-record.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)             run_sel="$1"; shift ;;
  esac
done

# ---- list: read the store back, no derivation -----------------------------------
if [[ "$cmd" == list ]]; then
  [[ -f "$RELAY_DEATH_RECORD_PATH" ]] || exit 0
  STORE="$RELAY_DEATH_RECORD_PATH" F_RUN="$run_sel" F_REPO="$only_repo" F_CAUSE="$only_cause" python3 - <<'PYEOF'
import json, os
store = os.environ["STORE"]
f_run, f_repo, f_cause = os.environ["F_RUN"], os.environ["F_REPO"], os.environ["F_CAUSE"]
if f_run in ("latest", "__all__"):
    f_run = ""
with open(store, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if f_run and rec.get("runId") != f_run:
            continue
        if f_repo and rec.get("repo") != f_repo:
            continue
        if f_cause and rec.get("cause") != f_cause:
            continue
        print(json.dumps(rec, ensure_ascii=False))
PYEOF
  exit 0
fi

[[ -f "$RELAY_EVENTS_PATH" ]] || {
  echo "death-record.sh: event log not found: $RELAY_EVENTS_PATH" >&2
  exit 1
}

# Repo -> path map for the salvage probe. own_repos() may legitimately return NOTHING (no
# registry yet); it returns NONZERO only on a relay.toml that EXISTS but fails to parse, and
# that status must be checked EXPLICITLY (id:0fa0 finding (a): a process-substitution loop
# discards it silently). A parse failure is NOT fatal here — the pairing pass is unaffected —
# but the salvage probe then has no checkout paths, and that degradation is REPORTED in the
# record's `salvage.error`, never rendered as a clean.
repo_map_file="$(mktemp)"
existing_keys_file="$(mktemp)"
records_file="$(mktemp)"
new_file="$(mktemp)"
trap 'rm -f -- "$repo_map_file" "$existing_keys_file" "$records_file" "$new_file"' EXIT

repo_map_ok=1
if ! own_repos >"$repo_map_file" 2>/dev/null; then
  repo_map_ok=0
  : >"$repo_map_file"
  log "own_repos() failed to parse $RELAY_TOML — salvage branch probe degraded to worktree-only"
fi

if [[ "$cmd" == record && -f "$RELAY_DEATH_RECORD_PATH" ]]; then
  STORE="$RELAY_DEATH_RECORD_PATH" python3 - >"$existing_keys_file" <<'PYEOF'
import json, os
with open(os.environ["STORE"], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            print(json.loads(line).get("key", ""))
        except Exception:
            pass
PYEOF
fi

EVENTS="$RELAY_EVENTS_PATH" RUN_SEL="$run_sel" ONLY_REPO="$only_repo" \
SALVAGE_MODE="$salvage_mode" WT_BASE="$RELAY_WORKTREE_BASE" \
REPO_MAP="$repo_map_file" REPO_MAP_OK="$repo_map_ok" EXISTING_KEYS="$existing_keys_file" \
python3 - >"$records_file" <<'PYEOF'
import glob, json, os, subprocess, sys

events_path = os.environ["EVENTS"]
run_sel     = os.environ["RUN_SEL"]
only_repo   = os.environ["ONLY_REPO"]
salvage     = os.environ["SALVAGE_MODE"]
wt_base     = os.environ["WT_BASE"]
repo_map_ok = os.environ["REPO_MAP_OK"] == "1"

repo_path = {}
with open(os.environ["REPO_MAP"], encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if "\t" in line:
            name, path = line.split("\t", 1)
            repo_path[name] = path

existing = set()
with open(os.environ["EXISTING_KEYS"], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line:
            existing.add(line)

# ---- signatures. Substring matches on the EXACT strings relay-loop.js emits. --------------
# The cause CLASS never depends on these for the dispatch/run-time split — that is decided
# STRUCTURALLY by the presence of a `dispatch` event. Signatures only refine `cause_detail`
# and separate the two dispatched-then-terminal sub-cases.
RUNTIME_DEATH_SIG = "child agent failed/skipped (API error or terminal failure)"
NO_MERGED_SIG     = "produced no merged= line"
REFUSAL_DETAILS = [
    ("prompt-size gate",                  "prompt-size-gate"),
    ("stranded branch",                   "stranded-branch"),
    ("provisionWorktree failed",          "provision-failed"),
    ("isolation gate failed",             "isolation-gate"),
    ("main checkout dirty",               "dirty-main-checkout"),
    ("Dirty main working tree",           "dirty-main-checkout"),
    ("suppressed re-dispatch",            "redispatch-suppressed"),
    ("stale worktree",                    "stale-worktree"),
    ("no-work handback suppression",      "no-work-suppression"),
    ("durable handback follow-up FAILED", "handback-followup-failed"),
]

def refusal_detail(reason):
    for sig, name in REFUSAL_DETAILS:
        if sig in reason:
            return name
    return "other"

# ---- pass 1: read events -----------------------------------------------------------------
events = []
malformed = 0
with open(events_path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            malformed += 1
            continue
        if isinstance(obj, dict):
            events.append(obj)

run_ids = []
for e in events:
    r = e.get("runId")
    if r and r not in run_ids:
        run_ids.append(r)

if run_sel == "__all__":
    wanted = set(run_ids)
elif run_sel in ("latest", ""):
    wanted = {run_ids[-1]} if run_ids else set()
else:
    wanted = {run_sel}

# ---- pass 2: pair dispatch -> terminal, per (runId, repo, mode) ---------------------------
# Queue semantics: each `dispatch` enqueues; the next `integrate`/`handback` for the same key
# dequeues it. A terminal with an EMPTY queue was never dispatched — that IS the
# dispatch-refusal discriminator (relay-loop.js emits the dispatch event at :3802, after every
# pre-dispatch guard). Leftover entries at EOF are units whose run ended with no terminal event.
pending = {}
seq_of  = {}
units   = []

def next_seq(k):
    seq_of[k] = seq_of.get(k, 0) + 1
    return seq_of[k]

for e in events:
    kind = e.get("kind")
    if kind not in ("dispatch", "integrate", "handback"):
        continue
    run  = e.get("runId") or ""
    repo = e.get("repo") or ""
    mode = e.get("mode") or ""
    if run not in wanted:
        continue
    if only_repo and repo != only_repo:
        continue
    k = (run, repo, mode)
    if kind == "dispatch":
        pending.setdefault(k, []).append(e)
    else:
        q = pending.get(k, [])
        d = q.pop(0) if q else None
        units.append((run, repo, mode, next_seq(k), d, e))

for k, q in pending.items():
    for d in q:
        units.append((k[0], k[1], k[2], next_seq(k), d, None))

# ---- pass 3: classify --------------------------------------------------------------------
def classify(dispatched, terminal):
    if terminal is None:
        return ("cause-unknown", "no-terminal-event",
                "a dispatch with NO integrate and NO handback anywhere in the log — the pool "
                "died or was killed mid-unit; the child's fate is not recorded")
    if terminal.get("kind") == "integrate":
        return (None, None, None)          # healthy: NO death record, by design
    reason = str(terminal.get("reason") or "")
    if not dispatched:
        return ("dispatch-refused", refusal_detail(reason),
                "a pre-dispatch guard fired: no child was spawned, no worktree was created, "
                "no work was lost")
    if RUNTIME_DEATH_SIG in reason:
        return ("runtime-death", "null-report-terminal-failure",
                "the child was dispatched and did work, then died mid-session with no report "
                "(in-session context growth / API terminal failure) — archiving a ledger does "
                "NOT address this; check the salvage signal before re-dispatching")
    if NO_MERGED_SIG in reason:
        return ("cause-unknown", "no-merged-line",
                "integrate.sh emitted no parseable merged= line. That ONE signature covers a "
                "classifier block, a dispatch failure and a mute integrator alike (id:f5d9(b)); "
                "they are not distinguishable today, so this is recorded as UNKNOWN rather "
                "than guessed")
    return ("child-handback", "contract-not-met",
            "the child ran to completion and handed back (contract_met=false) — not a death")

# ---- pass 4: salvage probe ---------------------------------------------------------------
def git(args, cwd):
    return subprocess.run(["git", "-C", cwd] + args,
                          capture_output=True, text=True, timeout=30)

def trunk_ref(path):
    r = git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], path)
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    for cand in ("main", "master"):
        if git(["rev-parse", "--verify", "--quiet", cand], path).returncode == 0:
            return cand
    return ""

def probe_salvage(run, repo):
    out = {"probed": False, "worktrees": [], "branches": [], "recoverable": None, "error": ""}
    errors = []
    probed_any = False

    wt_dir = os.path.join(wt_base, repo)
    try:
        for wt in sorted(glob.glob(os.path.join(wt_dir, run + "-*"))):
            if not os.path.isdir(wt):
                continue
            probed_any = True
            r = git(["status", "--porcelain"], wt)
            if r.returncode != 0:
                errors.append("status failed in %s: %s" % (wt, r.stderr.strip()[:120]))
                continue
            lines = [l for l in r.stdout.splitlines() if l.strip()]
            out["worktrees"].append({"path": wt, "dirty_files": len(lines)})
    except Exception as exc:                       # fail-open, never crash the scan
        errors.append("worktree probe: %s" % exc)

    path = repo_path.get(repo, "")
    if path and os.path.isdir(path):
        try:
            r = git(["for-each-ref", "--format=%(refname:short)",
                     "refs/heads/relay/" + run + "-*",
                     "refs/heads/relay/orphan/" + run + "-*"], path)
            if r.returncode != 0:
                errors.append("for-each-ref failed: %s" % r.stderr.strip()[:120])
            else:
                probed_any = True
                trunk = trunk_ref(path)
                for br in [b.strip() for b in r.stdout.splitlines() if b.strip()]:
                    n = None
                    if trunk:
                        c = git(["rev-list", "--count", trunk + ".." + br], path)
                        if c.returncode == 0 and c.stdout.strip().isdigit():
                            n = int(c.stdout.strip())
                    if n is None:
                        errors.append("could not count unmerged commits on " + br)
                    out["branches"].append({"ref": br, "unmerged_commits": n})
        except Exception as exc:
            errors.append("branch probe: %s" % exc)
    elif not repo_map_ok:
        errors.append("relay.toml unparseable — no checkout path for %s" % repo)
    else:
        errors.append("no checkout path for %s in the relay.toml own set" % repo)

    out["probed"] = probed_any
    out["error"] = "; ".join(errors)
    if probed_any and not errors:
        dirty = any(w["dirty_files"] > 0 for w in out["worktrees"])
        ahead = any((b["unmerged_commits"] or 0) > 0 for b in out["branches"])
        out["recoverable"] = bool(dirty or ahead)
    else:
        # A probe that could not fully run reports UNKNOWN (null), never a clean false.
        out["recoverable"] = None
    return out

# ---- emit --------------------------------------------------------------------------------
units.sort(key=lambda u: ((u[5] or u[4] or {}).get("ts", ""), u[1], u[2], u[3]))
for run, repo, mode, seq, disp, term in units:
    dispatched = disp is not None
    cause, detail, meaning = classify(dispatched, term)
    if cause is None:
        continue                                   # healthy unit -> no record, by design
    key = "%s|%s|%s|%d" % (run, repo, mode, seq)
    rec = {
        "kind": "death-record",
        "key": key,
        "runId": run,
        "repo": repo,
        "mode": mode,
        "seq": seq,
        "cause": cause,
        "cause_detail": detail,
        "cause_meaning": meaning,
        "dispatched": dispatched,
        "dispatch_ts": (disp or {}).get("ts", ""),
        "terminal_ts": (term or {}).get("ts", ""),
        "terminal_kind": (term or {}).get("kind", ""),
        "item": (disp or {}).get("item", "") or "",
        "tier": (disp or {}).get("tier", "") or "",
        "reason_head": " ".join(str((term or {}).get("reason", "")).split())[:400],
    }
    want_salvage = (salvage == "all"
                    or (salvage == "default" and cause in ("runtime-death", "cause-unknown")))
    if want_salvage:
        rec["salvage"] = probe_salvage(run, repo)
    else:
        rec["salvage"] = {
            "probed": False, "worktrees": [], "branches": [], "recoverable": None,
            "error": ("not probed (--no-salvage)" if salvage == "none"
                      else "not probed (cause class loses no work)"),
        }
    rec["new"] = key not in existing
    print(json.dumps(rec, ensure_ascii=False))

if malformed:
    sys.stderr.write("death-record.sh: %d malformed event line(s) skipped\n" % malformed)
PYEOF

# ---- output / store ------------------------------------------------------------------------
if [[ "$cmd" == scan ]]; then
  if [[ "$as_json" == 1 ]]; then
    cat "$records_file"
  else
    RECS="$records_file" python3 - <<'PYEOF'
import json, os
counts, rows = {}, []
with open(os.environ["RECS"], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        counts[rec["cause"]] = counts.get(rec["cause"], 0) + 1
        rows.append(rec)
if not rows:
    print("death-record: no death records for the selected run(s) — "
          "every dispatched unit integrated cleanly.")
else:
    print("death-record: %d record(s)" % len(rows))
    for c in sorted(counts):
        print("  %-18s %d" % (c, counts[c]))
    print("")
    for rec in rows:
        sv = rec.get("salvage") or {}
        rc = sv.get("recoverable")
        mark = "SALVAGEABLE" if rc is True else ("clean" if rc is False else "salvage:unknown")
        print("- %s %s/%s [%s / %s] %s" % (
            rec["terminal_ts"] or rec["dispatch_ts"], rec["repo"], rec["mode"],
            rec["cause"], rec["cause_detail"], mark))
        for w in sv.get("worktrees", []):
            if w["dirty_files"]:
                print("    uncommitted: %d file(s) in %s" % (w["dirty_files"], w["path"]))
        for b in sv.get("branches", []):
            n = b.get("unmerged_commits")
            if n:
                print("    unmerged:    %s commit(s) on %s" % (n, b["ref"]))
        if sv.get("error"):
            print("    probe note:  %s" % sv["error"])
        if rec.get("reason_head"):
            print("    reason:      %s" % rec["reason_head"][:200])
PYEOF
  fi
  exit 0
fi

# record: append only the NEW records, through the flock'd primitive.
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)" RECS="$records_file" python3 - >"$new_file" <<'PYEOF'
import json, os
now = os.environ.get("NOW", "")
with open(os.environ["RECS"], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if not rec.pop("new", False):
            continue
        rec["recorded_at"] = now
        print(json.dumps(rec, ensure_ascii=False))
PYEOF

n="$(grep -c '' "$new_file" || true)"
[[ -n "$n" ]] || n=0
if [[ "$dry_run" == 1 ]]; then
  cat "$new_file"
  echo "death-record: would append $n new record(s) to $RELAY_DEATH_RECORD_PATH (dry run)" >&2
  exit 0
fi
if [[ "$n" -eq 0 ]]; then
  echo "death-record: 0 new record(s); $RELAY_DEATH_RECORD_PATH unchanged"
  exit 0
fi
"$STATE_WRITE" event-append "$RELAY_DEATH_RECORD_PATH" <"$new_file"
log "record run=$run_sel appended=$n store=$RELAY_DEATH_RECORD_PATH"
echo "death-record: appended $n new record(s) to $RELAY_DEATH_RECORD_PATH"
