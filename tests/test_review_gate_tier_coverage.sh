#!/usr/bin/env bash
# roadmap:66d4
# RED spec (authored by /relay handoff 2026-07-19, apex) for id:66d4 — the tier-coverage
# checkpoint gate that MECHANIZES review.md §3 (id:f032, fully specified but per-turn-LLM-
# trusted today). Origin: chidiai `2026-07-18-during-relay-review-loderite-skipped-the`.
#
# Contract under test — a NEW relay/scripts/review-gate.sh:
#   review-gate.sh --repo <dir> --entry <file>
#   enumerates the DECLARED test tiers from <dir>'s manifests (this spec exercises the
#   package.json `scripts` source: each script key whose name contains "test" is a declared
#   tier, tier-name = the key) and REFUSES the checkpoint (nonzero exit) unless <file> (the
#   checkpoint-entry text) covers each declared tier with EITHER a result token
#   (`<tier>: <result>`) OR a `SKIPPED-TIER: <tier> — <reason>` line.
#   TOOLCHAIN-PRESENCE PROBE (the crux): a `SKIPPED-TIER` claim is REJECTED (nonzero) if the
#   toolchain is in fact present — here, a populated `<dir>/node_modules`. A judgment excuse
#   ("doc-only window") must NOT satisfy a skip when the tooling is installed.
#
# EXPECTED-RED while roadmap:66d4 is unticked. review-gate.sh does not exist yet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="$ROOT/relay/scripts/review-gate.sh"
[[ -x "$RG" ]] || { echo "review-gate.sh missing (RED): $RG"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A repo fixture declaring two test tiers via package.json scripts: `test` and `test:e2e`.
mkfixture() {  # mkfixture <dir> [with_node_modules]
  local d="$1"; mkdir -p "$d"
  cat > "$d/package.json" <<'EOF'
{ "name": "fixture", "scripts": { "build": "tsc", "test": "vitest run", "test:e2e": "playwright test" } }
EOF
  if [[ "${2:-}" == "with_node_modules" ]]; then
    mkdir -p "$d/node_modules/.bin"; : > "$d/node_modules/.bin/vitest"
  fi
}

# --- (a) MISSING TIER → refuse ------------------------------------------------------------
D="$tmp/a"; mkfixture "$D"
printf 'test: 12 passed\n' > "$tmp/a_entry"     # covers `test`, omits `test:e2e`
if "$RG" --repo "$D" --entry "$tmp/a_entry" 2>"$tmp/a_err"; then
  echo "FAIL (a): entry missing the test:e2e tier must be REFUSED (nonzero), got exit 0"; exit 1
fi
grep -q 'e2e' "$tmp/a_err" || { echo "FAIL (a): refusal must name the uncovered tier (test:e2e) on stderr"; exit 1; }

# --- (b) ALL TIERS REPORTED → accept ------------------------------------------------------
D="$tmp/b"; mkfixture "$D"
printf 'test: 12 passed\ntest:e2e: 5 passed\n' > "$tmp/b_entry"
"$RG" --repo "$D" --entry "$tmp/b_entry" || { echo "FAIL (b): entry covering every declared tier must be ACCEPTED (exit 0)"; exit 1; }

# --- (c) SKIPPED-TIER but TOOLCHAIN PRESENT → refuse (the crux) ----------------------------
D="$tmp/c"; mkfixture "$D" with_node_modules
printf 'test: 12 passed\nSKIPPED-TIER: test:e2e — doc-only window\n' > "$tmp/c_entry"
if "$RG" --repo "$D" --entry "$tmp/c_entry" 2>"$tmp/c_err"; then
  echo "FAIL (c): SKIPPED-TIER with node_modules present must be REJECTED (toolchain probe), got exit 0"; exit 1
fi

# --- (d) SKIPPED-TIER with TOOLCHAIN ABSENT → accept --------------------------------------
D="$tmp/d"; mkfixture "$D"   # no node_modules → toolchain genuinely absent
printf 'test: 12 passed\nSKIPPED-TIER: test:e2e — playwright not installed on host\n' > "$tmp/d_entry"
"$RG" --repo "$D" --entry "$tmp/d_entry" || { echo "FAIL (d): SKIPPED-TIER with toolchain absent must be ACCEPTED (exit 0)"; exit 1; }

echo "PASS: tier-coverage checkpoint gate (66d4)"
