#!/usr/bin/env bash
# roadmap:5eb3
# Spec for relay/scripts/file-surface-decisions.sh (id:5eb3; meeting 2026-06-30-2238).
#
# DECISION: when classify-verdict.sh emits verdict=human (promote==0 ∧ surface>0),
# the relay-loop calls file-surface-decisions.sh to FILE each surface item to the
# decision-queue. This is the MECHANICAL, FORCED, LOGGED filing step that replaces
# the Opus handoff apex for surface-only repos.
#
# CONTRACT:
#   1. N surface items from unpromoted-scan → exactly N decision-queue records written
#      (one per surface item with a non----- token).
#   2. A second run with the same surface set is a clean no-op (idempotent).
#   3. The script ALWAYS emits a count summary line to stdout (LOUD — never silent).
#   4. The script exits 0 on success.
#
# RED until file-surface-decisions.sh exists and passes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FSD="$ROOT/relay/scripts/file-surface-decisions.sh"
DQUEUE="$ROOT/relay/scripts/decision-queue.sh"

[[ -x "$FSD" ]] || { echo "file-surface-decisions.sh not found or not executable (RED): $FSD"; exit 1; }
[[ -x "$DQUEUE" ]] || { echo "decision-queue.sh not found (RED): $DQUEUE"; exit 1; }

# ── Scaffold a minimal fake repo for the test ────────────────────────────────
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

REPO="$TMPDIR/testrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@test"
git -C "$REPO" config user.name "test"

# Write a TODO.md with 2 surface-disposition items (untagged = surface) and 1 promote item ([ROUTINE]).
# unpromoted-scan requires a ROADMAP.md to exist (it compares against it for twin detection).
cat > "$REPO/TODO.md" <<'EOF'
## Current
- [ ] Some untagged surface item A <!-- id:aa01 -->
- [ ] Another untagged surface item B <!-- id:bb02 -->
- [ ] [ROUTINE] A promotable item C <!-- id:cc03 -->
EOF

cat > "$REPO/ROADMAP.md" <<'EOF'
# ROADMAP

(empty — no twins)
EOF

# Commit so git state is clean (unpromoted-scan needs a valid git repo)
git -C "$REPO" add .
git -C "$REPO" commit -q -m "test scaffold"

# Point decision-queue to an isolated file for this test
export RELAY_DECISION_QUEUE="$TMPDIR/test-decision-queue.jsonl"

# ── Run 1: initial filing ─────────────────────────────────────────────────────
OUT="$("$FSD" "$REPO" 2>/tmp/fsd-test-stderr.txt)"

# 1a. stdout must contain a count line (LOUD — never silent)
echo "$OUT" | grep -q "file-surface-decisions:" || {
  echo "LOUD-output: script must emit a count summary line to stdout"
  echo "Got: $OUT"
  exit 1
}

# 1b. Count the filed records (only surface items with non----- tokens get filed = aa01, bb02)
FILED="$(echo "$OUT" | grep -oP 'filed=\K[0-9]+')" || true
[[ "$FILED" == "2" ]] || {
  echo "filed-count: expected filed=2 surface items, got: $FILED (output: $OUT)"
  exit 1
}

# 1c. The decision-queue file must exist and have exactly 2 open records
[[ -f "$RELAY_DECISION_QUEUE" ]] || { echo "decision-queue file not created"; exit 1; }
RECORD_COUNT="$(python3 -c "
import json,sys
lines = [l.strip() for l in open('$RELAY_DECISION_QUEUE') if l.strip()]
open_recs = [json.loads(l) for l in lines if json.loads(l).get('status','open')=='open']
print(len(open_recs))
")"
[[ "$RECORD_COUNT" == "2" ]] || {
  echo "record-count: expected 2 open records, got $RECORD_COUNT"
  cat "$RELAY_DECISION_QUEUE"
  exit 1
}

# 1d. Each record must reference the correct source_ids
python3 -c "
import json
lines = [l.strip() for l in open('$RELAY_DECISION_QUEUE') if l.strip()]
recs = [json.loads(l) for l in lines]
source_ids = {r.get('source_id','') for r in recs if r.get('status','open')=='open'}
assert 'aa01' in source_ids, f'expected source_id aa01, got {source_ids}'
assert 'bb02' in source_ids, f'expected source_id bb02, got {source_ids}'
print('source-ids-ok')
" || { echo "source-ids: expected aa01 and bb02 in decision-queue records"; exit 1; }

# ── Run 2: idempotency ────────────────────────────────────────────────────────
# unpromoted-scan.sh ALREADY excludes tokens with OPEN decision-queue records (id:47f1),
# so the second run sees surface_items=0 — idempotency is enforced at scan level, not
# file level. filed=0 and the record count is unchanged.
OUT2="$("$FSD" "$REPO" 2>/tmp/fsd-test-stderr2.txt)"

# 2a. stdout must still emit a count line (LOUD even on a no-op)
echo "$OUT2" | grep -q "file-surface-decisions:" || {
  echo "idempotency-loud: run 2 must still emit a count summary"
  exit 1
}

# 2b. filed=0 on the second run (scan excludes already-filed tokens via id:47f1)
FILED2="$(echo "$OUT2" | grep -oP 'filed=\K[0-9]+')" || true
[[ "$FILED2" == "0" ]] || {
  echo "idempotency-filed: expected filed=0 on run 2, got: $FILED2 (output: $OUT2)"
  exit 1
}

# 2c. record count unchanged — the queue still has exactly 2 open records
RECORD_COUNT2="$(python3 -c "
import json
lines = [l.strip() for l in open('$RELAY_DECISION_QUEUE') if l.strip()]
open_recs = [json.loads(l) for l in lines if json.loads(l).get('status','open')=='open']
print(len(open_recs))
")"
[[ "$RECORD_COUNT2" == "2" ]] || {
  echo "idempotency-count: run 2 must not add new records (still 2, got $RECORD_COUNT2)"
  exit 1
}

echo "PASS test_file_surface_decisions"
