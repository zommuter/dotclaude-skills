#!/usr/bin/env bash
# roadmap:b018 — the id:4f9b prompt-size gate UNDER-COUNTS by ~50%: it sizes ONLY ROADMAP.md,
# while the assembled child prompt also embeds TODO.md. The gate must count EVERY ledger the
# child prompt actually carries.
#
# Incident (loderite, run relay-20260820-180056-4594, measured 2026-08-21):
#   ROADMAP.md = 350,698 B → estimate 99,674 tok → ALLOW, under the 100,000 budget by 326.
#   TODO.md    = 392,043 B is embedded in the child prompt too and is NOT in the estimate.
#   Counting both: 197,685 tok, ~2x budget.
# The child was dispatched, died with `Prompt is too long`, and was recorded as the generic
# `child agent failed/skipped (API error or terminal failure)` — the EXACT string id:4f9b was
# built to eliminate after the 2026-08-01 dotclaude-skills incident. The guard was WIRED and
# fired correctly against a model that is wrong: `grep -c` reassurance ([[relay-builtgreen-but-
# unreferenced]]) would not have caught this — the estimate's INPUTS are the thing to verify.
#
# HONEST COVERAGE LIMIT (same precedent as tests/test_prompt_size_gate_4f9b.sh, id:2ec4):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness. The
# behavioural cases below drive the PURE decision module relay/scripts/prompt-size-gate.mjs
# through node; the producer half is checked against the real classify-repo.sh on a fixture
# repo; a structural grep then pins that relay-loop.js's byte-identical INLINE copy learned
# the same input. None of that proves a live pool round short-circuits end-to-end.
#
# EXPECTED-RED while roadmap:b018 is unticked.
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

# ── (A) PRODUCER: classify-repo.sh must measure TODO.md the same way it measures ROADMAP.md
#        and ship `todo_bytes` on the emitted unit, beside `roadmap_bytes`. Without the
#        measurement there is nothing for the gate to count. ────────────────────────────────
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t
printf '# ROADMAP\n\n- [ ] [ROUTINE] do the thing <!-- id:1111 -->\n' > "$R/ROADMAP.md"
{ printf '# TODO\n\n## Current\n\n'
  n=0; while [[ $n -lt 400 ]]; do
    printf -- '- [ ] a backlog item with enough prose to be representative of the real ledger %03d <!-- id:%04x -->\n' "$n" $(( 0x2000 + n ))
    n=$((n+1))
  done
} > "$R/TODO.md"
git -C "$R" add -A
git -C "$R" commit -qm init

todo_real=$(wc -c < "$R/TODO.md")
rm_real=$(wc -c < "$R/ROADMAP.md")
unit_json="$("$CR" --emit unit --repo repo --path "$R" 2>/dev/null || true)"
if [[ -n "$unit_json" ]]; then
  got_todo=$(printf '%s' "$unit_json" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("todo_bytes","<<MISSING>>"))')
  got_rm=$(printf '%s' "$unit_json"   | python3 -c 'import sys,json;print(json.load(sys.stdin).get("roadmap_bytes","<<MISSING>>"))')
  [[ "$got_rm" == "$rm_real" ]] \
    && ok "classify-repo.sh --emit unit ships roadmap_bytes=$got_rm (id:4f9b, regression guard)" \
    || bad "roadmap_bytes regression: got '$got_rm', file is $rm_real B"
  [[ "$got_todo" == "$todo_real" ]] \
    && ok "classify-repo.sh --emit unit ships todo_bytes=$got_todo" \
    || bad "id:b018: classify-repo.sh does not ship todo_bytes (got '$got_todo', TODO.md is $todo_real B) — the gate has no way to size the second ledger"
else
  bad "id:b018: classify-repo.sh --emit unit produced no JSON for the fixture"
fi
grep -q 'todo_bytes' "$CR" \
  && ok "classify-repo.sh mentions todo_bytes" \
  || bad "id:b018: classify-repo.sh never measures TODO.md"

# ── (B) BEHAVIOUR: the pure gate must count BOTH ledgers. Driven with a SMALL promptChars so
#        the roadmap-only estimate reproduces the incident's own 'under budget by 326'. ──────
cat > "$TMP/drive.mjs" <<NODE
import { oversizeDispatchReason, estimateDispatchTokens, DISPATCH_TOKEN_BUDGET } from 'file://$GATE'
const out = []
const P = 1000                    // small assembled prompt: the ledgers dominate, as in the incident
const LODERITE_ROADMAP = 350698
const LODERITE_TODO    = 392043

// (1) The incident, reproduced. ROADMAP alone is UNDER budget — that is why the child was
//     dispatched at all. This case documents the trap; it must keep holding after the fix.
{
  const roadmapOnly = estimateDispatchTokens(P, LODERITE_ROADMAP)
  out.push('roadmap_only_under_budget=' + (roadmapOnly <= DISPATCH_TOKEN_BUDGET ? '1' : '0'))
  out.push('roadmap_only_near_budget=' + (roadmapOnly > 95000 ? '1' : '0'))
}

// (2) THE FIX: counting both ledgers must exceed the budget by roughly 2x.
{
  const both = estimateDispatchTokens(P, LODERITE_ROADMAP, LODERITE_TODO)
  out.push('both_over_budget=' + (both > DISPATCH_TOKEN_BUDGET ? '1' : '0'))
  out.push('both_about_double=' + (both > 180000 && both < 215000 ? '1' : '0'))
  out.push('todo_actually_counted=' + (both > estimateDispatchTokens(P, LODERITE_ROADMAP) + 90000 ? '1' : '0'))
}

