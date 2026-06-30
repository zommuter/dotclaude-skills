#!/usr/bin/env bash
# roadmap:0e57
# Tests for relay/scripts/backtest-historical.py (id:0e57) — historical verdict replay.
#
# Hermetic: builds temp git repos, fixture relay-events.jsonl and relay.toml; never
# touches ~/.config, ~/.claude, or the real own repos.
#
# Three assertions (per the id:0e57 spec):
#   (a) a 'review' event resolves against a commit with open [ROUTINE] work and the
#       historical verdict matches/diverges as expected; --json output is parseable
#       and contains the expected agree/diverge counts; 0 crashes (hard gate).
#   (b) the tool is read-only on the target repo: git worktree list shows only the
#       main worktree and the branch set is unchanged after the run.
#   (c) exit 0, plain mode also works.
#
# RED until relay/scripts/backtest-historical.py exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BH="$ROOT/relay/scripts/backtest-historical.py"
[[ -f "$BH" ]] || { echo "backtest-historical.py not yet implemented (RED): $BH"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_WORKTREE_BASE="$tmp/wt"

# ── Build test repo "myrepo" ──────────────────────────────────────────────────
# Commit 1 (C1): initial — only a TODO item, no ROADMAP
R="$SRC_DIR/myrepo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email "t@e"
git -C "$R" config user.name "t"

printf '# TODO\n## Current\n- [ ] some task <!-- id:aa01 -->\n' > "$R/TODO.md"
git -C "$R" add -A
GIT_COMMITTER_DATE="2026-06-10T10:00:00Z" \
  git -C "$R" commit -qm "initial" --date="2026-06-10T10:00:00Z"
C1="$(git -C "$R" rev-parse HEAD)"

# Checkpoint tag at C1
git -C "$R" tag -a "relay-ckpt-20260610-1000" -m "relay: checkpoint" "$C1"

# Commit 2 (C2): add ROADMAP with open [ROUTINE] item → classify = execute
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:aa01 -->
EOF
git -C "$R" add -A
GIT_COMMITTER_DATE="2026-06-15T12:00:00Z" \
  git -C "$R" commit -qm "add roadmap" --date="2026-06-15T12:00:00Z"
C2="$(git -C "$R" rev-parse HEAD)"

# Commit 3 (C3): close the ROUTINE item and clear TODO → classify = idle
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [x] [ROUTINE] do the thing <!-- id:aa01 --> done
EOF
printf '# TODO\n## Done\n' > "$R/TODO.md"
git -C "$R" add -A
GIT_COMMITTER_DATE="2026-06-20T14:00:00Z" \
  git -C "$R" commit -qm "close routine item" --date="2026-06-20T14:00:00Z"
C3="$(git -C "$R" rev-parse HEAD)"

# Checkpoint tag at C3 so there is no unaudited work after C3
git -C "$R" tag -a "relay-ckpt-20260620-1400" -m "relay: checkpoint" "$C3"

# ── relay.toml pointing at myrepo ────────────────────────────────────────────
cat > "$RELAY_TOML" <<'EOF'
[repos.myrepo]
classification = "own"
EOF

# ── fixture events ────────────────────────────────────────────────────────────
# Event A: ts=2026-06-15T13:00:00Z → resolves to C2 (open ROUTINE)
#           reconstructed verdict = execute; event mode = execute  → AGREE
# Event B: ts=2026-06-20T10:00:00Z → resolves to C2 (open ROUTINE still)
#           reconstructed verdict = execute; event mode = review   → DIVERGE
# Event C: ts=2026-06-20T15:00:00Z → resolves to C3 (no open items, ckpt at C3)
#           reconstructed verdict = idle;    event mode = idle     → AGREE
# Event D: non-own repo "nonexistent" → must be SKIPPED (counted in skipped, not events)
cat > "$RELAY_EVENTS" <<'EOF'
{"kind":"dispatch","repo":"myrepo","ts":"2026-06-15T13:00:00Z","mode":"execute","tier":"strong","round":1}
{"kind":"dispatch","repo":"myrepo","ts":"2026-06-20T10:00:00Z","mode":"review","tier":"strong","round":2}
{"kind":"dispatch","repo":"myrepo","ts":"2026-06-20T15:00:00Z","mode":"idle","tier":"strong","round":3}
{"kind":"dispatch","repo":"nonexistent","ts":"2026-06-20T15:00:00Z","mode":"review","tier":"strong","round":3}
EOF

# ── Case (a): parseable --json output, 0 crashes, correct agree/diverge counts ──
out="$(python3 "$BH" --json 2>/tmp/stderr_bh_a.txt)" \
  || { echo "FAIL: backtest-historical must exit 0 (report-only)"; exit 1; }

python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]

