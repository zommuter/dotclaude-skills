#!/usr/bin/env bash
# relay-status-publish.sh (id:0d31 — skeleton L1 thin-glue) — deterministic publisher for
# RELAY_STATUS.md + the append-only event log. It replaces a ~40-line haiku "glue" agent recipe
# (writeRelayStatus in relay-loop.js) that the Workflow engine could not run itself (it cannot
# exec shell — id:6e9d). The agent STAYS (engine constraint), but its prompt collapses to one
# piped invocation: short + precise → no target-drift (a weak model formatting claims-JSON into
# markdown and branching on "events or not" is exactly where drift happened).
#
# This script owns the deterministic work the agent used to do by hand:
#   • resolve the status path (refuse a non-absolute / unexpanded ~/$HOME target),
#   • peek live cross-session claims (claim.sh peek) and render the "## Claims (live)" section,
#   • render the "## Burnup this run" section from relay-burn.sh report,
#   • write the combined content ATOMICALLY via the flock'd single-writer (relay-state-write.sh
#     status-write — id:ebfb step 2),
#   • append any event lines to the JSONL via relay-state-write.sh event-append.
#
# I/O: the BASE status content (buildRelayStatus output) is read on stdin. If event lines are to
# be appended, they follow the content after ONE line equal to the sentinel below:
#     <status content>
#     ===RELAY-EVENTS===
#     <event json line 1>
#     <event json line 2>
# Everything before the sentinel is the content; everything after is the events block (may be
# empty / the sentinel absent → no events). The sentinel is intentionally unlikely in markdown.
#
# Usage: relay-status-publish.sh --path <status-path> --run <runId> --events-path <jsonl-path>
set -euo pipefail

SENTINEL='===RELAY-EVENTS==='
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITE="$HERE/relay-state-write.sh"
CLAIM="$HERE/claim.sh"
BURN="$HERE/relay-burn.sh"

path="" run="" events_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)        path="$2"; shift 2 ;;
    --run)         run="$2"; shift 2 ;;
    --events-path) events_path="$2"; shift 2 ;;
    *) echo "relay-status-publish: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$path" ]] || { echo "relay-status-publish: --path is required" >&2; exit 2; }

