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
#   [INPUT — meeting|access|decision] / [MECHANICAL] → laned (human/compute gate, verdict-neutral)
#   bare [HARD]                                       → laned (strong-model, not executor-promote)
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

# (n) bare [HARD] prefixed, prose [ROUTINE] → laned (strong-model, not executor-promote).
grep -qP '\t4444\tpromote\t' <<<"$out" && fail "(n) bare [HARD] id 4444 mis-promoted on a prose [ROUTINE] token:
$out"
grep -qP '\t4444\tlaned\t' <<<"$out" || fail "(n) bare [HARD] id 4444 not reported as laned:
$out"
pass "(n) bare [HARD] prefixed item → laned, not promote"

# (o) genuine [ROUTINE] item is STILL promote (the fix must not over-correct).
grep -qP '\t3333\tpromote\t' <<<"$out" || fail "(o) genuine [ROUTINE] id 3333 must remain promote:
$out"
pass "(o) genuine [ROUTINE] item still promotes"

echo "ALL PASS: id:719a unpromoted-scan primary_lane new-vocab recognition"
