#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:1447, filed against
# `tools/ledger-continuations.py`. Failures always count.
#
# id:1447 -- id:9ce0 replaced a hardcoded `REFUSE_IDS` with a computed cited-body
# predicate, but anchored the union verdict at FILE level. That is wrong in both
# directions at once, and the two directions are NOT symmetric:
#
#   LOUD and safe: every regex in a file that merely names a ledger counted as a search
#   over ledger text, because static extraction alone cannot say which regex is applied to
#   what the file read. 18 restored continuation lines drew one refusal naming dozens of
#   sites, most of them patterns a reader applies to its OWN source.
#
#   SILENT and unsafe: a file that reads `docs/ledger-notes/` in ONE function and the
#   ledger ALONE in another was CLEARED by the first. That is why reverting
#   `relay/scripts/roadmap-lint.sh`'s heredoc hop-table parser did NOT flip its verdict --
#   two unrelated notes reads elsewhere in the same file kept it cleared. On 2026-09-01
#   that class cost a peer repo four id markers (89f9, a5b6, ba07, ed26).
#
# The fix is construct-to-corpus dataflow: every construct carries the CORPUS of the text
# it is applied to (ledger / union / other / untraced), so union clears a construct only
# when that construct's OWN subject reads the union.
#
# Contract asserted here:
#   G. THE FALSE CLEAR. A file with one notes-reading function and one ledger-only
#      function is REFUSED for the second, not cleared by the first. This is the whole
#      item; the fixture is the roadmap-lint shape reduced to two functions.
#   H. THE NARROWING. A pattern whose subject demonstrably reads a NON-ledger file is
#      cleared and does not appear in the refusal at all.
#   I. Every named site carries the corpus its subject traced to, so a caller can tell an
#      evidenced consumer from an unresolved trace without re-deriving either.
#   J. An UNTRACED subject still REFUSES. This pass may only ever remove a refusal it can
#      justify, never add a clear it cannot, so the safe direction is preserved.
#   K. A heredoc program's subject traces through argv to what the host shell handed it --
#      the shape of the motivating consumer, a python parser inside a shell function.
#   L. NO NAMED EXCLUSION FOR THE INSTRUMENT and no per-repo branch. The shrink tool is
#      the single largest both-reader on this tree; it is resolved construct-level like
#      any other file, never by naming itself, which would be an id-keyed list wearing a
#      path (the id:cb3e shape id:9ce0 removed).
#
# fails-against: the defect and its fix land in the same commit as this spec, so there is
# no ancestor revision to check out; the negative case is a mutation of the shipped tool.
# It re-instates the id:9ce0 file-level union skip verbatim -- `if reads_notes(text):
# continue` right after the flow is built -- which is precisely the state being repaired.
# Case (G) is the first assertion that fires against it, and (G) is a `fail()` that exits,
# so it is also the last FAIL line emitted. The mutation touches one relative path under
# its own cwd.
# fails-against-mutation: sed -i 's|^            flow = FileFlow(rel, text)$|            flow = FileFlow(rel, text)\n            if reads_notes(text):\n                continue|' tools/ledger-continuations.py
# fails-against-assertion: case G: the ledger-only function must be REFUSED
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-continuations.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "setup: ledger-continuations.py not found at $TOOL"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------ the fixture ledger
# Three items, each body carrying ONE phrase that appears nowhere else in the ledger, so
# "does a reader still find this after the move" has an unambiguous answer.
mkdir -p "$TMP/tree/relay/scripts" "$TMP/tree/docs/ledger-notes"
cat > "$TMP/tree/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue

- [ ] **Read only by the ledger-only half of a notes-reading file.** <!-- id:cc01 -->
  - detail: the marker PHRASE-LEDGER-ONLY-HALF sits in this continuation line only.
- [ ] **Read only through the ledger+notes union.** <!-- id:cc02 -->
  - detail: the marker PHRASE-UNION-HALF sits in this continuation line only.
- [ ] **Named in a pattern applied to a sibling JS file, never to the ledger.** <!-- id:cc03 -->
  - detail: the marker PHRASE-OTHER-CORPUS sits in this continuation line only.
- [ ] **Read by a heredoc program handed the ledger on its command line.** <!-- id:cc04 -->
  - detail: the marker PHRASE-HEREDOC-ARGV sits in this continuation line only.
EOF

# ------------------------------------------------------------------- the reader set
# ONE FILE, THREE FUNCTIONS. This is the id:9ce0 false clear in miniature: under file-level
# anchoring the notes read in `check_union` cleared the whole file, `check_ledger_only`
# included. NOTHING here is registered with the tool -- it must find and separate these by
# walking the root.
cat > "$TMP/tree/relay/scripts/two_halves.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

