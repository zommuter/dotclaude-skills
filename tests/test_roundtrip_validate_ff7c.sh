#!/usr/bin/env bash
# roadmap:ff7c
#
# `tools/roundtrip-validate.py` -- the DIRECTIONAL round-trip validator the id:0d7c format
# ratified and nobody built. It takes a ledger tree plus its notes corpus BEFORE and AFTER a
# trimming pass and proves, mechanically, that the pass only moved things toward better.
# Its absence is how wave 1 shipped with 40 items whose decided-markers had gone dark while
# the acceptance gate reported SAFE TO LAND (id:5f34).
#
# THE DISEASE THIS FILE IS ITSELF EXPOSED TO. A checker that derives its notion of
# correctness from the thing it checks cannot fail (loderite id:dd44; id:0b70). A TEST that
# cannot fail is the same disease one level up, so every assertion below is paired with a
# NEGATIVE fixture: the corruption is applied, and the validator must refuse it. A positive
# fixture alone would pass against a validator that printed CLEAN unconditionally.
#
# Contract asserted here, one case per acceptance clause:
#   P.  An UNCHANGED pair is CLEAN (exit 0). A gate that cannot say "nothing broke" is
#       useless, and a real pass may legitimately move very little.
#   Q.  A LEGITIMATE relocation is CLEAN: prose moves off the head line into
#       docs/ledger-notes/<id>.md, every marker and the id stay on the line. This is the
#       positive control that separates "directional" from "any change is a failure".
#   A.  (a) A DESTROYED id is REFUSED -- gone from every ledger AND from the notes corpus.
#   A2. (a) An id that survives ONLY in its note is NOT reported as lost by (a) -- and IS
#       refused by (c), because a detail file is not an address. The split is deliberate
#       and is the id:5f34 shape exactly.
#   B.  (b) A line made MULTI-MARKER is REFUSED. md-merge refuses to attribute it (id:6059),
#       so the item is no longer writable by tooling even though its text is intact. The
#       refusal is observed by RUNNING md-merge, never by re-deriving its rule.
#   C.  (c) A SILENTLY CHANGED LANE is REFUSED, and both of (c)'s instruments fire: the
#       per-item lane map (which item) and `classify-repo.sh --emit unit` (the consumer's
#       own dispatch view).
#   C2. (c) A DESTROYED typed gate edge is REFUSED. `gated-on:` is an address; relocating it
#       into a note deletes it as far as every gate resolver is concerned.
#   D.  (d) A grammar finding count moving the WRONG WAY is REFUSED; the same fixture with
#       the movement reversed (a finding REMOVED) is CLEAN. Direction, not equality.
#   E.  (e) A NEW `orphan-scan --cross-ledger` finding is REFUSED.
#   I.  DIRECTIONALITY OF THE INHERITED DEFECT: a multi-marker line present in BOTH roots is
#       reported as inherited and does NOT refuse. Without this the gate goes red on the
#       live ledgers (32 such lines today) and gets baselined away on day one -- id:0b70
#       arriving from the other side.
#   H.  A harness that cannot RUN exits 2, never 0. "No findings" and "could not look" must
#       never be the same exit code.
#   Z.  END-TO-END: the real id:f193 relocation (commit ef7c7d0f, 93,667 chars moved out of
#       ROADMAP.md into docs/ledger-notes/401c.md) replays CLEAN; two deliberate corruptions
#       of that same after-state are REFUSED.
#
# HERMETIC. Everything runs in `mktemp -d`. The e2e trees are materialised with
# `git archive` out of this repo's own object store (local, deterministic, no network) and
# the working tree is never touched. `~/.claude` is never read or written: the validator is
# pointed at this repo's canonical `meeting/md-merge.py`, which is what the ~/.claude path
# symlinks to anyway.
#
# fails-against: the validator and this spec land in the same commit, so there is no
# ancestor revision to check out; the negative cases are mutations of the shipped tool.
# Case 1 disables the per-item LANE comparison -- verbatim the failure the item exists to
# prevent, where a "0 lane changes" verdict was produced by a check that could not see a
# lane change. Fixture C is built so that the classify-repo instrument ALSO fires, which is
# why the declared assertion is the per-item one: it is the half the mutation kills, and it
# is the LAST FAIL line the C case emits.
# Case 2 makes assertion (d) compare finding COUNTS as equal-or-fewer per ledger instead of
# comparing the finding SET, which is the plausible-looking shortcut that cannot see a
# finding being swapped for a different one. Fixture D-swap is exactly that shape.
# fails-against-mutation: sed -i 's/^        if b\["lane"\] != a\["lane"\]:$/        if False:/' tools/roundtrip-validate.py
# fails-against-assertion: case C: the per-item lane map must name the item whose lane changed
# fails-against-mutation: sed -i 's/^        gained = sorted(a - b)$/        gained = sorted(a - b) if len(a) > len(b) else []/' tools/roundtrip-validate.py
# fails-against-assertion: case D-swap: a finding SWAPPED for a different one must be REFUSED
#
# STATED, because a silent gap is worse than a declared one: `tests/verify-negative-cases.py`
# does NOT run the two declarations above. It reports this file as a ROADMAP-SHADOWED
# DECLARATION -- carrying both a `# roadmap:` token and a `# fails-against*` block, which
# its roadmap carve-out ("redness IS the spec") cancels. Both mutations were therefore run
# BY HAND on 2026-09-02 against the shipped tool, and each produced EXACTLY ONE `FAIL:` line,
# the declared one:
#   mutation 1 -> FAIL: case C: the per-item lane map must name the item whose lane changed
#   mutation 2 -> FAIL: case D-swap: a finding SWAPPED for a different one must be REFUSED
# One line each also satisfies the last-FAIL-line rule trivially. Cases A2/C2/Z3 stay green
# under mutation 1 and every other case stays green under mutation 2, which is what makes
# the pair discriminating rather than a blanket kill. The conflict between the two
# conventions is real and unresolved upstream; it is not resolved here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/tools/roundtrip-validate.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

