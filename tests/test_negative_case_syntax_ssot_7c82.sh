#!/usr/bin/env bash
# Defect-fix test for id:7c82 -- no roadmap header on purpose (see CLAUDE.md Testing).
#
# fails-against-mutation: sed -i 's/return bool(pat.search(text))/return True/' tests/lib/negative_case_syntax.py
# fails-against-assertion: (a) a CLOSED roadmap item must let its declared case run
# fails-against-mutation: sed -i 's/(?:-rev|-mutation)?//' tests/lib/negative_case_syntax.py
# fails-against-assertion: (c) the lint must accept the machine-readable spellings
#
# THE DEFECT (id:7c82): two tools read the SAME three header markers and each carried its own
# regex, so they disagreed.
#
#   (a) `tests/verify-negative-cases.py` bucketed a file as roadmap-spec on the mere PRESENCE
#       of a `# roadmap:XXXX` token, before considering any `# fails-against-*` declaration,
#       and never consulted the item's checkbox. The carve-out therefore never expired:
#       `tests/run-tests.sh` stops granting EXPECTED-RED the moment the item is ticked, while
#       this runner went on cancelling that file's declaration forever, silently. Every
#       CLOSED roadmap-spec test in the repo was permanently unverifiable.
#   (b) `tests/lint-vacuous-fixtures.py` matched only the BARE `# fails-against:` spelling, so
#       the ratified `-rev:`/`-mutation:` forms were invisible to it and every file using them
#       was flagged as undeclared (measured 2026-09-03: 11 flagged, 2 false positives).
#
# The fix is ONE definition, `tests/lib/negative_case_syntax.py`, imported by both -- the
# id:4983 class ("make one source serve the actor and the checker"). Case (e) pins that: a
# reintroduced local regex in either tool is the drift itself, and would go unnoticed while
# both tools happened to agree.
#
# The two mutations are chosen to hit ONE assertion each and to be independent: mutation 1
# makes every roadmap item look OPEN (presence-keyed carve-out, the pre-fix behaviour) and is
# caught by (a); mutation 2 strips the `-rev|-mutation` alternation out of the shared
# declaration pattern, restoring the pre-fix lint, and is caught by (c). `fail()` exits, so
# exactly one FAIL line fires per run and it is the declared one.
#
# Hermetic: fixture repos in a mktemp -d, no ~/.claude, no network. The fixture test files
# below build their `# roadmap:` / `# fails-against-*` header lines with printf rather than
# writing them literally -- a literal marker anywhere in THIS file would be read as this
# file's own by the whole-file scans in run-tests.sh, the lint and the runner.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/hermetic-git-env.sh"

VERIFY="$ROOT/tests/verify-negative-cases.py"
LINT="$ROOT/tests/lint-vacuous-fixtures.py"
SHARED="$ROOT/tests/lib/negative_case_syntax.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$VERIFY" ]] || fail "sanity: verify-negative-cases.py must exist"
[[ -f "$LINT"   ]] || fail "sanity: lint-vacuous-fixtures.py must exist"
[[ -f "$SHARED" ]] || fail "sanity: the shared definition tests/lib/negative_case_syntax.py must exist"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# ---------------------------------------------------------------- fixture repo builder
# $1 = dir, $2 = 4-hex token, $3 = checkbox char (' ' open, 'x' closed)
mk_repo() {
  local dir="$1" tok="$2" box="$3"
  mkdir -p "$dir/tests"
  printf 'GOOD\n' > "$dir/widget.txt"
  printf -- '- [%s] [ROUTINE] **fixture item.** <!-- id:%s -->\n' "$box" "$tok" > "$dir/ROADMAP.md"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# %s:%s\n' 'roadmap' "$tok"
    printf '# %s: %s\n' 'fails-against-mutation' "sed -i 's/GOOD/BAD/' widget.txt"
    printf '# %s: %s\n' 'fails-against-assertion' '(z) widget must read GOOD'
    printf 'set -euo pipefail\n'
    printf 'R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n'
    printf 'grep -q GOOD "$R/widget.txt" || { echo "FAIL: (z) widget must read GOOD"; exit 1; }\n'
    printf 'echo "PASS: (z) widget"\n'
  } > "$dir/tests/test_fixture_case.sh"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false \
      commit -qm fixture
}

CLOSED="$TMP/closed"; mk_repo "$CLOSED" aaaa x
OPEN="$TMP/open";     mk_repo "$OPEN"   bbbb ' '

