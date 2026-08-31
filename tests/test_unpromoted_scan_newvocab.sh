#!/usr/bin/env bash
# roadmap:719a — unpromoted-scan.sh primary_lane() must recognize the NEW capability-keyed
# lane vocabulary (`[INPUT — meeting|access|decision]`, bare `[HARD]`, `[MECHANICAL]`), not
# only the OLD venue-keyed `[HARD — pool|meeting|hands|decision gate]` spelling.
#
# THE BUG (observed 2026-07-11, run relay-20260711-123559-15556): the dual-vocab window is
# still OPEN (id:7df1 gated), so live TODO items carry new-vocab tags. primary_lane()'s tag
# lists (both the bold-anchor branch and the leftmost-scan branch) enumerate ONLY old-vocab
# tags. A new-vocab-prefixed item — `- [ ] [INPUT — meeting] **title** …` — fails the
# bold-title anchor (the tag sits BEFORE the `**`, not after), falls through to the
# leftmost-tag-anywhere scan, which does not know `[INPUT — meeting]` and so matches a
# `[ROUTINE]` token appearing DEEP IN THE ITEM'S PROSE → returns `[ROUTINE]` → disposition
# `promote`. Effect: all 8 of this repo's `[INPUT — meeting|access]` items were counted
# `promote`, classify-repo emitted a spurious `handoff` verdict (should be `human` per the
# promote==0 ∧ surface>0 case-b split, id:5eb3), and an Opus handoff child was dispatched
# with nothing executor-promotable to do. Same anchoring-failure CLASS as case (i) / id:4da4,
# new trigger (new-vocab tag defeats the bold anchor). This is the id:4d8e "pin each observed
# discovery failure as a RED fixture" discipline.
#
# RED until primary_lane() recognizes new-vocab tags AND anchors a tag that sits between
# `- [ ] ` and a bold `**title**`. Expected post-fix disposition:
#   [INPUT — meeting|access|decision|author] / [MECHANICAL] → laned (human/compute gate,
#                                                             verdict-neutral)
#   bare [HARD]                                             → promote (see below)
#
# AMENDED 2026-08-11 (id:4b64, routed:5ccd): case (n) originally asserted bare `[HARD]` →
# `laned`. That was WRONG, and verdict-invisible: `[HARD]` is the recorded 1:1 successor of
# `[HARD — pool]` (relay/references/hard-lanes.md rename table), which has always been
# `promote`; `laned` is verdict-NEUTRAL (classify-repo folds only {promote, surface}), so a
# repo whose apex backlog was written in the NEW vocabulary classified `idle` and never
# self-routed to handoff (VERIFIED LIVE in lodelore: id:b0c4 + id:193f). The assertion is
# re-pointed at `promote`, NOT weakened — it still fails if bare [HARD] lands in `surface`
# (the id:719a prose-false-match regression this case was written to catch).
# Hermetic: mktemp fixture repo, no network, no ~/.claude touch.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/unpromoted-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "unpromoted-scan.sh not found/executable at $SH"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t

# ROADMAP: nothing twinned (every TODO id below is un-promoted).
printf '# Roadmap\n\n## Items\n' > "$FIX/ROADMAP.md"

# TODO: new-vocab-tagged items, each PREFIXED with the lane tag before a bold title, and
# each MENTIONING an old-vocab executable token deep in its prose (the false-positive bait).
cat > "$FIX/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [INPUT — meeting] **Design the thing** — a meeting item whose body notes it supersedes an earlier [ROUTINE] plan <!-- id:7777 -->
- [ ] [INPUT — access] **Run the on-device step** — needs a credential; the authored half was a [ROUTINE] the pool built <!-- id:8888 -->
- [ ] [INPUT — decision] **Pick a substrate** — a discrete decision; prose mentions a [HARD — pool] alternative <!-- id:6666 -->
- [ ] [MECHANICAL] **Run the benchmark battery** — compute-only; the harness was authored as a [ROUTINE] <!-- id:5555 -->
- [ ] [HARD] **Strong-model refactor** — a genuine strong item; body references a [ROUTINE] follow-up <!-- id:4444 -->
- [ ] [ROUTINE] **A real executor item** — plainly promotable <!-- id:3333 -->
EOF

# (p)'s fixture, id:2222 — the hyphen-spelled OLD-vocab pool tag. Assembled via printf
# with the tag as an argument rather than written as a literal leading `- [ ]` line,
# because the pre-commit lane ratchet (hooks/pre-commit-lane-vocab.sh) correctly BLOCKS
# an ADDED checkbox line carrying old vocabulary in either delimiter -- and it should:
# this is a test fixture, not a live ledger item. Same form the committed fixtures in
# tests/test_lane_vocab_ratchet_delimiter.sh use, and it relies on the ratchet's own
# checkbox anchor, which is the live-tag-vs-mention distinction, not a bypass.
printf -- '- [ ] %s **Hyphen-spelled pool item** — the S4 target delimiter; body references a [ROUTINE] follow-up <!-- id:2222 -->\n' \
  '[HARD - pool]' >> "$FIX/TODO.md"

