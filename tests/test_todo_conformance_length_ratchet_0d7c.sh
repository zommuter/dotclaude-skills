#!/usr/bin/env bash
# No `# roadmap:` header -- this is a defect-fix / new-guard spec for TODO id:0d7c, filed from
# the meeting note `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md`, decision
# D4 AS AMENDED. Failures always count.
#
# WHAT IT PINS. D4 puts a 500-char head-line budget in relay/scripts/todo-conformance.sh and
# enforces it as a RATCHET. The amendment is the whole point: the `id:cb3e` baseline it was
# originally told to reuse is ID-KEYED and, by its own source at lib-state-claim.sh:157,
# "silently RE-GRANDFATHERS ... There is no expiry" -- so every one of today's 674 TODO items
# would be forgiven forever and free to regrow to 30 KB. The ratchet therefore baselines the
# LENGTH, not the id, and enforces MONOTONIC SHRINK. Case (c) below is the assertion an
# id-keyed baseline structurally cannot express, and is the heart of the amendment.
#
# Also pinned, because it is equally ratified and equally load-bearing: the COMPOSITION RULE.
# A line the shrinker would REFUSE to cut is reported but NEVER blocks -- 150 of 674 TODO and
# 43 of 127 ROADMAP items have no bold run, and without this, ticking one of their checkboxes
# would block a commit with no mechanical remedy.
#
# fails-against: the guard and this spec land in the same commit, so there is no ancestor
# revision to check out; the negative case is a mutation of the shipped script. It neuters the
# REGROWTH escalation only -- the class is still REPORTED, so the class-name assertion in case
# (c) still passes and the one that fires is the --strict exit assertion, which is exactly the
# monotonic-shrink guarantee an id-keyed baseline cannot make. It is the only FAIL line the
# mutation produces, hence also the last.
# fails-against-mutation: sed -i '/id:0d7c REGROWTH/s/strict_findings=$((strict_findings+1))//' relay/scripts/todo-conformance.sh
# fails-against-assertion: case (c) REGROWTH: a baselined over-budget line that GREW must FAIL --strict
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# HERMETICITY (id:2d17): this file drives LENGTH_BASELINE deliberately (that is its subject)
# but the SHAPE ratchet shares the same default-to-a-committed-file design, and these
# fixtures are long prose lines with ids absent from the live shape baseline -- so every one
# of them reports `shape-new`, an ERROR, and the --strict assertions below fail for a reason
# that has nothing to do with the length ratchet. Keep the shape ratchet INERT here.
export SHAPE_BASELINE="$tmp/no-shape-baseline.txt"

fail=0
report() { echo "FAIL: $1"; fail=1; }

# ---------------------------------------------------------------------------
# Fixture builders. The budget is NOT overridden -- these exercise the shipped
# 500-char contract. Filler prose deliberately avoids the state-claim terminal
# words and dependency prose, so no OTHER rule of this linter fires and muddies
# the exit codes.
# ---------------------------------------------------------------------------
filler() { # <n-repeats>  -> neutral prose, 60 chars per repeat
  local i
  for ((i = 0; i < $1; i++)); do
    printf 'padding prose about ledger head lines, segment %02d here; ' "$i"
  done
}

# A CUTTABLE over-budget line: a bold title (the shrinker's cut point) plus well over 40
# chars of movable residue after it.
cuttable() { # <id> <filler-repeats>
  printf -- '- [ ] [ROUTINE] **Title for %s** %s<!-- id:%s -->\n' "$1" "$(filler "$2")" "$1"
}

run() { # <flags...> -- runs the linter, captures stdout/stderr/rc
  set +e
  "$SH" "$@" > "$tmp/raw.txt" 2> "$tmp/err.txt"
  rc=$?
  set -e
  # This file specs the LENGTH ratchet only. todo-conformance emits several independent
  # rules per line, and the structural `shape-prose` check (id:30fe) fires on these
  # fixtures by design -- their filler IS prose, which is what makes them cuttable. Every
  # assertion below is of the form "this line must be silent", so leaving another rule's
  # findings in the stream makes this test assert that rule's behaviour too.
  grep -v '^shape-prose' "$tmp/raw.txt" > "$tmp/out.txt" || true
}

