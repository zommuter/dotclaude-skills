#!/usr/bin/env bash
# roadmap:292b
# Spec for tests/lint-vacuous-fixtures.py (id:292b) — the sibling of
# tests/lint-source-grep-assertions.py.
#
# The defect class this lint guards: a "defect-fix" test (one filed against a bug rather
# than an open ROADMAP item) that LOOKS behavioural but proves nothing because its fixture
# never reaches the guarded code path (three live 2026-08-13 instances — see TODO id:292b).
# Mechanism (1), the one this item ships: every defect-fix test file MUST declare the
# revision/mutation it is meant to FAIL against via a `# fails-against: <rev|mutation>`
# header, making the vacuous-fixture check a conscious, on-record discipline.
#
# Convention (CLAUDE.md §Testing): a test file WITHOUT a `# roadmap:XXXX` header IS a
# defect-fix test (its failures always count); a file WITH one is the RED spec of an open
# roadmap item and is exempt (its redness is the point).
#
# Every assertion RUNS the lint over purpose-built fixture test files under $tmpdir. There is
# NO assertion about the lint's own source text (that would be the very defect being linted).
#
# Hermetic: mktemp -d only; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/tests/lint-vacuous-fixtures.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-vacuous-fixtures.py not found at $LINT (id:292b not yet built)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
fix="$tmpdir/tests"
mkdir -p "$fix"

# (a) VIOLATION: a defect-fix test (no `# roadmap:` header) that omits `# fails-against:`.
cat > "$fix/test_undeclared.sh" <<'EOF'
#!/usr/bin/env bash
# guards some bug — but declares nothing it must fail against
set -euo pipefail
echo behavioural-looking
EOF

# (b) COMPLIANT: a defect-fix test that declares its negative case.
cat > "$fix/test_declared.sh" <<'EOF'
#!/usr/bin/env bash
# fails-against: HEAD~1 (revert of the id:abcd fix)
set -euo pipefail
echo behavioural
EOF

# (c) EXEMPT: a roadmap-spec test (carries `# roadmap:`) — its redness IS the spec, so the
#     `# fails-against:` requirement must NOT apply to it.
cat > "$fix/test_roadmap_spec.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:9f9f
set -euo pipefail
echo red-spec
EOF

run() { python3 "$LINT" "$@"; }

# --- (a) the undeclared defect-fix test is FLAGGED --------------------------------------
out_a="$(run "$fix/test_undeclared.sh" || true)"
grep -q 'test_undeclared.sh' <<<"$out_a" \
  || { sed 's/^/    /' <<<"$out_a"; fail "(a) a defect-fix test missing '# fails-against:' was NOT flagged"; }
pass "(a) a defect-fix test with no '# fails-against:' header is flagged"

# --- (b) a declared defect-fix test is NOT flagged --------------------------------------
out_b="$(run "$fix/test_declared.sh" || true)"
! grep -q 'test_declared.sh' <<<"$out_b" \
  || { sed 's/^/    /' <<<"$out_b"; fail "(b) a test that DOES declare '# fails-against:' was flagged — false positive"; }
pass "(b) a defect-fix test that declares its negative case is not flagged"

# --- (c) a roadmap-spec test is exempt (its redness is the spec) ------------------------
out_c="$(run "$fix/test_roadmap_spec.sh" || true)"
! grep -q 'test_roadmap_spec.sh' <<<"$out_c" \
  || { sed 's/^/    /' <<<"$out_c"; fail "(c) a '# roadmap:' spec test must be exempt from the fails-against requirement"; }
pass "(c) a roadmap-spec test is exempt"

# --- advisory by default (exit 0), non-zero only under --strict -------------------------
run "$fix/test_undeclared.sh" >/dev/null 2>&1 \
  || fail "the lint must be ADVISORY (exit 0) by default even with a hit"
if python3 "$LINT" --strict "$fix/test_undeclared.sh" >/dev/null 2>&1; then
  fail "--strict must exit non-zero when a violation exists"
fi
pass "(d) advisory by default; --strict exits non-zero on a violation"

echo "ALL PASS: vacuous-fixture lint (id:292b)"
