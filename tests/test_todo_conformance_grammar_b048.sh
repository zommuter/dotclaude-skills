#!/usr/bin/env bash
# roadmap:b048
#
# WHAT IT PINS. The owner's ledger LINE GRAMMAR (stated 2026-09-02, SUPERSEDING the
# block-size reading id:b048 was originally scoped as). A line in TODO.md / ROADMAP.md is
# valid iff it is exactly one of three things:
#   1. BLANK;
#   2. a HEADING -- at most ~200 chars, followed by an empty line, opening a NON-EMPTY
#      section, and never the last thing in the file;
#   3. an ITEM -- `- [ ]/[x]`, an optional lane tag, a title of at most ~200 chars, zero or
#      more typed-edge comments, then the item's own anchored id marker and END OF LINE.
# There are NO continuation lines: the prose lives in `docs/ledger-notes/<id>.md`, so an
# indented line is INVALID rather than "a large block".
#
# The cases below are the grammar's EDGES, which is where a validator like this goes wrong:
# a heading at EOF, a heading followed immediately by another heading, a trailing space
# after the id marker, a typed edge AFTER the id marker, several typed edges BEFORE it, and
# an indented continuation.
#
# Two properties matter as much as the classification and are pinned separately:
#   * REPORT-ONLY. 395 of 1080 TODO.md lines fail this today. An ERROR would wedge the
#     repo, so no `grammar-*` class may ever fail `--strict` (case (h)).
#   * THE ID PATTERN IS CONFIGURABLE (case (i)). The owner flagged that ids may change
#     shape when cartulary lands; a hardcoded `[0-9a-f]{4}` would silently report every
#     item as `grammar-item-no-id` on that day.
#
# fails-against: the guard and this spec land in the same commit, so there is no ancestor
# revision to check out; the negative case is a mutation of the shipped script. It restores
# the LENIENT end anchor (`-->[[:space:]]*$`), which is the shape a validator naturally
# gets wrong -- "nothing after the id marker" then silently permits trailing whitespace.
# That is the only assertion it breaks, hence also the last FAIL line it produces.
# fails-against-mutation: sed -i 's/=~ ${GRAMMAR_ID_MARKER_RE}\$ \]\]; then/=~ ${GRAMMAR_ID_MARKER_RE}[[:space:]]*$ ]]; then/' relay/scripts/todo-conformance.sh
# fails-against-assertion: case (d) TRAILING SPACE
#
# Hermetic: every fixture is synthesised under a mktemp -d. The live TODO.md/ROADMAP.md are
# never read, no ~/.claude write, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# The length ratchet is deliberately INERT here (no baseline file): this file specs the
# GRAMMAR, and a length finding sharing the output would make the exit-code assertions
# ambiguous. Its "INERT" notice goes to stderr, which is captured separately.
NOBASE="$tmp/no-such-baseline.txt"

# run <flags...> -- capture stdout/stderr/rc; `out.txt` keeps only the grammar findings, so
# an unrelated rule of this linter (shape-prose, dep-prose-untyped) cannot be asserted here
# by accident. `raw.txt` keeps everything for the diagnostics.
run() {
  set +e
  LENGTH_BASELINE="$NOBASE" "$SH" "$@" > "$tmp/raw.txt" 2> "$tmp/err.txt"
  rc=$?
  set -e
  grep '^grammar-' "$tmp/raw.txt" > "$tmp/out.txt" || true
}

# has <class> <lineno> -- the finding must be exactly this class on exactly this line.
has() {
  grep -qP "^$1[^\t]*\t$2\t" "$tmp/out.txt" \
    || report "$3
  expected '$1' on line $2. grammar findings were:
$(cat "$tmp/out.txt")"
}

# ---------------------------------------------------------------------------
# (a) A fully CONFORMING ledger is silent, and stays silent under --strict.
#     Includes the valid multi-edge shape: several typed edges BEFORE the id marker.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/a"
cat > "$tmp/a/TODO.md" <<'EOF'
# TODO

- [ ] [ROUTINE] **A short conforming title** <!-- id:aa01 -->
- [x] [HARD] A closed item with no bold run <!-- id:aa02 -->
- [ ] [ROUTINE] **Several typed edges, all before the id** <!-- gated-on:aa01 --> <!-- children:aa02 --> <!-- routed:aa03 --> <!-- answer-src:owner --> <!-- id:aa04 -->
EOF

run --strict "$tmp/a/TODO.md"
[[ ! -s "$tmp/out.txt" ]] \
  || report "case (a) CONFORMING: a valid ledger must produce NO grammar finding. got:
