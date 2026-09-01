#!/usr/bin/env bash
# test_death_record.sh — spec for relay/scripts/death-record.sh, the child death-cause record.
#
# NO `# roadmap:` header ON PURPOSE. This is a DEFECT-FIX test, not a roadmap-item spec: it
# pins behaviour authored against the id:4f9b/id:93cc incident (a child died `Prompt is too
# long` AFTER the dispatch-time gate correctly declined to fire, having already committed 566
# lines) and against the 2026-08-20 salvage incident (three children died holding 130-200k
# tokens of uncommitted work, recovered only because a human went looking). Defect-fix tests
# carry no roadmap id, so their failures ALWAYS count — expected-red semantics must never let
# this one go quietly amber.
#
# fails-against: relay/scripts/death-record.sh absent, non-executable, or built so that ANY of
#   the following holds —
#     * a HEALTHY unit (dispatch -> integrate) produces a death record (the negative control:
#       a false positive on a post-mortem tool destroys the credibility that makes anyone read
#       it, id:4347);
#     * a NAMED pre-dispatch refusal (a guard-signature handback) is not classed
#       `dispatch-refused`, or is not marked `dispatched:false` — that conflation is the whole
#       reason `roadmap-archive.sh` keeps being recommended for run-time deaths;
#     * an UNPAIRED terminal (handback, no dispatch event, no recognised guard signature) is
#       read as a refusal instead of `cause-unknown/unpaired-terminal`. Measured on the live
#       log 2026-08-21 (run relay-20260821-174757-32436): two such units existed and one
#       carried a FULL CHILD REPORT, so absence-of-dispatch does not mean nothing ran, and
#       calling it a refusal declares "no work was lost" over recoverable work;
#     * a run-time death (dispatch THEN the null-report terminal-failure handback) is not
#       classed `runtime-death`;
#     * the `no merged= line` signature is silently attributed to a cause instead of recorded
#       as `cause-unknown` (id:f5d9(b): classifier block vs dispatch failure vs mute integrator
#       are indistinguishable today and must not be guessed);
#     * a dispatch with no terminal event at all is not `cause-unknown/no-terminal-event`;
#     * a completed child handback is miscounted as a death;
#     * the salvage signal misses uncommitted worktree files or unmerged branch commits, or
#       reports `recoverable:false` for a probe that could NOT run (unknown must never render
#       as clean);
#     * `record` is not idempotent, or writes the store by any path other than
#       relay-state-write.sh's flock'd `event-append`;
#     * misuse (unknown subcommand, missing event log) exits 0.
#
# Hermetic: everything lives in one mktemp -d. HOME, RELAY_TOML, RELAY_EVENTS_PATH,
# FABLES_CONFIG, RELAY_DEATH_RECORD_PATH, RELAY_WORKTREE_BASE and DEATH_RECORD_LOG are all
# overridden, so the real ~/.claude, the real ~/.config/relay and the real repos are never
# touched. Git is used only on repos created inside the temp dir; no network, no remote.
# fails-against-rev: 9f906d290cf1 -- Makefile relay/scripts/death-record.sh
# fails-against-assertion: death-record.sh not found at

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/death-record.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "death-record.sh not found at $SH"
[[ -x "$SH" ]] || fail "death-record.sh not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

REPOS="$tmp/src"
WT="$tmp/worktrees"
CFG="$tmp/config"
mkdir -p "$REPOS" "$WT" "$CFG"

RUN="run-A"

# ---------------------------------------------------------------------------------------
# Fixture repos. `dead` carries salvageable work; `mute` is a clean checkout; `gone` is
# registered in relay.toml but its path does NOT exist (the probe-cannot-run control).
# ---------------------------------------------------------------------------------------
mkgit() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name tester
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit -qm init
}

mkgit "$REPOS/dead"
mkgit "$REPOS/mute"
mkgit "$REPOS/healthy"
mkgit "$REPOS/refused"
mkgit "$REPOS/handedback"
mkgit "$REPOS/unpaired"