# --------------------------------------------------------- (a) closed item => case RUNS
out_closed="$(python3 "$VERIFY" --root "$CLOSED" 2>&1)" || true
grep -q 'red-there  OK' <<<"$out_closed" \
  || fail "(a) a CLOSED roadmap item must let its declared case run, but the runner never executed it:
$out_closed"
pass "(a) closed roadmap item: declared case executed and red-there verified"

grep -q 'carve-out EXPIRED' <<<"$out_closed" \
  || fail "(b1) the expired carve-out must be REPORTED, not silently applied:
$out_closed"
pass "(b1) expired carve-out is named in the coverage report"

# ------------------------------------------------------- (b) open item => still skipped
out_open="$(python3 "$VERIFY" --root "$OPEN" 2>&1)" || true
if grep -q 'red-there' <<<"$out_open"; then
  fail "(b) an OPEN roadmap item is the RED SPEC and must NOT have its case executed:
$out_open"
fi
grep -q '1 roadmap-spec' <<<"$out_open" \
  || fail "(b2) the open-item fixture must be counted as roadmap-spec:
$out_open"
pass "(b) open roadmap item: still carved out, nothing executed"

# ---------------------------------------------------- (c)/(d) lint spelling agreement
L="$TMP/lint"; mkdir -p "$L"
{ printf '#!/usr/bin/env bash\n'; printf '# %s: %s\n' 'fails-against-mutation' 'true'; } > "$L/test_mut.sh"
{ printf '#!/usr/bin/env bash\n'; printf '# %s: %s\n' 'fails-against-rev' 'HEAD -- x'; } > "$L/test_rev.sh"
{ printf '#!/usr/bin/env bash\n'; printf '# %s: %s\n' 'fails-against' 'prose'; } > "$L/test_prose.sh"
{ printf '#!/usr/bin/env bash\n'; printf '# nothing declared\n'; } > "$L/test_none.sh"

out_lint="$(python3 "$LINT" "$L/test_mut.sh" "$L/test_rev.sh" "$L/test_prose.sh" "$L/test_none.sh" 2>&1)"
for f in test_mut.sh test_rev.sh test_prose.sh; do
  if grep -q "VIOLATION: .*$f" <<<"$out_lint"; then
    fail "(c) the lint must accept the machine-readable spellings, but flagged $f:
$out_lint"
  fi
done
pass "(c) lint accepts prose, -rev: and -mutation: declarations alike"

grep -q 'VIOLATION: .*test_none.sh' <<<"$out_lint" \
  || fail "(d) the lint must still flag a defect-fix test with NO declaration at all:
$out_lint"
pass "(d) lint still flags a genuinely undeclared defect-fix test"

# ------------------------------------------------------------- (e) ONE definition, not two
for tool in "$VERIFY" "$LINT"; do
  if grep -nE 're\.compile\(.*(fails-against|roadmap:)' "$tool"; then
    fail "(e) $(basename "$tool") defines its own fails-against/roadmap regex -- both tools must
import the ONE definition in tests/lib/negative_case_syntax.py (id:4983/id:7c82)"
  fi
done
grep -q 'from negative_case_syntax import' "$VERIFY" \
  || fail "(e) verify-negative-cases.py must import the shared definition"
grep -q 'from negative_case_syntax import' "$LINT" \
  || fail "(e) lint-vacuous-fixtures.py must import the shared definition"
pass "(e) both tools import the single shared definition"

# --------------------------------------- (f) the openness test agrees with run-tests.sh
# run-tests.sh:78-83 is the harness's own `item_open`; the shared module is its Python twin.
# If that grep is ever reshaped, this fires rather than letting a second meaning of
# `# roadmap:` grow back.
grep -q 'grep -qE "\^- \\\[ \\\] \.\*<!-- id:\${token} -->"' "$ROOT/tests/run-tests.sh" \
  || fail "(f) run-tests.sh's item_open() pattern changed shape; re-check the twin in
tests/lib/negative_case_syntax.py before adjusting this assertion"
grep -q "\^- \\\\\[ \\\\\] \.\*<!-- id:" "$SHARED" \
  || fail "(f) the shared module no longer mirrors run-tests.sh's item_open() pattern"
pass "(f) shared openness test mirrors run-tests.sh's item_open()"

echo "ALL PASS"
