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

# id:087b RELOCATION — the integrator is now relay/scripts/integrate.sh, dispatched by
# relay-loop.js as one mechanical hop. Check (1) above still guards relay-loop.js; the
# integrator's own staging behaviour is now real code in integrate.sh, so (1b), (2) and (3)
# read that file. This is STRONGER than before: a broad `git add` is now the literal absence
# of a command rather than a prompt instruction an agent could reweigh.
INTEG="$SRC_DIR/relay/scripts/integrate.sh"
[[ -x "$INTEG" ]] || fail "integrate.sh not found/executable at $INTEG"
grep -q 'relay/scripts/integrate.sh' "$JS" || fail "id:debf: relay-loop.js does not dispatch integrate.sh"

# (1b) No broad `git add` form is USED in integrate.sh either — checked over CODE lines only,
# so the prohibition comments that name the forms cannot satisfy it.
for badform in 'git add -A' 'git add --all' 'git add -u' 'git add .'; do
  if grep -qF -- "$badform" < <(grep -vE '^\s*#' "$INTEG") ; then
    fail "id:debf: integrate.sh USES a broad '$badform' in a code line — the scoop window is open"
  fi
done
pass "id:debf: no broad git add (-A/./-u/--all) in any integrate.sh code line"

# (2) The integrator integrates via the committed-branch --no-ff merge (stages nothing
# from the working tree), not by adding from the main checkout.
grep -qF -- 'merge --no-ff "$branch"' "$INTEG" \
  || fail "id:debf: integrate.sh does not integrate via 'git merge --no-ff \$branch' (committed branch)"
pass "id:debf: integrator integrates the committed worktree branch via --no-ff merge"

# (3) Every staging call in integrate.sh is path-SCOPED (`git add -- <path>`), and the
# scoped-staging invariant is documented with its id so it can't be silently dropped.
while IFS= read -r addline; do
  grep -qE 'git -C "\$path" add -- ' <<<"$addline" \
    || fail "id:debf: integrate.sh has a non-path-scoped staging call: $addline"
done < <(grep -vE '^\s*#' "$INTEG" | grep -F 'git -C "$path" add' || true)
grep -q "SCOPED-STAGING INVARIANT (id:debf" "$INTEG" \
  || fail "id:debf: integrate.sh missing the SCOPED-STAGING INVARIANT (id:debf) marker"
grep -q "scoped staging, id:debf" "$INTEG" \
  || fail "id:debf: integrate.sh does not name scoped staging at the staging sites"
grep -q "never scoop a concurrent ledger edit" "$INTEG" \
  || fail "id:debf: integrate.sh no longer states the concurrent-ledger-edit contract"
grep -q "scoop window, id:3558" "$INTEG" \
  || fail "id:debf: integrate.sh no longer cites the scoop-window hazard (id:3558)"
pass "id:debf: every integrate.sh staging call is path-scoped and the no-scoop contract is documented"

echo "ALL PASS: relay integrator uses scoped staging — no git add -A (id:debf)"
