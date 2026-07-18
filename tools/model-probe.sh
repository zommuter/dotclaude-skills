#!/usr/bin/env bash
# tools/model-probe.sh — standing model quality probe (id:c345)
#
# Subcommands (offline, no model call needed):
#   model-probe.sh grade <golden_regex> <output>    exit 0=pass, 1=fail
#   model-probe.sh battery-version [battery_path]   print battery version
#
# Run (requires probe OS user unless PROBE_MOCK_RESPONSE is set):
#   model-probe.sh [run] [model] [battery_path]
#   model-probe.sh run opus                          default battery, opus tier
#   model-probe.sh run sonnet                        sonnet tier
#   model-probe.sh run haiku                         haiku tier
#
# Env overrides (for testing):
#   PROBE_MOCK_RESPONSE   bypass claude invocation; use this text as model response
#   PROBE_LOG_PATH        override log path (default ~/.claude/logs/model-probe.jsonl)
#   PROBE_HOME            override probe user HOME for config-clean check
#
# Invocation shapes (D6):
#   Shape A (default): claude -p run as dedicated probe OS user with empty ~/.claude
#   Shape B (latent):  claude --bare -p with ANTHROPIC_API_KEY (set to use)
#
# Log schema (D2 + D1 OS-user refinement):
#   {ts, battery_version, model, item_id, pass, latency_s, out_tokens, tok_per_s,
#    model_id_str, fingerprint, cli_version, quota_tier, os_user, config_hash}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_BATTERY="${REPO_ROOT}/tools/model-probe.battery.jsonl"
DEFAULT_LOG="${HOME}/.claude/logs/model-probe.jsonl"

