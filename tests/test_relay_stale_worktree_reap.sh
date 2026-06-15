#!/usr/bin/env bash
# roadmap:3ac8 — discovery must distinguish a STALE worktree left by a dead run (no fresh
# claim) from a genuinely in-flight one (fresh claim), instead of treating any foreign-runId
# worktree's existence as "in-flight elsewhere" (which falsely starved the pool of 14 repos
# on 2026-06-15). Stale + empty → reap & classify; stale + commits → surface as handback.
# Static-structural checks on the discovery prompt in relay-loop.js.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) discovery consults LIVE claims (claim.sh peek) to decide in-flight vs stale.
grep -q "claim.sh peek" "$JS" || fail "discovery guard does not consult claim.sh peek (can't tell live from dead)"

# (2) the id:3ac8 marker + the 'no fresh claim → stale' reasoning is present.
grep -q "id:3ac8" "$JS" || fail "no id:3ac8 marker in the discovery guard"
# id:9ed4 reworded "has NO fresh claim" → "is NOT in the live-claim set" (the prelude passes the
# set rather than each shard running claim.sh peek) — same absence-of-fresh-claim keying.
grep -Eqi "NO fresh claim|no claim|NOT in the live-claim" "$JS" || fail "guard does not key the stale case on the absence of a fresh claim"

# (3) empty stale worktree (ancestor of main) is REAPED and the repo classified normally.
grep -q "merge-base --is-ancestor" "$JS" || fail "guard does not test ancestor-of-main (empty) before reaping"
grep -Eq "worktree remove --force" "$JS" || fail "guard never reaps an empty stale worktree"

# (4) commit-bearing stale worktree is NEVER reaped — surfaced as a handback needing integration.
grep -Eqi "unmerged commit|needs manual integration" "$JS" \
  || fail "guard does not surface a commit-bearing stale worktree as a handback (data-loss risk)"

# (5) the live-claim case still surfaces as in-flight-elsewhere (id:ebfb behaviour preserved).
grep -q "in-flight elsewhere" "$JS" || fail "live-claim case no longer surfaces as in-flight elsewhere"

pass "discovery reaps empty stale worktrees, surfaces commit-bearing ones, preserves live-claim in-flight (3ac8)"
