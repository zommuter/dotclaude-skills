#!/usr/bin/env bash
# relay/scripts/discover-prelude.sh — deterministic, mechanical DISCOVER-PRELUDE (id:86a2).
#
# WHY: the discover-prelude in relay-loop.js (label 'discover-prelude') used to be a
# `model:'haiku'` agent() whose ONLY job was the once-only global work at the head of the
# discovery step — runId generation, the CONSUMING `inject.sh take`, `claim.sh peek`, the
# own-repo enumeration + non-own skipped rollup, `discover-sig.sh`, and the `stop-sentinel.sh`
# check. EVERY one of those steps is ALREADY a shell helper (or a pure relay.toml read); the
# prelude never CLASSIFIES a repo (that is the shard's job). So there is no LLM judgment here
# to preserve — the whole prelude is mechanizable into ONE deterministic script dispatched via
# a single `model:'bash'` (```relay-mech) fence, mirroring discover-repos-mechanical.sh
# (id:9d97) and the other id:6176 mechanical hops. This is the id:c14d "multi-step-Haiku → one
# fenced command" pattern (2026-07-23 --fabled amendment; un-gated by the id:a36e proxy fix).
#
# Emits the PRELUDE_SCHEMA object on stdout (the exact shape relay-loop.js consumed from the
# haiku prelude, so the merge downstream is byte-identical):
#   {
#     "runId":          "relay-YYYYMMDD-HHMMSS-<suffix>",   // unique per pool run (id:0902)
#     "ts":             "<ISO-8601 UTC>",
#     "repos":          [ {"repo","path"(abs),"income"(bool)}, ... ],  // confirmed own repos
#     "skippedConfig":  [ {"repo","reason"}, ... ],          // every NON-own (or paused) block
#     "liveClaimRepos": [ "<repo>", ... ],                   // distinct repos under a LIVE claim
#     "injectedUnits":  [ <unit>, ... ],                     // consumed user-injected units
#     "signatures":     [ {"repo","sig"}, ... ],             // discover-sig.sh SUPERSET sigs
#     "stopRequested":  <bool>                               // operator graceful-stop sentinel
#   }
#
# DETERMINISM: the relay.toml-DERIVED parts (repos, skippedConfig) are a pure function of
# relay.toml — byte-identical across invocations. runId/ts are intentionally per-invocation
# (a fresh unique run id + timestamp every round); the CONSUMING steps (inject.sh take,
# stop-sentinel countdown/consume) mutate on-disk state exactly ONCE per call, by design.
#
# CONSUMING (run EXACTLY ONCE): `inject.sh take` atomically emits AND consumes pending
# injections; `stop-sentinel.sh check` atomically checks/counts-down/consumes the STOP
# sentinel. This script is the ONE actor that runs each, once per round — never call it more
# than once per round (the prelude contract, unchanged from the prose step 6/8).
#
# NO LLM, NO agent(), NO `claude -p` anywhere. Pure composition of the already-shell helpers.
#
# Own-repo enumeration reuses the SHARED own_repos() parser (lib-own-repos.sh, id:0fa0 finding
# e) — honoring `classification = "own"`, the `# path:` comment override, the `paused` flag,
# and absolute-path expansion — so the path-resolution logic never drifts from
# discover-repos-mechanical.sh / relay-doctor.sh. The income flag + the non-own skippedConfig
# rollup (which lib-own-repos.sh does not carry) are layered on top from a second relay.toml
# read; a genuine relay.toml PARSE failure exits LOUDLY (id:0fa0 finding a) before any output.
#
# Env overrides (hermetic testing; mirror the sibling scripts' idiom):
#   RELAY_TOML   default ~/.config/relay/relay.toml
#   SRC_DIR      default ~/src   (fallback path for a repo with no explicit path override)
#   STOP_PATH    default ~/.config/relay/STOP  (the operator graceful-stop sentinel file)
#   INJECT_BASE / CLAIM env / RELAY_WORKTREE_BASE — threaded straight to the sub-scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_OWN_REPOS="$SCRIPT_DIR/lib-own-repos.sh"
INJECT_SH="$SCRIPT_DIR/inject.sh"
CLAIM_SH="$SCRIPT_DIR/claim.sh"
DISCOVER_SIG="$SCRIPT_DIR/discover-sig.sh"
STOP_SENTINEL="$SCRIPT_DIR/stop-sentinel.sh"

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
STOP_PATH="${STOP_PATH:-$HOME/.config/relay/STOP}"
export RELAY_TOML SRC_DIR
LOG="${RELAY_DISCOVER_PRELUDE_LOG:-$HOME/.claude/logs/discover-prelude.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s discover-prelude.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# shellcheck source=lib-own-repos.sh
source "$LIB_OWN_REPOS"

