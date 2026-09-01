#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose: this closes a coupling that the
# routed:42c9/8b21 archive-blindness fixes THEMSELVES introduce, and has no ROADMAP item.
# Failures here always count.
#
# WHY THIS EXISTS. `discover-sig.sh` hashes a SUPERSET of every input the classifier reads,
# so the pool can reuse last round's verdict when the sig is unchanged. Its documented sole
# hazard is UNDER-invalidation (CLAUDE.md: "If you add a NEW signal to the shard prompt, add
# it to discover-sig.sh's blob too, or its verdict can go stale").
#
# Fixing routed:42c9/8b21 made `resolve-gates.sh` read `ROADMAP.archive.md`, and BOTH
# `classify-repo.sh` and `gather-repo-state.sh` call resolve-gates.sh. So ROADMAP.archive.md
# is now a genuine CLASSIFIER INPUT: archiving a gate target flips a gate from dangling to
# satisfied and can change the verdict. The sig blob hashed ROADMAP.md alone, so that change
# left the signature byte-identical and the cache would serve a STALE verdict.
#
# Over-hashing is free here (a wasted re-classify); under-hashing is the stale-verdict bug.
# fails-against: rev 6142f2329b34 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/append.sh, meeting/md-merge.py, meeting/orphan-scan.sh (+15 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 6142f2329b34 -- meeting/append.sh meeting/md-merge.py meeting/orphan-scan.sh relay/references/hard-lanes.md relay/scripts/classify-repo.sh relay/scripts/discover-sig.sh relay/scripts/gather-repo-state.sh relay/scripts/handback-guard.mjs relay/scripts/lib-anchored-id.sh relay/scripts/lib-roadmap-sections.sh relay/scripts/lib-typed-edges.sh relay/scripts/reconcile-repo.sh relay/scripts/relay-loop.js relay/scripts/resolve-gates.sh relay/scripts/roadmap-lint.sh relay/scripts/unpromoted-scan.sh tracker/SCHEMA.md tracker/ledger-map.py
# fails-against-assertion: signature did NOT change when ROADMAP.archive.md's checkbox state flipped — only its existence is hashed, not its content

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIG="$SRC_DIR/relay/scripts/discover-sig.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"
export RELAY_WORKTREE_BASE="$TMP/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

REPO="$TMP/widget"
git init -q "$REPO"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
printf '# Roadmap\n- [ ] [ROUTINE] gated work <!-- gated-on:ca01 --> <!-- id:ca02 -->\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
cat > "$RELAY_TOML" <<'TOML'
[repos.widget]
classification = "own"
income = false
TOML

sig_of() {
  printf '{"repos":[{"repo":"widget","path":"%s"}],"liveClaims":[]}\n' "$REPO" \
    | "$SIG" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])'
}

S0="$(sig_of)"
[[ -n "$S0" ]] || fail "signature empty for a valid repo (should only be empty on fail-open)"

# --- Case 1 — THE DEFECT: CREATING ROADMAP.archive.md must move the signature, because
# it is now a resolve-gates.sh input (ca01 goes from dangling to satisfied).
printf '# Roadmap archive\n- [x] [ROUTINE] the gate target, archived <!-- id:ca01 -->\n' > "$REPO/ROADMAP.archive.md"
S1="$(sig_of)"
[[ "$S1" != "$S0" ]] \
  || fail "signature did NOT change when ROADMAP.archive.md appeared — it is a classifier input via resolve-gates.sh, so the cache would serve a STALE verdict (under-invalidation)"
pass "creating ROADMAP.archive.md moves the signature"

# --- Case 2 — EDITING ROADMAP.archive.md must move it too (not just its existence):
# flipping the archived gate target back to open changes the gate verdict.
printf '# Roadmap archive\n- [ ] [ROUTINE] the gate target, archived but REOPENED <!-- id:ca01 -->\n' > "$REPO/ROADMAP.archive.md"
S2="$(sig_of)"
[[ "$S2" != "$S1" ]] \
  || fail "signature did NOT change when ROADMAP.archive.md's checkbox state flipped — only its existence is hashed, not its content"
pass "editing ROADMAP.archive.md moves the signature"

# --- Case 3 — determinism preserved: unchanged state, identical sig.
S3="$(sig_of)"
[[ "$S3" == "$S2" ]] || fail "signature not deterministic after the widening: '$S3' != '$S2'"
pass "still deterministic on unchanged state"

# --- Case 4 — a repo with NO ROADMAP.archive.md still produces a stable non-empty sig
# (a missing archive is a normal state, not a fail-open trigger).
rm -- "$REPO/ROADMAP.archive.md"
S4="$(sig_of)"; S5="$(sig_of)"
[[ -n "$S4" ]] || fail "signature went empty (fail-open sentinel) merely because ROADMAP.archive.md is absent"
[[ "$S4" == "$S5" ]] || fail "signature not deterministic with no ROADMAP.archive.md"
[[ "$S4" == "$S0" ]] || fail "removing ROADMAP.archive.md did not return the sig to its original value — the blob is not a pure function of state"
pass "a missing ROADMAP.archive.md is a normal state and round-trips"

echo "OK: test_discover_sig_roadmap_archive.sh"
