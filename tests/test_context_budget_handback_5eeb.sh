#!/usr/bin/env bash
# roadmap:5eeb
#
# id:5eeb — RED SPEC for the MID-RUN context-budget check that triggers a clean
# CHECKPOINT-AND-HANDBACK before an executor dies of `Prompt is too long`.
#
# WHY (measured, run `relay-20260826-162405-7522`, two loderite executors):
# both died with the verbatim API error `Prompt is too long`, orphaning partial
# work onto `relay/orphan/…-execute-5adb-0` and `…-execute-repo-0` and
# SUPPRESSING re-dispatch of those items until a human ran `/relay reconcile`.
# The cause was pure ACCUMULATION, not an oversized dispatch: initial prompts
# were 8,275 B and 6,359 B; final transcripts 428,151 B and 477,574 B over
# 166 / 193 turns; growth LINEAR (~100 KB by line 24/30, ~400 KB by line
# 152/150) with no single line above ~5% of its transcript.
#
# NOT id:35b7 / id:4f9b. The dispatch-time prompt-size gate sized CORRECTLY
# here (the 5adb unit even consumed its id:e68f ledger slice as designed) and
# must NOT be changed by this item — mid-run growth is structurally invisible
# to any dispatch-time gate.
#
# BYTE-ATTRIBUTED breakdown of both dead transcripts (measured 2026-08-26).
# This CORRECTS a first-pass diagnosis that blamed streamed build/test output;
# that reading is REFUTED and must not be restored:
#
#   bucket                          execute-5adb   execute-repo
#   build/test output                      3.3%           1.5%
#   code navigation (total)               14.5%          11.9%
#     ...of which grep-style lookup        2.5%           2.7%
#   docs / ledgers / relay brief          18.3%          23.0%
#   git plumbing                           0.4%           0.2%
#
# Build/test output is the SMALLEST named bucket — several invocations already
# redirect to a file and only `tail` it.
#
# THE STANDOUT IS STRUCTURAL, and it is what this spec designs against: both
# units burned the overwhelming majority of their budget INVESTIGATING BEFORE
# THEIR FIRST PRODUCTIVE EDIT. execute-5adb's first Edit came at line 99, after
# 282,716 B = 63.9% of the whole transcript; execute-repo's at line 133, after
# 379,317 B = 76.8%. Two-thirds to three-quarters of the window was gone before
# one line changed — which is why assertion (8) below requires the contract to
# name the investigate→edit boundary as an explicit check point, not just a
# periodic one.
#
# OWNER'S RECORDED JUDGEMENT on the TODO item, strengthened by the attribution:
# of candidates (a) redirect build/test output to a file and read back
# `tail -N`, (b) cap/truncate large `tool_result` payloads, (c) a mid-run
# budget check → checkpoint-and-handback, **(c) is the highest-value half** —
# dying costs a human `/relay reconcile` per orphan AND blocks re-dispatch,
# whereas an early handback costs nothing and keeps the work in the normal
# flow. (a) is measured at ~2% here and is DEMOTED to a note; (a) and (b) stay
# open on the TODO item and are OUT OF SCOPE here. So is the fixed ~32 KB
# brief cost (executor-contract.md + conventions.md read once per unit) — that
# is a different mechanism and overlaps id:9eb7.
#
# THRESHOLD CALIBRATION — deliberately NOT derived from the 200k window.
# Transcript bytes are a PROXY that UNDER-counts true context: the system
# prompt, tool definitions, skill payloads and CLAUDE.md all occupy the context
# window but never appear in the transcript. So the defaults are calibrated on
# the two OBSERVED deaths instead — handback at 300,000 B (~70% of the smaller
# one), warn at 200,000 B. That is the OPPOSITE derivation direction from
# `prompt-size-gate.mjs` (window-fraction), which is why it is spelled out.
# `est_tokens` (bytes/4) is REPORTING ONLY and must not be what the thresholds
# compare against — see id:9eb7's measured 2.66 chars/tok for dense relay
# markdown.
#
# TRIANGULATION (id:108e): the verdict assertions use SEVERAL distinct byte
# counts including both real death sizes, both threshold boundaries, and an
# override pair — special-casing them is harder than implementing the
# comparison.
#
# HONEST LIMIT (also stated on the ROADMAP item): the contract half below is a
# STATIC grep over contract TEXT. It proves the contract CARRIES the rule and
# that the versioned markers agree; it CANNOT prove a Sonnet child's behaviour
# changes — same limit as id:6f1c / id:9eb7. The script half IS behaviourally
# tested.
#
# Hermetic: fixtures live in `mktemp -d`; reads two repo source files
# read-only; never touches ~/.claude, ~/.config/relay, or the network.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/context-budget.sh"
CONTRACT="$SRC_DIR/relay/references/executor-contract.md"
CLAUDE_MD="$SRC_DIR/CLAUDE.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------- existence
[[ -f "$SCRIPT" ]] \
  || fail "relay/scripts/context-budget.sh not found at $SCRIPT (id:5eeb not built)"