# `unpaired`: a child that RAN (it filed a full report) but has NO dispatch event in the log.
# Its worktree holds uncommitted work — so misreading it as a pre-dispatch refusal would
# declare "no work was lost" over recoverable work.
UNP_WT="$WT/unpaired/$RUN-handoff-0"
mkdir -p "$WT/unpaired"
git -C "$REPOS/unpaired" worktree add -q --detach "$UNP_WT" >/dev/null
printf 'unsaved child work\n' > "$UNP_WT/scratch.txt"

# `dead`: a child worktree on relay/<runId>-… with TWO unmerged commits AND an uncommitted file.
DEAD_WT="$WT/dead/$RUN-execute-4f9b-0"
mkdir -p "$WT/dead"
git -C "$REPOS/dead" worktree add -q -b "relay/$RUN-execute-4f9b-0" "$DEAD_WT" >/dev/null
printf 'work 1\n' > "$DEAD_WT/a.txt"
git -C "$DEAD_WT" add -A && git -C "$DEAD_WT" commit -qm "child commit 1"
printf 'work 2\n' > "$DEAD_WT/b.txt"
git -C "$DEAD_WT" add -A && git -C "$DEAD_WT" commit -qm "child commit 2"
printf 'unsaved\n' > "$DEAD_WT/uncommitted.txt"     # untracked -> `??` in --porcelain

# `mute`: a worktree that exists and is entirely clean, on no relay branch.
MUTE_WT="$WT/mute/$RUN-review-0"
mkdir -p "$WT/mute"
git -C "$REPOS/mute" worktree add -q --detach "$MUTE_WT" >/dev/null

TOML="$tmp/relay.toml"
{
  for r in dead mute healthy refused handedback unpaired; do
    printf '[repos.%s]\nclassification = "own"\npath = "%s/%s"\n\n' "$r" "$REPOS" "$r"
  done
  # registered but MISSING on disk — the salvage probe must report UNKNOWN, never clean
  printf '[repos.gone]\nclassification = "own"\npath = "%s/gone-nowhere"\n\n' "$REPOS"
} > "$TOML"

# ---------------------------------------------------------------------------------------
# Fixture event log. The signatures are the EXACT strings relay-loop.js emits.
# ---------------------------------------------------------------------------------------
EV="$tmp/events.jsonl"
cat > "$EV" <<EOF
{"ts":"2026-08-21T10:00:00Z","runId":"$RUN","kind":"verdict","repo":"healthy","verdict":"execute","reason":"actionable"}
{"ts":"2026-08-21T10:01:00Z","runId":"$RUN","kind":"dispatch","repo":"healthy","mode":"execute","round":1,"tier":"sonnet","item":"aaaa"}
{"ts":"2026-08-21T10:02:00Z","runId":"$RUN","kind":"integrate","repo":"healthy","mode":"execute","ckpt":"relay-ckpt-x","push":"ok","ids":["aaaa"]}
{"ts":"2026-08-21T10:03:00Z","runId":"$RUN","kind":"handback","repo":"refused","mode":"execute","reason":"prompt-size gate (id:4f9b/id:b018): NOT dispatched — the assembled execute prompt for refused is ~131000 tok, over the 100000 tok dispatch budget. REMEDY: run roadmap-archive.sh. This repo is skipped, not failed: no worktree was created and no work was lost."}
{"ts":"2026-08-21T10:04:00Z","runId":"$RUN","kind":"dispatch","repo":"dead","mode":"execute","round":1,"tier":"sonnet","item":"4f9b"}
{"ts":"2026-08-21T10:05:00Z","runId":"$RUN","kind":"handback","repo":"dead","mode":"execute","reason":"child agent failed/skipped (API error or terminal failure); no auto-resume for execute. Any committed checkpoints are retired force-free (id:4df8/373e)."}
{"ts":"2026-08-21T10:06:00Z","runId":"$RUN","kind":"dispatch","repo":"mute","mode":"review","round":1,"tier":"opus","item":"bbbb"}
{"ts":"2026-08-21T10:07:00Z","runId":"$RUN","kind":"handback","repo":"mute","mode":"review","reason":"integrate.sh produced no merged= line (unparseable integrator output): "}
{"ts":"2026-08-21T10:08:00Z","runId":"$RUN","kind":"dispatch","repo":"handedback","mode":"handoff","round":1,"tier":"opus","item":"cccc"}
{"ts":"2026-08-21T10:09:00Z","runId":"$RUN","kind":"handback","repo":"handedback","mode":"handoff","reason":"contract_met=false — the slice lacked the acceptance criteria; no commit made; worktree clean."}
{"ts":"2026-08-21T10:10:00Z","runId":"$RUN","kind":"dispatch","repo":"gone","mode":"execute","round":2,"tier":"sonnet","item":"dddd"}
{"ts":"2026-08-21T10:11:00Z","runId":"$RUN","kind":"handback","repo":"unpaired","mode":"handoff","reason":"contract_met=false — the classifier's promote is already shipped; no commit made. (A FULL CHILD REPORT: this child demonstrably RAN, yet no dispatch event exists for it — observed live in run relay-20260821-174757-32436 on 2026-08-21.)"}
EOF

