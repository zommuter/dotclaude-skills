#!/usr/bin/env bash
# test_run_anomaly_scan.sh — spec for relay/scripts/run-anomaly-scan.sh, the end-of-run
# anomaly checker.
#
# NO `# roadmap:` header ON PURPOSE. This is a DEFECT-FIX test, not a roadmap-item spec:
# it pins behaviour authored in response to three failures OBSERVED on 2026-08-21 (install
# drift dispatching two zero-unit rounds; dispatch-layer classifier blocks that leave no
# trace anywhere; loderite skipped twice over a stale worktree with six actionable
# [ROUTINE] items). Defect-fix tests carry no roadmap id, so their failures ALWAYS count —
# expected-red semantics must never let this one go quietly amber.
#
# fails-against: relay/scripts/run-anomaly-scan.sh absent, non-executable, or built so
#   that ANY of the following holds —
#     * a repo classifying pool-actionable with zero work-unit trace this run is not
#       reported STARVED (the loderite failure — the one that motivated the tool);
#     * a dispatch with no integrate and no handback is not reported
#       DISPATCHED-BUT-NO-OUTCOME;
#     * the EMPTY "no merged= line (unparseable integrator output):" handback signature
#       is not reported INTEGRATE-EVAPORATED, or a NON-empty tail of that same message
#       false-positives into it;
#     * dispatched>0 with integrated==0 is not reported ZERO-YIELD-RUN;
#     * a repo in a RELAY_STATUS skip/blocked section that still classifies actionable is
#       not reported SKIPPED-WITH-ACTIONABLE;
#     * a HEALTHY run produces ANY finding (the negative control — a false positive on an
#       observability tool destroys the credibility that makes anyone read it, id:4347);
#     * a deliberately excluded/paused repo is reported as an anomaly;
#     * the default posture is not report-only exit 0, or --strict does not gate;
#     * --json is not parseable JSON;
#     * misuse (unknown runId, missing event log, corrupt OR ABSENT relay.toml) exits 0
#       instead of loudly nonzero — a scanner that reports "clean" when it could not read
#       its inputs is worse than no scanner;
#     * any FALSE-POSITIVE GUARD either fails to silence its healthy state OR silences the
#       genuine anomaly next to it. Every guard is specified as a PAIR (scenarios 7-15),
#       because a guard that hides a true positive is worse than the FP it removed:
#         - an `--only`-scoped run flags the unscoped fleet STARVED, or the scope guard
#           silences an IN-SCOPE zero-trace repo, or it stops failing open on a run that
#           emitted no verdict events at all;
#         - a quota-stopped run's `## Queued` units read as STARVED;
#         - a still-ALIVE run's in-flight units read as ZERO-YIELD / DISPATCHED-BUT-NO-
#           OUTCOME, or liveness alone (dead run) or an in-flight row alone (live run,
#           other repo) suppresses — both conjuncts are load-bearing;
#         - a repo that INTEGRATED this run is flagged on its stale accumulator Blocked
#           row, or a benign `dirty-worktree`/`claimed-elsewhere`/`intensive` skip fires,
#           or the benign match widens enough to swallow "stale worktree from a dead run";
#         - `--fast` prints STARVED in its `clean:` list — a class it never examined
#           (id:87a7); it must live-reclassify zero-trace repos instead;
#         - a zero-trace repo whose live classification FAILED is dropped silently rather
#           than reported STARVED-UNVERIFIED;
#         - the `integrate.sh mechanical hop failed to dispatch (…)` evaporation signature
#           is missed, or over-matches an ordinary handback;
#         - an unreadable heartbeat suppresses anything (it must fail open toward
#           REPORTING — a false "alive" hides real findings).
#
# Hermetic: everything lives in one mktemp -d. HOME, RELAY_TOML, RELAY_EVENTS_PATH,
# RELAY_STATUS_PATH and the classify hook (RUN_ANOMALY_CLASSIFY) are all overridden, so
# the real ~/.claude, the real ~/.config/relay and the real repos are never touched, and
# no network or git remote is involved.
# fails-against-rev: 3c13d2c8df57 -- Makefile relay/scripts/run-anomaly-scan.sh
# fails-against-assertion: run-anomaly-scan.sh not found at

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/run-anomaly-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "run-anomaly-scan.sh not found at $SH"
[[ -x "$SH" ]] || fail "run-anomaly-scan.sh not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

REPOS="$tmp/src"
mkdir -p "$REPOS"
for r in alpha beta gamma delta epsilon healthy1 healthy2 excluded1; do
  mkdir -p "$REPOS/$r"
done

# --- fixture relay.toml: THE own-repo set (paths pinned; no ~/src glob anywhere) ------
TOML="$tmp/relay.toml"
{
  for r in alpha beta gamma delta epsilon healthy1 healthy2 excluded1; do
    printf '[repos.%s]\nclassification = "own"\npath = "%s/%s"\n\n' "$r" "$REPOS" "$r"
  done
  # a NON-own repo must never be enumerated, however actionable it looks
  printf '[repos.foreign]\nclassification = "external"\npath = "%s/foreign"\n\n' "$REPOS"
} > "$TOML"

# --- fixture classify hook ------------------------------------------------------------
# Emits the same fields run-anomaly-scan.sh reads off classify-repo.sh (verdict,
# actionable_routine_open, actionable_routine_ids). Keyed by repo name from a table file
# so each scenario below can restate the live verdicts without rewriting the stub.
VERDICTS="$tmp/verdicts.tsv"
STUB="$tmp/classify-stub.sh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
set -euo pipefail
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) shift 2 ;;
    *) shift ;;
  esac
