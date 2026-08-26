#!/usr/bin/env bash
# roadmap:391b — wires the ALREADY-BUILT mechanical-orphan draft loop (id:8a6b) into
# relay-loop.js's PER-ROUND cadence (owner ratification 2026-08-26). Two owner decisions this
# tests holds to: (A) the pool NEVER authors into recipes/pending/ — mechanical-orphan-draft.sh
# only ever writes drafts/, the id:64d3 human-promotion trust boundary is untouched; (B) the
# drafter hop runs EVERY pool round, not only in a review path.
#
# Cannot run the Workflow engine itself in a hermetic test (relay-loop.js is a top-level script
# with side effects the moment it is evaluated — see test_dispatch_event_sig.sh /
# test_relay_status.sh for the established pattern this test follows: static source-shape
# assertions on relay-loop.js, PLUS genuine behavioural execution of the two functions this item
# added, extracted verbatim from the file text and run under node — not hand-duplicated logic).
#
# Hermetic: mktemp -d roots; RELAY_RECIPE_DIR/RELAY_TOML/SRC_DIR overrides; no ~/.claude, no
# ~/.config/relay, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
DRAFT="$SRC_DIR/relay/scripts/mechanical-orphan-draft.sh"
LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -x "$DRAFT" ]] || { echo "FAIL: mechanical-orphan-draft.sh missing/non-exec"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }

# ── 1. node --check + the Workflow template lexer must both stay clean after this edit ──
if node --check "$JS" 2>/tmp/391b_check.err; then
  ok "node --check relay-loop.js passes"
else
  bad "node --check failed: $(cat /tmp/391b_check.err)"
fi
if out="$(node "$LINT" "$JS" 2>&1)"; then
  ok "lint-workflow-templates.mjs stays clean (no unescaped-backtick hazard)"
else
  bad "lint-workflow-templates.mjs flagged a violation: $out"
fi

# ── 2. Static source-shape assertions (mirrors test_relay_status.sh / test_dispatch_event_sig.sh) ──
grep -q 'async function draftMechanicalOrphans' "$JS" \
  && ok "draftMechanicalOrphans() is defined" \
  || bad "draftMechanicalOrphans() missing"

grep -qF "'~/.claude/skills/relay/scripts/mechanical-orphan-draft.sh'" "$JS" \
  && ok "the exact fenced command string is present" \
  || bad "fenced command string not found verbatim"

grep -q '```relay-mech' "$JS" \
  && ok 'relay-loop.js still uses the ```relay-mech mechanical-hop fence convention' \
  || bad 'no ```relay-mech fence found'

grep -q 'await draftMechanicalOrphans()' "$JS" \
  && ok "draftMechanicalOrphans() is called from a round (per-round cadence, not review-only)" \
  || bad "draftMechanicalOrphans() is never called"

# Cadence: the call site sits right after the per-round beatHeartbeat() call, i.e. it runs on
# every round (dry or not), not gated behind actionable/dispatch logic.
# NOTE: assigned to a variable rather than piped into `grep -q` — under `set -o pipefail` an
# early-exiting pipe consumer SIGPIPEs the producer and fails the script (id:81d5 lint).
cadence_hit="$(awk '/await beatHeartbeat\(\)/{f=1} f&&/await draftMechanicalOrphans\(\)/{print;exit}' "$JS")"
[[ "$cadence_hit" == *draftMechanicalOrphans* ]] \
  && ok "drafter call site follows beatHeartbeat() — runs every round, mirrors an existing per-round hop" \
  || bad "drafter call is not positioned as a per-round hop alongside beatHeartbeat()"

grep -q 'mechanicalDrafts: null' "$JS" \
  && ok "state carries a mechanicalDrafts field, seeded null" \
  || bad "state.mechanicalDrafts not initialised"

grep -q 'mechanicalDrafts: s\.mechanicalDrafts' "$JS" \
  && ok "snapshotState() copies mechanicalDrafts (so scheduleStatusWrite's queued write sees it)" \
  || bad "snapshotState() does not carry mechanicalDrafts"

grep -q '## Mechanical drafts' "$JS" \
  && ok "buildRelayStatus() renders a Mechanical drafts section" \
  || bad "no Mechanical drafts section in buildRelayStatus()"

# id:64d3 — the pool must NEVER write recipes/pending itself. Assert the drafter call site and
# its surrounding comments never construct a pending/ path, and the script invoked is the
# DRAFTER (writes drafts/ only) not some pending-writing variant.
grep -q "NEVER writes pending/" "$JS" && grep -q "id:64d3" "$JS" \
  && ok "relay-loop.js documents/guards the drafts/-only, never-pending/ boundary in prose" \
  || bad "no explicit never-writes-pending guard language found"
