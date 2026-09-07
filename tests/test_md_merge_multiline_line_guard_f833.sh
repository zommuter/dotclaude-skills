#!/usr/bin/env bash
# NO `# roadmap:` header on purpose — id:f833 is a TODO defect-fix, not an open ROADMAP
# item, so these failures always count (CLAUDE.md §Testing).
#
# Defect (id:f833, found 2026-09-07 in kienzler-solutions TODO.md):
# `md-merge.py update-ids` replaces ONLY the line carrying the `<!-- id:XXXX -->` marker.
# A ledger item in these files is that marker line PLUS its indented continuation lines.
# So a caller updating a multi-line item by passing a multi-line `line` payload got a
# DUPLICATE, not an update: the new block was written where the marker line had been, and
# the old item's continuation lines stayed beneath it. Two such calls on one item tripled
# it.
#
# The failure is silent in the worst way for a mandated write path:
#   - exit 0, nothing on stderr;
#   - `_validate_replacement` passes, because it inspects only the payload's FIRST line
#     (which does carry the marker and is checkbox-shaped);
#   - `grep -c "id:XXXX"` still reports exactly ONE marker, so the obvious post-write
#     check cannot see it. Only reading the block does.
# Observed live: id:9f11 in kienzler-solutions/TODO.md grew 43 duplicated lines carrying
# SUPERSEDED legal citations, i.e. the stale copies actively contradicted the fresh item
# beneath them.
#
# SCOPE — this test pins the REFUSAL ONLY, deliberately.
# Making a wrapped item rewritable is ROADMAP id:4f0f, whose surface (`scope: "item"`)
# and block boundary (reuse `tools/ledger-continuations.py`) are specced in
# tests/test_md_merge_item_scope_4f0f.sh and still await owner ratification
# (REVIEW_ME id:b5c1 — which records whole-block replacement as deliberately NOT specced
# yet). A `block` op was prototyped alongside this guard on 2026-09-07 and withdrawn for
# exactly that reason: it introduced a SECOND continuation-boundary definition, the
# id:4983 defect class the 4f0f spec exists to avoid. Do not re-add a block op here —
# extend id:4f0f instead.
# fails-against: rev 5073c6236530 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/md-merge.py.
# fails-against-rev: 5073c6236530 -- meeting/md-merge.py
#
# This file uses the repo's accumulator idiom (several FAIL lines fire against the
# pre-fix tree), so `# fails-against-assertion:` below names the LAST one, per CLAUDE.md
# section Testing. It is also the most direct evidence: against the old tree the incident
# sequence leaves 2 injected continuation lines where it should leave 0.
# fails-against-assertion: duplication survived:

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MD="$REPO_ROOT/meeting/md-merge.py"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fixture() {
  cat > "$tmpdir/T.md" <<'EOF'
# TODO

## Current
- [ ] **alpha item** first line <!-- id:aaa1 -->
      alpha continuation one
      alpha continuation two
- [ ] **beta item** single line <!-- id:bbb2 -->

## Done
EOF
}

# --- 1. THE DEFECT: a multi-line `line` payload must be REFUSED --------------------
fixture
cp "$tmpdir/T.md" "$tmpdir/T.before"
set +e
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >"$tmpdir/out1" 2>&1
{"updates": [{"id": "aaa1", "line": "- [ ] **alpha item** REWRITTEN <!-- id:aaa1 -->\n      brand new continuation"}]}
JSON
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  ok "multi-line \"line\" payload is refused (exit $rc)"
else
  bad "SILENT DUPLICATION: a multi-line line-payload was accepted, leaving stale continuation lines beneath the new block"
fi

# --- 2. the refusal writes NOTHING (no half-applied ledger) ------------------------
if cmp -s "$tmpdir/T.md" "$tmpdir/T.before"; then
  ok "refusal wrote NOTHING (file byte-identical)"
else
  # No `diff | head` here: under `set -o pipefail` head's early exit SIGPIPEs diff and
  # the test dies on the failure path instead of reporting it (tests/lint-pipefail-sigpipe.py).
  diff "$tmpdir/T.before" "$tmpdir/T.md" > "$tmpdir/diffout" || true
  bad "file was modified despite the refusal: $(head -3 "$tmpdir/diffout")"
fi

# --- 3. the refusal is DIAGNOSTIC: it says why, and points at the open item --------
if grep -q "DUPLICATES the item" "$tmpdir/out1"; then
  ok "refusal explains the duplication failure mode"
else
  bad "refusal does not explain why: $(head -2 "$tmpdir/out1")"
fi
if grep -q "4f0f" "$tmpdir/out1"; then
  ok "refusal names the open item that will make wrapped rewrites possible (id:4f0f)"
else
  bad "refusal leaves the caller with no forward path: $(head -3 "$tmpdir/out1")"
fi

