#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:b54b is a TODO item, not a ROADMAP item, so per
# tests/run-tests.sh's own convention this file's failures are NEVER expected-red.
#
# id:b54b's standing detector: relay/scripts/fixture-branch-leak-scan.sh flags a `relay/*`
# ref in an own repo whose commit is reachable from no run id — the cheap, observe-only
# check the TODO item names as the durable defense against another `relay/ok`-shaped
# fixture leak going unnoticed. Hermetic: everything happens inside `mktemp -d`.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$SRC_DIR/relay/scripts/fixture-branch-leak-scan.sh"
[[ -x "$SCAN" ]] || { echo "FAIL: fixture-branch-leak-scan.sh not found/executable at $SCAN"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t
echo base >"$REPO/f"
git -C "$REPO" add -A
git -C "$REPO" commit -qm base

# =====================================================================================
# (A) a shape-anomaly branch (no runId component at all, e.g. the real relay/ok leak)
#     is flagged.
# =====================================================================================
git -C "$REPO" branch relay/ok
out="$("$SCAN" "$REPO")" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "(A) exit code should be 1 when a suspect branch exists, got $rc: $out"
grep -qE '^relay/ok\s' <<<"$out" || fail "(A) relay/ok not reported: $out"
grep -q 'shape-anomaly' <<<"$out" || fail "(A) relay/ok not flagged shape-anomaly: $out"
pass "(A) a shape-anomaly branch (relay/ok — no runId component) is flagged"
git -C "$REPO" branch -D relay/ok >/dev/null

# =====================================================================================
# (B) a run-scoped branch whose runId IS recorded in RELAY_LOG.md is NOT flagged.
# =====================================================================================
RUNID="relay-20260827-102629-23445"
git -C "$REPO" branch "relay/${RUNID}-execute-5eeb-0"
printf '# Relay Log\n\nrun %s completed.\n' "$RUNID" >"$REPO/RELAY_LOG.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "add relay log"
out="$("$SCAN" "$REPO")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "(B) a legit run-scoped branch with a recorded runId was flagged: $out"
[[ -z "$out" ]] || fail "(B) expected no output for a clean repo, got: $out"
pass "(B) a run-scoped branch whose runId IS in RELAY_LOG.md is not flagged"
git -C "$REPO" branch -D "relay/${RUNID}-execute-5eeb-0" >/dev/null

# =====================================================================================
# (C) a run-scoped-SHAPED branch whose runId is NOT in RELAY_LOG.md (reachable from no
#     run) is flagged as unknown-runid — the id:b54b item's exact phrasing.
# =====================================================================================
UNKNOWN_RUNID="relay-19700101-000000-1"
git -C "$REPO" branch "relay/${UNKNOWN_RUNID}-execute-ghost-0"
out="$("$SCAN" "$REPO")" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "(C) exit code should be 1 for an unknown-runid branch, got $rc: $out"
grep -q "unknown-runid:$UNKNOWN_RUNID" <<<"$out" || fail "(C) branch with an unrecorded runId not flagged unknown-runid: $out"
pass "(C) a run-scoped-shaped branch whose runId is reachable from no run is flagged unknown-runid"
git -C "$REPO" branch -D "relay/${UNKNOWN_RUNID}-execute-ghost-0" >/dev/null

# =====================================================================================
# (D) the deliberately-parked relay/orphan/* namespace is excluded — a parked orphan is
#     a working feature (relay-reconcile.sh), not a leak.
# =====================================================================================
git -C "$REPO" branch relay/orphan/some-parked-work-0
out="$("$SCAN" "$REPO")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "(D) a relay/orphan/* branch should never be flagged: $out"
[[ -z "$out" ]] || fail "(D) expected no output, got: $out"
pass "(D) relay/orphan/* is excluded (a deliberately-parked branch, not a leak)"

echo "ALL PASS: id:b54b fixture-branch-leak-scan.sh"
