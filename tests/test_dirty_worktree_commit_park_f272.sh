#!/usr/bin/env bash
# roadmap:f272
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:f272 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY — id:4df8 shipped and works for what it specced, but not for the incident that
# motivated it. worktree-retire.sh's dirty branch is SURFACE-and-LEAVE (`:13-14`, `:120-127`,
# exit 3). Its RED spec's fixture (c) (tests/test_context_death_parks_worktree_4df8.sh:68-77)
# only asserts a dirty tree is not silently DESTROYED, so the implementation correctly meets
# its spec — but the original ask in routed:3f22 was "if the worktree has commits OR A DIRTY
# TREE, commit-or-park it". Live evidence the gap is real: run relay-20260729-111723-7520's
# execute child died with 0 commits and a dirty tree carrying 47 lines (the id:4df8
# implementation itself); it survived only because a human noticed and hand-committed it as
# 46b260e. Under the shipped fix that same incident still ends at "surfaced and left".
#
# FORCE-FREE IS PRESERVED, and that is the point: committing residue onto its OWN relay-owned
# branch destroys nothing, unlike stash/clean/reset, which id:373e rightly bans. The ban is on
# DISCARDING; this is the opposite. Section (e) asserts the discipline explicitly so a later
# reader cannot mistake this for a relaxation of id:373e.
#
# CONTRACT (opt-in, so nothing existing changes meaning):
#   (a) dirty + relay-owned branch + --commit-residue  -> residue COMMITTED to that branch,
#       worktree removed, branch parked as relay/orphan/<bn>, exit 0, and the surfaced line
#       NAMES the ref (not the run-id-scoped worktree path — the id:4df8 §(d) finding).
#   (b) dirty + relay-owned + NO flag                  -> today's behaviour, byte for byte.
#   (c) dirty + NON-relay branch + flag                -> surfaced-and-left, exit 3, NO commit.
#   (d) the commit message is LOUD: contains WIP and UNVERIFIED.
#   (e) nothing is stashed/cleaned/reset; the residue's ORIGINAL CONTENT is in the ref's tip.
#   (f) the committed-work and clean-commitless outcomes are unchanged.
#   (g) relay-loop.js's null-report (context-death) path passes the flag.
#
# TRIANGULATION: (a) vs (b) forces the flag to be a real opt-in rather than a behaviour swap;
# (a) vs (c) forces the relay-owned-branch guard; (e) forces the content to survive rather
# than a plausible-looking empty commit.
#
# Hermetic: real git repos under mktemp -d; WORKTREE_RETIRE_LOG redirected; no network, no
# ~/.claude writes.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RETIRE="$ROOT/relay/scripts/worktree-retire.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -x "$RETIRE" ]] || { echo "FAIL: worktree-retire.sh missing at $RETIRE" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export WORKTREE_RETIRE_LOG="$tmp/retire.log"

RESIDUE_TEXT='the 47 lines a human had to rescue by hand'

mk_repo() {
  local r="$1"; git init -q "$r"
  git -C "$r" config user.email t@e; git -C "$r" config user.name t
  echo base > "$r/f.txt"; git -C "$r" add -A; git -C "$r" commit -qm base
}
# mk_dirty_wt <repo> <wt> <branch> — a worktree with ZERO commits of its own and a dirty tree
# (both a tracked modification and an untracked file — the real context-death shape).
mk_dirty_wt() {
  local r="$1" w="$2" b="$3"
  mkdir -p "$(dirname "$w")"
  git -C "$r" worktree add -q "$w" -b "$b" >/dev/null 2>&1
  echo modified > "$w/f.txt"
  printf '%s\n' "$RESIDUE_TEXT" > "$w/residue.txt"
}

# ── (a)+(d)+(e) dirty + relay-owned + --commit-residue ⇒ committed, parked, named ─────
repo="$tmp/r1"; mk_repo "$repo"
wt="$tmp/wt1/relay-20260729-111723-7520-execute"
mk_dirty_wt "$repo" "$wt" "relay/run1-execute"

set +e
out="$("$RETIRE" "$repo" "$wt" "relay/run1-execute" --commit-residue 2>&1)"
rc=$?
set -e

