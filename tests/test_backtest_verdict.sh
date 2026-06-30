#!/usr/bin/env bash
# roadmap:5f93
# Smoke/behaviour test for relay/scripts/backtest-verdict.py (id:5f93) — the pre-flip
# validation gate that replays classify-repo.sh over own repos and compares each verdict to
# the last logged dispatch verdict. Hermetic: fixture relay.toml + events + an on-disk repo.
# RED until backtest-verdict.py exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BT="$ROOT/relay/scripts/backtest-verdict.py"
[[ -f "$BT" ]] || { echo "backtest-verdict.py not yet implemented (RED): $BT"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_WORKTREE_BASE="$tmp/wt"   # passed through to gather-repo-state for hermeticity

# one own repo "foo" with an open [ROUTINE] item → classify-repo must yield execute
R="$SRC_DIR/foo"; mkdir -p "$R"
git -C "$R" init -q; git -C "$R" config user.email t@e; git -C "$R" config user.name t
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:0001 -->
EOF
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

cat > "$RELAY_TOML" <<'EOF'
[repos.foo]
classification = "own"
EOF
# last dispatch for foo was a 'review' → the tool should mark it diverged (execute != review)
echo '{"kind":"dispatch","repo":"foo","mode":"review"}' > "$RELAY_EVENTS"

# report-only: must exit 0
out="$("$BT" --json)" || { echo "backtest-verdict must exit 0 (report-only)"; exit 1; }

python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
assert s["repos"] == 1, f"expected 1 own repo, got {s}"
assert s["crashes"] == 0, f"classifier crashed in backtest: {o}"
foo = [r for r in o["rows"] if r["repo"] == "foo"][0]
assert foo["verdict"] == "execute", f"foo (open [ROUTINE]) must classify execute, got {foo}"
assert foo["last"] == "review", f"last-dispatch must be review, got {foo}"
assert foo["note"] == "diverged", f"execute vs review must be 'diverged', got {foo}"
assert s["diverged"] == 1 and s["agree"] == 0, f"summary counts wrong: {s}"
print("backtest-verdict assertions OK")
PYEOF

# plain (non-json) mode also works + is report-only
"$BT" >/dev/null || { echo "plain mode must exit 0"; exit 1; }

echo "PASS test_backtest_verdict"
