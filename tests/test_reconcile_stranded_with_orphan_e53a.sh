#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — this is a DEFECT-FIX test (id:e53a), not the spec of an
# open roadmap item, so its failures must always count (never EXPECTED-RED).
#
# id:e53a — in the per-repo `list` path, `stranded` was computed BEFORE the no-orphans early
# return but PRINTED only inside it. So as soon as the repo had at least one parked
# relay/orphan/* branch, the whole STRANDED section was silently omitted. The mixed case (some
# orphans parked AND some branches stranded) is exactly what a real recovery session hits, so
# the id:2b4b surfacing was invisible precisely when it was needed.
#
# Drives the REAL relay-reconcile.sh; no heartbeat marker exists under the overridden HOME, so
# every run reads as not-alive and the stranded branch qualifies.
# fails-against: rev dd8871507459 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/relay-reconcile.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: dd8871507459 -- relay/scripts/relay-reconcile.sh
# fails-against-assertion: the STRANDED section vanished because the repo also has a parked orphan (THE DEFECT)

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/relay-reconcile.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not executable"
bash -n "$SCRIPT" || fail "relay-reconcile.sh fails bash -n"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"; mkdir -p "$HOME"

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
echo base > "$repo/f.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm base

# 1. a PARKED orphan (the class the listing already handled)
git -C "$repo" checkout -q -b relay/orphan/relay-20260101-000000-1234-execute-repo-2 main
echo parked > "$repo/p.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm "parked orphan work"
git -C "$repo" checkout -q main

# 2. a STRANDED conflict-handback branch (live name, unmerged commits, run not alive)
git -C "$repo" checkout -q -b relay/relay-20260101-000000-1234-review-repo-0 main
echo work > "$repo/g.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm "unmerged review work"
git -C "$repo" checkout -q main

out="$(cd "$repo" && "$SCRIPT" "$repo" 2>&1)" || fail "reconcile exited non-zero: $out"

grep -q "parked orphan(s)" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the parked-orphan listing regressed"; }
grep -q "orphan/relay-20260101-000000-1234-execute-repo-2" <<<"$out" \
  || fail "the parked orphan is not named in the output"
pass "the parked orphan is still listed"

grep -q "STRANDED" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the STRANDED section vanished because the repo also has a parked orphan (THE DEFECT)"; }
grep -q "relay-20260101-000000-1234-review-repo-0" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the stranded branch is not named in the mixed-case output"; }
pass "the stranded section still prints alongside parked orphans"

# read-only: neither ref may be touched by a listing
git -C "$repo" rev-parse --verify -q refs/heads/relay/relay-20260101-000000-1234-review-repo-0 >/dev/null \
  || fail "the stranded branch was deleted — this listing must be strictly read-only"
git -C "$repo" rev-parse --verify -q refs/heads/relay/orphan/relay-20260101-000000-1234-execute-repo-2 >/dev/null \
  || fail "the parked orphan was deleted — this listing must be strictly read-only"
pass "listing is read-only; both refs survive"

echo "ALL PASS: stranded section survives a parked orphan (e53a)"