[[ -x "$VALIDATOR" ]] || { echo "FAIL: sanity: $VALIDATOR must exist and be executable"; exit 1; }

# run_validator <before> <after> [args...] -> rc; combined output in $tmp/out.txt
run_validator() {
  local before="$1" after="$2"; shift 2
  set +e
  python3 "$VALIDATOR" --before "$before" --after "$after" \
    --md-merge "$ROOT/meeting/md-merge.py" "$@" > "$tmp/out.txt" 2>&1
  local rc=$?
  set -e
  return $rc
}

# ---------------------------------------------------------------------------
# Synthetic fixture corpus. Small, conforming, and deliberately boring: every case
# below corrupts exactly ONE thing, so a refusal can only come from the clause under
# test. `seed <dir>` writes the BEFORE state.
# ---------------------------------------------------------------------------
seed() {
  local d="$1"
  mkdir -p "$d/docs/ledger-notes"
  cat > "$d/ROADMAP.md" <<'EOF'
# Roadmap

## Now

- [ ] [ROUTINE] **Alpha does a thing** -- a paragraph of body prose that sits on the head line and is the sort of thing a trimming pass relocates into a note. <!-- gated-on:bbbb --> <!-- id:aaaa -->
- [ ] [INPUT - decision] **Beta needs an owner call** -- more body prose here. <!-- id:bbbb -->
- [ ] [MECHANICAL] **Gamma is a daemon chore** <!-- id:cccc -->
EOF
  cat > "$d/TODO.md" <<'EOF'
# TODO

## Open

- [ ] [ROUTINE] **Delta, the TODO-side item** <!-- id:dddd -->
EOF
  cat > "$d/docs/ledger-notes/aaaa.md" <<'EOF'
# id:aaaa -- detail

## From ROADMAP
EOF
}

# clone_seed <name> -> echoes the AFTER dir for a fixture whose BEFORE is $tmp/base
clone_seed() {
  local name="$1"
  cp -a "$tmp/base" "$tmp/$name"
  echo "$tmp/$name"
}

