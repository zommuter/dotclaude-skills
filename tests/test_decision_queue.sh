#!/usr/bin/env bash
# roadmap:de31
# Spec for relay/scripts/decision-queue.sh (id:de31; meeting 2026-06-30-1523 DP4) — the durable
# file-backed human-decision-request queue. When the loop hits a resolution it can't mechanically
# close (a forced lane-triage, a "close or drain?" call), it APPENDS a decision request here and
# keeps working; the human answers out-of-band; the loop consumes the verdict later. This is the
# "one home" (the substrate); the transport (broker vs FIFO vs file-tail) is the deferred sibling
# id:b444. In scope here: the record format + the flock'd add/list/resolve helper.
#
# Record: {id, repo, kind, question, options[], evidence, requested_at, status, [answer, resolved_at]}
# RED until decision-queue.sh exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DQ="$ROOT/relay/scripts/decision-queue.sh"
[[ -x "$DQ" ]] || { echo "decision-queue.sh not yet implemented (RED): $DQ"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_DECISION_QUEUE="$tmp/dq.jsonl"

# add → prints the minted id
id="$("$DQ" add --repo truncocraft --kind lane-triage \
  --question "promote the 17 surface items as which lane?" \
  --option ROUTINE --option "HARD-meeting" \
  --evidence "unpromoted-scan: 0 promote, 17 surface")"
[[ -n "$id" ]] || { echo "add must print the minted decision id"; exit 1; }

# the queue file holds one open record with the right fields
python3 - "$RELAY_DECISION_QUEUE" "$id" <<'PYEOF'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(lines) == 1, lines
r = lines[0]
assert r["id"] == sys.argv[2], r
assert r["repo"] == "truncocraft" and r["kind"] == "lane-triage", r
assert r["status"] == "open", r
assert "promote the 17" in r["question"], r
assert r["options"] == ["ROUTINE", "HARD-meeting"], r
assert "17 surface" in r["evidence"], r
assert r.get("requested_at"), r
print("add record OK")
PYEOF

# list (default = open) shows it
"$DQ" list | grep -q "$id" || { echo "list must show the open decision"; exit 1; }

# add a second, idempotency of the file (append-only, two records)
id2="$("$DQ" add --repo zelegator --kind close-or-drain --question "close 244b or drain?")"
[[ "$(grep -c . "$RELAY_DECISION_QUEUE")" == "2" ]] || { echo "second add must append, not overwrite"; exit 1; }

# resolve the first → status resolved + answer + resolved_at
"$DQ" resolve "$id" --answer ROUTINE
python3 - "$RELAY_DECISION_QUEUE" "$id" <<'PYEOF'
import json, sys
recs = {json.loads(l)["id"]: json.loads(l) for l in open(sys.argv[1]) if l.strip()}
r = recs[sys.argv[2]]
assert r["status"] == "resolved" and r["answer"] == "ROUTINE" and r.get("resolved_at"), r
print("resolve record OK")
PYEOF

# list (open) no longer shows the resolved one, still shows the other
"$DQ" list | grep -q "$id" && { echo "resolved decision must NOT appear in the open list"; exit 1; } || true
"$DQ" list | grep -q "$id2" || { echo "the still-open decision must remain in the list"; exit 1; }

echo "PASS test_decision_queue"
