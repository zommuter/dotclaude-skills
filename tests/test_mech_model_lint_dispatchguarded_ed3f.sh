#!/usr/bin/env bash
# roadmap:ed3f — lint-mech-model.mjs must also lint `dispatchGuarded(` call sites, not only
# bare `agent(` calls.
#
# WHY (id:3222 fallout): the `release:*`, `gaming-log:*`, and `write-relay-status` fenced
# mechanical hops were routed through the id:3222 visibility wrapper `dispatchGuarded(opts,
# repo, prompt)`. Their ```relay-mech fence text now sits inside a `dispatchGuarded(...)`
# argument list, not a bare `agent(...)` one — so lint-mech-model.mjs (which matched only the
# identifier `agent`) silently STOPPED covering them. The `model: MECH_MODEL` invariant still
# holds today by a second route (test_release_hop_mechanical_f7d3.sh greps the label line), but
# the linter — the durable guard against a FUTURE hop hardcoding a literal — went blind. The
# next fenced hop routed through the guard would lose coverage the same invisible way.
#
# This suite proves lint-mech-model.mjs (a) FLAGS a fence-carrying dispatchGuarded() call
# hardcoding 'bash'/'haiku', naming the line; (b) is SILENT on one using model: MECH_MODEL;
# and (c) leaves the real tree clean (the invariant genuinely holds — releaseLease dispatches
# model: MECH_MODEL).
#
# EXPECTED-RED until id:ed3f is ticked in ROADMAP.md: the current linter matches only `agent`,
# so cases (1)/(1b) below do NOT yet fail the sample and this suite fails. That is the spec.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/lint-mech-model.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-mech-model.mjs not found at $LINT"
node --check "$LINT" || fail "lint-mech-model.mjs fails node --check"
pass "linter exists and parses"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# (1) A fence-carrying dispatchGuarded() call hardcoding model:'bash' → nonzero, names the line.
cat > "$TMP/dg-bad-bash.workflow.js" <<'EOF'
export const meta = { name: 'dg-bad-bash' }
async function run() {
  await dispatchGuarded(
    { label: 'release:x', phase: 'Leases', model: 'bash' },
    'repo',
    'Run exactly this one command:\n```relay-mech\nclaim.sh release x\n```'
  )
}
EOF
if out="$(node "$LINT" "$TMP/dg-bad-bash.workflow.js" 2>&1)"; then
  fail "linter did NOT flag a fence-carrying dispatchGuarded() call hardcoding model:'bash':
$out"
fi
grep -qE 'dg-bad-bash\.workflow\.js:3:' < <(echo "$out") \
  || fail "linter flagged but did not name the dispatchGuarded() call's line (expected dg-bad-bash.workflow.js:3:…):
$out"
pass "(1) fence-carrying dispatchGuarded() call hardcoding model:'bash' → nonzero, names the line"

# (1b) Same, but model:'haiku' — probe mode-a resolves MECH_MODEL to 'haiku', so hardcoding
#      either literal breaks the other mode; both must be rejected.
cat > "$TMP/dg-bad-haiku.workflow.js" <<'EOF'
export const meta = { name: 'dg-bad-haiku' }
async function run() {
  await dispatchGuarded(
    { label: 'release:x', phase: 'Leases', model: 'haiku' },
    'repo',
    'Run exactly this one command:\n```relay-mech\nclaim.sh release x\n```'
  )
}
EOF
if out="$(node "$LINT" "$TMP/dg-bad-haiku.workflow.js" 2>&1)"; then
  fail "linter did NOT flag a fence-carrying dispatchGuarded() call hardcoding model:'haiku':
$out"
fi
grep -qE 'dg-bad-haiku\.workflow\.js:3:' < <(echo "$out") \
  || fail "linter flagged but did not name the dispatchGuarded() call's line:
$out"
pass "(1b) fence-carrying dispatchGuarded() call hardcoding model:'haiku' → nonzero, names the line"

# (2) A fence-carrying dispatchGuarded() call using model: MECH_MODEL → exit zero.
cat > "$TMP/dg-good.workflow.js" <<'EOF'
export const meta = { name: 'dg-good' }
const MECH_MODEL = 'bash'
async function run() {
  await dispatchGuarded(
    { label: 'release:x', phase: 'Leases', model: MECH_MODEL },
    'repo',
    'Run exactly this one command:\n```relay-mech\nclaim.sh release x\n```'
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/dg-good.workflow.js" 2>&1)"; then
  fail "linter false-positived on a fence-carrying dispatchGuarded() call using model: MECH_MODEL:
$out"
fi
pass "(2) fence-carrying dispatchGuarded() call with model: MECH_MODEL → exit zero (no false positive)"

# (2b) A NON-fence dispatchGuarded() call (e.g. a plain best-effort log write with no relay-mech
#      fence) hardcoding a literal model must NOT be swept up — only FENCE-carrying calls are in
#      scope, same rule as for agent().
cat > "$TMP/dg-nonfence.workflow.js" <<'EOF'
export const meta = { name: 'dg-nonfence' }
async function run() {
  await dispatchGuarded(
    { label: 'gaming-log:x', phase: 'Logging', model: 'haiku' },
    'repo',
    'Summarize this for the gaming log.'
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/dg-nonfence.workflow.js" 2>&1)"; then
  fail "linter wrongly flagged a NON-fence dispatchGuarded() call hardcoding a literal model:
$out"
fi
pass "(2b) non-fence dispatchGuarded() call hardcoding a literal model → exit zero"

# (3) The real tree is CLEAN — releaseLease/gaming-log/write-relay-status all route their fenced
#     prompts through dispatchGuarded with model: MECH_MODEL, so once the linter SEES those calls
#     it must still pass. (This is the acceptance the invisible-coverage gap hid.)
if ! out="$(node "$LINT" "$ROOT" 2>&1)"; then
  fail "the live tree has a fence-carrying agent()/dispatchGuarded() call hardcoding a literal model:
$out"
fi
pass "(3) live tree lints clean (including the dispatchGuarded-routed release/gaming-log/status hops)"

echo "ALL PASS"