env_run() {
  HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$EV" \
  FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$CFG/relay-deaths.jsonl" \
  RELAY_WORKTREE_BASE="$WT" DEATH_RECORD_LOG="$tmp/death-record.log" \
  "$SH" "$@"
}

# ---------------------------------------------------------------------------------------
# 1. scan --json: every cause class distinguished; the healthy unit produces NO record.
# ---------------------------------------------------------------------------------------
JSON="$tmp/scan.jsonl"
env_run scan "$RUN" --json > "$JSON" || fail "scan exited nonzero"

python3 - "$JSON" <<'PYEOF' || exit 1
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by_repo = {r["repo"]: r for r in recs}
ok = True
def check(cond, msg):
    global ok
    if not cond:
        print("FAIL: " + msg); ok = False

check("healthy" not in by_repo,
      "NEGATIVE CONTROL: a healthy dispatch->integrate unit produced a death record: %s"
      % by_repo.get("healthy"))
check(len(recs) == 6, "expected exactly 6 records (6 non-healthy units), got %d: %s"
      % (len(recs), [r["repo"] for r in recs]))

# THE HARDENED RULE. A terminal handback with no dispatch event is NOT evidence of a
# refusal — measured on the live log 2026-08-21, where such a unit carried a full child
# report. It must read UNKNOWN and be salvage-probed, never "no work was lost".
r = by_repo.get("unpaired")
check(r is not None, "no record for the unpaired terminal handback")
if r:
    check(r["cause"] == "cause-unknown" and r["cause_detail"] == "unpaired-terminal",
          "an unpaired terminal with no guard signature classed %s/%s — reading absence of a "
          "dispatch event as a refusal declares 'no work was lost' over recoverable work"
          % (r["cause"], r["cause_detail"]))
    check(r["pairing"] == "terminal-without-dispatch",
          "the structural fact must be recorded separately from the cause, got %r"
          % r.get("pairing"))
    check(r["salvage"]["recoverable"] is True,
          "SALVAGE: an unpaired terminal must still be probed; its worktree holds "
          "uncommitted work but recoverable=%r" % r["salvage"]["recoverable"])

r = by_repo.get("refused")
check(r is not None, "no record for the pre-dispatch refusal")
if r:
    check(r["cause"] == "dispatch-refused", "refusal classed %r, want dispatch-refused" % r["cause"])
    check(r["cause_detail"] == "prompt-size-gate",
          "refusal detail %r, want prompt-size-gate" % r["cause_detail"])
    check(r["dispatched"] is False, "refusal must be dispatched:false")
    check(r["pairing"] == "terminal-without-dispatch", "refusal pairing %r" % r.get("pairing"))
    check(r["salvage"]["recoverable"] is None and not r["salvage"]["probed"],
          "a refusal loses no work; it must not be salvage-probed")

r = by_repo.get("dead")
check(r is not None, "no record for the run-time death")
if r:
    check(r["cause"] == "runtime-death", "death classed %r, want runtime-death" % r["cause"])
    check(r["dispatched"] is True, "a run-time death must be dispatched:true")
    check(r["item"] == "4f9b", "the dispatched item must ride along, got %r" % r["item"])
    sv = r["salvage"]
    check(sv["probed"] is True, "the run-time death must be salvage-probed")
    check(sv["recoverable"] is True, "SALVAGE: dead child's worktree holds work but recoverable=%r"
          % sv["recoverable"])
    check(any(w["dirty_files"] >= 1 for w in sv["worktrees"]),
          "SALVAGE: uncommitted worktree file not detected: %s" % sv["worktrees"])
    check(any(b["unmerged_commits"] == 2 for b in sv["branches"]),
          "SALVAGE: 2 unmerged commits not detected: %s" % sv["branches"])