# --- step 1/2: runId (unique per pool run, id:0902) + ISO-8601 UTC timestamp -----------------
runId="relay-$(date +%Y%m%d-%H%M%S)-$RANDOM"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tmp_own="$(mktemp)"; tmp_claim="$(mktemp)"; tmp_inject="$(mktemp)"; tmp_sig="$(mktemp)"; tmp_stop="$(mktemp)"
trap 'rm -- "$tmp_own" "$tmp_claim" "$tmp_inject" "$tmp_sig" "$tmp_stop" 2>/dev/null || true' EXIT

# --- step 3: confirmed own repos (CANONICAL parser; check exit status EXPLICITLY, id:0fa0 a) -
# A bare `done < <(own_repos)` discards a subshell's exit status, so a relay.toml parse error
# (tomllib exception → nonzero) would silently read as "0 own repos". Capture + test $? and, on
# a genuine parse failure, exit LOUDLY before emitting any output.
own_rc=0
own_repos > "$tmp_own" 2>>"$LOG" || own_rc=$?
if [[ "$own_rc" -ne 0 ]]; then
  echo "discover-prelude.sh: FAILED to parse relay.toml ($RELAY_TOML), rc=$own_rc — own-repo enumeration aborted; NOTHING emitted. See $LOG." >&2
  log "own_repos() FAILED rc=$own_rc — relay.toml parse error, aborting before any output (id:0fa0 a)"
  exit 1
fi

# --- step 5: liveClaimRepos (claim.sh peek — NON-consuming) -----------------------------------
"$CLAIM_SH" peek > "$tmp_claim" 2>>"$LOG" || log "claim.sh peek returned nonzero (treated as no live claims)"

# --- step 6: injectedUnits (inject.sh take — CONSUMING, EXACTLY ONCE) --------------------------
"$INJECT_SH" take > "$tmp_inject" 2>>"$LOG" || log "inject.sh take returned nonzero (treated as no pending injections)"

# --- step 5-derived: distinct live-claim repos, as a CSV for discover-sig's liveClaims section -
live_csv="$(python3 -c '
import json, sys
seen = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    r = o.get("repo")
    if r and r not in seen:
        seen.append(r)
print(",".join(sorted(seen)))
' "$tmp_claim")"

# --- step 7: signatures (discover-sig.sh — SUPERSET per-repo sig; fail-open empty sentinel) ---
if [[ -x "$DISCOVER_SIG" ]]; then
  LIVE_CLAIMS="$live_csv" python3 -c '
import json, os, sys
claims = [c for c in os.environ.get("LIVE_CLAIMS", "").split(",") if c]
repos = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    name, path = line.split("\t", 1)
    repos.append({"repo": name, "path": path})
print(json.dumps({"repos": repos, "liveClaims": claims}))
' "$tmp_own" | "$DISCOVER_SIG" > "$tmp_sig" 2>>"$LOG" || log "discover-sig.sh returned nonzero (sigs treated as empty/fail-open)"
else
  log "discover-sig.sh not found/executable at $DISCOVER_SIG — signatures empty (fail-open, always re-classify)"
  : > "$tmp_sig"
fi

# --- step 8: stopRequested (stop-sentinel.sh check — CONSUMING check/countdown, EXACTLY ONCE) --
if [[ -x "$STOP_SENTINEL" ]]; then
  "$STOP_SENTINEL" check --path "$STOP_PATH" > "$tmp_stop" 2>>"$LOG" || { echo '{"stopRequested":false}' > "$tmp_stop"; log "stop-sentinel.sh check nonzero — defaulting stopRequested:false (fail-safe)"; }
else
  echo '{"stopRequested":false}' > "$tmp_stop"
  log "stop-sentinel.sh not found/executable at $STOP_SENTINEL — stopRequested:false (fail-safe)"
