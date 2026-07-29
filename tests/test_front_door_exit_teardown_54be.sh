#!/usr/bin/env bash
# roadmap:54be
# RED SPEC for id:54be — front-door EXIT-ONLY teardown trap + the mode-b `--afk` prose fix
# (meeting docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md, D1-A + D3-A
# rider 1).
#
# WHAT MUST EXIST. The front door installs an EXIT trap owning EXACTLY two teardown actions:
#   1. heartbeat.sh stop <RUN_ID>
#   2. claim.sh release --run <RUN_ID>     (the id:89d6 sweep)
# Both fail LOUDLY to stderr — never `|| true`, never `2>/dev/null` ([[no-swallow-stderr]]).
# EXIT-ONLY is the point: beatHeartbeat (relay-loop.js:1743/:2552) and per-unit releaseLease
# (:2415) STAY in-Workflow. Beat means "the loop made progress"; a shell-lifetime beater
# would beat through a WEDGED Workflow, blinding the id:98f0 watchdog (--fabled F4).
#
# WHY AN ANCHORED FENCE, NOT PROSE. `relay/SKILL.md` is prose, and a prose grep is exactly
# the vacuous-guard failure id:cdcf documents (a reworded sentence silently empties the
# scoped region and the check passes having checked nothing). So the contract is:
#
#   * `relay/SKILL.md` carries the teardown between the anchors
#         <!-- teardown-trap:start -->   …   <!-- teardown-trap:end -->
#     with exactly one ```bash fence between them.
#   * That fenced snippet is SELF-CONTAINED: sourced in a shell where $RUN_ID is set, it
#     installs an EXIT trap and nothing else. It refers to the scripts by their installed
#     path prefix `~/.claude/skills/relay/scripts` (this test rewrites that prefix to a
#     stub dir — that is the ONLY substitution it makes, so the documented snippet stays
#     the literal thing an operator would run).
#
# RED today: no such anchors exist, no teardown trap is documented at all, and SKILL.md
# step 0b still tells an unattended mode-b run to "proceed conservatively".
#
# Hermetic: CLAIM_BASE + stub script dir in mktemp -d; the real ~/.claude, ~/.config/relay
# and the network are never touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/relay/SKILL.md"
REAL_CLAIM="$ROOT/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]]      || fail "relay/SKILL.md not found at $SKILL"
[[ -x "$REAL_CLAIM" ]] || fail "claim.sh not found/executable at $REAL_CLAIM"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RUN_ID_T="relay-20260729-100152-27550"
OTHER_RUN="relay-20260729-999999-11111"

# ── §1 the anchored teardown block exists and holds exactly one bash fence ────────────────
start_n="$(grep -n -- '<!-- teardown-trap:start -->' "$SKILL" | head -1 | cut -d: -f1)"
end_n="$(grep -n -- '<!-- teardown-trap:end -->'   "$SKILL" | head -1 | cut -d: -f1)"
[[ -n "$start_n" && -n "$end_n" ]] \
  || fail "(1) relay/SKILL.md has no <!-- teardown-trap:start/end --> anchors — the teardown must live in an ANCHORED region, not prose (id:cdcf: a prose-scoped guard can silently check nothing)"
(( end_n > start_n )) || fail "(1) teardown-trap:end precedes teardown-trap:start"

region="$(sed -n "$((start_n + 1)),$((end_n - 1))p" "$SKILL")"
fences="$(printf '%s\n' "$region" | grep -c '^```' || true)"
[[ "$fences" -eq 2 ]] \
  || fail "(1) the teardown-trap region must contain exactly one fenced block (found $fences fence markers)"
snippet="$(printf '%s\n' "$region" | sed -n '/^```/,/^```/p' | sed '1d;$d')"
[[ -n "$snippet" ]] || fail "(1) the teardown-trap fence is empty"
pass "(1) relay/SKILL.md carries an anchored teardown-trap region with one fenced snippet"

# ── §2 exactly two actions: heartbeat.sh stop + claim.sh release --run ────────────────────
printf '%s\n' "$snippet" | grep -q 'heartbeat\.sh stop' \
  || fail "(2) the teardown snippet does not run 'heartbeat.sh stop'"
printf '%s\n' "$snippet" | grep -qE 'claim\.sh release .*--run' \
  || fail "(2) the teardown snippet does not run the id:89d6 sweep 'claim.sh release --run <RUN_ID>'"
extra="$(printf '%s\n' "$snippet" | grep -oE '[a-z0-9_-]+\.(sh|py|js)' | sort -u \
         | grep -vE '^(heartbeat|claim)\.sh$' || true)"
[[ -z "$extra" ]] \
  || fail "(2) the teardown snippet invokes MORE than the two permitted actions (two-action cap): $extra"
printf '%s\n' "$snippet" | grep -qE 'heartbeat\.sh (beat|start)' \
  && fail "(2) the teardown snippet BEATS the heartbeat — beat must STAY in-Workflow (--fabled F4: a shell-lifetime beater beats through a wedged Workflow and blinds id:98f0)"
pass "(2) the teardown owns exactly heartbeat.sh stop + the claim.sh release --run sweep"

# ── §3 no-swallow: neither action may be silenced ─────────────────────────────────────────
printf '%s\n' "$snippet" | grep -q '|| true' \
  && fail "(3) the teardown snippet contains '|| true' — a failed teardown MUST be loud ([[no-swallow-stderr]], D3-A rider 1)"