done
line="$(grep -P "^\Q$repo\E\t" "$VERDICTS_FILE" || true)"
# a verdict cell of literal FAIL makes the classifier FAIL for that repo, so the
# STARVED-UNVERIFIED path (absence of evidence must never render as clean) is reachable.
case "$line" in
  *$'\t'FAIL*) echo "stub: classify failed for $repo" >&2; exit 1 ;;
esac
if [[ -z "$line" ]]; then
  printf '{"verdict":"idle","actionable_routine_open":0,"actionable_routine_ids":[]}\n'
  exit 0
fi
IFS=$'\t' read -r _ verdict count ids <<<"$line"
ids_json="[]"
if [[ -n "${ids:-}" ]]; then
  ids_json="[$(printf '%s' "$ids" | sed 's/[^,]*/"&"/g')]"
fi
printf '{"verdict":"%s","actionable_routine_open":%s,"actionable_routine_ids":%s}\n' \
  "$verdict" "${count:-0}" "$ids_json"
STUB_EOF
chmod +x "$STUB"

EVENTS="$tmp/relay-events.jsonl"
STATUS="$tmp/RELAY_STATUS.md"

# --- fixture heartbeat hook -----------------------------------------------------------
# Stands in for heartbeat.sh's `live-runs` subcommand, emitting the SAME one-JSON-line-per
# -run shape relay-status-publish.sh:158 already consumes. $LIVE_RUNS_FILE lists the runIds
# to report alive, one per line; an EMPTY file means "no run is alive", which is the
# default for every scenario that is not explicitly testing the in-flight guard.
LIVE_RUNS="$tmp/live-runs.txt"
: > "$LIVE_RUNS"
HBSTUB="$tmp/heartbeat-stub.sh"
cat > "$HBSTUB" <<'HB_EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "live-runs" ]] || { echo "heartbeat-stub: unexpected subcommand ${1:-}" >&2; exit 2; }
while IFS= read -r r; do
  [[ -n "$r" ]] || continue
  printf '{"runId":"%s","state":"alive","age_s":3}\n' "$r"
done < "$LIVE_RUNS_FILE"
HB_EOF
chmod +x "$HBSTUB"

scan() {
  HOME="$tmp" \
  SRC_DIR="$REPOS" \
  RELAY_TOML="$TOML" \
  RELAY_EVENTS_PATH="$EVENTS" \
  RELAY_STATUS_PATH="$STATUS" \
  RUN_ANOMALY_CLASSIFY="$STUB" \
  RUN_ANOMALY_HEARTBEAT="$HBSTUB" \
  LIVE_RUNS_FILE="$LIVE_RUNS" \
  VERDICTS_FILE="$VERDICTS" \
  RUN_ANOMALY_JOBS=2 \
  "$SH" "$@"
}

# ======================================================================================
# SCENARIO 1 — the sick run. One repo per anomaly class.
# ======================================================================================
RUN=run-sick

cat > "$VERDICTS" <<EOF
alpha	execute	3	57d1,6612,084f
beta	execute	1	aaaa
gamma	execute	1	bbbb
delta	execute	2	cccc,dddd
epsilon	idle	0
excluded1	execute	9	eeee
healthy1	idle	0
healthy2	idle	0
EOF

cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUN","kind":"verdict","repo":"alpha","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUN","kind":"verdict","repo":"excluded1","round":1,"verdict":"","reason":"excluded-by-config (paused)"}
{"ts":"","runId":"$RUN","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"aaaa"}
{"ts":"","runId":"$RUN","kind":"dispatch","repo":"gamma","mode":"execute","round":1,"item":"bbbb"}
{"ts":"","runId":"$RUN","kind":"handback","repo":"gamma","mode":"execute","reason":"integrate.sh produced no merged= line (unparseable integrator output): "}
{"ts":"","runId":"$RUN","kind":"dispatch","repo":"delta","mode":"execute","round":1,"item":"cccc"}
{"ts":"","runId":"$RUN","kind":"handback","repo":"delta","mode":"execute","reason":"sizing out as a hard-split; no commit made"}
{"ts":"","runId":"$RUN","kind":"dispatch","repo":"epsilon","mode":"execute","round":1,"item":"ffff"}
{"ts":"","runId":"$RUN","kind":"handback","repo":"epsilon","mode":"execute","reason":"integrate.sh produced no merged= line (unparseable integrator output): merged=0 conflicts"}
{"ts":"","runId":"$RUN","kind":"dispatch","repo":"healthy1","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUN","kind":"integrate","repo":"healthy1","mode":"execute","ckpt":"relay-ckpt-x","ids":["9999"]}
EOF

cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUN -->
## Run $RUN

## Completed this run
- healthy1  mode=execute  ckpt=relay-ckpt-x  ids=9999

## Blocked / HANDBACKs
- delta  reason=sizing out as a hard-split; no commit made  worktree=-
- gamma  reason=integrate.sh produced no merged= line (unparseable integrator output):   worktree=-

## Skipped (this round)
- alpha  stale worktree run-dead-0 from a dead run — park it for manual /relay reconcile
- excluded1  excluded-by-config (paused)
<!-- /relay-run:$RUN -->
EOF

out="$(scan "$RUN")" || fail "scan exited nonzero without --strict (report-only violated)"
echo "$out" > "$tmp/out-sick.txt"

# --- STARVED: alpha classifies execute with 3 items and has NO work-unit trace ---------
grep -q -- "--- STARVED ---" <<<"$out" || fail "STARVED section missing:\n$out"
grep -qE '^! alpha: .*execute.*3 actionable' <<<"$out" \
  || fail "alpha must be STARVED with its live item count:\n$out"
grep -q '57d1,6612,084f' <<<"$out" || fail "STARVED finding must name the actionable ids:\n$out"
# and it must carry a next command a human can actually run
grep -qE '^ *next: .+alpha' <<<"$out" || fail "STARVED finding must name a next command:\n$out"
pass "STARVED: actionable repo with zero work-unit trace is reported, with ids + next command"

# the recorded skip reason mentions a worktree → the next command must be the reconcile path
grep -qE '^ *next: git -C .*alpha worktree list' <<<"$out" \
  || fail "a worktree-flavoured skip reason must route to the worktree/reconcile command:\n$out"
pass "STARVED next-command specializes to worktree reconcile when the skip reason says so"

# --- DISPATCHED-BUT-NO-OUTCOME: beta dispatched, never integrated, never handed back ---
grep -q -- "--- DISPATCHED-BUT-NO-OUTCOME ---" <<<"$out" \
  || fail "DISPATCHED-BUT-NO-OUTCOME section missing:\n$out"
grep -qE '^! beta: dispatched with no integrate and no handback' <<<"$out" \
  || fail "beta must be DISPATCHED-BUT-NO-OUTCOME:\n$out"
pass "DISPATCHED-BUT-NO-OUTCOME: a dispatch with no outcome event is reported"

# --- INTEGRATE-EVAPORATED: gamma's EMPTY signature fires; epsilon's non-empty does not --
grep -q -- "--- INTEGRATE-EVAPORATED ---" <<<"$out" \
  || fail "INTEGRATE-EVAPORATED section missing:\n$out"
grep -qE '^! gamma: .*EMPTY .no merged= line' <<<"$out" \
  || fail "gamma (empty integrator-output signature) must be INTEGRATE-EVAPORATED:\n$out"
grep -qE '^! epsilon: .*EMPTY' <<<"$out" \
  && fail "epsilon's NON-EMPTY tail must NOT be INTEGRATE-EVAPORATED (different defect):\n$out"
pass "INTEGRATE-EVAPORATED: empty-tail signature fires; non-empty tail does not false-positive"

# --- cause honesty: it must NOT assert "classifier block" ------------------------------
grep -qi 'CAUSE UNKNOWN' <<<"$out" \
  || fail "INTEGRATE-EVAPORATED must be reported as cause-unknown (id:f5d9(b)):\n$out"
pass "INTEGRATE-EVAPORATED is reported cause-UNKNOWN, not asserted as a classifier block"

# --- SKIPPED-WITH-ACTIONABLE: delta ran, was handed back, still actionable -------------
grep -q -- "--- SKIPPED-WITH-ACTIONABLE ---" <<<"$out" \
  || fail "SKIPPED-WITH-ACTIONABLE section missing:\n$out"
grep -qE '^! delta: ends the run in RELAY_STATUS .blocked.*2 actionable' <<<"$out" \
  || fail "delta must be SKIPPED-WITH-ACTIONABLE with its item count:\n$out"
pass "SKIPPED-WITH-ACTIONABLE: blocked repo that still classifies actionable is reported"

# --- mutual exclusivity: no repo in both STARVED and SKIPPED-WITH-ACTIONABLE -----------
starved="$(awk '/^--- STARVED ---/{f=1;next} /^--- /{f=0} f && /^! /{print $2}' <<<"$out" | tr -d ':')"
skipped="$(awk '/^--- SKIPPED-WITH-ACTIONABLE ---/{f=1;next} /^--- /{f=0} f && /^! /{print $2}' <<<"$out" | tr -d ':')"
both="$(comm -12 <(sort <<<"$starved") <(sort <<<"$skipped") | tr -d '[:space:]')"
[[ -z "$both" ]] || fail "repo(s) reported in BOTH STARVED and SKIPPED-WITH-ACTIONABLE: $both"
pass "STARVED and SKIPPED-WITH-ACTIONABLE are mutually exclusive"

# --- excluded/paused repos are never anomalies, however actionable they classify -------
grep -q 'excluded1' <<<"$out" \
  && fail "a deliberately excluded/paused repo must never be reported:\n$out"
pass "excluded-by-config repo is not an anomaly (config working, not a defect)"

# --- a non-own repo is never enumerated ------------------------------------------------
grep -q 'foreign' <<<"$out" && fail "a non-own relay.toml repo must never be scanned:\n$out"
pass "non-own repos are never scanned (relay.toml own-set is the authority)"

# --- report-only posture + --strict gate ----------------------------------------------
rc=0; scan "$RUN" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "default posture must be report-only exit 0; got $rc"
rc=0; scan "$RUN" --strict >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "--strict must exit nonzero when findings exist; got $rc"
pass "report-only by default (exit 0); --strict exits nonzero on findings"

# --- --json is parseable and carries the classes ---------------------------------------
js="$(scan "$RUN" --json)"
python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
classes={f["class"] for f in d["findings"]}
need={"STARVED","DISPATCHED-BUT-NO-OUTCOME","INTEGRATE-EVAPORATED","SKIPPED-WITH-ACTIONABLE"}
missing=need-classes
assert not missing, "missing classes in --json: %s" % missing
assert d["run_id"], "no run_id in --json"
' <<<"$js" || fail "--json must be parseable JSON carrying every detected class"
pass "--json emits parseable JSON carrying every detected anomaly class"

# ======================================================================================
# SCENARIO 2 — ZERO-YIELD RUN (dispatched > 0, integrated == 0)
# ======================================================================================
RUN0=run-zero
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUN0","kind":"dispatch","repo":"healthy1","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUN0","kind":"handback","repo":"healthy1","mode":"execute","reason":"executor declined"}
EOF
cat > "$VERDICTS" <<'EOF'
healthy1	idle	0
EOF
: > "$STATUS"
out="$(scan "$RUN0")" || fail "zero-yield scan exited nonzero without --strict"
grep -q -- "--- ZERO-YIELD-RUN ---" <<<"$out" \
  || fail "dispatched>0 with integrated==0 must be ZERO-YIELD-RUN:\n$out"
grep -q 'dispatched=1 but integrated=0' <<<"$out" || fail "ZERO-YIELD-RUN must show the totals:\n$out"
pass "ZERO-YIELD-RUN: dispatched>0 / integrated==0 is reported with its totals"

# ======================================================================================
# SCENARIO 3 — NEGATIVE CONTROL. A healthy run must produce ZERO findings.
#   Every dispatched repo integrated; nothing skipped classifies actionable; every
#   undispatched own repo is idle. A false positive here is the failure that would make
#   people stop reading the report, so this assertion is as load-bearing as the five above.
# ======================================================================================
RUNH=run-healthy
cat > "$VERDICTS" <<'EOF'
alpha	idle	0
beta	idle	0
gamma	idle	0
delta	idle	0
epsilon	idle	0
excluded1	execute	9	eeee
healthy1	idle	0
healthy2	human	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNH","kind":"verdict","repo":"excluded1","round":1,"verdict":"","reason":"excluded-by-config (paused)"}
{"ts":"","runId":"$RUNH","kind":"dispatch","repo":"healthy1","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUNH","kind":"integrate","repo":"healthy1","mode":"execute","ckpt":"relay-ckpt-h","ids":["9999"]}
{"ts":"","runId":"$RUNH","kind":"dispatch","repo":"beta","mode":"review","round":1,"item":""}
{"ts":"","runId":"$RUNH","kind":"integrate","repo":"beta","mode":"review","ckpt":"relay-ckpt-h2","ids":[]}
EOF
cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUNH -->
## Run $RUNH

## Completed this run
- healthy1  mode=execute  ckpt=relay-ckpt-h  ids=9999
- beta  mode=review  ckpt=relay-ckpt-h2

## Blocked / HANDBACKs
_(none)_

## Skipped (this round)
- alpha  No actionable work found in any D3 priority class; backlog scan clean
- gamma  No actionable work found in any D3 priority class; backlog scan clean
- healthy2  human (surface-only backlog — not dispatchable pool work)
- excluded1  excluded-by-config (paused)
<!-- /relay-run:$RUNH -->
EOF

out="$(scan "$RUNH")" || fail "healthy scan exited nonzero without --strict"
echo "$out" > "$tmp/out-healthy.txt"
grep -q 'no anomalies' <<<"$out" || fail "NEGATIVE CONTROL: a healthy run must report no anomalies:\n$out"
grep -qE '^0 finding\(s\)' <<<"$out" || fail "NEGATIVE CONTROL: finding count must be 0:\n$out"
grep -qE '^! ' <<<"$out" && fail "NEGATIVE CONTROL: a healthy run emitted a finding line:\n$out"
pass "NEGATIVE CONTROL: a healthy run produces ZERO findings"

rc=0; scan "$RUNH" --strict >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "--strict on a healthy run must exit 0; got $rc"
pass "--strict on a healthy run exits 0"

# a `human`-verdict repo in the skipped section is NOT dispatchable pool work
grep -q 'healthy2' <<<"$out" && fail "a human-verdict repo must not be an anomaly:\n$out"
pass "human/mechanical/idle verdicts are not treated as pool-actionable"

# ======================================================================================
# SCENARIO 4 — MISUSE is loud. A scanner that cannot read its inputs must never say clean.
# ======================================================================================
rc=0; scan "no-such-run" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "an unknown runId must exit 2 (loud misuse); got $rc"
pass "unknown runId exits 2 (never a quiet clean report)"

rc=0
HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" \
  RELAY_EVENTS_PATH="$tmp/absent.jsonl" RELAY_STATUS_PATH="$STATUS" \
  RUN_ANOMALY_CLASSIFY="$STUB" VERDICTS_FILE="$VERDICTS" \
  "$SH" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "a missing event log must exit 2; got $rc"
pass "missing event log exits 2 (cannot audit a run without it)"

printf 'this is [not toml\n' > "$tmp/broken.toml"
rc=0
HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$tmp/broken.toml" \
  RELAY_EVENTS_PATH="$EVENTS" RELAY_STATUS_PATH="$STATUS" \
  RUN_ANOMALY_CLASSIFY="$STUB" VERDICTS_FILE="$VERDICTS" \
  "$SH" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "a CORRUPT relay.toml must exit 2, not silently enumerate zero repos (id:0fa0); got $rc"
pass "corrupt relay.toml exits 2 (id:0fa0 — never a silently-empty own-set)"

rc=0; scan --bogus-flag >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "an unknown flag must exit 2; got $rc"
pass "unknown flag exits 2"

# ======================================================================================
# SCENARIO 5 — --list-runs and --fast
# ======================================================================================
runs="$(scan --list-runs)"
[[ "$runs" == "$RUNH" ]] || fail "--list-runs must list the runIds present; got: $runs"
pass "--list-runs lists the runIds in the event log"

out="$(scan "$RUNH" --fast)" || fail "--fast exited nonzero"
grep -q '(hybrid)' <<<"$out" \
  || fail "--fast must report the HYBRID classify mode:\n$out"
grep -q -- '--fast' <<<"$out" || fail "--fast must warn that it is blind to state changed since:\n$out"
grep -q 'RECORDED' <<<"$out" || fail "--fast must say which verdicts are the RECORDED ones:\n$out"
pass "--fast reports the hybrid mode and names live vs recorded verdicts"

# ======================================================================================
# SCENARIO 6 — the real classify-repo.sh path (no stub), to prove the default wiring.
#   Uses a genuine git fixture repo with one open actionable [ROUTINE] item and NO events
#   for the run, i.e. the loderite shape end-to-end through the production classifier.
# ======================================================================================
REAL="$tmp/realsrc/starvedrepo"
mkdir -p "$REAL"
git -C "$REAL" init -q
git -C "$REAL" config user.email t@e.st
git -C "$REAL" config user.name t
printf '# ROADMAP\n\n## Items\n\n- [ ] a genuinely actionable unit [ROUTINE] <!-- id:ab12 -->\n' > "$REAL/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] a genuinely actionable unit <!-- id:ab12 -->\n' > "$REAL/TODO.md"
touch "$REAL/TODO.archive.md"
git -C "$REAL" add -A
git -C "$REAL" commit -qm init

REALTOML="$tmp/real-relay.toml"
printf '[repos.starvedrepo]\nclassification = "own"\npath = "%s"\n' "$REAL" > "$REALTOML"
REALEV="$tmp/real-events.jsonl"
printf '{"ts":"","runId":"run-real","kind":"dispatch","repo":"other","mode":"execute","round":1}\n{"ts":"","runId":"run-real","kind":"integrate","repo":"other","mode":"execute","ckpt":"c","ids":[]}\n' > "$REALEV"

out="$(HOME="$tmp" SRC_DIR="$tmp/realsrc" RELAY_TOML="$REALTOML" \
       RELAY_EVENTS_PATH="$REALEV" RELAY_STATUS_PATH="$tmp/absent-status.md" \
       RUN_ANOMALY_JOBS=1 "$SH" run-real)" \
  || fail "real-classify scan exited nonzero"
grep -qE '^! starvedrepo: classifies execute' <<<"$out" \
  || fail "the DEFAULT (unstubbed) classify-repo.sh path must report the starved repo:\n$out"
grep -q 'ab12' <<<"$out" || fail "real classify path must surface the actionable id:\n$out"
pass "default path calls the real classify-repo.sh and reports the starved repo end-to-end"

# ======================================================================================
# FALSE-POSITIVE GUARDS (id:f0ad(b), id:87a7).
#
# Every scenario below is a PAIR: the HEALTHY state must be silent, AND the genuine
# anomaly that lives closest to it must still be reported. A guard is only tested by the
# pair — the prior mutation pass killed 10 of 22 mutations and EVERY survivor was an FP
# guard, because the negative control held no repo with a live pool-actionable verdict,
# so no fixture reached those branches at all. Each fixture here therefore carries at
# least one repo classifying `execute` with a live item count, and asserts silence.
# ======================================================================================

# --- helper: assert a scan produced no findings at all --------------------------------
assert_clean() {
  local why="$1" o="$2"
  grep -q 'no anomalies' <<<"$o" || fail "$why — expected zero findings:\n$o"
  grep -qE '^! ' <<<"$o" && fail "$why — a finding line was emitted:\n$o"
  return 0
}

# ======================================================================================
# SCENARIO 7 — `--only`-scoped run. Out-of-scope repos are NOT starved.
#   relay-loop.js drops out-of-scope repos BEFORE sharding, so they get no verdict event
#   and no trace. Without the scope guard every other own repo reports STARVED.
# ======================================================================================
RUNO=run-only
cat > "$VERDICTS" <<'EOF'
alpha	execute	3	57d1,6612,084f
gamma	execute	2	bbbb,cccc
delta	execute	1	dddd
beta	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNO","kind":"verdict","repo":"beta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNO","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUNO","kind":"integrate","repo":"beta","mode":"execute","ckpt":"relay-ckpt-o","ids":["9999"]}
EOF
cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUNO -->
## Run $RUNO

## Completed this run
- beta  mode=execute  ckpt=relay-ckpt-o  ids=9999

## Blocked / HANDBACKs
_(none)_

## Skipped (this round)
_(none)_
<!-- /relay-run:$RUNO -->
EOF

out="$(scan "$RUNO")" || fail "--only-scoped scan exited nonzero"
assert_clean "--only-scoped run" "$out"
grep -qE '^! alpha' <<<"$out" && fail "an out-of-scope repo must never be STARVED:\n$out"
grep -qE 'NOT in this run.s scope' <<<"$out" \
  || fail "the report must SAY which repos were out of scope, not silently drop them:\n$out"
pass "FP GUARD (scope): an --only-scoped run does not report the unscoped fleet as STARVED"

# TRUE POSITIVE, same shape: alpha now HAS a verdict event (it was in scope), still zero
# trace, still classifies execute → the scope guard must NOT silence it.
cat >> "$EVENTS" <<EOF
{"ts":"","runId":"$RUNO","kind":"verdict","repo":"alpha","round":1,"verdict":"execute","reason":"actionable"}
EOF
out="$(scan "$RUNO")" || fail "in-scope starved scan exited nonzero"
grep -qE '^! alpha: classifies execute.*3 actionable' <<<"$out" \
  || fail "an IN-SCOPE repo with zero trace must still be STARVED:\n$out"
grep -qE '^! gamma' <<<"$out" && fail "gamma is still out of scope and must stay silent:\n$out"
pass "TRUE POSITIVE preserved: an in-scope zero-trace actionable repo is still STARVED"

# FAIL-OPEN: a run that emitted NO verdict events at all carries no scope evidence, so
# NOTHING is filtered — otherwise the guard silences the class whenever the verdict rows
# are themselves what went missing.
RUNN=run-noverdict
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNN","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUNN","kind":"integrate","repo":"beta","mode":"execute","ckpt":"c","ids":["9999"]}
EOF
: > "$STATUS"
out="$(scan "$RUNN")" || fail "no-verdict-event scan exited nonzero"
grep -qE '^! alpha: classifies execute' <<<"$out" \
  || fail "with NO verdict events the scope guard must FAIL OPEN and keep every repo a candidate:\n$out"
pass "FAIL-OPEN: a run with zero verdict events applies no scope filtering"

# ======================================================================================
# SCENARIO 8 — quota-stopped --afk run. `## Queued` units are accounted for, not starved.
# ======================================================================================
RUNQ=run-quota
cat > "$VERDICTS" <<'EOF'
alpha	execute	3	57d1,6612,084f
gamma	execute	2	bbbb,cccc
beta	idle	0
delta	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNQ","kind":"verdict","repo":"alpha","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNQ","kind":"verdict","repo":"gamma","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNQ","kind":"verdict","repo":"beta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNQ","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUNQ","kind":"integrate","repo":"beta","mode":"execute","ckpt":"relay-ckpt-q","ids":["9999"]}
EOF
cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUNQ -->
## Run $RUNQ

## In-flight
_(none)_

## Completed this run
- beta  mode=execute  ckpt=relay-ckpt-q  ids=9999

## Queued
- alpha  verdict=execute (not dispatched)
- gamma  verdict=execute (not dispatched)

## Blocked / HANDBACKs
_(none)_

## Skipped (this round)
_(none)_

## Quota remaining
- session  remaining=0%
<!-- /relay-run:$RUNQ -->
EOF

out="$(scan "$RUNQ")" || fail "quota-stopped scan exited nonzero"
assert_clean "quota-stopped run with a populated ## Queued" "$out"
pass "FP GUARD (queued): classified-but-undispatched units in ## Queued are not STARVED"

# TRUE POSITIVE: gamma leaves the Queued section — now nothing accounts for it, and it
# must be STARVED again. Only the ONE line changes between the two assertions.
python3 - "$STATUS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- gamma  verdict=execute (not dispatched)\n", "")
open(p, "w").write(t)
PY
out="$(scan "$RUNQ")" || fail "de-queued scan exited nonzero"
grep -qE '^! gamma: classifies execute.*2 actionable' <<<"$out" \
  || fail "a repo NOT in ## Queued with zero trace must still be STARVED:\n$out"
