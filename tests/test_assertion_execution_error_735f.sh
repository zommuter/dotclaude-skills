#!/usr/bin/env bash
# roadmap:735f
#
# RED SPEC for ROADMAP id:735f -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# THE DEFECT. A test that ends an assertion with `|| fail` cannot distinguish "the
# assertion is FALSE" from "the check COULD NOT RUN". `grep` exits 1 for no-match and 2
# for an ERROR -- a missing file, a permission problem, a failed fork under load. Both are
# non-zero, both take the `|| fail` branch, and both report as a failed assertion naming a
# property that is actually fine. 360 test files use `|| fail` after a grep.
#
# WHY IT IS WORTH AN ITEM. Two tests flaked green-standalone / red-in-suite on 2026-09-04
# (`test_privacy_gate_prepush.sh`, `test_verdict_event_c7dc.sh`), on a machine that has run
# at load average up to 29 with 30 registered worktrees, and neither is explained. A false
# red is cheaper than a false green but it is not free: it is what trains an operator to
# re-run until green, and the re-run habit is what makes a true red invisible. This item
# does NOT claim to have found the mechanism behind those two flakes; it fixes the property
# that made them unreadable.
#
# A HYPOTHESIS ALREADY TESTED AND REFUTED, recorded so nobody re-derives it: the
# `printf | grep -q` SIGPIPE-under-pipefail shape (id:81d5) does NOT explain them.
# `tests/test_pipefail_sigpipe_lint.sh` reports the repo free of the banned shape with zero
# exemptions, and a 10-iteration reproduction of the exact pipeline passed 10/10.
#
# THE INTERFACE THIS SPEC PINS, chosen here so 360 sites converge on ONE definition
# (id:4983) rather than 360 edits:
#
#   * `tests/lib/check.sh` is sourceable and defines `check <cmd> [args...]`. It runs the
#     command and branches on its status: 0 -> return 0; 1 -> a FALSE assertion, print a
#     line-leading `FAIL:` and return 1; >= 2 -> the check COULD NOT RUN, print a
#     line-leading `ERROR:` naming the command AND its exit status, and return 3.
#   * A test file exiting 3 is an EXECUTION ERROR. `tests/run-tests.sh` reports it
#     `ERROR  <name>`, counts it in a distinct `errored` summary field, lists it under an
#     `errored:` line, and fails the suite. It is never granted EXPECTED-RED: redness-is-
#     the-spec is a claim about assertions, not about a check that could not run.
#
# NO BLANKET RETRY. Retrying a flaky check hides exactly the signal this item exists to
# preserve. Case (E) pins that the runner executes each file once.
#
# Drives the REAL tests/run-tests.sh against a throwaway git repo; the live repo is only
# read. Hermetic: everything happens under mktemp, no network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TESTS="$SRC_DIR/tests/run-tests.sh"
CHECK_LIB="$SRC_DIR/tests/lib/check.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$RUN_TESTS" ]] || fail "setup: run-tests.sh not found at $RUN_TESTS"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# =====================================================================================
# (A) THE SHARED HELPER EXISTS
# =====================================================================================
[[ -f "$CHECK_LIB" ]] || \
  fail "(A) tests/lib/check.sh does not exist -- 360 sites want ONE definition of the assert-vs-error branch, not 360 edits (id:4983)"
pass "(A) the shared check helper exists"

# =====================================================================================
# (B) A CHECK THAT COULD NOT RUN IS AN ERROR, NAMING THE COMMAND AND ITS STATUS
# =====================================================================================
UNREADABLE="$TMP/no-such-dir/no-such-file"
probe="$TMP/probe_error.sh"
cat >"$probe" <<EOF
#!/usr/bin/env bash
set -uo pipefail
source "$CHECK_LIB"
check grep -q 'anything' "$UNREADABLE"
echo "helper-returned:\$?"
EOF
out="$(bash "$probe" 2>&1)"; rc_probe=$?
grep -qE '^ERROR:' <<<"$out" || \
  fail "(B) a grep that could not execute did not produce a line-leading ERROR: -- exit 2 was reported as a failed assertion, which is the whole defect. Got: $out"
