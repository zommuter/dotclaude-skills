#!/usr/bin/env bash
# roadmap:a42e — classify-repo.sh must gate the `standin` flag on the durable
# fable_rechecked watermark (id:e030): a checkpoint annotation that merely MENTIONS
# "fable-standin" (e.g. a genuine Fable recheck describing the standin review it
# audited) must NOT re-trigger standin once fable_rechecked is set — otherwise
# relay-loop.js's `standin || strongRecheckPending` elevation re-dispatches an
# idle→review on EVERY Fable pool round (observed: redundant zkm dispatch,
# run relay-20260701-234115, empty window; routed:f3d0).
#
# RED until the `standin && !fable_rechecked` gate lands. Hermetic: mktemp repo +
# fixture RELAY_TOML; no ~/.config touch.

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
# A GENUINE Fable recheck checkpoint whose annotation MENTIONS the standin review it
# audited (the routed:f3d0 zkm case, relay-ckpt-20260701-2315).
git -C "$repo" tag -a "relay-ckpt-20260101-0000" \
  -m "reviewer (claude-fable-5, recheck) — audited the fable-standin review of 2026-01-01" HEAD

standin_of() {
  "$CLASSIFY" --emit unit --repo fixture --path "$repo" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["standin"])'
}

# ── Test 1: fable_rechecked SET → standin must be false ───────────────────────
cat > "$RELAY_TOML" <<'TOML'
[repos.fixture]
classification = "own"
last_strong_ckpt = "relay-ckpt-20260101-0000"
strong_model = "claude-fable-5"
fable_rechecked = "2026-07-01"
TOML
echo "Test 1: recheck consumed (fable_rechecked set) → standin false"
got="$(standin_of)"
if [[ "$got" == "False" ]]; then
  ok "standin gated off by the consumed watermark"
else
  fail_msg "standin should be False once fable_rechecked is set, got '$got' (perpetual re-dispatch class)"
fi

# ── Test 2: fable_rechecked ABSENT → standin stays true (regression guard) ────
cat > "$RELAY_TOML" <<'TOML'
[repos.fixture]
classification = "own"
TOML
echo "Test 2: no recheck watermark → standin true (genuine pending recheck)"
got="$(standin_of)"
if [[ "$got" == "True" ]]; then
  ok "genuine standin mention still elevates"
else
  fail_msg "standin should stay True without a fable_rechecked watermark, got '$got'"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
