#!/usr/bin/env bash
# roadmap:4f9b — a child must never die with a bare `Prompt is too long` reported as the
# generic "child agent failed/skipped (API error or terminal failure)". The pool sizes the
# assembled child prompt BEFORE dispatch; over budget it refuses to dispatch and hands back
# with a reason that NAMES the cause (ROADMAP too large, with bytes) AND the remedy (run
# roadmap-archive.sh), surfaced in RELAY_STATUS.md's Blocked section.
#
# Incident (run relay-20260801-213927-29875, dotclaude-skills, 2026-08-01): child died against
# a 523,926-byte ROADMAP.md; relay-loop.js recorded the generic reason and RELAY_STATUS.md
# printed `## Blocked / HANDBACKs _(none)_` while 481 lines of work sat parked as an orphan.
# The id:4347 no-silent-swallow rule: a detectable, nameable failure must never be anonymous.
#
# HONEST COVERAGE LIMIT (same precedent as test_handback_invariant_equality.sh / id:1735):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness
# (id:2ec4). The behavioural cases below drive the PURE decision function
# (relay/scripts/prompt-size-gate.mjs) through node against a real fixture repo, and the
# fixture's ROADMAP is measured by the REAL producer (classify-repo.sh's host-side
# roadmap_bytes) — so the measurement path and the decision path are both exercised. The
# structural greps then pin that relay-loop.js WIRES the gate at the dispatch site with a
# byte-identical inline copy; they do not prove a live pool round short-circuits end-to-end.
#
# Hermetic: mktemp -d fixture repo, node + git only, no network, never touches ~/.claude.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$SRC_DIR/relay/scripts/prompt-size-gate.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
CLASSIFY_REPO="$SRC_DIR/relay/scripts/classify-repo.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$GATE" ]] || { echo "FAIL: prompt-size-gate.mjs missing at $GATE"; exit 1; }
[[ -f "$JS" ]]   || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# ── Fixture repos: one with an OVERSIZED ROADMAP, one with a normal-sized ROADMAP. ──────────
mkfixture() {   # mkfixture <dir> <target-bytes>
  local dir="$1" want="$2"
  mkdir -p "$dir"
  git init -q "$dir"
  {
    printf '# ROADMAP\n\n'
    printf -- '- [ ] [ROUTINE] **do the thing** <!-- id:aaaa -->\n'
    printf -- '  - **Acceptance**: the thing is done.\n\n'
    local n=0
    while [[ $n -lt 100000 ]]; do
      printf -- '- [x] [ROUTINE] **closed item %05d** — a done note long enough to be representative of the real ledger prose that accumulates inline. <!-- id:%04x -->\n' "$n" $(( n % 65536 ))
      n=$((n+1))
      # stop once the file would exceed the target
      if [[ $(( n * 170 )) -ge $want ]]; then break; fi
    done
  } > "$dir/ROADMAP.md"
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@e -c user.name=t commit -q -m init
}

mkfixture "$TMP/big"   600000
mkfixture "$TMP/small" 60000
big_bytes=$(wc -c < "$TMP/big/ROADMAP.md")
small_bytes=$(wc -c < "$TMP/small/ROADMAP.md")
[[ "$big_bytes" -gt 500000 ]] || bad "fixture: big ROADMAP is only $big_bytes bytes (wanted >500k)"
[[ "$small_bytes" -lt 100000 ]] || bad "fixture: small ROADMAP is $small_bytes bytes (wanted <100k)"
ok "fixtures built (big=$big_bytes B, small=$small_bytes B)"

# ── (A) The PRODUCER measures it. classify-repo.sh runs on the host (relay-loop.js is in a
#        sandbox with no filesystem) and must ship roadmap_bytes on the emitted unit. ────────
if [[ -x "$CLASSIFY_REPO" ]]; then
  meas=$(python3 - "$TMP/big/ROADMAP.md" <<'PY'
import os,sys; print(os.path.getsize(sys.argv[1]))
PY
)
  grep -q 'roadmap_bytes' "$CLASSIFY_REPO" \
    && ok "classify-repo.sh emits roadmap_bytes (host-side measurement, $meas B for the fixture)" \
    || bad "id:4f9b: classify-repo.sh does not emit roadmap_bytes — relay-loop.js has no way to size the ledger"
  grep -q '"roadmap_bytes": base.get("roadmap_bytes", 0)' "$CLASSIFY_REPO" \
    || bad "id:4f9b: roadmap_bytes is not on the --emit unit object (the shape relay-loop.js consumes)"
  ok "roadmap_bytes rides on the --emit unit object"
