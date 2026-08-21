#!/usr/bin/env bash
# id:7575 — a SLICED unit's brief must not INVITE the child to open the full ledgers when the
# measured headroom left by the gate could not possibly absorb one.
#
# No `# roadmap:` header on purpose: id:7575 is a TODO.md defect item, not a ROADMAP item, so
# this is a defect-fix test (per tests/README conventions) and its failures always count.
#
# The defect (verified verbatim in code, 2026-08-21): prompt-size-gate.mjs sizes a sliced unit
# on the SLICE ALONE and never counts ledger bytes, while sliceInstruction() in relay-loop.js
# told the child "The full ledgers are still on disk at their canonical paths if the slice
# genuinely does not carry something you need". On dotclaude-skills that is an approval granted
# on a ~4 KB slice plus an invitation to open a ~904,586 B TODO.md (~226k tok) — accepting it
# kills the child with `Prompt is too long`, reported as the generic "child agent failed/
# skipped" because id:61fa is still open. ledger-slice.sh bounds an item block by INDENTATION,
# so a column-0 acceptance line is silently dropped and the slice LOOKS incomplete — the
# invitation is therefore taken precisely when the slice is worst.
#
# THIS ITEM CHANGES ONLY WHAT THE BRIEF SAYS. The gate's verdict is deliberately untouched
# (case D below pins that), and neither brief variant may claim the slice ENFORCES anything —
# it lowers the default, the child keeps Read/Bash (id:9663).
#
# Hermetic: node only, no network, no ~/.claude, no git.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$SRC_DIR/relay/scripts/prompt-size-gate.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$GATE" ]] || { echo "FAIL: prompt-size-gate.mjs missing at $GATE"; exit 1; }
[[ -f "$JS" ]]   || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── (A)+(B)+(C)+(D) behaviour, driven through the pure module. ──────────────────────────────
cat > "$TMP/drive.mjs" <<NODE
import {
  sliceInstruction, sliceLedgerHeadroom, oversizeDispatchReason,
  DISPATCH_TOKEN_BUDGET, CHARS_PER_TOKEN, FIXED_OVERHEAD_TOKENS,
} from 'file://$GATE'
const out = []
const has = (s, re) => (re.test(s) ? '1' : '0')

// Real dotclaude-skills numbers, 2026-08-21: the ledgers dwarf every plausible headroom.
const DWARF = { repo: 'dotclaude-skills', verdict: 'execute', slice_path: '/tmp/slice-aaaa.md',
                slice_bytes: 3854, roadmap_bytes: 252809, todo_bytes: 904586 }
// A small repo: both ledgers fit comfortably inside the headroom the slice leaves.
const AMPLE = { repo: 'tiny', verdict: 'execute', slice_path: '/tmp/slice-bbbb.md',
                slice_bytes: 3347, roadmap_bytes: 40000, todo_bytes: 30000 }
// Sliced but the ledgers were never measured — must FAIL OPEN to today's wording.
const UNMEASURED = { repo: 'old-queue-entry', verdict: 'execute', slice_path: '/tmp/slice-cccc.md',
                     slice_bytes: 3000 }

// (A) AMPLE headroom ⇒ the child still gets the escape hatch.
{
  const s = sliceInstruction(AMPLE)
  out.push('ample_nonempty=' + (s ? '1' : '0'))
  out.push('ample_points_at_slice=' + (s.includes('/tmp/slice-bbbb.md') ? '1' : '0'))
  out.push('ample_invites=' + has(s, /full ledgers are still on disk/))
  out.push('ample_asks_to_report=' + has(s, /say which and why in your report/))
  out.push('ample_no_handback_order=' + (/HAND BACK/.test(s) ? '0' : '1'))
}

// (B) Ledgers DWARF the headroom ⇒ the invitation is withdrawn and replaced by a hand-back
//     instruction that NAMES the measured numbers (the whole bug class here is unmeasured
//     estimates, so the brief must quote what was measured).
{
  const s = sliceInstruction(DWARF)
  out.push('dwarf_nonempty=' + (s ? '1' : '0'))
  out.push('dwarf_points_at_slice=' + (s.includes('/tmp/slice-aaaa.md') ? '1' : '0'))
  out.push('dwarf_no_invitation=' + (/full ledgers are still on disk/.test(s) ? '0' : '1'))
  out.push('dwarf_says_handback=' + has(s, /HAND BACK/))
  out.push('dwarf_names_ledger_bytes=' + (s.includes('904586') ? '1' : '0'))
  out.push('dwarf_names_headroom=' + has(s, /headroom/i))
  out.push('dwarf_names_death=' + has(s, /Prompt is too long/))
  out.push('dwarf_names_id=' + (s.includes('id:7575') ? '1' : '0'))
  out.push('dwarf_forbids_speculative=' + has(s, /speculativ/i))
}

// (C) FAIL-OPEN: unmeasured ledgers, and no slice at all.
{
  out.push('unmeasured_invites=' + has(sliceInstruction(UNMEASURED), /full ledgers are still on disk/))
  out.push('unsliced_empty=' + (sliceInstruction({ repo: 'r', verdict: 'execute' }) === '' ? '1' : '0'))
  out.push('null_unit_empty=' + (sliceInstruction(null) === '' ? '1' : '0'))
}

