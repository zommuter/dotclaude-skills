#!/usr/bin/env bash
# roadmap:8123
# The CACHE-SIDE half of id:8123's chain-end classifier re-ask.
#
# classify-verdict.sh gained a NEW named classifier input (the chain-end fact) under which
# `review` outranks `execute`. discover-sig.sh (id:c3a6) hashes a SUPERSET of every input the
# classifier reads and the pool REUSES last round's verdict for an unchanged signature —
# UNDER-invalidation is that cache's only hazard. So a chain-end fact that is NOT in the hashed
# blob means a chain-end verdict can be served STALE (last round's `execute`) and the forced
# review silently never fires, in exactly the situation the cadence fix was built for. That is
# the same trap id:907e clause (i) closes from the other side; both must hold or the fix is a
# no-op.
#
# This test pins THREE things: (1) the fact moves the signature, (2) its absence is identical to
# an explicit false (so no existing caller's sig churns), and (3) the field name discover-sig.sh
# hashes is THE SAME TOKEN classify-verdict.sh reads and relay-loop.js emits — the spec left the
# spelling to the implementer, so the only thing that can be asserted is that all three agree.
#
# Hermetic: a throwaway git repo, overridden RELAY_TOML / RELAY_WORKTREE_BASE, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIG="$SRC_DIR/relay/scripts/discover-sig.sh"
CV="$SRC_DIR/relay/scripts/classify-verdict.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SIG" ]] || fail "discover-sig.sh not found or not executable: $SIG"
[[ -x "$CV"  ]] || fail "classify-verdict.sh not found or not executable: $CV"
[[ -f "$JS"  ]] || fail "relay-loop.js not found: $JS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"
export RELAY_WORKTREE_BASE="$TMP/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

REPO="$TMP/widget"
git init -q "$REPO"
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'roadmap\n- [ ] [ROUTINE] do a thing\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
cat > "$RELAY_TOML" <<'TOML'
[repos.widget]
classification = "own"
income = false
TOML

# ── which field name did the implementer pick? Whatever classify-verdict.sh actually READS. ──
FIELD=""
for cand in chain_ended chainEnded chain_end chain_end_reason; do
  if grep -q "\"$cand\"" "$CV"; then FIELD="$cand"; break; fi
done
[[ -n "$FIELD" ]] || fail "classify-verdict.sh reads none of the chain-end field spellings (chain_ended/chainEnded/chain_end/chain_end_reason) — id:8123 is not implemented on the classifier side"

sig_of() { # $1 = extra per-repo JSON fragment (may be empty)
  printf '{"repos":[{"repo":"widget","path":"%s"%s}],"liveClaims":[]}\n' "$REPO" "$1" \
    | "$SIG" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])'
}

case "$FIELD" in
  chain_end_reason) TRUE_FRAG=",\"$FIELD\":\"handback\"" ;;
  *)                TRUE_FRAG=",\"$FIELD\":true" ;;
esac

# (1) The chain-end fact MOVES the signature — no stale-verdict window.
S_PLAIN="$(sig_of "")"
S_CHAIN="$(sig_of "$TRUE_FRAG")"
[[ -n "$S_PLAIN" ]] || fail "signature empty for a valid repo (fail-open sentinel where a real sig was expected)"
[[ "$S_PLAIN" != "$S_CHAIN" ]] \
  || fail "discover-sig.sh does NOT hash '$FIELD': the signature is identical with and without the chain-end fact ($S_PLAIN) — the id:c3a6 cache would serve last round's 'execute' verdict and the id:8123 forced review would silently never fire"
pass "(1) the chain-end fact '$FIELD' changes the discovery signature"

# (2) ABSENT must equal explicitly-false — an existing caller that never heard of the field
#     must not see its signature churn (over-invalidation is safe but pointless churn is not).
case "$FIELD" in
  chain_end_reason) FALSE_FRAG=",\"$FIELD\":\"\"" ;;
  *)                FALSE_FRAG=",\"$FIELD\":false" ;;
esac
S_FALSE="$(sig_of "$FALSE_FRAG")"
[[ "$S_PLAIN" == "$S_FALSE" ]] \
  || fail "an ABSENT '$FIELD' ($S_PLAIN) does not hash the same as an explicit false/empty ($S_FALSE) — every pre-8123 caller's signature would churn on upgrade"
pass "(2) an absent chain-end fact is identical to an explicit false"

# (3) Determinism — the new section must not make the sig unstable.
[[ "$(sig_of "$TRUE_FRAG")" == "$S_CHAIN" ]] || fail "signature with the chain-end fact is not deterministic"
pass "(3) the chain-end signature is deterministic"

# (4) The blob is LABELED with the same token (a bare value hashed under some other label would
#     still pass (1) but would leave the coupling undocumented and easy to break).
grep -q "== $FIELD ==" "$SIG" \
  || fail "discover-sig.sh hashes the chain-end fact under some other label — the blob must carry a '== $FIELD ==' section so the classifier↔cache coupling is greppable from both sides"
pass "(4) discover-sig.sh's blob carries a labeled '== $FIELD ==' section"

# (5) The LOOP emits the same token into the discover-sig input, or the sig-side half is
#     built-but-unreferenced (the [[relay-builtgreen-but-unreferenced]] class).
grep -q "$FIELD" "$JS" \
  || fail "relay-loop.js never emits '$FIELD' — discover-sig.sh hashes a field nobody supplies, so the cache-invalidation half of id:8123 is dead code"
pass "(5) relay-loop.js supplies '$FIELD' to the discovery signature"

echo "PASS test_chain_end_sig_8123"