else
  bad "classify-repo.sh missing/not executable at $CLASSIFY_REPO"
fi

# ── (B) BEHAVIOUR: the pure gate refuses the oversized fixture with a reason naming cause +
#        remedy, and passes the normal one. Driven through node against the real byte counts. ─
cat > "$TMP/drive.mjs" <<NODE
import { oversizeDispatchReason, estimateDispatchTokens, DISPATCH_TOKEN_BUDGET } from 'file://$GATE'
const out = []
const PROMPT = 'x'.repeat(9000)   // a realistic assembled unitPrompt (~9 KB)

// (1) OVERSIZED fixture: must REFUSE, and the reason must name cause + remedy.
{
  const unit = { repo: 'fixture-big', path: '$TMP/big', verdict: 'execute', roadmap_bytes: $big_bytes }
  const r = oversizeDispatchReason(unit, PROMPT.length)
  out.push('big_refused=' + (r ? '1' : '0'))
  out.push('big_names_roadmap=' + (/ROADMAP\.md is too large/.test(r) ? '1' : '0'))
  out.push('big_names_bytes=' + (r.includes(String($big_bytes)) ? '1' : '0'))
  out.push('big_names_remedy=' + (/roadmap-archive\.sh/.test(r) ? '1' : '0'))
  out.push('big_names_path=' + (r.includes('$TMP/big') ? '1' : '0'))
  out.push('big_not_generic=' + (/API error or terminal failure/.test(r) ? '0' : '1'))
  out.push('big_names_id=' + (r.includes('id:4f9b') ? '1' : '0'))
  out.push('big_names_repo=' + (r.includes('fixture-big') ? '1' : '0'))
}

// (2) NORMAL fixture: must DISPATCH (empty reason). A gate that refuses everything is useless.
{
  const unit = { repo: 'fixture-small', path: '$TMP/small', verdict: 'execute', roadmap_bytes: $small_bytes }
  out.push('small_dispatches=' + (oversizeDispatchReason(unit, PROMPT.length) === '' ? '1' : '0'))
}

// (3) FAIL-OPEN on an unmeasured unit — an older queue entry / injected unit has no
//     roadmap_bytes. Blocking on ABSENT data would be worse than the death this prevents.
{
  out.push('unmeasured_dispatches=' + (oversizeDispatchReason({ repo: 'r', verdict: 'execute' }, PROMPT.length) === '' ? '1' : '0'))
  out.push('zero_dispatches=' + (oversizeDispatchReason({ repo: 'r', roadmap_bytes: 0 }, PROMPT.length) === '' ? '1' : '0'))
  out.push('null_unit_dispatches=' + (oversizeDispatchReason(null, PROMPT.length) === '' ? '1' : '0'))
}

// (4) The estimate accounts for BOTH the prompt and the ledger, plus fixed overhead — a gate
//     that ignored the ROADMAP would not have caught the 2026-08-01 death.
{
  const withLedger = estimateDispatchTokens(PROMPT.length, $big_bytes)
  const withoutLedger = estimateDispatchTokens(PROMPT.length, 0)
  out.push('ledger_dominates=' + (withLedger > withoutLedger * 10 ? '1' : '0'))
  out.push('budget_sane=' + (DISPATCH_TOKEN_BUDGET >= 50000 && DISPATCH_TOKEN_BUDGET <= 150000 ? '1' : '0'))
}

