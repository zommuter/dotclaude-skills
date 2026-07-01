#!/usr/bin/env bash
# roadmap:c3f7 — relay-loop.js discovery guards: sync-with-origin (c3f7) + worktree-aware
# (ebfb step 1). Static checks on the discovery agent prompt (live discovery is the id:1ad7
# pilot — too expensive for unit tests; this pins the prompt contract that prevents the
# 2026-06-15 stale-clone incident and cross-session double-work).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"      # id:11ad — the per-repo git gather moved here
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"       # mechanical successor to the discovery-prompt guards

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
command -v node >/dev/null && { node --check "$JS" || fail "relay-loop.js is not valid JS"; pass "relay-loop.js parses"; }

# ── Sync-with-origin guard (id:c3f7) ──
# id:11ad: the per-repo git operations (fetch + ahead/behind compute) moved into
# gather-repo-state.sh. The old LLM discovery prompt's DECISION logic (diverged-surface +
# behind-only ff) is now mechanical, in reconcile-repo.sh. Assert both halves.
[[ -x "$GATHER" ]] || fail "gather-repo-state.sh not found"
[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found"
grep -q "id:c3f7" "$RECONCILE" || fail "reconcile-repo.sh missing the id:c3f7 sync-with-origin marker"
grep -q "fetch origin" "$GATHER" || fail "gather-repo-state.sh does not fetch origin before gathering"
grep -q "rev-list --left-right --count" "$GATHER" || fail "gather-repo-state.sh does not compute ahead/behind"
grep -qi "diverged from origin" "$RECONCILE" || fail "reconcile-repo.sh does not surface a diverged repo"
grep -q -- "merge --ff-only" "$RECONCILE" || fail "reconcile-repo.sh does not fast-forward a behind-only repo"
pass "sync-with-origin guard: fetch+ahead/behind in gather, diverged-surface+ff-only in reconcile-repo.sh (id:c3f7/11ad)"

# Integrator belt-and-suspenders (id:c3f7): the serialized integrator re-checks via the
# testable sync-origin.sh helper and aborts before checkpointing on a diverged base.
grep -q "sync-origin.sh" "$JS" || fail "integrator does not belt-and-suspenders via sync-origin.sh"
grep -q "base diverged from origin" "$JS" || fail "integrator does not abort on a diverged base"
pass "integrator belt-and-suspenders via sync-origin.sh (id:c3f7)"

# ── Worktree-aware / claimed-elsewhere guard (id:ebfb step 1) ──
# id:ebfb step 1 (foreign in-flight worktree) is now mechanical in reconcile-repo.sh: it
# inspects the worktree dir under WORKTREE_BASE, skips the run's OWN worktree (branch prefix
# matches --runid), and surfaces any remaining foreign worktree as in-flight when the repo is
# in the --live-claims set passed in by the prelude (replacing the old per-repo claim.sh peek).
grep -q "WORKTREE_BASE" "$RECONCILE" || fail "reconcile-repo.sh missing the worktree-aware guard"
grep -q "cache/relay/worktrees" "$RECONCILE" || fail "worktree guard does not inspect the worktree dir"
grep -qi "in-flight elsewhere" "$RECONCILE" || fail "worktree guard does not surface a foreign in-flight worktree"
grep -q '"\$bn" == "\$runid"\*' "$RECONCILE" || fail "worktree guard does not skip this run's OWN worktree by runid prefix"
grep -q -- "--live-claims" "$RECONCILE" || fail "worktree guard does not key foreign-vs-live on the --live-claims param"
pass "worktree-aware guard: own-runid worktree skipped, live-claimed foreign worktree → surfaced in-flight (id:ebfb)"

echo "ALL PASS: discovery guards (sync id:c3f7 + worktree-aware id:ebfb)"