$(cat "$tmp/out.txt")"
(( rc == 0 )) \
  || report "case (a) CONFORMING: a valid ledger must exit 0 under --strict (got rc=$rc). raw:
$(cat "$tmp/raw.txt")"

# ---------------------------------------------------------------------------
# (b) HEADING EDGES. Three distinct structural failures, each reported against the
#     offending HEADING's own line number even though the rule is multi-line.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/b"
cat > "$tmp/b/TODO.md" <<'EOF'
# TODO
## Immediately another heading

## Empty section

## Next section

- [ ] [ROUTINE] **An item so the last section is not empty** <!-- id:bb01 -->

## Heading at EOF
EOF

run "$tmp/b/TODO.md"
has grammar-heading-no-blank 1 "case (b) HEADING: a heading not followed by an empty line must be reported"
has grammar-heading-empty-sec 2 "case (b) HEADING: a heading whose next non-blank line is another heading opens an EMPTY section"
has grammar-heading-empty-sec 4 "case (b) HEADING: the second empty section must be reported too"
has grammar-heading-eof 10 "case (b) HEADING: a heading that is the last non-blank line of the file opens no section"
grep -qP '^grammar-[^\t]*\t6\t' "$tmp/out.txt" \
  && report "case (b) HEADING: the well-formed heading on line 6 (blank after, non-empty section) must be silent"

# ---------------------------------------------------------------------------
# (c) A typed edge AFTER the id marker is invalid -- the order is fixed, the id marker
#     ENDS the line. This is the shape a lenient 'contains an id' check accepts.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/c"
cat > "$tmp/c/TODO.md" <<'EOF'
# TODO

- [ ] [ROUTINE] **Edge after the id marker** <!-- id:cc01 --> <!-- gated-on:cc02 -->
EOF

run "$tmp/c/TODO.md"
has grammar-item-edge-after-id 3 "case (c) EDGE AFTER ID: a typed edge following the id marker must be reported"

# ---------------------------------------------------------------------------
# (d) A TRAILING SPACE after the id marker is invalid. "Nothing after the id marker" is
#     literal; whitespace is the reading a validator most easily gets wrong, and it is
#     the case the negative mutation for this file restores.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/d"
{
  echo '# TODO'
  echo
  printf -- '- [ ] [ROUTINE] **Trailing space after the marker** <!-- id:dd01 --> \n'
} > "$tmp/d/TODO.md"

run "$tmp/d/TODO.md"
has grammar-item-after-id 3 "case (d) TRAILING SPACE: a space after the id marker must be reported -- 'nothing after the id marker' is literal"

# ---------------------------------------------------------------------------
# (e) An INDENTED CONTINUATION line is invalid outright. Not "a big block": under this
#     grammar the body does not live in the ledger at all.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/e"
cat > "$tmp/e/TODO.md" <<'EOF'
# TODO

- [ ] [ROUTINE] **An item with a body** <!-- id:ee01 -->
  - **Acceptance**: this clause belongs in docs/ledger-notes/ee01.md, not here.
EOF

run "$tmp/e/TODO.md"
has grammar-continuation 4 "case (e) CONTINUATION: an indented line must be reported as invalid, not tolerated as an item body"

# ---------------------------------------------------------------------------
# (f) An item with NO anchored id marker. `- [x]` deliberately, so the OLDER missing-id
#     rule (open items only) cannot supply the finding this case is asserting.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/f"
cat > "$tmp/f/TODO.md" <<'EOF'
# TODO

- [x] [ROUTINE] **A closed item that never got an id**
EOF

run "$tmp/f/TODO.md"
has grammar-item-no-id 3 "case (f) NO ID: an item without its own anchored id marker must be reported"

# ---------------------------------------------------------------------------
# (g) TITLE LENGTH is a NAMED, CONFIGURABLE approximation, not a ratified constant: the
#     same line must flip from reported to silent when the knob moves. Pinning the
#     mechanism rather than the number is the point -- the exact figure is still open.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/g"
long_title="$(for i in $(seq 1 12); do printf 'a title fragment number %02d, ' "$i"; done)"
{
  echo '# TODO'
  echo
  printf -- '- [ ] [ROUTINE] **%s** <!-- id:a101 -->\n' "$long_title"
} > "$tmp/g/TODO.md"

run "$tmp/g/TODO.md"
has grammar-item-title-long 3 "case (g) TITLE: a title over the default approximate maximum must be reported"
LEDGER_ITEM_TITLE_MAX=4000 run "$tmp/g/TODO.md"
unset LEDGER_ITEM_TITLE_MAX
grep -q '^grammar-item-title-long' "$tmp/out.txt" \
  && report "case (g) TITLE: with LEDGER_ITEM_TITLE_MAX raised the SAME line must go silent -- the figure is an approximation, so it must be a knob and not a constant"

