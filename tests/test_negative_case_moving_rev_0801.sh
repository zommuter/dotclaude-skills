#!/usr/bin/env bash
# verify-negative-cases.py must REFUSE a `# fails-against-rev:` that names a MOVING
# revision (id:0801).
#
# No `# roadmap:` header: this is a defect-fix test, not a roadmap item's spec, so
# its failures always count.
#
# Defect: a `# fails-against-rev:` declaration is DURABLE -- re-read weeks later,
# long after commits have landed on top of the one its author was sitting on.
# `HEAD~1` names the pre-fix revision only until the very next commit; after that
# the runner overlays a revision that ALREADY CONTAINS the fix, the test passes,
# and the case is reported VACUOUS. That verdict is the failure this runner exists
# to make impossible, arriving from the DECLARATION side rather than the test side:
# it says "no killing power" about a test whose killing power was never exercised,
# and it is indistinguishable from the real thing. Measured 2026-09-09 on BOTH of
# this repo's relative declarations -- test_roadmap_lint_duplicate_detail_pointer_78e6.sh
# (rotted within one integrate) and test_roadmap_lint_follows_pointer_e95b.sh.
#
# Immutability is decided on the BASE ref, before any `~`/`^`/`@{}` traversal, so
# `<sha>^` is accepted and `HEAD~1` / `main~3` are not.
#
# fails-against: the guard and this spec land in adjacent commits, so the negative
# case is the parent revision of verify-negative-cases.py alone. The rev is PINNED
# to an immutable sha and must never be written `HEAD~1` -- which is, verbatim, the
# defect this file pins.
# fails-against-rev: 4de015846 -- tests/verify-negative-cases.py
# fails-against-assertion: a declaration naming a MOVING revision was accepted
#
# Hermetic: parses fixture headers via the runner's own --list mode in a temp dir;
# no ~/.claude, no network, no writes outside mktemp.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/tests/verify-negative-cases.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$RUNNER" ]] || fail "verify-negative-cases.py not found at $RUNNER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Load the runner as a module and exercise the predicate directly. The whole-run
# path needs a git repo, a corpus and minutes of wall time; the CONFIG ERROR this
# file pins is produced by a pure function, so probe that function.
probe() {
  python3 - "$RUNNER" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vnc", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
fn = getattr(m, "validate_rev_immutable", None)
if fn is None:
    print("NO-PREDICATE")
    sys.exit(0)
err = fn(sys.argv[2])
print("ACCEPTED" if err is None else "REFUSED")
PY
}

# (a) THE DEFECT: the exact spelling that rotted twice must be refused.
got="$(probe 'HEAD~1')"
[[ "$got" != "ACCEPTED" && "$got" != "NO-PREDICATE" ]] \
  || fail "a declaration naming a MOVING revision was accepted: rev 'HEAD~1' -> $got"

# (b) The same rot through a named branch, not just HEAD.
got="$(probe 'main~3')"
[[ "$got" == "REFUSED" ]] \
  || fail "(b) 'main~3' traverses from a moving ref but was $got"

# (c) NEGATIVE CONTROL -- the guard must not swallow legitimate immutable revs.
# Without this, refusing everything would satisfy (a) and (b).
for good in 4d133c76ce48 4d133c76ce48^ 9d5048a62acbacbd3a918212341606a01dd25cae; do
  got="$(probe "$good")"
  [[ "$got" == "ACCEPTED" ]] \
    || fail "(c) immutable rev '$good' must stay accepted, got $got"
done

# (d) The repo's own corpus must be clean under the guard, so the refusal is a
# real gate rather than a rule nothing satisfies.
bad="$(grep -rh 'fails-against-rev:' "$ROOT"/tests/test_*.sh \
        | sed 's/.*fails-against-rev: *//' | awk '{print $1}' \
        | grep -E '^(HEAD|[^0-9a-fA-F][^~^@]*[~^])' || true)"
[[ -z "$bad" ]] \
  || fail "(d) the corpus still declares moving revs: $(tr '\n' ' ' <<<"$bad")"

pass "verify-negative-cases.py refuses a MOVING fails-against-rev (HEAD~1, main~3), keeps immutable shas and <sha>^, and the corpus is clean under the guard (id:0801)"