# Resolve ~ / $HOME in the target; refuse anything that did not expand to an absolute path
# (the same guard the agent applied + relay-state-write.sh re-checks — id:c34a).
resolve() { python3 -c 'import os,sys; print(os.path.expanduser(sys.argv[1]))' "$1"; }
target="$(resolve "$path")"
case "$target" in
  /*) : ;;
  *) echo "relay-status-publish: refusing non-absolute/unexpanded target: $target" >&2; exit 1 ;;
esac

# Split stdin into the content and the (optional) trailing events block at the sentinel line.
raw="$(cat)"
content="$raw"
events=""
if printf '%s\n' "$raw" | grep -qxF "$SENTINEL"; then
  content="$(printf '%s\n' "$raw" | sed "/^${SENTINEL}\$/,\$d")"
  events="$(printf '%s\n' "$raw" | sed "1,/^${SENTINEL}\$/d")"
fi

# ── ## Claims (live) — render live cross-session claims (id:ebfb). ──
claims_section="## Claims (live)"
claim_lines="$("$CLAIM" peek 2>/dev/null || true)"
if [[ -n "$claim_lines" ]]; then
  rendered="$(printf '%s\n' "$claim_lines" | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # {key,repo,runId,mode,item,...}; show repo, else item, else the raw claim KEY (id:8c85).
    # A KEYED claim (the meeting advisory `meeting:<repo>`, a resource claim, …) has BOTH repo
    # and item empty, and jq's `//` only falls through on null/false — never on "" — so the old
    # `.repo // .item` rendered `-   mode=… run=…` with no subject at all. `key` is always
    # populated, so it is the correct last resort: a live claim always names something.
    printf '%s' "$line" | jq -r '"- " + (if (.repo // "") != "" then .repo
        elif (.item // "") != "" then .item
        elif (.key // "") != "" then .key
        else "?" end)
      + "  mode=" + (.mode // "?") + "  run=" + (.runId // "?")' 2>/dev/null || true
  done)"
  claims_section+=$'\n'"${rendered:-_(none)_}"
else
  claims_section+=$'\n''_(none)_'
fi

# ── ## Burnup this run — from relay-burn.sh report (stdout empty when <2 samples). ──
burnup_section="## Burnup this run"
burn_out=""
[[ -n "$run" ]] && burn_out="$("$BURN" report --run "$run" 2>/dev/null || true)"
if [[ -n "$burn_out" ]]; then
  burnup_section+=$'\n''```'$'\n'"$burn_out"$'\n''```'
else
  burnup_section+=$'\n''_(insufficient samples yet)_'
fi

# ── ## Mechanical orphans / drafts (id:8a6b) — LOUD-surface every open [MECHANICAL] item with
# no recipe, and every un-promoted auto-drafted skeleton, so they never rot silently. Read-only
# cross-repo scan; fail-open (empty section if the scanner is absent/errors). ──
mech_section="## Mechanical orphans / drafts (id:8a6b)"
mech_scan="$HERE/mechanical-orphan-scan.sh"
mech_rendered=""
if [[ -x "$mech_scan" ]]; then
  mech_rendered="$("$mech_scan" 2>/dev/null | while IFS=$'\t' read -r mkind mid mrepo mhost mres mdetail; do
    [[ -n "$mkind" ]] || continue
    [[ "$mhost" == "-" ]] && mhost="?"; [[ "$mres" == "-" ]] && mres="?"
    case "$mkind" in
      orphan) printf -- '- ⚠️ ORPHAN  id:%s  repo=%s  host=%s  resource=%s  — no recipe anywhere; author one + promote drafts/ -> pending/ (it will never run)\n' "$mid" "$mrepo" "$mhost" "$mres" ;;
      draft)  printf -- '- 📝 DRAFT   id:%s  repo=%s  host=%s  resource=%s  — un-promoted skeleton; fill TODOs + move drafts/ -> pending/ to launch\n' "$mid" "$mrepo" "$mhost" "$mres" ;;
    esac
  done || true)"
fi
mech_section+=$'\n'"${mech_rendered:-_(none)_}"

# ── id:0f9e — MERGE-ON-WRITE, not whole-file replace. ───────────────────────────────────────
# RELAY_STATUS.md is ONE global path with no runId in it (relay-loop.js: RELAY_STATUS_PATH), and
# id:11c6's singleton guard EXEMPTS --afk and every directed/scoped mode, so parallel pools are
# the DESIGNED normal case. The write was atomic but last-writer-wins whole-file replacement, so
# at any instant the file showed exactly one run and every other live run's status was simply
# gone — and because the id:8c85 accounting universe is the SCOPED ownRepos, a `--only` run's
# "complete accounting" and a fleet run's were indistinguishable at the same filename. Observed
# live 2026-08-18: loderite relay-20260818-154017-12780 overlapping cartulary
# relay-20260818-152657-28729, and again csgebra relay-20260818-205434-31345 alongside the
# discovery producer.
#
# Each run now owns a DELIMITED section keyed by its runId; a publish replaces only its OWN
# section and preserves every other LIVE run's. Sections whose run is no longer live are garbage
# collected, EXCEPT when liveness cannot be determined — an unreadable/empty `heartbeat.sh
# live-runs` keeps everything (FAIL-OPEN: never delete another run's status on uncertainty).
#
# Concurrency: read→compose→write is serialized on a DEDICATED lock so two publishers cannot
# lose each other's section (the atomic single-writer alone does not prevent a lost update — it
# prevents a torn one). The final byte-write still goes through relay-state-write.sh status-write
# so there remains exactly ONE writer; that helper takes a DIFFERENT lock file, so nesting the
# two cannot deadlock.
RUN_KEY="${run:-no-run}"
BASE_DIR="${FABLES_CONFIG:-$HOME/.config/relay}"
MERGE_LOCK="$BASE_DIR/.status-merge.lock"
mkdir -p "$BASE_DIR"
: >>"$MERGE_LOCK"

# This run's section: the rendered body (its own H1 demoted to a run heading so the merged file
# keeps exactly one H1) followed by the PER-RUN burnup. Claims + mechanical orphans are
# cross-run scans, so they stay at file level, rendered once.
# The payload's H1 becomes the run's section heading (one H1 per file), and its `## Run progress`
# is DEMOTED to `### Run progress (this run)`. The demotion is not cosmetic: that heading used to
# be unique per file, and after the merge it appears once PER RUN — so a fleet reader doing
# `grep -A6 '## Run progress'` silently lands in whichever run sorted first and reads ONE run's
# counters believing they are totals (reported by the csgebra session 2026-08-18, who hit exactly
# that). Demoting removes the `^## ` collision while leaving `## In-flight` / `## Completed this
# run` intact, which the id:15bd statusline's awk fallbacks anchor on. Fleet numbers live in
# `## Aggregate` above; per-run numbers live inside that run's `relay-run:` block.
run_body="$(printf '%s\n' "$content" \
  | sed "1s|^# RELAY_STATUS — |## Run ${RUN_KEY} — |" \
  | sed "s|^## Run progress\$|### Run progress (this run)|")"
run_block="$(printf '<!-- relay-run:%s -->\n%s\n\n%s\n<!-- /relay-run:%s -->' \
  "$RUN_KEY" "$run_body" "$burnup_section" "$RUN_KEY")"

# Live run universe (fail-open: empty ⇒ keep every existing section).
HEARTBEAT="$HERE/heartbeat.sh"
live_runs=""
if [[ -x "$HEARTBEAT" ]]; then
  live_runs="$("$HEARTBEAT" live-runs 2>/dev/null | jq -r 'select(.state=="alive") | .runId' 2>/dev/null || true)"
fi

exec 8>"$MERGE_LOCK"
flock -w 30 8 || { echo "relay-status-publish: merge lock timeout" >&2; exit 1; }

prev=""
[[ -f "$target" ]] && prev="$(cat "$target")"

# Carry forward every OTHER run's section, in the order it already had.
carried="$(RUN_KEY="$RUN_KEY" LIVE="$live_runs" python3 - "$target" <<'PYEOF'
import os, re, sys
path = sys.argv[1]
try:
    prev = open(path, encoding='utf-8').read()
except OSError:
    prev = ''
mine = os.environ['RUN_KEY']
live = [r for r in os.environ.get('LIVE', '').split('\n') if r.strip()]
blocks = re.findall(r'<!-- relay-run:(\S+) -->\n(.*?)\n<!-- /relay-run:\1 -->', prev, re.DOTALL)
out = []
for rid, body in blocks:
    if rid == mine:
        continue                      # replaced by the freshly rendered section
    if live and rid not in live:
        continue                      # run is over — garbage collect its section
    out.append(f'<!-- relay-run:{rid} -->\n{body}\n<!-- /relay-run:{rid} -->')
print('\n\n'.join(out), end='')
PYEOF
)"

all_blocks="$run_block"
[[ -n "$carried" ]] && all_blocks="$run_block"$'\n\n'"$carried"

# Aggregate — DERIVED by summing the per-run "## Run progress" counters actually present in the
# merged sections, so it can never claim a scope it did not read. A run whose block omits a
# counter contributes 0 to it.
agg_runs="$(printf '%s\n' "$all_blocks" | grep -c '^<!-- relay-run:' || true)"
agg_inflight="$(printf '%s\n' "$all_blocks" | awk -F= '/^- in-flight=/{s+=$2} END{print s+0}')"
agg_blocked="$(printf '%s\n' "$all_blocks" | awk -F= '/^- blocked=/{s+=$2} END{print s+0}')"
agg_completed="$(printf '%s\n' "$all_blocks" | awk -F= '/^- completed=/{s+=$2} END{print s+0}')"
agg_round="$(printf '%s\n' "$all_blocks" | awk -F= '/^- round=/{if($2+0>m) m=$2+0} END{print m+0}')"
header="# RELAY_STATUS — last updated $(date '+%Y-%m-%dT%H:%M:%S%:z')"
# The counters are emitted ONE PER LINE, aggregate FIRST, deliberately: the id:15bd statusline
# reads `^- round=` / `^- completed=` / `^- in-flight=` with `head -1`, so placing the summed
# values above the run sections makes it report FLEET totals with ZERO reader changes. Left as a
# single multi-key line, `head -1` would instead have picked whichever run section happened to
# sit first — the same nondeterminism id:0f9e exists to remove. `round` is the MAX across runs
# (rounds are per-run, so a sum would be meaningless), the rest are sums.
aggregate="## Aggregate (id:0f9e — summed over the run sections below)"
aggregate+=$'\n'"- run sections=${agg_runs}"
aggregate+=$'\n'"- round=${agg_round}"
aggregate+=$'\n'"- in-flight=${agg_inflight}"
aggregate+=$'\n'"- completed=${agg_completed}"
aggregate+=$'\n'"- blocked=${agg_blocked}"
if [[ -z "$live_runs" ]]; then
  aggregate+=$'\n'"- ⚠️ liveness UNKNOWN (heartbeat live-runs unreadable) — stale sections are KEPT, not garbage collected"
fi

combined="${header}"$'\n\n'"${aggregate}"$'\n\n'"${all_blocks}"$'\n\n'"${claims_section}"$'\n\n'"${mech_section}"$'\n'

# Atomic, flock'd single-writer (mkdir -p + temp + atomic mv + ~/$HOME refusal — id:ebfb step 2).
printf '%s' "$combined" | "$STATE_WRITE" status-write "$target"
flock -u 8 || true

# Append event lines off-critical-path (id:c8b6). Only when there is a non-empty events block.
if [[ -n "${events//[$'\n\t ']/}" && -n "$events_path" ]]; then
  evt="$(resolve "$events_path")"
  printf '%s\n' "$events" | "$STATE_WRITE" event-append "$evt"
fi

echo "relay-status-publish: wrote $target"