# ── grade subcommand (offline) ────────────────────────────────────────────────
if [[ "${1:-}" == "grade" ]]; then
  shift
  [[ $# -ge 2 ]] || { echo "usage: model-probe.sh grade <golden_regex> <output>" >&2; exit 2; }
  regex="$1"; output="$2"
  printf '%s\n' "$output" | grep -qP "$regex" && exit 0
  exit 1
fi

# ── battery-version subcommand (offline) ──────────────────────────────────────
if [[ "${1:-}" == "battery-version" ]]; then
  shift
  bat="${1:-$DEFAULT_BATTERY}"
  python3 - "$bat" <<'PYEOF'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    obj = json.loads(line)
    if obj.get('type') == 'meta':
        print(obj['version'])
        sys.exit(0)
print('ERROR: no meta line found in battery', file=sys.stderr)
sys.exit(1)
PYEOF
  exit 0
fi

# ── run (default) ─────────────────────────────────────────────────────────────
[[ "${1:-}" == "run" ]] && shift
MODEL="${1:-opus}"
[[ $# -ge 1 ]] && shift || true
BATTERY_PATH="${1:-$DEFAULT_BATTERY}"
[[ $# -ge 1 ]] && shift || true

LOG_PATH="${PROBE_LOG_PATH:-$DEFAULT_LOG}"
MOCK_RESPONSE="${PROBE_MOCK_RESPONSE:-}"

# Config-clean assertion: always check when PROBE_HOME is set; in real mode also
# check the default probe home. In mock mode without PROBE_HOME, skip the check
# (no real probe user involved).
_probe_home_check=""
if [[ -n "${PROBE_HOME:-}" ]]; then
  _probe_home_check="$PROBE_HOME"
elif [[ -z "$MOCK_RESPONSE" ]]; then
  _probe_home_check="/home/claude-probe"
fi

if [[ -n "$_probe_home_check" ]]; then
  _dot_claude="$_probe_home_check/.claude"
  if [[ -f "$_dot_claude/CLAUDE.md" ]] || \
     [[ -d "$_dot_claude/skills" ]] || \
     [[ -f "$_dot_claude/settings.json" ]]; then
    echo "ERROR: probe HOME '$_probe_home_check' has Claude config files — not clean." >&2
    echo "       Empty '$_dot_claude/' before running the probe (see id:d0c0)." >&2
    exit 1
  fi
fi

# Capture environment facts for the log
CLI_VERSION="$(claude --version 2>/dev/null | head -1 || echo "unknown")"

_config_home="${PROBE_HOME:-/home/claude-probe}"
if [[ -d "$_config_home/.claude" ]]; then
  CONFIG_HASH="$(find "$_config_home/.claude" -maxdepth 5 -type f 2>/dev/null \
    | sort | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}' || echo "empty")"
else
  CONFIG_HASH="empty"
fi

CURRENT_OS_USER="$(id -un)"
mkdir -p "$(dirname "$LOG_PATH")"

# Delegate the item loop to Python for JSON handling
exec python3 - \
  "$BATTERY_PATH" "$MODEL" "$LOG_PATH" \
  "$CLI_VERSION" "$CONFIG_HASH" "$CURRENT_OS_USER" \
  "${PROBE_HOME:-/home/claude-probe}" \
  "${MOCK_RESPONSE}" \
  <<'PYEOF'
import json, re, subprocess, sys, time, os

battery_path, model, log_path, cli_version, config_hash, os_user, probe_home, mock_response = sys.argv[1:]

# Read battery
battery_version = None
items = []
for line in open(battery_path):
    line = line.strip()
    if not line:
        continue
    obj = json.loads(line)
    if obj.get('type') == 'meta':
        battery_version = obj['version']
    else:
        items.append(obj)

if not battery_version:
    print('ERROR: no meta line (version) found in battery', file=sys.stderr)
    sys.exit(1)

print(f"model-probe: model={model} battery_version={battery_version} items={len(items)}", flush=True)

for item in items:
    item_id = item['id']
    prompt = item['prompt']
    golden_regex = item['golden_regex']

    model_id_str = 'mock'
    fingerprint = 'mock'
    quota_tier = 'mock'
    out_tokens = 0
    tok_per_s = 0.0
    response_text = ''

    t0 = time.monotonic()

    if mock_response:
        # Testing: bypass model invocation
        response_text = mock_response
        latency_s = 0.001
        current_os_user = os_user  # current user in mock mode
    else:
        # Shape A: claude -p as dedicated probe OS user with empty ~/.claude
        probe_user = 'claude-probe'
        try:
            cmd = [
                'sudo', '-u', probe_user,
                'env', f'HOME={probe_home}',
                'claude', '-p', prompt,
                '--output-format', 'stream-json', '--verbose',
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            latency_s = time.monotonic() - t0

            for sline in result.stdout.splitlines():
                sline = sline.strip()
                if not sline:
                    continue
                try:
                    ev = json.loads(sline)
                except json.JSONDecodeError:
                    continue
                evtype = ev.get('type', '')
                evsubtype = ev.get('subtype', '')
                if evtype == 'system' and evsubtype == 'init':
                    model_id_str = ev.get('model', 'unknown')
                    fingerprint = ev.get('session_id', 'unknown')
                    quota_tier = str(ev.get('quota_type', 'unknown'))
                elif evtype == 'assistant':
                    for block in ev.get('message', {}).get('content', []):
                        if block.get('type') == 'text':
                            response_text += block['text']
                    usage = ev.get('message', {}).get('usage', {})
                    out_tokens = usage.get('output_tokens', 0)
                    tok_per_s = out_tokens / latency_s if latency_s > 0 else 0.0

            if result.returncode != 0 and not response_text:
                stderr = result.stderr.strip()
                print(f'ERROR: claude -p failed for {item_id}: {stderr}', file=sys.stderr)
                sys.exit(1)

            # Shape B (latent fallback — uncomment + set ANTHROPIC_API_KEY to use):
            # cmd_b = ['claude', '--bare', '-p', prompt, '--output-format', 'stream-json']
            # ...

            current_os_user = probe_user

        except subprocess.TimeoutExpired:
            print(f'ERROR: claude -p timed out for {item_id}', file=sys.stderr)
            sys.exit(1)
        except FileNotFoundError:
            print(f'ERROR: probe OS user {probe_user!r} not found or claude not in PATH.'
                  ' Probe OS user setup is gated on id:d0c0.', file=sys.stderr)
            sys.exit(1)

    # Grade: 0=pass, 1=fail
    try:
        passed = bool(re.search(golden_regex, response_text))
    except re.error as e:
        print(f'WARNING: invalid golden_regex for {item_id}: {e}', file=sys.stderr)
        passed = False

    # Append log line
    log_entry = {
        'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'battery_version': battery_version,
        'model': model,
        'item_id': item_id,
        'pass': passed,
        'latency_s': round(latency_s, 3),
        'out_tokens': out_tokens,
        'tok_per_s': round(tok_per_s, 2),
        'model_id_str': model_id_str,
        'fingerprint': fingerprint,
        'cli_version': cli_version,
        'quota_tier': quota_tier,
        'os_user': current_os_user if not mock_response else os_user,
        'config_hash': config_hash,
    }
    with open(log_path, 'a') as f:
        f.write(json.dumps(log_entry) + '\n')

    status = 'PASS' if passed else 'FAIL'
    print(f'  {item_id}: {status}', flush=True)

print(f'Done. Log: {log_path}')
PYEOF