seed "$tmp/base"

# --- P: an unchanged pair is CLEAN --------------------------------------------------
p_after="$(clone_seed p)"
if run_validator "$tmp/base" "$p_after"; then
  grep -q 'DIRECTIONAL VERDICT: CLEAN' "$tmp/out.txt" \
    || report "case P: an unchanged pair must print a CLEAN directional verdict"
else
  report "case P: an unchanged pair must exit 0, got $? -- $(tail -3 "$tmp/out.txt")"
fi

# --- Q: a legitimate relocation is CLEAN --------------------------------------------
# The head line keeps its lane tag, its typed gate edge and its id; only the prose moves,
# and it lands verbatim in the item's note. This is what a correct pass looks like.
q_after="$(clone_seed q)"
python3 - "$q_after" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
rm = d / "ROADMAP.md"
text = rm.read_text()
old = ("- [ ] [ROUTINE] **Alpha does a thing** -- a paragraph of body prose that sits on the "
       "head line and is the sort of thing a trimming pass relocates into a note. "
       "<!-- gated-on:bbbb --> <!-- id:aaaa -->")
new = ("- [ ] [ROUTINE] **Alpha does a thing** -- detail: `docs/ledger-notes/aaaa.md` "
       "<!-- gated-on:bbbb --> <!-- id:aaaa -->")
assert old in text, "fixture drift: the Alpha head line is not what case Q expects"
rm.write_text(text.replace(old, new))
note = d / "docs" / "ledger-notes" / "aaaa.md"
note.write_text(note.read_text() + "\na paragraph of body prose that sits on the head line "
                "and is the sort of thing a trimming pass relocates into a note.\n")
PY
if run_validator "$tmp/base" "$q_after"; then
  :
else
  report "case Q: a legitimate relocation must be CLEAN, got exit $? -- $(tail -5 "$tmp/out.txt")"
fi

# --- A: a DESTROYED id is REFUSED ---------------------------------------------------
a_after="$(clone_seed a)"
python3 - "$a_after" <<'PY'
import pathlib, sys
rm = pathlib.Path(sys.argv[1]) / "ROADMAP.md"
rm.write_text(rm.read_text().replace(" <!-- id:cccc -->", ""))
PY
if run_validator "$tmp/base" "$a_after" --only a; then
  report "case A: a destroyed id must be REFUSED (exit non-zero)"
else
  grep -q 'FATAL.*(a).*LOST id:cccc' "$tmp/out.txt" \
    || report "case A: the refusal must name the LOST id -- got: $(tail -3 "$tmp/out.txt")"
fi

# --- A2: an id surviving only in its note is not (a)-lost, but IS (c)-refused --------
a2_after="$(clone_seed a2)"
python3 - "$a2_after" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
rm = d / "ROADMAP.md"
rm.write_text(rm.read_text().replace(" <!-- id:cccc -->", ""))
(d / "docs" / "ledger-notes" / "cccc.md").write_text(
    "# id:cccc -- detail <!-- id:cccc -->\n\n## From ROADMAP\n\nGamma is a daemon chore\n")
PY
if run_validator "$tmp/base" "$a2_after" --only a; then
  grep -q 'id:cccc left every ledger line but survives in' "$tmp/out.txt" \
    || report "case A2: (a) must say the BODY survived and defer the judgement to (b)/(c)"
else
  report "case A2: (a) must NOT call a note-only survivor lost -- that is (c)'s finding"
fi
if run_validator "$tmp/base" "$a2_after" --only c; then
  report "case A2: (c) must REFUSE an item whose address left the ledger for a note file"
else
  grep -q 'FATAL.*(c).*id:cccc had a computable lane/gate BEFORE and none AFTER' "$tmp/out.txt" \
    || report "case A2: (c)'s refusal must name the item that lost its address"
fi

