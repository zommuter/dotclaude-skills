#!/usr/bin/env bash
# roadmap:0d31 — [skeleton L1] thin-glue: relay-status-publish.sh replaces the ~40-line
# writeRelayStatus haiku recipe with one deterministic call (short+precise agent prompt → no
# target-drift). This tests the SCRIPT's deterministic behavior; the relay-loop.js wiring is
# checked structurally below. Hermetic: sandboxed HOME under mktemp; never touches the real
# ~/.config or the network (claim.sh peek / relay-burn.sh report find an empty sandbox → the
# "_(none)_" / "_(insufficient samples yet)_" branches, which is exactly what we assert).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$SRC_DIR/relay/scripts/relay-status-publish.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$PUB" ]] || fail "relay-status-publish.sh not found/executable"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"          # sandbox every helper's ~-default (claim/burn/state-write logs)
mkdir -p "$TMP/.config/relay"
STATUS="$TMP/.config/relay/RELAY_STATUS.md"
EVENTS="$TMP/.config/relay/relay-events.jsonl"

# (1) content-only (no events): writes the body + both rendered sections, no events file.
printf '# RELAY_STATUS — body line\nsome status text' \
  | "$PUB" --path "$STATUS" --run relay-20260618-test --events-path "$EVENTS" >/dev/null
[[ -f "$STATUS" ]] || fail "status file not written"
grep -q "RELAY_STATUS — body line" "$STATUS" || fail "base content missing from status file"
grep -q "## Claims (live)" "$STATUS" || fail "Claims section not rendered"
grep -q "## Burnup this run" "$STATUS" || fail "Burnup section not rendered"
grep -q "_(none)_" "$STATUS" || fail "empty-sandbox claims should render _(none)_"
[[ ! -f "$EVENTS" ]] || fail "no events were passed → events file must not be created"
pass "content-only publish writes body + Claims + Burnup, no events file"

# (2) with a trailing events block (after the sentinel) → appended to the JSONL.
printf '# body2\n===RELAY-EVENTS===\n{"e":"dispatch","repo":"foo"}\n{"e":"integrate","repo":"foo"}' \
  | "$PUB" --path "$STATUS" --run relay-20260618-test --events-path "$EVENTS" >/dev/null
grep -q "# body2" "$STATUS" || fail "second publish did not rewrite the body"
grep -q "RELAY-EVENTS" "$STATUS" && fail "the sentinel leaked into the status body"
[[ -f "$EVENTS" ]] || fail "events block was not appended to the JSONL"
[[ "$(grep -c '"repo":"foo"' "$EVENTS")" == "2" ]] || fail "expected 2 event lines appended"
pass "events block after the sentinel is split off and appended to the JSONL"

# (3) a non-absolute / unexpandable target is refused (id:c34a guard preserved).
if printf 'x' | "$PUB" --path 'relative/path.md' --run r --events-path "$EVENTS" >/dev/null 2>&1; then
  fail "non-absolute target must be refused"
fi
pass "non-absolute target is refused"

# (4) relay-loop.js wiring: writeRelayStatus delegates to the script (one-line invocation),
#     and node --check still passes.
[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"
grep -q "relay-status-publish.sh" "$JS" || fail "writeRelayStatus does not call relay-status-publish.sh"
grep -q "id:0d31" "$JS" || fail "no id:0d31 marker tying the wiring to the roadmap item"
pass "relay-loop.js writeRelayStatus delegates to relay-status-publish.sh (0d31)"