[[ -x "$SCRIPT" ]] \
  || fail "relay/scripts/context-budget.sh is not executable"
[[ -f "$CONTRACT" ]] || fail "executor-contract.md not found at $CONTRACT"
[[ -f "$CLAUDE_MD" ]] || fail "CLAUDE.md not found at $CLAUDE_MD"

# Run the script, capturing stdout, stderr and exit status without letting
# `set -e` kill us. Results land in $OUT / $ERR / $RC.
run_budget() {
  OUT=""; ERR=""; RC=0
  OUT="$("$SCRIPT" "$@" 2>"$tmpdir/stderr")" || RC=$?
  ERR="$(cat "$tmpdir/stderr")"
}

# assert_verdict <expected-verdict> <expected-rc> <label> -- <args...>
assert_verdict() {
  local want="$1" want_rc="$2" label="$3"; shift 3
  [[ "$1" == "--" ]] && shift
  run_budget "$@"
  [[ "$OUT" == *"context-budget: $want"* ]] \
    || fail "$label: expected verdict '$want', got stdout: ${OUT:-<empty>}"
  [[ "$RC" == "$want_rc" ]] \
    || fail "$label: expected exit $want_rc for verdict '$want', got $RC"
}

# ---------------------------------------------------- (1) verdict by byte count
# Triangulated across ok / warn / handback, including both boundaries and both
# REAL observed death sizes.
assert_verdict ok       0 "tiny transcript"            -- --bytes 1000
assert_verdict ok       0 "just under warn"            -- --bytes 199999
assert_verdict warn     0 "at warn boundary"           -- --bytes 200000
assert_verdict warn     0 "between warn and handback"  -- --bytes 250000
assert_verdict handback 3 "at handback boundary"       -- --bytes 300000
assert_verdict handback 3 "real death #1 (428,151 B)"  -- --bytes 428151
assert_verdict handback 3 "real death #2 (477,574 B)"  -- --bytes 477574
pass "verdicts triangulate ok/warn/handback across 7 distinct byte counts incl. both real deaths"

# ------------------------------------------------ (2) exit status is load-bearing
# `handback` MUST be exit 3 (the "you cannot proceed here" code host-gate.sh
# already uses) so a caller can branch on status alone; ok/warn MUST be 0 so a
# routine check never trips `set -e` in an executor's own tooling.
run_budget --bytes 428151
[[ "$RC" == "3" ]] || fail "handback must exit 3 (host-gate.sh convention), got $RC"
run_budget --bytes 250000
[[ "$RC" == "0" ]] || fail "warn must exit 0 (a warning never halts the caller), got $RC"
pass "exit status: handback=3, warn=0"