check_union() {
  local p="$1"
  cat "$p" "$(dirname "$p")/docs/ledger-notes"/*.md | grep -q 'PHRASE-UNION-HALF'
}

check_ledger_only() {
  local p="$1"
  grep -q 'PHRASE-LEDGER-ONLY-HALF' "$p"
}

check_other_corpus() {
  local js="$ROOT/relay/scripts/relay-loop.js"
  grep -q 'PHRASE-OTHER-CORPUS' "$js"
}

roadmap="$ROOT/ROADMAP.md"
check_union "$roadmap"
check_ledger_only "$roadmap"
check_other_corpus
EOF

# A heredoc program handed the ledger on its command line: the motivating consumer's shape.
cat > "$TMP/tree/relay/scripts/heredoc_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
parse() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
for line in text.split('\n'):
    if re.search(r'PHRASE-HEREDOC-ARGV', line):
        print(line)
PY
}
roadmap="$ROOT/ROADMAP.md"
parse "$roadmap"
EOF

run() { python3 "$TOOL" --file ROADMAP.md --root "$1" --dry-run 2>&1; }
out="$(run "$TMP/tree")" || fail "setup: the tool exited non-zero on the fixture tree"

# Every consumer below reads from a HERE-STRING, never from a pipe: `producer | grep -q`
# lets SIGPIPE on the producer become the pipeline's status under `set -o pipefail`
# (id:81d5), and `tests/lint-pipefail-sigpipe.py` rejects that shape with no exemptions.

# --- (G) THE FALSE CLEAR ------------------------------------------------------------
cc01="$(grep -A8 'id:cc01' <<<"$out" || true)"
[[ -n "$cc01" ]] || \
  fail "case G: the ledger-only function must be REFUSED even though the same file reads the notes elsewhere"
grep -q 'two_halves.sh:' <<<"$cc01" || \
  fail "case G2: the id:cc01 refusal must name relay/scripts/two_halves.sh"
grep -q 'PHRASE-LEDGER-ONLY-HALF' <<<"$cc01" || \
  fail "case G3: the id:cc01 refusal must quote the consumer pattern that matched"
pass "(G) a ledger-only construct refuses despite a notes-reading sibling in the same file"

# --- (H) THE NARROWING ---------------------------------------------------------------
if grep -q 'id:cc03' <<<"$out"; then
  fail "case H: a pattern whose subject reads a sibling .js file must be cleared, not named"
fi
grep -qE '^patterns cleared \(non-ledger\)    : [1-9]' <<<"$out" || \
  fail "case H2: the cleared-as-non-ledger count must be non-zero -- the narrowing narrows nothing"
pass "(H) a construct whose subject reads a non-ledger file is cleared"

# --- (I) EVERY SITE CARRIES ITS CORPUS ----------------------------------------------
grep -q '\[ledger\] relay/scripts/two_halves.sh' <<<"$cc01" || \
  fail "case I: each named site must carry the corpus its subject traced to, e.g. [ledger]"
grep -qE 'ledger-traced, [0-9]+ untraced-subject' <<<"$out" || \
  fail "case I2: the refusal header must split the sites into ledger-traced and untraced"
pass "(I) named sites carry their corpus and the header splits the two kinds"

# --- (J) AN UNTRACED SUBJECT STILL REFUSES ------------------------------------------
# `grep -q PAT "$2"` in a file that also reads a ledger: the operand is a positional this
# pass cannot resolve, so the subject is unexplained. Unexplained must refuse.
cat > "$TMP/tree/relay/scripts/untraced_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ledger="$1/ROADMAP.md"
wc -l < "$ledger"
grep -q 'PHRASE-OTHER-CORPUS' "$2"
EOF
out2="$(run "$TMP/tree")" || fail "setup: the tool exited non-zero after adding the untraced reader"
grep -q 'id:cc03' <<<"$out2" || \
  fail "case J: an UNTRACED subject must still refuse -- clearing what it cannot explain is the unsafe direction"
grep -q '\[untraced\] relay/scripts/untraced_reader.sh' <<<"$out2" || \
  fail "case J2: an untraced site must be named AND tagged untraced, not merged with the evidenced ones"
pass "(J) an unexplained subject refuses and is tagged untraced"

# --- (K) HEREDOC ARGV ----------------------------------------------------------------
cc04="$(grep -A8 'id:cc04' <<<"$out" || true)"
grep -q '\[ledger\] relay/scripts/heredoc_reader.sh' <<<"$cc04" || \
  fail "case K: a heredoc program's subject must trace through argv to the ledger the host shell handed it"
pass "(K) heredoc argv binding traces to the ledger"

# --- (L) NO NAMED EXCLUSION FOR THE INSTRUMENT --------------------------------------
# The refusal machinery must not know its own name, nor any other consumer's, nor which
# repo it is in. `find_readers` / `corpus_of` / `corpus_at` decide from data alone.
if grep -nE '^\s*(if|elif)\b.*(ledger-continuations|ledger-shrink|roadmap-lint|todo-conformance|orphan-scan)' "$TOOL"; then
  fail "case L: a consumer path is branched on in the source -- that is an id-keyed list wearing a path"
fi
if grep -nE '^[A-Z_]*(EXCLUDE|SKIP_FILES|REFUSE_IDS|ALLOW)[A-Z_]*[[:space:]]*=[[:space:]]*[\[{(]' "$TOOL"; then
  fail "case L2: a path or id exclusion list is back in the tool"
fi
pass "(L) no named exclusion and no per-repo branch in the source"

echo "OK: tests/test_construct_corpus_dataflow_1447.sh"
