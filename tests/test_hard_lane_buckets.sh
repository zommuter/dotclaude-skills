#!/usr/bin/env bash
# roadmap:78ff — explicit `[HARD]` lane tags + bucketed human-backlog surface.
#
# WHY (decision 2026-06-21, user "obviously explicit"): `[HARD]` only means "apex
# tier, not a cheap Sonnet routine" — NOT the disposition. The old
# gather-human-backlog.sh::emit_gated_hard lumped EVERY open `[HARD]` item as a single
# `gated_hard` "needs a /meeting" row, so ~40 pool-executable HARD items read as 40
# meetings. The fix: every open `[HARD]` ROADMAP item declares an EXPLICIT lane in its
# bracket tag (`[HARD — pool|meeting|hands]`), the collector READS it (never infers)
# and emits a per-lane bucket kind; a `[HARD]` with NO recognized lane is a LOUD reject
# (stderr ERROR + nonzero exit, id:415b — never silently default a disposition).
#
# Asserts:
#   - one item per lane buckets to the right kind (hard_pool/hard_meeting/hard_hands);
#   - the auto-gate aliases ([HARD — decision gate], 🚧 route:meeting) bucket as meeting;
#   - an UNTAGGED [HARD] item makes the script EXIT NONZERO and print a stderr ERROR;
#   - the shared lane vocabulary doc exists (the contract both consumers read);
#   - the doc's lane marker set matches the markers the collector recognizes
#     (cross-check the shared contract).
#
# Hermetic: a temp RELAY_TOML + a temp own repo with a crafted ROADMAP.md.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"
VOCAB="$SRC_DIR_REPO/relay/references/hard-lanes.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

# --- the shared lane vocabulary doc exists (the contract both tools read) -----
[[ -f "$VOCAB" ]] || fail "lane vocabulary doc missing at $VOCAB (id:78ff/b466 shared contract)"
for marker in '[HARD — pool]' '[HARD — meeting]' '[HARD — hands]' '[HARD — decision gate]'; do
  grep -qF "$marker" "$VOCAB" || fail "vocab doc does not define the lane marker '$marker'"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- fixture A: one well-tagged item per lane + the two aliases --------------
mkdir -p "$tmp/src/repoOK"
cat >"$tmp/src/repoOK/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD — pool] Pool-executable apex item <!-- id:1111 -->
- [ ] A meeting-lane item [HARD — meeting] <!-- id:2222 -->
- [ ] A hands-lane item [HARD — hands] <!-- id:3333 -->
- [ ] Auto-gated alias item [HARD — decision gate] <!-- id:4444 -->
- [ ] Inline-routed alias item [HARD — strong model] 🚧 GATED route:meeting <!-- id:5555 -->
- [x] [HARD — pool] A CLOSED pool item that must never be emitted <!-- id:6666 -->
- [ ] [ROUTINE] A routine item that is not HARD at all <!-- id:7777 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoOK]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "well-tagged fixture should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1) each lane buckets to the right kind.
grep -qP '\thard_pool\t.*Pool-executable apex item' <<<"$out" \
  || fail "pool item not bucketed as hard_pool (out: $out)"
grep -qP '\thard_meeting\t.*A meeting-lane item' <<<"$out" \
  || fail "meeting item not bucketed as hard_meeting (out: $out)"
grep -qP '\thard_hands\t.*A hands-lane item' <<<"$out" \
  || fail "hands item not bucketed as hard_hands (out: $out)"

# (2) the two aliases bucket as meeting.
grep -qP '\thard_meeting\t.*Auto-gated alias item' <<<"$out" \
  || fail "[HARD — decision gate] alias not bucketed as hard_meeting (out: $out)"
grep -qP '\thard_meeting\t.*Inline-routed alias item' <<<"$out" \
  || fail "🚧 route:meeting inline alias not bucketed as hard_meeting (out: $out)"

# (3) closed [x] HARD items and non-HARD items are never emitted.
! grep -q "CLOSED pool item" <<<"$out" || fail "a closed [x] HARD item was emitted (out: $out)"
! grep -q "routine item that is not HARD" <<<"$out" || fail "a non-HARD item was emitted as a lane (out: $out)"

# --- fixture B: an UNTAGGED [HARD] item → LOUD reject (nonzero + stderr) ------
mkdir -p "$tmp/src/repoBad"
cat >"$tmp/src/repoBad/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD — pool] A correctly tagged item <!-- id:aaaa -->
- [ ] An item with a bare HARD tag and no lane [HARD — strong model] <!-- id:bbbb -->
MD

cat >"$tmp/relay2.toml" <<'TOML'
[repos.repoBad]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out2="$(RELAY_TOML="$tmp/relay2.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err2")"
rc2=$?
set -e

# (4) the untagged item forces a NONZERO exit (id:415b LOUD reject).
[[ $rc2 -ne 0 ]] || fail "an untagged [HARD] item must make the script exit nonzero, got 0 (out: $out2)"

# (5) a stderr ERROR names the untagged item (loud, not silent).
grep -qi "ERROR" "$tmp/err2" || fail "no stderr ERROR line for the untagged [HARD] item (err: $(cat "$tmp/err2"))"
grep -qi "lane" "$tmp/err2" || fail "the ERROR does not mention the missing lane tag (err: $(cat "$tmp/err2"))"

# (6) the correctly-tagged item in the SAME repo is still emitted before the reject.
grep -q "correctly tagged item" <<<"$out2" \
  || fail "the well-tagged item in the bad repo was not emitted (out: $out2)"

pass "explicit [HARD] lane tags bucket to hard_pool/hard_meeting/hard_hands, aliases map to meeting, and an untagged [HARD] is a loud nonzero reject (78ff)"
