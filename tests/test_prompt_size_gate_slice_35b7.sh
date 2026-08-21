#!/usr/bin/env bash
# roadmap:35b7 — the pre-dispatch prompt-size gate must size a unit on its id:e68f SLICE when
# one exists, and only fall back to counting the whole ledgers when there is none.
#
# THE INCIDENT (dotclaude-skills, 2026-08-21): id:b018 (count ROADMAP + TODO) and id:e68f (write
# a slice and hand the child its path) merged in the same checkpoint and were ratified as
# INDEPENDENT. They are not. `oversizeDispatchReason` counted `roadmap_bytes + todo_bytes`
# unconditionally, so this repo estimated ~301,349 tok (ROADMAP 252,809 B + TODO 904,586 B)
# against a 100,000 tok budget and the gate refused EVERY dispatch — on bytes the child is no
# longer required to read, because sliceLedgerForUnit() stamps unit.slice_path immediately
# BEFORE the gate's call site, with a slice measured at 3,854 B for a real item.
#
# THE FIX UNDER TEST: when unit.slice_path is set, the required-read set IS the slice — size
# that and stop counting the ledgers. The slice size is MEASURED (ledger-slice.sh reports it on
# an ADDITIVE stdout contract, path still last) and never a guessed allowance: the gate exists
# because an unmeasured estimate let loderite through by 326 tokens. Fail-open is unchanged —
# unmeasured input, including a slice of unknown size, never blocks a dispatch.
#
# Hermetic: mktemp -d fixture repo, git/node/python3 only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/relay/scripts/prompt-size-gate.mjs"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Fixture: a repo whose ledgers are FAR over budget but whose dispatched item is tiny. ────
R="$TMP/repo"; mkdir -p "$R"
{
  printf '# ROADMAP\n\n## Items\n\n'
  printf -- '- [ ] [ROUTINE] **THE DISPATCHED ITEM** — build the widget <!-- id:1111 -->\n'
  printf -- '  - **Acceptance**: the widget exists.\n\n'
  n=0
  while [[ $n -lt 3000 ]]; do
    printf -- '- [ ] [ROUTINE] **OPEN item %04d** — a long OPEN note representative of the real ledger prose that accumulates inline and dominates the byte count. <!-- id:%04x -->\n' "$n" $(( 0x4000 + n ))
    n=$((n+1))
  done
} > "$R/ROADMAP.md"
{
  printf '# TODO\n\n## Current\n\n'
  n=0
  while [[ $n -lt 3000 ]]; do
    printf -- '- [ ] design-ledger item %04d with enough prose to be representative of the real thing <!-- id:%04x -->\n' "$n" $(( 0x7000 + n ))
    n=$((n+1))
  done
} > "$R/TODO.md"

rm_bytes=$(wc -c < "$R/ROADMAP.md")
todo_bytes=$(wc -c < "$R/TODO.md")
[[ $(( (rm_bytes + todo_bytes) / 4 )) -gt 100000 ]] \
  || bad "fixture: ledgers only $(( (rm_bytes + todo_bytes) / 4 )) tok — must exceed the 100000 budget on their own"
ok "fixture built: ROADMAP=$rm_bytes B + TODO=$todo_bytes B ≈ $(( (rm_bytes + todo_bytes) / 4 )) tok, well over budget"

# ── (A) ledger-slice.sh must REPORT the slice's measured size, additively: the byte count is
#        a new line, the PATH is still the last line (18 assertions in the id:e68f test and
#        relay-loop.js's last-non-empty-line parse both depend on that). ────────────────────
OUT="$TMP/slice.md"
slice_stdout="$("$SLICE" --repo repo --path "$R" --id 1111 --out "$OUT" 2>"$TMP/err")" || {
  bad "id:35b7: ledger-slice.sh failed — $(head -2 "$TMP/err" | tr '\n' ' ')"
}
real_bytes=$(wc -c < "$OUT" 2>/dev/null || echo 0)
reported=$(sed -n 's/^slice-bytes:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' <<<"$slice_stdout" | head -1)
if [[ -n "$reported" ]]; then
  ok "ledger-slice.sh reports its slice size on stdout (slice-bytes: $reported)"
