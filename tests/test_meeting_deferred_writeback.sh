#!/usr/bin/env bash
# roadmap:2c42 — /meeting deferred ledger write-back: breadcrumb + replay-on-next-invocation
# + log. When step 2a's relay-pool claim is REFUSED, the meeting must persist a replayable
# payload (gitignored) + log the event, and a setup-phase replay check (in /meeting setup and
# /todo-update) must apply pending payloads under a FRESH claim, then clear the drop file.
# Static checks on the meeting SKILL contract (mirrors test_meeting_claim_hold.sh, id:d748).
# Meeting 2026-06-22 (af04): docs/meeting-notes/2026-06-22-2139-meeting-worktree-writeback.md.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MD="$SRC_DIR/meeting/SKILL.md"
TODO_MD="$SRC_DIR/todo-update/SKILL.md"
GITIGNORE="$SRC_DIR/.gitignore"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MD" ]] || fail "meeting/SKILL.md not found"

# (1) On a refused claim (deferral), the meeting persists a replayable breadcrumb payload to a
# gitignored drop path AND logs the event.
grep -q '\.meeting-deferred-writeback\.json' "$MD" \
  || fail "step 2a does not persist a breadcrumb payload (.meeting-deferred-writeback.json) on deferral"
grep -q 'meeting-deferred-writeback\.log' "$MD" \
  || fail "step 2a does not append a deferral event to the meeting-deferred-writeback log"
pass "deferral persists a breadcrumb payload + logs the event (id:2c42)"

# (2) The payload format is generic ({target_file, helper, payload}) so it extends to future
# defer sites, but is wired in only at the step-2a <root> ledger write-back (the sole site
# that defers today).
grep -q 'target_file' "$MD" || fail "breadcrumb payload missing generic target_file field"
grep -q 'helper' "$MD"      || fail "breadcrumb payload missing generic helper field"
grep -q 'payload' "$MD"     || fail "breadcrumb payload missing generic payload field"
pass "breadcrumb payload is the generic {target_file, helper, payload} shape"

# (3) A setup-phase replay check applies any pending payload under a FRESH claim, then clears
# the drop file — and is present in BOTH /meeting setup and /todo-update.
grep -qi 'replay' "$MD" \
  || fail "meeting SKILL has no setup-phase replay check for pending deferred write-backs"
grep -q 'claim.sh acquire' "$MD" \
  || fail "replay does not re-acquire a fresh claim before applying the deferred payload"
[[ -f "$TODO_MD" ]] || fail "todo-update/SKILL.md not found"
grep -qi 'meeting-deferred-writeback\|deferred write-back\|replay' "$TODO_MD" \
  || fail "/todo-update has no replay check for a pending meeting deferred write-back"
pass "setup-phase replay (fresh claim, clears drop file) wired into /meeting + /todo-update"

# (4) Nothing is applied while the pool still holds the claim (replay defers again on refusal).
grep -qi 'still holds\|fresh claim\|under a fresh' "$MD" \
  || fail "replay does not guard against applying while the pool still holds the claim"
pass "replay does not apply while the pool still holds the claim"

# (5) The drop file is gitignored.
[[ -f "$GITIGNORE" ]] || fail ".gitignore not found"
grep -q '\.meeting-deferred-writeback\.json' "$GITIGNORE" \
  || fail ".meeting-deferred-writeback.json is not gitignored"
pass ".meeting-deferred-writeback.json is gitignored"

echo "ALL PASS: /meeting deferred ledger write-back breadcrumb + replay (id:2c42)"
