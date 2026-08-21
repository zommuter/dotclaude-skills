#!/usr/bin/env bash
# roadmap:66d9 — provisionWorktree() must fail CLOSED.
#
# RED SPEC authored at handoff 2026-08-11. The defect: relay-loop.js:2777-2789 discards the
# mechanical hop's return value and only catches a `throw`, but the proxy reports command
# failure in the RESPONSE BODY (mechanical-proxy.py:613-617 → "MECH-ERROR exit=<n>"), never by
# throwing. So a refused/errored provision returns `true` and a child is dispatched into a repo
# with no worktree — the id:c6c8 hazard id:34b7 was closed to remove.
#
# The fix is fail-closed by POSITIVE TOKEN, not by error-sniffing: sniffing for "MECH-ERROR" is
# itself fail-open, because an unrecognised body (a 404 passthrough, a harness message, a
# truncated read) is not that string and would sail through. The script self-verifies and emits
# `PROVISION-OK <path>`; the parent returns true ONLY on that token.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/provision-worktree.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "provision-worktree.sh not found/executable at $SH"

# ── hermetic fixture: a real git repo in a temp dir (never touches ~/.claude or ~/src) ──
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init

# ── (1) happy path: registration + branch + the PROVISION-OK token ───────────────────────
WT1="$TMP/wt1"
out="$("$SH" "$REPO" "$WT1" relay/test-a)" || fail "provision-worktree.sh exited non-zero on a clean provision"

grep -q "$(cd "$WT1" && pwd)" < <(git -C "$REPO" worktree list --porcelain) \
  || fail "worktree was not registered in 'git worktree list'"
git -C "$REPO" rev-parse --verify -q refs/heads/relay/test-a >/dev/null \
  || fail "branch relay/test-a was not created"
pass "clean provision registers the worktree and creates the branch"

# THE RED ASSERTION — the parent has no other channel: the Workflow sandbox is fs-less, so a
# positive token on stdout is the ONLY way it can distinguish success from a 404'd passthrough.
[[ "$(printf '%s\n' "$out" | tail -1)" == PROVISION-OK\ * ]] \
  || fail "stdout's last line is not 'PROVISION-OK <path>' (got: '$(printf '%s\n' "$out" | tail -1)') — the parent cannot verify success without it"
pass "clean provision prints PROVISION-OK <path> as its last stdout line"

# ── (2) failure path: an ALREADY-EXISTING branch must exit non-zero AND emit no token ─────
WT2="$TMP/wt2"
rc=0
out2="$("$SH" "$REPO" "$WT2" relay/test-a 2>/dev/null)" || rc=$?
[[ "$rc" -ne 0 ]] || fail "provision-worktree.sh exited 0 for an already-existing branch"
grep -q "PROVISION-OK" <<<"$out2" \
  && fail "a FAILED provision still emitted the PROVISION-OK token — the token would certify a broken worktree"
pass "an already-existing branch exits non-zero and emits no PROVISION-OK token"

# ── (3) self-verification: the script must ASSERT its own postcondition, not assume it ────
# `git worktree add` succeeding is not proof the worktree is usable; the script is the only
# actor with filesystem access, so the verification has to live here.
grep -q "worktree list" "$SH" \
  || fail "provision-worktree.sh never runs 'git worktree list' — it does not verify registration"
grep -q "rev-parse --verify" "$SH" \
  || fail "provision-worktree.sh never runs 'rev-parse --verify' — it does not verify the branch exists"
pass "provision-worktree.sh self-verifies registration and branch before exiting"

# The deliberate best-effort symlink lines must SURVIVE (a repo lacking node_modules/.venv is a
# no-op, not a failure). Guard against an over-eager "remove all || true" refactor.
grep -q "node_modules" "$SH" || fail "the node_modules provisioning line was removed"
grep -q "|| true" "$SH" || fail "the deliberate best-effort '|| true' on the symlink lines was removed"
pass "the best-effort symlink provisioning is preserved"

# ── (4) parent side: the hop's return value must be BOUND and TESTED ──────────────────────
node --check "$JS" || fail "relay-loop.js fails node --check"

# Extract provisionWorktree()'s body (from its declaration to the next top-level `async function`).
body="$(awk '/^async function provisionWorktree/,/^}/' "$JS")"
[[ -n "$body" ]] || fail "could not locate provisionWorktree() in relay-loop.js"

grep -Eq '(const|let|var)[[:space:]]+[A-Za-z_]+[[:space:]]*=[[:space:]]*await agent\(' <<<"$body" \
  || fail "provisionWorktree() does not BIND the await agent(...) result — it cannot inspect the hop's outcome (this is the fail-open)"
pass "provisionWorktree() binds the mechanical hop's return value"

grep -q "PROVISION-OK" <<<"$body" \
  || fail "provisionWorktree() never tests for the PROVISION-OK token — it cannot fail closed"
pass "provisionWorktree() gates its true-return on the PROVISION-OK token"

# `return true` must not be reachable without consulting the token: no bare `return true` that
# precedes the token check in the function body.
first_true="$(head -1 < <(grep -n 'return true' <<<"$body") | cut -d: -f1 || true)"
first_tok="$(head -1 < <(grep -n 'PROVISION-OK' <<<"$body") | cut -d: -f1 || true)"
[[ -n "$first_true" && -n "$first_tok" && "$first_tok" -lt "$first_true" ]] \
  || fail "a 'return true' appears before any PROVISION-OK check — the success path is still unguarded"
pass "no unguarded 'return true' precedes the token check"

# Diagnosability: a rejected body must be logged, never silently discarded (id:4347).
grep -q "log(" <<<"$body" || fail "provisionWorktree() logs nothing on the failure path — a silent false is the same invisibility"
pass "provisionWorktree() logs what came back when it rejects"

echo "ALL PASS: provisioning fails CLOSED on a positive token (66d9)"