r = by_repo.get("mute")
check(r is not None, "no record for the mute integrator")
if r:
    check(r["cause"] == "cause-unknown",
          "the `no merged= line` signature must be cause-unknown, got %r" % r["cause"])
    check(r["cause_detail"] == "no-merged-line",
          "mute-integrator detail %r, want no-merged-line" % r["cause_detail"])
    check("f5d9" in r["cause_meaning"],
          "cause-unknown must cite id:f5d9(b) rather than guess a cause")
    check(r["salvage"]["recoverable"] is False,
          "a clean worktree with no relay branch must read recoverable:false, got %r"
          % r["salvage"]["recoverable"])

r = by_repo.get("handedback")
check(r is not None, "no record for the completed child handback")
if r:
    check(r["cause"] == "child-handback",
          "a completed handback classed %r, want child-handback" % r["cause"])

r = by_repo.get("gone")
check(r is not None, "no record for the dispatch with no terminal event")
if r:
    check(r["cause"] == "cause-unknown" and r["cause_detail"] == "no-terminal-event",
          "dispatch-with-no-terminal classed %s/%s" % (r["cause"], r["cause_detail"]))
    sv = r["salvage"]
    check(sv["recoverable"] is None,
          "FAIL-OPEN: a probe that could not run must report recoverable:null, got %r"
          % sv["recoverable"])
    check(sv["error"], "a probe that could not run must say why")

sys.exit(0 if ok else 1)
PYEOF
pass "scan distinguishes all four cause classes and emits NO record for the healthy unit"

# ---------------------------------------------------------------------------------------
# 2. The text report names the salvageable child loudly.
# ---------------------------------------------------------------------------------------
TXT="$(env_run scan "$RUN")" || fail "text scan exited nonzero"
grep -q 'SALVAGEABLE' <<<"$TXT" || fail "text report must mark the salvageable death:\n$TXT"
grep -q 'uncommitted: 1 file' <<<"$TXT" || fail "text report must name the uncommitted count:\n$TXT"
grep -q 'unmerged:    2 commit' <<<"$TXT" || fail "text report must name the unmerged count:\n$TXT"
grep -q 'runtime-death' <<<"$TXT" || fail "text report must name the cause class:\n$TXT"
pass "text report surfaces the salvage signal and the cause class"

# ---------------------------------------------------------------------------------------
# 3. record: writes through relay-state-write.sh, and is idempotent.
# ---------------------------------------------------------------------------------------
STORE="$CFG/relay-deaths.jsonl"
[[ -e "$STORE" ]] && fail "store must not exist before the first record"

SPY="$tmp/state-write-spy.sh"
cat > "$SPY" <<SPY_EOF
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "$tmp/spy.log"
exec "$ROOT/relay/scripts/relay-state-write.sh" "\$@"
SPY_EOF
chmod +x "$SPY"

out="$(HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$EV" \
       FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$STORE" RELAY_WORKTREE_BASE="$WT" \
       DEATH_RECORD_LOG="$tmp/death-record.log" RELAY_STATE_WRITE="$SPY" \
       "$SH" record "$RUN")" || fail "record exited nonzero"
grep -q 'appended 6' <<<"$out" || fail "record must append 6 records, said:\n$out"
[[ -f "$STORE" ]] || fail "record did not create the store"
grep -q "event-append $STORE" "$tmp/spy.log" \
  || fail "the store must be written ONLY via relay-state-write.sh event-append (flock'd)"

n1="$(grep -c '' "$STORE")"
out2="$(HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$EV" \
        FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$STORE" RELAY_WORKTREE_BASE="$WT" \
        DEATH_RECORD_LOG="$tmp/death-record.log" RELAY_STATE_WRITE="$SPY" \
        "$SH" record "$RUN")" || fail "second record exited nonzero"
