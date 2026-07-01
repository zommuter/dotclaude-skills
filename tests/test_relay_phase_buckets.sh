#!/usr/bin/env bash
# roadmap:7c10 — finer-grained /workflows phase buckets. The per-verdict grouping (id:7d1e) left
# two buckets as overloaded catch-alls: Integrate was flooded by the write-relay-status snapshot
# writer, and discover-shards shared the Discover bucket with the prelude; Support lumped quota +
# leases + injection + heartbeat + auto-reconcile together. This splits them into single-purpose
# buckets so the live pane's per-phase counts are meaningful. PURELY a display grouping — zero
# behavioural change. Structural assertions on the agent() phase: opts + meta.phases. Hermetic.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing"; exit 1; }

grep -q "id:7c10" "$JS" || bad "relay-loop.js: no id:7c10 marker (phase-bucket rationale missing)"

# meta.phases declares the new single-purpose buckets.
for title in Discover Classify Execute Review Hard Handoff Integrate Status Logging Quota Leases Support; do
  grep -qE "title: '$title'" "$JS" || bad "meta.phases missing the '$title' bucket"
done
ok "meta.phases declares all 12 single-purpose buckets (incl. Classify/Status/Logging/Quota/Leases)"

# The two former floods are split OUT of Discover/Integrate. discover-shard was replaced by
# the mechanical discover-run runner, which keeps the same Classify bucket.
grep -q "label: \`discover-run:\${chunk.length}\`, phase: 'Classify'" "$JS" \
  || bad "discover-run not in the Classify bucket (still in Discover?)"
ok "discover-run → Classify (split from the prelude's Discover bucket)"

grep -q "label: 'write-relay-status', phase: 'Status'" "$JS" \
  || bad "write-relay-status not moved to the Status bucket (still flooding Integrate?)"
ok "write-relay-status → Status (no longer floods Integrate)"

# Integrate is now ONLY the real merge agent.
grep -q "label: \`integrate:\${unit.repo}\`, phase: 'Integrate'" "$JS" \
  || bad "integrate:<repo> is not in the Integrate bucket"
# and the per-unit logging/followup agents moved to Logging.
grep -q "label: \`gaming-log:\${repo}\`, phase: 'Logging'" "$JS" \
  || bad "gaming-log not moved to the Logging bucket"
grep -q "label: \`handback-followup:\${unit.repo}\`, phase: 'Logging'" "$JS" \
  || bad "handback-followup not moved to the Logging bucket"
ok "Integrate holds only the merge; gaming-log + handback-followup → Logging"

# Support catch-all is broken up: quota → Quota, release → Leases.
grep -q "label: \`quota:\${tier}\`, phase: 'Quota'" "$JS" \
  || bad "quota gate not moved to the Quota bucket"
grep -q "label: \`release:\${unit.repo}\`, phase: 'Leases'" "$JS" \
  || bad "lease release not moved to the Leases bucket"
ok "quota → Quota, release → Leases (Support catch-all de-cluttered)"

# Regression: the moved agents must NOT still be tagged with their old buckets.
grep -q "label: 'write-relay-status', phase: 'Integrate'" "$JS" && bad "write-relay-status still tagged Integrate" || ok "write-relay-status no longer tagged Integrate"
grep -q "label: \`discover-shard:\${chunk.length}\`, phase: 'Discover'" "$JS" && bad "discover-shard still tagged Discover" || ok "discover-shard no longer tagged Discover"

# The genuine support agents (injection/heartbeat/auto-reconcile) remain in Support.
grep -q "label: 'inject-take', phase: 'Support'" "$JS" || bad "inject-take left the Support bucket unexpectedly"
grep -q "label: 'auto-reconcile-restart', phase: 'Support'" "$JS" || bad "auto-reconcile-restart left the Support bucket unexpectedly"
ok "inject-take + auto-reconcile-restart remain in Support"

echo "test_relay_phase_buckets: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
