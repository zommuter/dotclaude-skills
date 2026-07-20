#!/usr/bin/env bash
# roadmap:fa5c — gather-human-backlog.sh must never abort the WHOLE cross-repo scan
# on a single untagged [HARD]/[INPUT — ...] item in one repo. Observed 2026-07-19: a
# malformed lane tag in one repo (e.g. zkWhale id:770d/f0e5 carrying
# `[HARD — strong model]`) truncated the entire multi-repo /relay human sweep,
# silently dropping every repo not yet processed (~2/3 of the human backlog
# invisible on the 2026-07-19 run).
#
# Fix: a malformed/untagged item is reported to stderr as an ERROR but must NOT
# stop the scan — every other repo's (and the same repo's other) boxes are still
# emitted, and the script exits nonzero at the END (for CI) only after finishing
# the full sweep.
#
# Acceptance: a fixture repo with one bad-lane item must not suppress a second
# fixture repo's boxes — repoZZZ's REVIEW_ME.md box must be emitted even though
# repoAAA (processed first, alphabetically) carries an untagged [HARD] item.
# The TODO text further specifies: "make the lane-reject per-item (collect
# rejects, print them at the end as a distinct ERROR block, exit nonzero for CI,
# but ALWAYS finish emitting every repo's boxes)" — so with TWO bad repos, both
# rejects must be collected and printed together as one block AFTER the scan
# finishes, not interleaved/lost mid-run.
#
# Hermetic: temp RELAY_TOML + three temp own repos (bad, good, bad).

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# repoAAA/repoBBB sort around repoMMM so a naive early-abort would truncate
# repoMMM and/or repoBBB.
mkdir -p "$tmp/src/repoAAA" "$tmp/src/repoMMM" "$tmp/src/repoZZZ"
cat >"$tmp/src/repoAAA/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] An item with a bare HARD tag and no recognized lane [HARD — strong model REPOAAA] <!-- id:bbbb -->
MD

cat >"$tmp/src/repoMMM/REVIEW_ME.md" <<'MD'
# Review me

- [ ] A box that must still be surfaced despite repoAAA's bad tag <!-- id:cccc -->
MD

cat >"$tmp/src/repoZZZ/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] Another item with a bare HARD tag and no recognized lane [HARD — strong model REPOZZZ] <!-- id:dddd -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoAAA]
classification = "own"
confirmed = "2026-01-01"

[repos.repoMMM]
classification = "own"
confirmed = "2026-01-01"

[repos.repoZZZ]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")"
rc=$?
set -e

# (1) the run still exits nonzero overall (CI-visible contract gap) ...
[[ $rc -ne 0 ]] || fail "an untagged [HARD] item should still force a nonzero exit at the end, got 0"

# (2) ... but the repo BETWEEN the two bad repos is still fully emitted — the
# scan did not truncate at the first bad tag.
grep -q "must still be surfaced despite repoAAA" <<<"$out" \
  || fail "repoMMM's REVIEW_ME box was suppressed by repoAAA's bad tag — the scan aborted instead of continuing (out: $out, err: $(cat "$tmp/err"))"

# (3) both bad repos' rejects are reported LOUDLY on stderr (neither one is lost
# because a later abort short-circuited before it was scanned).
grep -qi "ERROR" "$tmp/err" || fail "no stderr ERROR line at all (err: $(cat "$tmp/err"))"
grep -q "REPOAAA" "$tmp/err" || fail "repoAAA's untagged item was not reported (err: $(cat "$tmp/err"))"
grep -q "REPOZZZ" "$tmp/err" || fail "repoZZZ's untagged item was not reported — the scan likely stopped before reaching it (err: $(cat "$tmp/err"))"

# (4) the rejects are collected and printed together as ONE distinct block at
# the end of the run (TODO id:fa5c: "collect rejects, print them at the end as
# a distinct ERROR block"), not scattered/lost mid-scan. Assert both untagged
# items appear contiguously after a single reject-block header, rather than
# each repo's ERROR being an isolated, uncorrelated stderr line.
grep -qi "untagged" "$tmp/err" || fail "no distinct untagged-lane-reject block header on stderr (err: $(cat "$tmp/err"))"
block="$(sed -n '/[Uu]ntagged/,$p' "$tmp/err")"
grep -q "REPOAAA" <<<"$block" || fail "repoAAA's reject is not part of the end-of-run reject block (err: $(cat "$tmp/err"))"
grep -q "REPOZZZ" <<<"$block" || fail "repoZZZ's reject is not part of the end-of-run reject block (err: $(cat "$tmp/err"))"

pass "untagged [HARD] items in multiple repos never truncate the cross-repo scan, and are collected into one end-of-run reject block (fa5c)"
