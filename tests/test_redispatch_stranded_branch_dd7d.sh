#!/usr/bin/env bash
# roadmap:dd7d — re-dispatch of an item with a committed stranded branch must REFUSE and
# surface, and integrate must compare against any sibling branch for the same item.
#
# RED SPEC authored 2026-08-18, owner-ratified disposition (b)+(c). Option (a) — hand the
# child the stranded branch — is explicitly NOT adopted; it re-opens the uncommitted-state
# hazard id:9834 closed. Nothing here should drive an executor toward reusing a worktree.
#
# THE DEFECT (lodelore run relay-20260818-110858-18948, id:15d2): a dirty-tree handback
# (id:aa93) in round 4 was followed by a plain re-dispatch of the same still-open item in
# round 5. The second child started from origin/main, blind to the first child's COMMITTED
# branch, and reached a contradictory answer (3/6/12 in-game days vs 6.337/12.675/25.350 —
# a factor 2.11, i.e. two different planet masses at identical semi-major axes). It surfaced
# only as an add/add git conflict during a manual integrate.
#
# PREMISE CORRECTION, recorded because the FIRST inbound report (routed:d99c) got it wrong
# and an executor would otherwise build the wrong guard: the two children were SEQUENTIAL,
# not concurrent (relay-events.jsonl: round-4 dispatch 09:27:48Z, handback same round,
# round-5 dispatch 09:32:35Z). d99c asked for "at-most-one live child per item id per run";
# that guard would NOT have prevented this and is NOT what this item builds.
#
# NAMING CONTRACT, verified against the code 2026-08-18 — do not re-derive:
#   relay-loop.js:2219   unitKey   = ${verdict}-${itemId || 'repo'}-${attempt}
#   relay-loop.js:2228   branchFor = relay/${runId}-${unitKey}
#   worktree-retire.sh:80-81       parks as relay/orphan/$(basename <worktree-dir>)
# so the item id is in a parseable position in BOTH namespaces, and the scan must be
# runId-AGNOSTIC (branchFor is runId-prefixed; a same-run glob misses earlier runs).
#
# This test is deliberately BEHAVIOURAL, not source-grep shape (the id:3a50 defect class):
# it builds real git fixtures and EXECUTES the scanner. The two grep assertions at the end
# are wiring tripwires beside that real coverage — a built-but-unreferenced script is the
# id:5367/id:2062 failure mode and must not read as done.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$SRC_DIR/relay/scripts/stranded-branch-scan.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$SCAN" ]] || fail "relay/scripts/stranded-branch-scan.sh does not exist or is not executable (THE DEFECT — nothing can see a stranded branch at re-dispatch)"

# ── fixture: a repo whose item dd7d has branches of every shape the scan must classify ────
repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name "Test"
echo base > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "base"

# (1) a live-namespace stranded branch from an OLD run, 1 commit beyond main
git -C "$repo" checkout -q -b relay/relay-OLDRUN-execute-dd7d-0
echo stranded > "$repo/stranded.txt"
git -C "$repo" add stranded.txt
git -C "$repo" commit -q -m "the stranded result"

# (2) a PARKED orphan of the same shape, 1 commit beyond main
git -C "$repo" checkout -q main
git -C "$repo" checkout -q -b relay/orphan/relay-OTHERRUN-execute-dd7d-1
echo parked > "$repo/parked.txt"
git -C "$repo" add parked.txt
git -C "$repo" commit -q -m "the parked result"

# (3) a ZERO-commit branch for the same item — what a LIVE parallel child looks like (id:6e02)
git -C "$repo" checkout -q main
git -C "$repo" checkout -q -b relay/relay-NEWRUN-execute-dd7d-2

# (4) a repo-scoped branch with a commit — must NOT be item-matched (itemId falls back to 'repo')
git -C "$repo" checkout -q main
git -C "$repo" checkout -q -b relay/relay-OLDRUN-review-repo-0
echo reposcoped > "$repo/repo.txt"
git -C "$repo" add repo.txt
git -C "$repo" commit -q -m "repo-scoped work"

git -C "$repo" checkout -q main

run_scan() { "$SCAN" "$repo" --verdict "$1" --item "$2" --base main 2>"$tmpdir/err"; }

