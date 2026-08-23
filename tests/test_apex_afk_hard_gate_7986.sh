#!/usr/bin/env bash
# roadmap:7986 — apex `hard` dispatch requires `--afk`; the gate keys on STRONG_TIER, not a model id.
#
# ONE unit combining two owner-ratified TODO items (2026-08-23):
#   id:7986 — apex `hard` dispatch MUST require `--afk`. Owner 2026-08-22, after a live pool
#             spent Opus on three [HARD] units against his cap. `handoff` is PERMITTED ALWAYS,
#             like `review`; ONLY `hard` is gated. That ruling is SETTLED — this spec encodes it.
#   id:da51 — the HARD-execute gate compared the model-id string literal `claude-opus-4-8`, so
#             bumping the pin to `claude-opus-5` would make the inequality true and DEFER every
#             hard unit while reporting "requires apex Opus" — a message false precisely when
#             the pin is correct. The gate must ask `STRONG_TIER === 'opus'` instead, and the
#             model id becomes a pure OUTPUT value.
#
# SPEC SHAPE (the id:dc5b round-plan.mjs / id:1735 handback-summary.mjs pattern):
# the invariant lives in an extractable PURE module `relay/scripts/apex-gate.mjs` exporting
#
#     enforceApexGate(units, { strongTier, afk }) -> { plan, hardDeferred }
#
#   - units      : the round's dispatchable units IN SCHEDULING ORDER, [{ repo, verdict, ... }]
#   - strongTier : 'opus' | 'fable'  (NOT a model id — that is the whole point of da51)
#   - afk        : boolean, true when the run was launched `--afk`
#   - plan       : surviving units, ORDER PRESERVED
#   - hardDeferred: every `hard` unit this gate withheld, carried WHOLE plus a `gateReason`
#                  string so the RELAY_STATUS Queued surface can name WHY. Never dropped,
#                  never silently idle — mirrors the proven `intensive:<res>` skip shape.
#
# relay-loop.js carries a byte-equivalent inline copy (the Workflow sandbox cannot `import`)
# and is pinned structurally below, exactly as round-plan.mjs is.
#
# Hermetic: reads only the shipped tree + a mktemp'd node spec. No network, no ~/.claude.
#
# On lint-source-grep-assertions.py: groups (B)/(C) ARE source greps over relay-loop.js and
# SKILL.md, and the lint flags this file SHAPE-ONLY — identically to the ratified precedent
# tests/test_round_plan_one_unit_per_repo.sh. That is deliberate and the lint is advisory:
# relay-loop.js runs ONLY in the Workflow sandbox (the id:2d20 RED-spec-from-worktree hazard),
# so it is not hermetically executable. The BEHAVIOURAL evidence lives in group (A) against the
# extractable module; (B) pins the wiring, and (C1)/(B2)/(B4) are ABSENCE assertions about a
# string literal, which is genuinely a text contract (da51: the literal must not survive).
#
# MUTATION-VERIFIED 2026-08-23 against a reference implementation. Five mutants, each caught by
# the intended assertion and by no other: model-id-keyed gate → (A5)+(A3); handoff also gated →
# (A2); hard dropped instead of surfaced → (A2); --afk ignored (today's behaviour) → (A2);
# non-apex reason blaming --afk → (A3). The correct implementation makes all of (A) green.
#
# EXPECTED-RED while roadmap:7986 is unticked.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/relay/scripts/apex-gate.mjs"
JS="$ROOT/relay/scripts/relay-loop.js"
SKILL="$ROOT/relay/SKILL.md"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

command -v node >/dev/null || { echo "FAIL: node not available (required)"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# (A) BEHAVIOURAL — the pure gate module
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "$GATE" ]]; then
  fail "(A) relay/scripts/apex-gate.mjs not found — the extractable pure gate module IS the spec surface"
else
  cat > "$TMP/spec.mjs" <<EOF