if grep -qE "pending/[a-zA-Z0-9_.\$\{\}-]*\.json.*mechanical-orphan-draft|mechanical-orphan-draft.*>\s*.*pending" "$JS"; then
  bad "relay-loop.js appears to write pending/ directly from the drafter hop — id:64d3 VIOLATION"
else
  ok "relay-loop.js never constructs a pending/ write path around the drafter hop"
fi

# Fail-open shape: MECH-ERROR handling + a try/catch, both resolving to null rather than
# rethrowing/propagating a rejection that could fail the round.
awk '/^async function draftMechanicalOrphans/,/^async function stopHeartbeat/' "$JS" > /tmp/391b_fn.js
grep -q 'MECH-ERROR exit=' /tmp/391b_fn.js && ok "draftMechanicalOrphans() checks the MECH-ERROR sentinel" || bad "no MECH-ERROR check"
grep -q 'catch (e)' /tmp/391b_fn.js && ok "draftMechanicalOrphans() has a catch block" || bad "no catch block"
null_returns="$(grep -c 'return null' /tmp/391b_fn.js || true)"   # var, not a pipe into grep -q (id:81d5)
(( null_returns >= 1 )) && ok "draftMechanicalOrphans() has at least one fail-open 'return null'" || bad "no fail-open return null"
grep -q '^\s*throw' /tmp/391b_fn.js && bad "draftMechanicalOrphans() rethrows — not fail-open" || ok "draftMechanicalOrphans() never rethrows"

# The call site must never let a rejection propagate un-caught either (the function itself
# never rejects per the assertions above, but assert the call is a plain await with no bare
# .then/.catch dance masking a swallow, and no surrounding try/catch that could itself fail
# the round on a thrown mechDraftResult).
grep -q 'const mechDraftResult = await draftMechanicalOrphans()' "$JS" \
  && ok "call site is a plain await (round proceeds unconditionally after it settles)" \
  || bad "call site shape changed unexpectedly"

# ── 3. BEHAVIOURAL: extract the exact regex relay-loop.js uses to parse the drafter's summary
# line, and confirm it matches REAL stdout from the REAL mechanical-orphan-draft.sh (hermetic
# fixture, no ~/.claude, no ~/.config/relay, no network) — proves the two sides of the contract
# (script's stdout shape <-> relay-loop.js's parser) actually agree, not just that each looks
# plausible in isolation. ──
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_RECIPE_DIR="$TMP/recipes"
mkdir -p "$RELAY_RECIPE_DIR/pending" "$RELAY_RECIPE_DIR/done" "$TMP/repoY"
cat > "$TMP/repoY/ROADMAP.md" <<'EOF'
# ROADMAP
- [ ] [MECHANICAL] orphaned mechanical item <!-- id:9391 -->
EOF
real_stdout="$("$DRAFT" "repoY=$TMP/repoY")"
echo "$real_stdout"
summary_line="$(echo "$real_stdout" | tail -1)"

