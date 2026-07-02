#!/usr/bin/env bash
# relay-gap-sample.sh — between-runs churn EVIDENCE LOGGER for relay discovery.
#
# WHY (pre-meeting brief 2026-07-02, discovery→OS-layer question): the only live
# justification for moving discovery onto a systemd timer / inotify layer is
# between-runs LATENCY — work accruing while no pool runs, sitting until the next
# manual /relay launch. That latency has NEVER been measured (relay-events.jsonl
# logs dispatched verdicts only). Per observe-before-preventing, this logger runs
# FIRST and any timer/inotify *dispatch* build is gated on what it shows.
#
# WHAT it does per tick (report-only, ZERO LLM, side-effect-free on every repo):
#   1. Enumerate relay.toml `classification = "own"` repos (honoring `# path:`,
#      skipping `paused`) — same parse as gather-human-backlog.sh/relay-reconcile.sh.
#   2. discover-sig.sh over all of them (one call, JSON in/out).
#   3. For repos whose sig CHANGED since the last tick (or fail-open empty sig):
#      classify-repo.sh --repo --path (the PURE island: gather → unpromoted-scan →
#      classify-verdict; never reconcile-repo.sh, never a write) → verdict.
#   4. Append one JSONL line per changed repo + one per-tick summary line, stamped
#      with whether a pool run was ALIVE at sample time (heartbeat.sh live-runs).
#
# The analysis this feeds: correlate {ts, repo, verdict-became-actionable,
# pool_live=false} events against the next run-start (relay-events.jsonl /
# heartbeats) → distribution of "actionable work sat idle for H hours". That
# number is the meeting's decision input for options B/C/D/E in the brief.
#
# NOT a scheduler, NOT a queue, NOT a dispatcher: it never launches anything,
# never writes a repo, never touches relay.toml. Overlap with a live pool is
# benign (classify island is side-effect-free; sig reads are cheap git reads).
#
# Output lines (~/.config/relay/relay-gap-samples.jsonl):
#   {"ts":"…","kind":"change","repo":"x","verdict":"execute","prev_verdict":"idle",
#    "reason":"…","sig":"…","pool_live":true}
#   {"ts":"…","kind":"tick","checked":38,"changed":2,"classify_errors":0,"pool_live":true}
#   {"ts":"…","kind":"error","repo":"x","detail":"…"}          # loud, never swallowed
#
# Env overrides (hermetic tests):
#   RELAY_TOML         default ~/.config/relay/relay.toml
#   SRC_DIR            default ~/src
#   RELAY_GAP_SAMPLES  default ~/.config/relay/relay-gap-samples.jsonl
#   RELAY_GAP_STATE    default ~/.config/relay/relay-gap-state.json
#   RELAY_SCRIPTS      default <this repo>/relay/scripts
#   HEARTBEAT_BASE     forwarded to heartbeat.sh (default ~/.config/relay/heartbeats)
#
# Conventions: set -euo pipefail; short stdout; details → ~/.claude/logs/relay-gap-sample.log;
# flock'd JSONL append (fd 9); state rewrite is tmp+mv atomic.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELAY_SCRIPTS="${RELAY_SCRIPTS:-$REPO_ROOT/relay/scripts}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
SAMPLES="${RELAY_GAP_SAMPLES:-$HOME/.config/relay/relay-gap-samples.jsonl}"
STATE="${RELAY_GAP_STATE:-$HOME/.config/relay/relay-gap-state.json}"
LOG="${RELAY_GAP_LOG:-$HOME/.claude/logs/relay-gap-sample.log}"

mkdir -p "$(dirname "$SAMPLES")" "$(dirname "$STATE")" "$(dirname "$LOG")"

log() { printf '%s relay-gap-sample %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# --- own repos from relay.toml (same parse as relay-reconcile.sh / gather-human-backlog.sh)
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)
def expand(p):
    return os.path.expanduser(os.path.expandvars(p))
for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# flock'd append of one JSONL line (fd 9 pattern, see append.sh/diary-append.sh)
append_line() {
  local line="$1"
  (
    exec 9>>"$SAMPLES.lock"
    flock 9
    printf '%s\n' "$line" >>"$SAMPLES"
  )
}

# --- pool liveness at sample time (heartbeat.sh live-runs; loud on error) -----
pool_live="false"
if live_out="$("$RELAY_SCRIPTS/heartbeat.sh" live-runs 2>>"$LOG")"; then
  [[ -n "$live_out" ]] && pool_live="true"
