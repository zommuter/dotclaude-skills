#!/usr/bin/env bash
# roadmap:8111 — B2 lane-reader migration to the new capability vocabulary
# (meeting 2026-07-02-1924 decision 2). This is the VERIFIABLE RED slice of the large
# B2 migration: the lane-PARSER `gather-human-backlog.sh` must bucket the NEW vocab —
#   bare [HARD]         → hard_pool
#   [INPUT — meeting]   → hard_meeting  (and [INPUT — decision] likewise)
#   [INPUT — access]    → hard_hands
# without LOUD-rejecting. TODAY it does the opposite: a bare [HARD] item trips the
# untagged LOUD-reject (nonzero) and an [INPUT — …] item is silently skipped (it does not
# even match /\[HARD/), so this whole test is genuinely RED until B2a lands.
#
# The relay-loop.js verdict-regex + classify-repo.sh primary-lane flips (B2b) are
# VERIFY-ON-IMPLEMENTATION — asserted by the ~30 migrated existing lane tests once they
# carry the new vocab, not re-encoded here.
#
# Hermetic: temp ROADMAP + relay.toml fixtures; no ~/.claude, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATHER="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$GATHER" ]] || fail "gather-human-backlog.sh not found/executable at $GATHER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoNew"
cat >"$tmp/src/repoNew/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD] a bare-hard new-pool item <!-- id:dd01 -->
- [ ] [INPUT — meeting] a meeting-input item <!-- id:dd02 -->
- [ ] [INPUT — decision] a decision-input item <!-- id:dd03 -->
- [ ] [INPUT — access] an access-input item <!-- id:dd04 -->
MD
cat >"$tmp/relay.toml" <<'TOML'
[repos.repoNew]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$GATHER" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] \
  || fail "new-vocab ROADMAP must NOT LOUD-reject after B2 (exit $rc); stderr: $(cat "$tmp/err")"
pass "gather-human-backlog does not LOUD-reject a new-vocab ROADMAP"

grep -qF 'hard_pool'    <<<"$out" || fail "bare [HARD] must bucket as hard_pool; got: $out"
grep -qF 'hard_meeting' <<<"$out" || fail "[INPUT — meeting]/[INPUT — decision] must bucket as hard_meeting; got: $out"
grep -qF 'hard_hands'   <<<"$out" || fail "[INPUT — access] must bucket as hard_hands; got: $out"
pass "gather-human-backlog buckets the new capability vocabulary into the human lanes"

echo "ALL PASS: wave-2b lane-reader migration (id:8111) — verifiable slice"