grep -qE '^! alpha' <<<"$out" && fail "alpha is still queued and must stay silent:\n$out"
pass "TRUE POSITIVE preserved: dropping a repo out of ## Queued restores its STARVED finding"

# ======================================================================================
# SCENARIO 9 — in-flight run. A unit still EXECUTING has not yet failed to yield.
# ======================================================================================
RUNI=run-inflight
cat > "$VERDICTS" <<'EOF'
alpha	execute	3	57d1
beta	execute	1	bbbb
gamma	idle	0
delta	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNI","kind":"verdict","repo":"alpha","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNI","kind":"dispatch","repo":"alpha","mode":"execute","round":1,"item":"57d1"}
EOF
cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUNI -->
## Run $RUNI

## In-flight
- alpha  mode=execute  agent=ag-0001  → id:57d1 (1 of 3 actionable)

## Completed this run
_(none)_

## Blocked / HANDBACKs
_(none)_

## Skipped (this round)
_(none)_
<!-- /relay-run:$RUNI -->
EOF

printf '%s\n' "$RUNI" > "$LIVE_RUNS"
out="$(scan "$RUNI")" || fail "in-flight scan exited nonzero"
assert_clean "a still-alive run with an in-flight unit" "$out"
grep -q 'STILL ALIVE' <<<"$out" || fail "the report must say the run is still alive:\n$out"
pass "FP GUARD (in-flight): a live run's executing unit is neither ZERO-YIELD nor DISPATCHED-BUT-NO-OUTCOME"

