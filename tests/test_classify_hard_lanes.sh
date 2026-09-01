#!/usr/bin/env bash
# Defect-fix test (no roadmap item — inline fix for the /meeting HARD-lane over-claim,
# 2026-07-14; MIGRATED to the capability-keyed vocabulary 2026-07-30 for routed:f1e1).
# classify.sh must route a lane-tagged item by its LANE tag, not floor everything to C3.
#
# CANONICAL vocab (capability-keyed, id:4f02) — the shared contract is
# relay/references/hard-lanes.md, parsed identically by gather-human-backlog.sh and
# project_manager's scan.py (id:b466):
#   [HARD]  (bare)         → POOL  (relay-executor work; /meeting skips it)
#   [INPUT — meeting]      → C3    (the meeting-worthy lane)
#   [INPUT — decision]     → HUMAN (human decides, NO meeting — id:1f1c)
#   [INPUT — access]       → HANDS (human-manual work; /meeting skips it)
#   [INPUT — author]       → HANDS (human-authored content, id:2b0b)
# ACCEPTED old vocab (venue-keyed; dual-vocab window id:4f02/id:8111 still OPEN):
#   [HARD — pool] → POOL, [HARD — meeting] → C3, [HARD — hands] → HANDS,
#   [HARD — decision gate] → C3 (auto-gate alias, id:3801)
# An UNRECOGNIZED lane → C3 with GATE containing HARD-NOLANE (id:78ff loud reject).
#
# routed:f1e1 REGRESSION: before the fix the extractor only saw /\[HARD[^]]*\]/, so bare
# [HARD] — the spelling hooks/pre-commit-lane-vocab.sh now MANDATES — fell to the default
# and every ratchet-compliant pool item read as C3 + HARD-NOLANE (surfaced as a redundant
# meeting candidate AND permanently reported "needs a lane"), while the entire
# [INPUT — …] family was invisible to the lane floor entirely.
#
# And the lane must be read from the item's OWN LEADING tag segment, NOT its prose —
# an [INPUT — meeting] umbrella whose body discusses "[HARD — pool]" must not read as POOL
# (anchoring regression, id:0d58/id:4da4), including when the mention is backtick-quoted
# (id:306d/id:1bbd).
# fails-against: rev 56650ae42087 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/SKILL.md, meeting/append.sh, meeting/classify.sh (+3 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 56650ae42087 -- meeting/SKILL.md meeting/append.sh meeting/classify.sh projects/SKILL.md relay/references/human.md relay/scripts/scan-routed.sh
# fails-against-assertion: [HARD — pool] must be POOL, got

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
- [ ] [HARD] **Bare hard item** — the new-vocab pool lane. <!-- id:dddd -->
- [ ] [INPUT — meeting] **Umbrella** — a long design item whose own lane is meeting but whose PROSE, hundreds of characters into this single line, goes on to weigh several directions, cite cousin items, quote prior decisions, and only much later discuss moving discovery work onto a [HARD — pool] executor lane while mentioning pool and hands repeatedly in the body. <!-- id:eeee -->
- [ ] [HARD — meeting] **Meeting-tagged item whose long title even says the word MEETING and pool and hands** — but the tag is the lane. <!-- id:9999 -->
- [ ] [HARD] **MEETING: a bare-hard item whose title starts with the word MEETING** must not read as the meeting lane. <!-- id:8888 -->
- [ ] **Plain item** to design and evaluate later. <!-- id:ffff -->
- [ ] [INPUT — decision] **Decision item** — a human call, no design session. <!-- id:1111 -->
- [ ] [INPUT — access] **Access item** — needs sudo on the device. <!-- id:2222 -->
- [ ] [INPUT — author] **Author item** — human-expert-authored content. <!-- id:3333 -->
- [ ] [HARD — decision gate] **Old auto-gate alias** — routes to the meeting lane. <!-- id:4444 -->
- [ ] [INPUT — nonsense] **Unrecognized lane** — must LOUD-reject. <!-- id:5555 -->
- [ ] [ROUTINE] **A routine item** whose prose merely mentions a re-laned `[INPUT — access]` tag in backticks. <!-- id:6666 -->
- [ ] [ROUTINE] **A plain routine item** — no link, no planning keyword. <!-- id:7777 -->
- [ ] [ROUTINE] **A routine item we should evaluate and plan** — keyword-bait prose that used to force C2. <!-- id:aab1 -->
- [ ] [ROUTINE] **A routine item with a designed note** docs/meeting-notes/2026-01-01-0000-x.md — link + Decisions, so it used to be C1. <!-- id:aab2 -->
- [ ] [MECHANICAL] **A daemon-run item** — pure compute, no LLM. <!-- id:aab3 -->
- [ ] [MECHANICAL] [INTENSIVE — local-llm] **A daemon item with a composed resource axis** — the INTENSIVE modifier must not shadow the lane. <!-- id:aab4 -->
- [ ] [INPUT — meeting] **A meeting item whose long prose discusses moving work onto a [ROUTINE] executor lane and mentions [MECHANICAL] daemon runs**, repeatedly, hundreds of characters into this single line, so that a naive whole-line grep would mis-read its lane — this is the trap that overstated id:4e3b's own blast radius by ~50%% during its design, and the head-anchor is what prevents it. <!-- id:aab5 -->
EOF

