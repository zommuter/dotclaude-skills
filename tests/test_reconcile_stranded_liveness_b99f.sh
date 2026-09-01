#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — this is a DEFECT-FIX test (id:b99f), not the spec of an
# open roadmap item, so its failures must always count (never EXPECTED-RED).
#
# id:b99f — relay-reconcile.sh's stranded-branch liveness gate could never fire.
# `heartbeat.sh live-runs` emits one compact JSON OBJECT per alive run:
#   {"runId":"relay-20260813-161440-6605","pid":"","host":"zomni",...,"state":"alive"}
# but list_stranded matched it with `grep -qxF "$runid"` (whole-line equality against a BARE
# runId). A JSON line can never equal a bare runId, so the `continue` was unreachable and EVERY
# unmerged relay branch was labelled STRANDED even while its owning run was mid-round. That
# matters because the recommended disposition for a STRANDED branch is `--discard`: the tool
# pointed a human at live in-flight work.
#
# This drives the REAL relay-reconcile.sh against the REAL heartbeat.sh (its dependency),
# isolated via HOME → $HEARTBEAT_BASE, so the JSON shape under test is the one production emits
# rather than a retyped fixture.
# fails-against: rev dd8871507459 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/relay-reconcile.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: dd8871507459 -- relay/scripts/relay-reconcile.sh
# fails-against-assertion: a branch whose owning run is ALIVE was reported as STRANDED — the liveness gate never fired (THE DEFECT)

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/relay-reconcile.sh"
HB="$SRC_DIR/relay/scripts/heartbeat.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not executable"
[[ -x "$HB" ]] || fail "heartbeat.sh not executable"
command -v jq >/dev/null || fail "jq required"
bash -n "$SCRIPT" || fail "relay-reconcile.sh fails bash -n"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"; mkdir -p "$HOME"   # heartbeat base + logs land here, never in ~

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
echo base > "$repo/f.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm base

ALIVE_RUN="relay-20260101-000000-1234"
DEAD_RUN="relay-20251231-235959-9999"

mk_branch() { # <runId> <suffix> <file>
  git -C "$repo" checkout -q -b "relay/$1-$2" main
  echo work > "$repo/$3"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "unmerged work on $1"
  git -C "$repo" checkout -q main
}
mk_branch "$ALIVE_RUN" review-repo-0 g.txt
mk_branch "$DEAD_RUN"  execute-repo-1 h.txt

# Only ALIVE_RUN gets a heartbeat marker; DEAD_RUN has none.
"$HB" beat "$ALIVE_RUN" >/dev/null

# Sanity: live-runs really emits JSON (if this ever became a bare runId the defect would be
# moot and this test would be testing nothing).
live="$("$HB" live-runs)"
grep -q '"runId"' <<<"$live" \
  || fail "heartbeat live-runs no longer emits JSON objects — re-derive this test"
grep -qxF "$ALIVE_RUN" <<<"$live" \
  && fail "live-runs emitted a bare runId line — the premise of this test changed"
pass "heartbeat live-runs emits JSON objects, not bare runIds"

out="$(cd "$repo" && "$SCRIPT" "$repo" 2>&1)" || fail "reconcile exited non-zero: $out"

grep -q "$ALIVE_RUN-review-repo-0" <<<"$out" \
  && { echo "$out" | sed 's/^/    /'; fail "a branch whose owning run is ALIVE was reported as STRANDED — the liveness gate never fired (THE DEFECT)"; }
pass "a branch whose owning run is alive is NOT reported as stranded"

grep -q "STRANDED" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the dead run's branch was not surfaced at all"; }
grep -q "$DEAD_RUN-execute-repo-1" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the branch of a run with NO heartbeat must still be stranded"; }
pass "a branch whose owning run is not alive IS reported as stranded"

# Once the alive run stops, its branch becomes stranded too — proves the suppression above was
# liveness, not some unrelated filter.
"$HB" stop "$ALIVE_RUN"
out2="$(cd "$repo" && "$SCRIPT" "$repo" 2>&1)" || fail "reconcile exited non-zero: $out2"
grep -q "$ALIVE_RUN-review-repo-0" <<<"$out2" \
  || { echo "$out2" | sed 's/^/    /'; fail "after the run stopped its branch should be stranded"; }
pass "the same branch becomes stranded once its run's marker is gone"

# FAIL-SAFE direction: an UNREADABLE heartbeat must report NOTHING (treat all runs as alive),
# because the recommended disposition for a stranded branch is the destructive --discard.
badhb="$tmpdir/badhb"; mkdir -p "$badhb"
cp "$SCRIPT" "$badhb/relay-reconcile.sh"
for f in trunk-branch.sh ckpt-tag.sh sync-origin.sh commit-ledger.sh; do
  [ -e "$SRC_DIR/relay/scripts/$f" ] && cp "$SRC_DIR/relay/scripts/$f" "$badhb/$f"
done
printf '#!/usr/bin/env bash\nexit 3\n' > "$badhb/heartbeat.sh"
chmod +x "$badhb/heartbeat.sh" "$badhb/relay-reconcile.sh"
out3="$(cd "$repo" && "$badhb/relay-reconcile.sh" "$repo" 2>&1)" || fail "reconcile exited non-zero: $out3"
grep -q "STRANDED" <<<"$out3" \
  && { echo "$out3" | sed 's/^/    /'; fail "an unreadable heartbeat must NOT produce stranded reports (fail-safe = treat all runs alive)"; }
grep -qi "treating all runs as ALIVE" <<<"$out3" \
  || { echo "$out3" | sed 's/^/    /'; fail "the heartbeat failure must be SURFACED, not silently swallowed (id:4347)"; }
pass "unreadable heartbeat: fail-safe silence, and the failure is surfaced on stderr"

echo "ALL PASS: stranded liveness is matched against the runId FIELD (b99f)"
