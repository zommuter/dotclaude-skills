#!/usr/bin/env bash
# Defect-fix test (NO roadmap item -- id:ed35 lives only in TODO.md, so per CLAUDE.md §Testing
# this file omits a `# roadmap:` header and its failures always count).
#
# id:ed35 -- GATE 1 of `relay/scripts/auto-integrate-orphan.sh` bound the orphan to the FIRST
# `id:` token in its HEAD COMMIT MESSAGE. For a commit-and-park residue commit that token is the
# MECHANISM's own id, not the work item's. Observed live on
# `relay/orphan/relay-20260909-143257-21736-execute-b437-0`, whose HEAD subject is:
#
#   chore(relay): WIP UNVERIFIED residue auto-commit for worktree
#   relay-20260909-143257-21736-execute-b437-0 (id:f272 commit-and-park; do not treat as reviewed)
#
# so the unit bound to `f272` (the commit-and-park feature) instead of `b437` (the work).
#
# DIRECTION OF THE FAILURE, stated because the first draft of docs/ledger-notes/ed35.md got it
# backwards and a session summary repeated the error: this is FAIL-SAFE, not fail-open. GATE 1 has
# TWO checks -- no open box for the bound item, AND an `[x]` box for it. Measured on that orphan,
# `f272` has 0 open and 0 `[x]` boxes on the orphan's live ledgers, so the SECOND check refuses it
# as "not marked COMPLETE" and the orphan stays parked. The bug over-refuses; it never clears
# unreviewed work onto main. It is therefore a correctness-and-inertness defect (one more reason
# id:1048 almost never fires), NOT a security hole. Do not re-file it as the latter.
#
# The fix binds from the BRANCH NAME, which the dispatcher writes as structured data, and treats a
# residue auto-commit as deliberately UNBINDABLE rather than asking a cleanly-wrong question.
#
# fails-against: added in the same commit as the fix, so there is no ancestor tree to overlay. The
#   negative case BREAKS the branch-parse expression in the script (4 hex digits -> 5, so no real
#   branch name matches). That is the realistic regression shape -- someone edits the parse -- and
#   it fires assertion (g), which is the one that pins this file's copy of the expression to the
#   script's live one. A first attempt declared a multi-line python heredoc here; the runner
#   rejected it, correctly, because a heredoc split across comment lines contributes only its FIRST
#   line (id:b890). One complete command on one line, always.
# fails-against-mutation: sed -i 's#(\[0-9a-fA-F\]{4})-\[0-9\]+\$#([0-9a-fA-F]{5})-[0-9]+$#' relay/scripts/auto-integrate-orphan.sh
# fails-against-assertion: (g) this test's binding expression no longer matches the script's
#
# Hermetic: one scratch git repo under mktemp -d; never reads the real ledgers, never the network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/auto-integrate-orphan.sh"

fails=0
pass() { echo "PASS: $*"; }
note() { echo "FAIL: $*"; fails=$((fails+1)); }
die()  { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || die "auto-integrate-orphan.sh not executable at $SCRIPT"

# The binding expression under test, lifted out so this test exercises the real one rather than a
# paraphrase. It must stay in sync with the script; the mutation above proves it is the live one.
# No `| head`: the input is a single branch name, so sed emits at most one match -- and piping into
# an early-exiting consumer under pipefail is the id:81d5 shape the suite BLOCKS. The script's live
# line is written the same way for the same reason, which assertion (g) pins.
bind_from_branch() { sed -nE 's#.*-(execute|hard)-([0-9a-fA-F]{4})-[0-9]+$#\2#p' <<<"$1"; }

# --- (a) the live incident shape: branch names the work, commit names the mechanism -------------
branch='relay/orphan/relay-20260909-143257-21736-execute-b437-0'
got="$(bind_from_branch "$branch")"
if [[ "$got" == "b437" ]]; then
  pass "(a) residue-commit orphan binds to the WORK item b437 from its branch name"
else
  note "(a) residue auto-commit bound to the MECHANISM id instead of the work: branch '$branch' resolved to '${got:-<empty>}', want b437"
fi

# --- (b) the script must prefer the branch, so the prose token is not even consulted ------------
if grep -q 'id:ed35 -- bind from the BRANCH NAME' "$SCRIPT"; then
  pass "(b) the script binds from the branch name first"
else
  note "(b) the script has no branch-name binding -- it is still prose-first"
fi

# --- (c) a residue auto-commit must be UNBINDABLE, never bound to the mechanism's id ------------
if grep -q 'WIP UNVERIFIED residue auto-commit' "$SCRIPT" && grep -q 'UNBINDABLE' "$SCRIPT"; then
  pass "(c) a residue auto-commit HEAD is treated as UNBINDABLE, not bound to f272"
else
  note "(c) the script does not special-case a residue auto-commit HEAD, so an unnamed unit can still bind to the mechanism id"
fi

# --- (d) an unnamed unit yields nothing from the branch (falls through honestly) ----------------
got="$(bind_from_branch 'relay/orphan/relay-20260909-185356-12943-execute-repo-0')"
if [[ -z "$got" ]]; then
  pass "(d) an unnamed '-execute-repo-0' unit yields no branch binding"
else
  note "(d) an unnamed unit wrongly bound to '$got' from its branch name"
fi

# --- (e) a hard unit binds too, not only execute -----------------------------------------------
got="$(bind_from_branch 'relay/orphan/relay-20260831-120000-111-hard-9ab2-0')"
if [[ "$got" == "9ab2" ]]; then
  pass "(e) a hard-lane unit binds from its branch name"
else
  note "(e) hard-lane branch did not bind: got '${got:-<empty>}', want 9ab2"
fi

# --- (f) the fail-safe direction is DOCUMENTED in the script, so nobody re-files it as a hole ---
if grep -qi 'FAIL-SAFE' "$SCRIPT"; then
  pass "(f) the script records that the old bug over-refused rather than over-cleared"
else
  note "(f) the script does not record the failure DIRECTION; the next reader may re-file this as a security hole, which it is not"
fi

# --- (g) ANTI-PARAPHRASE: this file's bind_from_branch must be the script's LIVE expression ------
# Assertions (a), (d) and (e) run a COPY of the parse, so on their own they would keep passing
# after the script's real expression was changed or deleted -- a test of itself. This pins the copy
# to the original. Ordered LAST deliberately: the runner requires the declared
# `fails-against-assertion` to be the final FAIL line when a file accumulates several.
LIVE_EXPR='s#.*-(execute|hard)-([0-9a-fA-F]{4})-[0-9]+$#\2#p'
if grep -qF -- "$LIVE_EXPR" "$SCRIPT"; then
  pass "(g) the binding expression in this test is byte-identical to the script's live one"
else
  note "(g) this test's binding expression no longer matches the script's -- assertions (a)/(d)/(e) are now testing a paraphrase, not the real parse"
fi

if (( fails > 0 )); then
  echo "test_auto_integrate_binding_ed35: $fails assertion(s) failed"
  exit 1
fi
echo "ALL PASS: auto-integrate binds the orphan to its work item, not to the mechanism (id:ed35)"
