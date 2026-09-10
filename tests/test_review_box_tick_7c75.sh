#!/usr/bin/env bash
# No roadmap header -- id:7c75 lives in TODO.md, not ROADMAP.md, so this is a plain
# feature/defect spec and its failures ALWAYS count (never EXPECTED-RED).
#
# id:7c75 -- `/relay human` section 3(a) mandates a REVIEW_ME apply step its own tooling
# could not perform: `meeting/md-merge.py` addresses a line only by an anchored
# `<!-- id:XXXX -->` marker (`update-ids`) or by a `## ` heading (`update-sections`, whose
# unit is the WHOLE section). The common REVIEW_ME shape is one coarse heading over many
# boxes, so the section handle exists but hand-composing the replacement is where a wrong
# box gets ticked silently. `relay/scripts/review-box-tick.py` is the composer that closes
# that gap.
#
# Contract asserted here:
#   A. --dry-run is INERT: the ledger is BYTE-IDENTICAL afterwards. This is the id:f563
#      class -- `scan-routed.sh` documents "writes NOTHING" and really deletes inbox
#      lines, because its dry-run is a flag re-checked at one of two write branches. Here
#      the dry branch never receives the real path at all.
#   B. The dry-run diff is byte-EXACT: applying for real yields exactly the file the dry
#      run predicted. A dry run that models the write instead of exercising it is worth
#      nothing.
#   C. ONE-BOX GUARANTEE: in a 12-box section under a single `## ` heading, exactly one box
#      flips and the other 11 lines survive VERBATIM.
#   W. A REAL WRAPPED-TITLE BOX (this repo's own REVIEW_ME.md:1286, verbatim) ticks without
#      splicing the rationale into the middle of its sentence and without leaving its `**`
#      run unterminated. A REVIEW_ME head line is a PHYSICAL line, not a logical one; 188 of
#      431 open boxes fleet-wide wrap. This is the id:2964 class one layer up.
#   X. An inline-markup run still OPEN where the rationale would land is a REFUSAL (exit 9),
#      in the box or in the caller's own --rationale (exit 1). Never emitted into.
#   D. Nothing is appended to the checkbox line: it changes by exactly its checkbox
#      character, so a trailing anchored marker stays line-final (the anchored-id readers
#      require that), and the rationale goes on its own line.
#   E. Idempotent: re-running on an already-ticked box is a clean exit-0 no-op that writes
#      nothing, not a double-tick and not an error.
#   F/G. A selector matching 2+ boxes and one matching 0 REFUSE with DIFFERENT exit codes
#      and DIFFERENT messages, both with EMPTY stdout -- their remedies are opposite
#      (narrow the selector vs. the box is not there). The id:6d7e ruling.
#   H. A file with no `## ` heading above the box (the real ai-codebench shape: an H1 title
#      and 11 bare boxes) refuses loudly instead of inventing an anchor.
#   I. A REPEATED heading refuses: md-merge keys on heading TEXT and rewrites EVERY match,
#      so applying would duplicate our section into all of them and destroy the others.
#   J. Structurally one writer: `_run_md_merge` has exactly one call site.
#   K. md-merge is the ONLY write path -- with md-merge unavailable the tool can write
#      nothing at all. It never falls back to editing the ledger itself.
#
# fails-against: the tool and this spec land in the same commit, so there is no ancestor
# revision to check out; the negative case is a mutation of the shipped tool. It makes the
# --dry-run branch pick the REAL ledger path as its write target instead of a temp copy --
# which is exactly the id:f563 defect this design exists to avoid, and which no other case
# in this file detects (the apply path and every refusal path are untouched by it). Case A
# is first in the file and `fail()` exits, so case A is the assertion that fires. The
# mutation touches only a relative path under its own cwd. It also drops the
# `shutil.copyfile` line: without that, copying the file onto itself raises SameFileError
# and the case goes red at "--dry-run exited 1" -- red for the wrong reason, and exactly
# as vacuous as passing. Verified with `make verify-negatives`.
# fails-against-mutation: sed -i -e 's|^            write_target = Path(td) / path.name$|            write_target = path|' -e 's|^            shutil.copyfile(path, write_target)$||' relay/scripts/review-box-tick.py
# fails-against-assertion: case A: --dry-run must leave the ledger BYTE-IDENTICAL
#
# fails-against: SECOND case, for the wrapped-title placement (the defect found on first
# real use, 2026-09-10). The mutation restores the first version's behaviour in its purest
# form: it APPENDS the rationale to the checkbox line's text. On a wrapped title that lands
# mid-sentence, and inside a `**` run that does not close until two lines later.
# ORDERING, which is load-bearing: case W runs 4th, immediately after C, and cases A/B/C all
# survive this mutation -- their fixture boxes have single-line titles whose bold run opens
# and closes on the head line, A's diff assertion is anchored on the line's PREFIX, and B
# counts changed lines (still 4) rather than their content. Case D asserts the same "nothing
# is appended to the head line" property and would also fire, which is why W is ordered
# BEFORE D and not after it.
# REACHABILITY, recorded because it decides which assertion is declared: W2 (the bold-run
# balance) is NOT reachable under this mutation -- appending text to a line does not change
# the `**` COUNT, so the box still balances even though the rationale sits inside the open
# run. W1 (the head line changed by more than its checkbox character) is the assertion that
# fires and the one declared. An earlier attempt to mutate the INSERTION INDEX instead
# (`ins = rel + 1`) was rejected: the tool's own exit-7 markup invariant caught it first, so
# the case died at "case W: apply exited 7" -- red for the wrong reason, and exactly as
# vacuous as passing. That is the second time this file's negative case had to be re-aimed;
# both were caught by `make verify-negatives`, neither by reading. The mutation touches only
# a relative path under its own cwd.
# fails-against-mutation: sed -i 's|^    new_section\[rel\] = flip_only(section\[rel\])$|    new_section[rel] = flip_only(section[rel]).replace(chr(10), " -- APPENDED TO THE HEAD LINE" + chr(10))|' relay/scripts/review-box-tick.py
# fails-against-assertion: case W: a WRAPPED title must not be interrupted
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/relay/scripts/review-box-tick.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "setup: review-box-tick.py not found at $TOOL"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------ fixture ledgers
# The hard case, and the main one: ONE coarse `## Open` heading over 12 boxes. Each box
# carries a token unique to it, so "did the right box flip" has an unambiguous answer.
mk_multibox() {
  {
    echo '# Human review queue'
    echo
    echo '## Open'
    echo
    for n in $(seq -w 1 12); do
      echo "- [ ] **Box $n** needs a decision. TOKEN-$n"
      echo "  Continuation for box $n with EVIDENCE-$n cited."
    done
    echo
    echo '## Resolved'
    echo
    echo '- [x] Something already closed.'
  } > "$1"
}

