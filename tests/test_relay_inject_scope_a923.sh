#!/usr/bin/env bash
# routed:a923 — scope-aware `inject.sh take`. NO roadmap: header: this is a defect fix (a
# scoped pool stole and LOST another pool's injection, run relay-20260811-221031-22542), so
# its failures always count.
#
# Covers the three layers of the fix:
#   (A) inject.sh take --repo consumes ONLY matching shards, leaves the rest PENDING
#   (B) discover-prelude.sh threads $ONLY_REPO into the CONSUMING take
#   (C) relay-loop.js passes its --only scope to BOTH takes (prelude + mid-round) and
#       fail-CLOSES (sentinel, never a global drain) on an unsafe scope name

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/inject.sh"
PRELUDE="$SRC_DIR/relay/scripts/discover-prelude.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "inject.sh not found/executable at $SH"

export INJECT_BASE; INJECT_BASE="$(mktemp -d)"
export INJECT_LOG=/dev/null
trap 'rm -rf "$INJECT_BASE"' EXIT

# ── (A) helper semantics: scoped take ────────────────────────────────────────────────────
tok_a="$("$SH" add cartulary --item aaaa)"
tok_b="$("$SH" add lodelore  --item f3cf)"

out="$("$SH" take --repo cartulary)"
[[ "$(printf '%s\n' "$out" | grep -c .)" == 1 ]] || fail "scoped take emitted more than the in-scope unit"
jq -e '.repo=="cartulary"' <<<"$out" >/dev/null || fail "scoped take emitted the wrong repo"
pass "take --repo emits only the in-scope shard"

[[ -f "$INJECT_BASE/inject.d/$tok_b.json" ]] \
  || fail "THE BUG: out-of-scope shard ($tok_b, lodelore) was consumed by a cartulary-scoped take"
[[ -f "$INJECT_BASE/inject.done/$tok_a.json" ]] || fail "in-scope shard was not moved to inject.done"
pass "take --repo leaves the out-of-scope shard PENDING (no steal, no loss)"

# the pending shard is still takeable by the pool that can work it
out2="$("$SH" take --repo lodelore)"
jq -e '.repo=="lodelore"' <<<"$out2" >/dev/null || fail "the left-pending shard was not takeable afterwards"
pass "the left-pending shard is still takeable by its own repo's pool"

# unscoped take is unchanged (global drain)
"$SH" add r1 >/dev/null; "$SH" add r2 >/dev/null
[[ "$("$SH" take | grep -c .)" == 2 ]] || fail "unscoped take is no longer a global drain (regression)"
pass "unscoped take still drains globally (unchanged for an unscoped pool)"

# a non-matching scope consumes NOTHING (fail-closed, not fail-open-to-global)
"$SH" add only-mine >/dev/null
[[ -z "$("$SH" take --repo __unresolvable-scope__)" ]] || fail "sentinel scope emitted a unit"
[[ "$("$SH" peek | grep -c .)" == 1 ]] || fail "sentinel scope consumed a shard — must consume NOTHING"
pass "a scope matching no repo consumes nothing (fail-CLOSED, never a global drain)"

# peek is scopeable too, and remains non-consuming
[[ -z "$("$SH" peek --repo nonesuch)" ]] || fail "scoped peek emitted a non-matching shard"
[[ "$("$SH" peek --repo only-mine | grep -c .)" == 1 ]] || fail "scoped peek did not emit the matching shard"
[[ "$("$SH" peek | grep -c .)" == 1 ]] || fail "peek consumed a shard (must be non-consuming)"
pass "peek --repo filters and stays non-consuming"

# unknown arg is a LOUD reject, not a silent global take
if "$SH" take --bogus x 2>/dev/null; then fail "take accepted an unknown arg (silent global-take risk)"; fi
pass "take rejects an unknown arg loudly"

# ── (B) discover-prelude.sh threads ONLY_REPO into the CONSUMING take ─────────────────────
grep -q 'scope_args=(--repo "\$ONLY_REPO")' "$PRELUDE" \
  || fail "discover-prelude.sh does not scope inject.sh take by \$ONLY_REPO (routed:a923)"
# the scope must be a conditional ARG on the ONE call site, never a second (double-drain).
[[ "$(grep -c '"\$INJECT_SH" take' "$PRELUDE")" == 1 ]] \
  || fail "discover-prelude.sh no longer has EXACTLY one inject.sh take call site"
pass "discover-prelude.sh scopes its single CONSUMING take by \$ONLY_REPO"

# end-to-end: the prelude with ONLY_REPO set leaves the out-of-scope shard pending
tok_x="$("$SH" add scoped-repo)"; tok_y="$("$SH" add other-repo)"
RELAY_TOML="$INJECT_BASE/nonexistent.toml" ONLY_REPO=scoped-repo \
  RELAY_DISCOVER_PRELUDE_LOG=/dev/null "$PRELUDE" >/dev/null 2>&1 || true
[[ -f "$INJECT_BASE/inject.d/$tok_y.json" ]] \
  || fail "THE BUG end-to-end: discover-prelude.sh under ONLY_REPO consumed the out-of-scope shard"
[[ -f "$INJECT_BASE/inject.done/$tok_x.json" ]] \
  || fail "discover-prelude.sh under ONLY_REPO did not consume its OWN in-scope shard"
"$SH" take >/dev/null   # reset
pass "discover-prelude.sh end-to-end: consumes in-scope, leaves out-of-scope PENDING"

# ── (C) relay-loop.js wiring ──────────────────────────────────────────────────────────────
node --check "$JS" || fail "relay-loop.js fails node --check"

grep -q 'INJECT_SCOPE' "$JS" || fail "relay-loop.js has no INJECT_SCOPE (scope never reaches the takes)"
grep -q 'ONLY_REPO=\${INJECT_SCOPE}' "$JS" \
  || fail "the prelude dispatch does not thread ONLY_REPO=\$INJECT_SCOPE"
grep -q 'inject.sh take\${INJECT_SCOPE ? ` --repo \${INJECT_SCOPE}`' "$JS" \
  || fail "the MID-ROUND take (takeInjections) is not scoped — the second steal path stays open"
pass "relay-loop.js scopes BOTH the prelude take and the mid-round take"

# fail-closed sentinel on an unsafe scope name (shell-splice guard)
grep -q '__unresolvable-scope__' "$JS" \
  || fail "no fail-closed sentinel for an unsafe --only name (would splice into the shell or drain globally)"
grep -q "A-Za-z0-9._-" "$JS" || fail "no character allowlist guarding the shell-spliced scope token"
pass "an unsafe --only name yields a no-match sentinel (fail-closed, injection-safe)"

# backstop: an out-of-scope injected unit that reaches the loop anyway is refused LOUDLY
grep -q 'function enforceInjectScope' "$JS" || fail "no enforceInjectScope backstop"
grep -q 'SCOPE VIOLATION' "$JS" || fail "the backstop does not log loudly (silent drop = the same loss)"
grep -q 'enforceInjectScope(prelude.injectedUnits' "$JS" \
  || fail "the prelude merge path is not backstopped"
grep -q 'enforceInjectScope(parseInjectTake' "$JS" || fail "the mid-round path is not backstopped"
pass "out-of-scope injected units are refused with a LOUD, recoverable log on both paths"

echo "ALL PASS: inject take is scope-aware end to end (routed:a923)"