else
  # heartbeat failure is evidence-quality-relevant → record loudly, keep sampling
  append_line "$(jq -cn --arg ts "$(now_iso)" '{ts:$ts,kind:"error",repo:"",detail:"heartbeat.sh live-runs failed (see log)"}')"
  pool_live="unknown"
fi

# --- enumerate + sign --------------------------------------------------------
repos_tsv="$(own_repos)"
if [[ -z "$repos_tsv" ]]; then
  log "no own repos found in $RELAY_TOML — nothing to sample"
  append_line "$(jq -cn --arg ts "$(now_iso)" --arg pl "$pool_live" '{ts:$ts,kind:"tick",checked:0,changed:0,classify_errors:0,pool_live:$pl}')"
  echo "gap-sample: 0 repos"
  exit 0
fi

sig_input="$(printf '%s\n' "$repos_tsv" | jq -Rcn '{repos:[inputs|select(length>0)|split("\t")|{repo:.[0],path:.[1]}],liveClaims:[]}')"
sig_lines="$(printf '%s' "$sig_input" | "$RELAY_SCRIPTS/discover-sig.sh")"

# --- previous state ----------------------------------------------------------
prev_state="{}"
[[ -f "$STATE" ]] && prev_state="$(cat "$STATE")"

# --- walk repos: classify the changed (or fail-open empty-sig) ones -----------
checked=0 changed=0 errors=0
new_state="{}"
while IFS=$'\t' read -r name path; do
  [[ -n "$name" ]] || continue
  checked=$((checked+1))
  sig="$(printf '%s\n' "$sig_lines" | jq -r --arg r "$name" 'select(.repo==$r).sig' | head -1)"
  prev_sig="$(printf '%s' "$prev_state" | jq -r --arg r "$name" '.[$r].sig // ""')"
  prev_verdict="$(printf '%s' "$prev_state" | jq -r --arg r "$name" '.[$r].verdict // ""')"

  if [[ -n "$sig" && "$sig" == "$prev_sig" ]]; then
    # unchanged → carry state forward, no classify (the sig-cache contract)
    new_state="$(printf '%s' "$new_state" | jq -c --arg r "$name" --arg s "$sig" --arg v "$prev_verdict" '.[$r]={sig:$s,verdict:$v}')"
    continue
  fi

  # changed or fail-open empty sig → classify (pure island; no reconcile)
  if cls="$("$RELAY_SCRIPTS/classify-repo.sh" --repo "$name" --path "$path" 2>>"$LOG")"; then
    verdict="$(printf '%s' "$cls" | jq -r '.verdict // "PARSE-ERROR"')"
    reason="$(printf '%s' "$cls" | jq -r '(.reason // "")[:160]')"
  else
    verdict="ERROR" reason="classify-repo.sh failed (see log)"
    errors=$((errors+1))
  fi
  changed=$((changed+1))
  append_line "$(jq -cn --arg ts "$(now_iso)" --arg r "$name" --arg v "$verdict" --arg pv "$prev_verdict" \
    --arg re "$reason" --arg s "$sig" --arg pl "$pool_live" \
    '{ts:$ts,kind:"change",repo:$r,verdict:$v,prev_verdict:$pv,reason:$re,sig:$s,pool_live:$pl}')"
  new_state="$(printf '%s' "$new_state" | jq -c --arg r "$name" --arg s "$sig" --arg v "$verdict" '.[$r]={sig:$s,verdict:$v}')"
done <<<"$repos_tsv"

# --- tick summary + atomic state write ----------------------------------------
append_line "$(jq -cn --arg ts "$(now_iso)" --argjson c "$checked" --argjson ch "$changed" \
  --argjson e "$errors" --arg pl "$pool_live" \
  '{ts:$ts,kind:"tick",checked:$c,changed:$ch,classify_errors:$e,pool_live:$pl}')"
tmp="$(mktemp "$(dirname "$STATE")/.gap-state.XXXXXX")"
printf '%s\n' "$new_state" >"$tmp"
mv "$tmp" "$STATE"

log "tick: checked=$checked changed=$changed errors=$errors pool_live=$pool_live"
echo "gap-sample: $checked repos, $changed changed, $errors errors, pool_live=$pool_live"
