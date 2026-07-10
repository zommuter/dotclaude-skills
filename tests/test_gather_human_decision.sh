#!/usr/bin/env bash
# Defect-fix test (no roadmap item — failures always count).
# Kills the human-backlog "noise meeting" overcount at its source (user task id:baf1):
#
# (1) BUCKET/ROUTE split (id:1f1c): a HUMAN-DECIDES item — `[INPUT — decision]`, or an
#     auto-gate note routed `route:human` / "needs /relay human" — buckets to
#     `human_decision`, NOT `hard_meeting`. A /meeting sweep reads only the meeting
#     bucket, so these no longer inflate the meeting count. The genuine meeting lanes
#     ([HARD — meeting], [INPUT — meeting], route:meeting) STAY hard_meeting.
# (2) REAL route on box_summary (id:80e0): the blanket "needs a /meeting" trailer is
#     GONE from human_decision rows — grepping the collector's own output for
#     "needs a /meeting" must NOT match a human_decision row (the whole point: the
#     backlog can now be measured from the output).
# Also: a DECOMPOSED parent marked `@container` (id:8504) is skipped entirely.
#
# Hermetic: a temp RELAY_TOML + a temp own repo with a crafted ROADMAP.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoHD"
cat >"$tmp/src/repoHD/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [INPUT — decision] A pure human-decision item <!-- id:1111 -->
- [ ] A routed-human alias item [HARD — strong model] 🚧 GATED route:human <!-- id:2222 -->
- [ ] A needs-relay-human alias item [HARD — strong model] 🚧 GATED needs /relay human <!-- id:3333 -->
- [ ] [INPUT — meeting] A genuine meeting item <!-- id:4444 -->
- [ ] A meeting-routed alias item [HARD — meeting] 🚧 route:meeting <!-- id:5555 -->
- [ ] [HARD — meeting] A DECOMPOSED parent marked as a container @container <!-- id:6666 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoHD]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "fixture should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1a) [INPUT — decision] → human_decision, NEVER hard_meeting.
grep -qP '\thuman_decision\t.*A pure human-decision item' <<<"$out" \
  || fail "[INPUT — decision] not bucketed as human_decision (out: $out)"
! grep -qP '\thard_meeting\t.*A pure human-decision item' <<<"$out" \
  || fail "[INPUT — decision] leaked into hard_meeting (out: $out)"

# (1b) route:human alias → human_decision, NEVER hard_meeting.
grep -qP '\thuman_decision\t.*A routed-human alias item' <<<"$out" \
  || fail "route:human alias not bucketed as human_decision (out: $out)"
! grep -qP '\thard_meeting\t.*A routed-human alias item' <<<"$out" \
  || fail "route:human alias leaked into hard_meeting (out: $out)"

# (1c) "needs /relay human" note → human_decision.
grep -qP '\thuman_decision\t.*A needs-relay-human alias item' <<<"$out" \
  || fail "'needs /relay human' note not bucketed as human_decision (out: $out)"

# (1d) genuine meeting lanes STAY hard_meeting (control — no over-move).
grep -qP '\thard_meeting\t.*A genuine meeting item' <<<"$out" \
  || fail "[INPUT — meeting] no longer buckets as hard_meeting (out: $out)"
grep -qP '\thard_meeting\t.*A meeting-routed alias item' <<<"$out" \
  || fail "route:meeting alias no longer buckets as hard_meeting (out: $out)"

# (1e) @container DECOMPOSED parent is skipped entirely (id:8504).
! grep -q "A DECOMPOSED parent marked as a container" <<<"$out" \
  || fail "an @container-marked parent was emitted (out: $out)"

# (2) REAL route on box_summary: "needs a /meeting" must match ONLY meeting rows,
#     never a human_decision row (the ungreppable-blanket-trailer bug, id:80e0).
hd_lines="$(grep -P '\thuman_decision\t' <<<"$out")"
[[ -n "$hd_lines" ]] || fail "no human_decision rows produced at all (out: $out)"
! grep -q 'needs a /meeting' <<<"$hd_lines" \
  || fail "a human_decision row still carries the blanket 'needs a /meeting' trailer (rows: $hd_lines)"
grep -q 'human-decision' <<<"$hd_lines" \
  || fail "human_decision rows do not state their real route on box_summary (rows: $hd_lines)"
# And a genuine meeting row DOES still name a /meeting (route accuracy both ways).
grep -qP '\thard_meeting\t.*needs a /meeting' <<<"$out" \
  || fail "a hard_meeting row no longer names a /meeting on box_summary (out: $out)"

pass "human-decides items ([INPUT — decision] / route:human / needs-/relay-human) bucket as human_decision with their REAL route, meeting lanes stay hard_meeting, @container skipped (baf1: 1f1c/80e0/8504)"