# Extract the parser regex source verbatim from the file (the literal /…/ after `.match(`).
# `awk NR==1` (no `exit`) reads its whole input, so it cannot SIGPIPE the producer the way
# `head -1` does under `set -o pipefail` (id:81d5 lint).
regex_src="$(grep -oP "(?<=\.match\()/[^/]*mechanical-orphan-draft: drafted=[^/]*/" "$JS" | awk 'NR==1')"
[[ -n "$regex_src" ]] && ok "extracted the parser regex literal from relay-loop.js: $regex_src" || bad "could not extract the parser regex from relay-loop.js"

# Pass the regex source through the ENVIRONMENT (never bash string-interpolated into the JS
# source) so its backslashes (\d, \() survive verbatim — an unquoted bash interpolation would
# strip them and silently corrupt the pattern.
export REGEX_SRC="$regex_src"
node - "$summary_line" <<'NODE' > /tmp/391b_parse.out 2>/tmp/391b_parse.err
const line = process.argv[2] || process.argv[1]
const re = eval(process.env.REGEX_SRC)
const m = line.match(re)
if (!m) { console.error('NO MATCH'); process.exit(1) }
console.log(`drafted=${m[1]} skipped=${m[2]}`)
NODE
rc=$?
[[ $rc -eq 0 ]] \
  && ok "relay-loop.js's own regex parses the REAL script's summary line: $(cat /tmp/391b_parse.out)" \
  || bad "relay-loop.js's regex failed to parse real stdout '$summary_line': $(cat /tmp/391b_parse.err)"

grep -q 'drafted=1' /tmp/391b_parse.out && grep -q 'skipped=0' /tmp/391b_parse.out \
  && ok "parsed counts match the fixture (1 fresh orphan drafted, 0 pre-existing)" \
  || bad "parsed counts wrong: $(cat /tmp/391b_parse.out)"

# Re-run: idempotent → drafted=0 skipped=0. mechanical-orphan-scan.sh's own orphan->draft
# kind-flip (mechanical-orphan-scan.sh:118-120) means an id with a draft is no longer reported
# as `orphan` at all, so mechanical-orphan-draft.sh's per-invocation loop (which only visits
# `kind=="orphan"` rows) never revisits it — it silently reports 0/0 for that id from here on.
# This is EXACTLY why relay-loop.js's state.mechanicalDrafts must ACCUMULATE drafted/skipped
# across rounds rather than treat any one round's total as a live count (see that field's
# declaration comment in relay-loop.js) — asserting that here pins the real script behaviour the
# JS-side accumulator design depends on.
real_stdout2="$("$DRAFT" "repoY=$TMP/repoY")"
summary_line2="$(echo "$real_stdout2" | tail -1)"
node - "$summary_line2" <<'NODE' > /tmp/391b_parse2.out 2>/tmp/391b_parse2.err
const line = process.argv[2] || process.argv[1]
const re = eval(process.env.REGEX_SRC)
const m = line.match(re)
if (!m) process.exit(1)
console.log(`drafted=${m[1]} skipped=${m[2]}`)
NODE
rc2=$?
[[ $rc2 -eq 0 ]] && grep -q 'drafted=0' /tmp/391b_parse2.out && grep -q 'skipped=0' /tmp/391b_parse2.out \
  && ok "idempotent re-run parses as drafted=0 skipped=0 (the orphan->draft kind-flip means it is no longer even visited — confirms the accumulator design in relay-loop.js is necessary, not a live-total shortcut)" \
  || bad "idempotent re-run did not parse as expected: $(cat /tmp/391b_parse2.out 2>/dev/null || true)"

# ── 4. BEHAVIOURAL: the exact fenced command string that will be dispatched must pass
# mechanical-proxy.py's _command_allowed() predicate (READ ONLY — no edits made there). A hop
# whose shape fails this predicate silently 404s and fails open (the specific failure mode this
# item's brief called out). ──
PROXY="$SRC_DIR/relay/scripts/mechanical-proxy.py"
[[ -f "$PROXY" ]] || { echo "FAIL: mechanical-proxy.py not found"; exit 1; }
cmd_line="$(grep -oP "(?<=')~/\.claude/skills/relay/scripts/mechanical-orphan-draft\.sh(?=')" "$JS" | awk 'NR==1')"
[[ -n "$cmd_line" ]] && ok "recovered the exact fenced command from relay-loop.js: $cmd_line" || bad "could not recover the fenced command"

allowed="$(python3 - "$PROXY" "$cmd_line" <<'PY'
import importlib.util, sys
proxy_path, cmd = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("mechanical_proxy", proxy_path)
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)
print("True" if mp._command_allowed(cmd) else "False")
print("True" if "mechanical-orphan-draft.sh" in mp.ALLOWED_RELAY_SCRIPTS else "False")
PY
)"
# Split into an array instead of piping into `sed -n Np | grep -q` — both are early-exiting
# pipe consumers under `set -o pipefail` (id:81d5 lint).
mapfile -t allowed_lines <<< "$allowed"
[[ "${allowed_lines[0]:-}" == "True" ]] \
  && ok "mechanical-proxy.py's _command_allowed() ACCEPTS the exact dispatched command (no silent 404 hazard)" \
  || bad "_command_allowed() REJECTS the dispatched command — this hop would fail open silently: $allowed"
[[ "${allowed_lines[1]:-}" == "True" ]] \
  && ok "mechanical-orphan-draft.sh is present in ALLOWED_RELAY_SCRIPTS" \
  || bad "mechanical-orphan-draft.sh missing from ALLOWED_RELAY_SCRIPTS"

