#!/usr/bin/env bash
# id:f499 — sliceLedgerForUnit's NO-ITEM early return must LOG WHY, like every other failure
# branch on that path.
#
# (No `# roadmap:` header: this is a defect fix filed in TODO.md only, so its failures always
# count — it is never EXPECTED-RED.)
#
# THE DEFECT: `relay-loop.js`'s `sliceLedgerForUnit` opened with `const item =
# dispatchItemFor(unit); if (!item) return null` — a SILENT return. The function's own header
# promises "FAIL-OPEN and LOUD: any failure (no item id, script error, agent throw, MECH-ERROR,
# empty or non-path stdout) leaves unit.slice_path unset, LOGS WHY". Four of those five branches
# logged; the first did not.
#
# THE COST is diagnostic, not cosmetic: `oversizeDispatchReason`'s UNSLICED branch tells the
# operator to "find why `ledger-slice.sh` produced no `slice_path` for it (the relay-loop log
# records the reason)". A REVIEW unit carries no `actionable_routine_ids`, so `dispatchItemFor`
# yields '' and this is exactly the branch it takes — meaning the remedy pointed at a log line
# that could never exist (found while measuring id:502f, 2026-08-27).
#
# HONEST COVERAGE LIMIT (same precedent as tests/test_prompt_size_gate_4f9b.sh, id:2ec4):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness, so
# this is a STRUCTURAL check over the source — it proves the branch logs and that the log names
# the required facts, not that a live pool round emits it.
#
# Hermetic: reads repo sources only. mktemp -d scratch, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── (A) The silent form is GONE. ─────────────────────────────────────────────────────────────
if grep -qF 'const item = dispatchItemFor(unit)' "$JS"; then
  ok "sliceLedgerForUnit still resolves its dispatch item via dispatchItemFor()"
else
  bad "id:f499: sliceLedgerForUnit no longer calls dispatchItemFor — this test is pinned to the wrong site"
fi

# ── (B) The no-item branch LOGS, and the log names repo + verdict + the no-item cause. ───────
python3 - "$JS" > "$TMP/out" <<'PY'
import re, sys
src = open(sys.argv[1]).read()

i = src.find('async function sliceLedgerForUnit(unit)')
if i < 0:
    print('no_slice_fn=0'); raise SystemExit(0)
print('no_slice_fn=1')

# The function body up to its first `let raw` — i.e. the no-item guard only.
head = src[i:]
end = head.find('let raw')
head = head[:end] if end > 0 else head[:2000]

guard = re.search(r'if \(!item\)\s*\{(.*?)\n  \}', head, re.S)
if not guard:
    # a bare `if (!item) return null` (the defect) or an unrecognised shape
    print('no_item_branch_logs=' + ('0' if 'if (!item) return null' in head else 'UNKNOWN'))
    print('log_names_repo=0'); print('log_names_verdict=0'); print('log_names_cause=0')
    print('branch_still_returns_null=0')
    raise SystemExit(0)

body = guard.group(1)
logs = re.findall(r'log\(`([^`]*)`\)', body)
print('no_item_branch_logs=' + ('1' if logs else '0'))
msg = logs[0] if logs else ''
print('log_names_repo='    + ('1' if '${unit.repo}' in msg else '0'))
print('log_names_verdict=' + ('1' if 'unit.verdict' in msg else '0'))
print('log_names_cause='   + ('1' if re.search(r'no dispatch item|nothing to slice', msg, re.I) else '0'))
# FAIL-OPEN preserved: the branch must still return null so dispatch proceeds unsliced.
print('branch_still_returns_null=' + ('1' if 'return null' in body else '0'))
# The log must go through the same log() helper the sibling branches use, not console.*
print('uses_log_helper=' + ('1' if 'console.' not in body else '0'))
PY

while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && ok "f499: $k" || bad "id:f499: case failed — $k=$v"
done < "$TMP/out"

# ── (C) PARITY: all FIVE failure modes the header promises now log. ──────────────────────────
# The other four were already loud; pin them so a future edit cannot quietly silence one.
fnbody=$(python3 - "$JS" <<'PY'
import sys
src = open(sys.argv[1]).read()
i = src.find('async function sliceLedgerForUnit(unit)')
j = src.find('\n}\n', i)
sys.stdout.write(src[i:j])
PY
)
n_logs=$(grep -c 'log(`relay-loop: id:e68f' <<<"$fnbody" || true)
if [[ "$n_logs" -ge 5 ]]; then
  ok "sliceLedgerForUnit carries $n_logs id:e68f log lines (no-item, throw, MECH-ERROR, unusable path, success)"
else
  bad "id:f499: sliceLedgerForUnit has only $n_logs id:e68f log lines — a failure mode went silent"
fi

# ── (D) The remedy text that DEPENDS on this log still exists, so the pairing stays true. ────
grep -qF 'the relay-loop log records the reason' "$JS" \
  && ok "oversizeDispatchReason's unsliced remedy still promises a logged reason (the consumer of this fix)" \
  || bad "id:f499: the unsliced-branch remedy no longer promises a logged reason — re-check this pairing"

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: sliceLedgerForUnit's no-item early return logs why (id:f499)"
