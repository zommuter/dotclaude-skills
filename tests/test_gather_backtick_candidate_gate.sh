#!/usr/bin/env bash
# roadmap:306d — the candidate-skip gate in gather-human-backlog.sh's emit_hard_lanes
# must strip backticks BEFORE deciding whether a line is a HARD/INPUT candidate at
# all. Bug: the candidate gate read the RAW line, but lane-detection ran on the
# backtick-stripped `clean` text (the id:1bbd fix). A `[ROUTINE]` item whose only
# mention of `[INPUT — ...]` is inside backtick-quoted prose (e.g. "re-laned
# `[INPUT — decision]`->`[ROUTINE]`") passed the raw candidate gate (raw text
# contains "[INPUT —"), then found no lane tag in the stripped text and fell into
# the untagged LOUD-reject branch — a false positive that both mis-emitted an ERROR
# and forced a nonzero exit for an item that was never actually a HARD/INPUT item.
#
# Fix: strip backticks before the candidate-skip check, so a [ROUTINE] item merely
# quoting a lane tag in prose is recognized as NOT a candidate and silently skipped.
#
# Acceptance (id:306d): a fixture [ROUTINE] item carrying a backtick-quoted
# `[INPUT — ...]` prose mention is SKIPPED (not emitted, not rejected as untagged),
# and the scan exits 0.
#
# Hermetic: temp RELAY_TOML + temp own repo with a crafted ROADMAP.md.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoRoutine"
cat >"$tmp/src/repoRoutine/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] gather-human-backlog.sh false-rejects a [ROUTINE] item that merely mentions re-laned `[INPUT — decision]`->`[ROUTINE]` in prose <!-- id:4a46 -->
- [ ] [HARD — pool] A correctly tagged item in the same repo <!-- id:9999 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoRoutine]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?

[[ $rc -eq 0 ]] || fail "a [ROUTINE] item merely mentioning a backtick-quoted lane tag must not force a nonzero exit, got $rc (stderr: $(cat "$tmp/err"))"

! grep -q "false-rejects" <<<"$out" \
  || fail "the [ROUTINE] item was emitted as a lane row (should be silently skipped, not a candidate at all): $out"

! grep -qi "ERROR" "$tmp/err" \
  || fail "an ERROR was printed for the [ROUTINE] item — it must be silently skipped, not rejected: $(cat "$tmp/err")"

grep -qP '\thard_pool\t.*correctly tagged item' <<<"$out" \
  || fail "the genuinely tagged item in the same repo was not still emitted (out: $out)"

pass "a [ROUTINE] item merely quoting a lane tag in backticks is skipped, not rejected (306d)"
