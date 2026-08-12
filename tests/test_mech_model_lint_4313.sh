#!/usr/bin/env bash
# roadmap:4313 — every ```relay-mech fence-carrying `agent()` call must dispatch
# `model: MECH_MODEL`, never a literal model name.
#
# The SYMPTOM this guards is already fixed (loderite 490ac6e): discover-prelude,
# the discover-run shard, and releaseLease each missed the id:4239 MECH_MODEL
# indirection. Because discover-prelude is round-1's FIRST hop, probe mode-a
# killed the whole pool with zero units dispatched (run relay-20260730-115757-3504).
# This suite proves lint-mech-model.mjs (a) FLAGS a fence-carrying agent() call
# hardcoding 'bash' or 'haiku', naming the line; (b) is SILENT on a fence-carrying
# call using model: MECH_MODEL and on a NON-fence call hardcoding a literal model
# (handback-followup/integrate/gaming-log — real inference calls); and (c) runs
# CLEAN against the real tree.

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

# (1) A fence-carrying agent() call hardcoding model:'bash' → nonzero, names the line.
cat > "$TMP/bad-bash.mjs" <<'EOF'
export const meta = { name: 'bad-bash' }
async function run() {
  await agent(
    'Run EXACTLY this command:\n```relay-mech\ncmd\n```',
    { label: 'x', phase: 'Support', model: 'bash' }
  )
}
EOF
if out="$(node "$LINT" "$TMP/bad-bash.mjs" 2>&1)"; then
  fail "linter did NOT flag a fence-carrying agent() call hardcoding model:'bash':
$out"
fi
echo "$out" | grep -qE 'bad-bash\.mjs:3:' \
  || fail "linter flagged but did not name the agent() call's line (expected bad-bash.mjs:3:…):
$out"
pass "(1) fence-carrying agent() call hardcoding model:'bash' → nonzero, names the line"

# (1b) Same, but model:'haiku' — mode-a is EXACTLY why both literals must be rejected, not
#      just 'bash' (probe mode-a resolves MECH_MODEL to 'haiku'; hardcoding it breaks the
#      healthy-proxy case instead).
cat > "$TMP/bad-haiku.mjs" <<'EOF'
export const meta = { name: 'bad-haiku' }
async function run() {
  await agent(
    'Run EXACTLY this command:\n```relay-mech\ncmd\n```',
    { label: 'x', phase: 'Support', model: 'haiku' }
  )
}
EOF
if out="$(node "$LINT" "$TMP/bad-haiku.mjs" 2>&1)"; then
  fail "linter did NOT flag a fence-carrying agent() call hardcoding model:'haiku':
$out"
fi
echo "$out" | grep -qE 'bad-haiku\.mjs:3:' \
  || fail "linter flagged but did not name the agent() call's line:
$out"
pass "(1b) fence-carrying agent() call hardcoding model:'haiku' → nonzero, names the line"

