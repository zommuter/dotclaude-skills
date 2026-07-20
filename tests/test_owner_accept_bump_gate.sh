#!/usr/bin/env bash
# roadmap:8089
# RED spec (authored by /relay handoff 2026-07-20, apex) for the user-visible-close
# + bump gate — the BUILDABLE-NOW parts only (owner-ratified D3, meeting
# docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md,
# routed:1c08b). Incident: a @manual-acceptance ("NOT executor-closeable") item was
# bump-closed on a "driver's directive" → premature version bump.
#
#   (3a) FAIL-CLOSED owner-accept gate in review.md: a user-visible/@manual-acceptance
#        item cannot be bump-closed without an explicit greppable owner-accept marker
#        (`@owner-accepted:YYYY-MM-DD`); absent → the item stays OPEN, is EXCLUDED
#        from the user-observable-close set feeding the bump (NOT a repo-wide bump
#        block), and gets a REVIEW_ME "needs owner-accept" box. A driver's directive
#        is insufficient.
#   (3a-provenance) the marker is spoofable by the incident's own actor, so the
#        EXECUTOR CONTRACT forbids executors/drain sessions writing @owner-accepted —
#        a contract-surface change: executor-contract.md bumps v9 → v10 and the
#        CLAUDE.md `## Relay contract` pointer refreshes to match; review.md §2b
#        gains a gaming-check for an executor-introduced marker (flag + reopen).
#   (3b) reviewer JUDGMENT cross-check in review.md §2b: "does the app's real
#        entrypoint (not a dev harness) call the new path?" — grep-assisted, loud;
#        NOT a mechanical pass/fail.
#
# The git-hook PLUGIN into the 7a05/id:077d framework is GATED on id:077d readiness
# and is deliberately NOT specced here (a gated seam, not executor work).
#
# EXPECTED-RED while roadmap:8089 is unticked (does not fail the suite).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REV="$ROOT/relay/references/review.md"
EC="$ROOT/relay/references/executor-contract.md"
CM="$ROOT/CLAUDE.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$REV" ]] || fail "review.md not found at $REV"
[[ -f "$EC"  ]] || fail "executor-contract.md not found at $EC"
[[ -f "$CM"  ]] || fail "repo CLAUDE.md not found at $CM"

# ── (3a) fail-closed owner-accept gate in review.md ───────────────────────────
grep -q '@owner-accepted:' "$REV" \
  || fail "(3a) review.md does not define the dated @owner-accepted:YYYY-MM-DD marker grammar"
grep -qi 'needs owner-accept' "$REV" \
  || fail "(3a) review.md does not prescribe the REVIEW_ME 'needs owner-accept' box for a missing marker"
grep -qi 'user-observable' "$REV" \
  || fail "(3a) review.md does not tie the gate to the user-observable-close set feeding the bump"
grep -qi 'repo-wide' "$REV" \
  || fail "(3a) review.md does not state the item-close scoping (excluded from the close set, NOT a repo-wide bump block)"
grep -qiE "driver'?s directive" "$REV" \
  || fail "(3a) review.md does not state that a driver's directive is INSUFFICIENT for owner acceptance"
pass "(3a) review.md carries the fail-closed owner-accept gate (marker grammar, REVIEW_ME box, item-scoped exclusion, driver-insufficient)"

# ── (3a-provenance) executor contract v10 forbids executor-written markers ────
grep -q 'relay-executor contract v10' "$EC" \
  || fail "(3a-prov) executor-contract.md marker is not bumped to v10 (contract-surface change requires the bump)"
grep -q '@owner-accepted' "$EC" \
  || fail "(3a-prov) executor-contract.md does not mention @owner-accepted at all"
ec_rule="$(grep -n '@owner-accepted' "$EC" | head -5)"
grep -iqE 'never|must not|forbid' <(grep -iA2 -B2 '@owner-accepted' "$EC") \
  || fail "(3a-prov) executor-contract.md does not FORBID executors/drain sessions writing @owner-accepted (found only: $ec_rule)"
pass "(3a-prov) executor contract v10 forbids executor/drain-written @owner-accepted"

# ── (3a-provenance) CLAUDE.md pointer refreshed + marker-consistent ───────────
grep -q '<!-- relay-executor contract v10 -->' "$CM" \
  || fail "(3a-prov) CLAUDE.md '## Relay contract' pointer not refreshed to v10"
ec_v="$(grep -oE 'relay-executor contract v[0-9]+' "$EC" | head -1)"
cm_v="$(grep -oE 'relay-executor contract v[0-9]+' "$CM" | head -1)"
[[ -n "$ec_v" && "$ec_v" == "$cm_v" ]] \
  || fail "(3a-prov) contract version drift: executor-contract.md says '$ec_v' but CLAUDE.md pointer says '$cm_v'"
pass "(3a-prov) CLAUDE.md pointer matches the v10 contract marker"

# ── (3a-provenance + 3b) review.md §2b judgment-residue block ─────────────────
sec2b="$(sed -n '/### 2b\./,/### 2c\./p' "$REV")"
[[ -n "$sec2b" ]] || fail "(2b) could not extract review.md §2b (judgment-residue checks)"

grep -q '@owner-accepted' <<<"$sec2b" \
  || fail "(3a-prov) review.md §2b has no gaming-check for an executor-introduced @owner-accepted marker in the reviewed diff"
grep -qi 'reopen' <<<"$sec2b" \
  || fail "(3a-prov) the §2b @owner-accepted gaming-check does not flag + reopen"
pass "(3a-prov) review.md §2b gaming-check: executor-introduced @owner-accepted → flag + reopen"

grep -qi 'entrypoint' <<<"$sec2b" \
  || fail "(3b) review.md §2b has no real-entrypoint cross-check ('does the app's real entrypoint call the new path?')"
grep -qi 'dev harness' <<<"$sec2b" \
  || fail "(3b) the §2b entrypoint cross-check does not name the dev-harness failure mode (a harness mistaken for shipped)"
pass "(3b) review.md §2b carries the real-entrypoint-not-dev-harness judgment cross-check"

echo "OK: all owner-accept bump-gate assertions passed"
