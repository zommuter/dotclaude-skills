#!/usr/bin/env bash
# roadmap:dc5b
# RED spec (authored by /relay handoff 2026-07-20, apex) for the one-unit-per-repo-
# per-round scheduler invariant — DECIDED C2 at meeting mtg-1726 (2026-07-19, D3):
# an execute+review pair dispatched for the SAME repo in one round collides on the
# non-union ROADMAP.md at integrate (observed: loderite run relay-20260717-100452-13146
# — the review→execute re-chain fired on child-settle, the execute child branched from
# a pre-promotion main and conflicted with the merged review). The invariant: NEVER
# dispatch two units for the same repo in one round; the lower-priority duplicate is
# DEFERRED (loudly, never silently dropped) to the next round's fresh discovery.
#
# Shape (the id:1735 handback-summary.mjs pattern): the invariant lives in an
# extractable pure module `relay/scripts/round-plan.mjs` exporting
#   enforceOneUnitPerRepo(units) -> { plan, deferred }
# — first unit per repo in scheduling order wins (scheduling order is already
# verdict-class-priority order), every later same-repo unit goes to `deferred`
# (carrying repo + verdict so the surface names what was deferred); order of the
# surviving plan is preserved. relay-loop.js wires it into the dispatch path (the
# Workflow sandbox uses an inline copy, per the established 1735 pattern — pinned
# structurally here; live pickup-in-all-lane-orderings is the sandbox residue noted
# on the ROADMAP item, NOT provable hermetically).
#
# NOT a direct [ROUTINE] executor pickup: relay-loop.js runs only in the Workflow
# sandbox (the id:2d20 RED-spec-from-worktree hazard) — the .mjs module + this spec
# are worktree-verifiable; the relay-loop.js wiring is verified structurally.
#
# EXPECTED-RED while roadmap:dc5b is unticked (does not fail the suite).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RP="$ROOT/relay/scripts/round-plan.mjs"
LOOP="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

command -v node >/dev/null || fail "node not available (required by drain-driver tests too)"
[[ -f "$RP" ]] || fail "round-plan.mjs not found at $RP (the extractable pure module is the spec surface)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/spec.mjs" <<EOF
const { enforceOneUnitPerRepo } = await import('file://$RP');
const fail = (m) => { console.error('FAIL: ' + m); process.exit(1); };

// (a) duplicate repo in one round: first (higher verdict-class) unit wins,
//     the later same-repo unit is DEFERRED — never dispatched, never dropped.
const units = [
  { repo: 'X', verdict: 'review'  },
  { repo: 'X', verdict: 'execute' },
  { repo: 'Y', verdict: 'execute' },
];
const r = enforceOneUnitPerRepo(units);
if (!r || !Array.isArray(r.plan) || !Array.isArray(r.deferred))
  fail('(a) enforceOneUnitPerRepo must return { plan: [], deferred: [] }');
if (r.plan.length !== 2) fail('(a) plan must keep exactly one unit per repo (got ' + r.plan.length + ')');
if (r.plan[0].repo !== 'X' || r.plan[0].verdict !== 'review')
  fail('(a) first-in-scheduling-order unit for X (review) must win, got ' + JSON.stringify(r.plan[0]));
if (r.plan[1].repo !== 'Y' || r.plan[1].verdict !== 'execute')
  fail('(a) Y unit must survive untouched, got ' + JSON.stringify(r.plan[1]));
if (r.deferred.length !== 1) fail('(a) exactly the duplicate X unit must be deferred (got ' + r.deferred.length + ')');
if (r.deferred[0].repo !== 'X' || r.deferred[0].verdict !== 'execute')
  fail('(a) deferred entry must carry repo+verdict of the dropped unit, got ' + JSON.stringify(r.deferred[0]));
console.log('PASS: (a) duplicate-repo round defers the later unit, first wins');

// (b) no duplicates: plan is the input (order preserved), nothing deferred.
const clean = [
  { repo: 'A', verdict: 'execute' },
  { repo: 'B', verdict: 'review'  },
  { repo: 'C', verdict: 'hard'    },
];
const r2 = enforceOneUnitPerRepo(clean);
if (r2.plan.length !== 3 || r2.deferred.length !== 0)
  fail('(b) a duplicate-free round must pass through unchanged');
if (r2.plan.map(u => u.repo).join(',') !== 'A,B,C')
  fail('(b) plan order must be preserved, got ' + r2.plan.map(u => u.repo).join(','));
console.log('PASS: (b) duplicate-free round passes through, order preserved');

// (c) three units for one repo: exactly one survives, two deferred.
const r3 = enforceOneUnitPerRepo([
  { repo: 'Z', verdict: 'execute' },
  { repo: 'Z', verdict: 'review'  },
  { repo: 'Z', verdict: 'hard'    },
]);
if (r3.plan.length !== 1 || r3.deferred.length !== 2)
  fail('(c) triple-duplicate: one survives, two deferred (got plan=' + r3.plan.length + ' deferred=' + r3.deferred.length + ')');
console.log('PASS: (c) N-duplicate round keeps exactly one unit');
EOF
node "$TMP/spec.mjs" || fail "round-plan.mjs behavioural spec failed"
pass "round-plan.mjs enforceOneUnitPerRepo behaves per the C2 invariant"

# Structural pin: relay-loop.js wires the invariant into its dispatch path (inline
# copy or call — the sandbox cannot import; the name is the pin, per the id:1735
# byte-identical-inline-copy pattern).
grep -q 'enforceOneUnitPerRepo' "$LOOP" \
  || fail "relay-loop.js does not reference enforceOneUnitPerRepo — the invariant is not wired into the dispatch path"
pass "relay-loop.js references enforceOneUnitPerRepo (dispatch-path wiring pinned)"

echo "OK: all one-unit-per-repo-per-round assertions passed"
