#!/usr/bin/env bash
# roadmap:1bbd — gather-human-backlog.sh emit_hard_lanes() must read the lane from the
# item's OWN bracket tag (the tag immediately after the title), NOT from a literal
# `[HARD — pool]` that merely appears in the item's body PROSE (e.g. a re-lane-criterion
# sentence). Reported by it-infra relay HARD child (inbox routed:6645): a genuinely
# `[HARD — hands]` item whose prose quoted `[HARD — pool]` mis-bucketed as hard_pool →
# it-infra open_hard_pool=2 false-positive → a wasted Opus HARD dispatch.
#
# RED until the fix lands (the lane-parse currently does a whole-line substring match with
# the pool branch checked FIRST, so any prose mention of [HARD — pool] wins). Acceptance:
# the hands item with [HARD — pool] in its prose buckets as hard_hands, not hard_pool.
#
# Hermetic: a temp RELAY_TOML + a temp own repo with a crafted ROADMAP.md.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoP"
cat >"$tmp/src/repoP/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] A genuinely hands item whose re-lane criterion quotes `[HARD — pool]` in prose [HARD — hands] <!-- id:9321 -->
- [ ] A real pool item [HARD — pool] <!-- id:5555 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoP]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "fixture should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1) the hands item must bucket as hard_hands, NOT hard_pool — the lane comes from its
#     own bracket tag, not the [HARD — pool] string in its prose.
grep -qP '\thard_hands\t.*genuinely hands item' <<<"$out" \
  || fail "hands item (prose mentions [HARD — pool]) not bucketed as hard_hands (out: $out)"
! grep -qP '\thard_pool\t.*genuinely hands item' <<<"$out" \
  || fail "hands item mis-bucketed as hard_pool because of a prose [HARD — pool] mention (out: $out)"

# (2) the genuine pool item still buckets as hard_pool (no regression).
grep -qP '\thard_pool\t.*A real pool item' <<<"$out" \
  || fail "genuine [HARD — pool] item not bucketed as hard_pool (out: $out)"

pass "emit_hard_lanes reads the lane from the item's own bracket tag, ignoring a [HARD — pool] mention in body prose (1bbd)"

# roadmap:5648 — position-anchoring for emit_hard_lanes (mirrors classify.sh id:0d58/
# id:4da4: the item's OWN bracket tag decides, never a bucket that merely happens to be
# checked first). Before this fix the lane chain tested the whole backtick-stripped line
# with each bucket's pattern checked in a FIXED priority order regardless of textual
# position — so an item whose own head tag is `[HARD — meeting]` but whose body merely
# discusses an UNQUOTED `[HARD — pool]` later mis-bucketed as `hard_pool` (id:d84f); in
# TODO mode that silently DROPPED the item entirely (`if (bucket == "pool" ...) next`).
# The fix selects the TEXTUALLY-LEFTMOST recognized bracket tag on the line — not a fixed
# head-char window (a window false-rejects real production items across the fleet whose
# only tag sits past the window on a longer non-bold title — measured on zkm/loderite/
# puzzle-pwa before adopting this approach instead).

tmp2="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2"' EXIT

mkdir -p "$tmp2/src/repoQ"
cat >"$tmp2/src/repoQ/ROADMAP.md" <<MD
# Roadmap

## Items