# Hard gate: 0 crashes
assert s["crashes"] == 0, f"0 crashes required (hard gate): {s}"
assert s["mode"] == "historical", f"mode must be 'historical': {s}"

# 3 own-repo events processed; nonexistent is skipped
assert s["events"] == 3, f"expected 3 processed events (nonexistent skipped), got {s}"
assert s["skipped"] >= 1, f"nonexistent repo must be in skipped count, got {s}"

rows = o["rows"]
assert len(rows) == 3, f"expected 3 rows (skipped events not in rows), got {len(rows)}"

# Event A: C2 has open [ROUTINE] → execute; event mode = execute → agree
a = [r for r in rows if r["ts"] == "2026-06-15T13:00:00Z"][0]
assert a["verdict"] == "execute", f"C2 (open [ROUTINE]) must classify execute, got {a}"
assert a["note"] == "agree",      f"event A (mode=execute) must agree, got {a}"

# Event B: C2 again but event mode = review → diverge
b = [r for r in rows if r["ts"] == "2026-06-20T10:00:00Z"][0]
assert b["verdict"] == "execute", f"C2 still has open [ROUTINE] → execute, got {b}"
assert b["note"] == "diverge",    f"event B (mode=review) must diverge, got {b}"

# Event C: C3 (no open items, ckpt at C3 → no unaudited) → idle; event mode = idle → agree
c = [r for r in rows if r["ts"] == "2026-06-20T15:00:00Z"][0]
assert c["verdict"] == "idle", f"C3 (no open items, clean after ckpt) must classify idle, got {c}"
assert c["note"] == "agree",   f"event C (mode=idle) must agree, got {c}"

assert s["agree"] == 2,  f"expected 2 agrees (A and C), got {s}"
assert s["diverge"] == 1, f"expected 1 diverge (B), got {s}"

# per_mode_agreement must contain each event mode that was processed
assert "execute" in s["per_mode_agreement"], f"per_mode_agreement missing 'execute': {s}"
assert "review"  in s["per_mode_agreement"], f"per_mode_agreement missing 'review': {s}"
assert "idle"    in s["per_mode_agreement"], f"per_mode_agreement missing 'idle': {s}"

print("case (a) assertions OK (0 crashes, correct agree/diverge, parseable JSON)")
PYEOF

# ── Case (b): read-only constraint — no extra worktrees or branches created ──
branches_before="$(git -C "$R" branch -l 2>/dev/null | sort)"
python3 "$BH" --json > /dev/null 2>/dev/null

wt_count="$(git -C "$R" worktree list 2>/dev/null | wc -l)"
[[ "$wt_count" -eq 1 ]] \
  || { echo "FAIL: script created extra worktrees in target repo; count=$wt_count"; exit 1; }

branches_after="$(git -C "$R" branch -l 2>/dev/null | sort)"
[[ "$branches_before" == "$branches_after" ]] \
  || { echo "FAIL: branch set changed after run (read-only violation)"; exit 1; }

echo "case (b) read-only constraint OK (worktrees=1, branch set unchanged)"

# ── Case (c): plain mode exits 0 and produces output ─────────────────────────
python3 "$BH" > /dev/null \
  || { echo "FAIL: plain mode must exit 0"; exit 1; }
echo "case (c) plain-mode exit 0 OK"

# ── Optional: --since filters events ─────────────────────────────────────────
out2="$(python3 "$BH" --since 2026-06-20 --json 2>/dev/null)" \
  || { echo "FAIL: --since must exit 0"; exit 1; }
python3 - "$out2" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
assert s["crashes"] == 0, f"0 crashes with --since: {s}"
# Only events B and C qualify (ts >= 2026-06-20); event A pre-dates
assert s["events"] == 2, f"--since 2026-06-20 should yield 2 events, got {s}"
print("case (--since filter) OK")
PYEOF

echo "PASS test_backtest_historical"
