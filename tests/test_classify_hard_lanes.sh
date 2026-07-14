#!/usr/bin/env bash
# Defect-fix test (no roadmap item — inline fix for the /meeting HARD-lane over-claim,
# 2026-07-14). classify.sh must route a [HARD] item by its LANE tag, not floor every
# [HARD] to C3:
#   [HARD — meeting] → C3   (the only meeting-worthy lane)
#   [HARD — pool]    → POOL  (relay-executor work; /meeting skips it)
#   [HARD — hands]   → HANDS (human-manual work; /meeting skips it)
#   [HARD] (no lane) → C3 with GATE containing HARD-NOLANE (id:78ff loud reject)
# And the lane must be read from the item's OWN LEADING tag segment, NOT its prose —
# an [INPUT — meeting] umbrella whose body discusses "[HARD — pool]" must not read as POOL
# (anchoring regression, id:0d58/id:4da4).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/classify.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "classify.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [HARD — pool] **Pool item** — executor work. <!-- id:aaaa -->
- [ ] [HARD — hands] **Hands item** — human runs it. <!-- id:bbbb -->
- [ ] [HARD — meeting] **Meeting item** — needs a design session. <!-- id:cccc -->
- [ ] [HARD] **Bare hard item** — no lane declared. <!-- id:dddd -->
- [ ] [INPUT — meeting] **Umbrella** — a long design item whose own lane is meeting but whose PROSE, hundreds of characters into this single line, goes on to weigh several directions, cite cousin items, quote prior decisions, and only much later discuss moving discovery work onto a [HARD — pool] executor lane while mentioning pool and hands repeatedly in the body. <!-- id:eeee -->
- [ ] [HARD — meeting] **Meeting-tagged item whose long title even says the word MEETING and pool and hands** — but the tag is the lane. <!-- id:9999 -->
- [ ] [HARD] **MEETING: a bare-hard item whose title starts with the word MEETING** must not read as the meeting lane. <!-- id:8888 -->
- [ ] **Plain item** to design and evaluate later. <!-- id:ffff -->
EOF

out="$("$SH" "$TMP")"

cls() { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $1}'; }
gate() { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $5}'; }

[[ "$(cls aaaa)" == "POOL"  ]] || fail "[HARD — pool] must be POOL, got '$(cls aaaa)'"
pass "[HARD — pool] → POOL"

[[ "$(cls bbbb)" == "HANDS" ]] || fail "[HARD — hands] must be HANDS, got '$(cls bbbb)'"
pass "[HARD — hands] → HANDS"

[[ "$(cls cccc)" == "C3"    ]] || fail "[HARD — meeting] must be C3, got '$(cls cccc)'"
pass "[HARD — meeting] → C3"

[[ "$(cls dddd)" == "C3"    ]] || fail "bare [HARD] must be C3, got '$(cls dddd)'"
[[ "$(gate dddd)" == *HARD-NOLANE* ]] || fail "bare [HARD] gate must contain HARD-NOLANE, got '$(gate dddd)'"
pass "bare [HARD] → C3 + HARD-NOLANE"

# Anchoring: the [INPUT — meeting] umbrella cites [HARD — pool] in prose but its OWN lane
# is [INPUT — meeting] — it must NOT be POOL/HANDS/HARD-NOLANE.
c="$(cls eeee)"
[[ "$c" != "POOL" && "$c" != "HANDS" ]] || fail "prose [HARD — pool] wrongly routed umbrella to '$c' (anchoring bug)"
[[ "$(gate eeee)" != *HARD-NOLANE* ]] || fail "umbrella wrongly flagged HARD-NOLANE from prose [HARD]"
pass "[INPUT — meeting] umbrella with deep-prose [HARD — pool] → not POOL/HANDS ('$c')"

# Lane word must be read from INSIDE the [HARD …] bracket, not a bare title word.
[[ "$(cls 9999)" == "C3" ]] || fail "[HARD — meeting] with 'pool'/'hands' in its title must be C3, got '$(cls 9999)'"
pass "[HARD — meeting] with distractor title words → C3"

[[ "$(cls 8888)" == "C3" ]] || fail "[HARD] with a 'MEETING:'-prefixed title must be C3, got '$(cls 8888)'"
[[ "$(gate 8888)" == *HARD-NOLANE* ]] || fail "[HARD] with 'MEETING:' title must be HARD-NOLANE (bare [HARD] is no-lane), got '$(gate 8888)'"
pass "[HARD] 'MEETING:'-titled → C3 + HARD-NOLANE (title word not a lane)"

echo "ALL PASS"