else
  bad "id:35b7: ledger-slice.sh printed no 'slice-bytes: <N>' line — no measured byte count reaches the gate, so it cannot size on the slice (got: '${slice_stdout//$'\n'/ | }')"
fi
if [[ "$reported" == "$real_bytes" ]]; then
  ok "the reported size is the file's REAL size ($real_bytes B) — measured, not a guessed allowance"
else
  bad "id:35b7: reported slice size '$reported' != actual $real_bytes B — the gate would size on a wrong number"
fi
last_line="$(grep -v '^[[:space:]]*$' <<<"$slice_stdout" | tail -1)"
if [[ "$last_line" == "$OUT" ]]; then
  ok "the slice PATH is still the last non-empty stdout line (existing contract preserved)"
else
  bad "id:35b7: last stdout line is '$last_line', not the bare path '$OUT' — the additive contract replaced instead of adding"
fi

# ── (B) The decision function itself, driven through node against the real byte counts. ─────
PROMPTLEN=6000
if out="$(node --input-type=module -e "
import { oversizeDispatchReason, DISPATCH_TOKEN_BUDGET } from '$GATE'
const PROMPT = 'x'.repeat($PROMPTLEN)
const base = { repo: 'fixture', path: '$R', verdict: 'execute', roadmap_bytes: $rm_bytes, todo_bytes: $todo_bytes }
const res = []
// A unit WITH a measured slice: the ledgers are huge, the slice is tiny ⇒ MUST dispatch.
const sliced = Object.assign({}, base, { slice_path: '$OUT', slice_bytes: $real_bytes })
res.push('sliced_dispatches=' + (oversizeDispatchReason(sliced, PROMPT.length) === '' ? '1' : '0'))
// The SAME unit without a slice ⇒ MUST still refuse (the id:b018 behaviour is untouched).
res.push('unsliced_refuses=' + (oversizeDispatchReason(base, PROMPT.length) ? '1' : '0'))
// Slice present but its size UNMEASURED ⇒ fail OPEN (never block on missing data), and NOT a
// silent fallback to counting ledgers the child will not read.
res.push('unmeasured_slice_dispatches=' + (oversizeDispatchReason(Object.assign({}, base, { slice_path: '$OUT' }), PROMPT.length) === '' ? '1' : '0'))
// A slice that is ITSELF over budget must still refuse — the gate is not disabled by a slice.
const huge = Object.assign({}, base, { slice_path: '$OUT', slice_bytes: 600000 })
const hugeReason = oversizeDispatchReason(huge, PROMPT.length)
res.push('huge_slice_refuses=' + (hugeReason ? '1' : '0'))
res.push('huge_names_slice=' + (hugeReason.includes('$OUT') && hugeReason.includes('600000') ? '1' : '0'))
res.push('huge_disclaims_archiving=' + (/archiving the ledgers will NOT help/i.test(hugeReason) ? '1' : '0'))
// The UNSLICED refusal's REMEDY must not be archive-only: on this repo TODO.md is 529 open /
// 1 closed, so archive-done.sh moves nothing and the printed remedy was a dead end.
const r = oversizeDispatchReason(base, PROMPT.length)
res.push('remedy_names_slice_lever=' + (/id:e68f ledger slice/i.test(r) ? '1' : '0'))
res.push('remedy_conditions_archiving=' + (/OPEN items/.test(r) && /only applies if the bulk is CLOSED/i.test(r) ? '1' : '0'))
res.push('budget_unchanged=' + (DISPATCH_TOKEN_BUDGET === 100000 ? '1' : '0'))
console.log(res.join('\n'))
" 2>"$TMP/nodeerr")"; then
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    case "$k:$v" in
      sliced_dispatches:1)            ok "a unit WITH a measured slice DISPATCHES though its ledgers are ~$(( (rm_bytes + todo_bytes) / 4 )) tok — the slice is the required-read set" ;;
      sliced_dispatches:*)            bad "id:35b7: a sliced unit is STILL refused — the gate is counting ledgers the child no longer has to read (this is the un-dispatchable-repo bug)" ;;
      unsliced_refuses:1)             ok "the SAME unit WITHOUT a slice still REFUSES (id:b018 ledger sizing intact)" ;;
      unsliced_refuses:*)             bad "id:35b7: an UNSLICED oversized unit now dispatches — the fix disabled the gate instead of narrowing it" ;;
      unmeasured_slice_dispatches:1)  ok "a slice with NO measured size fails OPEN (unmeasured input never blocks)" ;;
      unmeasured_slice_dispatches:*)  bad "id:35b7: an unmeasured slice blocks dispatch — fail-open behaviour changed" ;;
      huge_slice_refuses:1)           ok "a slice that is itself over budget still REFUSES (a slice does not disable the gate)" ;;
      huge_slice_refuses:*)           bad "id:35b7: an oversized SLICE dispatches — the gate is now unconditionally open for sliced units" ;;
      huge_names_slice:1)             ok "the oversized-slice refusal names the slice path and its byte count" ;;
      huge_names_slice:*)             bad "id:35b7: the oversized-slice refusal does not name the slice path + bytes — anonymous cause (id:4347)" ;;
      huge_disclaims_archiving:1)     ok "the oversized-slice refusal says archiving the ledgers will NOT help" ;;
      huge_disclaims_archiving:*)     bad "id:35b7: the oversized-slice refusal still points at the ledger archivers — wrong remedy" ;;
      remedy_names_slice_lever:1)     ok "the unsliced refusal's REMEDY names the id:e68f slice lever first" ;;
      remedy_names_slice_lever:*)     bad "id:35b7: the printed REMEDY still does not name the slice lever — it sends the operator to archive-done.sh on a ledger of OPEN items" ;;
      remedy_conditions_archiving:1)  ok "the REMEDY marks archiving as conditional on the bulk being CLOSED and names the OPEN-items case" ;;
      remedy_conditions_archiving:*)  bad "id:35b7: the REMEDY still prescribes archiving unconditionally — useless when the ledger is 529 open / 1 closed" ;;
      budget_unchanged:1)             ok "DISPATCH_TOKEN_BUDGET is still 100000 (no budget was widened to paper over this)" ;;
      budget_unchanged:*)             bad "id:35b7: DISPATCH_TOKEN_BUDGET changed — the fix must narrow WHAT is counted, never raise the cap" ;;
    esac
  done <<<"$out"
