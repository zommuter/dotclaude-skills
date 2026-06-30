#!/usr/bin/env bash
# roadmap:0e57
# Fidelity tests for relay/scripts/backtest-historical.py (id:0e57) — three fidelity passes.
#
# (a) per-row reason+evidence + reconstructed input fields in --json output
# (b) reconstruction-gap:legacy-lane-vocab for shard=hard rows where open_hard_pool=0
#     but legacy [HARD — <non-lane>] items exist in the as-of ROADMAP
# (c) tag-time filter: a ckpt tag created AFTER the event ts does NOT suppress
#     substantive_unaudited (a future tag must not count as "already audited")
# (d) reconstruction-gap:9973 note (gate is applied from git-show state; test
#     verifies the gate fires and is reflected in reconstructed fields)
# (e) output reframe: summary leads with candidate-classifier-worse count, not agree%
#
# Hermetic: all state in mktemp -d; never touches ~/.config, ~/.claude, or live repos.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BH="$ROOT/relay/scripts/backtest-historical.py"
[[ -f "$BH" ]] || { echo "backtest-historical.py not found (RED): $BH"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_SHADOW_LOG="$tmp/shadow.jsonl"

# ── Helper: init git repo with identity ──────────────────────────────────────
init_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.email "t@e"
  git -C "$path" config user.name "t"
}

# ── relay.toml with two repos ─────────────────────────────────────────────────
cat > "$RELAY_TOML" <<'EOF'
[repos.legacy-hard-repo]
classification = "own"

[repos.routine-repo]
classification = "own"

[repos.recurring-audit-repo]
classification = "own"
EOF

# ===========================================================================
# REPO 1: legacy-hard-repo — has [HARD — strong model] (pre-id:78ff vocab)
#   The shard dispatched it as "hard"; classifier sees open_hard_pool=0 because
#   it only counts [HARD — pool] (post-id:78ff). This is a legacy-lane-vocab gap.
# ===========================================================================
R1="$SRC_DIR/legacy-hard-repo"
init_repo "$R1"

cat > "$R1/ROADMAP.md" <<'EOF'
# Roadmap
## Hard
- [ ] [HARD — strong model] Old-style hard item <!-- id:aa01 -->
EOF
cat > "$R1/TODO.md" <<'EOF'
# TODO
## Current
- [ ] some task <!-- id:bb01 -->
EOF
git -C "$R1" add -A
GIT_COMMITTER_DATE="2026-06-10T10:00:00Z" \
  git -C "$R1" commit -qm "initial" --date="2026-06-10T10:00:00Z"
GIT_COMMITTER_DATE="2026-06-10T10:00:00Z" \
  git -C "$R1" tag -a "relay-ckpt-20260610-1000" -m "relay: checkpoint"

# Dispatch event at 2026-06-15: shard said "hard" (old vocab), classifier will say handoff or idle
# because [HARD — strong model] does NOT count as [HARD — pool] and the unpromoted TODO item
# bb01 is not in ROADMAP → handoff.

# ===========================================================================
# REPO 2: routine-repo — execute vs review diverge (classifier-better)
# ===========================================================================
R2="$SRC_DIR/routine-repo"
init_repo "$R2"

cat > "$R2/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:cc01 -->
EOF
cat > "$R2/TODO.md" <<'EOF'
# TODO
## Current
- [x] done item
EOF
git -C "$R2" add -A
GIT_COMMITTER_DATE="2026-06-12T10:00:00Z" \
  git -C "$R2" commit -qm "initial with routine" --date="2026-06-12T10:00:00Z"
GIT_COMMITTER_DATE="2026-06-12T10:00:00Z" \
  git -C "$R2" tag -a "relay-ckpt-20260612-1000" -m "relay: checkpoint"

# Shard dispatched as "review" (wrong — there's open ROUTINE which outranks review)
# Classifier should say "execute" → classifier-better

