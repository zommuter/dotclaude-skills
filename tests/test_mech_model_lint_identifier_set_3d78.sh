#!/usr/bin/env bash
# DEFECT FIX — no `# roadmap:` header on purpose: id:3d78 is a defect filed by the
# 2026-08-13 relay review, not a ROADMAP item, so this file's failures always count.
#
# Defect (id:3d78): `5c425fc` shipped
#   AGENT_CALL_IDENTIFIERS = new Set(['agent', 'dispatchGuarded', 'agentGuarded', 'safeAgent'])
# while the RATIFIED id:ed3f spec (recovered by `edbc462`) says verbatim:
#   "`dispatchGuarded` is the ONLY such wrapper in the tree today (`agentGuarded`/`safeAgent`
#    do not exist — do not invent matchers for them)."
# A derived implementation drifting from its ratified source in the PERMISSIVE direction —
# invisible to a green suite, because matching a non-existent identifier fails nothing.
#
# The lint's identifier set must therefore track the tree, not speculate: a wrapper earns a
# matcher when it EXISTS, and the spec is amended at that point (owner's call), not
# pre-emptively. This suite pins both directions — the two real identifiers are still
# matched, the two invented ones are not.
# fails-against: rev 7b69fa084b2d -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/classify-repo.sh, relay/scripts/gather-repo-state.sh, relay/scripts/lib-roadmap-sections.sh (+3 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 7b69fa084b2d -- relay/scripts/classify-repo.sh relay/scripts/gather-repo-state.sh relay/scripts/lib-roadmap-sections.sh relay/scripts/lib-state-claim.sh relay/scripts/lint-mech-model.mjs relay/scripts/roadmap-lint.sh
# fails-against-assertion: is matched, contradicting the ratified id:ed3f spec clause

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/lint-mech-model.mjs"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -f "$LINT" ]] || { echo "lint-mech-model.mjs not found at $LINT"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# sample <name> <identifier> — a fence-carrying call hardcoding model:'bash' (the exact
# shape the lint exists to reject) dispatched through <identifier>.
sample() {
  cat > "$TMP/$1.workflow.js" <<EOF
export const meta = { name: '$1' }
async function run() {
  await $2(
    { label: 'release:x', phase: 'Leases', model: 'bash' },
    'repo',
    'Run exactly this one command:\n\`\`\`relay-mech\nclaim.sh release x\n\`\`\`'
  )
}
EOF
  node "$LINT" "$TMP/$1.workflow.js" >/dev/null 2>&1 && echo clean || echo flagged
}

# ── the identifiers that EXIST in the tree are still linted (positive controls) ─────────
for ident in agent dispatchGuarded; do
  [[ "$(sample "real-$ident" "$ident")" == "flagged" ]] \
    && ok "$ident( — a real dispatch identifier — is still linted" \
    || bad "$ident( is no longer linted: the narrowing went too far (id:ed3f's actual scope)"
done

# ── the identifiers the ratified spec FORBADE are not matched ───────────────────────────
for ident in agentGuarded safeAgent; do
  [[ "$(sample "invented-$ident" "$ident")" == "clean" ]] \
    && ok "$ident( is NOT matched — the id:ed3f spec forbade inventing this matcher" \
    || bad "$ident( is matched, contradicting the ratified id:ed3f spec clause"
done

# ── and neither invented identifier exists in the tree, which is WHY (re-derived, not
#    trusted from the finding text): if one ever does, this test is the place to amend,
#    together with the spec clause — that is an owner call, not a silent widening.
found=$(grep -rlE '\b(function|const|let)\s+(agentGuarded|safeAgent)\b' "$ROOT/relay/scripts" || true)
[[ -z "$found" ]] \
  && ok "neither agentGuarded nor safeAgent is defined anywhere in relay/scripts" \
  || bad "a wrapper the spec called non-existent now EXISTS ($found) — amend the id:ed3f spec clause and this test together"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