# The ai-codebench shape, reproduced: an H1 title and bare boxes, ZERO `## ` headings.
mk_noheading() {
  {
    echo '# Human review queue <!-- budget: 15 min -->'
    echo
    echo 'Judgment calls encoded in red tests.'
    echo
    echo '- [ ] **id:0ce2 -- the mechanical run "SUCCEEDED"** and produced zero judgments.'
    echo '  The question for you is about the acceptance contract.'
  } > "$1"
}

RAT='ANSWERED 2026-09-10: option (a), verified against commit deadbee'

# ============================================================ (A) dry-run is INERT
mk_multibox "$TMP/a.md"
before_sum="$(sha256sum < "$TMP/a.md")"
rc=0
python3 "$TOOL" --file "$TMP/a.md" --match 'EVIDENCE-07' --rationale "$RAT" \
  --dry-run > "$TMP/a.out" 2> "$TMP/a.err" || rc=$?
(( rc == 0 )) || { cat "$TMP/a.err"; fail "case A: --dry-run exited $rc, expected 0"; }
after_sum="$(sha256sum < "$TMP/a.md")"
[[ "$before_sum" == "$after_sum" ]] \
  || fail "case A: --dry-run must leave the ledger BYTE-IDENTICAL"
grep -q '^+- \[x\] \*\*Box 07\*\*' "$TMP/a.out" \
  || fail "case A: the dry-run diff must show box 07 flipping"
grep -q 'DRY RUN: nothing written' "$TMP/a.out" \
  || fail "case A: the dry run must say so on stdout"
pass "A: --dry-run prints the diff and leaves the file byte-identical"