# TRUE POSITIVE (a): the run is DEAD — the same in-flight row is now a STRANDED unit.
: > "$LIVE_RUNS"
out="$(scan "$RUNI")" || fail "dead-run scan exited nonzero"
grep -q -- "--- ZERO-YIELD-RUN ---" <<<"$out" \
  || fail "a DEAD run with dispatched>0 / integrated==0 must still be ZERO-YIELD-RUN:\n$out"
grep -qE '^! alpha: dispatched with no integrate and no handback' <<<"$out" \
  || fail "a DEAD run's in-flight row is a stranded unit and must still be reported:\n$out"
pass "TRUE POSITIVE preserved: liveness ALONE does not suppress — a dead run reports its stranded units"

# TRUE POSITIVE (b): the run IS alive, but a repo with NO in-flight row evaporated. The
# in-flight row ALONE must not suppress either — both conjuncts are load-bearing.
printf '%s\n' "$RUNI" > "$LIVE_RUNS"
cat >> "$EVENTS" <<EOF
{"ts":"","runId":"$RUNI","kind":"verdict","repo":"beta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNI","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"bbbb"}
EOF
out="$(scan "$RUNI")" || fail "live-run-with-evaporation scan exited nonzero"
grep -qE '^! beta: dispatched with no integrate and no handback' <<<"$out" \
  || fail "a live run must still report a repo that has NO in-flight row and no outcome:\n$out"
grep -qE '^! alpha: dispatched with no integrate' <<<"$out" \
  && fail "alpha IS in flight in a live run and must stay silent:\n$out"
pass "TRUE POSITIVE preserved: in a live run, only the repos actually IN FLIGHT are exempt"
: > "$LIVE_RUNS"

# ======================================================================================
# SCENARIO 10 — handback accumulator + benign per-round skips.
#   state.handbacks is push-only and never reset all run, so a repo handed back in round 1
#   and INTEGRATED in round 2 keeps its Blocked row. And under one-unit-per-repo-per-round
#   a backlog repo is EXPECTED to be skipped once its unit lands.
# ======================================================================================
RUNA=run-accum
cat > "$VERDICTS" <<'EOF'
beta	execute	4	b111,b222
delta	execute	2	d111
gamma	execute	6	g111,g222
alpha	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNA","kind":"verdict","repo":"beta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNA","kind":"verdict","repo":"delta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNA","kind":"verdict","repo":"gamma","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNA","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"b111"}
{"ts":"","runId":"$RUNA","kind":"handback","repo":"beta","mode":"execute","reason":"executor declined round 1"}
{"ts":"","runId":"$RUNA","kind":"dispatch","repo":"beta","mode":"execute","round":2,"item":"b111"}
{"ts":"","runId":"$RUNA","kind":"integrate","repo":"beta","mode":"execute","ckpt":"relay-ckpt-a","ids":["b111"]}
{"ts":"","runId":"$RUNA","kind":"dispatch","repo":"delta","mode":"execute","round":1,"item":"d111"}
{"ts":"","runId":"$RUNA","kind":"handback","repo":"delta","mode":"execute","reason":"executor declined"}
{"ts":"","runId":"$RUNA","kind":"dispatch","repo":"gamma","mode":"execute","round":1,"item":"g111"}
{"ts":"","runId":"$RUNA","kind":"handback","repo":"gamma","mode":"execute","reason":"executor declined"}
EOF
cat > "$STATUS" <<EOF
# RELAY_STATUS

