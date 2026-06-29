#!/usr/bin/env bash
# roadmap:672b
#
# id:672b — /meeting acquires ONE advisory repo claim at SETUP for relay-managed
# repos (ROADMAP.md exists), released on every exit path. Reconciled 2026-06-29
# with id:c144: the setup claim REPLACES the old per-write-back acquire; ledger
# write-backs peek-and-warn + flock + atomic commit under the held claim. On an
# EXISTING claim at setup, /meeting INFORMS the user and proceeds as a
# non-conflicting session (NOT abort, NOT worktree-per-meeting, af04); id:2c42 is
# the flock-timeout fallback only. Non-relay repos behave exactly as before.
#
# Content-assertion test against meeting/SKILL.md (mirrors
# tests/test_meeting_c1_executor_contract.sh). RED until SKILL.md documents the
# setup-claim behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"

fail() { echo "FAIL: $1"; exit 1; }

[[ -f "$SKILL" ]] || fail "meeting/SKILL.md not found at $SKILL"

# (a) A setup-time advisory claim ACQUIRE with --mode meeting, gated on a
#     relay-managed repo (ROADMAP.md). Find the acquire line(s) and assert the
#     mode + the setup-time + relay-gate framing live with it.
acq="$(grep -nE 'claim\.sh acquire .*--mode meeting' "$SKILL" || true)"
[[ -n "$acq" ]] || fail "no setup-time 'claim.sh acquire ... --mode meeting' found in SKILL.md"

# The acquire must be described as a SETUP-time claim (not the removed step-2a
# write-back acquire). Require explicit setup framing somewhere in SKILL.md tied
# to the claim.
grep -qiE 'advisory claim at setup|claim at setup|setup.{0,40}advisory claim|advisory.{0,20}claim.{0,40}setup' "$SKILL" \
  || fail "SKILL.md does not document the claim as a SETUP-time advisory claim"

# The setup claim must be gated on a relay-managed repo (ROADMAP.md exists).
grep -qiE 'ROADMAP\.md.{0,80}(exists|relay-managed)|relay-managed.{0,40}ROADMAP\.md' "$SKILL" \
  || fail "setup claim not gated on a relay-managed repo (ROADMAP.md)"

# (b) RELEASE at end-of-meeting on all exit paths.
grep -qE 'claim\.sh release' "$SKILL" || fail "no 'claim.sh release' in SKILL.md"
grep -qiE 'release.{0,80}(end of (the )?meeting|all exit paths|every exit path|on (all|every) exit)' "$SKILL" \
  || fail "SKILL.md does not document releasing the setup claim at end-of-meeting / all exit paths"
# TTL backstop for a missed release path.
grep -qiE 'ttl' "$SKILL" || fail "SKILL.md does not mention the TTL backstop for the setup claim"

# (c) Existing-claim NON-CONFLICTING path: inform user + proceed; NOT abort, NOT
#     worktree-per-meeting.
grep -qiE '(already (claimed|held)|existing claim|live pool).{0,160}(inform|non-conflicting)' "$SKILL" \
  || grep -qiE 'non-conflicting session' "$SKILL" \
  || fail "SKILL.md does not document the existing-claim inform + non-conflicting-session path"
grep -qiE 'NOT worktree-per-meeting|not worktree.per.meeting|af04' "$SKILL" \
  || fail "SKILL.md does not state the non-conflicting path is NOT worktree-per-meeting (af04)"

# (d) c144 reconciliation: write-back proceeds under flock / peek-and-warn;
#     id:2c42 is the flock-TIMEOUT fallback only.
grep -qiE 'c144' "$SKILL" || fail "SKILL.md missing the id:c144 reconciliation reference"
grep -qiE 'peek.and.warn|peek and warn' "$SKILL" || fail "SKILL.md missing peek-and-warn write-back framing"
grep -qiE '2c42.{0,120}(flock.timeout|timeout)|(flock.timeout|timeout).{0,120}2c42' "$SKILL" \
  || fail "SKILL.md does not scope id:2c42 to the flock-timeout fallback only"

# (e) Non-relay repos unaffected: no claim acquired.
grep -qiE 'non-relay repos?.{0,120}(no claim|no ROADMAP\.md|behave|as before|skip)' "$SKILL" \
  || fail "SKILL.md does not state non-relay repos acquire NO setup claim"

echo ok