# ===========================================================================
# REPO 3: recurring-audit-repo — test the id:9973 gate
#   Has a [HARD — pool] item with relay:recurring-audit.
#   Latest commit is only a relay: checkpoint → sub_unaudited=false
#   → 9973 gate fires: item is NOT counted in open_hard_pool
# ===========================================================================
R3="$SRC_DIR/recurring-audit-repo"
init_repo "$R3"

cat > "$R3/ROADMAP.md" <<'EOF'
# Roadmap
## Hard
- [ ] [HARD — pool] Recurring audit item <!-- relay:recurring-audit --> <!-- id:dd01 -->
EOF
cat > "$R3/TODO.md" <<'EOF'
# TODO
EOF
git -C "$R3" add -A
GIT_COMMITTER_DATE="2026-06-12T10:00:00Z" \
  git -C "$R3" commit -qm "initial" --date="2026-06-12T10:00:00Z"
GIT_COMMITTER_DATE="2026-06-12T10:00:00Z" \
  git -C "$R3" tag -a "relay-ckpt-20260612-1000" -m "relay: checkpoint"

# Add only a checkpoint commit (non-substantive) → sub_unaudited stays false
cat >> "$R3/ROADMAP.md" <<'EOF'
<!-- relay-note: checkpoint only -->
EOF
git -C "$R3" add -A
GIT_COMMITTER_DATE="2026-06-15T10:00:00Z" \
  git -C "$R3" commit -qm "relay: checkpoint" --date="2026-06-15T10:00:00Z"
GIT_COMMITTER_DATE="2026-06-15T10:00:00Z" \
  git -C "$R3" tag -a "relay-ckpt-20260615-1000" -m "relay: checkpoint"

# Shard dispatched as "hard" (it counted the recurring-audit item);
# classifier applies 9973 gate: sub_unaudited=false → item excluded → open_hard_pool=0
# → verdict=idle (no other work). Diverge. The 9973 gate was applied → note it.

# ===========================================================================
# TAG-TIME FILTER REPO: future-tag-repo (inline, no relay.toml entry needed
# for the tag-time unit test — we test via the compute_substantive_unaudited
# helper directly using a separate script invocation below)
# ===========================================================================

# ===========================================================================
# Build a fourth repo specifically for the tag-time filter test (case c)
# This repo needs a ckpt tag created AFTER the event timestamp
# ===========================================================================
cat >> "$RELAY_TOML" <<'EOF'

[repos.future-tag-repo]
classification = "own"
EOF

R4="$SRC_DIR/future-tag-repo"
init_repo "$R4"

# C1: substantive commit (not a checkpoint) at T1
printf '# Work\nsome content\n' > "$R4/work.md"
git -C "$R4" add -A
GIT_COMMITTER_DATE="2026-06-10T10:00:00Z" \
  git -C "$R4" commit -qm "substantive work" --date="2026-06-10T10:00:00Z"

# C2: more substantive work at T2 < event_ts
printf 'more work\n' >> "$R4/work.md"
git -C "$R4" add -A
GIT_COMMITTER_DATE="2026-06-12T10:00:00Z" \
  git -C "$R4" commit -qm "more work" --date="2026-06-12T10:00:00Z"
C4_HEAD="$(git -C "$R4" rev-parse HEAD)"

# Ckpt tag created AFTER the event timestamp (2026-06-20 > 2026-06-15)
# This tag SHOULD NOT be used to suppress sub_unaudited for events before 2026-06-20
GIT_COMMITTER_DATE="2026-06-20T10:00:00Z" \
  git -C "$R4" tag -a "relay-ckpt-20260620-1000" -m "relay: checkpoint"

cat > "$R4/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] future work <!-- id:ee01 -->
EOF
git -C "$R4" add -A
GIT_COMMITTER_DATE="2026-06-25T10:00:00Z" \
  git -C "$R4" commit -qm "add roadmap" --date="2026-06-25T10:00:00Z"