grep -qF 'grep' <<<"$out" || fail "(B2) the ERROR line does not name the command that failed: $out"
grep -qE 'ERROR:.*(exit|status)[^0-9]*[2-9]' <<<"$out" || \
  fail "(B3) the ERROR line does not report the command's exit status: $out"
grep -qF 'helper-returned:3' <<<"$out" || \
  fail "(B4) check() must return 3 for a could-not-run check so the file's exit status carries the distinction: $out"
pass "(B) a check that could not run reports ERROR with the command and its status"

# =====================================================================================
# (C) A GENUINELY FALSE ASSERTION IS STILL A FAILURE, NOT AN ERROR
# =====================================================================================
present="$TMP/present.txt"; echo "some other text" >"$present"
probe2="$TMP/probe_false.sh"
cat >"$probe2" <<EOF
#!/usr/bin/env bash
set -uo pipefail
source "$CHECK_LIB"
check grep -q 'absent-token' "$present"
echo "helper-returned:\$?"
EOF
out2="$(bash "$probe2" 2>&1)"
grep -qE '^ERROR:' <<<"$out2" && \
  fail "(C) a genuinely false assertion (grep exit 1) was reported as an execution ERROR -- the two must not collapse in the other direction: $out2"
grep -qE '^FAIL:' <<<"$out2" || fail "(C2) a false assertion did not produce a line-leading FAIL: $out2"
grep -qF 'helper-returned:1' <<<"$out2" || \
  fail "(C3) check() must return 1 for a false assertion, distinct from 3: $out2"
pass "(C) a false assertion is still reported as a failure"

# =====================================================================================
# (D) THE RUNNER SHOWS THE DISTINCTION IN ITS SUMMARY
# =====================================================================================
REPO="$TMP/scratch-repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t
echo base >"$REPO/f"; git -C "$REPO" add -A; git -C "$REPO" commit -qm base
mkdir -p "$REPO/tests"

COUNTER="$TMP/runs.count"; : >"$COUNTER"
cat >"$REPO/tests/test_errored_fixture.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
echo "x" >> "$COUNTER"
echo "ERROR: grep could not run (exit 2) -- intentional fixture for the 735f spec"
exit 3
EOF
cat >"$REPO/tests/test_false_fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "FAIL: an assertion that is genuinely false -- intentional fixture for the 735f spec"
exit 1
EOF
chmod +x "$REPO/tests/test_errored_fixture.sh" "$REPO/tests/test_false_fixture.sh"

rc=0
out3="$(cd "$REPO" && bash "$RUN_TESTS" \
        "$REPO/tests/test_errored_fixture.sh" "$REPO/tests/test_false_fixture.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(D) the runner exited 0 with an errored and a failed test: $out3"
grep -qE '^ERROR +test_errored_fixture\.sh' <<<"$out3" || \
  fail "(D2) the runner did not report the errored file as ERROR: $out3"
grep -qE '^FAIL +test_false_fixture\.sh' <<<"$out3" || \
  fail "(D3) the runner no longer reports a genuinely failed file as FAIL: $out3"
grep -qE '^summary:.*1 errored' <<<"$out3" || \
  fail "(D4) the summary line does not carry a distinct errored count -- the distinction must be visible in the summary, not only by opening the log: $out3"
grep -qE '^summary:.*1 failed' <<<"$out3" || \
  fail "(D5) the summary line lost its failed count: $out3"
pass "(D) the runner separates execution errors from false assertions in its summary"

# =====================================================================================
# (E) NO BLANKET RETRY
# =====================================================================================
runs="$(wc -l <"$COUNTER" | tr -d ' ')"
[[ "$runs" == "1" ]] || \
  fail "(E) the errored fixture was executed $runs times -- a blanket retry hides exactly the signal this item exists to preserve"
pass "(E) each test file is executed once"

echo "ALL PASS: id:735f a check that could not run is distinguishable from a false assertion"
