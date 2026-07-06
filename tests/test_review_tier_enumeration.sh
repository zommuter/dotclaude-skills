#!/usr/bin/env bash
# roadmap:f032 — review.md step 3 must mandate run-or-record-skip for EVERY declared
# test tier (routed:49a0).
#
# WHY: isochrone's e2e tier was RED for 13 days across 5 reviews that logged "suites
# green" while running only the unit tiers (playwright silently absent — no node_modules).
# A green claim from a SUBSET of tiers is the C3 "a skipped test is not a pass" class.
# Step 3 must force the reviewer to (a) ENUMERATE the repo's declared tiers, (b) RUN each
# or RECORD-THE-SKIP with reason in RELAY_LOG + the summary, (c) NAME the tiers actually
# run in any green claim — banning bare "suites green" from a subset. Aligned with
# handoff C3's `unverified` doctrine (same file family, cited).
#
# WEAK-but-cheap WORDING drift-guard: asserts the enumerate / record-skip / name-tiers
# markers are present in review.md step 3. Section-scoped so a marker dropped elsewhere
# in the file cannot false-green it. The REAL enforcement is the Opus reviewer following
# the contract.
set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$SRC_DIR_REPO/relay/references/review.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$REVIEW" ]] || fail "missing contract doc: $REVIEW"

# region <start_substr> <end_substr> <file>: print from the first line CONTAINING
# start_substr up to (excluding) the next line CONTAINING end_substr; to EOF if end is
# never found. Substring (not regex) matching via index().
region() {
  awk -v s="$1" -v e="$2" '
    index($0, s) { inreg=1 }
    inreg {
      if (!seenstart) { seenstart=1; print; next }
      if (index($0, e)) exit
      print
    }
  ' "$3"
}

# Step 3 region: from the "## 3." heading up to the next "## 4." heading.
s3="$(region '## 3.' '## 4.' "$REVIEW")"
[[ -n "$s3" ]] || fail "could not locate step 3 in review.md"

# The step-3 heading itself must be about tiers / run-or-record-skip, not the old
# bare "BDD suites" heading (which claimed no tier obligation).
grep -qiE '^## 3\..*tier' <<<"$s3" \
  || fail "step 3 heading no longer names the test-tier obligation (expected 'tier' in the '## 3.' heading)"
pass "step 3 heading names the test-tier obligation"

# (a) ENUMERATE the declared tiers.
grep -qiE 'enumerate' <<<"$s3" \
  || fail "(a) step 3 does not require ENUMERATING the repo's declared test tiers"
grep -qF 'package.json' <<<"$s3" \
  || fail "(a) step 3 does not name the tier-source manifests (package.json/Makefile/CI)"
pass "(a) step 3 requires enumerating declared tiers from manifests"

# (b) RUN each, or RECORD-THE-SKIP with reason in RELAY_LOG + summary.
grep -qiE 'record.the.skip' <<<"$s3" \
  || fail "(b) step 3 does not require RECORD-THE-SKIP for tiers that cannot run"
grep -qF 'RELAY_LOG' <<<"$s3" \
  || fail "(b) step 3 does not require recording the skip in RELAY_LOG"
pass "(b) step 3 requires run-or-record-skip (RELAY_LOG + summary)"

# (c) NAME the tiers actually run; ban bare "suites green" from a subset.
grep -qiE 'name the tiers|which tiers ran' <<<"$s3" \
  || fail "(c) step 3 does not require NAMING the tiers actually run in a green claim"
grep -qiE 'ban' <<<"$s3" \
  || fail "(c) step 3 does not BAN the bare subset-wide green wording"
pass "(c) step 3 names-tiers and bans bare subset-wide 'suites green'"

# Alignment with handoff C3's `unverified` doctrine — must be cited by name.
grep -qF 'unverified' <<<"$s3" \
  || fail "step 3 does not cite handoff C3's \`unverified\` doctrine (a skipped tier is not a pass)"
grep -qiE 'C3|§2\.4' <<<"$s3" \
  || fail "step 3 does not cross-reference the C3 / §2.4 skipped-is-not-a-pass rule"
pass "step 3 aligns with handoff C3's unverified doctrine"

echo "ALL PASS: review.md step 3 mandates run-or-record-skip for every declared tier (id:f032)"