- [ ] [HARD — meeting] which relay lane the research seam gets ([HARD — pool]? a new [RESEARCH]) <!-- id:d84f -->
- [ ] [HARD — pool] real pool item, positive control <!-- id:aaaa -->
- [ ] [HARD — meeting] real meeting item, positive control <!-- id:bbbb -->
- [ ] [HARD — hands] real hands item, positive control <!-- id:cccc -->
- [ ] [INPUT — meeting] input meeting item, positive control <!-- id:dddd -->
- [ ] [INPUT — access] input access item, positive control <!-- id:eeee -->
- [ ] [HARD] bare hard item, positive control <!-- id:ffff -->
- [ ] [INBOUND routed:1234 from other] [HARD — hands] leading prefix then genuine tag <!-- id:9999 -->
- [ ] $(python3 -c "print('x' * 115)") a long non-bold title whose only tag [INPUT — access] sits well past any fixed head window <!-- id:be40 -->
- [ ] [HARD — strong model] a legacy-vocab bracket the lane chain does not itself recognize, but a 🚧 route:human note deep in the body still routes it <!-- id:2222 -->
- [ ] this one truly carries no recognized lane at all, only the candidate-gate literal [HARD <!-- id:3333 -->
MD

cat >"$tmp2/relay.toml" <<TOML
[repos.repoQ]
classification = "own"
confirmed = "2026-01-01"
TOML

out2="$(RELAY_TOML="$tmp2/relay.toml" SRC_DIR="$tmp2/src" bash "$SCRIPT" 2>"$tmp2/err")" && rc2=0 || rc2=$?
[[ $rc2 -eq 1 ]] || fail "5648 fixture should exit 1 (id:3333 is a genuine untagged reject), got $rc2 (stdout: $out2, stderr: $(cat "$tmp2/err"))"

# (a) head tag [HARD — meeting] wins over a TEXTUALLY-LATER, UNQUOTED [HARD — pool]
#     mentioned in prose — the item's OWN (leftmost) bracket tag decides, not bucket
#     check-order (the id:d84f incident).
grep -qP '\thard_meeting\t.*which relay lane the research seam gets' <<<"$out2" \
  || fail "d84f-shape item not bucketed as hard_meeting from its own leftmost tag (out: $out2)"
! grep -qP '\thard_pool\t.*which relay lane the research seam gets' <<<"$out2" \
  || fail "d84f-shape item mis-bucketed as hard_pool from the later unquoted prose mention (out: $out2)"

# (b) positive controls: every recognized bucket still resolves from a genuine tag.
grep -qP '\thard_pool\t.*real pool item, positive control' <<<"$out2" || fail "hard_pool positive control failed (out: $out2)"
grep -qP '\thard_meeting\t.*real meeting item, positive control' <<<"$out2" || fail "hard_meeting positive control failed (out: $out2)"
grep -qP '\thard_hands\t.*real hands item, positive control' <<<"$out2" || fail "hard_hands positive control failed (out: $out2)"
grep -qP '\thard_meeting\t.*input meeting item, positive control' <<<"$out2" || fail "[INPUT — meeting] positive control failed (out: $out2)"
grep -qP '\thard_hands\t.*input access item, positive control' <<<"$out2" || fail "[INPUT — access] positive control failed (out: $out2)"
grep -qP '\thard_pool\t.*bare hard item, positive control' <<<"$out2" || fail "bare [HARD] positive control failed (out: $out2)"

# (c) a leading [INBOUND ...] prefix bracket followed by the genuine lane tag still
#     resolves to that lane, AND a route: alias deep in the body (id:2222, no bracket
#     tag at all) is still recognized — route aliases scan the full line, unanchored.
grep -qP '\thard_hands\t.*leading prefix then genuine tag' <<<"$out2" \
  || fail "INBOUND-prefixed item did not resolve its own [HARD — hands] tag (out: $out2)"
grep -qP '\thuman_decision\t.*a legacy-vocab bracket the lane chain does not itself recognize' <<<"$out2" \
  || fail "route:human alias deep in the body was not recognized as the fallback when the bracket itself is unrecognized (out: $out2)"

# (d) a genuine ONLY-tag on a long non-bold title (no fixed-window false reject — the
#     regression this fix must NOT introduce, id:be40 shape re-purposed as a POSITIVE
#     control here since 5648 never required a head-char window, only leftmost-wins).
grep -qP '\thard_hands\t.*long non-bold title' <<<"$out2" \
  || fail "be40-shape item (only tag past a fixed 120-char window) was wrongly untagged-rejected (out: $out2)"

# (e) an item with no recognized lane at all is still the LOUD untagged reject with a
#     non-zero exit — the guard must not be dissolved.
! grep -qP '\t(hard_pool|hard_meeting|hard_hands|human_decision)\t.*truly carries no recognized lane' <<<"$out2" \
  || fail "genuinely untagged item was laned instead of rejected (out: $out2)"
grep -qE 'ERROR:.*NO recognized lane.*truly carries no recognized lane' "$tmp2/err" \
  || fail "genuinely untagged item did not produce the LOUD untagged reject on stderr (stderr: $(cat "$tmp2/err"))"

pass "emit_hard_lanes anchors the lane to the item's OWN (textually-leftmost) bracket tag; a later unquoted prose mention never hijacks the bucket, and no fixed head-window false-rejects a genuine tag (5648)"
