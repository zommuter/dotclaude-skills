#!/usr/bin/env bash
# Defect-fix test — no roadmap item (regression spec for the 2026-07-01 duplicate-dispatch
# incident, run relay-20260701-202806-14640; filed follow-ups id:7b83/id:482d cover the
# structural remainder).
#
# INCIDENT: an interactive /relay session checkpointed dotclaude-skills 6× (relay-ckpt
# 1927..2110, all strong "reviewer (claude-opus-4-8, ...)" tags) WITHOUT advancing
# relay.toml's last_strong_ckpt (stuck at 1635). gather-repo-state.sh anchors the id:365b
# audit window on relay.toml's last_strong_ckpt FIRST, so substantive_unaudited stayed true
# over an already-audited window → classify-verdict re-emitted `review` every round →
# the pool re-dispatched duplicate strong reviews (observed 20:28 and 22:52 the same night,
# both burned an Opus review of already-reviewed work).
#
# SPEC: the checkpoint tags themselves carry the role in their annotation's final label line
# (ckpt-tag.sh appends it last: "reviewer (...)" / "strong-execute (...)" / "executor (...)").
# When a strong-labeled ckpt tag NEWER than the relay.toml watermark exists, the audit window
# must anchor on that tag — a lagging toml watermark must not resurrect already-audited
# commits. Executor-labeled tags must NEVER advance the strong-audit anchor (an executor
# checkpoint is not an audit — id:e030 masking direction), and the unset-watermark fallback
# ($latest tag) must stay byte-identical.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

mkrepo() {  # mkrepo <dir> — repo with one commit + strong ckpt tag relay-ckpt-20260701-1635
  local r="$1"; mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  echo code > "$r/app.sh"
  git -C "$r" add -A; git -C "$r" commit -qm init
  git -C "$r" tag -a relay-ckpt-20260701-1635 -m 'baseline review

reviewer (claude-opus-4-8, fable-standin, relay-loop)'
}

mktoml() {  # mktoml <file> <repo-name> [watermark] — minimal relay.toml block
  local f="$1" name="$2" wm="${3:-}"
  {
    printf '[repos.%s]\n' "$name"
    printf 'classification = "own"\n'
    if [[ -n "$wm" ]]; then printf 'last_strong_ckpt = "%s"\n' "$wm"; fi
  } > "$f"
}

gather() {  # gather <toml> <repo-name> <path>
  RELAY_TOML="$1" RELAY_WORKTREE_BASE="$TMP/wt" \
    "$GATHER" --repo "$2" --path "$3" --runid test
}

# --- (1) THE INCIDENT: toml watermark lags a NEWER strong-labeled ckpt tag --------------
# Substantive commits after the toml watermark, all covered by a newer strong tag at HEAD.
r1="$TMP/stale"; mkrepo "$r1"
echo feature > "$r1/feature.sh"; git -C "$r1" add -A; git -C "$r1" commit -qm 'feat: real work'
echo more > "$r1/more.sh"; git -C "$r1" add -A; git -C "$r1" commit -qm 'feat: more work'
git -C "$r1" tag -a relay-ckpt-20260701-2019 -m 'reviewed the real work

reviewer (claude-opus-4-8, integrate)'
mktoml "$TMP/t1.toml" canary-stale relay-ckpt-20260701-1635
j="$(gather "$TMP/t1.toml" canary-stale "$r1")"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "stale toml watermark + newer strong tag covering all commits → substantive_unaudited=False (no duplicate review)" \
  || bad "substantive_unaudited=True over an already-strong-audited window — the pool would re-dispatch a duplicate strong review (2026-07-01 incident)"

# --- (2) control: NEW work after the newest strong tag still audits ----------------------
echo newer > "$r1/newer.sh"; git -C "$r1" add -A; git -C "$r1" commit -qm 'feat: unaudited'
j="$(gather "$TMP/t1.toml" canary-stale "$r1")"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "substantive commit after the newest strong tag → substantive_unaudited=True (real audit never skipped)" \
  || bad "substantive_unaudited=False hid a commit newer than every strong tag"

# --- (3) executor tags never advance the strong-audit anchor ----------------------------
# Watermark = the strong 1635 tag; substantive commit; then an EXECUTOR ckpt at HEAD.
r3="$TMP/exec"; mkrepo "$r3"
echo feature > "$r3/feature.sh"; git -C "$r3" add -A; git -C "$r3" commit -qm 'feat: executor work'
git -C "$r3" tag -a relay-ckpt-20260701-1700 -m 'executor built the feature

executor (sonnet, relay-loop)'
mktoml "$TMP/t3.toml" canary-exec relay-ckpt-20260701-1635
j="$(gather "$TMP/t3.toml" canary-exec "$r3")"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "executor-labeled newer tag does NOT advance the strong anchor → work still audits (id:e030 direction)" \
  || bad "an executor checkpoint advanced the strong-audit anchor — unreviewed executor work would skip audit"

# --- (4) unset watermark keeps the existing \$latest fallback ----------------------------
# No last_strong_ckpt in toml → audit_ref = latest ckpt tag (pre-existing id:365b fallback):
# the executor tag at HEAD covers everything → substantive_unaudited=False, unchanged.
mktoml "$TMP/t4.toml" canary-exec
j="$(gather "$TMP/t4.toml" canary-exec "$r3")"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "unset watermark → \$latest fallback unchanged (executor tag at HEAD → nothing unaudited)" \
  || bad "unset-watermark fallback behavior changed"

echo "test_gather_stale_strong_watermark: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
