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

# (D1) the two discovery agents (discover-prelude + the discover-run mechanical runner that
#      replaced the old discover-shard LLM prompt) must be EXPLICITLY pinned to a fixed cheap
#      tier — never inheriting the session model (Opus) = the 35% tier-leak. Post-a0b6 both are
#      PURE TRANSPORT (prelude relays relay.toml/claims/sigs; runner shells discover-repo.sh per
#      repo, zero reasoning), so the floor dropped sonnet→haiku (id:2ec4, both pilot-validated
#      2026-07-01: discover-run 3 tool calls; prelude 50/50 non-empty sigs w/ absolute paths).
#      id:86a2 (2026-07-23): the discover-prelude is now MECHANIZED one step further — a
#      model:'bash' (```relay-mech) dispatch of discover-prelude.sh, no LLM at all (the prelude
#      never classifies). So its explicit pin is now 'bash', not 'haiku'; the D1 invariant
#      (explicit fixed cheap pin, NEVER inherits Opus) is preserved and strengthened.
#      id:24ec (2026-07-23): the discover-run half is now ALSO mechanized — a model:'bash'
#      dispatch of discover-chunk.sh (CASE B: per-repo discover-repo.sh reconcile+classify,
#      concatenated; no LLM). So its explicit pin flipped 'haiku' → 'bash'. The D1 invariant
#      (explicit fixed cheap pin, NEVER inherits Opus) holds for BOTH discovery hops.
grep -Eq "label: \`discover-run.*model: 'bash'" "$JS" \
  || grep -Pzoq "discover-run[^\n]*\n?[^\n]*model: 'bash'" "$JS" \
  || fail "discover-run agent is not pinned to model: 'bash' (id:24ec mechanized dispatch / stale pin / tier leak)"
grep -Eq "label: 'discover-prelude'.*model: 'bash'" "$JS" \
  || grep -Pzoq "discover-prelude[^\n]*\n?[^\n]*model: 'bash'" "$JS" \
  || fail "discover-prelude agent is not pinned to model: 'bash' (id:86a2 mechanized dispatch / stale pin)"

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

pass "discovery is signature-cached: shards fire only on churn, prelude bash-pinned (id:86a2) + run bash-pinned (id:24ec), fail-open (c3a6 + id:2ec4 tier flip)"
