#!/usr/bin/env bash
# roadmap:4df8
#
# RED SPEC — authored 2026-07-28 (handoff C3), NOT implemented. EXPECTED-RED while id:4df8 is
# unticked.
#
# WHY — this one nearly cost real work. The `report == null` terminal-error path in relay-loop.js
# pushes a handback naming `worktreePathFor(unit)` but NEVER parks the branch. That path is
# RUN-ID-SCOPED (~/.cache/relay/worktrees/<repo>/<runId>-<verdict>), so a relaunch mints a new
# runId and never looks there, and `/relay reconcile` TRUTHFULLY reports "no parked orphans"
# because no `relay/orphan/*` ref was ever created. The work is not lost-and-flagged — it is
# invisible, and the next `git worktree prune` takes it. loderite's id:2435 output survived only
# because a human inspected a stale worktree before relaunching.
#
# WHY IT IS CHEAP — the asymmetry is the point: D1's orphan-park machinery ALREADY EXISTS and
# already fires for killed runs, and `contract_met=false` genuinely has nothing to save (the
# contract mandates a clean worktree on size-out, id:8b1f). It is SPECIFICALLY the terminal-error
# path that skips parking. Reuse the existing path (worktree-retire.sh → unmerged branch renamed
# to relay/orphan/<bn>) rather than writing new disposal logic.
#
# Pairs with id:61fa: that one makes the death VISIBLE; this one makes its WORK RECOVERABLE.
# Neither subsumes the other.
#
# Hermetic: real git repos under mktemp -d; no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RETIRE="$ROOT/relay/scripts/worktree-retire.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -x "$RETIRE" ]] || { note "worktree-retire.sh missing"; exit 1; }

# ── (0) STRUCTURAL: the null-report branch must invoke the park path at all. ──────
# Extract by brace depth, NOT by a fixed-indent `return` terminator — the id:98ea finding showed
# `^  return$` matches ZERO lines in relay-loop.js, so that style of extractor silently reads to
# EOF and asserts on unrelated text.
block="$(awk '/if \(!report\) \{/{d=0;f=1} f{print; d+=gsub(/\{/,"{"); d-=gsub(/\}/,"}"); if(d<=0 && NR>1 && f) exit}' "$LOOP")"
[[ -n "$block" ]] || note "(0) could not locate the null-report branch in relay-loop.js"
grep -qE 'worktree-retire|parkWorktree|relay/orphan' <<<"$block" \
  || note "(0) the null-report (context-death) branch never parks the worktree — its committed work becomes unreachable next run (run-id-scoped path + no orphan ref)"

# ── (a) a worktree WITH COMMITS must end up parked as a reachable orphan ref ──────
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mk_repo() {
  local r="$1"; git init -q "$r"; git -C "$r" config user.email t@e; git -C "$r" config user.name t
  echo base > "$r/f.txt"; git -C "$r" add -A; git -C "$r" commit -qm base
}
repo="$tmp/repo"; mk_repo "$repo"
wt="$tmp/wt/run1-execute"; mkdir -p "$tmp/wt"
git -C "$repo" worktree add -q "$wt" -b "relay/run1-execute" >/dev/null 2>&1
echo work > "$wt/f.txt"; git -C "$wt" add -A; git -C "$wt" commit -qm "completed work that must survive"

"$RETIRE" "$repo" "$wt" "relay/run1-execute" >/dev/null 2>&1 || true
git -C "$repo" show-ref --verify --quiet "refs/heads/relay/orphan/run1-execute" \
  || note "(a) a context-death worktree WITH COMMITS was not parked to relay/orphan/* — this is the stranding bug; the commit is now reachable only via a run-id-scoped path no relaunch will look at"

# ── (b) a CLEAN, commitless worktree must be reaped, not litter an orphan ref ─────
repo2="$tmp/repo2"; mk_repo "$repo2"
wt2="$tmp/wt2/run2-execute"; mkdir -p "$tmp/wt2"
git -C "$repo2" worktree add -q "$wt2" -b "relay/run2-execute" >/dev/null 2>&1
"$RETIRE" "$repo2" "$wt2" "relay/run2-execute" --expect-merged >/dev/null 2>&1 || true
git -C "$repo2" show-ref --verify --quiet "refs/heads/relay/orphan/run2-execute" \
  && note "(b) a clean commitless worktree was parked as an orphan — do not litter; reap it"

# ── (c) a DIRTY worktree must be surfaced+left, never force-cleaned (id:373e) ─────
repo3="$tmp/repo3"; mk_repo "$repo3"
wt3="$tmp/wt3/run3-execute"; mkdir -p "$tmp/wt3"
git -C "$repo3" worktree add -q "$wt3" -b "relay/run3-execute" >/dev/null 2>&1
echo committed > "$wt3/f.txt"; git -C "$wt3" add -A; git -C "$wt3" commit -qm keep
echo residue > "$wt3/dirty.txt"
"$RETIRE" "$repo3" "$wt3" "relay/run3-execute" >/dev/null 2>&1 || true
if [[ ! -d "$wt3" ]] && ! git -C "$repo3" show-ref --verify --quiet "refs/heads/relay/orphan/run3-execute"; then
  note "(c) a DIRTY worktree was removed without parking its branch — force-free discipline (id:373e) requires surface-and-leave or park, never silent destruction"
fi

# ── (d) the operator-facing reason must name the ORPHAN REF, not the dead path ────
grep -qE 'worktreePathFor\(unit\)' <<<"$block" && ! grep -q 'relay/orphan' <<<"$block" \
  && note "(d) the handback reason names a run-id-scoped worktree path but no orphan ref — actively misleading once the run ends, since nothing will ever look there"

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:4df8 not built yet" >&2; exit 1; }
echo "ALL PASS: context-death worktrees are parked and recoverable (id:4df8)"