# --- B: a MULTI-MARKER line is REFUSED (md-merge id:6059) ---------------------------
b_after="$(clone_seed b)"
python3 - "$b_after" <<'PY'
import pathlib, sys
rm = pathlib.Path(sys.argv[1]) / "ROADMAP.md"
rm.write_text(rm.read_text().replace(
    "**Gamma is a daemon chore** <!-- id:cccc -->",
    "**Gamma is a daemon chore** <!-- id:cccc --> <!-- id:bbbb -->"))
PY
if run_validator "$tmp/base" "$b_after" --only b; then
  report "case B: a line made multi-marker must be REFUSED -- md-merge cannot address it"
else
  grep -q 'FATAL.*(b).*id:cccc became UNWRITABLE' "$tmp/out.txt" \
    || report "case B: the refusal must name the id md-merge can no longer resolve"
  grep -qi 'AMBIGUOUS own id' "$tmp/out.txt" \
    || report "case B: the refusal must carry md-merge's OWN reason, not a re-derived one"
fi

# --- C: a SILENTLY CHANGED LANE is REFUSED ------------------------------------------
c_after="$(clone_seed c)"
python3 - "$c_after" <<'PY'
import pathlib, sys
rm = pathlib.Path(sys.argv[1]) / "ROADMAP.md"
rm.write_text(rm.read_text().replace("[INPUT - decision]", "[ROUTINE]"))
PY
if run_validator "$tmp/base" "$c_after" --only c; then
  report "case C: a silently changed lane must be REFUSED"
else
  grep -q "FATAL.*(c).*classify-repo.sh --emit unit disagrees on the lane-derived field" "$tmp/out.txt" \
    || report "case C: the consumer's own view (classify-repo --emit unit) must disagree too"
  grep -q 'FATAL.*(c).*id:bbbb LANE CHANGED \[INPUT - decision\] -> \[ROUTINE\]' "$tmp/out.txt" \
    || report "case C: the per-item lane map must name the item whose lane changed"
fi

# --- C2: a DESTROYED typed gate edge is REFUSED -------------------------------------
c2_after="$(clone_seed c2)"
python3 - "$c2_after" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
rm = d / "ROADMAP.md"
rm.write_text(rm.read_text().replace("<!-- gated-on:bbbb --> ", ""))
note = d / "docs" / "ledger-notes" / "aaaa.md"
note.write_text(note.read_text() + "\n<!-- gated-on:bbbb -->\n")
PY
if run_validator "$tmp/base" "$c2_after" --only c; then
  report "case C2: a gate edge relocated into a note must be REFUSED -- an edge is an address"
else
  grep -q 'FATAL.*(c).*id:aaaa gated-on EDGE CHANGED' "$tmp/out.txt" \
    || report "case C2: the refusal must name the item and the edge kind"
fi

# --- D: grammar moving the wrong way is REFUSED; the right way is CLEAN -------------
d_after="$(clone_seed d)"
printf 'a bare prose line that is no item at all\n' >> "$d_after/TODO.md"
if run_validator "$tmp/base" "$d_after" --only d; then
  report "case D: a GAINED grammar finding must be REFUSED"
else
  grep -q 'FATAL.*(d).*TODO.md GAINED grammar finding grammar-line' "$tmp/out.txt" \
    || report "case D: the refusal must name the ledger and the grammar rule gained"
fi
# The mirror image: the same finding REMOVED must be clean, or (d) is an equality check
# wearing a directional name.
mkdir -p "$tmp/d_rev_before"
cp -a "$d_after/." "$tmp/d_rev_before/"
if run_validator "$tmp/d_rev_before" "$tmp/base" --only d; then
  :
else
  report "case D-reverse: REMOVING a grammar finding must be CLEAN, got exit $? -- $(tail -3 "$tmp/out.txt")"