<!-- relay-run:$RUNA -->
## Run $RUNA

## Completed this run
- beta  mode=execute  ckpt=relay-ckpt-a  ids=b111

## Blocked / HANDBACKs
- beta  reason=executor declined round 1  worktree=-

## Skipped (this round)
- delta  dirty-worktree
- gamma  stale worktree run-dead-0 from a dead run — park it for manual /relay reconcile
<!-- /relay-run:$RUNA -->
EOF

out="$(scan "$RUNA")" || fail "accumulator scan exited nonzero"
echo "$out" > "$tmp/out-accum.txt"
grep -qE '^! beta: ends the run in RELAY_STATUS' <<<"$out" \
  && fail "FP GUARD (accumulator): a repo that INTEGRATED this run must not be SKIPPED-WITH-ACTIONABLE on a stale Blocked row:\n$out"
pass "FP GUARD (accumulator): a round-1 handback row does not flag a repo that integrated in round 2"

grep -qE '^! delta: ends the run in RELAY_STATUS' <<<"$out" \
  && fail "FP GUARD (benign skip): a 'dirty-worktree' per-round skip must not be an anomaly:\n$out"
pass "FP GUARD (benign skip): claimed-elsewhere / dirty-worktree / intensive skips are silent"

# TRUE POSITIVE, in the SAME fixture: gamma's skip reason merely CONTAINS the word
# "worktree" — it is the loderite failure, not a benign `dirty-worktree` category — and
# must still fire. This is what keeps the benign match narrow.
grep -qE '^! gamma: ends the run in RELAY_STATUS .skipped.*6 actionable' <<<"$out" \
  || fail "a 'stale worktree from a dead run' skip is the loderite case and must still be reported:\n$out"
