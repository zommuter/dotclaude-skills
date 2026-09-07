#!/usr/bin/env bash
#
# GREEN REGRESSION-GUARD (no `# roadmap:` header on purpose -- there is no open item
# behind it, so any failure here always counts as a real failure; see CLAUDE.md
# §Testing). Reviewed + boxed in REVIEW_ME.md per review.md §2b.3, which forbids a
# silently-added green test that pins behaviour with no "is this correct or a frozen
# bug?" entry.
#
# WHAT IT PINS, AND WHY IT DID NOT EXIST
#
# `id:b87b` had TWO acceptance clauses in `docs/ledger-notes/b87b.md`:
#   (a) a commit on the runner's OWN branch is not a hermeticity breach, while other
#       `refs/heads/relay/*` drift still is; and
#   (b) "an added ref, a removed ref and a moved ref are three different findings and
#       only the first is 'left new relay/* refs'" -- the message must say WHICH.
#
# The pre-authored RED spec `test_hermeticity_own_branch_b87b.sh` covers (a) fully and
# covers (b) NOT AT ALL: its case (3) is a force-moved-ref COVERAGE assertion, and the
# note's own Done-check case (3) ("assert the breach text for case (2) names the
# addition") was dropped when the spec was written. The ~20 lines of classification
# code in `run-tests.sh` therefore shipped green with zero tests. This file closes that
# gap. It was written by the 2026-09-07 chain-end review, which verified the behaviour
# by hand first; the assertions below are that manual check made durable.
#
# The discriminating half is the NEGATIVE assertion in each case: code that
# unconditionally printed all three labels would satisfy every positive assertion, so
# each case also demands that the two WRONG labels are absent.
#
# EVERY label pattern below is LINE-ANCHORED on the runner's two-space indent, and that
# is load-bearing rather than tidiness: "removed ref(s):" CONTAINS "moved ref(s):" as a
# substring, so an unanchored negative assertion reports the removed case as also
# claiming a move. The first draft of this file did exactly that and failed for that
# reason alone.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

RUNNER="$(pwd)/tests/run-tests.sh"
[[ -f "$RUNNER" ]] || { echo "FIXTURE-BROKEN: no $RUNNER"; exit 1; }

fails=0
FAIL() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok: $*"; }

# Drive the REAL runner in a throwaway repo holding exactly one (leaking) test, so the
# breach path is exercised end-to-end rather than by re-implementing the snapshot.
run_with_leak() { # $1 = shell body for the leaking test; echoes the runner's output
  local scratch
  scratch=$(mktemp -d)
  mkdir -p "$scratch/tests"
  cp "$RUNNER" "$scratch/tests/run-tests.sh"
  chmod +x "$scratch/tests/run-tests.sh"
  {
    echo '#!/usr/bin/env bash'
    printf '%s\n' "$1"
    echo 'echo "PASS: leaker"'
  } > "$scratch/tests/test_leak.sh"
  chmod +x "$scratch/tests/test_leak.sh"
  # The fixture repo is checked out on a `relay/*` branch, which is the REAL deployment
  # condition (every relay child runs this suite from a `relay/<runId>-...` worktree) and
  # is what makes case (4) below non-vacuous: on a default `main` branch the runner's own
  # ref is not inside the watched `refs/heads/relay/` namespace at all, so an own-branch
  # commit could never raise a breach and case (4) would pass against the PRE-b87b runner
  # too. Checked: it does fail there once the branch is inside the namespace.
  git -C "$scratch" init -q -b relay/fixture-review-repo-0
  echo seed > "$scratch/f"
  git -C "$scratch" -c user.email=t@e -c user.name=t add -A
  git -C "$scratch" -c user.email=t@e -c user.name=t commit -qm seed
  # A pre-existing relay ref, so the removed/moved cases have something to act on.
  git -C "$scratch" update-ref refs/heads/relay/pre HEAD
  ( cd "$scratch" && bash tests/run-tests.sh 2>&1 )
  rm -rf "$scratch"
}

ADDED_RE='^  added ref\(s\):'
REMOVED_RE='^  removed ref\(s\):'
MOVED_RE='^  moved ref\(s\):'

# $1 = case label, $2 = anchored regex for the ONE label expected, $3 = the ref name it
# must name, $4 = runner output, $5.. = anchored regexes that must be ABSENT
assert_classified() {
  local case_label="$1" want="$2" want_ref="$3" out="$4"; shift 4
  if ! grep -q 'HERMETICITY BREACH' <<<"$out"; then
    echo "FIXTURE-BROKEN: $case_label did not raise a breach at all, so the label"
    echo "assertions below would be vacuous."
    exit 1
  fi
  local line
  line="$(grep -E "$want" <<<"$out")"
  if [[ -z "$line" ]]; then
    FAIL "$case_label printed no '$want' line -- the breach message does not say WHICH drift fired"
  elif [[ "$line" != *"$want_ref"* ]]; then
    FAIL "$case_label labelled the drift but named the wrong ref: '$line' (wanted $want_ref)"
  else
    pass "$case_label names its finding and its ref ($want_ref)"
  fi
  local bad
  for bad in "$@"; do
    if grep -qE "$bad" <<<"$out"; then
      FAIL "$case_label ALSO printed a '$bad' line -- the labels are not discriminating"
    else
      pass "$case_label correctly omits $bad"
    fi
  done
}

added_out=$(run_with_leak 'git update-ref refs/heads/relay/leaked HEAD')
assert_classified "(1) an ADDED relay ref" \
  "$ADDED_RE" 'refs/heads/relay/leaked' "$added_out" \
  "$REMOVED_RE" "$MOVED_RE"

removed_out=$(run_with_leak 'git update-ref -d refs/heads/relay/pre')
assert_classified "(2) a REMOVED relay ref" \
  "$REMOVED_RE" 'refs/heads/relay/pre' "$removed_out" \
  "$ADDED_RE" "$MOVED_RE"

moved_out=$(run_with_leak 'echo x >> f
git -c user.email=t@e -c user.name=t commit -qam m2
git update-ref refs/heads/relay/pre HEAD')
assert_classified "(3) a MOVED relay ref" \
  "$MOVED_RE" 'refs/heads/relay/pre' "$moved_out" \
  "$ADDED_RE" "$REMOVED_RE"

# (4) The id:b87b core, restated through the REAL runner rather than the extracted
# snapshot function the b87b spec uses: a commit on the runner's own branch must not
# raise a breach at all, so none of the three labels can appear.
own_out=$(run_with_leak 'echo y >> f
git -c user.email=t@e -c user.name=t commit -qam "work as the contract requires"')
if grep -q 'HERMETICITY BREACH' <<<"$own_out"; then
  FAIL "(4) a commit on the runner's own relay branch raised a breach through the real runner (id:b87b regression)"
else
  pass "(4) a commit on the runner's own relay branch is clean end-to-end"
fi

if (( fails )); then
  echo "$fails assertion(s) failed"
  exit 1
fi
echo "PASS: hermeticity breach messages classify added/removed/moved distinctly (id:b87b clause b)"
