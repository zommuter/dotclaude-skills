#!/usr/bin/env bash
# NO `# roadmap:` header on purpose — id:5d7e is a TODO defect-fix, not an open ROADMAP
# item, so these failures always count (CLAUDE.md §Testing).
#
# Defect (id:5d7e, found 2026-08-19 within hours of id:f26d shipping regex_sub/insert_*):
# `md-merge.py update-ids` SILENTLY DROPS all but one update when several target the SAME
# id in one payload, and still exits 0.
#
# Two independent mechanisms, both silent:
#   1. Cross-class: ops are bucketed into replace_map / append_map / regex_sub_map and
#      applied through an if/elif/elif chain, so at most ONE class runs per id.
#   2. Within-class: each bucket is a dict keyed by id, so a second op of the same class
#      overwrites the first.
#
# Observed live: a 4-update payload (2 regex_sub ticks + 2 appends, two ids) applied only
# the appends. Both checkboxes stayed `[ ]` while their rationale annotations landed —
# producing ledger lines that READ as done-and-annotated with an open checkbox.
#
# This matters out of proportion to the ergonomics because md-merge.py is THE mandated
# flock'd write path for every shared non-union ledger (global CLAUDE.md §"Tool choice for
# file edits", tier 1). A trusted writer that reports success while discarding half the
# request is the id:4347 silent-no-op class in the worst possible place.
#
# Ratified semantic: COMPOSE all ops for an id, in payload order. (The alternative —
# refuse loudly — was considered; composing is what a caller means and loses nothing.)
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
- [ ] [ROUTINE] **alpha item** some prose <!-- id:aaa1 -->
- [ ] [ROUTINE] **beta item** other prose <!-- id:bbb2 -->
EOF
}

line_of() { grep -h "id:$1 -->" "$tmpdir/T.md"; }
box_of()  { grep -o '^- \[.\]' <<< "$(line_of "$1")"; }

# --- 1. THE DEFECT: regex_sub + append on the SAME id, one payload -----------------
fixture
set +e
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >"$tmpdir/out1" 2>&1
{"updates": [
  {"id": "aaa1", "regex_sub": {"pattern": "^- \\[ \\]", "repl": "- [x]"}},
  {"id": "aaa1", "append": " — done, verified."}
]}
JSON
rc=$?
set -e
if [[ $rc -eq 0 ]]; then ok "same-id regex_sub+append exits 0"
else bad "expected exit 0, got $rc: $(head -3 "$tmpdir/out1")"; fi

if [[ "$(box_of aaa1)" == "- [x]" ]]; then
  ok "the regex_sub applied (checkbox ticked) despite a same-id append in the payload"
else
  bad "SILENT DROP: checkbox is $(box_of aaa1), expected - [x] — the regex_sub was discarded"
fi
if grep -q "done, verified." <<< "$(line_of aaa1)"; then
  ok "the append also applied (both ops composed, not one-wins)"
else
  bad "the append was discarded"
fi

# --- 2. reverse order — append first, then regex_sub -------------------------------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [
  {"id": "aaa1", "append": " — annotated first."},
  {"id": "aaa1", "regex_sub": {"pattern": "^- \\[ \\]", "repl": "- [x]"}}
]}
JSON
if [[ "$(box_of aaa1)" == "- [x]" ]] && grep -q "annotated first." <<< "$(line_of aaa1)"; then
  ok "order-independent: append-then-regex_sub also composes both"
else
  bad "reverse order lost an op: box=$(box_of aaa1) line=$(line_of aaa1 | cut -c1-80)"
fi

# --- 3. within-class: TWO appends for the same id ----------------------------------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [
  {"id": "bbb2", "append": " FIRST."},
  {"id": "bbb2", "append": " SECOND."}
]}
JSON
if grep -q "FIRST." <<< "$(line_of bbb2)" && grep -q "SECOND." <<< "$(line_of bbb2)"; then
  ok "two same-class appends both apply, in payload order"
else
  bad "a same-class duplicate was silently overwritten: $(line_of bbb2 | cut -c1-100)"
fi

# --- 4. NO REGRESSION: different ids in one payload still both apply ---------------
fixture
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >/dev/null 2>&1
{"updates": [
  {"id": "aaa1", "regex_sub": {"pattern": "^- \\[ \\]", "repl": "- [x]"}},
  {"id": "bbb2", "append": " — beta annotated."}
]}
JSON
if [[ "$(box_of aaa1)" == "- [x]" ]] && grep -q "beta annotated." <<< "$(line_of bbb2)"; then
  ok "distinct-id payload unaffected (no regression on the normal path)"
else
  bad "regression on distinct ids: aaa1=$(box_of aaa1) bbb2=$(line_of bbb2 | cut -c1-60)"
fi

# --- 5. the id:6059 multi-marker guard still fires on the COMPOSED result ----------
# Composing must not open a hole in the write-side marker guard: an append that injects a
# second anchored id marker has to be refused, and refused on the FINAL text.
fixture
set +e
python3 "$MD" update-ids --file "$tmpdir/T.md" <<'JSON' >"$tmpdir/out5" 2>&1
{"updates": [
  {"id": "aaa1", "regex_sub": {"pattern": "^- \\[ \\]", "repl": "- [x]"}},
  {"id": "aaa1", "append": " see <!-- id:9999 --> too"}
]}
JSON
rc5=$?
set -e
if [[ $rc5 -ne 0 ]]; then ok "composed result that gains a 2nd id marker is REFUSED (id:6059 intact)"
else bad "expected non-zero for a composed 2-marker line, got 0"; fi
if [[ "$(box_of aaa1)" == "- [ ]" ]]; then
  ok "refusal left the file untouched (no partial write)"
else
  bad "partial write on refusal: box=$(box_of aaa1)"
fi

echo "  ---- $pass passed, $fail failed"
[[ $fail -eq 0 ]]