# ---------------------------------------------------------------------------
# (a) A NEW over-budget line BLOCKS: not in the baseline, cuttable, so --strict fails.
#     An UNDER-budget line in the same file must stay silent (no flat rule).
# ---------------------------------------------------------------------------
mkdir -p "$tmp/a"
{
  echo '# TODO'
  echo
  echo '## Current'
  cuttable aa01 12          # ~780 chars, cuttable, unbaselined
  echo '- [ ] [ROUTINE] **A short item** that is comfortably under the budget <!-- id:aa02 -->'
} > "$tmp/a/TODO.md"
: > "$tmp/a/baseline.txt"   # baseline EXISTS but is empty: the ratchet is live, nothing grandfathered

LENGTH_BASELINE="$tmp/a/baseline.txt" run --strict "$tmp/a/TODO.md"
grep -qP '^length-over-budget[^\t]*\t4\t' "$tmp/out.txt" \
  || report "case (a) NEW: an unbaselined over-budget line must be reported as length-over-budget on line 4. got:
$(cat "$tmp/out.txt")"
(( rc != 0 )) \
  || report "case (a) NEW: a new over-budget head line must FAIL --strict (got rc=0) -- without this the budget is advice, not a ratchet"
grep -q 'id:aa02' "$tmp/out.txt" \
  && report "case (a) NEW: an UNDER-budget line must not be reported at all (the rule is a ratchet, not a flat cap)"

# ---------------------------------------------------------------------------
# (b) A BASELINED over-budget line that SHRANK is allowed: reported as grandfathered
#     (never silently dropped) but never escalated. This is what lets the rule land on a
#     corpus where nearly every line is already over budget, with no migration.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/b"
{
  echo '# TODO'
  echo
  echo '## Current'
  cuttable bb01 12
} > "$tmp/b/TODO.md"
b_len=$(awk 'NR==4{print length($0)}' "$tmp/b/TODO.md")
printf '# baseline\nTODO.md\tbb01\t%d\n' $((b_len + 400)) > "$tmp/b/baseline.txt"

LENGTH_BASELINE="$tmp/b/baseline.txt" run --strict "$tmp/b/TODO.md"
(( rc == 0 )) \
  || report "case (b) SHRINK: a baselined over-budget line that got SHORTER must not fail --strict (got rc=$rc). out:
$(cat "$tmp/out.txt")"
grep -qP '^length-grandfathered' "$tmp/out.txt" \
  || report "case (b) SHRINK: a grandfathered line must still be REPORTED, never silently dropped. got:
$(cat "$tmp/out.txt")"

# ---------------------------------------------------------------------------
# (c) A BASELINED over-budget line that GREW is BLOCKED. THE HEART OF THE AMENDMENT: an
#     id-keyed baseline (cb3e) says "this id is forgiven forever" and cannot express this
#     at all, which is exactly why D4 was amended to baseline the LENGTH instead.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/c"
{
  echo '# TODO'
  echo
  echo '## Current'
  cuttable cc01 12
} > "$tmp/c/TODO.md"
c_len=$(awk 'NR==4{print length($0)}' "$tmp/c/TODO.md")
printf '# baseline\nTODO.md\tcc01\t%d\n' $((c_len - 50)) > "$tmp/c/baseline.txt"

LENGTH_BASELINE="$tmp/c/baseline.txt" run --strict "$tmp/c/TODO.md"
grep -qP '^length-regrowth' "$tmp/out.txt" \
  || report "case (c) REGROWTH: a line longer than its baselined length must be reported as length-regrowth. got:
$(cat "$tmp/out.txt")"
(( rc != 0 )) \
  || report "case (c) REGROWTH: a baselined over-budget line that GREW must FAIL --strict (got rc=0) -- monotonic shrink is the one thing an id-keyed baseline cannot enforce"

# ---------------------------------------------------------------------------
# (d) An UNSHRINKABLE line never blocks (the ratified composition rule: a rule may not
#     demand a cut the tool will not make). Two refusal shapes, both mirroring splitHead:
#       d1 -- no bold run at all (the 193-item population);
#       d2 -- a bold run, but under 40 chars of movable residue after the must-keep tokens.
#     Neither is baselined, so under a naive rule both would be case (a) blockers.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/d"
{
  echo '# TODO'
  echo
  echo '## Current'
  printf -- '- [ ] [ROUTINE] no bold run anywhere on this line, %s<!-- id:dd01 -->\n' "$(filler 12)"
  printf -- '- [ ] [ROUTINE] %s**Trailing title with nothing movable after it** <!-- id:dd02 -->\n' "$(filler 12)"
} > "$tmp/d/TODO.md"
: > "$tmp/d/baseline.txt"