fi
# And a finding SWAPPED for a different one -- same count, different set -- must be
# REFUSED. This is the case a count comparison cannot see.
d_swap_before="$(clone_seed d_swap_before)"
d_swap_after="$(clone_seed d_swap_after)"
printf 'a bare prose line that is no item at all\n' >> "$d_swap_before/TODO.md"
printf 'a DIFFERENT bare prose line, also no item\n' >> "$d_swap_after/TODO.md"
if run_validator "$d_swap_before" "$d_swap_after" --only d; then
  report "case D-swap: a finding SWAPPED for a different one must be REFUSED"
else
  grep -q 'FATAL.*(d).*GAINED grammar finding' "$tmp/out.txt" \
    || report "case D-swap: the refusal must name the newly gained finding"
fi

# --- E: a NEW cross-ledger finding is REFUSED ---------------------------------------
e_after="$(clone_seed e)"
printf -- '- [x] [ROUTINE] **Delta, the TODO-side item** <!-- id:dddd -->\n' >> "$e_after/ROADMAP.md"
if run_validator "$tmp/base" "$e_after" --only e; then
  report "case E: a new orphan-scan --cross-ledger finding must be REFUSED"
else
  grep -q 'FATAL.*(e).*orphan-scan--cross-ledger GAINED a finding' "$tmp/out.txt" \
    || report "case E: the refusal must name the detector that gained a finding"
fi

# --- I: an INHERITED defect is reported, not refused --------------------------------
# Both roots carry the same multi-marker line. Absolute checking would refuse this and the
# gate would be red on the live ledgers from day one; directional checking must not.
mkdir -p "$tmp/i_before"
cp -a "$b_after/." "$tmp/i_before/"
i_after="$(clone_seed i_after)"
python3 - "$i_after" <<'PY'
import pathlib, sys
rm = pathlib.Path(sys.argv[1]) / "ROADMAP.md"
rm.write_text(rm.read_text().replace(
    "**Gamma is a daemon chore** <!-- id:cccc -->",
    "**Gamma is a daemon chore** <!-- id:cccc --> <!-- id:bbbb -->"))
PY
if run_validator "$tmp/i_before" "$i_after" --only bc; then
  grep -q 'WARN.*(b).*id:cccc was already unwritable BEFORE the pass' "$tmp/out.txt" \
    || report "case I: an inherited defect must still be REPORTED, not silently waived"
else
  report "case I: a defect present in BOTH roots must not refuse -- the check is DIRECTIONAL"
fi

# --- H: a harness that cannot run exits 2, never 0 ----------------------------------
set +e
python3 "$VALIDATOR" --before "$tmp/does-not-exist" --after "$tmp/base" > "$tmp/out.txt" 2>&1
h_rc=$?
set -e
[[ "$h_rc" -eq 2 ]] \
  || report "case H: an unreadable root must exit 2 (harness error), got $h_rc"

# ---------------------------------------------------------------------------
# Z: END-TO-END -- replay the real id:f193 relocation out of this repo's git history.
#
# ef7c7d0f moved a 93,667-char block off the id:401c ROADMAP head line into
# docs/ledger-notes/401c.md. The trees are materialised with `git archive` into $tmp; the
# working tree is never touched, which also means this case is immune to the ledger
# migration running in parallel with it.
# ---------------------------------------------------------------------------
E2E_COMMIT="ef7c7d0f"
LEDGER_PATHS=(TODO.md ROADMAP.md REVIEW_ME.md TODO.archive.md ROADMAP.archive.md
              REVIEW_ME.archive.md docs/ledger-notes)

if ! git -C "$ROOT" cat-file -e "${E2E_COMMIT}^{commit}" 2>/dev/null; then
  echo "SKIP: case Z: commit $E2E_COMMIT is not in this clone's object store"
