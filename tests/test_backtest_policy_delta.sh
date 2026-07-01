#!/usr/bin/env bash
# roadmap:0e57 — expected-policy-delta bucketing in backtest-historical.py (triage of the
# 109 candidate-classifier-worse rows, 2026-07-01, DP7 flip gate id:4d8e/a0b6).
#
# The classifier's LOWER-priority verdict is reclassified from candidate-classifier-worse to
# expected-policy-delta ONLY when it is the correct deterministic output of a decided policy
# rule for the reconstructed PRECONDITION. Crucially, a bug-shaped divergence (verdict WITHOUT
# its precondition) must STAY candidate-classifier-worse — the quality signal is preserved.
# Directly unit-tests the pure functions match_policy_delta() + derive_category() (no git
# fixture needed). Hermetic.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BH="$ROOT/relay/scripts/backtest-historical.py"
[[ -f "$BH" ]] || { echo "FAIL: backtest-historical.py not found: $BH"; exit 1; }

python3 - "$BH" <<'PYEOF'
import importlib.util, sys
sys.dont_write_bytecode = True  # don't leave a relay/scripts/__pycache__ behind (manifest test)
spec = importlib.util.spec_from_file_location("bh", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
mpd, dc = m.match_policy_delta, m.derive_category
fails = []
def ok(cond, msg):
    print(("PASS" if cond else "FAIL") + ": " + msg)
    if not cond: fails.append(msg)

def st(promote=0, surface=0, sub=False, hardpool=0):
    return {"hasRoutine": False, "substantive_unaudited": sub, "open_hard_pool": hardpool,
            "roadmap_actionable_open": 0, "unpromoted": {"promote": promote, "surface": surface}}

# ── match_policy_delta: the four decided rules fire on their precondition ──
ok(mpd("human",   st(promote=0, surface=3)) == "id:5eb3 surface-only→human", "surface-only→human rule fires")
ok(mpd("handoff", st(promote=2, surface=1)) == "promote>0→handoff",          "promote>0→handoff rule fires")
ok(mpd("review",  st(sub=True))             == "D3 substantive-unaudited→review", "substantive→review rule fires")
ok(mpd("hard",    st(hardpool=1))           == "open_hard_pool→hard",        "open_hard_pool→hard rule fires")

# ── the SIGNAL-PRESERVING negatives: verdict without its precondition → NO match (stays loud) ──
ok(mpd("human",   st(promote=2, surface=3)) is None, "human WITH promote>0 does NOT match (bug-shape stays loud)")
ok(mpd("human",   st(promote=0, surface=0)) is None, "human with no surface does NOT match")
ok(mpd("handoff", st(promote=0, surface=5)) is None, "handoff WITHOUT promotable does NOT match")
ok(mpd("review",  st(sub=False))            is None, "review WITHOUT unaudited does NOT match")
ok(mpd("hard",    st(hardpool=0))           is None, "hard WITHOUT open_hard_pool does NOT match")
ok(mpd("idle",    st())                     is None, "idle matches no rule")

# ── derive_category: reclassification only in the candidate-worse direction, gap wins ──
# human(5) vs shard review(2): v_rank>m_rank (candidate-worse direction). Rule matches → expected-policy-delta.
ok(dc("human", "review", [], st(promote=0, surface=3)) == "expected-policy-delta",
   "surface-only→human diverge buckets expected-policy-delta")
# same shape but a reconstruction gap present → gap takes precedence (never hidden as policy-delta)
ok(dc("human", "review", ["legacy-lane-vocab"], st(promote=0, surface=3)) == "reconstruction-gap",
   "gap precedence over expected-policy-delta")
# bug-shape: human but promote>0 → no rule → stays candidate-classifier-worse (LOUD)
ok(dc("human", "review", [], st(promote=2, surface=3)) == "candidate-classifier-worse",
   "bug-shape (human w/ promote>0) stays candidate-classifier-worse")
# a genuine miss with no matching rule stays loud: idle(6) vs execute(1)
ok(dc("idle", "execute", [], st()) == "candidate-classifier-worse",
   "unexplained lower-priority diverge stays candidate-classifier-worse")
# classifier-better direction is unaffected: execute(1) vs shard human(5), v_rank<m_rank
ok(dc("execute", "human", [], st()) == "classifier-better",
   "higher-priority diverge still classifier-better (unaffected)")

sys.exit(1 if fails else 0)
PYEOF
echo "ALL PASS"
