#!/usr/bin/env bash
# Defect-fix test, no roadmap item — reported 2026-09-09 from code.lawless while retiring
# annex worktrees, fixed the same session. Follow-up to id:8d76.
#
# fails-against-rev: c38f16aa -- relay/scripts/worktree-retire.sh
# (a STABLE sha, not HEAD~1 -- a moving rev is forbidden by id:0801 and the suite caught it)
# fails-against-assertion: two worktrees with IDENTICAL residue minted the SAME --ack token
#
# THE DEFECT: `--discard-residue --ack <token>` computed its digest over the residue BYTES
# only — porcelain status, tracked diff, untracked file contents — and NOT over the worktree
# identity. So two worktrees of the same repo holding byte-identical residue minted the SAME
# token, and a token obtained by inspecting ONE worktree silently authorised discarding
# ANOTHER whose residue the operator had never seen.
#
# WHY IT IS NOT AN EDGE CASE: on a git-annex repo it is the NORM. The cosmetic unlocked-pointer
# noise (id:3016) is the same paths in every worktree of the repo, so every worktree yields the
# same token. Observed live: `0aa7ea46f3ae` minted by BOTH ...-execute-c381-0 and
# ...-execute-c381-1. That instance was a near-miss — both residues genuinely were cosmetic and
# nothing was lost — which is exactly why it needs a test rather than a war story.
#
# The header's claim "the token is bound to this exact residue: if it changes, the token stops
# working" was true but incomplete: bound to the CONTENT, not the LOCATION.
#
# Hermetic: mktemp -d, git + coreutils, no network, never touches ~/.claude.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WTR="$ROOT/relay/scripts/worktree-retire.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git unavailable"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R" "$TMP/hooks"
git -C "$R" init -q .
git -C "$R" config user.email t@e
git -C "$R" config user.name t
git -C "$R" config core.hooksPath "$TMP/hooks"
echo base > "$R/f.txt"; git -C "$R" add f.txt; git -C "$R" commit -qm init

# Two worktrees of the SAME repo carrying BYTE-IDENTICAL residue — the annex shape.
for n in A B; do
  git -C "$R" worktree add -q "$TMP/wt$n" -b "relay/wt$n" HEAD 2>/dev/null
  echo IDENTICAL_RESIDUE > "$TMP/wt$n/stray.txt"
done

token_for() {
  # No `head -1` here: under `set -o pipefail` an early-exiting consumer SIGPIPEs its producer,
  # which is the id:81d5 shape the repo lints for (and which this test tripped on first write).
  # `awk NR==1` reads to EOF instead, so nothing is killed mid-pipe.
  "$WTR" "$R" "$TMP/wt$1" "relay/wt$1" --discard-residue --ack DELIBERATELY-WRONG 2>&1 \
    | grep -oE '\-\-ack [0-9a-f]{12}' | awk 'NR==1{print $2}'
}

tokA="$(token_for A)"
tokB="$(token_for B)"

if [ -z "$tokA" ] || [ -z "$tokB" ]; then
  bad "could not obtain a token from one or both worktrees (A='$tokA' B='$tokB') — fixture broken, assertions below are meaningless"
  echo "---- $pass ok, $fail failed ----"; exit 1
fi
ok "both worktrees mint a token (A=$tokA B=$tokB)"

# THE ASSERTION.
if [ "$tokA" = "$tokB" ]; then
  bad "two worktrees with IDENTICAL residue minted the SAME --ack token ($tokA) — a token from one authorises discarding the other"
else
  ok "identical residue in different worktrees mints DIFFERENT tokens — discard authority is worktree-bound"
fi

# The token must still be bound to the CONTENT too: changing the residue invalidates it.
echo CHANGED >> "$TMP/wtA/stray.txt"
tokA2="$(token_for A)"
if [ "$tokA2" = "$tokA" ]; then
  bad "changing wtA's residue did NOT change its token ($tokA) — content binding was lost"
else
  ok "changing the residue still invalidates the token — content binding preserved"
fi

echo "---- $pass ok, $fail failed ----"
[ "$fail" -eq 0 ] || exit 1