// (3) The loderite unit must be REFUSED, and the reason must NAME TODO.md and its bytes —
//     a refusal that blames only ROADMAP.md sends the human to archive the wrong file.
{
  const u = { repo: 'loderite', path: '/p/loderite', verdict: 'execute',
              roadmap_bytes: LODERITE_ROADMAP, todo_bytes: LODERITE_TODO }
  const r = oversizeDispatchReason(u, P)
  out.push('loderite_refused=' + (r ? '1' : '0'))
  out.push('loderite_names_todo=' + (/TODO\.md/.test(r) ? '1' : '0'))
  out.push('loderite_names_todo_bytes=' + (r.includes(String(LODERITE_TODO)) ? '1' : '0'))
  out.push('loderite_names_roadmap_bytes=' + (r.includes(String(LODERITE_ROADMAP)) ? '1' : '0'))
  out.push('loderite_not_generic=' + (/API error or terminal failure/.test(r) ? '0' : '1'))
}

// (4) TRIANGULATION — a SECOND, differently-shaped case, so hard-coding the loderite numbers
//     is not a pass. Here ROADMAP is small and TODO alone blows the budget.
{
  const u = { repo: 'todo-heavy', path: '/p/x', verdict: 'execute', roadmap_bytes: 20000, todo_bytes: 500000 }
  const r = oversizeDispatchReason(u, P)
  out.push('todo_heavy_refused=' + (r ? '1' : '0'))
  out.push('todo_heavy_names_todo=' + (/TODO\.md/.test(r) ? '1' : '0'))
}

// (5) NEGATIVE CONTROL — a gate that refuses everything is useless. Both ledgers small ⇒ dispatch.
{
  out.push('small_dispatches=' + (oversizeDispatchReason(
    { repo: 'r', path: '/p', roadmap_bytes: 40000, todo_bytes: 30000 }, P) === '' ? '1' : '0'))
}

// (6) FAIL-OPEN preserved: absent/zero todo_bytes must behave exactly as today. Blocking on
//     ABSENT data would be strictly worse than the death this prevents.
{
  out.push('no_todo_field_dispatches=' + (oversizeDispatchReason(
    { repo: 'r', path: '/p', roadmap_bytes: 40000 }, P) === '' ? '1' : '0'))
  out.push('zero_todo_dispatches=' + (oversizeDispatchReason(
    { repo: 'r', path: '/p', roadmap_bytes: 40000, todo_bytes: 0 }, P) === '' ? '1' : '0'))
  out.push('unmeasured_dispatches=' + (oversizeDispatchReason({ repo: 'r' }, P) === '' ? '1' : '0'))
  out.push('null_unit_dispatches=' + (oversizeDispatchReason(null, P) === '' ? '1' : '0'))
  // a unit measured ONLY on TODO (no roadmap_bytes) must still be sizeable — the old
  // "if (!roadmapBytes) return empty" short-circuit would silently skip it.
  out.push('todo_only_measured_refused=' + (oversizeDispatchReason(
    { repo: 'r', path: '/p', todo_bytes: 900000 }, P) ? '1' : '0'))
}

// (7) id:4f9b CALIBRATION UNCHANGED — the two historical points must keep their verdicts
//     when no todo_bytes is present, so this change cannot silently re-tune the gate.
{
  out.push('incident_523926_refused=' + (oversizeDispatchReason(
    { repo: 'dotclaude-skills', path: '/p', roadmap_bytes: 523926 }, P) ? '1' : '0'))
  out.push('postarchive_254087_dispatches=' + (oversizeDispatchReason(
    { repo: 'dotclaude-skills', path: '/p', roadmap_bytes: 254087 }, P) === '' ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

res=$(node "$TMP/drive.mjs" 2>&1) || { echo "BAD: node driver failed:"; echo "$res" | sed 's/^/    /'; fail=$((fail+1)); res=""; }
[[ -n "$res" ]] && echo "$res" | sed 's/^/    /'
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && ok "gate: $k" || bad "id:b018: gate case failed — $k"
done <<< "$res"

# ── (C) WIRING: relay-loop.js's inline copy must learn the same input, and the dispatch site
#        must pass it. An inline copy that still sizes only ROADMAP.md ships the bug. ────────
grep -q 'todo_bytes' "$JS" \
  && ok "relay-loop.js's inline gate knows about todo_bytes" \
  || bad "id:b018: relay-loop.js inline copy still sizes ONLY ROADMAP.md — the tested logic is not the shipped logic"

if python3 - "$GATE" "$JS" <<'PY'
import sys
mod = open(sys.argv[1]).read(); js = open(sys.argv[2]).read()
missing = []
for fn in ('function estimateDispatchTokens', 'function oversizeDispatchReason'):
    i = mod.find('export ' + fn)
    if i < 0:
        missing.append(fn + ' (absent from module)'); continue
    body = mod[i:]
    body = body[:body.index('\n}\n') + 3].replace('export ', '', 1)
    if body not in js:
        missing.append(fn + ' (inline copy drifted)')
sys.exit(1 if missing else 0)
PY
then
  ok "relay-loop.js inline copies stay byte-equivalent to prompt-size-gate.mjs"
else
  bad "id:b018: relay-loop.js inline copy has DRIFTED from prompt-size-gate.mjs after the todo_bytes change"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: prompt-size gate counts every embedded ledger (id:b018)"
