#!/usr/bin/env bash
# roadmap:c855 — [skeleton L2] push-seed discoverCache from the integrator's post-merge state.
# After the pool integrates a repo, its discovery sig changes (new ckpt tag + RELAY_LOG/ROADMAP),
# so the next round re-classifies (an LLM shard — the dominant discover cost, id:9cb1) the exact
# repo the pool just finished. Fix: the serialized integrator recomputes the repo's discover-sig
# (post merge+tag+push+toml+worktree-removal) plus open-work counts and returns them; integrate()
# seeds an 'idle' cache entry ONLY when the repo is provably drained (0 open ROUTINE AND 0 open
# HARD), so next round's prelude sig matches → cache HIT → no shard. FAIL-OPEN preserved: any
# external change re-derives the sig → MISS → re-classify; under-invalidation (stale idle masking
# real work) is refused via the drained-only gate. Static-structural checks on relay-loop.js
# (live discovery too expensive to run here; discover-sig.sh itself is in test_discover_sig.sh).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) INTEGRATE_SCHEMA carries the push-seed inputs the integrator returns.
for f in postSig openRoutine openHard; do
  grep -q "$f" "$JS" || fail "INTEGRATE_SCHEMA / integrator missing $f field"
done

# (2) the integrator prompt recomputes the sig via discover-sig.sh AFTER the merge (push-seed input).
grep -q "discover-sig.sh" "$JS" || fail "integrator does not run discover-sig.sh for postSig"
# it counts open ROUTINE + HARD items from ROADMAP.md (the drained-only gate inputs).
grep -Eq "ROUTINE.*ROADMAP|ROADMAP.*ROUTINE|\\[ROUTINE\\]" "$JS" || fail "integrator does not count open ROUTINE items"
grep -Eq "\\[HARD" "$JS" || fail "integrator does not count open HARD items"

# (3) integrate() seeds an 'idle' cache entry ONLY when provably drained (both counts 0),
#     else DELETES the entry (re-classify). Anchor on the drained gate + the delete branch.
grep -Eq "openRoutine \|\| 0\) === 0 && \(result.openHard \|\| 0\) === 0" "$JS" \
  || fail "integrate() does not gate the push-seed on drained (0 routine AND 0 hard)"
grep -Eq "delete state.discoverCache\[unit.repo\]" "$JS" \
  || fail "integrate() does not delete the cache entry when not drained (under-invalidation guard)"
grep -q "idle: true" "$JS" || fail "no 'idle: true' push-seed marker"

# (4) the cache-reuse loop honors an 'idle' entry: a HIT skips the shard AND is not dispatched
#     (contributes only a skipped rollup line, never a unit).
grep -Eq "cached.idle|reusedIdle" "$JS" || fail "cache-reuse loop does not honor push-seeded idle entries"
grep -q "reusedIdle" "$JS" || fail "idle hits are not folded into the skipped rollup"

# (5) fail-open / under-invalidation invariant is documented + the c855 marker ties it to roadmap.
grep -Eiq "fail.?open|under-invalidation" "$JS" || fail "no fail-open / under-invalidation note for the push-seed"
grep -q "id:c855" "$JS" || fail "no id:c855 marker tying the push-seed to the roadmap item"

pass "discoverCache is push-seeded from the integrator's drained post-merge state, fail-open (c855)"