# The C1 fixture above needs a linked note WITH a Decisions section, mirroring the
# test_classify_hard_floor.sh fixture, so the [ROUTINE]-with-Decisions case is real.
mkdir -p "$TMP/docs/meeting-notes"
printf '# note\n\n## Decisions\n\n- D1: something was decided.\n' \
  > "$TMP/docs/meeting-notes/2026-01-01-0000-x.md"

out="$("$SH" "$TMP")"

cls()  { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $1}'; }
gate() { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $5}'; }

# --- ACCEPTED old vocab (dual-vocab window still OPEN) --------------------------
[[ "$(cls aaaa)" == "POOL"  ]] || fail "[HARD — pool] must be POOL, got '$(cls aaaa)'"
pass "[HARD — pool] → POOL"

[[ "$(cls bbbb)" == "HANDS" ]] || fail "[HARD — hands] must be HANDS, got '$(cls bbbb)'"
pass "[HARD — hands] → HANDS"

[[ "$(cls cccc)" == "C3"    ]] || fail "[HARD — meeting] must be C3, got '$(cls cccc)'"
pass "[HARD — meeting] → C3"

[[ "$(cls 4444)" == "C3"    ]] || fail "[HARD — decision gate] must be C3, got '$(cls 4444)'"
[[ "$(gate 4444)" != *HARD-NOLANE* ]] || fail "[HARD — decision gate] must not be HARD-NOLANE"
pass "[HARD — decision gate] → C3 (auto-gate alias, id:3801)"

# --- CANONICAL new vocab (routed:f1e1 — the regression this test now guards) ----
[[ "$(cls dddd)" == "POOL" ]] || fail "bare [HARD] must be POOL (new-vocab pool lane), got '$(cls dddd)'"
[[ "$(gate dddd)" != *HARD-NOLANE* ]] || fail "bare [HARD] must NOT be HARD-NOLANE — it IS the pool lane (routed:f1e1), got '$(gate dddd)'"
pass "bare [HARD] → POOL, no HARD-NOLANE (routed:f1e1)"

[[ "$(cls 1111)" == "HUMAN" ]] || fail "[INPUT — decision] must be HUMAN, got '$(cls 1111)'"
pass "[INPUT — decision] → HUMAN (human decides, no meeting — id:1f1c)"

[[ "$(cls 2222)" == "HANDS" ]] || fail "[INPUT — access] must be HANDS, got '$(cls 2222)'"
pass "[INPUT — access] → HANDS"

[[ "$(cls 3333)" == "HANDS" ]] || fail "[INPUT — author] must be HANDS, got '$(cls 3333)'"
pass "[INPUT — author] → HANDS (id:2b0b)"

# --- LOUD reject on an unrecognized lane (id:78ff / id:415b) --------------------
[[ "$(cls 5555)" == "C3" ]] || fail "unrecognized lane must be C3, got '$(cls 5555)'"
[[ "$(gate 5555)" == *HARD-NOLANE* ]] || fail "unrecognized lane must be HARD-NOLANE, got '$(gate 5555)'"
pass "[INPUT — nonsense] → C3 + HARD-NOLANE (loud reject preserved)"

# --- ANCHORING (id:0d58/id:4da4) + backtick-stripping (id:306d/id:1bbd) --------
c="$(cls eeee)"
[[ "$c" != "POOL" && "$c" != "HANDS" ]] || fail "prose [HARD — pool] wrongly routed umbrella to '$c' (anchoring bug)"
[[ "$(gate eeee)" != *HARD-NOLANE* ]] || fail "umbrella wrongly flagged HARD-NOLANE from prose [HARD]"
pass "[INPUT — meeting] umbrella with deep-prose [HARD — pool] → not POOL/HANDS ('$c')"

