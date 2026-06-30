#!/usr/bin/env bash
# roadmap:f896
# Static source-shape assertion: verify that relay-loop.js's pushEvent('dispatch',…) call
# includes a `sig` field, and that the unit-construction loop stamps u.sig from sigByRepo.
# Cannot run the Workflow engine in a hermetic test; mirrors the pattern of other source-shape
# tests (e.g. test_workflow_template_lint.sh's static grep assertions).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }

# 1. The dispatch pushEvent must include a sig field.
grep -q "pushEvent('dispatch'.*sig:" "$JS" \
  || { echo "FAIL: pushEvent('dispatch',…) in relay-loop.js does not include a 'sig:' field (id:f896)"; exit 1; }
echo "PASS (1): pushEvent('dispatch') includes sig field"

# 2. The unit-construction cache loop must stamp u.sig from sigByRepo.
grep -q "u\.sig = sig" "$JS" \
  || { echo "FAIL: relay-loop.js unit cache loop does not set u.sig (id:f896)"; exit 1; }
echo "PASS (2): unit cache loop sets u.sig"

# 3. The sig field uses fail-open sentinel (|| '') so absent sigs yield empty string.
grep -q "sigByRepo\[u\.repo\] || ''" "$JS" \
  || { echo "FAIL: relay-loop.js unit sig stamping is not fail-open (missing || '') (id:f896)"; exit 1; }
echo "PASS (3): unit sig is fail-open (|| '')"

# 4. The template-literal linter must still pass (the engine has a backtick-in-template hazard).
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || { echo "FAIL: lint-workflow-templates.mjs not found; cannot verify template safety"; exit 1; }
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  echo "FAIL: relay-loop.js has a template-literal violation after f896 edit:
$out"
  exit 1
fi
echo "PASS (4): relay-loop.js still lints clean after f896 edit"

echo "PASS test_dispatch_event_sig"