if (( rc != 0 )); then
  note "(a) --commit-residue on a dirty relay-owned worktree must retire cleanly (exit 0), got $rc: ${out//$'\n'/ }"
fi
ref="refs/heads/relay/orphan/relay-20260729-111723-7520-execute"
if ! git -C "$repo" show-ref --verify --quiet "$ref"; then
  note "(a) no reachable orphan ref was produced — the residue is still recoverable only by a human noticing the directory, which is exactly the incident (run relay-20260729-111723-7520, rescued by hand as 46b260e)"
else
  # (e) the ORIGINAL content must be in the ref's tip — not an empty or placeholder commit.
  got="$(git -C "$repo" show "${ref}:residue.txt" 2>/dev/null || true)"
  [[ "$got" == "$RESIDUE_TEXT" ]] \
    || note "(e) the parked ref's tip does not contain the untracked residue verbatim (got: '${got:0:60}') — a commit that does not carry the work is worse than none, because it looks like a rescue"
  tracked="$(git -C "$repo" show "${ref}:f.txt" 2>/dev/null || true)"
  [[ "$tracked" == "modified" ]] \
    || note "(e) the parked ref's tip lost the TRACKED modification (got: '${tracked:0:60}')"
  # (d) the commit message must be loud about what this is.
  msg="$(git -C "$repo" log -1 --format=%B "$ref" 2>/dev/null || true)"
  grep -q 'WIP' <<<"$msg"        || note "(d) the residue commit message must contain 'WIP' — it is unreviewed work, and the message is the only thing that says so; got: ${msg//$'\n'/ }"
  grep -q 'UNVERIFIED' <<<"$msg" || note "(d) the residue commit message must contain 'UNVERIFIED'; got: ${msg//$'\n'/ }"
fi
# (a) the surfaced line must name the REF, not the run-id-scoped worktree path.
grep -q 'relay/orphan/relay-20260729-111723-7520-execute' <<<"$out" \
  || note "(a) the surfaced line does not name the resulting ref — a message pointing at the run-id-scoped worktree path is actively misleading once the run ends (the id:4df8 §(d) finding); got: ${out//$'\n'/ }"
[[ ! -d "$wt" ]] \
  || note "(a) the worktree directory is still on disk after a successful commit-and-park — once the residue is safely on a ref there is nothing left to preserve"
# (e) force-free: no stash may have been created.
[[ -z "$(git -C "$repo" stash list 2>/dev/null)" ]] \
  || note "(e) a stash entry was created — id:373e bans stash/clean/reset; committing to the branch is the force-free route and the only permitted one"

# ── (b) NO flag ⇒ today's behaviour, unchanged ────────────────────────────────────────
repo2="$tmp/r2"; mk_repo "$repo2"
wt2="$tmp/wt2/run2-execute"
mk_dirty_wt "$repo2" "$wt2" "relay/run2-execute"
set +e
out2="$("$RETIRE" "$repo2" "$wt2" "relay/run2-execute" 2>&1)"
rc2=$?
set -e
(( rc2 == 3 )) \
  || note "(b) WITHOUT --commit-residue a dirty worktree must still be surfaced-and-left with exit 3 (got $rc2) — the new behaviour is OPT-IN so no existing caller or test changes meaning"
[[ -d "$wt2" ]] \
  || note "(b) WITHOUT the flag the dirty worktree must be LEFT on disk"
git -C "$repo2" show-ref --verify --quiet "refs/heads/relay/orphan/run2-execute" \
  && note "(b) WITHOUT the flag nothing may be committed or parked"

# ── (c) a NON-relay-owned branch is never committed to, even with the flag ────────────
repo3="$tmp/r3"; mk_repo "$repo3"
wt3="$tmp/wt3/feature-x"
mk_dirty_wt "$repo3" "$wt3" "feature/x"
set +e
out3="$("$RETIRE" "$repo3" "$wt3" "feature/x" --commit-residue 2>&1)"
rc3=$?
set -e
(( rc3 == 3 )) \
  || note "(c) a dirty worktree on a NON-relay-owned branch must stay surfaced-and-left (exit 3, got $rc3) even with --commit-residue — the helper never commits to a branch it does not own"
