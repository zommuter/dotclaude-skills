#!/usr/bin/env bash
# roadmap:5884 — classify-repo.sh must gate `strongRecheckPending` on the recorded
# strong_model: a relay.toml entry whose strong checkpoint was ALREADY produced by a
# Fable model (strong_model contains "fable", case-insensitive) must NOT queue an
# optional Fable recheck — that is a same-tier second opinion (observed: chidiai
# relay-ckpt-20260702-0048, strong_model="claude-fable-5", fable_rechecked=false →
# wasted Fable-rechecks-Fable dispatch; routed:1c2b). The write-side twin (id:6856)
# only fixes NEW checkpoints; pre-existing / non-pool-written entries need this
# read-side gate.
#
# RED until the model-aware gate lands. Hermetic: mktemp repo + fixture RELAY_TOML;
# no ~/.config touch. Idiom: test_classify_repo_standin_gate.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"
export RELAY_DECISION_QUEUE="$tmpdir/decision-queue.jsonl"
mkdir -p "$RELAY_WORKTREE_BASE"

repo="$tmpdir/fixture"
git init -q "$repo"
git -C "$repo" config user.email "t@t"
git -C "$repo" config user.name "T"
printf '# Roadmap\n\n## Items\n' > "$repo/ROADMAP.md"
printf '# TODO\n' > "$repo/TODO.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m "init"
git -C "$repo" tag -a "relay-ckpt-20260101-0000" -m "reviewer (relay-loop)" HEAD

pending_of() {
  "$CLASSIFY" --emit unit --repo fixture --path "$repo" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["strongRecheckPending"])'
}

# ── Test 1: strong_model is a Fable model → strongRecheckPending must be false ──
cat > "$RELAY_TOML" <<'TOML'
[repos.fixture]
classification = "own"
last_strong_ckpt = "relay-ckpt-20260101-0000"
strong_model = "claude-fable-5"
fable_rechecked = false
TOML
echo "Test 1: strong_model=claude-fable-5 + fable_rechecked=false → pending false"
got="$(pending_of)"
if [[ "$got" == "False" ]]; then
  ok "Fable-authored strong checkpoint never queues a Fable-rechecks-Fable review"
else
  fail_msg "strongRecheckPending should be False for a fable strong_model, got '$got' (wasted same-tier recheck, routed:1c2b)"
fi

# ── Test 2: strong_model is Opus → pending stays true (regression guard) ────────
cat > "$RELAY_TOML" <<'TOML'
[repos.fixture]
classification = "own"
last_strong_ckpt = "relay-ckpt-20260101-0000"
strong_model = "claude-opus-4-8"
fable_rechecked = false
TOML
echo "Test 2: strong_model=claude-opus-4-8 + fable_rechecked=false → pending true"
got="$(pending_of)"
if [[ "$got" == "True" ]]; then
  ok "Opus-standin strong checkpoint still invites the optional Fable recheck"
else
  fail_msg "strongRecheckPending should stay True for an Opus strong_model, got '$got'"
fi

# ── Test 3: strong_model ABSENT (legacy entry) → pending stays true ─────────────
cat > "$RELAY_TOML" <<'TOML'
[repos.fixture]
classification = "own"
last_strong_ckpt = "relay-ckpt-20260101-0000"
fable_rechecked = false
TOML
echo "Test 3: strong_model absent + fable_rechecked=false → pending true (conservative)"
got="$(pending_of)"
if [[ "$got" == "True" ]]; then
  ok "legacy entry without strong_model keeps the conservative pending default"
else
  fail_msg "strongRecheckPending should stay True when strong_model is absent, got '$got'"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