# ===========================================================================
# Write fixture events
# ===========================================================================
cat > "$RELAY_EVENTS" <<'EOF'
{"kind":"dispatch","repo":"legacy-hard-repo","ts":"2026-06-15T12:00:00Z","mode":"hard","tier":"strong","round":1}
{"kind":"dispatch","repo":"routine-repo","ts":"2026-06-15T12:00:00Z","mode":"review","tier":"strong","round":1}
{"kind":"dispatch","repo":"recurring-audit-repo","ts":"2026-06-15T12:00:00Z","mode":"hard","tier":"strong","round":1}
{"kind":"dispatch","repo":"future-tag-repo","ts":"2026-06-15T12:00:00Z","mode":"review","tier":"strong","round":1}
EOF

# ===========================================================================
# Run the backtest
# ===========================================================================
out="$(python3 "$BH" --json 2>"$tmp/stderr.txt")" \
  || { echo "FAIL: backtest-historical must exit 0 (report-only)"; exit 1; }

# ── Case (a): per-row reason+evidence+reconstructed fields ───────────────────
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
s = o["summary"]
rows = o["rows"]

# Hard gate: 0 crashes
assert s["crashes"] == 0, f"0 crashes required (hard gate): {s}"

# Every processed row must have classifier_reason, classifier_evidence, reconstructed
# (even agree rows should carry these for traceability)
processed = [r for r in rows if r.get("note") not in ("new", None) and not (r.get("note","").startswith("ERR"))]
assert len(processed) >= 1, f"expected at least 1 processed row, got {rows}"

for r in processed:
    assert "classifier_reason" in r, f"row missing classifier_reason: {r}"
    assert "classifier_evidence" in r, f"row missing classifier_evidence: {r}"
    assert isinstance(r["classifier_evidence"], list), f"classifier_evidence must be a list: {r}"
    assert "reconstructed" in r, f"row missing reconstructed dict: {r}"
    rc = r["reconstructed"]
    for field in ("hasRoutine", "substantive_unaudited", "open_hard_pool",
                  "roadmap_actionable_open", "unpromoted"):
        assert field in rc, f"reconstructed missing '{field}': {rc}"
    assert "promote" in rc["unpromoted"] and "surface" in rc["unpromoted"], \
        f"reconstructed unpromoted must have promote+surface: {rc}"

print("case (a) per-row reason+evidence+reconstructed OK")
PYEOF

# ── Case (b): legacy-lane-vocab reconstruction gap ───────────────────────────
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
rows = o["rows"]

legacy = [r for r in rows if r["repo"] == "legacy-hard-repo"]
assert len(legacy) == 1, f"expected 1 legacy-hard-repo row, got {legacy}"
r = legacy[0]
# Classifier must NOT agree with "hard" (open_hard_pool=0 for [HARD — strong model])
assert r["verdict"] != "hard", \
    f"[HARD — strong model] must NOT count as open_hard_pool — expected non-hard verdict, got {r}"
# The row must be a diverge (shard said hard, classifier saw open_hard_pool=0)
assert r["note"] == "diverge", f"legacy-hard-repo must diverge: {r}"
# And it must be categorized as reconstruction-gap:legacy-lane-vocab
assert r.get("category") == "reconstruction-gap", \
    f"legacy lane vocab diverge must be reconstruction-gap, got category={r.get('category')!r}: {r}"
assert "legacy-lane-vocab" in r.get("reconstruction_gap_flags", []), \
    f"reconstruction_gap_flags must contain 'legacy-lane-vocab': {r}"
# Also verify the reconstructed open_hard_pool is 0 (legacy tag was not counted)
assert r["reconstructed"]["open_hard_pool"] == 0, \
    f"[HARD — strong model] must yield open_hard_pool=0, got {r['reconstructed']['open_hard_pool']}"

print("case (b) legacy-lane-vocab reconstruction-gap OK")
PYEOF

# ── Case (c): tag-time filter — future ckpt tag does NOT suppress sub_unaudited ─
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
rows = o["rows"]