pass "TRUE POSITIVE preserved: a stale-worktree skip is NOT matched as a benign category"

# and a plain blocked repo with no integrate is still reported
cat >> "$STATUS" <<'EOF'
EOF
python3 - "$STATUS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace(
    "- beta  reason=executor declined round 1  worktree=-",
    "- beta  reason=executor declined round 1  worktree=-\n- delta  reason=executor declined  worktree=-")
open(p, "w").write(t)
PY
out="$(scan "$RUNA")" || fail "blocked-no-integrate scan exited nonzero"
grep -qE '^! delta: ends the run in RELAY_STATUS .blocked.*2 actionable' <<<"$out" \
  || fail "a BLOCKED repo that never integrated must still be SKIPPED-WITH-ACTIONABLE:\n$out"
pass "TRUE POSITIVE preserved: a blocked repo with no integrate this run still reports"

# ======================================================================================
# SCENARIO 11 — --fast must NOT lose the STARVED class (id:87a7).
#   The defect: `--fast` printed `clean: … STARVED`, affirmatively declaring clean a class
#   it never examined. A mode that cannot check a class must never print that class clean.
# ======================================================================================
RUNF=run-fast
cat > "$VERDICTS" <<'EOF'
alpha	execute	3	57d1,6612,084f
beta	idle	0
gamma	idle	0
delta	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNF","kind":"verdict","repo":"alpha","round":1,"verdict":"idle","reason":"stale — nothing to do"}
{"ts":"","runId":"$RUNF","kind":"verdict","repo":"beta","round":1,"verdict":"execute","reason":"actionable"}
{"ts":"","runId":"$RUNF","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"9999"}
{"ts":"","runId":"$RUNF","kind":"integrate","repo":"beta","mode":"execute","ckpt":"relay-ckpt-f","ids":["9999"]}
EOF
: > "$STATUS"

out="$(scan "$RUNF" --fast)" || fail "--fast scan exited nonzero"
grep -qE '^! alpha: classifies execute.*3 actionable' <<<"$out" \
  || fail "--fast must LIVE-reclassify zero-trace repos so STARVED is not lost (the recorded verdict says idle):\n$out"
# exact-token membership in the `clean:` list — a substring match would be satisfied by
# STARVED-UNVERIFIED and quietly stop testing the thing this assertion is for.
clean_line="$(grep -E '^clean: ' <<<"$out" || true)"
clean_items="$(tr ',' '\n' <<<"${clean_line#clean: }" | tr -d ' ')"
grep -qx 'STARVED' <<<"$clean_items" \
  && fail "--fast must never print STARVED as clean:\n$out"
pass "id:87a7: --fast is HYBRID — a zero-trace repo is live-reclassified and STARVED survives"

# and the full mode agrees, so the two modes cannot silently disagree on this class
out_full="$(scan "$RUNF")" || fail "full-mode scan exited nonzero"
grep -qE '^! alpha: classifies execute.*3 actionable' <<<"$out_full" \
  || fail "full mode must report the same STARVED case as --fast:\n$out_full"
pass "--fast and full mode agree on the STARVED class"

# ======================================================================================
# SCENARIO 12 — STARVED-UNVERIFIED. A class that could not be CHECKED is never "clean".
# ======================================================================================
cat > "$VERDICTS" <<'EOF'
alpha	FAIL	0
beta	idle	0
gamma	idle	0
delta	idle	0
epsilon	idle	0
healthy1	idle	0
healthy2	idle	0
excluded1	idle	0
EOF
out="$(scan "$RUNF")" || fail "classify-failure scan exited nonzero"
grep -q -- "--- STARVED-UNVERIFIED ---" <<<"$out" \
  || fail "a zero-trace repo whose live classification FAILED must be STARVED-UNVERIFIED, not silently dropped:\n$out"
grep -qE '^! alpha: zero work-unit trace.*classification failed' <<<"$out" \
  || fail "STARVED-UNVERIFIED must name the repo and say why it could not be checked:\n$out"
pass "STARVED-UNVERIFIED: an unclassifiable zero-trace repo is reported, never assumed clean"

# ======================================================================================
# SCENARIO 13 — the SECOND evaporation signature (relay-loop.js:3219).
#   Three of the four evaporations on 2026-08-21 came through the mechanical-hop branch,
#   which the empty-tail-only regex missed entirely.
# ======================================================================================
RUNE=run-evap2
cat > "$VERDICTS" <<'EOF'
beta	idle	0
gamma	idle	0
EOF
cat > "$EVENTS" <<EOF
{"ts":"","runId":"$RUNE","kind":"dispatch","repo":"beta","mode":"execute","round":1,"item":"b1"}
{"ts":"","runId":"$RUNE","kind":"handback","repo":"beta","mode":"execute","reason":"integrate.sh mechanical hop failed to dispatch (Error: model 404) — no merged= line was returned; the worktree stays on disk for a retry"}
{"ts":"","runId":"$RUNE","kind":"dispatch","repo":"gamma","mode":"execute","round":1,"item":"g1"}
{"ts":"","runId":"$RUNE","kind":"handback","repo":"gamma","mode":"execute","reason":"executor sized the item out; no commit made"}
EOF
: > "$STATUS"
out="$(scan "$RUNE")" || fail "evap2 scan exited nonzero"
grep -qE '^! beta: .*handback' <<<"$out" \
  || fail "the mechanical-hop dispatch-failure signature must be INTEGRATE-EVAPORATED:\n$out"
# capture-then-test, never `awk … | grep -q` (pipefail + early-exiting consumer is banned)
evap_block="$(awk '/^--- INTEGRATE-EVAPORATED ---/{f=1;next} /^--- /{f=0} f' <<<"$out")"
grep -q '^! beta:' <<<"$evap_block" \
  || fail "beta must appear under INTEGRATE-EVAPORATED:\n$out"
grep -q '^! gamma:' <<<"$evap_block" \
  && fail "an ordinary handback reason must NOT be INTEGRATE-EVAPORATED:\n$out"
pass "INTEGRATE-EVAPORATED also catches the mechanical-hop dispatch failure, without over-matching"

# ======================================================================================
# SCENARIO 14 — an ABSENT relay.toml is misuse, not a clean fleet.
#   Only the CORRUPT path was guarded; an absent file yielded own-repos=0, no findings,
#   exit 0 — a false clean.
# ======================================================================================
rc=0
HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$tmp/no-such-relay.toml" \
  RELAY_EVENTS_PATH="$EVENTS" RELAY_STATUS_PATH="$STATUS" \
  RUN_ANOMALY_CLASSIFY="$STUB" VERDICTS_FILE="$VERDICTS" \
  "$SH" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "an ABSENT relay.toml must exit 2 like every other unreadable input; got $rc"
pass "absent relay.toml exits 2 (never own-repos=0 + 'no anomalies' + exit 0)"

# ======================================================================================
# SCENARIO 15 — the heartbeat probe is FAIL-OPEN in the safe direction.
#   A broken/absent heartbeat must suppress NOTHING; a false "alive" would hide findings.
# ======================================================================================
out="$(HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" \
       RELAY_EVENTS_PATH="$EVENTS" RELAY_STATUS_PATH="$STATUS" \
       RUN_ANOMALY_CLASSIFY="$STUB" VERDICTS_FILE="$VERDICTS" \
       RUN_ANOMALY_HEARTBEAT="$tmp/no-such-heartbeat.sh" RUN_ANOMALY_JOBS=2 \
       "$SH" "$RUNE")" || fail "scan with an absent heartbeat exited nonzero"
grep -q -- "--- ZERO-YIELD-RUN ---" <<<"$out" \
  || fail "an ABSENT heartbeat must suppress nothing (fail-open toward REPORTING):\n$out"
grep -q 'STILL ALIVE' <<<"$out" && fail "an absent heartbeat must never claim the run is alive:\n$out"
pass "heartbeat probe fails open toward reporting (an unreadable heartbeat suppresses nothing)"

echo "ALL TESTS PASSED"
