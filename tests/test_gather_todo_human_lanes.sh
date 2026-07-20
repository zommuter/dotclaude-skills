#!/usr/bin/env bash
# roadmap:4e67
# id:4e67 — gather-human-backlog.sh must ALSO scan each own repo's TODO.md for open
# human-lane items ([INPUT — meeting|access|decision], [HARD — meeting]) and emit them
# alongside the ROADMAP/REVIEW_ME output, DEDUP BY id (an item whose id appears in BOTH
# TODO and ROADMAP is listed ONCE — never double-emitted). Closes the e9cd TODO-blindness
# gap (human-gated items living only in TODO were invisible to /relay human).
#
# Hermetic: a temp RELAY_TOML + a temp own repo with a crafted ROADMAP.md and TODO.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoTD"

# ROADMAP carries id:aaaa (a [HARD — meeting] item). id:cccc lives in BOTH ledgers.
cat >"$tmp/src/repoTD/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD — meeting] A roadmap-only meeting item <!-- id:aaaa -->
- [ ] [INPUT — meeting] An item present in BOTH ledgers <!-- id:cccc -->
MD

# TODO has: id:bbbb ([INPUT — meeting]) TODO-only → MUST surface; id:cccc (also on ROADMAP)
# → MUST appear ONCE (deduped); id:dddd ([INPUT — access]) TODO-only human-lane → surface;
# id:eeee ([INPUT — decision]) TODO-only human-lane → surface; id:ffff ([ROUTINE]) is NOT a
# human lane → must NOT surface; id:0000 (bare [HARD], pool lane) → not a human lane → skip.
cat >"$tmp/src/repoTD/TODO.md" <<'MD'
# TODO

- [ ] [INPUT — meeting] A TODO-only meeting-gated item <!-- id:bbbb -->
- [ ] [INPUT — meeting] An item present in BOTH ledgers <!-- id:cccc -->
- [ ] [INPUT — access] A TODO-only access item <!-- id:dddd -->
- [ ] [INPUT — decision] A TODO-only human-decision item <!-- id:eeee -->
- [ ] [ROUTINE] A plain routine item, not human-gated <!-- id:ffff -->
- [ ] [HARD] A bare pool item, the pool runs it <!-- id:0000 -->
- [x] [INPUT — meeting] A CLOSED meeting item, never emitted <!-- id:9999 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoTD]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "fixture should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1) TODO-only [INPUT — meeting] item surfaces.
grep -q 'id:bbbb' <<<"$out" \
  || fail "TODO-only [INPUT — meeting] item (id:bbbb) did not surface (out: $out)"

# (2) TODO-only [INPUT — access] item surfaces.
grep -q 'id:dddd' <<<"$out" \
  || fail "TODO-only [INPUT — access] item (id:dddd) did not surface (out: $out)"

# (3) TODO-only [INPUT — decision] item surfaces.
grep -q 'id:eeee' <<<"$out" \
  || fail "TODO-only [INPUT — decision] item (id:eeee) did not surface (out: $out)"

# (4) DEDUP: id present in BOTH ledgers appears exactly ONCE.
cnt="$(grep -c 'id:cccc' <<<"$out" || true)"
[[ "$cnt" -eq 1 ]] || fail "id:cccc (in BOTH ledgers) emitted $cnt times, expected exactly 1 (out: $out)"

# (5) The roadmap-only meeting item still surfaces (no regression).
grep -q 'id:aaaa' <<<"$out" \
  || fail "roadmap-only meeting item (id:aaaa) no longer surfaces (out: $out)"

# (6) A [ROUTINE] TODO item is NOT a human lane — must NOT surface.
! grep -q 'id:ffff' <<<"$out" \
  || fail "[ROUTINE] TODO item (id:ffff) leaked into human backlog (out: $out)"

# (7) A bare [HARD] (pool) TODO item is not a human lane — must NOT surface from TODO.
! grep -q 'id:0000' <<<"$out" \
  || fail "bare [HARD] pool TODO item (id:0000) leaked into human backlog (out: $out)"

# (8) A CLOSED TODO box is never emitted.
! grep -q 'id:9999' <<<"$out" \
  || fail "closed [x] TODO item (id:9999) was emitted (out: $out)"

pass "gather scans TODO.md human-lane items ([INPUT — meeting|access|decision], [HARD — meeting]), dedups by id against ROADMAP, skips routine/pool/closed (id:4e67)"