git -C "$FIX" add -A; git -C "$FIX" commit -qm init

rc=0; out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: must exit 0 with findings; got $rc"

# (j) [INPUT — meeting] prefixed, prose [ROUTINE] → MUST be laned, MUST NOT be promote.
grep -qP '\t7777\tpromote\t' <<<"$out" && fail "(j) [INPUT — meeting] id 7777 mis-promoted on a prose [ROUTINE] token (new-vocab bold-anchor gap):
$out"
grep -qP '\t7777\tlaned\t' <<<"$out" || fail "(j) [INPUT — meeting] id 7777 not reported as laned:
$out"
pass "(j) [INPUT — meeting] prefixed item → laned, not promote"

# (k) [INPUT — access] prefixed, prose [ROUTINE] → laned, not promote.
grep -qP '\t8888\tpromote\t' <<<"$out" && fail "(k) [INPUT — access] id 8888 mis-promoted on a prose [ROUTINE] token:
$out"
grep -qP '\t8888\tlaned\t' <<<"$out" || fail "(k) [INPUT — access] id 8888 not reported as laned:
$out"
pass "(k) [INPUT — access] prefixed item → laned, not promote"

# (l) [INPUT — decision] prefixed, prose [HARD — pool] → laned, not promote.
grep -qP '\t6666\tpromote\t' <<<"$out" && fail "(l) [INPUT — decision] id 6666 mis-promoted on a prose [HARD — pool] token:
$out"
grep -qP '\t6666\tlaned\t' <<<"$out" || fail "(l) [INPUT — decision] id 6666 not reported as laned:
$out"
pass "(l) [INPUT — decision] prefixed item → laned, not promote"

# (m) [MECHANICAL] prefixed, prose [ROUTINE] → laned (compute gate, not executor-promote).
grep -qP '\t5555\tpromote\t' <<<"$out" && fail "(m) [MECHANICAL] id 5555 mis-promoted on a prose [ROUTINE] token:
$out"
grep -qP '\t5555\tlaned\t' <<<"$out" || fail "(m) [MECHANICAL] id 5555 not reported as laned:
$out"
pass "(m) [MECHANICAL] prefixed item → laned, not promote"

# (n) bare [HARD] prefixed, prose [ROUTINE] → promote (the pool lane, id:4b64), and NEVER
# surface (the id:719a anchoring regression this case guards).
grep -qP '\t4444\tsurface\t' <<<"$out" && fail "(n) bare [HARD] id 4444 fell through to surface (primary_lane did not recognize it):
$out"
grep -qP '\t4444\tlaned\t' <<<"$out" && fail "(n) bare [HARD] id 4444 reported laned — laned is verdict-neutral, so the item is invisible to classify-repo and the repo classifies idle (id:4b64, routed:5ccd):
$out"
grep -qP '\t4444\tpromote\t' <<<"$out" || fail "(n) bare [HARD] id 4444 not reported as promote (it is the 1:1 successor of [HARD — pool]):
$out"
pass "(n) bare [HARD] prefixed item → promote (pool lane, both spellings)"

# (p) HYPHEN-spelled [HARD - pool] → promote, exactly as its em-dash twin (id:e8d4, S4).
# Guards the pairing that broke in the S4 executor's parked residue: primary_lane's tag
# list gained "[HARD - pool]" so the scan RETURNED the hyphen form, while the disposition
# regex still listed only the em-dash spelling — so the item landed in `laned`, which is
# verdict-neutral. That is case (n)'s lodelore failure re-created in the new delimiter,
# and nothing caught it. The tag list and the disposition must always change together.
grep -qP '\t2222\tsurface\t' <<<"$out" && fail "(p) [HARD - pool] id 2222 fell through to surface (primary_lane does not recognize the hyphen spelling):
$out"
grep -qP '\t2222\tlaned\t' <<<"$out" && fail "(p) [HARD - pool] id 2222 reported laned — the tag list knows the hyphen spelling but the promote disposition does not, so the item is verdict-invisible and the repo classifies idle (id:e8d4; same class as id:4b64/routed:5ccd):
$out"
grep -qP '\t2222\tpromote\t' <<<"$out" || fail "(p) [HARD - pool] id 2222 not reported as promote (both pool spellings are the same lane):
$out"
pass "(p) hyphen-spelled [HARD - pool] → promote (delimiter-agnostic pool lane)"

# (o) genuine [ROUTINE] item is STILL promote (the fix must not over-correct).
grep -qP '\t3333\tpromote\t' <<<"$out" || fail "(o) genuine [ROUTINE] id 3333 must remain promote:
$out"
pass "(o) genuine [ROUTINE] item still promotes"

echo "ALL PASS: id:719a unpromoted-scan primary_lane new-vocab recognition"
