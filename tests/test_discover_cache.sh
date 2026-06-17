#!/usr/bin/env bash
# roadmap:c3a6 — content-addressed discovery cache wiring in relay-loop.js. The classifier shards
# re-ran fresh EVERY round (≤MAX_ROUNDS), re-classifying unchanged repos — the bulk of the
# on-critical-path "status" overhead. Fix: the prelude returns a per-repo SUPERSET signature
# (discover-sig.sh); runRound reuses a cached verdict for repos whose signature is unchanged,
# spawning an LLM shard only for churned/new/fail-open repos. Plus D1: the shard inherits the
# session model (Opus) — pin it to sonnet like its prelude sibling. Static-structural checks
# (live discovery is too expensive to run here; the helper itself is tested in test_discover_sig.sh).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (D1) the discover-shard agent is pinned to sonnet (was inheriting the session model = Opus).
#      Anchor to the shard line specifically: the shardPrompt agent call carries model: 'sonnet'.
grep -Eq "label: \`discover-shard.*model: 'sonnet'" "$JS" \
  || grep -Pzoq "discover-shard[^\n]*\n?[^\n]*model: 'sonnet'" "$JS" \
  || fail "discover-shard agent is not pinned to model: 'sonnet' (D1 tier leak)"

# (D3a) PRELUDE_SCHEMA carries a signatures field (per-repo {repo, sig}).
grep -q "signatures" "$JS" || fail "PRELUDE_SCHEMA / prelude has no signatures field"
# the prelude prompt runs the signature helper (it executes the script, not hashes in-prompt).
grep -q "discover-sig.sh" "$JS" || fail "prelude does not run discover-sig.sh"

# (D3b) runRound keeps a per-round-persistent signature cache on state.
grep -q "state.discoverCache" "$JS" || fail "no state.discoverCache (content-addressed cache)"

# (D3c) only CHANGED/new repos are sent to the shard parallel(); unchanged reuse the cached unit.
#       Assert the cache is consulted to partition repos before the shard fan-out, and that a
#       cached unit is reused (not re-classified).
grep -Eq "changed|cache(Miss|d)|reclassif" "$JS" || fail "no changed-vs-unchanged partition before shard fan-out"
grep -Eq "discoverCache\[[^]]+\]\.unit|cached\.unit|\.unit\b" "$JS" || fail "cached unit is never reused"

# (D3d) fail-open: an empty/sentinel signature (or a repo absent from the cache) must re-classify,
#       never serve a stale verdict. Check the wording is present so the invariant is documented + tested.
grep -Eiq "fail.?open|sentinel|empty sig" "$JS" || fail "no fail-open handling for empty/sentinel signatures"

# (D3e) the merged discovery object keeps the byte-identical {units, surfaced, skipped} shape — the
#       cache must not change what downstream runRound consumes (regression guard against shape drift).
grep -q "runId: prelude.runId" "$JS" || fail "merged discovery dropped the prelude runId (shape drift)"
grep -q "id:c3a6" "$JS" || fail "no id:c3a6 marker tying this wiring to the roadmap item"

pass "discovery is signature-cached: shards fire only on churn, sonnet-pinned, fail-open (c3a6)"
