#!/usr/bin/env bash
# roadmap:923b
# RED SPEC for id:923b — per-unit identity key; re-key the repo-as-primary-key collision sites.
#
# Two CONCRETE latent bugs today (verified 2026-07-30, line numbers may drift):
#   relay-loop.js:1804  worktreePathFor builds ~/.cache/relay/worktrees/<repo>/<runId>-<verdict>
#                       => two concurrent same-repo executes compute the IDENTICAL path.
#   relay-loop.js:2435  state.inFlight = state.inFlight.filter(r => r.repo !== unit.repo)
#                       => completing one unit clears EVERY same-repo in-flight entry.
#
# Ratified key shape: itemId x attempt (a bare itemId collides on retries and on the open
# id:1b1a duplicate-line bug; a bare nonce orphans pre-crash worktrees from id:7809's view).
#
# The Workflow engine cannot run hermetically, so the assertions are source-shape (style of
# tests/test_dispatch_event_sig.sh) PLUS a directly-callable purity check of the extracted
# key function when the implementation exposes one. Honest limitation: the source-shape half
# guards the shape of the fix, not its runtime behaviour.
#
# TRIANGULATION (id:108e): the key function is exercised with THREE distinct unit shapes —
# two different item ids, the same id at different attempts, and an id-less review unit —
# so a hard-coded single-case pass is not enough.
#
# RED until relay-loop.js is re-keyed. roadmap:923b unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# 1. A unit-key helper exists and is NAMED (so it can be tested and reused).
grep -Eq '(unitKey|unitKeyFor)' "$JS" \
  || fail "(1) no unitKey/unitKeyFor helper in relay-loop.js — the unit identity key does not exist (id:923b)"
pass "(1) a named unit-key helper exists"

# 2. The worktree path is keyed by the UNIT key, not by repo+verdict alone.
if grep -Eq 'worktrees/\$\{unit\.repo\}/\$\{state\.runId\}-\$\{unit\.verdict\}' "$JS"; then
  fail "(2) worktreePathFor still builds <repo>/<runId>-<verdict> — two same-repo units still collide (id:923b)"
fi
grep -Eq 'worktreePathFor' "$JS" \
  || fail "(2) worktreePathFor disappeared entirely — expected it re-keyed, not deleted (id:923b)"
pass "(2) worktreePathFor is no longer keyed by repo+verdict alone"

# 3. The in-flight sweep no longer clears every same-repo entry.
if grep -Eq 'state\.inFlight\.filter\(r => r\.repo !== unit\.repo\)' "$JS"; then
  fail "(3) the inFlight sweep still filters by repo only — a sibling same-repo unit is still wiped (id:923b)"
fi
grep -Eq 'state\.inFlight = state\.inFlight\.filter' "$JS" \
  || fail "(3) the inFlight sweep disappeared entirely — expected it re-keyed, not deleted (id:923b)"
pass "(3) the inFlight sweep is keyed per unit, not per repo"

# 4. The key carries an ATTEMPT component (a bare itemId collides on retries).
grep -Eqi 'attempt' "$JS" \
  || fail "(4) no attempt component anywhere — the key cannot distinguish a retry of the same item (id:923b)"
pass "(4) the key carries an attempt component"

# 5. enqueueIntegration stays REPO-keyed (its serialization is correct; A3 two-tier lease).
grep -Eq 'function enqueueIntegration\(repo' "$JS" \
  || fail "(5) enqueueIntegration is no longer repo-keyed — the A3 two-tier split must NOT flatten it (id:923b)"
pass "(5) enqueueIntegration is still repo-keyed"

# 6. The repo-level claim.sh lease is still acquired at REPO granularity — this is what a
#    parallel /meeting advisory claim collides against; re-keying it to a unit would silently
#    dissolve that collision ([[claim-lease-mode-blind-no-pool-meeting-skip]]).
grep -Eq 'claim\.sh' "$JS" \
  || fail "(6) no claim.sh reference — the repo-level lease is gone (id:923b, A3)"
if grep -Eq "claim\.sh acquire[^\"']*\\\$\{unitKey" "$JS"; then
  fail "(6) claim.sh acquire is keyed by the UNIT key — the repo lease must stay repo-keyed so a /meeting claim still collides (id:923b, A3)"
fi
pass "(6) the claim.sh lease is still repo-granular"

# 7. BEHAVIOUR of the key function. relay-loop.js runs inside the Workflow sandbox and cannot
#    `require` a sibling module or use module.exports, so the helper is EXTRACTED TEXTUALLY and
#    evaluated standalone. This imposes one deliberate constraint on the implementation, stated
#    here so it is not a surprise: `unitKey` must be a SINGLE-LINE pure arrow function of one
#    argument — the same shape `worktreePathFor` already has at :1804 — with no closure over
#    module state. Three distinct unit shapes (two ids / same id different attempt / id-less
#    review) must yield distinct keys, and the same shape must be stable across calls.
keyline="$(grep -E '^[[:space:]]*const unitKey(For)? = \(' "$JS" | head -1 || true)"
[[ -n "$keyline" ]] \
  || fail "(7) no single-line 'const unitKey = (…) => …' arrow found — the key must be a pure, textually-extractable one-liner so it can be tested standalone (id:923b)"
KEYLINE="$keyline" node -e '
  const src = process.env.KEYLINE;
  let f;
  try { f = eval("(" + src.replace(/^\s*const\s+unitKey(For)?\s*=\s*/, "") + ")"); }
  catch (e) { console.error("unitKey is not standalone-evaluable (closes over module state?): " + e.message); process.exit(1); }
  if (typeof f !== "function") { console.error("unitKey did not evaluate to a function"); process.exit(1); }
  let keys;
  try {
    keys = [
      f({repo:"r", verdict:"execute", itemId:"aaaa", attempt:1}),
      f({repo:"r", verdict:"execute", itemId:"bbbb", attempt:1}),
      f({repo:"r", verdict:"execute", itemId:"aaaa", attempt:2}),
      f({repo:"r", verdict:"review", attempt:1}),
    ].map(String);
  } catch (e) { console.error("unitKey threw on a probe unit: " + e.message); process.exit(1); }
  if (new Set(keys).size !== 4) { console.error("keys collide: " + JSON.stringify(keys)); process.exit(1); }
  if (String(f({repo:"r", verdict:"execute", itemId:"aaaa", attempt:1})) !== keys[0]) {
    console.error("key is not stable across calls"); process.exit(1);
  }
' || fail "(7) unitKey does not separate {two ids, same id different attempt, id-less review} or is unstable (id:923b)"
pass "(7) unitKey separates all four probe shapes and is stable"

# 8. The engine still parses and lints clean.
node --check "$JS" >/dev/null 2>&1 || fail "(8) node --check failed on relay-loop.js after the 923b edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(8) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(8) relay-loop.js has a template-literal violation after the 923b edit:
$out"
fi
pass "(8) relay-loop.js parses and lints clean"

echo "PASS test_unit_identity_key_923b"