# ── (A) finds a committed stranded branch in the LIVE namespace, exit 0 ───────────────────
out="$(run_scan execute dd7d || fail "scan exited non-zero on a normal repo (it is observe-only; reserve non-zero for usage/repo errors): $(cat "$tmpdir/err")")"
grep -q 'relay/relay-OLDRUN-execute-dd7d-0' <<<"$out" \
  || { echo "  scan output was:"; sed 's/^/    /' <<<"$out"; fail "scan did not report the committed stranded branch — re-dispatch stays blind (THE DEFECT)"; }
pass "a committed stranded branch in the live namespace is reported"

# ── (B) finds the PARKED orphan too — both namespaces ─────────────────────────────────────
grep -q 'relay/orphan/relay-OTHERRUN-execute-dd7d-1' <<<"$out" \
  || { echo "  scan output was:"; sed 's/^/    /' <<<"$out"; fail "scan missed the relay/orphan/* namespace — a parked branch is the commonest stranded shape"; }
pass "a parked relay/orphan/* branch for the same item is reported"

# ── (C) run-id-AGNOSTIC: both hits came from runIds unrelated to each other ───────────────
# (A) matched OLDRUN and (B) matched OTHERRUN; a runId-scoped glob could not have found both.
pass "the scan is run-id-agnostic (matched two distinct runIds)"

# ── (D) a ZERO-commit branch is NOT reported (trap iii, id:6e02) ──────────────────────────
if grep -q 'relay/relay-NEWRUN-execute-dd7d-2' <<<"$out"; then
  echo "  scan output was:"; sed 's/^/    /' <<<"$out"
  fail "scan reported a ZERO-commit branch — that is what a LIVE parallel child's fresh worktree looks like (id:6e02); refusing dispatch on it would deadlock the pool against itself"
fi
pass "a zero-commit branch is not reported"

# ── (E) a repo-scoped branch is NOT item-matched (trap i) ─────────────────────────────────
if grep -q 'review-repo-0' <<<"$out"; then
  echo "  scan output was:"; sed 's/^/    /' <<<"$out"
  fail "scan item-matched a repo-scoped branch — itemId falls back to the literal string 'repo', so '…-review-repo-0' must never match --item dd7d"
fi
pass "a repo-scoped branch is not falsely item-matched"

# ── (F) an item with no stranded branch prints nothing, still exit 0 ──────────────────────
out_none="$(run_scan execute ffff || fail "scan exited non-zero when it found nothing; empty output is the no-op signal: $(cat "$tmpdir/err")")"
[[ -z "${out_none//[[:space:]]/}" ]] \
  || { echo "  scan output was:"; sed 's/^/    /' <<<"$out_none"; fail "scan printed output for an item that has no branches — a false positive here refuses a legitimate dispatch"; }
pass "an item with no stranded branch yields empty output and exit 0"

# ── (G) observe-only: the scan must not have mutated the repo ─────────────────────────────
[[ -z "$(git -C "$repo" status --porcelain)" ]] || fail "scan left the repo dirty — it must be observe-only (never checkout/merge/delete)"
branches_after="$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads | sort)"
[[ "$(wc -l <<<"$branches_after")" -eq 5 ]] \
  || { echo "  branches now:"; sed 's/^/    /' <<<"$branches_after"; fail "scan added or removed branches — it must be observe-only"; }
pass "the scan is observe-only (repo clean, branch set unchanged)"

# ── (H) WIRING — built+green is not wired (id:5367/id:2062 failure mode) ──────────────────
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"
# KNOWN + INTENTIONAL source-grep hit (lint-source-grep-assertions.py reports this file
# SHAPE-ONLY on $JS). It is the legitimate case that lint's own docstring carves out: the
# contract here genuinely IS "relay-loop.js must reference this script". relay-loop.js is a
# Workflow script that cannot be executed from a hermetic test, and the BEHAVIOURAL half is
# already covered above by really running $SCAN against real git fixtures. Do NOT delete this
# assertion to silence the lint — without it, a scanner that is built, tested and green but
# wired to nothing would read as done (the id:5367/id:2062 failure mode).
refs="$(grep -c 'stranded-branch-scan' "$JS" || true)"
[[ "$refs" -ge 2 ]] \
  || fail "relay-loop.js references stranded-branch-scan.sh $refs time(s); it must be wired at BOTH the pre-dispatch (b) and integrate (c) sites — a built-but-unreferenced script does not close this item"
pass "relay-loop.js references the scanner at 2+ sites (pre-dispatch + integrate)"

echo "ALL PASS: re-dispatch sees a stranded branch and integrate compares siblings (dd7d)"
