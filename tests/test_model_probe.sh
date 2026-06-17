#!/usr/bin/env bash
# roadmap:040a — tests/test_model_probe.sh: hermetic offline contract tests for
# tools/model-probe.sh (grading, log format, battery-version propagation,
# empty-config assertion). No network, no model calls, no ~/.claude touch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/tools/model-probe.sh"
BATTERY="$ROOT/tools/model-probe.battery.jsonl"

[[ -x "$SCRIPT" ]] || { echo "tools/model-probe.sh missing or not executable"; exit 1; }
[[ -f "$BATTERY" ]] || { echo "tools/model-probe.battery.jsonl missing"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Test 1: grade subcommand ──────────────────────────────────────────────────
"$SCRIPT" grade '\b56\b' '7 times 8 is 56.' \
  || { echo "FAIL test1: grade should exit 0 when output matches golden_regex"; exit 1; }

"$SCRIPT" grade '\b56\b' '7 times 8 is 57.' \
  && { echo "FAIL test1: grade should exit 1 when output does not match"; exit 1; } || true

echo "PASS test1: grade subcommand"

# ── Test 2: battery-version subcommand ───────────────────────────────────────
cat > "$tmp/battery.jsonl" <<'EOF'
{"type":"meta","version":"v-test-1","description":"fixture battery"}
{"id":"f001","prompt":"What is 1+1? Answer with only the number.","golden_regex":"\\b2\\b"}
EOF

ver="$("$SCRIPT" battery-version "$tmp/battery.jsonl")"
[[ "$ver" == "v-test-1" ]] \
  || { echo "FAIL test2: battery-version should print 'v-test-1', got '$ver'"; exit 1; }

echo "PASS test2: battery-version subcommand"

# ── Test 3: log format + battery-version propagation (mock mode) ─────────────
log_file="$tmp/probe.jsonl"
mkdir -p "$tmp/empty-probe-home"

PROBE_MOCK_RESPONSE="The answer is 2." \
PROBE_LOG_PATH="$log_file" \
PROBE_HOME="$tmp/empty-probe-home" \
  "$SCRIPT" run opus "$tmp/battery.jsonl" >/dev/null

[[ -f "$log_file" ]] || { echo "FAIL test3: log file not created at $log_file"; exit 1; }
line="$(tail -1 "$log_file")"
[[ -n "$line" ]] || { echo "FAIL test3: log file is empty"; exit 1; }

python3 - "$line" "$tmp/battery.jsonl" <<'PYEOF'
import json, sys

line = sys.argv[1]
battery_path = sys.argv[2]

try:
    obj = json.loads(line)
except json.JSONDecodeError as e:
    print(f"FAIL test3: log line is not valid JSON: {e}\nLine: {line!r}")
    sys.exit(1)

required = ["ts", "battery_version", "model", "item_id", "pass", "latency_s",
            "out_tokens", "tok_per_s", "model_id_str", "fingerprint",
            "cli_version", "quota_tier", "os_user", "config_hash"]
missing = [f for f in required if f not in obj]
if missing:
    print(f"FAIL test3: log line missing fields: {missing}\nLine: {line!r}")
    sys.exit(1)

# battery_version propagation
if obj["battery_version"] != "v-test-1":
    print(f"FAIL test3: battery_version should be 'v-test-1', got {obj['battery_version']!r}")
    sys.exit(1)

# model field
if obj["model"] != "opus":
    print(f"FAIL test3: model should be 'opus', got {obj['model']!r}")
    sys.exit(1)

# pass field is bool
if not isinstance(obj["pass"], bool):
    print(f"FAIL test3: 'pass' field should be bool, got {type(obj['pass'])}")
    sys.exit(1)

print("OK: log line valid JSON with all required fields, correct battery_version and model")
PYEOF

echo "PASS test3: log format and battery-version propagation"

# ── Test 4: empty-config assertion refuses dirty probe HOME ──────────────────
dirty_home="$tmp/dirty-probe-home"
mkdir -p "$dirty_home/.claude"
echo "# stray CLAUDE.md" > "$dirty_home/.claude/CLAUDE.md"

PROBE_MOCK_RESPONSE="The answer is 2." \
PROBE_LOG_PATH="$tmp/log4.jsonl" \
PROBE_HOME="$dirty_home" \
  "$SCRIPT" run opus "$tmp/battery.jsonl" 2>/dev/null \
  && { echo "FAIL test4: should refuse to run with dirty probe HOME containing CLAUDE.md"; exit 1; } \
  || true

echo "PASS test4: empty-config assertion refuses dirty probe HOME"

echo "ALL PASS"