# Lane word must be read from INSIDE the bracket, not a bare title word. Under the new
# vocab this item's own lane is bare [HARD] → POOL; the 'MEETING:' title must not make it C3.
[[ "$(cls 9999)" == "C3" ]] || fail "[HARD — meeting] with 'pool'/'hands' in its title must be C3, got '$(cls 9999)'"
pass "[HARD — meeting] with distractor title words → C3"

[[ "$(cls 8888)" == "POOL" ]] || fail "[HARD] with a 'MEETING:'-prefixed title must be POOL (title word is not a lane), got '$(cls 8888)'"
pass "[HARD] 'MEETING:'-titled → POOL (title word not a lane)"

# A backtick-quoted lane mention in a non-lane item must not give it that lane.
c="$(cls 6666)"
[[ "$c" != "HANDS" ]] || fail "backtick-quoted [INPUT — access] wrongly routed a [ROUTINE] item to HANDS (id:306d)"
[[ "$(gate 6666)" != *HARD-NOLANE* ]] || fail "[ROUTINE] item wrongly flagged HARD-NOLANE from a backtick-quoted lane mention"
pass "[ROUTINE] with backtick-quoted \`[INPUT — access]\` → not HANDS ('$c')"

# --- id:4e3b: the other two capability lanes ------------------------------------
# [ROUTINE] → EXEC unconditionally, and [MECHANICAL] → its own SURFACED class.
[[ "$(cls 7777)" == "EXEC" ]] || fail "[ROUTINE] must be EXEC, got '$(cls 7777)'"
[[ "$(gate 7777)" != *HARD-NOLANE* ]] || fail "[ROUTINE] must NOT be HARD-NOLANE — it IS a valid lane"
pass "[ROUTINE] → EXEC (id:4e3b)"

# Keyword bait ("evaluate", "plan") used to force C2 via the keyword hint.
[[ "$(cls aab1)" == "EXEC" ]] || fail "[ROUTINE] with planning-keyword prose must still be EXEC, not C2, got '$(cls aab1)'"
pass "[ROUTINE] + planning-keyword prose → EXEC (keyword hint no longer wins)"

# THE LOAD-BEARING ONE: a [ROUTINE] item with a link + ## Decisions used to be C1, and
# C1 means /meeting implements it INLINE. It must be EXEC — the pool is its home, and the
# cheaper lane must not get more meeting access than bare [HARD] (which is POOL even when
# impl-ready). Guards against a well-meaning "but it's ready, let /meeting do it" revert.
[[ "$(cls aab2)" == "EXEC" ]] || fail "[ROUTINE] with link+Decisions must STILL be EXEC (never C1 — the inline-implement path is deliberately closed to it), got '$(cls aab2)'"
pass "[ROUTINE] + link + ## Decisions → EXEC, NOT C1 (id:4e3b, the deliberate carve-out refusal)"

[[ "$(cls aab3)" == "MECH" ]] || fail "[MECHANICAL] must be MECH, got '$(cls aab3)'"
[[ "$(gate aab3)" != *HARD-NOLANE* ]] || fail "[MECHANICAL] must NOT be HARD-NOLANE — it IS a valid lane"
pass "[MECHANICAL] → MECH (own class, surfaced — not folded into POOL)"

# MECH must be DISTINCT from POOL: a [MECHANICAL] item is pool-inert AND human-inert with
# no daemon built, so it needs its own visible class rather than being lumped with pool work.
[[ "$(cls aab3)" != "POOL" ]] || fail "[MECHANICAL] must not collapse into POOL — it is daemon-run, not pool-dispatched"
pass "MECH is a distinct class from POOL"

# [INTENSIVE — <resource>] composes with a capability lane and must not shadow it.
[[ "$(cls aab4)" == "MECH" ]] || fail "[MECHANICAL] with a composed [INTENSIVE — …] modifier must be MECH, got '$(cls aab4)'"
pass "[MECHANICAL] [INTENSIVE — local-llm] → MECH (resource axis does not shadow the lane)"

# ANCHORING for the new lanes — the trap that overstated id:4e3b's own blast radius.
c="$(cls aab5)"
[[ "$c" == "C3" ]] || fail "[INPUT — meeting] item whose PROSE mentions [ROUTINE]/[MECHANICAL] must stay C3, got '$c' (head-anchor regression)"
pass "[INPUT — meeting] with deep-prose [ROUTINE]/[MECHANICAL] mentions → C3 (anchoring holds for the new lanes)"

echo "ALL PASS"
