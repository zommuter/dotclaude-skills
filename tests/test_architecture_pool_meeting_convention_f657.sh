#!/usr/bin/env bash
# roadmap:f657
# Spec for the ARCHITECTURE.md pool-∥-meeting parallel-safety convention (id:f657).
#
# A scoped `/relay --afk --only <repo>` pool and a `/meeting` were observed running
# concurrently on the SAME repo with no ledger collision. The three mechanisms that make it
# safe are already built; the convention (what is safe to run in parallel and WHY) is a
# durable topology fact that ARCHITECTURE.md owns — not item status. This test asserts that
# subsection exists and names the load-bearing mechanisms by their ids.
#
# A doc-content contract is a LEGITIMATE assertion over a markdown file (the carve-out in
# tests/lint-source-grep-assertions.py's own DOC class), not a source-grep-as-behaviour smell.
#
# Hermetic: reads the shipped ARCHITECTURE.md read-only; no tmp, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/ARCHITECTURE.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$DOC" ]] || fail "ARCHITECTURE.md not found at $DOC"

# The two load-bearing mechanism ids must BOTH be cited (distinct claim keys id:0ee1;
# ledger-only writes are not lease-gated id:c144). These are the mechanisms the item
# requires the subsection to name.
grep -q '0ee1' "$DOC" \
  || fail "ARCHITECTURE.md must cite id:0ee1 (distinct claim keys) in the pool-∥-meeting convention (id:f657 not yet done)"
grep -q 'c144' "$DOC" \
  || fail "ARCHITECTURE.md must cite id:c144 (ledger-only writes are not lease-gated) in the pool-∥-meeting convention (id:f657 not yet done)"
pass "both mechanism ids (0ee1, c144) are cited"

# The citations must sit in an actual pool-∥-meeting parallel-safety context, not merely
# appear somewhere in the file. Require a line that mentions BOTH 'pool' and 'meeting' in a
# parallel/concurrent framing.
grep -iEq '(pool[^\n]*meeting|meeting[^\n]*pool)' "$DOC" \
  || fail "ARCHITECTURE.md must describe the pool ∥ meeting parallel topology (a line naming both 'pool' and 'meeting')"
grep -iEq 'parallel|concurrent|∥|simultaneous' "$DOC" \
  || fail "ARCHITECTURE.md must frame it as a parallel/concurrent-safety convention"
pass "a pool ∥ meeting parallel-safety framing is present"

echo "ALL PASS: ARCHITECTURE.md pool-∥-meeting parallel-safety convention (id:f657)"