printf '%s\n' "$snippet" | grep -q '2>/dev/null' \
  && fail "(3) the teardown snippet redirects stderr to /dev/null — a failed teardown MUST be loud"
printf '%s\n' "$snippet" | grep -q 'trap' \
  || fail "(3) the teardown snippet installs no trap — it must be an EXIT trap, not a straight-line call on the success path"
printf '%s\n' "$snippet" | grep -qE 'trap[^#]*EXIT' \
  || fail "(3) the trap is not on EXIT — a Workflow that DIES must still tear down"
pass "(3) the teardown is an EXIT trap and swallows nothing"

# ── behavioural harness ───────────────────────────────────────────────────────────────────
STUB="$TMP/scripts"; mkdir -p "$STUB"
cp -- "$REAL_CLAIM" "$STUB/claim.sh"; chmod +x "$STUB/claim.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/heartbeat.sh"; chmod +x "$STUB/heartbeat.sh"

runnable="$TMP/teardown.sh"
printf '%s\n' "$snippet" | sed "s#~/.claude/skills/relay/scripts#$STUB#g" >"$runnable"

export CLAIM_BASE="$TMP/claimbase"
export CLAIM_LOG=/dev/null

seed_claims() {
  rm -rf "$CLAIM_BASE"
  "$STUB/claim.sh" acquire loderite   --repo loderite --run "$RUN_ID_T" --mode execute   >/dev/null
  "$STUB/claim.sh" acquire zkm-photo  --repo zkm-photo --run "$RUN_ID_T" --mode review   >/dev/null
  "$STUB/claim.sh" acquire truncocraft --repo truncocraft --run "$OTHER_RUN" --mode review >/dev/null
}
held_by_run() {  # count live shards whose .runId == $1
  local want="$1" n=0 f
  shopt -s nullglob
  for f in "$CLAIM_BASE"/claims/*.json; do
    [[ "$(jq -r '.runId // ""' "$f" 2>/dev/null)" == "$want" ]] && n=$((n + 1))
  done
  echo "$n"
}

# ── §4a a Workflow that RETURNS leaves no lease held by its runId ─────────────────────────
seed_claims
[[ "$(held_by_run "$RUN_ID_T")" -eq 2 ]] || fail "(4a) fixture setup failed"
( export RUN_ID="$RUN_ID_T" CLAIM_BASE CLAIM_LOG; . "$runnable"; exit 0 ) >/dev/null 2>&1
[[ "$(held_by_run "$RUN_ID_T")" -eq 0 ]] \
  || fail "(4a) after a Workflow that RETURNED, leases held by its runId survive"
[[ "$(held_by_run "$OTHER_RUN")" -eq 1 ]] \
  || fail "(4a) the teardown released ANOTHER run's lease — the sweep must be run-scoped"
pass "(4a) a Workflow that returns leaves no lease held by its runId (and none of another run's)"

# ── §4b a Workflow that DIES leaves no lease held by its runId ────────────────────────────
seed_claims
( export RUN_ID="$RUN_ID_T" CLAIM_BASE CLAIM_LOG; . "$runnable"; exit 7 ) >/dev/null 2>&1
[[ "$(held_by_run "$RUN_ID_T")" -eq 0 ]] \
  || fail "(4b) after a Workflow that DIED (exit 7), leases held by its runId survive — the trap is not on EXIT"
pass "(4b) a Workflow that dies leaves no lease held by its runId"

# ── §4c a FAILED release prints to stderr ─────────────────────────────────────────────────
seed_claims
FAILSTUB="$TMP/failscripts"; mkdir -p "$FAILSTUB"
printf '#!/usr/bin/env bash\necho "claim.sh: simulated release failure" >&2\nexit 1\n' >"$FAILSTUB/claim.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAILSTUB/heartbeat.sh"
chmod +x "$FAILSTUB/claim.sh" "$FAILSTUB/heartbeat.sh"
failrunnable="$TMP/teardown-fail.sh"
printf '%s\n' "$snippet" | sed "s#~/.claude/skills/relay/scripts#$FAILSTUB#g" >"$failrunnable"

errfile="$TMP/stderr.txt"
( export RUN_ID="$RUN_ID_T"; . "$failrunnable"; exit 0 ) >/dev/null 2>"$errfile"
[[ -s "$errfile" ]] \
  || fail "(4c) a FAILED release produced EMPTY stderr — the failure is being swallowed; it must be loud"
pass "(4c) a failed release prints to stderr"

# ── §5 the mode-b `--afk` prose no longer contradicts D2 ──────────────────────────────────
# Step 0b currently says an unattended mode-b run should "proceed conservatively" and keep
# model:"bash". After D2, mode-b is a launch REFUSAL; the two cannot both be documented.
modeb="$(grep -n 'proceed conservatively' "$SKILL" || true)"
[[ -z "$modeb" ]] \
  || fail "(5) relay/SKILL.md still tells an unattended run to 'proceed conservatively' on mode-b — D2 makes mode-b a launch REFUSAL. Offending line(s):
$modeb"
pass "(5) the mode-b --afk guidance no longer contradicts D2"

echo "ALL PASS: front-door EXIT-ONLY teardown trap + mode-b prose fix (id:54be)"