# ── 5. BEHAVIOURAL: extract buildRelayStatus()'s mechDrafts render snippet and confirm both
# branches (never-run vs a real hop result) render as expected — a real, not hand-duplicated,
# slice of the file's own logic. ──
node - "$JS" <<'NODE'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2] || process.argv[1], 'utf8')
const start = src.indexOf('const mechDrafts = state.mechanicalDrafts')
if (start < 0) { console.error('start marker not found'); process.exit(1) }
const endMarker = "'_(not yet run this session)_'"
const endIdx = src.indexOf(endMarker, start)
if (endIdx < 0) { console.error('end marker not found'); process.exit(1) }
const snippet = src.slice(start, endIdx + endMarker.length)
// Evaluate the snippet with a stubbed `state`, twice.
function render(mechanicalDrafts) {
  const state = { mechanicalDrafts }
  const fn = new Function('state', snippet + '\nreturn mechDrafts;')
  return fn(state)
}
const nullCase = render(null)
const hopCase = render({ drafted: 3, skipped: 4 })
if (nullCase !== '_(not yet run this session)_') { console.error('FAIL null-case: ' + nullCase); process.exit(1) }
// ACCUMULATOR semantics (id:391b): `drafted` is what THIS RUN newly wrote, summed across
// rounds; `skipped` is the rare same-round race. They are deliberately NOT added together —
// drafted+skipped is not a meaningful "awaiting promotion" total, because the true cross-run
// backlog is served live by relay-status-publish.sh's "## Mechanical orphans / drafts (id:8a6b)"
// section. Assert each part separately, and assert the misleading SUM is absent so a future
// edit cannot quietly reintroduce it.
if (!/3 new draft\(s\) written this run/.test(hopCase)) { console.error('FAIL hop-case drafted: ' + hopCase); process.exit(1) }
if (!/4 same-round skip\(s\)/.test(hopCase)) { console.error('FAIL hop-case skipped: ' + hopCase); process.exit(1) }
if (/\b7\b/.test(hopCase)) { console.error('FAIL hop-case must NOT sum drafted+skipped into a bogus total: ' + hopCase); process.exit(1) }
if (!/awaiting HUMAN promotion/.test(hopCase)) { console.error('FAIL hop-case must name the human promotion gate (id:64d3): ' + hopCase); process.exit(1) }
console.log('OK: null renders "' + nullCase + '"; hop renders "' + hopCase + '"')
NODE
if [[ $? -eq 0 ]]; then
  ok "buildRelayStatus()'s mechDrafts snippet (extracted verbatim) renders both branches correctly"
else
  bad "extracted mechDrafts snippet failed to render as expected"
fi

# ── 6. BEHAVIOURAL: draftMechanicalOrphans() itself, extracted verbatim, fails open on a
# thrown agent() and on a MECH-ERROR sentinel — a refused/failed hop must never reject or
# throw out of runRound. ──
node - "$JS" <<'NODE'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2] || process.argv[1], 'utf8')
const start = src.indexOf('async function draftMechanicalOrphans() {')
if (start < 0) { console.error('start marker not found'); process.exit(1) }
const endMarker = '\nasync function stopHeartbeat'
const endIdx = src.indexOf(endMarker, start)
if (endIdx < 0) { console.error('end marker not found'); process.exit(1) }
const fnSrc = src.slice(start, endIdx)

async function run(label, agentImpl) {
  const log = () => {}
  const MECH_MODEL = 'bash'
  const agent = agentImpl
  const wrapped = new Function('agent', 'log', 'MECH_MODEL', `
    ${fnSrc}
    return draftMechanicalOrphans();
  `)
  let result, threw = false
  try {
    result = await wrapped(agent, log, MECH_MODEL)
  } catch (e) {
    threw = true
  }
  console.log(`${label}: threw=${threw} result=${JSON.stringify(result)}`)
  return { threw, result }
}

;(async () => {
  const { threw: t1, result: r1 } = await run('throwing-agent', async () => { throw new Error('proxy refused') })
  const { threw: t2, result: r2 } = await run('mech-error-agent', async () => 'MECH-ERROR exit=1 boom')
  const { threw: t3, result: r3 } = await run('garbage-agent', async () => 'nonsense, no summary line here')
  const { threw: t4, result: r4 } = await run('success-agent', async () => 'drafted: 9391 (repoY) -> /x\nmechanical-orphan-draft: drafted=1 skipped=0 (existing)')
  if (t1 || t2 || t3 || t4) { console.error('a fail-open path THREW instead of resolving'); process.exit(1) }
  if (r1 !== null || r2 !== null || r3 !== null) { console.error('a fail-open path did not resolve to null'); process.exit(1) }
  if (!r4 || r4.drafted !== 1 || r4.skipped !== 0) { console.error('success path did not parse correctly: ' + JSON.stringify(r4)); process.exit(1) }
  console.log('ALL FAIL-OPEN PATHS RESOLVE (never throw), SUCCESS PATH PARSES')
})()
NODE
if [[ $? -eq 0 ]]; then
  ok "draftMechanicalOrphans() (extracted verbatim) fails open on throw/MECH-ERROR/unparseable stdout, and parses success"
else
  bad "draftMechanicalOrphans() fail-open behaviour did not hold under direct execution"
fi

echo "test_mechanical_orphan_draft_wiring_391b: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
