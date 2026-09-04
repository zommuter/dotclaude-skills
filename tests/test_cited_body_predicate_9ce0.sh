#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:9ce0, filed against
# `tools/ledger-continuations.py`. Failures always count.
#
# id:9ce0 -- the tool's `cited-body` refusal used to be a hand-maintained `REFUSE_IDS`
# dict of `id -> reason`. That dict WAS the mechanism, so emptying it (2026-09-03, when
# its single entry went stale) left `REFUSED cited-body` printing 0 unconditionally, for
# every ledger, forever: a check that structurally cannot fail (the id:0b70 vacuous-check
# class). An id-keyed list is also the wrong SHAPE -- the id:cb3e grandfathering trap --
# because it cannot know about a consumer minted tomorrow.
#
# Contract asserted here:
#   A. `REFUSED cited-body` is COMPUTED from the live consumer set under `--root`. The same
#      ledger scanned against a reader set that greps its bodies refuses; scanned against a
#      root with no readers at all it relocates. A constant cannot do both.
#   B. A refusal NAMES the consumer's `file:line` and the pattern, so it can be acted on.
#   C. The one-level constant fold works: a reader whose pattern is a shell variable with a
#      single literal assignment is ANALYSED, not written off. Reporting that unanalysable
#      would be a false loud failure over the most important readers in the set.
#   D. A UNION-ANCHORED reader (one that also reads `docs/ledger-notes/`) does NOT refuse:
#      relocation cannot break it, which is the whole reason the original `id:6b35` entry
#      was correctly liftable.
#   E. A reader whose pattern is composed at run time is reported UNANALYSABLE by name, and
#      never silently scored "no match" -- silent success is the failure being repaired.
#   F. No id-keyed or token-keyed allow list survives in the source.
#
# fails-against: the defect and its fix land in the same commit as this spec, so there is no
# ancestor revision to check out; the negative case is a mutation of the shipped tool. It
# replaces the computed reader set with an empty one -- which is EXACTLY the post-2026-09-03
# state being repaired, a live `cited-body` counter wired to nothing. Assertions (A) and (E)
# both fire against it; `fail()` exits on the first, so the declared assertion is (A), the
# refusal count. The mutation touches only a relative path under its own cwd.
# fails-against-mutation: sed -i 's/^    readers = find_readers(root)$/    readers = {"ledger_only": [], "union": [], "patterns": [], "unanalysable": []}/' tools/ledger-continuations.py
# fails-against-assertion: case A: cited-body must be COMPUTED, expected 2 refusals from the fixture reader set
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-continuations.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "setup: ledger-continuations.py not found at $TOOL"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- the fixture ledger
# Four items. Each body carries ONE distinctive phrase that appears nowhere else in the
# ledger, so "does a reader still find this after the move" has an unambiguous answer.
mk_ledger() {
  mkdir -p "$1"
  cat > "$1/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue

- [ ] **An item a plain test greps by body text.** <!-- id:aa01 -->
  - detail: the marker PHRASE-READ-BY-A-TEST sits in this continuation line only.
- [ ] **An item whose body nothing anywhere reads.** <!-- id:aa02 -->
  - detail: ordinary prose about an ordinary queue entry, cited by nobody.
- [ ] **An item read only through the ledger+notes union.** <!-- id:aa03 -->
  - detail: the marker PHRASE-IN-A-NOTE-READER sits in this continuation line only.
- [ ] **An item greped through a single-assignment variable.** <!-- id:aa04 -->
  - detail: the marker PHRASE-VIA-CONST-VAR sits in this continuation line only.
EOF
}

mk_ledger "$TMP/withreaders"
mk_ledger "$TMP/noreaders"

# ------------------------------------------------------------------ the reader set
# NOTHING here is registered with the tool. The tool must FIND these by walking the root,
# which is the point: a hand-named consumer list is the shape id:9ce0 bans.
mkdir -p "$TMP/withreaders/tests" "$TMP/withreaders/tools" "$TMP/withreaders/relay/scripts"

# (1) ledger-only reader, literal pattern -> must refuse id:aa01
cat > "$TMP/withreaders/tests/fixture_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LEDGER="$1/ROADMAP.md"
grep -q 'PHRASE-READ-BY-A-TEST' "$LEDGER" || exit 1
EOF