grep -q '0 new record' <<<"$out2" || fail "record must be idempotent, second run said:\n$out2"
n2="$(grep -c '' "$STORE")"
[[ "$n1" == "$n2" ]] || fail "record duplicated entries: $n1 -> $n2"
pass "record appends via the flock'd primitive and is idempotent"

# ---------------------------------------------------------------------------------------
# 4. list filters the store; every stored record round-trips as JSON.
# ---------------------------------------------------------------------------------------
lst="$(env_run list --cause runtime-death)" || fail "list exited nonzero"
python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]' <<<"$lst" \
  || fail "list output is not JSONL"
grep -q '"repo": *"dead"' <<<"$lst" || fail "list --cause runtime-death must return the dead child:\n$lst"
grep -q 'handedback' <<<"$lst" && fail "list --cause must not leak other classes:\n$lst"
pass "list filters the store by cause"

# ---------------------------------------------------------------------------------------
# 5. Misuse is LOUD. A post-mortem tool that reports "nothing died" when it could not read
#    its input is worse than no tool.
# ---------------------------------------------------------------------------------------
set +e
env_run bogus-subcommand >/dev/null 2>&1; rc_sub=$?
HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$tmp/absent.jsonl" \
  FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$STORE" RELAY_WORKTREE_BASE="$WT" \
  DEATH_RECORD_LOG="$tmp/death-record.log" "$SH" scan >/dev/null 2>&1; rc_ev=$?
env_run scan --nonsense-flag >/dev/null 2>&1; rc_flag=$?
set -e
[[ "$rc_sub"  -eq 2 ]] || fail "unknown subcommand must exit 2, got $rc_sub"
[[ "$rc_ev"   -ne 0 ]] || fail "a missing event log must exit nonzero, got $rc_ev"
[[ "$rc_flag" -eq 2 ]] || fail "an unknown flag must exit 2, got $rc_flag"
pass "misuse exits loudly"

# ---------------------------------------------------------------------------------------
# 6. A run with ONLY healthy units yields no records at all (the whole-run negative control).
# ---------------------------------------------------------------------------------------
EV2="$tmp/events-clean.jsonl"
cat > "$EV2" <<EOF
{"ts":"2026-08-21T11:00:00Z","runId":"run-B","kind":"dispatch","repo":"healthy","mode":"execute","round":1,"tier":"sonnet","item":"eeee"}
{"ts":"2026-08-21T11:01:00Z","runId":"run-B","kind":"integrate","repo":"healthy","mode":"execute","ckpt":"c","push":"ok","ids":["eeee"]}
EOF
clean="$(HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$EV2" \
         FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$tmp/store2.jsonl" \
         RELAY_WORKTREE_BASE="$WT" DEATH_RECORD_LOG="$tmp/death-record.log" \
         "$SH" scan latest)" || fail "clean-run scan exited nonzero"
grep -q 'no death records' <<<"$clean" || fail "a fully healthy run must report no records:\n$clean"
pass "NEGATIVE CONTROL: a fully healthy run produces zero death records"

# ---------------------------------------------------------------------------------------
# 7. A malformed event line is skipped loudly (stderr) and never crashes the scan.
# ---------------------------------------------------------------------------------------
EV3="$tmp/events-bad.jsonl"
cat "$EV" > "$EV3"
printf 'this is not json\n' >> "$EV3"
err="$tmp/bad.err"
HOME="$tmp" SRC_DIR="$REPOS" RELAY_TOML="$TOML" RELAY_EVENTS_PATH="$EV3" \
  FABLES_CONFIG="$CFG" RELAY_DEATH_RECORD_PATH="$tmp/store3.jsonl" \
  RELAY_WORKTREE_BASE="$WT" DEATH_RECORD_LOG="$tmp/death-record.log" \
  "$SH" scan "$RUN" --json > "$tmp/bad.jsonl" 2>"$err" || fail "a malformed line must not crash the scan"
grep -q 'malformed event line' "$err" || fail "a malformed event line must be reported on stderr"
[[ "$(grep -c '' "$tmp/bad.jsonl")" == "6" ]] || fail "malformed lines must not change the record set"
pass "a malformed event line is skipped LOUDLY, never silently"

echo "ALL TESTS PASSED"