# (2) A fence-carrying agent() call using model: MECH_MODEL → exit zero.
cat > "$TMP/good-fence.mjs" <<'EOF'
export const meta = { name: 'good-fence' }
const MECH_MODEL = 'bash'
async function run() {
  await agent(
    'Run EXACTLY this command:\n```relay-mech\ncmd\n```',
    { label: 'x', phase: 'Support', model: MECH_MODEL }
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/good-fence.mjs" 2>&1)"; then
  fail "linter false-positived on a fence-carrying call using model: MECH_MODEL:
$out"
fi
pass "(2) fence-carrying agent() call with model: MECH_MODEL → exit zero (no false positive)"

# (2b) A NON-fence agent() call hardcoding a literal model (a real inference call, e.g.
#      handback-followup/integrate/gaming-log) → exit zero, must NOT be swept up.
cat > "$TMP/good-nonfence.mjs" <<'EOF'
export const meta = { name: 'good-nonfence' }
async function run() {
  await agent(
    'Summarize the handback for this repo.',
    { label: 'handback-followup', phase: 'Logging', model: 'haiku' }
  )
  await agent(
    prompt,
    { label: 'integrate', phase: 'Integrate', schema: INTEGRATE_SCHEMA, model: 'sonnet' }
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/good-nonfence.mjs" 2>&1)"; then
  fail "linter wrongly flagged a NON-fence agent() call hardcoding a literal model:
$out"
fi
pass "(2b) non-fence agent() call hardcoding a literal model (real inference call) → exit zero"

# (2c) A doc-comment INSIDE the call arguments merely mentioning model:"bash" as PROSE (this
#      file's own id:6176 convention: 'mechanical hop (model:"bash")') must not be mistaken
#      for the real options object — the real dispatch below it uses MECH_MODEL and must pass.
cat > "$TMP/good-comment.mjs" <<'EOF'
export const meta = { name: 'good-comment' }
const MECH_MODEL = 'bash'
async function run() {
  await agent(
    // id:6176 — mechanical hop (model:"bash"): the ```relay-mech fence carries the command;
    // mechanical-proxy.py extracts and runs it locally with zero upstream inference.
    'Run EXACTLY this command:\n```relay-mech\ncmd\n```',
    { label: 'x', phase: 'Support', model: MECH_MODEL }
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/good-comment.mjs" 2>&1)"; then
  fail "linter mistook a doc-comment's model:\"bash\" PROSE for the real options object:
$out"
fi
pass "(2c) doc-comment mentioning model:\"bash\" as prose does not desync the real model: MECH_MODEL check"

# (2d) id:ed3f — a fence-carrying call routed through the `dispatchGuarded` wrapper (not a
#      bare `agent(` call) hardcoding a literal model must be FLAGGED, naming the line — the
#      real releaseLease shape this fix targets.
cat > "$TMP/bad-guarded.mjs" <<'EOF'
export const meta = { name: 'bad-guarded' }
async function run() {
  await dispatchGuarded(
    { label: 'release:x:claim', phase: 'Leases', model: 'bash' },
    'repo',
    'Run exactly this one command:\n```relay-mech\ncmd\n```'
  )
}
EOF
if out="$(node "$LINT" "$TMP/bad-guarded.mjs" 2>&1)"; then
  fail "linter did NOT flag a fence-carrying dispatchGuarded() call hardcoding model:'bash':
$out"
fi
echo "$out" | grep -qE 'bad-guarded\.mjs:3:' \
  || fail "linter flagged but did not name the dispatchGuarded() call's line:
$out"
pass "(2d) fence-carrying dispatchGuarded() call hardcoding a literal model → nonzero, names the line"

# (2e) Same shape but with model: MECH_MODEL → exit zero (no false positive on the wrapper).
cat > "$TMP/good-guarded.mjs" <<'EOF'
export const meta = { name: 'good-guarded' }
const MECH_MODEL = 'bash'
async function run() {
  await dispatchGuarded(
    { label: 'release:x:claim', phase: 'Leases', model: MECH_MODEL },
    'repo',
    'Run exactly this one command:\n```relay-mech\ncmd\n```'
  )
}
EOF
if ! out="$(node "$LINT" "$TMP/good-guarded.mjs" 2>&1)"; then
  fail "linter false-positived on a fence-carrying dispatchGuarded() call using model: MECH_MODEL:
$out"
fi
pass "(2e) fence-carrying dispatchGuarded() call with model: MECH_MODEL → exit zero"

# (3) Directory scan discovers workflow scripts via the export-const-meta marker / *.workflow.js
#     and ignores a plain script with no marker.
mkdir -p "$TMP/repo/relay/scripts"
cp "$TMP/bad-bash.mjs" "$TMP/repo/relay/scripts/wf.workflow.js"
cat > "$TMP/repo/relay/scripts/plain.mjs" <<'EOF'
// no meta marker → not a workflow script; its bad fence dispatch is not linted
async function run() {
  await agent(
    '```relay-mech\ncmd\n```',
    { model: 'bash' }
  )
}
EOF
if node "$LINT" "$TMP/repo" >/dev/null 2>&1; then
  fail "directory scan missed the violation in wf.workflow.js"
fi
out="$(node "$LINT" "$TMP/repo" 2>&1 || true)"
echo "$out" | grep -q 'wf.workflow.js' || fail "directory scan did not report wf.workflow.js:
$out"
echo "$out" | grep -q 'plain.mjs' && fail "directory scan wrongly linted the non-workflow plain.mjs:
$out"
pass "(3) dir scan finds *.workflow.js / export-const-meta scripts, skips non-workflow files"

# (4) The real tree is CLEAN (acceptance — the invariant holds today per this handoff's audit).
if ! out="$(node "$LINT" "$ROOT" 2>&1)"; then
  fail "the live tree has a fence-carrying agent() call hardcoding a literal model:
$out"
fi
pass "(4) live tree lints clean"

# (5) Wired into the Makefile install manifest (id:69ef install-completeness precedent).
grep -q 'scripts/lint-mech-model.mjs' "$ROOT/Makefile" \
  || fail "lint-mech-model.mjs not in the Makefile relay manifest"
pass "(5) linter is in the Makefile install manifest"

echo "ALL PASS"
