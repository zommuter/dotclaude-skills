#!/usr/bin/env bash
# roadmap:7c5f — the id:b018 prompt-size gate counts ROADMAP.md + TODO.md and DELIBERATELY
# excludes REVIEW_ME.md + RELAY_LOG.md, reasoning that counting them "would refuse execute
# units on bytes they never read". That reasoning is correct for execute units and WRONG for
# review units: a review child is contractually required to read BOTH (the trust-but-verify
# procedure, and the single-id-two-views tick-back). So a review unit can clear the budget and
# die with `Prompt is too long` — the exact loderite-by-326-tokens pathology id:b018 was filed
# to fix, still live for one verdict class, with no detector.
#
# THE FIX: the counted ledger set is VERDICT-DEPENDENT. REVIEW_ME.md + RELAY_LOG.md are added
# when `unit.verdict === 'review'` and are NOT counted otherwise, so no execute/hard/handoff
# unit's verdict changes. Interaction with id:7575/id:35b7 is preserved: a unit carrying a
# `slice_path` is sized on the SLICE and counts NO ledgers at all — review units included.
#
# HONEST COVERAGE LIMIT (same precedent as tests/test_prompt_size_gate_4f9b.sh, id:2ec4):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness. The
# behavioural cases drive the PURE decision module relay/scripts/prompt-size-gate.mjs through
# node; the producer half is checked against the real classify-repo.sh on a fixture repo; a
# structural check then pins that relay-loop.js's INLINE copy is byte-identical. None of that
# proves a live pool round short-circuits end-to-end.
#
# Hermetic: mktemp -d fixture repo, node + git + python3 only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/relay/scripts/prompt-size-gate.mjs"
JS="$ROOT/relay/scripts/relay-loop.js"
CR="$ROOT/relay/scripts/classify-repo.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$GATE" ]] || { echo "FAIL: prompt-size-gate.mjs missing at $GATE"; exit 1; }
[[ -f "$JS"   ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }
[[ -x "$CR"   ]] || { echo "FAIL: classify-repo.sh missing/not executable at $CR"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_WORKTREE_BASE="$TMP/wt"
export RELAY_TOML="$TMP/relay.toml"; printf '[repos]\n' > "$RELAY_TOML"

# ── (A) PRODUCER: classify-repo.sh must measure the two review-only ledgers on the HOST,
#        on the same fail-open-on-0 terms as roadmap_bytes/todo_bytes. ───────────────────────
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t
printf '# ROADMAP\n\n- [ ] [ROUTINE] do the thing <!-- id:1111 -->\n' > "$R/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] something <!-- id:2222 -->\n' > "$R/TODO.md"
printf '# REVIEW_ME\n\n- [ ] @needs-auth a box the review child must read <!-- id:3333 -->\n' > "$R/REVIEW_ME.md"
printf '# Relay log\n\n## 2026-08-21 — executor (sonnet)\n\nWorked id:1111.\n' > "$R/RELAY_LOG.md"
git -C "$R" add -A
git -C "$R" commit -qm init

rme_real=$(wc -c < "$R/REVIEW_ME.md")
rlog_real=$(wc -c < "$R/RELAY_LOG.md")
unit_json="$("$CR" --emit unit --repo repo --path "$R" 2>/dev/null || true)"
if [[ -n "$unit_json" ]]; then
  got_rme=$(printf '%s' "$unit_json"  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("review_me_bytes","<<MISSING>>"))')
  got_rlog=$(printf '%s' "$unit_json" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("relay_log_bytes","<<MISSING>>"))')
  [[ "$got_rme" == "$rme_real" ]] \
    && ok "classify-repo.sh --emit unit ships review_me_bytes=$got_rme" \
    || bad "id:7c5f: classify-repo.sh does not ship review_me_bytes (got '$got_rme', file is $rme_real B)"
  [[ "$got_rlog" == "$rlog_real" ]] \
    && ok "classify-repo.sh --emit unit ships relay_log_bytes=$got_rlog" \
    || bad "id:7c5f: classify-repo.sh does not ship relay_log_bytes (got '$got_rlog', file is $rlog_real B)"
else
  bad "id:7c5f: classify-repo.sh --emit unit produced no JSON for the fixture"
fi

# Absent files ⇒ 0 ⇒ fail-open, exactly like an absent ROADMAP/TODO.
R2="$TMP/repo-bare"; mkdir -p "$R2"
git -C "$R2" init -q
git -C "$R2" config user.email t@e
git -C "$R2" config user.name t
printf '# ROADMAP\n\n- [ ] [ROUTINE] x <!-- id:4444 -->\n' > "$R2/ROADMAP.md"
git -C "$R2" add -A
git -C "$R2" commit -qm init
bare_json="$("$CR" --emit unit --repo repo-bare --path "$R2" 2>/dev/null || true)"
if [[ -n "$bare_json" ]]; then
  z=$(printf '%s' "$bare_json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("%s/%s"%(d.get("review_me_bytes","<<MISSING>>"),d.get("relay_log_bytes","<<MISSING>>")))')
  [[ "$z" == "0/0" ]] \
    && ok "absent REVIEW_ME.md/RELAY_LOG.md measure as 0/0 (fail-open, never blocks)" \
    || bad "id:7c5f: absent review ledgers must measure 0/0, got '$z'"
else
  bad "id:7c5f: classify-repo.sh --emit unit produced no JSON for the bare fixture"
fi

# ── (B) BEHAVIOUR: the pure gate. ────────────────────────────────────────────────────────────
cat > "$TMP/drive.mjs" <<NODE
import { oversizeDispatchReason, sliceLedgerHeadroom, estimateDispatchTokens, DISPATCH_TOKEN_BUDGET } from 'file://$GATE'
const out = []
const P = 1000

// Sizing: budget 100000 tok, 12000 tok fixed overhead ⇒ ~352,000 B of countable payload.
// ROADMAP + TODO alone sit UNDER it; adding the two review-only ledgers pushes OVER.
const RM = 150000, TD = 180000, RME = 60000, RLOG = 40000
const base = { repo: 'fixture', path: '/p/x', roadmap_bytes: RM, todo_bytes: TD,
               review_me_bytes: RME, relay_log_bytes: RLOG }

// (0) The trap, documented: the two ledgers the OLD gate counted are under budget on their own.
out.push('two_ledgers_under_budget=' + (estimateDispatchTokens(P, RM, TD) <= DISPATCH_TOKEN_BUDGET ? '1' : '0'))

// (1) THE FIX — a REVIEW unit is REFUSED once its review-only ledgers are counted.
{
  const r = oversizeDispatchReason({ ...base, verdict: 'review' }, P)
  out.push('review_refused=' + (r ? '1' : '0'))
  out.push('review_reason_names_review_me=' + (r.includes('REVIEW_ME.md') && r.includes(String(RME)) ? '1' : '0'))
  out.push('review_reason_names_relay_log=' + (r.includes('RELAY_LOG.md') && r.includes(String(RLOG)) ? '1' : '0'))
}

// (2) NO VERDICT CHANGE for anything else: the IDENTICAL unit as execute/hard/handoff still
//     dispatches. This is the id:b018 reasoning the fix must preserve, not overturn.
for (const v of ['execute', 'hard', 'handoff']) {
  out.push(v + '_still_dispatches=' + (oversizeDispatchReason({ ...base, verdict: v }, P) === '' ? '1' : '0'))
}
// A unit with NO verdict at all is not a review unit either.
out.push('unverdicted_still_dispatches=' + (oversizeDispatchReason({ ...base }, P) === '' ? '1' : '0'))

// (3) id:7575/id:35b7 INTERACTION — a review unit WITH a slice is sized on the SLICE and counts
//     NO ledgers (review-only ones included): no double-count, and it dispatches.
{
  const u = { ...base, verdict: 'review', slice_path: '/tmp/slice.md', slice_bytes: 4000 }
  out.push('sliced_review_dispatches=' + (oversizeDispatchReason(u, P) === '' ? '1' : '0'))
  // and a sliced review unit whose SLICE is genuinely huge is refused ON THE SLICE, naming it
  const big = oversizeDispatchReason({ ...u, slice_bytes: 500000 }, P)
  out.push('sliced_review_sized_on_slice=' + (big.includes('id:35b7') && big.includes('500000') ? '1' : '0'))
  out.push('sliced_review_does_not_count_ledgers=' + (!big.includes(String(RME)) && !big.includes(String(RLOG)) && !big.includes(String(TD)) ? '1' : '0'))
}

// (4) FAIL-OPEN preserved: an unmeasured review unit can never trip the gate.
out.push('unmeasured_review_fails_open=' + (oversizeDispatchReason({ repo: 'r', path: '/p', verdict: 'review' }, P) === '' ? '1' : '0'))
// ...and a review unit measured ONLY on the review-only ledgers is still sizeable.
out.push('review_only_ledgers_sizeable=' + (oversizeDispatchReason(
  { repo: 'r', path: '/p', verdict: 'review', review_me_bytes: 900000 }, P) ? '1' : '0'))

// (5) id:7c5f acceptance 4 — sliceLedgerHeadroom's "largest ledger" must consider the
//     review-only ledgers for a REVIEW unit, else the brief tells a review child a full read is
//     affordable while the two files it MUST read are uncounted.
{
  const u = { verdict: 'review', slice_bytes: 4000, roadmap_bytes: 20000, todo_bytes: 30000, review_me_bytes: 800000 }
  const h = sliceLedgerHeadroom(u)
  out.push('headroom_review_largest_is_review_me=' + (h.largestLedgerName === 'REVIEW_ME.md' ? '1' : '0'))
  out.push('headroom_review_not_affordable=' + (h.affordable === false ? '1' : '0'))
  const he = sliceLedgerHeadroom({ ...u, verdict: 'execute' })
  out.push('headroom_execute_ignores_review_ledgers=' + (he.largestLedgerName === 'TODO.md' && he.affordable === true ? '1' : '0'))
}

// (6) The budget literal is untouched (test_prompt_size_gate_4f9b.sh pins it in both copies).
out.push('budget_unchanged=' + (DISPATCH_TOKEN_BUDGET === 100000 ? '1' : '0'))

console.log(out.join('\n'))
NODE

res=$(node "$TMP/drive.mjs" 2>&1) || { echo "BAD: node driver failed:"; echo "$res" | sed 's/^/    /'; fail=$((fail+1)); res=""; }
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && ok "gate: $k" || bad "id:7c5f: gate case failed — $k"
done <<< "$res"

# ── (C) WIRING: relay-loop.js's inline copy must learn the same inputs and stay byte-identical.
grep -q 'review_me_bytes' "$JS" \
  && ok "relay-loop.js's inline gate knows about review_me_bytes" \
  || bad "id:7c5f: relay-loop.js inline copy never counts REVIEW_ME.md — the tested logic is not the shipped logic"
grep -q 'relay_log_bytes' "$JS" \
  && ok "relay-loop.js's inline gate knows about relay_log_bytes" \
  || bad "id:7c5f: relay-loop.js inline copy never counts RELAY_LOG.md"

if python3 - "$GATE" "$JS" <<'PY'
import sys
mod = open(sys.argv[1]).read(); js = open(sys.argv[2]).read()
missing = []
for fn in ('function countedLedgersFor', 'function estimateDispatchTokens',
           'function oversizeDispatchReason', 'function sliceLedgerHeadroom'):
    i = mod.find('export ' + fn)
    if i < 0:
        missing.append(fn + ' (absent from module)'); continue
    body = mod[i:]
    body = body[:body.index('\n}\n') + 3].replace('export ', '', 1)
    if body not in js:
        missing.append(fn + ' (inline copy drifted)')
if missing:
    sys.stderr.write('drifted/absent: ' + ', '.join(missing) + '\n')
    sys.exit(1)
PY
then
  ok "relay-loop.js inline copies stay byte-identical to prompt-size-gate.mjs"
else
  bad "id:7c5f: relay-loop.js inline copy has DRIFTED from prompt-size-gate.mjs"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: the prompt-size gate's counted ledger set is verdict-dependent (id:7c5f)"