# ---------------------------------------------------------------------------
# (h) REPORT-ONLY. Every violation this file can raise without tripping another rule,
#     in one file, must still exit 0 under --strict. Almost the whole corpus is
#     non-conforming today; an ERROR here would wedge the repo.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/h"
{
  echo '# TODO'
  echo '## No blank after the heading'
  echo
  printf -- '- [ ] [ROUTINE] **Trailing space** <!-- id:b101 --> \n'
  printf -- '- [ ] [ROUTINE] **Edge after id** <!-- id:b102 --> <!-- gated-on:b101 -->\n'
  echo '  a continuation line that this grammar does not allow'
  printf -- '- [ ] [ROUTINE] **%s** <!-- id:b103 -->\n' "$long_title"
} > "$tmp/h/TODO.md"

run --strict "$tmp/h/TODO.md"
(( rc == 0 )) \
  || report "case (h) REPORT-ONLY: no grammar class may fail --strict (got rc=$rc). raw:
$(cat "$tmp/raw.txt")"
# Deliberately 4, not the 5 this fixture emits: the negative case declared in the header
# neuters exactly one of them, and a count assertion that ALSO fired there would make this
# file's declared `fails-against-assertion` the first of two FAIL lines instead of the last
# (the tests/ rule: the declaration must match the LAST line a non-exiting accumulator
# emits). The guard's job is "the fixture was reached at all", which 4 still discharges.
(( $(wc -l < "$tmp/out.txt") >= 4 )) \
  || report "case (h) REPORT-ONLY: the fixture must actually produce the findings it is exiting 0 in spite of -- an unreached fixture proves nothing (id:a73c). got:
$(cat "$tmp/out.txt")"

# ---------------------------------------------------------------------------
# (i) THE ID PATTERN IS CONFIGURABLE. The owner flagged that ids may lengthen or change
#     shape when cartulary lands; with the class hardcoded, that day turns every item in
#     the fleet into `grammar-item-no-id`. Both directions are pinned: an 8-hex id is
#     conforming under the wider class, and the 4-hex spelling stops being one.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/i"
cat > "$tmp/i/TODO.md" <<'EOF'
# TODO

- [x] [ROUTINE] **An id in a future, longer shape** <!-- id:0123abcd -->
EOF

run "$tmp/i/TODO.md"
has grammar-item-no-id 3 "case (i) ID SHAPE: sanity -- an 8-hex id is NOT a valid id under the default 4-hex class, so the override below has something to prove"
LEDGER_ID_TOKEN_RE='[0-9a-f]{8}' run "$tmp/i/TODO.md"
grep -q '^grammar-item' "$tmp/out.txt" \
  && report "case (i) ID SHAPE: with LEDGER_ID_TOKEN_RE widened, the 8-hex item must be conforming. got:
$(cat "$tmp/out.txt")"
LEDGER_ID_TOKEN_RE='[0-9a-f]{8}' run "$tmp/a/TODO.md"
unset LEDGER_ID_TOKEN_RE
grep -q '^grammar-item-no-id' "$tmp/out.txt" \
  || report "case (i) ID SHAPE: the override must actually REPLACE the token class -- under an 8-hex class the 4-hex items must stop resolving. got:
$(cat "$tmp/out.txt")"

# ---------------------------------------------------------------------------
# (j) SCOPE. `--no-grammar` suppresses the rule, and `*.archive.md` is out of scope
#     entirely (id:2065), exactly like the length ratchet.
# ---------------------------------------------------------------------------
run --no-grammar "$tmp/h/TODO.md"
[[ ! -s "$tmp/out.txt" ]] \
  || report "case (j) SCOPE: --no-grammar must suppress every grammar finding. got:
$(cat "$tmp/out.txt")"

cp "$tmp/h/TODO.md" "$tmp/h/TODO.archive.md"
run "$tmp/h/TODO.archive.md"
[[ ! -s "$tmp/out.txt" ]] \
  || report "case (j) SCOPE: *.archive.md is out of scope for the grammar (id:2065). got:
$(cat "$tmp/out.txt")"

if (( fail )); then
  exit 1
fi
echo "PASS: todo-conformance.sh validates the b048 ledger LINE grammar (blank / heading / item), reports every edge -- heading at EOF, empty section, no blank after, trailing space and typed edge after the id marker, indented continuation -- with a configurable id token class and approximate title/heading maxima, and never escalates under --strict"
