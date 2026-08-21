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
#     * misuse (unknown runId, missing event log, corrupt relay.toml) exits 0 instead of
#       loudly nonzero — a scanner that reports "clean" when it could not read its inputs
#       is worse than no scanner.
#
# Hermetic: everything lives in one mktemp -d. HOME, RELAY_TOML, RELAY_EVENTS_PATH,
# RELAY_STATUS_PATH and the classify hook (RUN_ANOMALY_CLASSIFY) are all overridden, so
# the real ~/.claude, the real ~/.config/relay and the real repos are never touched, and
# no network or git remote is involved.

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

scan() {
  HOME="$tmp" \
  SRC_DIR="$REPOS" \
  RELAY_TOML="$TOML" \
  RELAY_EVENTS_PATH="$EVENTS" \
  RELAY_STATUS_PATH="$STATUS" \
  RUN_ANOMALY_CLASSIFY="$STUB" \
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
grep -q '(recorded)' <<<"$out" \
  || fail "--fast must report that verdicts are the RECORDED ones:\n$out"
grep -q -- '--fast' <<<"$out" || fail "--fast must warn that it is blind to state changed since:\n$out"
pass "--fast uses recorded verdicts and says so in the report"

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

echo "ALL TESTS PASSED"