# ------------------------------------------------ (3) machine-readable one-liner
run_budget --bytes 428151
[[ "$OUT" == *"bytes=428151"* ]] || fail "output must report bytes=428151, got: $OUT"
[[ "$OUT" == *"est_tokens="* ]]  || fail "output must report est_tokens=<T>, got: $OUT"
[[ "$OUT" == *"warn_bytes="* ]]  || fail "output must report the warn_bytes threshold in use, got: $OUT"
[[ "$OUT" == *"handback_bytes="* ]] || fail "output must report the handback_bytes threshold in use, got: $OUT"
line_count="$(printf '%s\n' "$OUT" | wc -l)"
[[ "$line_count" == "1" ]] || fail "stdout must be exactly ONE line, got $line_count lines: $OUT"
# est_tokens is bytes/4 (CHARS_PER_TOKEN, cross-referenced to prompt-size-gate.mjs)
[[ "$OUT" == *"est_tokens=107037"* ]] \
  || fail "est_tokens must be bytes/4 = 107037 for 428151 B (reporting only), got: $OUT"
pass "stdout is one machine-readable line carrying bytes/est_tokens/both thresholds"

# --------------------------------------------------- (4) --transcript measures a file
small="$tmpdir/small.jsonl"
big="$tmpdir/big.jsonl"
head -c 1000 /dev/zero > "$small"
head -c 350000 /dev/zero > "$big"
assert_verdict ok       0 "--transcript on a small file" -- --transcript "$small"
assert_verdict handback 3 "--transcript on a 350 KB file" -- --transcript "$big"
run_budget --transcript "$big"
[[ "$OUT" == *"bytes=350000"* ]] \
  || fail "--transcript must report the file's real byte count, got: $OUT"
pass "--transcript measures the file and yields the same verdicts as --bytes"

# ------------------------------------------------------- (5) thresholds overridable
# Proves the comparison is real and not three hard-coded byte literals.
assert_verdict handback 3 "override: handback below default warn" \
  -- --bytes 1000 --handback-bytes 500
assert_verdict warn 0 "override: warn low, handback high" \
  -- --bytes 1000 --warn-bytes 500 --handback-bytes 100000
assert_verdict ok 0 "override: both raised above a real death size" \
  -- --bytes 428151 --warn-bytes 900000 --handback-bytes 1000000
run_budget --bytes 1000 --warn-bytes 500 --handback-bytes 100000
[[ "$OUT" == *"warn_bytes=500"* && "$OUT" == *"handback_bytes=100000"* ]] \
  || fail "overridden thresholds must be echoed in the output line, got: $OUT"
pass "--warn-bytes / --handback-bytes override the calibrated defaults"

# ---------------------------------------------- (6) fail-open, but LOUD (id:4347)
# A measurement failure must NEVER block an executor's work, and must NEVER be
# silent. Verdict `unknown`, exit 0, non-empty stderr.
assert_verdict unknown 0 "missing transcript" -- --transcript "$tmpdir/does-not-exist.jsonl"
run_budget --transcript "$tmpdir/does-not-exist.jsonl"
[[ -n "$ERR" ]] \
  || fail "a missing transcript must be LOUD on stderr (id:4347 no-silent-swallow), stderr was empty"
unreadable="$tmpdir/unreadable.jsonl"
head -c 400000 /dev/zero > "$unreadable"
chmod 000 "$unreadable"
if [[ -r "$unreadable" ]]; then
  echo "SKIP: running as root — cannot test the unreadable-file branch"
else
  assert_verdict unknown 0 "unreadable transcript" -- --transcript "$unreadable"
fi
chmod 644 "$unreadable"
pass "fail-open on an unmeasurable transcript: verdict unknown, exit 0, loud stderr"