const { enforceApexGate } = await import('file://$GATE');
let bad = 0;
const fail = (m) => { console.log('FAIL: ' + m); bad++; };
const ok   = (m) => console.log('PASS: ' + m);
const UNITS = () => ([
  { repo: 'r1', verdict: 'review'  },
  { repo: 'r2', verdict: 'hard'    },
  { repo: 'r3', verdict: 'handoff' },
  { repo: 'r4', verdict: 'execute' },
  { repo: 'r5', verdict: 'hard'    },
]);
const shape = (r) => r && Array.isArray(r.plan) && Array.isArray(r.hardDeferred);
// mark() snapshots the failure counter so each group can report its own verdict
// independently — a later group's failure must never suppress an earlier group's PASS line.
const mark = () => bad;
const clean = (n) => bad === n;
const repos = (a) => a.map(u => u.repo).join(',');

// (A1) --afk + apex tier: EVERYTHING dispatches, hard included, order preserved.
{
  const r = enforceApexGate(UNITS(), { strongTier: 'opus', afk: true });
  if (!shape(r)) fail('(A1) must return { plan: [], hardDeferred: [] }');
  else if (repos(r.plan) !== 'r1,r2,r3,r4,r5')
    fail('(A1) with --afk at apex every unit must dispatch, order preserved — got plan=' + repos(r.plan));
  else if (r.hardDeferred.length !== 0)
    fail('(A1) with --afk at apex nothing may be deferred — got ' + JSON.stringify(r.hardDeferred));
  else ok('(A1) --afk + STRONG_TIER=opus → hard units DISPATCH');
}

// (A2) NO --afk at apex: hard units are WITHHELD and SURFACED with a reason naming --afk.
//      review / handoff / execute are untouched (owner 2026-08-22: handoff is PERMITTED
//      ALWAYS, like review; ONLY hard is gated).
{
  const n = mark();
  const r = enforceApexGate(UNITS(), { strongTier: 'opus', afk: false });
  if (!shape(r)) fail('(A2) must return { plan: [], hardDeferred: [] }');
  else {
    if (repos(r.plan) !== 'r1,r3,r4')
      fail('(A2) without --afk exactly the hard units must be withheld and review/handoff/execute kept in order — got plan=' + repos(r.plan));
    if (repos(r.hardDeferred) !== 'r2,r5')
      fail('(A2) both hard units must be surfaced as deferred (never dropped) — got ' + repos(r.hardDeferred));
    for (const u of r.hardDeferred) {
      if (u.verdict !== 'hard') fail('(A2) deferred entry must carry its verdict — got ' + JSON.stringify(u));
      if (typeof u.gateReason !== 'string' || !u.gateReason.includes('--afk'))
        fail('(A2) each deferred hard unit needs a gateReason NAMING --afk — got ' + JSON.stringify(u.gateReason));
    }
    if (!r.plan.some(u => u.verdict === 'handoff'))
      fail('(A2) handoff must NOT be gated on --afk (owner 2026-08-22, settled)');
    if (!r.plan.some(u => u.verdict === 'review'))
      fail('(A2) review must NOT be gated on --afk');
    if (clean(n)) ok('(A2) no --afk → hard SURFACED-as-deferred naming --afk; review/handoff/execute dispatch');
  }
}

// (A3) non-apex tier: hard stays for Fable handoff-C5/review-step6 (pre-existing id:da26
//      behaviour, preserved) — and its reason must NOT blame --afk, which was supplied.
{
  const n = mark();
  const r = enforceApexGate(UNITS(), { strongTier: 'fable', afk: true });
  if (!shape(r)) fail('(A3) must return { plan: [], hardDeferred: [] }');
  else {
    if (repos(r.plan) !== 'r1,r3,r4') fail('(A3) non-apex tier must still withhold hard — got plan=' + repos(r.plan));
    if (r.hardDeferred.length !== 2) fail('(A3) both hard units must be surfaced — got ' + r.hardDeferred.length);
    for (const u of r.hardDeferred) {
      if (!/apex/i.test(u.gateReason || ''))
        fail('(A3) non-apex deferral reason must say APEX — got ' + JSON.stringify(u.gateReason));
      if (/--afk/.test(u.gateReason || ''))
        fail('(A3) non-apex deferral must NOT blame --afk (it was supplied) — self-contradicting message, the da51 class');
    }
    if (clean(n)) ok('(A3) non-apex tier defers hard with an apex reason, not an --afk reason');
  }
}