fi

# --- assemble the PRELUDE_SCHEMA object ------------------------------------------------------
# The own-repo path resolution (honoring `# path:` / paused / abs-expansion) is the CANONICAL
# lib-own-repos.sh output in $tmp_own; here we only LAYER ON the income flag (per own repo) and
# compute the skippedConfig rollup (every NON-own block, plus any paused own block — never
# silently dropped). A genuine relay.toml parse error already exited loudly above via own_repos.
RUN_ID="$runId" TS="$ts" python3 -c '
import json, os, re, sys, tomllib

run_id = os.environ["RUN_ID"]
ts     = os.environ["TS"]
own_file, claim_file, inject_file, sig_file, stop_file, toml_path, src_dir = sys.argv[1:8]

# CANONICAL own set (name -> abs path) from lib-own-repos.sh — order preserved.
own = []          # [(name, path)] in enumeration order
own_names = set()
for line in open(own_file, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    name, path = line.split("\t", 1)
    own.append((name, path))
    own_names.add(name)

# Second relay.toml read for income (own) + skippedConfig (non-own / paused). A missing
# relay.toml is a valid empty state (own would already be empty).
income_by = {}
skipped = []
if os.path.exists(toml_path):
    with open(toml_path, "rb") as fh:
        data = tomllib.load(fh)
    for name, entry in data.get("repos", {}).items():
        cls = entry.get("classification")
        if cls == "own":
            income_by[name] = bool(entry.get("income"))
            if name not in own_names:
                # own but dropped by lib-own-repos (paused) — surface, do not silently drop.
                skipped.append({"repo": name, "reason": "excluded-by-config (paused)"})
        else:
            skipped.append({"repo": name, "reason": "excluded-by-config (%s)" % (cls if cls else "no-classification")})

repos = [{"repo": n, "path": p, "income": income_by.get(n, False)} for (n, p) in own]

# liveClaimRepos — distinct .repo from claim.sh peek (sorted for determinism).
live = []
for line in open(claim_file, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    r = o.get("repo")
    if r and r not in live:
        live.append(r)
live.sort()

# injectedUnits — shape mirrors relay-loop.js parseInjectTake (id:6176). This script HAS fs
# access, so it resolves the injected repo path itself (own map, else $src_dir/<repo>).
own_path = {n: p for (n, p) in own}
injected = []
for line in open(inject_file, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    repo = o.get("repo")
    if not repo:
        continue
    path = own_path.get(repo) or os.path.join(src_dir, repo)
    injected.append({
        "injected": True,
        "inject_token": o.get("token"),
        "verdict": o.get("verdict") or "execute",
        "repo": repo,
        "path": path,
        "reason": "user-injected high-priority task",
        "inject_item": o.get("item") or "",
        "inject_prompt": o.get("prompt") or "",
        "income": False,
        "standin": False,
        "hasRoutine": False,
        "openHard": False,
        "strongRecheckPending": False,
        "lastCkpt": "",
        "intensive": "",
    })

# signatures — discover-sig.sh emits one {repo,sig} JSON line per repo; pass through verbatim.
signatures = []
for line in open(sig_file, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    if isinstance(o, dict) and "repo" in o:
        signatures.append({"repo": o["repo"], "sig": o.get("sig", "")})

# stopRequested — stop-sentinel.sh check emits {"stopRequested":<bool>}. FAIL-SAFE: only a
# literal true triggers a stop; any parse failure is a benign false.
stop_requested = False
try:
    with open(stop_file, encoding="utf-8") as fh:
        stop_requested = bool(json.load(fh).get("stopRequested") is True)
except Exception:
    stop_requested = False

out = {
    "runId": run_id,
    "ts": ts,
    "repos": repos,
    "skippedConfig": skipped,
    "liveClaimRepos": live,
    "injectedUnits": injected,
    "signatures": signatures,
    "stopRequested": stop_requested,
}
print(json.dumps(out))
' "$tmp_own" "$tmp_claim" "$tmp_inject" "$tmp_sig" "$tmp_stop" "$RELAY_TOML" "$SRC_DIR"

log "emitted prelude runId=$runId repos=$(wc -l < "$tmp_own" | tr -d ' ') live=[$live_csv]"