# ============================================================ (B) the diff is byte-EXACT
# Apply for real, then check the result equals the dry run's own prediction. Rebuilding
# the predicted file from the diff would re-implement patch; instead compare the real
# apply against a second copy the dry run was run over -- the dry run already used the
# real md-merge over a copy, so the check is: apply == what the diff described.
cp "$TMP/a.md" "$TMP/b.md"
rc=0
python3 "$TOOL" --file "$TMP/b.md" --match 'EVIDENCE-07' --rationale "$RAT" \
  > "$TMP/b.out" 2> "$TMP/b.err" || rc=$?
(( rc == 0 )) || { cat "$TMP/b.err"; fail "case B: apply exited $rc, expected 0"; }
diff -u "$TMP/a.md" "$TMP/b.md" > "$TMP/b.realdiff" || true
# Every +/- line the real apply produced must appear in the dry run's diff, and vice
# versa: same single changed line, same text.
# NOTE: the payload lines are themselves markdown list items starting with `-`, so a
# diff line reads `-- [ ] **Box 07** ...`. Strip the `---`/`+++` file headers by position
# rather than by pattern; a `^[+-][^+-]` filter silently matches nothing here.
tail -n +3 "$TMP/b.realdiff" | grep -E '^[+-]' > "$TMP/b.changed" || true
real_changed="$(wc -l < "$TMP/b.changed")"
# 4 = the head line out, the flipped head line in, and the two inserted rationale lines
# (blank + the paragraph). The rationale is NOT appended to the head line -- see case W.
[[ "$real_changed" == "4" ]] \
  || fail "case B: the real apply changed $real_changed lines, expected exactly 4"
while IFS= read -r ln; do
  grep -qxF -e "$ln" "$TMP/a.out" \
    || fail "case B: the real apply produced a line the dry run did not predict: $ln"
done < "$TMP/b.changed"
pass "B: the dry-run diff is byte-exact against the real apply"

# ============================================================ (C) one-box guarantee
open_after="$(grep -c '^- \[ \]' "$TMP/b.md")"
[[ "$open_after" == "11" ]] \
  || fail "case C: expected 11 boxes still open after one tick, found $open_after"
ticked="$(grep -c '^- \[x\] \*\*Box' "$TMP/b.md")"
[[ "$ticked" == "1" ]] || fail "case C: expected exactly 1 ticked Box line, found $ticked"
for n in 01 02 03 04 05 06 08 09 10 11 12; do
  grep -qxF -e "- [ ] **Box $n** needs a decision. TOKEN-$n" "$TMP/b.md" \
    || fail "case C: box $n was not preserved verbatim"
  grep -qxF "  Continuation for box $n with EVIDENCE-$n cited." "$TMP/b.md" \
    || fail "case C: box $n's continuation line was not preserved verbatim"
done
grep -qxF '  Continuation for box 07 with EVIDENCE-07 cited.' "$TMP/b.md" \
  || fail "case C: the TARGET box's continuation line must also survive verbatim"
grep -q '^## Resolved' "$TMP/b.md" || fail "case C: the sibling section was destroyed"
grep -qxF -e '- [x] Something already closed.' "$TMP/b.md" \
  || fail "case C: the sibling section's content was destroyed"
pass "C: exactly one of 12 boxes flipped; the other 11 and the sibling section are verbatim"

# ================================================ (W) a REAL wrapped-title box, id:2964 class
# The bytes below are lines 1286-1288 of this repo's own REVIEW_ME.md as of 2026-09-10,
# copied VERBATIM (the box's body below its title is truncated; the title, its wrap and its
# `**` run -- the only properties under test -- are untouched). This is the box that broke
# the first shipped version: its head line is a PHYSICAL line that ends mid-sentence
# ("...carried TWO independent" / "first-class dispatch exclusions..."), with the `**` bold
# run opened on the head line and closed two lines later. Appending to the head line spliced
# the rationale into the middle of that sentence AND left it inside an unterminated bold run.
# 188 of 431 open boxes fleet-wide (44%) have a wrapped title, so this is the common shape,
# not an edge case.
cat > "$TMP/w.md" <<'EOF'
# Human review queue

## Review 2026-09-09c

