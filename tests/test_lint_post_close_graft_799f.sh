#!/usr/bin/env bash
# roadmap:799f
#
# RED SPEC for id:799f -- the DECLARATION-axis sibling of id:11a4 (the EXPECTED-RED axis).
# See ROADMAP.md id:799f for the full context: the `# fails-against` exemption in
# tests/lint-vacuous-fixtures.py used to be keyed on a roadmap-spec file's mere token
# PRESENCE, so once the item closed the exemption never expired -- a defect-fix case grafted
# into an already-landed roadmap-keyed spec inherited a blanket exemption and was verifiable
# by nothing. Confirmed live: case (8) of
# tests/test_title_rewrite_batch_acceptance_64f9.sh (id:227d) landed into a file keyed
# `# roadmap:521b`, which had already closed, with no `# fails-against*` declaration and no
# entry in tests/negative-case-exemptions.txt.
#
# This spec builds two fixture git repos:
#   (1) GRAFT   -- a roadmap-keyed test file, item CLOSED, that gains an undeclared
#                  assertion in a commit AFTER the item's closing commit. Must be FLAGGED.
#   (2) UNTOUCHED -- the same closed-item file, never touched again since closure. Must
#                  stay exempt (the population this item explicitly forbids sweeping into
#                  new violations -- 355 files measured 2026-09-09).
#
# Hermetic: fixture repos in a mktemp -d, no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/hermetic-git-env.sh"

LINT="$ROOT/tests/lint-vacuous-fixtures.py"
[[ -f "$LINT" ]] || { echo "FAIL: sanity: lint-vacuous-fixtures.py must exist"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

git_c() { git -C "$1" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false "${@:2}"; }

# ---------------------------------------------------------------------- (1) GRAFT fixture
G="$TMP/graft"
mkdir -p "$G/tests"
printf -- '- [x] [ROUTINE] **fixture item, closed.** <!-- id:c799 -->\n' > "$G/ROADMAP.md"
{
  printf '#!/usr/bin/env bash\n'
  printf '# roadmap:c799\n'
  printf 'set -euo pipefail\n'
  printf 'fail() { echo "FAIL: $*"; exit 1; }\n'
  printf '[[ 1 -eq 1 ]] || fail "(1) baseline case, present at closing time"\n'
  printf 'echo "PASS: (1) baseline"\n'
} > "$G/tests/test_graft_fixture.sh"
git -C "$G" init -q
git -C "$G" add -A
git_c "$G" commit -qm "close c799 with baseline case"

# The graft: an UNDECLARED new assertion added after the item already closed — exactly the
# id:227d/64f9 shape, with no `# fails-against*` line accompanying it.
printf '[[ 2 -eq 2 ]] || fail "(2) grafted case, added after closure, undeclared"\n' \
  >> "$G/tests/test_graft_fixture.sh"
git -C "$G" add -A
git_c "$G" commit -qm "graft an undeclared case into the closed c799 spec"

out_graft="$(python3 "$LINT" "$G/tests/test_graft_fixture.sh" 2>&1)"
grep -q 'test_graft_fixture.sh' <<<"$out_graft" \
  || fail "(1) a case grafted into a CLOSED roadmap-keyed spec after closure, with no declaration, was NOT flagged:
$out_graft"
pass "(1) a post-close undeclared graft into a closed roadmap-spec file is flagged"

# ------------------------------------------------------------------ (2) UNTOUCHED control
U="$TMP/untouched"
mkdir -p "$U/tests"
printf -- '- [x] [ROUTINE] **fixture item, closed.** <!-- id:c799 -->\n' > "$U/ROADMAP.md"
{
  printf '#!/usr/bin/env bash\n'
  printf '# roadmap:c799\n'
  printf 'set -euo pipefail\n'
  printf 'fail() { echo "FAIL: $*"; exit 1; }\n'
  printf '[[ 1 -eq 1 ]] || fail "(1) baseline case, present at closing time"\n'
  printf 'echo "PASS: (1) baseline"\n'
} > "$U/tests/test_untouched_fixture.sh"
git -C "$U" init -q
git -C "$U" add -A
git_c "$U" commit -qm "close c799 with baseline case, never touched again"

out_untouched="$(python3 "$LINT" "$U/tests/test_untouched_fixture.sh" 2>&1)"
if grep -q 'test_untouched_fixture.sh' <<<"$out_untouched"; then
  fail "(2) an UNTOUCHED landed RED spec (nothing changed since its item closed) was flagged -- false positive, exactly the 355-file sweep this item forbids:
$out_untouched"
fi
pass "(2) an untouched landed RED spec stays exempt after its item closes"

# ------------------------------------------------------- (3) total does not explode: a
# still-OPEN roadmap item stays fully exempt regardless of later edits (unchanged behaviour).
O="$TMP/open"
mkdir -p "$O/tests"
printf -- '- [ ] [ROUTINE] **fixture item, still open.** <!-- id:o799 -->\n' > "$O/ROADMAP.md"
{
  printf '#!/usr/bin/env bash\n'
  printf '# roadmap:o799\n'
  printf 'set -euo pipefail\n'
  printf 'fail() { echo "FAIL: $*"; exit 1; }\n'
  printf '[[ 1 -eq 1 ]] || fail "(1) baseline"\n'
} > "$O/tests/test_open_fixture.sh"
git -C "$O" init -q
git -C "$O" add -A
git_c "$O" commit -qm "baseline, item still open"
printf '[[ 2 -eq 2 ]] || fail "(2) more case added while item is still open"\n' \
  >> "$O/tests/test_open_fixture.sh"
git -C "$O" add -A
git_c "$O" commit -qm "add another case while c799 is open"

out_open="$(python3 "$LINT" "$O/tests/test_open_fixture.sh" 2>&1)"
if grep -q 'test_open_fixture.sh' <<<"$out_open"; then
  fail "(3) a still-OPEN roadmap item's spec was flagged -- its redness is the spec regardless of edits:
$out_open"
fi
pass "(3) a still-open roadmap item stays exempt even after gaining a case"

echo "ALL PASS: post-close graft check (id:799f)"
