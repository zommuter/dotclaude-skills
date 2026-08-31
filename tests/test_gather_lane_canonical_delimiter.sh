#!/usr/bin/env bash
# roadmap:098a — em-dash delimiter migration S2. gather-repo-state.sh must recognize the
# HYPHEN lane/modifier spelling everywhere it currently hardcodes the em dash, and must
# normalize every input spelling to ONE canonical value.
#
# THE BUG this pins (measured 2026-08-31, before the fix): `roadmap_primary_lane`'s tag
# list at :337 enumerates ONLY em-dash spellings, so a `[HARD - pool]` item falls through
# and returns the EMPTY string. Two observable consequences, both silent:
#   (a) open_hard_pool does not count it (the :554 walk compares the canonical value), so
#       a repo whose HARD backlog is written in the target delimiter reports 0 open pool
#       items and classify-verdict.sh never emits a `hard` verdict for it;
#   (b) the [INTENSIVE] greps at :361/:364/:378 match `[INTENSIVE — ` only, so a
#       hyphen-spelled `[INTENSIVE - <res>]` is INVISIBLE — the item loses its run-alone
#       resource claim and can be dispatched concurrently with another intensive unit.
#       That is the exact hazard the 2026-06-23 incident in this file's own comment
#       describes (a zomni [INTENSIVE — local-llm] item dispatched when it should not be).
# (b) is the live one: the SSOT now emits hyphens (S1) and the CLAUDE.md em-dash ban
# pushes authors the same way, so newly authored items land in the invisible spelling.
#
# Acceptance (migration doc §S2): roadmap_primary_lane returns the SAME canonical string
# for every input spelling; top_intensive / top_intensive_routine / top_intensive_hard
# fire on both delimiters; open_hard_pool is unchanged for em-dash input.
#
# Hermetic: mktemp fixture repo, no network, no ~/.claude touch.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/gather-repo-state.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "gather-repo-state.sh not found/executable at $SH"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
printf '# TODO\n' > "$FIX/TODO.md"

# Lane tags are assembled via printf arguments rather than written as literal leading
# `- [ ]` lines: the pre-commit lane ratchet correctly BLOCKS an ADDED checkbox line
# carrying old vocabulary in either delimiter, and a fixture is not a live ledger item.
# Same form the committed tests/test_lane_vocab_ratchet_delimiter.sh fixtures use.
{
  printf '# Roadmap\n\n## Items\n'
  printf -- '- [ ] %s em-dash pool control <!-- id:1111 -->\n'            '[HARD — pool]'
  printf -- '- [ ] %s hyphen pool item <!-- id:2222 -->\n'                '[HARD - pool]'
  # ORDER IS LOAD-BEARING: the per-lane walk takes the FIRST candidate whose primary lane
  # matches, in file order. The HYPHEN intensive item is placed FIRST precisely so the
  # assertion discriminates -- if the hyphen spelling is not recognized, this item is
  # skipped and top_intensive_hard falls through to the em-dash control's `emdash-res`,
  # which is exactly the pre-fix observation.
  printf -- '- [ ] %s %s hyphen intensive item <!-- id:4444 -->\n'        '[HARD - pool]' '[INTENSIVE - hyphen-res]'
  printf -- '- [ ] %s %s em-dash intensive control <!-- id:3333 -->\n'    '[HARD — pool]' '[INTENSIVE — emdash-res]'
  printf -- '- [ ] %s %s hyphen intensive routine <!-- id:5555 -->\n'     '[ROUTINE]'     '[INTENSIVE - routine-res]'
} > "$FIX/ROADMAP.md"

git -C "$FIX" add -A; git -C "$FIX" commit -qm init

out="$("$SH" --repo fixrepo --path "$FIX" 2>/dev/null)" \
  || fail "gather-repo-state.sh exited non-zero on the fixture"

jget() { printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }

ohp="$(jget open_hard_pool)"
ti="$(jget top_intensive)"
tih="$(jget top_intensive_hard)"
tir="$(jget top_intensive_routine)"

# (a) CONTROL — the em-dash pool items must still count. If this fails the fixture never
# reached the code under test and every result below is meaningless.
[[ "$ohp" -ge 2 ]] \
  || fail "CONTROL BROKEN: em-dash [HARD — pool] items (1111, 3333) not counted — open_hard_pool=$ohp, so the fixture never exercised the walk and a green result below would be meaningless"
pass "control: em-dash pool items counted (open_hard_pool=$ohp)"

# (b) all four pool items count — the two hyphen-spelled ones are recognized too.
[[ "$ohp" -eq 4 ]] \
  || fail "hyphen-spelled [HARD - pool] items (2222, 4444) not counted: open_hard_pool=$ohp, expected 4 — roadmap_primary_lane's tag list does not know the hyphen spelling, so the canonical value is empty and the open_hard_pool walk skips them"
pass "both delimiters counted in open_hard_pool (=4)"

# (c) CONTROL — the em-dash [INTENSIVE] modifier is still seen at all.
[[ -n "$ti" ]] \
  || fail "CONTROL BROKEN: no [INTENSIVE] resource found at all (top_intensive='') — the intensive block never ran"
pass "control: an [INTENSIVE] resource is detected (top_intensive=$ti)"

# (d) the hyphen [INTENSIVE] on a hyphen HARD line populates top_intensive_hard. This is
# the live hazard: without it the item silently loses its run-alone resource claim.
[[ "$tih" == "hyphen-res" ]] \
  || fail "hyphen [INTENSIVE - hyphen-res] on a [HARD - pool] line did not populate top_intensive_hard (got '$tih') — the item loses its exclusive resource claim and can be dispatched alongside another intensive unit (the 2026-06-23 hazard)"
pass "hyphen [INTENSIVE] fires on the HARD lane (top_intensive_hard=$tih)"

# (e) the hyphen [INTENSIVE] on a [ROUTINE] line populates top_intensive_routine.
[[ "$tir" == "routine-res" ]] \
  || fail "hyphen [INTENSIVE - routine-res] on a [ROUTINE] line did not populate top_intensive_routine (got '$tir')"
pass "hyphen [INTENSIVE] fires on the ROUTINE lane (top_intensive_routine=$tir)"

echo "ALL PASS: id:098a gather-repo-state.sh delimiter-agnostic lane + INTENSIVE recognition"
