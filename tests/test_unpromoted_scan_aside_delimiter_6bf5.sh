#!/usr/bin/env bash
# roadmap:6bf5 -- unpromoted-scan.sh's CLAUSE-BOUNDARY recognizer must accept the
# migrated `--` aside, not the em dash alone.
#
# `primary_lane`'s path-4 fallback (the leftmost-tag-with-a-boundary scan) counted a
# tag as genuine only when what follows it is end-of-line, the trailing
# `<!-- id:... -->` marker, or an EM-DASH aside. The fleet-wide em-dash ban routes
# every newly written aside to `--`, so an item spelled entirely in the target
# vocabulary reached NO boundary and returned empty.
#
# Consequences, measured on the four fixtures below before the fix:
#   [HARD - meeting] + `--` aside -> surface  (should be laned; human-lane triage noise)
#   [HARD - pool]    + `--` aside -> surface  (should be promote; SILENT and severe)
# The pool case is the id:4b64 lodelore failure re-created in the new delimiter:
# classify-repo folds only {promote, surface}, so a repo whose whole backlog reads
# like this counts zero promotable work and classifies `idle`.
#
# The em-dash twins (cc01/cc03) are the CONTROLS: they must keep their pre-existing
# dispositions, proving the fixture reaches the boundary logic at all and that the
# fix widened the boundary rather than replacing it.
#
# A single `-` must NOT open a clause (cc05) -- ordinary prose punctuation.
#
# Hermetic: one fixture repo under mktemp -d; no network, no ~/.claude, no registry.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/unpromoted-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "unpromoted-scan.sh not found/executable at $SH"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st
git -C "$FIX" config user.name t

printf '# Roadmap\n\n## Items\n' > "$FIX/ROADMAP.md"

# Non-bold items whose lane tag sits mid-line, immediately before an aside. Built with
# printf so no SOURCE line of this test starts with a `- [ ]` checkbox carrying an
# old-vocab lane tag -- that shape is what hooks/pre-commit-lane-vocab.sh blocks.
{
  printf '# TODO\n\n## Current\n'
  printf -- '- [ ] %s\n' '(i) design item [HARD — meeting] — note: supersedes an earlier plan <!-- id:cc01 -->'
  printf -- '- [ ] %s\n' '(i) design item [HARD - meeting] -- note: supersedes an earlier plan <!-- id:cc02 -->'
  printf -- '- [ ] %s\n' '(i) work item [HARD — pool] — note: the aside <!-- id:cc03 -->'
  printf -- '- [ ] %s\n' '(i) work item [HARD - pool] -- note: the aside <!-- id:cc04 -->'
  printf -- '- [ ] %s\n' '(i) work item [HARD - pool] - note: a single hyphen is prose <!-- id:cc05 -->'
} > "$FIX/TODO.md"
git -C "$FIX" add -A
git -C "$FIX" commit -qm init

run_scan() { "$1" "$FIX" 2>/dev/null; }
disp_of() {
  awk -F'\t' -v t="$2" '$2 == t { print $3; found=1 } END { if (!found) print "ABSENT" }' <<<"$1"
}

rc=0
out="$(run_scan "$SH")" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: unpromoted-scan.sh must exit 0 even with findings; got $rc"

# --- Controls: the em-dash spellings keep their pre-existing dispositions -------------
d="$(disp_of "$out" cc01)"
[[ "$d" == "laned" ]] || fail "control cc01 ([HARD — meeting] before an em-dash aside) got '$d', expected 'laned' -- the fixture is not reaching the boundary logic, so the assertions below prove nothing
--- scan output ---
$out"
pass "control: em-dash tag before an em-dash aside still reads as laned (cc01)"

d="$(disp_of "$out" cc03)"
[[ "$d" == "promote" ]] || fail "control cc03 ([HARD — pool] before an em-dash aside) got '$d', expected 'promote'
--- scan output ---
$out"
pass "control: em-dash pool tag before an em-dash aside still promotes (cc03)"

# --- The fix: a `--` aside is a clause boundary too -----------------------------------
d="$(disp_of "$out" cc02)"
[[ "$d" == "laned" ]] || fail "cc02 ([HARD - meeting] before a '--' aside) got '$d', expected 'laned' -- the aside marker must be two-spelling, exactly as the lane delimiter is
--- scan output ---
$out"
pass "hyphen tag before a '--' aside reads as laned (cc02)"

d="$(disp_of "$out" cc04)"
[[ "$d" == "promote" ]] || fail "cc04 ([HARD - pool] before a '--' aside) got '$d', expected 'promote' -- a pool item spelled entirely in the TARGET vocabulary must still promote, else the repo counts zero promotable work and classifies idle (the id:4b64 lodelore failure in the new delimiter)
--- scan output ---
$out"
pass "hyphen pool tag before a '--' aside still promotes (cc04)"

# --- A single hyphen is prose, not a clause opener ------------------------------------
d="$(disp_of "$out" cc05)"
[[ "$d" == "surface" ]] || fail "cc05 uses a SINGLE '-' after the tag; that is ordinary prose punctuation and must not count as a clause boundary, but got '$d'
--- scan output ---
$out"
pass "a single hyphen after the tag is not a clause boundary (cc05)"

# --- NEGATIVE CONTROL: the same fixture against the UNFIXED recognizer -----------------
# Copy the script and delete the `--` alternation, then assert the copy really changed
# (an unmodified copy would make this control a silent no-op, the trap that makes a
# green before/after harness meaningless).
UNFIXED="$FIX/unpromoted-scan.unfixed.sh"
python3 - "$SH" "$UNFIXED" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
needle = ' || [[ "$after" =~ ^[[:space:]]*-- ]]'
text = open(src, encoding="utf-8").read()
if needle not in text:
    sys.exit("negative control could not find the '--' alternation to remove")
open(dst, "w", encoding="utf-8").write(text.replace(needle, "", 1))
PY
[[ $? -eq 0 ]] || fail "could not build the unfixed copy for the negative control"
chmod +x "$UNFIXED"
cmp -s "$SH" "$UNFIXED" && fail "negative control is a no-op: the unfixed copy is byte-identical to the real script"

nrc=0
nout="$(run_scan "$UNFIXED")" || nrc=$?
[[ "$nrc" -eq 0 ]] || fail "negative control: the unfixed copy exited $nrc (expected 0); it did not run, so it proves nothing
--- output ---
$nout"
nd="$(disp_of "$nout" cc04)"
[[ "$nd" == "surface" ]] || fail "negative control did NOT reproduce the defect: cc04 read '$nd' against the unfixed recognizer, expected 'surface'. Either the fixture no longer exercises path 4 or the removal targeted the wrong line
--- output ---
$nout"
nd="$(disp_of "$nout" cc03)"
[[ "$nd" == "promote" ]] || fail "negative control removed too much: the em-dash control cc03 read '$nd' against the unfixed copy, expected 'promote'"
pass "negative control: without the '--' alternation cc04 falls to 'surface' while cc03 still promotes"

echo "ALL PASS: $(basename "$0")"