// (A4) neither: still exactly the hard units, still surfaced.
{
  const r = enforceApexGate(UNITS(), { strongTier: 'fable', afk: false });
  if (!shape(r) || repos(r.plan) !== 'r1,r3,r4' || r.hardDeferred.length !== 2)
    fail('(A4) fable + no --afk must withhold exactly the hard units');
  else ok('(A4) fable + no --afk → hard withheld, review/handoff/execute dispatch');
}

// (A5) da51 REGRESSION GUARD — the assertion that matters most.
//      The gate must NOT key on a model-id string. Feeding it the OLD pin, the NEW pin, or
//      no model id at all must produce IDENTICAL results: hard dispatches in every case.
{
  const base = { strongTier: 'opus', afk: true };
  const outs = [
    JSON.stringify(enforceApexGate(UNITS(), base)),
    JSON.stringify(enforceApexGate(UNITS(), { ...base, strongModel: 'claude-opus-4-8' })),
    JSON.stringify(enforceApexGate(UNITS(), { ...base, strongModel: 'claude-opus-5' })),
    JSON.stringify(enforceApexGate(UNITS(), { ...base, STRONG_MODEL: 'claude-opus-5' })),
  ];
  if (new Set(outs).size !== 1)
    fail('(A5) da51: the gate observes a model id — bumping the pin changes dispatch. Outputs: ' + outs.join(' | '));
  else if (!JSON.parse(outs[0]).plan.some(u => u.verdict === 'hard'))
    fail('(A5) da51: hard must dispatch at apex regardless of any model id supplied');
  else ok('(A5) da51: gate is model-id-blind — bumping the pin does NOT defer hard units');
}

// (A6) tolerant of an empty/absent round.
{
  const r = enforceApexGate([], { strongTier: 'opus', afk: false });
  if (!shape(r) || r.plan.length || r.hardDeferred.length) fail('(A6) empty round must yield empty plan + empty hardDeferred');
  else ok('(A6) empty round handled');
}

process.exit(bad ? 1 : 0);
EOF
  if node "$TMP/spec.mjs"; then
    pass "(A) apex-gate.mjs behavioural spec"
  else
    fail "(A) apex-gate.mjs behavioural spec FAILED (see PASS/FAIL lines above)"
  fi

  # (A7) purity: the gate module must not contain a model-id literal at all (da51).
  if grep -q 'claude-opus' "$GATE"; then
    fail "(A7) apex-gate.mjs contains a model-id literal — the gate must ask STRONG_TIER, not a model id (da51)"
  else
    pass "(A7) apex-gate.mjs carries no model-id literal"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# (B) relay-loop.js — wiring + the da51 de-coupling
# ─────────────────────────────────────────────────────────────────────────────
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
node --check "$JS" || fail "(B0) relay-loop.js is not valid JS"

grep -q 'enforceApexGate' "$JS" \
  || fail "(B1) relay-loop.js does not reference enforceApexGate — the gate is wired to nothing"
grep -q 'enforceApexGate' "$JS" && pass "(B1) relay-loop.js wires enforceApexGate into the dispatch path"

if grep -q 'claude-opus-4-8' "$JS"; then
  fail "(B2) relay-loop.js still contains the superseded pin 'claude-opus-4-8' (da51): $(grep -c 'claude-opus-4-8' "$JS") occurrence(s) at lines $(grep -n 'claude-opus-4-8' "$JS" | cut -d: -f1 | tr '\n' ' ')"
else
  pass "(B2) relay-loop.js carries no 'claude-opus-4-8' literal"
fi

grep -qF "const STRONG_MODEL = STRONG_TIER === 'opus' ? 'claude-opus-5' : 'claude-fable-5'" "$JS" \
  || fail "(B3) STRONG_MODEL is not pinned to 'claude-opus-5' (it is a pure OUTPUT value now)"
grep -qF "const STRONG_MODEL = STRONG_TIER === 'opus' ? 'claude-opus-5' : 'claude-fable-5'" "$JS" \
  && pass "(B3) STRONG_MODEL pinned to claude-opus-5"

