#!/usr/bin/env bash
# roadmap:e8ea
# Tests for the e8ea divergence-bucketing in backtest-verdict.py:
#   - a dispatch event WITH sig == current-sig but different verdict → RED
#   - a dispatch event WITH sig != current-sig → EXPECTED (state drift)
#   - a dispatch event WITHOUT sig (pre-f896) → EXPECTED (state drift)
# Uses the same fixture style as test_backtest_verdict.sh.  Hermetic.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BT="$ROOT/relay/scripts/backtest-verdict.py"
DISCOVER_SIG="$ROOT/relay/scripts/discover-sig.sh"
[[ -f "$BT" ]] || { echo "FAIL: backtest-verdict.py not found"; exit 1; }
[[ -f "$DISCOVER_SIG" ]] || { echo "FAIL: discover-sig.sh not found"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_SHADOW_LOG="$tmp/shadow.jsonl"

# ── build fixture repo "foo" with an open [ROUTINE] item (live verdict = execute) ──
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

# ── compute the REAL current sig for "foo" ──
real_sig="$(printf '%s' '{"repos":[{"repo":"foo","path":"'"$R"'"}],"liveClaims":[]}' \
  | "$DISCOVER_SIG" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("sig",""))')"

# ── case 1: same sig, different verdict → RED ──
printf '{"kind":"dispatch","repo":"foo","mode":"review","sig":"%s"}\n' "$real_sig" > "$RELAY_EVENTS"
out="$(python3 "$BT" --json)" || { echo "FAIL: backtest must exit 0 (report-only)"; exit 1; }
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
foo = [r for r in o["rows"] if r["repo"] == "foo"][0]
assert foo["verdict"] == "execute", f"live verdict must be execute, got {foo}"
assert foo["last_mode"] == "review", f"last dispatch must be review, got {foo}"
assert foo["note"] == "RED", f"same-sig + different-verdict must bucket RED, got {foo}"
assert s["red"] == 1, f"red count must be 1, got {s}"
assert s["expected"] == 0, f"expected count must be 0, got {s}"
assert s["crashes"] == 0, f"no crashes expected: {s}"
print("case 1 (same-sig, different verdict → RED): OK")
PYEOF

# ── case 2: different sig → EXPECTED (state drift) ──
printf '{"kind":"dispatch","repo":"foo","mode":"review","sig":"stale000000000000000000000000000000000000000000000000000000000000"}\n' > "$RELAY_EVENTS"
out="$(python3 "$BT" --json)" || { echo "FAIL: backtest must exit 0 (report-only)"; exit 1; }
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
foo = [r for r in o["rows"] if r["repo"] == "foo"][0]
assert foo["note"] == "EXPECTED", f"changed-sig must bucket EXPECTED, got {foo}"
assert s["expected"] == 1, f"expected count must be 1, got {s}"
assert s["red"] == 0, f"red count must be 0, got {s}"
print("case 2 (different sig → EXPECTED): OK")
PYEOF

# ── case 3: no sig (pre-f896 event) → EXPECTED ──
printf '{"kind":"dispatch","repo":"foo","mode":"review"}\n' > "$RELAY_EVENTS"
out="$(python3 "$BT" --json)" || { echo "FAIL: backtest must exit 0 (report-only)"; exit 1; }
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
foo = [r for r in o["rows"] if r["repo"] == "foo"][0]
assert foo["note"] == "EXPECTED", f"absent-sig must bucket EXPECTED, got {foo}"
print("case 3 (no sig / pre-f896 → EXPECTED): OK")
PYEOF

# ── case 4: agree rows stay 'agree' (same verdict) ──
printf '{"kind":"dispatch","repo":"foo","mode":"execute","sig":"%s"}\n' "$real_sig" > "$RELAY_EVENTS"
out="$(python3 "$BT" --json)" || { echo "FAIL: backtest must exit 0 (report-only)"; exit 1; }
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
foo = [r for r in o["rows"] if r["repo"] == "foo"][0]
assert foo["note"] == "agree", f"same-verdict must stay 'agree', got {foo}"
assert s["agree"] == 1, f"agree count must be 1, got {s}"
assert s["red"] == 0 and s["expected"] == 0, f"red/expected must be 0, got {s}"
print("case 4 (agree stays agree): OK")
PYEOF

echo "PASS test_backtest_bucketing"
