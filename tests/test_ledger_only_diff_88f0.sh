#!/usr/bin/env bash
# roadmap:88f0 — ONE shared ledger-only-diff predicate (relay/scripts/lib-ledger-only-diff.sh),
# wired into the pre-integrate isolation gate (verify-isolation.sh, id:f682).
#
# Trigger (observed live 2026-07-28, run relay-20260728-105959-1379): the isolation gate
# false-positived on a repo whose main advanced ONLY via id:c144-sanctioned ledger-only
# commits (a ROADMAP promotion + two inbox-ingest stubs) — id:c144 explicitly exempts
# ledger-only writes from the relay lease (the documented /relay human / /meeting
# write-back path, id:15d5/2147), but the isolation gate's heuristic ("empty worktree +
# main advanced by a non-merge commit ⇒ suspected breach") cannot tell that class apart
# from a genuine breach. Fix: classify the advancing commits; a ledger-only range is
# NOT a breach, anything else still defers exactly as before.
#
# Fixtures (per the ROADMAP item's RED spec):
#   1. a commit range touching only ROADMAP.md          → ledger-only TRUE
#   2. a range touching ROADMAP.md AND a .sh file        → FALSE
#   3. an empty range                                    → FALSE (never vacuously true)
#   4. a merge commit                                    → unchanged from today (isolation
#      gate's existing (b3) "merge-only" branch already returns ok; untouched by this fix)
#   5. integration: the isolation gate PASSES on the ledger-only case and still DEFERS
#      (exit 2) on the mixed case.
#
# Hermetic: mktemp only, no ~/.claude, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-ledger-only-diff.sh"
GATE="$ROOT/relay/scripts/verify-isolation.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -f "$LIB" ]] || fail "lib-ledger-only-diff.sh not found at $LIB"
[[ -x "$GATE" ]] || fail "verify-isolation.sh not found/executable at $GATE"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=/dev/null
source "$LIB"

REPO="$tmp/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'roadmap seed\n' > "$REPO/ROADMAP.md"
printf 'code seed\n' > "$REPO/lib.sh"
git -C "$REPO" add ROADMAP.md lib.sh
git -C "$REPO" commit -qm seed
base_sha="$(git -C "$REPO" rev-parse HEAD)"

# ── 1. ledger-only range → TRUE ──
printf 'roadmap seed\nticked\n' > "$REPO/ROADMAP.md"
git -C "$REPO" commit -qam 'roadmap: tick item'
ledger_sha="$(git -C "$REPO" rev-parse HEAD)"
if ledger_only_diff "$REPO" "$base_sha..$ledger_sha"; then
    pass "(1) ROADMAP.md-only range → ledger_only_diff TRUE"
else
    fail "(1) ROADMAP.md-only range should be TRUE"
fi

# ── 2. mixed range (ROADMAP.md + a .sh file) → FALSE ──
printf 'code seed\nchanged\n' > "$REPO/lib.sh"
git -C "$REPO" commit -qam 'code: change lib.sh'
mixed_sha="$(git -C "$REPO" rev-parse HEAD)"
if ledger_only_diff "$REPO" "$base_sha..$mixed_sha"; then
    fail "(2) mixed ROADMAP.md+lib.sh range should be FALSE"
else
    pass "(2) mixed range → ledger_only_diff FALSE"
fi

# ── 3. empty range → FALSE (never vacuously true) ──
if ledger_only_diff "$REPO" "$ledger_sha..$ledger_sha"; then
    fail "(3) empty range should be FALSE, not vacuously TRUE"
else
    pass "(3) empty range → ledger_only_diff FALSE"
fi

# ── 4. merge-only case: isolation gate unaffected, still ok/exit 0 (pre-existing (b3)) ──
BREPO="$tmp/brepo"
mkdir -p "$BREPO"
git -C "$BREPO" init -q -b main
git -C "$BREPO" config user.email t@example.com
git -C "$BREPO" config user.name tester
printf 'seed\n' > "$BREPO/file.txt"
git -C "$BREPO" add file.txt
git -C "$BREPO" commit -qm seed
git -C "$BREPO" branch feature
WT4="$tmp/brepo-wt4"
git -C "$BREPO" worktree add -q -b child4 "$WT4" main
git -C "$BREPO" checkout -q feature
printf 'feature work\n' > "$BREPO/feature.txt"
git -C "$BREPO" add feature.txt
git -C "$BREPO" commit -qm 'feature work'
git -C "$BREPO" checkout -q main
git -C "$BREPO" merge -q --no-ff feature -m 'merge feature'
if out="$("$GATE" "$WT4" --base main 2>&1)"; then
    pass "(4) merge-only main advance (pre-existing b3) → gate still exits 0 ($out)"
else
    fail "(4) merge-only main advance should still exit 0, got: $out"
fi

# ── 5a. integration: isolation gate PASSES on a ledger-only main advance ──
make_repo_and_worktree_ledger() {
    local name="$1"
    REPO5="$tmp/$name"
    WT5="$tmp/$name-wt"
    mkdir -p "$REPO5"
    git -C "$REPO5" init -q -b main
    git -C "$REPO5" config user.email t@example.com
    git -C "$REPO5" config user.name tester
    printf 'seed\n' > "$REPO5/ROADMAP.md"
    git -C "$REPO5" add ROADMAP.md
    git -C "$REPO5" commit -qm seed
    git -C "$REPO5" worktree add -q -b "$name-child" "$WT5" main
}
make_repo_and_worktree_ledger r5a
printf 'seed\nticked\n' > "$REPO5/ROADMAP.md"
git -C "$REPO5" commit -qam 'roadmap: sanctioned ledger-only advance'
if out="$("$GATE" "$WT5" --base main 2>&1)"; then
    grep -qiE 'ledger-only|88f0' <<<"$out" \
        || fail "(5a) ok output should name the ledger-only exemption, got: $out"
    pass "(5a) empty worktree + ledger-only main advance → gate exits 0 ($out)"
else
    fail "(5a) empty worktree + ledger-only main advance should exit 0, got non-zero: $out"
fi

# ── 5b. integration: isolation gate still DEFERS (exit 2) on a mixed main advance ──
make_repo_and_worktree_ledger r5b
printf 'seed\nticked\n' > "$REPO5/ROADMAP.md"
printf 'new code\n' > "$REPO5/leaked.sh"
git -C "$REPO5" add leaked.sh ROADMAP.md
git -C "$REPO5" commit -qm 'leaked: mixed ledger + code commit'
if "$GATE" "$WT5" --base main >/dev/null 2>&1; then
    fail "(5b) empty worktree + mixed (ledger+code) main advance should exit 2, but exited 0"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(5b) mixed main advance should exit 2, got $rc"
    pass "(5b) empty worktree + mixed main advance → gate still exits 2 (deferred)"
fi

pass "lib-ledger-only-diff.sh + isolation-gate wiring (id:88f0)"