else
  mkdir -p "$tmp/e2e/before" "$tmp/e2e/after"
  for side in "before:${E2E_COMMIT}^" "after:${E2E_COMMIT}"; do
    d="${side%%:*}"; rev="${side##*:}"
    git -C "$ROOT" archive "$rev" "${LEDGER_PATHS[@]}" | tar -x -C "$tmp/e2e/$d"
  done

  # Fixture sanity: without these the case could pass vacuously against an empty tree.
  grep -q '<!-- id:401c -->' "$tmp/e2e/before/ROADMAP.md" \
    || report "case Z sanity: the BEFORE ROADMAP.md must carry id:401c"
  before_len=$(awk '/<!-- id:401c -->/ {print length($0); exit}' "$tmp/e2e/before/ROADMAP.md")
  after_len=$(awk '/<!-- id:401c -->/ {print length($0); exit}' "$tmp/e2e/after/ROADMAP.md")
  [[ -n "$before_len" && -n "$after_len" ]] \
    || report "case Z sanity: both trees must carry an id:401c head line"

  # Z1 -- the real pass replays CLEAN. Scoped to the two ledgers the pass touched, which
  # keeps a ~45s case from becoming a ~2min one; (e)'s detectors still read the whole tree.
  if run_validator "$tmp/e2e/before" "$tmp/e2e/after" --ledgers ROADMAP.md,TODO.md; then
    grep -q 'DIRECTIONAL VERDICT: CLEAN' "$tmp/out.txt" \
      || report "case Z1: the real f193 relocation must yield a CLEAN directional verdict"
    grep -q '\[c\] lane and typed gate' "$tmp/out.txt" \
      || report "case Z1: assertion (c) must actually have run"
  else
    report "case Z1: the real f193 relocation must replay CLEAN, got exit $? -- $(grep -m3 FATAL "$tmp/out.txt")"
  fi

  # Z2 -- corrupt that same after-state so the id:401c line carries a SECOND anchored id.
  # The prose is untouched and every marker survives; only addressability breaks.
  cp -a "$tmp/e2e/after" "$tmp/e2e/after_z2"
  python3 - "$tmp/e2e/after_z2" <<'PY'
import pathlib, sys
rm = pathlib.Path(sys.argv[1]) / "ROADMAP.md"
text = rm.read_text()
assert text.count("<!-- id:401c -->") == 1, "fixture drift: expected exactly one 401c anchor"
# f193 already lives in this same ledger, so this mints no new address -- it only makes the
# 401c line ambiguous under the id:6059 grammar.
rm.write_text(text.replace("<!-- id:401c -->", "<!-- id:401c --> <!-- id:f193 -->", 1))
PY
  if run_validator "$tmp/e2e/before" "$tmp/e2e/after_z2" --only ab --ledgers ROADMAP.md; then
    report "case Z2: a corrupted after-state (multi-marker 401c line) must be REFUSED"
  else
    grep -q 'FATAL.*(b).*id:401c became UNWRITABLE' "$tmp/out.txt" \
      || report "case Z2: the refusal must name id:401c as newly unwritable"
  fi

  # Z3 -- the id:5f34 shape itself: the BODY survives (401c.md still carries the marker)
  # while the ADDRESS is deleted from the ledger line. (a) must NOT call that lost, and
  # (c) must refuse it.
  cp -a "$tmp/e2e/after" "$tmp/e2e/after_z3"
  python3 - "$tmp/e2e/after_z3" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
rm = d / "ROADMAP.md"
rm.write_text(rm.read_text().replace(" <!-- id:401c -->", "", 1))
note = d / "docs" / "ledger-notes" / "401c.md"
assert "<!-- id:401c -->" in note.read_text(), "fixture drift: the note must carry the marker"
PY
  if run_validator "$tmp/e2e/before" "$tmp/e2e/after_z3" --only ac --ledgers ROADMAP.md; then
    report "case Z3: an address deleted from the ledger while the body survives must be REFUSED"
  else
    grep -q 'id:401c left every ledger line but survives in' "$tmp/out.txt" \
      || report "case Z3: (a) must report the body-survived/address-lost split"
    grep -q 'FATAL.*(c).*id:401c had a computable lane/gate BEFORE and none AFTER' "$tmp/out.txt" \
      || report "case Z3: (c) must REFUSE the item that lost its address"
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: roundtrip-validate (id:ff7c) -- all five assertions fire on their negative case"
fi
exit "$fail"