- [ ] **`id:6446` was worked by an executor even though its ROADMAP line carried TWO independent
  first-class dispatch exclusions, and the classifier correctly excluded it -- so the exclusion is
  computed and then not consulted by whatever picks the item.** Verified by evaluating
  `classify-repo.sh`'s own predicates against the literal line. <!-- id:c076 -->

- [ ] **A second box** that must not be disturbed. SECOND-BOX
EOF
head_before="$(sed -n '5p' "$TMP/w.md")"
rc=0
python3 "$TOOL" --file "$TMP/w.md" --match 'carried TWO independent' --rationale "$RAT" \
  > /dev/null 2> "$TMP/w.err" || rc=$?
(( rc == 0 )) || { cat "$TMP/w.err"; fail "case W: apply exited $rc, expected 0"; }
head_after="$(sed -n '5p' "$TMP/w.md")"
# (W1) THE SENTENCE IS NOT INTERRUPTED: the head line differs from the original in exactly
# one character position, the checkbox. Anything spliced in mid-sentence changes more.
[[ "$head_after" == "${head_before/- \[ \]/- [x]}" ]] \
  || { printf 'before: %s\nafter:  %s\n' "$head_before" "$head_after"; \
       fail "case W: a WRAPPED title must not be interrupted -- the checkbox line may change ONLY the checkbox character"; }
# (W2) THE RENDERED RESULT IS WELL-FORMED: `**` runs balance across the whole box, and the
# bold run that opens on the head line still closes on the line it always closed on.
box_bold="$(sed -n '5,10p' "$TMP/w.md" | grep -o '\*\*' | wc -l)"
(( box_bold % 2 == 0 )) \
  || { sed -n '5,10p' "$TMP/w.md"; fail "case W: the box was left with an UNBALANCED ** run ($box_bold markers)"; }
grep -qxF -e '  computed and then not consulted by whatever picks the item.** Verified by evaluating' "$TMP/w.md" \
  || fail "case W: the line closing the bold run was not preserved verbatim"
# (W3) The rationale is present, on its own line, AFTER the box's last body line.
rat_line="$(grep -nxF -e "  $RAT" "$TMP/w.md" | cut -d: -f1)"
[[ -n "$rat_line" ]] || { cat "$TMP/w.md"; fail "case W: the rationale is missing from the box"; }
close_line="$(grep -n 'own predicates against the literal line' "$TMP/w.md" | cut -d: -f1)"
(( rat_line > close_line )) \
  || fail "case W: the rationale (line $rat_line) must come AFTER the box's last body line (line $close_line)"
# (W4) The anchored marker is still line-final on the body line that carried it.
grep -q 'literal line\. <!-- id:c076 -->$' "$TMP/w.md" \
  || fail "case W: the box's anchored marker was disturbed"
grep -qxF -e '- [ ] **A second box** that must not be disturbed. SECOND-BOX' "$TMP/w.md" \
  || fail "case W: the neighbouring box was disturbed"
pass "W: a real wrapped-title box ticks without splicing the sentence or breaking the bold run"

# ================================================ (X) refuse an OPEN inline-markup run
# If the box's own markup is unbalanced where the paragraph would land, emitting into it
# would leave the file malformed from there on. That is a refusal, not something to emit.
cat > "$TMP/x.md" <<'EOF'
## Open

- [ ] **A box whose bold run never closes. UNBALANCED-BOX
  and its continuation line does not close it either.
EOF
sum_before="$(sha256sum < "$TMP/x.md")"
rc=0
python3 "$TOOL" --file "$TMP/x.md" --match 'UNBALANCED-BOX' --rationale "$RAT" \
  > "$TMP/x.out" 2> "$TMP/x.err" || rc=$?
(( rc == 9 )) || { cat "$TMP/x.err"; fail "case X: an open ** run at the insertion point must exit 9, got $rc"; }
[[ ! -s "$TMP/x.out" ]] || fail "case X: a refusal must print NOTHING on stdout"
grep -q 'bold run' "$TMP/x.err" || fail "case X: the message must name the open run"
[[ "$sum_before" == "$(sha256sum < "$TMP/x.md")" ]] || fail "case X: a refusal must not write"
# The same guard on the caller's own text: a rationale that opens a run and never closes it
# would break the box just as surely.
rc=0
python3 "$TOOL" --file "$TMP/w.md" --match 'SECOND-BOX' --rationale 'ANSWERED: **never closed' \
  > "$TMP/x2.out" 2> "$TMP/x2.err" || rc=$?
