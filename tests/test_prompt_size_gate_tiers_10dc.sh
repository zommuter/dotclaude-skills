#!/usr/bin/env bash
# id:10dc — the dispatch-token budget is PER TIER, and the fixed-overhead constant is the
# MEASURED 65,000 rather than the unmeasured 12,000 it carried until 2026-08-27.
#
# No `# roadmap:` header on purpose: there is NO ROADMAP.md item for this change — it is an
# owner-ratified constants correction, not a queued roadmap unit — so per tests/run-tests.sh
# conventions the header is omitted and every failure here always counts.
#
# WHAT WAS FALSIFIED. prompt-size-gate.mjs carried, as its reason for a single flat budget:
# "ALL FOUR carry a 200,000-token context window — no dispatched tier has a different one …
# so a tier-keyed budget table would hold four identical rows and buy nothing. … If a tier with
# a different window is ever dispatched, THIS is the line to split per tier". A census of
# 28,365 transcripts (API `usage` sums of input + cache_creation + cache_read; ledger refs
# id:7829 for the Sonnet drop, id:10dc for the constants) measured that premise FALSE:
#   * claude-opus-5   — max 378,108 tok direct / 234,302 in-pool; ZERO `Prompt is too long`
#                       failures across the whole corpus.
#   * claude-sonnet-5 — max 379,086 tok (2026-07) falling to 178,310 (2026-08), with 46 genuine
#                       failures ALL inside 170,875–178,310 — a ~200k window minus the ~24k
#                       output reserve.
# Opus's TRUE ceiling remains UNKNOWN: 378,108 is the largest context ever DEMANDED of it, not
# a measured limit. 300,000 is a cap chosen below the largest observed success.
#
# RATIFIED (owner, 2026-08-27): Sonnet/execute → 100,000; Opus/review+hard+handoff → 300,000;
# FIXED_OVERHEAD_TOKENS → 65,000.
#
# THE FABLE CASE WAS RESOLVED BY THE OWNER 2026-08-27: "fable same as opus" — claude-fable-5
# gets the 300,000 STRONG-tier budget. Case (C) now pins THAT. The ratification the previous
# revision of this comment demanded ("an owner decision to make explicitly, not a fix to apply
# by analogy with Opus") is exactly what happened, and the branch is explicit in both copies
# rather than a widened Opus `startsWith`.
#
# THE OVERRIDDEN EVIDENCE IS STILL LIVE, so case (C) also documents it: Fable shows max observed
# context 429,064 tok yet one genuine `Prompt is too long` at 177,602 tok. If that death was a
# true ceiling rather than a one-off, 300,000 trades a loud refusal for a silent mid-work death.
# A Fable `Prompt is too long` is the evidence the ruling lacked — if one appears, re-open the
# ruling; do NOT quietly re-tighten this test instead.
#
# HONEST COVERAGE LIMIT (same precedent as tests/test_prompt_size_gate_4f9b.sh, id:2ec4):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness. The
# behavioural cases drive the PURE module through node; the structural checks pin that
# relay-loop.js resolves the model BEFORE the gate, passes that tier's budget, and reuses the
# same resolution for the actual dispatch. None of that proves a live pool round end-to-end.
#
# Hermetic: mktemp -d, node only, no network, no git, never touches ~/.claude.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$SRC_DIR/relay/scripts/prompt-size-gate.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$GATE" ]] || { echo "FAIL: prompt-size-gate.mjs missing at $GATE"; exit 1; }
[[ -f "$JS"   ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/drive.mjs" <<NODE
import {
  oversizeDispatchReason, estimateDispatchTokens, dispatchBudgetForModel,
  DISPATCH_TOKEN_BUDGET, OPUS_DISPATCH_TOKEN_BUDGET, FIXED_OVERHEAD_TOKENS, CHARS_PER_TOKEN,
} from 'file://$GATE'
const out = []
const P = 9000   // a realistic assembled unitPrompt (~9 KB)

// ── (A) THE CONSTANTS. Pinned as literals so a change is a conscious, reviewed act. ─────────
out.push('overhead_is_65000=' + (FIXED_OVERHEAD_TOKENS === 65000 ? '1' : '0'))
out.push('sonnet_budget_is_100000=' + (DISPATCH_TOKEN_BUDGET === 100000 ? '1' : '0'))
out.push('opus_budget_is_300000=' + (OPUS_DISPATCH_TOKEN_BUDGET === 300000 ? '1' : '0'))
out.push('opus_budget_is_3x_sonnet=' + (OPUS_DISPATCH_TOKEN_BUDGET === DISPATCH_TOKEN_BUDGET * 3 ? '1' : '0'))
// The old constant must be GONE: 12,000 was never measured, and the measured preamble is ~4.9x it.
out.push('old_12000_overhead_is_gone=' + (FIXED_OVERHEAD_TOKENS !== 12000 ? '1' : '0'))

// ── (B) THE BUDGET IS KEYED OFF THE RESOLVED MODEL, not the verdict string. ─────────────────
out.push('sonnet_model_gets_sonnet_budget=' + (dispatchBudgetForModel('sonnet') === DISPATCH_TOKEN_BUDGET ? '1' : '0'))
out.push('opus_model_gets_opus_budget=' + (dispatchBudgetForModel('claude-opus-5') === OPUS_DISPATCH_TOKEN_BUDGET ? '1' : '0'))
// FAIL-SAFE, not fail-open: an unknown / absent / malformed model gets the CONSERVATIVE cap.
// A budget is not measurement data — guessing HIGH here would convert a loud, lossless refusal
// into a silent mid-work death, which is the one trade prompt-size-gate.mjs item (6) forbids.
for (const m of ['', 'haiku', 'claude-sonnet-5', 'sonnet[1m]', 'gpt-nonsense'])
  out.push('unknown_model_' + (m || 'empty') + '_is_conservative=' + (dispatchBudgetForModel(m) === DISPATCH_TOKEN_BUDGET ? '1' : '0'))
out.push('null_model_is_conservative=' + (dispatchBudgetForModel(null) === DISPATCH_TOKEN_BUDGET ? '1' : '0'))
out.push('undefined_model_is_conservative=' + (dispatchBudgetForModel(undefined) === DISPATCH_TOKEN_BUDGET ? '1' : '0'))

// ── (C) FABLE — PARITY WITH OPUS, OWNER-RULED 2026-08-27. ───────────────────────────────────
// claude-fable-5 is dispatched for review/hard/handoff whenever STRONG_TIER=fable. The owner
// ruled "fable same as opus", so it gets the 300,000 STRONG-tier budget via its OWN branch —
// never a widened Opus `startsWith`. The overridden evidence (429,064 tok observed; one genuine
// failure at 177,602 tok) is recorded in both module copies; see this file's header.
out.push('fable_gets_strong_budget=' + (dispatchBudgetForModel('claude-fable-5') === OPUS_DISPATCH_TOKEN_BUDGET ? '1' : '0'))
out.push('fable_is_not_sonnet_capped=' + (dispatchBudgetForModel('claude-fable-5') !== DISPATCH_TOKEN_BUDGET ? '1' : '0'))
// The branch must be EXPLICIT, not a widened Opus prefix test: a fable id must not match via
// any 'claude-opus-' rule, and an unrelated strong-sounding model must still be conservative.
out.push('unknown_strong_model_still_conservative=' + (dispatchBudgetForModel('claude-sonnet-5') === DISPATCH_TOKEN_BUDGET ? '1' : '0'))
// ...and parity must hold END-TO-END, not just in the lookup: the same strong unit that
// dispatches on Opus must now dispatch on Fable too, at the identical payload.
{
  const u = { repo: 'fixture', path: '/p/x', verdict: 'review',
              roadmap_bytes: 150000, todo_bytes: 150000 }
  const fable = oversizeDispatchReason(u, P, dispatchBudgetForModel('claude-fable-5'))
  const opus  = oversizeDispatchReason(u, P, dispatchBudgetForModel('claude-opus-5'))
  out.push('fable_strong_unit_dispatches=' + (fable === '' ? '1' : '0'))
  out.push('same_unit_dispatches_on_opus=' + (opus === '' ? '1' : '0'))
  out.push('fable_and_opus_agree=' + (fable === opus ? '1' : '0'))
}
// A unit too big for BOTH strong tiers must still be refused on Fable, quoting the strong cap —
// parity must not become "Fable is never refused".
{
  const huge = { repo: 'fixture', path: '/p/x', verdict: 'review',
                 roadmap_bytes: 900000, todo_bytes: 900000 }
  const fable = oversizeDispatchReason(huge, P, dispatchBudgetForModel('claude-fable-5'))
  out.push('oversize_fable_unit_still_refused=' + (fable ? '1' : '0'))
  out.push('fable_refusal_quotes_strong_cap=' + (fable.includes(String(OPUS_DISPATCH_TOKEN_BUDGET) + ' tok dispatch budget') ? '1' : '0'))
}

// ── (D) BEHAVIOURAL SPLIT — the same unit, sized against each tier. ─────────────────────────
// Chosen to sit strictly between the two caps: 600,000 B of ledgers ⇒ ~217,250 tok.
{
  const RM = 300000, TD = 300000
  const est = estimateDispatchTokens(P, RM, TD)
  out.push('between_the_caps=' + (est > DISPATCH_TOKEN_BUDGET && est <= OPUS_DISPATCH_TOKEN_BUDGET ? '1' : '0'))
  const exec = { repo: 'r', path: '/p', verdict: 'execute', roadmap_bytes: RM, todo_bytes: TD }
  const rev  = { repo: 'r', path: '/p', verdict: 'review',  roadmap_bytes: RM, todo_bytes: TD }
  out.push('execute_refused_at_sonnet_budget=' +
    (oversizeDispatchReason(exec, P, dispatchBudgetForModel('sonnet')) ? '1' : '0'))
  out.push('review_dispatches_at_opus_budget=' +
    (oversizeDispatchReason(rev, P, dispatchBudgetForModel('claude-opus-5')) === '' ? '1' : '0'))
  // The refusal must QUOTE the tier's own cap — an operator told "over the 100000 tok budget"
  // for a unit that was actually sized at 300,000 is being sent to fix the wrong thing.
  out.push('refusal_quotes_the_tier_cap=' +
    (oversizeDispatchReason(exec, P, dispatchBudgetForModel('sonnet')).includes('100000 tok dispatch budget') ? '1' : '0'))
  // A payload over BOTH caps is refused on both.
  const huge = { ...rev, roadmap_bytes: 900000, todo_bytes: 900000 }
  out.push('huge_refused_on_both=' +
    (oversizeDispatchReason(huge, P, DISPATCH_TOKEN_BUDGET) && oversizeDispatchReason(huge, P, OPUS_DISPATCH_TOKEN_BUDGET) ? '1' : '0'))
}

// ── (E) THE DEFAULT IS STILL THE SONNET CAP. An UNPASSED budget must never silently widen. ──
{
  const u = { repo: 'r', path: '/p', verdict: 'review', roadmap_bytes: 300000, todo_bytes: 300000 }
  out.push('unpassed_budget_defaults_to_sonnet=' + (oversizeDispatchReason(u, P) ? '1' : '0'))
  out.push('unpassed_budget_quotes_sonnet_cap=' + (oversizeDispatchReason(u, P).includes('100000 tok dispatch budget') ? '1' : '0'))
}

// ── (F) FAIL-OPEN is UNCHANGED by the split — an unmeasured unit never trips either tier. ───
for (const b of [DISPATCH_TOKEN_BUDGET, OPUS_DISPATCH_TOKEN_BUDGET]) {
  out.push('unmeasured_fails_open_at_' + b + '=' + (oversizeDispatchReason({ repo: 'r', verdict: 'execute' }, P, b) === '' ? '1' : '0'))
  out.push('null_unit_fails_open_at_' + b + '=' + (oversizeDispatchReason(null, P, b) === '' ? '1' : '0'))
}

// ── (G) THE OVERHEAD CONSTANT IS ACTUALLY APPLIED, not merely declared. ─────────────────────
{
  // A ZERO-byte unit still costs the full preamble.
  out.push('empty_unit_costs_the_preamble=' + (estimateDispatchTokens(0, 0, 0) === FIXED_OVERHEAD_TOKENS ? '1' : '0'))
  // And the correction TIGHTENED the gate: a payload that fitted under a 12,000 overhead but
  // not under 65,000 must now refuse. 150,000 B ⇒ 37,500 tok of ledger: 49,500 under the old
  // constant, 102,500 under the corrected one.
  const B = 150000
  out.push('tightened_by_the_correction=' + (
    Math.round(B / CHARS_PER_TOKEN) + 12000 <= DISPATCH_TOKEN_BUDGET &&
    estimateDispatchTokens(0, B, 0) > DISPATCH_TOKEN_BUDGET ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

res=$(node "$TMP/drive.mjs" 2>&1) || { echo "BAD: node driver failed:"; echo "$res" | sed 's/^/    /'; fail=$((fail+1)); res=""; }
[[ -n "$res" ]] && echo "$res" | sed 's/^/    /'
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && ok "gate: $k" || bad "id:10dc: gate case failed — $k"
done <<< "$res"

# ── (H) WIRING: relay-loop.js must resolve the model ONCE, BEFORE the gate, pass that tier's
#        budget, and reuse the SAME resolution for the real dispatch. Two copies of the
#        verdict→model mapping could drift and let the gate size a unit against a tier it is
#        not dispatched on — which is the whole reason the budget is model-keyed. ────────────
grep -qF "const unitModel = unit.verdict === 'execute' ? 'sonnet' : STRONG_MODEL" "$JS" \
  && ok "relay-loop.js resolves the dispatch model once into unitModel" \
  || bad "id:10dc: relay-loop.js has no single unitModel resolution"
grep -qF 'oversizeDispatchReason(unit, unitPrompt(unit).length, dispatchBudgetForModel(unitModel))' "$JS" \
  && ok "the gate is called with THIS unit's tier budget, keyed off the resolved model" \
  || bad "id:10dc: the gate is not keyed off the resolved model"
grep -qF 'opts.model = unitModel' "$JS" \
  && ok "the dispatch reuses the same unitModel the gate was keyed off" \
  || bad "id:10dc: opts.model no longer reuses unitModel — a second verdict→model copy can drift"

model_line=$(head -1 < <(grep -n "const unitModel = unit.verdict === 'execute'" "$JS") | cut -d: -f1)
gate_line=$(head -1 < <(grep -n 'const oversizeReason = oversizeDispatchReason' "$JS") | cut -d: -f1)
opts_line=$(head -1 < <(grep -n 'opts.model = unitModel' "$JS") | cut -d: -f1)
if [[ -n "$model_line" && -n "$gate_line" && -n "$opts_line" && "$model_line" -lt "$gate_line" && "$gate_line" -lt "$opts_line" ]]; then
  ok "ordering holds: unitModel ($model_line) → gate ($gate_line) → dispatch ($opts_line)"
else
  bad "id:10dc: model/gate/dispatch ordering broken (model=$model_line gate=$gate_line opts=$opts_line)"
fi

# The verdict→model mapping must exist EXACTLY ONCE in the dispatch path.
n_map=$(grep -cF "unit.verdict === 'execute' ? 'sonnet' : STRONG_MODEL" "$JS")
[[ "$n_map" -eq 1 ]] \
  && ok "the verdict→model mapping appears exactly once in relay-loop.js" \
  || bad "id:10dc: verdict→model mapping appears $n_map times — a second copy can drift"

# ── (I) The inline copies must stay byte-identical (dispatchBudgetForModel included). ───────
if python3 - "$GATE" "$JS" <<'PY'
import sys
mod = open(sys.argv[1]).read(); js = open(sys.argv[2]).read()
missing = []
for fn in ('function dispatchBudgetForModel', 'function estimateDispatchTokens',
           'function oversizeDispatchReason', 'function countedLedgersFor',
           'function sliceLedgerHeadroom'):
    i = mod.find('export ' + fn)
    if i < 0:
        missing.append(fn + ' (absent from module)'); continue
    body = mod[i:]
    body = body[:body.index('\n}\n') + 3].replace('export ', '', 1)
    if body not in js:
        missing.append(fn + ' (inline copy drifted)')
for const in ('const DISPATCH_TOKEN_BUDGET = 100000',
              'const OPUS_DISPATCH_TOKEN_BUDGET = 300000',
              'const FIXED_OVERHEAD_TOKENS = 65000'):
    if const not in js or ('export ' + const) not in mod:
        missing.append(const)
if missing:
    sys.stderr.write('drifted/absent: ' + ', '.join(missing) + '\n')
    sys.exit(1)
PY
then
  ok "relay-loop.js inline copies + per-tier constants stay byte-identical to prompt-size-gate.mjs"
else
  bad "id:10dc: relay-loop.js inline copy has DRIFTED from prompt-size-gate.mjs"
fi

# ── (J) THE FALSIFIED COMMENT MUST BE GONE. Its premise ("four identical rows") is measured
#        false and its own pre-registered split trigger has fired; leaving it in place would
#        hand the next reader a ratified-looking reason to collapse the table again. ─────────
# The old premise may survive ONLY as a quoted, explicitly-superseded record (that is the
# honest way to retire a ratified-looking claim) — never as a live reason, and never twice.
n_rows=$(grep -c 'four identical rows' "$GATE")
if [[ "$n_rows" -eq 0 ]]; then
  bad "id:10dc: prompt-size-gate.mjs deleted the old premise outright — quote it as superseded so the next reader sees WHAT was falsified"
elif [[ "$n_rows" -eq 1 ]] && grep -q 'MEASURED FALSE' "$GATE"; then
  ok "the 'four identical rows' premise survives once, quoted and marked MEASURED FALSE"
else
  bad "id:10dc: the falsified premise appears $n_rows time(s) and/or is not marked MEASURED FALSE — it still reads as a live reason"
fi
grep -q 'pre-registered trigger' "$GATE" \
  && ok "the module records that the comment's OWN pre-registered split trigger fired" \
  || bad "id:10dc: the module does not record that the pre-registered trigger fired"
grep -q '28,365' "$GATE" \
  && ok "prompt-size-gate.mjs records the 28,365-transcript measurement that replaced it" \
  || bad "id:10dc: the replacement measurement is not recorded in prompt-size-gate.mjs"
grep -qi 'ceiling.*UNKNOWN\|UNKNOWN' "$GATE" \
  && ok "prompt-size-gate.mjs records honestly that Opus's true ceiling is UNKNOWN" \
  || bad "id:10dc: prompt-size-gate.mjs does not record that 378,108 is a DEMAND, not a limit"
grep -q 'FABLE — OWNER RULED' "$GATE" \
  && ok "prompt-size-gate.mjs records the Fable ruling" \
  || bad "id:10dc: the Fable ruling is not recorded in prompt-size-gate.mjs"
grep -q 'FABLE — OWNER RULED' "$JS" \
  && ok "the Fable ruling is recorded at the inline copy too" \
  || bad "id:10dc: the Fable ruling is not recorded in relay-loop.js"
# The ruling OVERRODE a contrary measurement. Both copies must keep that data point visible, so
# a future reader can re-open the ruling on evidence instead of rediscovering the conflict.
for f in "$GATE" "$JS"; do
  grep -q '177,602' "$f" \
    && ok "the overridden Fable failure datum survives in $(basename "$f")" \
    || bad "id:10dc: $(basename "$f") drops the 177,602 datum the Fable ruling overrode"
done

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: the dispatch-token budget is per-tier and the overhead constant is 65000 (id:10dc)"
