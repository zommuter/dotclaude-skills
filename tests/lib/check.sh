#!/usr/bin/env bash
# tests/lib/check.sh — shared assert-vs-error helper (id:735f / id:4983).
#
# `check <cmd> [args...]` runs a command and distinguishes:
#   exit 0     -> the assertion holds; return 0.
#   exit 1     -> a FALSE assertion; print a line-leading `FAIL:` naming the command,
#                 return 1.
#   exit >= 2  -> the check COULD NOT RUN (e.g. grep's exit 2 for a missing/unreadable
#                 file, a permission problem, a failed fork under load); print a
#                 line-leading `ERROR:` naming the command and its exit status,
#                 return 3.
#
# Exists because `grep -q ... || fail` (and its ~360 test-file variants) conflates
# "the assertion is false" with "the check could not execute" — both are non-zero, both
# take the same `|| fail` branch, so a transient subprocess failure under load reports
# as a false assertion about a property that is actually fine. See
# docs/ledger-notes/735f.md for the incident this fixes.
#
# A caller that wants run-tests.sh to distinguish an execution error from a failed
# assertion at the FILE level should `exit 3` when `check` returns 3 (e.g.
# `check grep -q foo bar || exit $?`) — run-tests.sh treats a test file's exit status 3
# as ERROR, never as EXPECTED-RED, independent of whether its roadmap item is open.
#
# NOT a retry: `check` runs its command exactly once. Retrying a flaky check would hide
# exactly the signal this helper exists to preserve.

check() {
  local rc
  "$@"
  rc=$?
  if (( rc == 0 )); then
    return 0
  elif (( rc == 1 )); then
    echo "FAIL: $*"
    return 1
  else
    echo "ERROR: $* (exit status $rc)"
    return 3
  fi
}