(( rc == 1 )) || fail "case X: an unbalanced --rationale must be refused, got $rc"
[[ ! -s "$TMP/x2.out" ]] || fail "case X: the rationale refusal must print NOTHING on stdout"
pass "X: an open ** run in the box (exit 9) or in the rationale (exit 1) is refused, never emitted"

# ============================================================ (D) rationale + marker order
cat > "$TMP/d.md" <<'EOF'
## Open

- [ ] **A box with an anchored marker** MARKED-BOX <!-- id:ab12 -->
- [ ] **A box without one** PLAIN-BOX
EOF
rc=0
python3 "$TOOL" --file "$TMP/d.md" --match 'MARKED-BOX' --rationale "$RAT" \
  > /dev/null 2> "$TMP/d.err" || rc=$?
(( rc == 0 )) || { cat "$TMP/d.err"; fail "case D: apply exited $rc, expected 0"; }
# The checkbox line must be byte-identical to the original apart from the `[ ]`->`[x]`
# character: nothing appended, so the anchored marker is still the LAST thing on it and
# every anchored-id reader keeps its grip.
grep -qxF -e '- [x] **A box with an anchored marker** MARKED-BOX <!-- id:ab12 -->' "$TMP/d.md" \
  || { grep -n 'MARKED-BOX' "$TMP/d.md"; fail "case D: the checkbox line must change ONLY the checkbox character, leaving the anchored marker line-final"; }
grep -qxF -e "  $RAT" "$TMP/d.md" \
  || { cat "$TMP/d.md"; fail "case D: the rationale must be emitted on its OWN indented line"; }
pass "D: only the checkbox char changes; marker line-final; rationale on its own line"

# ============================================================ (E) idempotent no-op
sum_before="$(sha256sum < "$TMP/d.md")"
rc=0
python3 "$TOOL" --file "$TMP/d.md" --match 'MARKED-BOX' --rationale "$RAT" \
  > "$TMP/e.out" 2> "$TMP/e.err" || rc=$?
(( rc == 0 )) || { cat "$TMP/e.err"; fail "case E: re-run exited $rc, expected a clean 0"; }
[[ "$sum_before" == "$(sha256sum < "$TMP/d.md")" ]] \
  || fail "case E: re-running on a ticked box must write NOTHING"
grep -q 'no-op' "$TMP/e.out" || fail "case E: the no-op must say so"
[[ "$(grep -c '^- \[x\]' "$TMP/d.md")" == "1" ]] \
  || fail "case E: double-tick or duplicated line"
pass "E: re-running on an already-ticked box is a clean no-op"

# ============================================================ (F) ambiguous refusal
mk_multibox "$TMP/f.md"
sum_before="$(sha256sum < "$TMP/f.md")"
rc=0
python3 "$TOOL" --file "$TMP/f.md" --match 'needs a decision' --rationale "$RAT" \
  > "$TMP/f.out" 2> "$TMP/f.err" || rc=$?
(( rc == 3 )) || fail "case F: an ambiguous --match must exit 3, got $rc"
[[ ! -s "$TMP/f.out" ]] || { cat "$TMP/f.out"; fail "case F: a refusal must print NOTHING on stdout"; }
grep -qi 'ambiguous' "$TMP/f.err" || fail "case F: the message must name ambiguity"
grep -q 'line 5:' "$TMP/f.err" || fail "case F: the message must list the candidate lines"
[[ "$sum_before" == "$(sha256sum < "$TMP/f.md")" ]] || fail "case F: a refusal must not write"
pass "F: a 12-way match refuses with exit 3, empty stdout, candidates named"

# ============================================================ (G) no-match refusal
rc=0
python3 "$TOOL" --file "$TMP/f.md" --match 'NO-SUCH-TOKEN' --rationale "$RAT" \
  > "$TMP/g.out" 2> "$TMP/g.err" || rc=$?