[[ "$(git -C "$repo3" rev-list --count feature/x 2>/dev/null || echo 0)" == "1" ]] \
  || note "(c) a commit was made on the non-relay branch 'feature/x' — that branch may be a human's work in progress"

# ── (f) the two already-working outcomes are unchanged ────────────────────────────────
repo4="$tmp/r4"; mk_repo "$repo4"
wt4="$tmp/wt4/run4-execute"; mkdir -p "$tmp/wt4"
git -C "$repo4" worktree add -q "$wt4" -b "relay/run4-execute" >/dev/null 2>&1
echo work > "$wt4/f.txt"; git -C "$wt4" add -A; git -C "$wt4" commit -qm "completed work"
"$RETIRE" "$repo4" "$wt4" "relay/run4-execute" --commit-residue >/dev/null 2>&1 || true
git -C "$repo4" show-ref --verify --quiet "refs/heads/relay/orphan/run4-execute" \
  || note "(f) a CLEAN worktree with commits must still park as relay/orphan/* (id:4df8 fixture (a) regression)"

repo5="$tmp/r5"; mk_repo "$repo5"
wt5="$tmp/wt5/run5-execute"; mkdir -p "$tmp/wt5"
git -C "$repo5" worktree add -q "$wt5" -b "relay/run5-execute" >/dev/null 2>&1
"$RETIRE" "$repo5" "$wt5" "relay/run5-execute" --commit-residue --expect-merged >/dev/null 2>&1 || true
git -C "$repo5" show-ref --verify --quiet "refs/heads/relay/orphan/run5-execute" \
  && note "(f) a CLEAN, commitless worktree must still be reaped, not parked (id:4df8 fixture (b) regression)"

# ── (e2) no discarding op OUTSIDE the gated discard branch ────────────────────────────
# NARROWED 2026-08-26 (roadmap:8d76, owner ruling). This used to ban every discarding verb
# anywhere in the file, which was right while the script had NO discard path. It now has
# exactly one — `--discard-residue --ack <token>` — because id:221f(a) moves
# `git * --force*` to `deny`, removing the raw command a human previously used, so the
# capability had to survive in an audited form inside this allowlisted script.
#
# f272's OWN invariant is unchanged and is what this still enforces: the COMMIT-and-park
# path must never discard — committing is the force-free alternative, and that is the whole
# point of the item. So we strip the guarded discard block and assert the REST is clean.
# `git stash`, `git clean` and `reset --hard` stay banned EVERYWHERE, including inside the
# discard block: they are unrecoverable, whereas the discard path archives first.
rest="$(awk '/^if \[\[ "\$discard_residue" -eq 1 \]\]; then/{skip=1} skip && /^fi$/{skip=0; next} !skip' "$RETIRE")"
if grep -nE 'checkout -- |git restore' <<<"$rest" >/dev/null; then
  note "(e2) a DISCARDING git op appears OUTSIDE the gated --discard-residue block — id:373e bans stash/clean/reset/checkout-- on the commit-and-park path; committing is the force-free alternative"
fi
if grep -nE 'git (stash|clean|reset --hard)' "$RETIRE" >/dev/null; then
  note "(e2b) worktree-retire.sh contains an UNRECOVERABLE discarding op (stash/clean/reset --hard) — banned everywhere, including inside the gated discard block, which archives before it destroys"
fi

# ── (g) the null-report (context-death) caller must pass the flag ─────────────────────
if [[ -f "$LOOP" ]]; then
  block="$(awk '/if \(!report\) \{/{d=0;f=1} f{print; d+=gsub(/\{/,"{"); d-=gsub(/\}/,"}"); if(d<=0 && NR>1 && f) exit}' "$LOOP")"
  if [[ -n "$block" ]]; then
    grep -q 'commit-residue' <<<"$block" \
      || note "(g) relay-loop.js's null-report (context-death) branch does not pass --commit-residue — the helper gaining the ability changes nothing if the one caller that hits this case never asks for it ([[relay-builtgreen-but-unreferenced]])"
  else
    note "(g) could not locate the null-report branch in relay-loop.js to check the caller wiring"
  fi
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:f272 not built yet" >&2; exit 1; }
echo "ALL PASS: a dirty relay-owned worktree is committed and parked, force-free (id:f272)"