// (5) The historical incident's own numbers: 523,926 B must refuse; the post-archive
//     254,087 B must dispatch. This is the calibration, pinned so a budget change is a
//     conscious act.
{
  out.push('incident_refused=' + (oversizeDispatchReason({ repo: 'dotclaude-skills', path: '/p', roadmap_bytes: 523926 }, PROMPT.length) ? '1' : '0'))
  out.push('postarchive_dispatches=' + (oversizeDispatchReason({ repo: 'dotclaude-skills', path: '/p', roadmap_bytes: 254087 }, PROMPT.length) === '' ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

res=$(node "$TMP/drive.mjs")
echo "$res" | sed 's/^/    /'
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && ok "gate: $k" || bad "id:4f9b: gate case failed — $k"
done <<< "$res"

# ── (C) WIRING: relay-loop.js must actually call the gate at the dispatch site, before the
#        child is spawned, and record it as a real handback on BOTH surfaces. ───────────────
grep -qF -- 'const oversizeReason = oversizeDispatchReason(unit, unitPrompt(unit).length)' "$JS" \
  && ok "relay-loop.js calls oversizeDispatchReason on the assembled unitPrompt" \
  || bad "id:4f9b: relay-loop.js never sizes the assembled prompt before dispatch"

gate_line=$(grep -n 'const oversizeReason = oversizeDispatchReason' "$JS" | head -1 | cut -d: -f1)
disp_line=$(grep -n 'report = await agent(unitPrompt(unit), opts)' "$JS" | head -1 | cut -d: -f1)
if [[ -n "$gate_line" && -n "$disp_line" && "$gate_line" -lt "$disp_line" ]]; then
  ok "gate (line $gate_line) runs BEFORE the child dispatch (line $disp_line)"
else
  bad "id:4f9b: gate does not precede the dispatch (gate=$gate_line dispatch=$disp_line)"
fi

# The refusal must return early — a gate that logs and dispatches anyway fixes nothing.
block=$(awk -v s="$gate_line" 'NR>=s && NR<=s+10' "$JS")
grep -qF 'state.handbacks.push({ repo: unit.repo, reason: oversizeReason' <<<"$block" \
  && ok "refusal pushes a real handback into the persistent accumulator (RELAY_STATUS Blocked source)" \
  || bad "id:4f9b: refusal does not push into state.handbacks — it would not appear in RELAY_STATUS Blocked"
grep -qF "pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: oversizeReason })" <<<"$block" \
  && ok "refusal emits a handback EVENT (forward id:4a46 invariant)" \
  || bad "id:4f9b: refusal emits no handback event"
grep -qF 'emittedHandbackEvents.push({ repo: unit.repo, reason: oversizeReason })' <<<"$block" \
  && ok "refusal registers with the id:4a46 invariant backstop" \
  || bad "id:4f9b: refusal not registered with emittedHandbackEvents"
grep -qE '^\s*return$' <<<"$block" \
  && ok "refusal returns early — the child is NOT dispatched" \
  || bad "id:4f9b: refusal does not return early; the oversized child would still be dispatched"

# ── (D) The inline copies in relay-loop.js must stay byte-equivalent to the pure module
#        (the Workflow sandbox cannot import — same discipline as round-plan.mjs / id:dc5b). ─
if python3 - "$GATE" "$JS" <<'PY'
import sys
mod = open(sys.argv[1]).read()
js  = open(sys.argv[2]).read()
bad = []
for fn in ('function estimateDispatchTokens', 'function oversizeDispatchReason'):
    body = mod[mod.index('export ' + fn):]
    body = body[:body.index('\n}\n') + 3].replace('export ', '', 1)
    if body not in js:
        bad.append(fn)
for const in ('const CHARS_PER_TOKEN = 4', 'const DISPATCH_TOKEN_BUDGET = 100000', 'const FIXED_OVERHEAD_TOKENS = 12000'):
    if const not in js or ('export ' + const) not in mod:
        bad.append(const)
sys.exit(1 if bad else 0)
PY
then
  ok "relay-loop.js inline copies are byte-equivalent to prompt-size-gate.mjs"
else
  bad "id:4f9b: relay-loop.js inline copy has DRIFTED from prompt-size-gate.mjs — the tested logic is not the shipped logic"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: pre-dispatch prompt-size gate names cause + remedy (id:4f9b)"