# ------------------------------------------------------------ (7) purity / no writes
# The check runs mid-unit, possibly many times. It must be a read-only decision
# function: no state files, no repo mutation.
before="$(find "$tmpdir" -type f | sort)"
run_budget --transcript "$big"
after="$(find "$tmpdir" -type f | sort)"
[[ "$before" == "$after" ]] \
  || fail "context-budget.sh created or removed files — it must be a pure read-only check"
pass "context-budget.sh is read-only (no files created or removed)"

# ------------------------------------------- (8) the executor contract carries the rule
contract_text="$(cat "$CONTRACT")"
[[ "$contract_text" == *"context-budget.sh"* ]] \
  || fail "executor-contract.md never names context-budget.sh — the mid-run check is not in the contract"
case "$contract_text" in
  *heckpoint*) : ;;
  *) fail "executor-contract.md does not describe a mid-run CHECKPOINT before the wall" ;;
esac
case "$contract_text" in
  *"Prompt is too long"*) : ;;
  *) fail "executor-contract.md does not name the verbatim failure (\`Prompt is too long\`) the rule prevents" ;;
esac
# The disposition matters as much as the trigger: on a handback the executor
# COMMITS the work already done (this is the id:8b1f CUTOFF branch, NOT the
# clean-worktree SIZE-OUT branch of rule 2b), and returns route "none" so the
# item stays plainly re-dispatchable instead of being gated or re-tagged.
case "$contract_text" in
  *'route'*'none'*) : ;;
  *) fail "executor-contract.md does not state the context handback returns route \"none\" (keeps the item re-dispatchable, no handback-followup gating)" ;;
esac
# THE PRE-FIRST-EDIT CHECK POINT — the trigger the 63.9% / 76.8% measurement
# demands. A budget check that only fires periodically still lets a unit spend
# three-quarters of its window investigating before producing anything
# committable; the investigate→edit boundary is where a handback is still cheap
# AND the remaining budget still covers the actual work.
case "$contract_text" in
  *"first edit"*|*"first Edit"*|*"FIRST EDIT"*) : ;;
  *) fail "executor-contract.md does not name the investigate→edit boundary (BEFORE your first edit) as a check point — the 63.9%/76.8% pre-first-edit spend is the measured shape this rule exists to catch" ;;
esac
pass "executor contract carries the mid-run budget rule, both trigger points (periodic + pre-first-edit), and the disposition"

# ------------------------------------- (9) VERSIONED-CONTRACT discipline (v12 → v13)
# executor-contract.md is a versioned surface: a rule change an in-flight
# executor must know about MUST bump the in-file marker AND the CLAUDE.md
# pointer. A contract edit without both is the silent-breakage class the marker
# exists to prevent.
contract_marker="$(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CONTRACT" | awk 'NR==1')"
pointer_marker="$(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CLAUDE_MD" | awk 'NR==1')"
contract_v="$(printf '%s' "$contract_marker" | tr -dc '0-9')"
pointer_v="$(printf '%s' "$pointer_marker" | tr -dc '0-9')"

[[ -n "$contract_v" ]] || fail "no 'contract vN' marker found in executor-contract.md"
[[ -n "$pointer_v" ]]  || fail "no '## Relay contract' vN pointer marker found in CLAUDE.md"
(( contract_v >= 13 )) \
  || fail "executor-contract.md is still at v$contract_v — an id:5eeb rule change MUST bump it to v13 (see its ## Maintenance section)"
[[ "$contract_v" == "$pointer_v" ]] \
  || fail "contract marker v$contract_v disagrees with the CLAUDE.md pointer v$pointer_v — bump discipline broken"
case "$contract_text" in
  *"v12 → v13"*) : ;;
  *) fail "executor-contract.md's ## Maintenance section has no 'v12 → v13' entry recording WHY the bump fired" ;;
esac
pass "contract bumped to v$contract_v, CLAUDE.md pointer agrees, Maintenance records the v12 → v13 rationale"

echo "ALL PASS: mid-run context budget triggers a clean checkpoint-and-handback (id:5eeb)"