(( rc == 2 )) || fail "case G: a --match hitting nothing must exit 2 (NOT 3), got $rc"
[[ ! -s "$TMP/g.out" ]] || fail "case G: a refusal must print NOTHING on stdout"
grep -qi 'NO box containing' "$TMP/g.err" || fail "case G: the message must say nothing matched"
grep -qi 'ambiguous' "$TMP/g.err" \
  && fail "case G: the no-match message must NOT be the ambiguity message -- the remedies are opposite"
pass "G: a zero-match refuses with exit 2 and its OWN message, distinct from ambiguity"

# ============================================================ (H) no `## ` anchor at all
mk_noheading "$TMP/h.md"
sum_before="$(sha256sum < "$TMP/h.md")"
rc=0
python3 "$TOOL" --file "$TMP/h.md" --match 'acceptance contract' --rationale "$RAT" \
  > "$TMP/h.out" 2> "$TMP/h.err" || rc=$?
(( rc == 4 )) || fail "case H: a file with no '## ' heading must exit 4, got $rc"
[[ ! -s "$TMP/h.out" ]] || fail "case H: a refusal must print NOTHING on stdout"
grep -q 'heading' "$TMP/h.err" || fail "case H: the message must name the missing anchor"
[[ "$sum_before" == "$(sha256sum < "$TMP/h.md")" ]] || fail "case H: a refusal must not write"
# And --dry-run must refuse identically, not silently "succeed".
rc=0
python3 "$TOOL" --file "$TMP/h.md" --match 'acceptance contract' --rationale "$RAT" \
  --dry-run > /dev/null 2>&1 || rc=$?
(( rc == 4 )) || fail "case H: --dry-run must refuse the same way, got $rc"
pass "H: the no-heading shape (real ai-codebench) refuses loudly instead of guessing"

# ============================================================ (I) repeated heading
cat > "$TMP/i.md" <<'EOF'
## Open

- [ ] first FIRST-BOX

## Open

- [ ] second SECOND-BOX
EOF
sum_before="$(sha256sum < "$TMP/i.md")"
rc=0
python3 "$TOOL" --file "$TMP/i.md" --match 'FIRST-BOX' --rationale "$RAT" \
  > "$TMP/i.out" 2> "$TMP/i.err" || rc=$?
(( rc == 5 )) || fail "case I: a repeated heading must exit 5, got $rc"
[[ ! -s "$TMP/i.out" ]] || fail "case I: a refusal must print NOTHING on stdout"
grep -q 'occurs 2 times' "$TMP/i.err" || fail "case I: the message must name the repetition"
[[ "$sum_before" == "$(sha256sum < "$TMP/i.md")" ]] || fail "case I: a refusal must not write"
pass "I: a repeated '## ' heading refuses rather than silently taking the first"

# ============================================================ (J) one writer, one call site
# Supplementary source-shape tripwire beside the behavioural cases above, NOT a substitute
# for them: the inertness of --dry-run rests on the real path being unreachable from the
# dry branch, which is a claim about call sites. If a second call site appears, that
# structural argument no longer holds even if every case above still passes.
defs="$(grep -c '^def _run_md_merge(' "$TOOL")"
[[ "$defs" == "1" ]] || fail "case J: expected exactly 1 definition of _run_md_merge, found $defs"
sites="$(grep -cE '^[[:space:]]+_run_md_merge\(' "$TOOL")"
[[ "$sites" == "1" ]] \
  || fail "case J: expected exactly ONE call site of _run_md_merge, found $sites"
pass "J: _run_md_merge has exactly one call site"

# ============================================================ (K) md-merge is the ONLY writer
mk_multibox "$TMP/k.md"
sum_before="$(sha256sum < "$TMP/k.md")"
rc=0
python3 "$TOOL" --file "$TMP/k.md" --match 'EVIDENCE-03' --rationale "$RAT" \
  --md-merge "$TMP/does-not-exist.py" > "$TMP/k.out" 2> "$TMP/k.err" || rc=$?
(( rc != 0 )) || fail "case K: with md-merge missing the tool must refuse, not fall back"
[[ "$sum_before" == "$(sha256sum < "$TMP/k.md")" ]] \
  || fail "case K: with md-merge missing the ledger must be untouched -- there is no other write path"
pass "K: no md-merge, no write -- the tool never edits a ledger itself"

echo "ALL PASS: review-box-tick (id:7c75)"
