#!/usr/bin/env bash
# roadmap:c3f7 — relay-loop.js discovery guards: sync-with-origin (c3f7) + worktree-aware
# (ebfb step 1). Static checks on the discovery agent prompt (live discovery is the id:1ad7
# pilot — too expensive for unit tests; this pins the prompt contract that prevents the
# 2026-06-15 stale-clone incident and cross-session double-work).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"   # id:11ad — the per-repo git gather moved here

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
command -v node >/dev/null && { node --check "$JS" || fail "relay-loop.js is not valid JS"; pass "relay-loop.js parses"; }

# ── Sync-with-origin guard (id:c3f7) ──
# id:11ad: the per-repo git operations (fetch + ahead/behind compute) moved into
# gather-repo-state.sh; the prompt now reads the upstream_ahead_behind field and keeps the
# DECISION logic (diverged-surface + behind-only ff) inline. Assert both halves.
[[ -x "$GATHER" ]] || fail "gather-repo-state.sh not found"
grep -q "SYNC-WITH-ORIGIN GUARD" "$JS" || fail "discovery prompt missing the sync-with-origin guard"
grep -q "fetch origin" "$GATHER" || fail "gather-repo-state.sh does not fetch origin before gathering"
grep -q "rev-list --left-right --count" "$GATHER" || fail "gather-repo-state.sh does not compute ahead/behind"
grep -q "upstream_ahead_behind" "$JS" || fail "sync guard does not read upstream_ahead_behind from gather"
grep -qi "diverged from origin" "$JS" || fail "sync guard does not surface a diverged repo"
grep -q -- "merge --ff-only" "$JS" || fail "sync guard does not fast-forward a behind-only repo"
pass "sync-with-origin guard: fetch+ahead/behind in gather, diverged-surface+ff-only in prompt (id:c3f7/11ad)"

# Integrator belt-and-suspenders (id:c3f7): the serialized integrator re-checks via the
# testable sync-origin.sh helper and aborts before checkpointing on a diverged base.
grep -q "sync-origin.sh" "$JS" || fail "integrator does not belt-and-suspenders via sync-origin.sh"
grep -q "base diverged from origin" "$JS" || fail "integrator does not abort on a diverged base"
pass "integrator belt-and-suspenders via sync-origin.sh (id:c3f7)"

# ── Worktree-aware / claimed-elsewhere guard (id:ebfb step 1) ──
grep -q "WORKTREE-AWARE" "$JS" || fail "discovery prompt missing the worktree-aware guard"
grep -q "cache/relay/worktrees" "$JS" || fail "worktree guard does not inspect the worktree dir"
grep -qi "in-flight elsewhere" "$JS" || fail "worktree guard does not surface a foreign in-flight worktree"
grep -q "does NOT start with this run's runId" "$JS" || fail "worktree guard does not key on foreign runId"
pass "worktree-aware guard: foreign-runId worktree → surfaced in-flight (id:ebfb)"

echo "ALL PASS: discovery guards (sync id:c3f7 + worktree-aware id:ebfb)"
