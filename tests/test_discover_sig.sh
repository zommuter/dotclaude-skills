#!/usr/bin/env bash
# roadmap:c3a6 — content-addressed discovery cache. discover-sig.sh computes a per-repo SUPERSET
# signature over every input the discovery shard classifier reads, so the relay pool can skip
# re-classifying (an LLM shard) a repo whose observable state is unchanged since last round.
# Correctness rule: OVER-invalidation is safe (a wasted re-classify); only UNDER-invalidation is
# dangerous (a stale verdict). So every classifier input MUST move the signature, and any git error
# MUST fail open (empty sentinel sig → caller re-classifies). This test proves both.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIG="$SRC_DIR/relay/scripts/discover-sig.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SIG" ]] || fail "discover-sig.sh not found or not executable: $SIG"

# ── hermetic scratch: a throwaway git repo + overridable relay.toml + worktree base ──
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"
export RELAY_WORKTREE_BASE="$TMP/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

REPO="$TMP/widget"
git init -q "$REPO"
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'roadmap\n- [ ] [ROUTINE] do a thing\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
cat > "$RELAY_TOML" <<'TOML'
[repos.widget]
classification = "own"
income = false
TOML

# helper: emit the signature for the single repo "widget" (not in liveClaims unless arg given)
sig_of() {
  local claims="${1:-[]}"
  printf '{"repos":[{"repo":"widget","path":"%s"}],"liveClaims":%s}\n' "$REPO" "$claims" \
    | "$SIG" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])'
}

# (1) Deterministic — same state, two invocations, identical sig.
S1="$(sig_of)"; S2="$(sig_of)"
[[ -n "$S1" ]] || fail "signature is empty for a valid repo (should only be empty on fail-open)"
[[ "$S1" == "$S2" ]] || fail "signature not deterministic: '$S1' != '$S2'"
pass "deterministic + non-empty for a valid repo"

# (2) Superset coverage — each input independently MUST change the sig.
changed() { # <prev> <mutation-label>; recompute, assert differs, echo new
  local prev="$1" label="$2" new; new="$(sig_of)"
  [[ "$new" != "$prev" ]] || fail "signature did NOT change after: $label (under-invalidation = stale verdict)"
  echo "$new"
}

# 2a HEAD (new commit)
echo x >> "$REPO/file"; git -C "$REPO" add -A; git -C "$REPO" commit -qm c2
S="$(changed "$S1" "new commit / HEAD")"
# 2b checkpoint tag list
git -C "$REPO" tag -a relay-ckpt-1 -m "ckpt one"
S="$(changed "$S" "new relay-ckpt-* tag")"
# 2c latest tag MESSAGE (fable-standin detection lives in the message)
git -C "$REPO" tag -d relay-ckpt-1 >/dev/null
git -C "$REPO" tag -a relay-ckpt-1 -m "ckpt one, fable-standin"
S="$(changed "$S" "latest tag message")"
# 2d ROADMAP.md content (hasRoutine / openHard / GATED all derive from it)
printf 'roadmap\n- [ ] [HARD — strong model] big thing\n' > "$REPO/ROADMAP.md"
S="$(changed "$S" "ROADMAP.md edit")"
# 2e dirty working tree (porcelain)
echo dirty > "$REPO/untracked"
S="$(changed "$S" "dirty working tree / porcelain")"
git -C "$REPO" add -A; git -C "$REPO" commit -qm clean
S="$(sig_of)"  # re-baseline after committing
# 2f worktree dir appears (stale/claimed-elsewhere signal)
mkdir -p "$RELAY_WORKTREE_BASE/widget/relay-20260101-1"
S="$(changed "$S" "worktree directory appears")"
# 2g relay/orphan/* ref (suppress-redispatch signal)
git -C "$REPO" branch relay/orphan/widget
S="$(changed "$S" "relay/orphan/* ref appears")"
# 2h relay.toml block (income/intensive/strongRecheckPending/path)
cat > "$RELAY_TOML" <<'TOML'
[repos.widget]
classification = "own"
income = true
intensive = "local-llm"
TOML
S="$(changed "$S" "relay.toml block edit")"
# 2i in-liveClaims flag (GLOBAL claim.sh peek state, not the repo's own files)
SN="$(sig_of '["widget"]')"
[[ "$SN" != "$S" ]] || fail "signature did NOT change when repo entered liveClaims (claimed-elsewhere verdict would go stale)"
# 2j decision-queue records (OUTSIDE the repo; classifier depends on them via
# unpromoted-scan case-g + resolved-record exclusion — 2026-07-02 fix): filing an entry
# must invalidate; resolving it must invalidate again.
export RELAY_DECISION_QUEUE="$TMP/dq.jsonl"
DQID="$("$(dirname "$SIG")/decision-queue.sh" add --repo widget --kind lane-triage --question "Assign a lane to TODO id:abcd: x" --source-id abcd)"
S="$(changed "$S" "decision-queue entry filed")"
"$(dirname "$SIG")/decision-queue.sh" resolve "$DQID" --answer "parked" >/dev/null
S="$(changed "$S" "decision-queue entry resolved")"
pass "superset covers HEAD, tags, tag-message, ROADMAP, porcelain, worktree, orphan-ref, relay.toml, liveClaims, decision-queue"

# (3) Fail-open — a non-git path yields an empty sentinel sig (exit 0), so the caller re-classifies.
OUT="$(printf '{"repos":[{"repo":"ghost","path":"%s/nope"}],"liveClaims":[]}\n' "$TMP" | "$SIG")" \
  || fail "discover-sig.sh exited non-zero on a bad repo path (must fail open, exit 0)"
GSIG="$(echo "$OUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])')"
[[ -z "$GSIG" ]] || fail "non-git path did not produce an empty sentinel sig (got '$GSIG')"
pass "fail-open: git error → empty sentinel sig, exit 0"

pass "discover-sig.sh computes a fail-open superset signature (c3a6)"