# The HARD gate must not compare STRONG_MODEL at all — that coupling IS da51.
if grep -nE "STRONG_MODEL\s*(!==|===)\s*'claude-opus" "$JS" >/dev/null; then
  fail "(B4) relay-loop.js still gates on a STRONG_MODEL model-id comparison (da51 coupling): $(grep -nE "STRONG_MODEL\s*(!==|===)\s*'claude-opus" "$JS" | cut -d: -f1 | tr '\n' ' ')"
else
  pass "(B4) no STRONG_MODEL-vs-model-id comparison remains"
fi

# --afk must actually be READ from the normalized args object (today it has NO consumer).
grep -qE '\bA\.afk\b' "$JS" \
  || fail "(B5) relay-loop.js never reads A.afk — the flag stays INERT and the owner rule stays prose (id:7986)"
grep -qE '\bA\.afk\b' "$JS" && pass "(B5) relay-loop.js reads A.afk from the normalized args object"

# Deferred hard units must reach the RENDERED Queued surface carrying their gateReason
# (the id:8c85 class: a unit pulled from `actionable` and added to no section vanishes).
if grep -q 'gateReason' < <(grep -n 'hardDeferred.map' "$JS"); then
  pass "(B6) deferred hard units reach state.queued carrying gateReason"
else
  fail "(B6) the state.queued hardDeferred.map does not surface gateReason — deferred hard units render without the --afk reason (id:8c85 vanish class)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# (C) relay/SKILL.md — the doc currently teaches the OPPOSITE (id:7986)
# ─────────────────────────────────────────────────────────────────────────────
[[ -f "$SKILL" ]] || { echo "FAIL: relay/SKILL.md not found"; exit 1; }

if grep -q 'claude-opus-4-8' "$SKILL"; then
  fail "(C1) SKILL.md still documents the superseded pin 'claude-opus-4-8' (da51), lines: $(grep -n 'claude-opus-4-8' "$SKILL" | cut -d: -f1 | tr '\n' ' ')"
else
  pass "(C1) SKILL.md carries no 'claude-opus-4-8' literal"
fi

grep -q 'args\.afk' "$SKILL" \
  || fail "(C2) SKILL.md's Workflow-launch arg list does not document args.afk — the front door never passes it"
grep -q 'args\.afk' "$SKILL" && pass "(C2) SKILL.md documents args.afk pass-through"

# The HARD-execute gate paragraph must name --afk as a condition.
if grep -q -- '--afk' < <(awk '/Gate: `hard` is dispatched/,/^$/' "$SKILL"); then
  pass "(C3) SKILL.md's HARD-execute gate paragraph names --afk"
else
  fail "(C3) SKILL.md's HARD-execute gate paragraph does not mention --afk — it teaches the pre-2026-08-22 rule"
fi

# The --afk flags-table row must say it gates hard dispatch.
if grep -qi 'hard' < <(grep -E '^\| `--afk`' "$SKILL"); then
  pass "(C4) SKILL.md's --afk flags-table row documents the hard gate"
else
  fail "(C4) SKILL.md's --afk row still claims the flag only surfaces the /loop nudge — it now gates hard dispatch"
fi

# And it must state EXPLICITLY that review + handoff are NOT gated (owner 2026-08-22).
if grep -qiE '(review|handoff)[^.]*(regardless of|never gated|not gated)[^.]*--afk|--afk[^.]*(never gates|does not gate)[^.]*(review|handoff)' "$SKILL"; then
  pass "(C5) SKILL.md states review + handoff dispatch regardless of --afk"
else
  fail "(C5) SKILL.md never states that review and handoff dispatch REGARDLESS of --afk — the wording may be read as gating handoff too (owner 2026-08-22 settled: only hard is gated)"
fi

echo
if (( fails )); then
  echo "RED: $fails assertion group(s) failed (roadmap:7986 + id:da51 — one unit, one commit)"
  exit 1
fi
echo "ALL PASS: apex --afk hard gate + model-id decoupling (roadmap:7986, id:da51)"