ftr = [r for r in rows if r["repo"] == "future-tag-repo"]
assert len(ftr) == 1, f"expected 1 future-tag-repo row, got {ftr}"
r = ftr[0]
# The ckpt tag was created AFTER the event ts (2026-06-20 > 2026-06-15).
# The commits C1+C2 are NOT checkpoint commits → they ARE substantive.
# Without the tag-time filter, the tag would make sub_unaudited=False (wrong).
# With the filter, sub_unaudited must be True (the tag is excluded).
assert r["reconstructed"]["substantive_unaudited"] == True, \
    f"Future ckpt tag (created 2026-06-20) must NOT suppress sub_unaudited " \
    f"for event at 2026-06-15: {r['reconstructed']}"

print("case (c) tag-time filter OK (future ckpt tag excluded)")
PYEOF

# ── Case (d): id:9973 recurring-audit gate reflected in reconstructed fields ──
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
rows = o["rows"]

ra = [r for r in rows if r["repo"] == "recurring-audit-repo"]
assert len(ra) == 1, f"expected 1 recurring-audit-repo row, got {ra}"
r = ra[0]
# sub_unaudited should be False (only relay: checkpoint commits since the ckpt tag)
assert r["reconstructed"]["substantive_unaudited"] == False, \
    f"Only ckpt commits since tag → sub_unaudited must be False: {r['reconstructed']}"
# 9973 gate: open_hard_pool must be 0 (recurring-audit item excluded when sub_unaudited=False)
assert r["reconstructed"]["open_hard_pool"] == 0, \
    f"relay:recurring-audit item with sub_unaudited=False must yield open_hard_pool=0: {r['reconstructed']}"
# The row diverges (shard said hard, classifier says idle/something else)
assert r["note"] == "diverge", f"recurring-audit-repo must diverge: {r}"

print("case (d) id:9973 gate reflected in open_hard_pool=0 OK")
PYEOF

# ── Case (e): classifier-better for execute-vs-review ────────────────────────
python3 - "$out" <<'PYEOF'
import json, sys
o = json.loads(sys.argv[1])
rows = o["rows"]

rr = [r for r in rows if r["repo"] == "routine-repo"]
assert len(rr) == 1, f"expected 1 routine-repo row, got {rr}"
r = rr[0]
assert r["verdict"] == "execute", f"open [ROUTINE] must classify execute: {r}"
assert r["note"] == "diverge", f"shard said review, classifier says execute → diverge: {r}"
assert r.get("category") == "classifier-better", \
    f"execute (rank 1) vs shard review (rank 2): must be classifier-better, got {r.get('category')!r}"

print("case (e) classifier-better for execute > review OK")
PYEOF

# ── Case (f): summary reframe — candidate-classifier-worse leads, agree% demoted ──
plain_out="$(python3 "$BH" 2>/dev/null)"
# The plain output must mention "candidate-classifier-worse" (or the count)
echo "$plain_out" | grep -qi "candidate.classifier.worse\|candidate_classifier_worse" \
  || { echo "FAIL: plain output must lead with candidate-classifier-worse count"; exit 1; }
# Must NOT lead with "agree=" or "agreement %" as the headline signal
first_line="$(echo "$plain_out" | head -1)"
echo "$first_line" | grep -qi "^agree\|^agreement" \
  && { echo "FAIL: first summary line must NOT be agree count: $first_line"; exit 1; }

echo "case (f) output reframe OK (candidate-classifier-worse leads)"

# ── Case (g): read-only guard ─────────────────────────────────────────────────
for repo_path in "$R1" "$R2" "$R3" "$R4"; do
  wt="$(git -C "$repo_path" worktree list 2>/dev/null | wc -l)"
  [[ "$wt" -eq 1 ]] \
    || { echo "FAIL: extra worktrees in $repo_path after run; count=$wt"; exit 1; }
done
echo "case (g) read-only guard OK (no extra worktrees)"

echo "PASS test_backtest_fidelity"
