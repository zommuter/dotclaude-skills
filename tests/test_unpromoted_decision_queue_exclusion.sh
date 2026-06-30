#!/usr/bin/env bash
# roadmap:47f1
# Spec for the case-g resolution wiring (id:47f1; TODO id:4d8e corpus case g).
#
# THE BUG (live evidence 2026-06-30 `/relay --afk`): the classifier correctly emits
# `handoff` on surface-only backlog (DoD case b — surface must NOT be hidden as idle),
# but the handoff RESOLUTION silently no-ops on surface items — `decision-queue.sh`
# (id:de31) was built as the durable lane-triage home yet never wired in, and
# `unpromoted-scan.sh` re-counts surface items every round → `handoff` re-fires forever
# (the no-op loop; truncocraft case g). The fix is the resolution, NOT the classifier:
#   1. `decision-queue.sh add --source-id <token>` records the originating TODO id.
#   2. `unpromoted-scan.sh` EXCLUDES a token that has an OPEN decision-queue record for
#      that repo → a filed surface item stops counting as fresh backlog → loop broken.
# A RESOLVED record does NOT exclude (the human assigned a lane → the item must resurface
# so handoff promotes it).
#
# RED until decision-queue.sh learns --source-id and unpromoted-scan.sh consults the queue.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DQ="$ROOT/relay/scripts/decision-queue.sh"
SCAN="$ROOT/relay/scripts/unpromoted-scan.sh"

[[ -x "$DQ" && -x "$SCAN" ]] || { echo "scripts missing (RED): $DQ / $SCAN"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RELAY_DECISION_QUEUE="$TMP/decision-queue.jsonl"

# --- a hermetic repo with un-twinned TODO backlog (no ROADMAP → all un-twinned) ------------
REPO="$TMP/demo"
mkdir -p "$REPO"
git -C "$REPO" init -q
cat >"$REPO/TODO.md" <<'EOF'
# TODO
- [ ] untagged surface item one <!-- id:aaaa -->
- [ ] untagged surface item two <!-- id:bbbb -->
- [ ] [ROUTINE] directly promotable <!-- id:cccc -->
EOF

scan() { "$SCAN" "$REPO" 2>/dev/null; }
disp_of() { scan | awk -F'\t' -v t="$1" '$2==t {print $3}'; }

# --- baseline: nothing filed → aaaa/bbbb surface, cccc promote -----------------------------
[[ "$(disp_of aaaa)" == "surface" ]] || { echo "baseline: aaaa must be surface"; exit 1; }
[[ "$(disp_of bbbb)" == "surface" ]] || { echo "baseline: bbbb must be surface"; exit 1; }
[[ "$(disp_of cccc)" == "promote" ]] || { echo "baseline: cccc must be promote"; exit 1; }

# --- (1) --source-id is stored on the record -----------------------------------------------
dqid="$("$DQ" add --repo demo --kind lane-triage \
          --question "Assign a lane to TODO id:aaaa: untagged surface item one" \
          --source-id aaaa)"
[[ -n "$dqid" ]] || { echo "decision-queue add must print an id"; exit 1; }
stored="$("$DQ" list --repo demo | python3 -c 'import sys,json
for l in sys.stdin:
    r=json.loads(l)
    if r.get("source_id")=="aaaa": print("yes"); break')"
[[ "$stored" == "yes" ]] || { echo "(1) --source-id aaaa must be stored on the record"; exit 1; }

# --- (2) a filed surface token is EXCLUDED; unfiled ones unaffected -------------------------
[[ -z "$(disp_of aaaa)" ]]            || { echo "(2) filed aaaa must be excluded from the scan (loop-breaker)"; exit 1; }
[[ "$(disp_of bbbb)" == "surface" ]]  || { echo "(2) unfiled bbbb must still be surface"; exit 1; }
[[ "$(disp_of cccc)" == "promote" ]]  || { echo "(2) cccc must still be promote"; exit 1; }

# --- (3) a RESOLVED record does NOT exclude — the item must resurface for promotion ---------
"$DQ" resolve "$dqid" --answer "lane: [ROUTINE]" >/dev/null
[[ "$(disp_of aaaa)" == "surface" ]] || { echo "(3) resolved record must NOT exclude — aaaa resurfaces"; exit 1; }

echo "PASS test_unpromoted_decision_queue_exclusion"
