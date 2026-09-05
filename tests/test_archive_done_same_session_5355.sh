#!/usr/bin/env bash
# roadmap:5355
#
# RED SPEC for id:5355 (adopted from the shared inbox as routed:3b3a, reported by loderite).
#
# THE DEFECT. todo-update/archive-done.sh:107 tests the prior-commit membership FIRST and
# UNCONDITIONALLY:
#
#     if line.rstrip('\n').strip() in prior_done:
#         ym = today_ym
#     else:
#         m = date_re.search(line)   # the `on YYYY-MM-DD` age check -- never reached
#
# `prior_done` is built at :39 from `git show HEAD:$TODO_REL`, so it holds every `[x]` line
# in the PRIOR COMMIT regardless of that line's own date. The mandated skill order
# guarantees the condition is met for work just finished: git-diary-workflow Step 1 commits,
# then Step 3 runs todo-update -- so this session's just-committed `[x]` items ARE in HEAD.
# An item closed minutes ago is archived on the very next run.
#
# Observed 2026-09-04 in lodelore: id:b0a0 and id:3cd8, both dated that same day, were
# archived on the run following their own commit, and were restored by hand.
#
# WHY THIS IS NOT MERELY UNTIDY, which is the reason it is pinned rather than filed as
# cosmetic: archiving moves `routed:XXXX` breadcrumbs OUT of TODO.md. The cross-repo
# twin-guard (scan-routed.sh, append.sh inbox-done) scans only TODO.md and ROADMAP.md, and
# `inbox-done` REFUSES (exit 3) without the twin -- so a same-session close becomes an
# undrainable inbox entry that re-reports forever as a dead letter.
#
# WHAT THE FIX MUST PRESERVE, pinned as case (2): genuinely old entries must still archive
# by the prior-commit path. A fix that simply deletes the prior_done branch would strand
# every dateless `[x]` item in TODO.md forever, which is a worse failure than the bug.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SCRIPT="$(pwd)/todo-update/archive-done.sh"
fails=0
FAIL() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok: $*"; }

TODAY=$(date '+%Y-%m-%d')
OLD=$(date -d '60 days ago' '+%Y-%m-%d')

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

git -C "$scratch" init -q -b main

{
  echo "# TODO"
  echo
  echo "## Current"
  echo
  echo "- [x] Closed in THIS session, dated today <!-- routed:aaaa --> <!-- id:aaaa --> on ${TODAY}."
  echo "- [x] Closed two months ago <!-- id:bbbb --> on ${OLD}."
  # ARMING CANARY. This entry carries NO parseable date, so the date path (script :110)
  # cannot archive it -- only the prior_done branch (:107) can. Its arrival in the archive
  # is therefore PROOF that the branch under test actually fired. Without it a run in which
  # prior_done came back EMPTY would sail through every assertion below, which is exactly
  # how the first draft of this file reported a false PASS: the script resolves prior_done
  # via `git rev-parse --show-toplevel` against the CURRENT DIRECTORY (:36), so running it
  # from outside the fixture repo silently yields an empty set.
  echo "- [x] Dateless canary, archivable only via the prior-commit branch <!-- id:dddd -->"
  echo "- [ ] Still open <!-- id:cccc -->"
  # archive-done.sh only archives when the file has >= 50 lines (script :23).
  for i in $(seq 1 60); do echo "- [ ] filler item $i <!-- id:f$(printf '%03d' "$i") -->"; done
} > "$scratch/TODO.md"

git -C "$scratch" -c user.email=t@e -c user.name=t add -A
git -C "$scratch" -c user.email=t@e -c user.name=t commit -qm "close both items"

# The script derives prior_done from `git rev-parse --show-toplevel` in the CURRENT
# DIRECTORY, so it MUST be invoked from inside the fixture repo or the branch under test is
# never armed.
out=$(cd "$scratch" && bash "$SCRIPT" TODO.md 2>&1)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "FIXTURE-BROKEN: archive-done.sh exited $rc"
  echo "$out"
  exit 1
fi
if [[ ! -f "$scratch/TODO.archive.md" ]]; then
  echo "FIXTURE-BROKEN: no TODO.archive.md was written, so nothing was archived at all;"
  echo "the assertions below would be vacuous. Script output was:"
  echo "$out"
  exit 1
fi
# FIXTURE SANITY -- the arming proof. The dateless canary can ONLY reach the archive via
# the prior_done branch. If it did not move, prior_done was empty, the branch under test
# never executed, and every assertion below would pass for the wrong reason.
if ! grep -q 'Dateless canary' "$scratch/TODO.archive.md"; then
  echo "FIXTURE-BROKEN: the dateless canary was not archived, so the prior_done branch"
  echo "never fired and the assertions below are vacuous. Script output was:"
  echo "$out"
  exit 1
fi

# (1) THE DEFECT: an entry dated TODAY must survive, even though it sits in the prior commit.
if grep -q 'Closed in THIS session' "$scratch/TODO.md"; then
  pass "(1) same-session entry dated today stayed in TODO.md"
else
  FAIL "(1) same-session entry dated today was archived out of TODO.md"
fi

# (1b) and it must not have been moved into the archive either.
if grep -q 'Closed in THIS session' "$scratch/TODO.archive.md"; then
  FAIL "(1b) same-session entry dated today was moved into TODO.archive.md"
else
  pass "(1b) same-session entry is absent from TODO.archive.md"
fi

# (1c) the routed: breadcrumb -- the concrete cross-repo harm -- is still greppable where
# scan-routed.sh and `append.sh inbox-done` actually look.
if grep -q 'routed:aaaa' "$scratch/TODO.md"; then
  pass "(1c) routed: breadcrumb still in TODO.md for the twin-guard"
else
  FAIL "(1c) routed: breadcrumb left TODO.md -- inbox-done will now refuse (exit 3)"
fi

# (2) NEGATIVE CONTROL / armed trap: a genuinely old entry still archives.
if grep -q 'Closed two months ago' "$scratch/TODO.archive.md"; then
  pass "(2) genuinely old entry still archives"
else
  FAIL "(2) genuinely old entry no longer archives -- the over-correction"
fi

if (( fails )); then
  echo "$fails assertion(s) failed"
  exit 1
fi
echo "PASS: same-session closes survive, old ones still archive (id:5355)"