// (C2) NO-ENFORCEMENT CLAIM (id:9663): neither variant may say the slice bounds/limits/
//      prevents/restricts what the child can read. It lowers the DEFAULT only.
{
  const both = sliceInstruction(AMPLE) + ' || ' + sliceInstruction(DWARF)
  const claims = /slice (enforces|prevents|restricts|limits|bounds)|you (cannot|may not|are not allowed to) read|forbidden to read|no access to the ledgers/i
  out.push('no_enforcement_claim=' + (claims.test(both) ? '0' : '1'))
  // and the hardened variant must still be honest that reading is possible, just fatal.
  out.push('dwarf_honest_about_cost=' + has(sliceInstruction(DWARF), /cost, not a boundary|nothing stops you/i))
}

// (D) THE GATE'S VERDICT IS UNCHANGED. Every unit above dispatches exactly as it does today.
{
  const P = 9000
  out.push('gate_dwarf_still_dispatches=' + (oversizeDispatchReason(DWARF, P) === '' ? '1' : '0'))
  out.push('gate_ample_still_dispatches=' + (oversizeDispatchReason(AMPLE, P) === '' ? '1' : '0'))
  out.push('gate_unmeasured_still_dispatches=' + (oversizeDispatchReason(UNMEASURED, P) === '' ? '1' : '0'))
  // an oversized SLICE must still refuse — the headroom wording never softens the gate
  out.push('gate_big_slice_still_refuses=' + (oversizeDispatchReason({ ...DWARF, slice_bytes: 600000 }, P) ? '1' : '0'))
}

// (E) The headroom figure is MEASURED from the unit's own byte counts and the budget — not a
//     fixed allowance. Re-derive it independently here and require an exact match.
{
  const h = sliceLedgerHeadroom(DWARF)
  const expected = DISPATCH_TOKEN_BUDGET - (Math.round(DWARF.slice_bytes / CHARS_PER_TOKEN) + FIXED_OVERHEAD_TOKENS)
  out.push('headroom_is_derived=' + (h.headroomTokens === expected ? '1' : '0'))
  out.push('headroom_largest_is_todo=' + (h.largestLedgerName === 'TODO.md' ? '1' : '0'))
  out.push('headroom_largest_bytes=' + (h.largestLedgerBytes === 904586 ? '1' : '0'))
  out.push('headroom_dwarf_unaffordable=' + (h.affordable === false ? '1' : '0'))
  out.push('headroom_ample_affordable=' + (sliceLedgerHeadroom(AMPLE).affordable === true ? '1' : '0'))
  out.push('headroom_unmeasured_failopen=' + (sliceLedgerHeadroom(UNMEASURED).affordable === true ? '1' : '0'))
  // Scaling with the budget proves the figure is not a hardcoded constant.
  out.push('headroom_scales_with_budget=' + (sliceLedgerHeadroom(DWARF, 400000).affordable === true ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

if res=$(node "$TMP/drive.mjs" 2>&1); then
  echo "$res" | sed 's/^/    /'
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    [[ "$v" == "1" ]] && ok "brief: $k" || bad "id:7575: case failed — $k"
  done <<< "$res"
else
  echo "$res" | sed 's/^/    /'
  bad "id:7575: driver did not run — prompt-size-gate.mjs does not export sliceInstruction/sliceLedgerHeadroom yet"
fi

# ── (F) WIRING: relay-loop.js must use the SHARED builder, mirrored byte-for-byte (the
#        Workflow sandbox cannot import — same discipline as the id:4f9b gate copies). ───────
if python3 - "$GATE" "$JS" <<'PY'
import sys
mod = open(sys.argv[1]).read()
js  = open(sys.argv[2]).read()
missing = []
for fn in ('function sliceLedgerHeadroom', 'function sliceInstruction'):
    i = mod.find('export ' + fn)
    if i < 0:
        missing.append(fn + ' (not exported by the module)'); continue
    body = mod[i:]
    body = body[:body.index('\n}\n') + 3].replace('export ', '', 1)
    if body not in js:
        missing.append(fn + ' (inline copy drifted)')
sys.exit(1 if missing else 0)
PY
then
  ok "relay-loop.js inline copies of sliceLedgerHeadroom/sliceInstruction are byte-equivalent to the module"
else
  bad "id:7575: relay-loop.js does not carry byte-equivalent inline copies of the shared brief builder"
fi

# The old unconditional invitation must not survive anywhere as a raw literal in relay-loop.js
# outside the mirrored function (that is what made the escape hatch unconditional).
if [[ "$(grep -cF "'The full ledgers are still on disk at their canonical paths" "$JS")" -le 1 ]]; then
  ok "relay-loop.js carries the invitation string at most once (inside the mirrored builder)"
else
  bad "id:7575: relay-loop.js still has a second, unconditional copy of the invitation string"
fi

echo
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
