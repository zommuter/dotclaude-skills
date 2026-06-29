#!/usr/bin/env bash
# TODO id:debf — Close scoop window (ii): ban `git add -A` in the relay integrator.
# NOT a ROADMAP item (TODO-id feature) — no `# roadmap:` header, so its failures
# always count. Contract (meeting D2, 2026-06-17-0953): a concurrent uncommitted
# ledger edit (from /meeting or /relay human) is never captured in a pool checkpoint
# commit. The integrator integrates ONLY the child's committed worktree branch via
# `git merge --no-ff`; it must never stage the main checkout broadly.
#
# Static contract check (the live loop is too expensive to run in a unit test, like
# test_relay_loop_structure.sh): assert relay-loop.js carries the scoped-staging
# invariant and contains NO broad `git add` form anywhere.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) No broad `git add` form is USED anywhere in relay-loop.js. Scoped `git add --
# <path>` (e.g. the id:bae5 uv.lock relock) is allowed. The only lines permitted to
# MENTION a broad form are negation/prohibition lines (the id:debf invariant itself) —
# every such line must carry a negation marker (do NOT / NEVER). A bare command usage
# would lack the marker and fail here.
for badform in 'git add -A' 'git add --all' 'git add -u' 'git add .'; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -qE 'do NOT run|NEVER stage|never broadly|never \`git add' <<<"$line"; then
      fail "id:debf: relay-loop.js uses a broad '$badform' outside a prohibition: $line"
    fi
  done < <(grep -F -- "$badform" "$JS" || true)
done
pass "id:debf: no broad git add (-A/./-u/--all) USED in relay-loop.js (only the prohibition mentions them)"

# (2) The integrator integrates via the committed-branch --no-ff merge (stages nothing
# from the working tree), not by adding from the main checkout.
grep -qF -- 'merge --no-ff ${report.branch}' "$JS" \
  || fail "id:debf: integrator does not integrate via 'git merge --no-ff \${report.branch}' (committed branch)"
pass "id:debf: integrator integrates the committed worktree branch via --no-ff merge"

# (3) The scoped-staging invariant is documented in the integrator prompt with its id,
# so it can't be silently dropped.
grep -q "SCOPED-STAGING INVARIANT (id:debf" "$JS" \
  || fail "id:debf: integrator prompt missing the SCOPED-STAGING INVARIANT (id:debf) marker"
grep -q "never scoop a concurrent ledger edit" "$JS" \
  || fail "id:debf: invariant does not state the concurrent-ledger-edit contract"
grep -q "scoop window, id:3558" "$JS" \
  || fail "id:debf: invariant does not cite the scoop-window hazard (id:3558)"
pass "id:debf: integrator prompt documents the scoped-staging invariant (no-scoop contract)"

echo "ALL PASS: relay integrator uses scoped staging — no git add -A (id:debf)"