# (2) union-anchored reader -> must NOT refuse id:aa03
cat > "$TMP/withreaders/tools/union_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LEDGER="$1/ROADMAP.md"
NOTES="$1/docs/ledger-notes"
cat "$LEDGER" "$NOTES"/*.md 2>/dev/null | grep -q 'PHRASE-IN-A-NOTE-READER' || exit 1
EOF

# (3) ledger-only reader whose pattern is a variable with ONE literal assignment.
# The one-level constant fold must resolve it -> must refuse id:aa04.
cat > "$TMP/withreaders/relay/scripts/fold_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
FOLD_PAT='PHRASE-VIA-CONST-VAR'
LEDGER="$1/ROADMAP.md"
grep -q "${FOLD_PAT}" "$LEDGER" || exit 1
EOF

# (4) ledger-only reader whose pattern is genuinely composed at run time -> UNANALYSABLE
cat > "$TMP/withreaders/relay/scripts/runtime_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LEDGER="$1/ROADMAP.md"
grep -q "$2" "$LEDGER" || exit 1
EOF

run() { python3 "$TOOL" --file ROADMAP.md --root "$1" --dry-run 2>&1; }

with="$(run "$TMP/withreaders")"  || fail "setup: the tool exited non-zero on the reader fixture"
without="$(run "$TMP/noreaders")" || fail "setup: the tool exited non-zero on the reader-free fixture"

# Every consumer below reads from a HERE-STRING, never from a pipe: `producer | grep -q`
# lets SIGPIPE on the producer become the pipeline's status under `set -o pipefail`
# (id:81d5), and `tests/lint-pipefail-sigpipe.py` rejects that shape with no exemptions.

# --- (A) the counter is computed, not constant -------------------------------------
n_with="$(sed -n 's/^REFUSED cited-body *: *//p' <<<"$with")"
n_without="$(sed -n 's/^REFUSED cited-body *: *//p' <<<"$without")"
[[ "$n_with" == "2" ]] || \
  fail "case A: cited-body must be COMPUTED, expected 2 refusals from the fixture reader set (got '$n_with')"
[[ "$n_without" == "0" ]] || \
  fail "case A2: the SAME ledger under a root with no readers must relocate, got '$n_without' refusals"
grep -q '^items with a continuation block : 4' <<<"$without" || \
  fail "case A3: all four blocks must relocate when nothing reads them"
pass "(A) cited-body varies with the live consumer set: 2 with readers, 0 without"

# --- (B) the refusal names the consumer -------------------------------------------
aa01="$(grep 'fixture_reader.sh:' < <(grep -A20 'id:aa01' <<<"$with") || true)"
[[ -n "$aa01" ]] || \
  fail "case B: the id:aa01 refusal must name tests/fixture_reader.sh with a line number"
grep -q 'PHRASE-READ-BY-A-TEST' <<<"$aa01" || \
  fail "case B2: the id:aa01 refusal must quote the consumer pattern that matched"
grep -qE 'fixture_reader\.sh:[0-9]+' <<<"$aa01" || \
  fail "case B3: the consumer must be named as file:line, not as a bare filename"
pass "(B) refusal names the consumer file:line and its pattern"

# --- (C) the one-level constant fold ----------------------------------------------
grep -q 'fold_reader.sh:' < <(grep -A20 'id:aa04' <<<"$with") || \
  fail "case C: a pattern held in a single-assignment variable must be FOLDED and refused"
# The UNANALYSABLE block only, bounded by the next counter line: a `-A<n>` window bleeds
# into the refusal list, which legitimately names the same file.
unan="$(sed -n '/^UNANALYSABLE reader constructs/,/^REFUSED /p' <<<"$with")"
if grep -q 'fold_reader.sh' <<<"$unan"; then
  fail "case C2: a foldable variable pattern must not be reported unanalysable"
fi
pass "(C) one-level constant fold resolves a single-literal-assignment pattern"

# --- (D) a union-anchored reader does not refuse ----------------------------------
if grep -q 'id:aa03' <<<"$with"; then
  fail "case D: a reader that also reads docs/ledger-notes must NOT refuse -- relocation cannot break it"
fi
grep -q '^union-anchored readers (notes)   : 1' <<<"$with" || \
  fail "case D2: the union-anchored reader must be counted, not merely ignored"
pass "(D) union-anchored reader is counted and refuses nothing"

# --- (E) runtime-composed patterns fail LOUD --------------------------------------
grep -q 'runtime_reader.sh:.*run time' <<<"$unan" || \
  fail "case E: a runtime-composed reader pattern must be reported UNANALYSABLE by name"
grep -qE '^UNANALYSABLE reader constructs   : [1-9]' <<<"$with" || \
  fail "case E2: the UNANALYSABLE counter must be non-zero when a reader cannot be analysed"
pass "(E) runtime-composed reader reported UNANALYSABLE by name"

# --- (F) no id-keyed allow list survives ------------------------------------------
if grep -nE '^[A-Z_]*REFUSE_IDS[A-Z_]*[[:space:]]*=' "$TOOL"; then
  fail "case F: an id-keyed refusal list is back in the tool -- that is the id:cb3e shape id:9ce0 removed"
fi
pass "(F) no id-keyed refusal list in the source"

echo "OK: tests/test_cited_body_predicate_9ce0.sh"