# --- 4. the refusal leaves no stale .lock behind -----------------------------------
# The check runs UNDER the flock (it needs the file to know whether the target wraps),
# so the lock must still be released on the refusal path.
if [[ ! -e "$tmpdir/T.md.lock" ]]; then
  ok "no lock file left behind by the refusal"
else
  bad "a lock file survived the refusal"
fi

# --- 5. THE INCIDENT SEQUENCE: two such calls must not accumulate anything ---------
# This is what tripled kienzler-solutions id:9f11 — two updates of one wrapped item.
fixture
for _ in 1 2; do
  set +e
  python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [{"id": "aaa1", "line": "- [ ] **alpha item** round N <!-- id:aaa1 -->\n      continuation A"}]}
JSON
  set -e
done
if [[ "$(grep -c 'alpha item' "$tmpdir/T.md")" -eq 1 \
   && "$(grep -c 'continuation A' "$tmpdir/T.md")" -eq 0 ]]; then
  ok "the incident sequence accumulates nothing (1 item line, 0 injected continuations)"
else
  bad "duplication survived: $(grep -c 'alpha item' "$tmpdir/T.md") item line(s), $(grep -c 'continuation A' "$tmpdir/T.md") injected continuation(s)"
fi

# --- 6. NO REGRESSION: a single-line `line` still replaces the marker line ---------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [{"id": "aaa1", "line": "- [x] **alpha item** done <!-- id:aaa1 -->"}]}
JSON
if grep -q '^- \[x\] \*\*alpha item\*\* done' "$tmpdir/T.md" \
   && [[ "$(grep -c 'alpha continuation' "$tmpdir/T.md")" -eq 2 ]]; then
  ok "single-line \"line\" behaviour unchanged (continuation lines preserved)"
else
  bad "regression on the single-line replace path"
fi

# --- 7. NO REGRESSION: append and regex_sub are untouched by the guard -------------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [{"id": "bbb2", "append": " -- annotated"},
             {"id": "aaa1", "regex_sub": {"pattern": "^- \\[ \\]", "repl": "- [x]"}}]}
JSON
if grep -q 'annotated' "$tmpdir/T.md" && grep -q '^- \[x\] \*\*alpha item\*\*' "$tmpdir/T.md"; then
  ok "append and regex_sub unaffected (the guard is scoped to \"line\")"
else
  bad "the guard leaked into another op path"
fi

# --- 8. NO REGRESSION: --allow-new still appends a single-line new item ------------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" --allow-new <<'JSON' >/dev/null 2>&1
{"updates": [{"id": "eee5", "line": "- [ ] **new item** <!-- id:eee5 -->"}]}
JSON
if grep -q 'new item' "$tmpdir/T.md"; then
  ok "--allow-new single-line path unaffected"
else
  bad "--allow-new regressed"
fi

# --- 9. THE GUARD MUST BE NARROW: a multi-line payload onto a NEW item is legal ----
# relay/scripts/handback-followup.py:172 emits every seam this way — a head line plus
# indented Acceptance/Done-check/Context lines (owner requirement 2026-07-26). There are
# no old continuation lines to strand, so nothing is duplicated. A guard that refused
# this shape outright would break the handback path; that over-broad first cut is
# exactly what tests/test_handback_followup.sh and test_seam_emitter_acceptance_44a1.sh
# caught on 2026-09-07.
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" --allow-new <<'JSON' >"$tmpdir/out9" 2>&1
{"updates": [{"id": "fff6", "line": "- [ ] **seam item** <!-- id:fff6 -->\n  - **Acceptance**: something\n  - **Done-check**: something else"}]}
JSON
if grep -q 'Acceptance' "$tmpdir/T.md" && grep -q 'Done-check' "$tmpdir/T.md"; then
  ok "multi-line payload for a BRAND-NEW item still works (the handback seam shape)"
else
  bad "guard is too broad: it refused a multi-line payload for a new item: $(head -3 "$tmpdir/out9")"
fi

# --- 10. ...and onto an existing SINGLE-LINE item it is legal too ------------------
# bbb2 has no continuation lines, so growing it into a wrapped item strands nothing.
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >"$tmpdir/out10" 2>&1
{"updates": [{"id": "bbb2", "line": "- [ ] **beta item** now wrapped <!-- id:bbb2 -->\n      newly added continuation"}]}
JSON
if grep -q 'newly added continuation' "$tmpdir/T.md" \
   && [[ "$(grep -c 'beta item' "$tmpdir/T.md")" -eq 1 ]]; then
  ok "multi-line payload onto a SINGLE-LINE item still works (nothing to strand)"
else
  bad "guard is too broad: single-line -> wrapped was refused: $(head -3 "$tmpdir/out10")"
fi

echo
echo "md-merge multi-line \"line\" guard (id:f833): $pass passed, $fail failed"
[[ $fail -eq 0 ]]