else
  bad "id:35b7: node could not evaluate the gate — $(head -3 "$TMP/nodeerr" | tr '\n' ' ')"
fi

# ── (C) The wiring: relay-loop.js must actually stamp the measured size on the unit, and its
#        inline gate copy must carry the slice branch (byte-equivalence is pinned by
#        tests/test_prompt_size_gate_4f9b.sh; this pins the PLUMBING that feeds it). ────────
if grep -q 'slice-bytes:' "$JS"; then
  ok "relay-loop.js parses the slice-bytes line out of ledger-slice.sh's stdout"
else
  bad "id:35b7: relay-loop.js never reads 'slice-bytes:' — the measurement is produced but never reaches the gate"
fi
if grep -q 'unit.slice_bytes =' "$JS"; then
  ok "relay-loop.js stamps unit.slice_bytes (what oversizeDispatchReason sizes on)"
else
  bad "id:35b7: relay-loop.js never sets unit.slice_bytes — the gate sees an unmeasured slice and silently fails open forever"
fi
if grep -q 'u.slice_path' "$JS"; then
  ok "relay-loop.js's inline gate copy branches on u.slice_path"
else
  bad "id:35b7: the inline gate copy in relay-loop.js has no slice branch — the shipped path still counts ledgers"
fi
# Ordering: the slice must be stamped BEFORE the gate is consulted, or slice_path is never set
# when the gate runs.
slice_at=$(grep -n 'await sliceLedgerForUnit(unit)' "$JS" | head -1 | cut -d: -f1)
gate_at=$(grep -n 'const oversizeReason = oversizeDispatchReason(' "$JS" | head -1 | cut -d: -f1)
if [[ -n "$slice_at" && -n "$gate_at" && "$slice_at" -lt "$gate_at" ]]; then
  ok "sliceLedgerForUnit() runs BEFORE the gate (line $slice_at < $gate_at) — slice_path is set when the gate reads it"
else
  bad "id:35b7: the slice is not stamped before the gate call (slice=$slice_at gate=$gate_at) — the gate would always see an unsliced unit"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: the prompt-size gate sizes on the id:e68f slice when one exists (id:35b7)"