LENGTH_BASELINE="$tmp/d/baseline.txt" run --strict "$tmp/d/TODO.md"
(( rc == 0 )) \
  || report "case (d) UNSHRINKABLE: a line the shrinker would refuse to cut must NEVER block (got rc=$rc). out:
$(cat "$tmp/out.txt")"
[[ "$(grep -cP '^length-unshrinkable' "$tmp/out.txt" || true)" == "2" ]] \
  || report "case (d) UNSHRINKABLE: both refusal shapes (no bold run; under-40-char residue) must be REPORTED as length-unshrinkable. got:
$(cat "$tmp/out.txt")"
grep -qP '^length-over-budget' "$tmp/out.txt" \
  && report "case (d) UNSHRINKABLE: a refusable line must not be classified as a blocking over-budget line"

# ---------------------------------------------------------------------------
# (e) `*.archive.md` is out of scope entirely (id:2065): the same blocking fixture as (a),
#     renamed, must produce no length finding and no non-zero exit.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/e"
cp "$tmp/a/TODO.md" "$tmp/e/TODO.archive.md"
: > "$tmp/e/baseline.txt"

LENGTH_BASELINE="$tmp/e/baseline.txt" run --strict "$tmp/e/TODO.archive.md"
(( rc == 0 )) \
  || report "case (e) ARCHIVE: *.archive.md is out of scope for the ratchet (id:2065); got rc=$rc. out:
$(cat "$tmp/out.txt")"
grep -qP '^length-' "$tmp/out.txt" \
  && report "case (e) ARCHIVE: no length class may be emitted for an *.archive.md file. got:
$(cat "$tmp/out.txt")"

# ---------------------------------------------------------------------------
# (f) No baseline file => the ratchet is INERT and says so LOUDLY on stderr. Landing the
#     rule without a snapshot would otherwise fail every ledger line in the fleet at once,
#     and a silently-disabled guard is the id:4347 no-silent-swallow class.
# ---------------------------------------------------------------------------
LENGTH_BASELINE="$tmp/a/does-not-exist.txt" run --strict "$tmp/a/TODO.md"
(( rc == 0 )) \
  || report "case (f) INERT: with no baseline file the ratchet must perform no length findings (got rc=$rc)"
grep -q 'ratchet INERT' "$tmp/err.txt" \
  || report "case (f) INERT: a missing baseline must be announced LOUDLY on stderr, never silently disable the guard. stderr:
$(cat "$tmp/err.txt")"

# ---------------------------------------------------------------------------
# (g) `--regen-length-baseline` is the deliberate separate act: it PRINTS a snapshot and
#     writes nothing, and feeding that snapshot back makes the same file pass --strict.
#     This is what makes the guard landable and re-tightenable after a shrink.
# ---------------------------------------------------------------------------
run --regen-length-baseline "$tmp/a/TODO.md"
(( rc == 0 )) || report "case (g) REGEN: --regen-length-baseline exited $rc"
cp "$tmp/out.txt" "$tmp/a/regen.txt"
grep -qP '^TODO\.md\taa01\t[0-9]+$' "$tmp/a/regen.txt" \
  || report "case (g) REGEN: the snapshot must carry a <ledger>TAB<id>TAB<length> row for the over-budget item. got:
$(cat "$tmp/a/regen.txt")"
grep -q 'aa02' "$tmp/a/regen.txt" \
  && report "case (g) REGEN: an UNDER-budget line must not enter the baseline (it has nothing to grandfather)"
LENGTH_BASELINE="$tmp/a/regen.txt" run --strict "$tmp/a/TODO.md"
(( rc == 0 )) \
  || report "case (g) REGEN: the file must pass --strict under its own freshly regenerated baseline (got rc=$rc). out:
$(cat "$tmp/out.txt")"

if (( fail )); then
  exit 1
fi
echo "PASS: todo-conformance.sh enforces the 500-char head-line budget as a LENGTH-baselined monotonic-shrink ratchet, grandfathers, never blocks a line the shrinker would refuse, and ignores *.archive.md (id:0d7c)"
