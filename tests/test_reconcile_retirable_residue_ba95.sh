#!/usr/bin/env bash
# roadmap:ba95
#
# id:ba95 — RETIRABLE RESIDUE: a relay worktree whose branch is fully MERGED into trunk, and a
# leftover directory under the relay worktree cache that no worktree registration mentions.
#
# WHY THIS IS A SEPARATE CLASS FROM `stranded` (id:2b4b), and why folding them would be wrong:
# `list_stranded` deliberately reports only a branch "which carries commits the trunk does not
# have" (relay-reconcile.sh, the `rev-list --count "$trunk..$br" -eq 0 → continue` guard). That
# is correct — it exists to surface work that could be LOST, its recommended disposition is the
# destructive `--discard`, and a merged branch has nothing to lose. So a MERGED-but-registered
# worktree is invisible to it BY DESIGN, not by oversight.
#
# The cost is not lost work — it is that such residue looks exactly like hidden work until
# somebody spends an investigation proving it is not. That happened on 2026-09-08 with
# `relay/relay-20260907-100619-27900-execute-4839-0`: a clean, fully-merged worktree that no
# sweep mentioned, which read as a missed orphan.
#
# So the two groups must stay DISTINGUISHABLE in the output: a stranded branch needs a human
# decision and cannot be fed to `--integrate` (which prefixes relay/orphan/), whereas retirable
# residue has one mechanical disposition — `worktree-retire.sh --expect-merged`.
#
# Hermetic: mktemp -d for everything, RELAY_TOML/SRC_DIR overridden, no network, never touches
# ~/.config/relay, ~/.claude, or any real repo.
#
# fails-against-rev: 13445619dbfefe8b3d286b7a9f846a649b2f9ab7 -- relay/scripts/relay-reconcile.sh
# fails-against-assertion: (a) a merged-branch relay worktree is not reported as retirable residue

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILE="$ROOT/relay/scripts/relay-reconcile.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$RECONCILE" ]] || fail "relay-reconcile.sh missing/not executable: $RECONCILE"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
git_q() { git "$@" >/dev/null 2>&1; }

# --- fixture repo with a real trunk -------------------------------------------------------
R="$T/alpha"
git_q init -b main "$R"
git_q -C "$R" config user.email fixture@example.invalid
git_q -C "$R" config user.name fixture
echo base > "$R/f"; git_q -C "$R" add -A; git_q -C "$R" commit -m base

# A relay branch whose commit IS on trunk (merged) — the retirable case.
git_q -C "$R" branch relay/relay-20260101-000000-1-execute-repo-0
CACHE="$T/cache/worktrees/alpha"
mkdir -p "$CACHE"
git_q -C "$R" worktree add "$CACHE/relay-20260101-000000-1-execute-repo-0" \
  relay/relay-20260101-000000-1-execute-repo-0

# A leftover DIRECTORY that no worktree registration mentions.
mkdir -p "$CACHE/relay-19700101-000000-9-execute-repo-0"
echo stale > "$CACHE/relay-19700101-000000-9-execute-repo-0/residue"

# relay.toml naming just this repo
cat > "$T/relay.toml" <<TOML
[repos.alpha]
classification = "own"
confirmed = "2026-01-01"
# path: $R
TOML

export RELAY_TOML="$T/relay.toml" SRC_DIR="$T"
export RELAY_WORKTREE_CACHE="$T/cache/worktrees"

out="$("$RECONCILE" --all 2>&1)"

# (a) the merged-branch worktree is reported as retirable residue
grep -qi 'retirable' <<< "$out" \
  && pass "(a) the sweep has a retirable-residue group" \
  || fail "(a) a merged-branch relay worktree is not reported as retirable residue"$'\n'"$out"

grep -q 'relay-20260101-000000-1-execute-repo-0' <<< "$out" \
  && pass "(b) the merged-branch worktree is named" \
  || fail "(b) the merged-branch worktree was not named in the output:"$'\n'"$out"

# (c) it must NOT be filed as stranded — that group means unmerged work needing a decision
if grep -qi 'stranded' <<< "$out"; then
  stranded_block="$(sed -n '/STRANDED/,$p' <<< "$out")"
  grep -q 'relay-20260101-000000-1-execute-repo-0' <<< "$stranded_block" \
    && fail "(c) a MERGED worktree was filed under STRANDED — that group means unmerged work whose disposition is the destructive --discard" \
    || pass "(c) the merged worktree is not filed under STRANDED"
else
  pass "(c) no STRANDED group emitted for a merged-only fixture"
fi

# (d) the leftover directory with no registration is reported too
grep -q 'relay-19700101-000000-9-execute-repo-0' <<< "$out" \
  && pass "(d) the unregistered leftover cache directory is reported" \
  || fail "(d) a leftover cache directory that no worktree registration mentions was not reported:"$'\n'"$out"

# (e) the disposition is named, so the reader is not left to guess the retire path
grep -q 'worktree-retire.sh' <<< "$out" \
  && pass "(e) the output names worktree-retire.sh as the disposition" \
  || fail "(e) the retirable group does not name worktree-retire.sh:"$'\n'"$out"

echo "OK: tests/test_reconcile_retirable_residue_ba95.sh"
