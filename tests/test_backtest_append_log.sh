#!/usr/bin/env bash
# roadmap:1324
# Tests for backtest-verdict.py --append-log (id:1324):
#   - --append-log writes a parseable JSON line with the expected keys to the path
#   - RELAY_SHADOW_LOG env override controls the path (hermetic)
#   - appending twice yields two lines
#   - --append-log with an explicit path uses that path
#   - exit 0 (report-only)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BT="$ROOT/relay/scripts/backtest-verdict.py"
[[ -f "$BT" ]] || { echo "FAIL: backtest-verdict.py not found"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_SHADOW_LOG="$tmp/shadow.jsonl"

# minimal own repo "foo"
R="$SRC_DIR/foo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:0001 -->
EOF
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A
git -C "$R" commit -qm init

cat > "$RELAY_TOML" <<'EOF'
[repos.foo]
classification = "own"
EOF
printf '{"kind":"dispatch","repo":"foo","mode":"review"}\n' > "$RELAY_EVENTS"

# ── case 1: --append-log writes a parseable JSON line ──
python3 "$BT" --append-log || { echo "FAIL: --append-log must exit 0"; exit 1; }
[[ -f "$RELAY_SHADOW_LOG" ]] || { echo "FAIL: shadow log not created at RELAY_SHADOW_LOG"; exit 1; }
lines="$(wc -l < "$RELAY_SHADOW_LOG")"
[[ "$lines" -eq 1 ]] || { echo "FAIL: expected 1 line in shadow log, got $lines"; exit 1; }
python3 - "$RELAY_SHADOW_LOG" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    line = f.readline().strip()
o = json.loads(line)
required = {"agree", "diverged", "red", "expected", "new", "crashes", "distribution", "timestamp"}
missing = required - set(o.keys())
assert not missing, f"missing keys in shadow log entry: {missing}; got {o}"
assert isinstance(o["agree"], int), f"agree must be int, got {o}"
assert isinstance(o["diverged"], int), f"diverged must be int, got {o}"
assert isinstance(o["red"], int), f"red must be int, got {o}"
assert isinstance(o["expected"], int), f"expected must be int, got {o}"
assert isinstance(o["crashes"], int), f"crashes must be int, got {o}"
assert isinstance(o["distribution"], dict), f"distribution must be dict, got {o}"
assert isinstance(o["timestamp"], str), f"timestamp must be str, got {o}"
print("case 1 (--append-log writes parseable JSON with expected keys): OK")
PYEOF

# ── case 2: appending twice yields two lines ──
python3 "$BT" --append-log || { echo "FAIL: second --append-log must exit 0"; exit 1; }
lines="$(wc -l < "$RELAY_SHADOW_LOG")"
[[ "$lines" -eq 2 ]] || { echo "FAIL: expected 2 lines after second append, got $lines"; exit 1; }
echo "case 2 (append twice → two lines): OK"

# ── case 3: explicit path argument ──
explicit="$tmp/explicit.jsonl"
python3 "$BT" --append-log "$explicit" || { echo "FAIL: --append-log <path> must exit 0"; exit 1; }
[[ -f "$explicit" ]] || { echo "FAIL: explicit log path not created"; exit 1; }
python3 -c "import json; json.loads(open('$explicit').read())" || { echo "FAIL: explicit log is not valid JSON"; exit 1; }
echo "case 3 (--append-log <explicit-path>): OK"

# ── case 4: --append-log can be combined with --json (both outputs produced) ──
python3 "$BT" --json --append-log > "$tmp/json_out.txt" || { echo "FAIL: --json --append-log must exit 0"; exit 1; }
python3 -c "import json,sys; json.loads(open('$tmp/json_out.txt').read())" \
  || { echo "FAIL: stdout is not valid JSON when combined with --append-log"; exit 1; }
echo "case 4 (--json --append-log both work): OK"

echo "PASS test_backtest_append_log"
