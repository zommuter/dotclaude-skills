#!/usr/bin/env bash
# roadmap:e047
#
# RED SPEC for ROADMAP id:e047 -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# THE DEFECT. `SH_ASSIGN_RE` in `tools/ledger-continuations.py` matches a shell
# assignment's right-hand side within ONE line only -- its alternation is
# `"..."`, `'...'`, `$(...)` with no `)` crossing, or a bare run of non-space. A
# command substitution spread over a backslash-newline continuation is therefore
# truncated at the end of the first physical line, and every operand on the
# continuation line is invisible to the corpus trace.
#
# Reduced from the shape the note names verbatim:
#
#     outbullet=$(grep -rhF 'OUT of scope' "$ROADMAP" \
#                                          "$ROOT/docs/ledger-notes")
#
# The reader plainly reads the ledger UNION the notes, so relocating a body into
# `docs/ledger-notes/` cannot break it and it must be CLEARED. Today the notes operand
# vanishes, the construct traces to corpus `ledger`, and the block is REFUSED.
#
# WHY THE UNSAFE DIRECTION IS THE POINT. Observed here the truncation removes a NOTES
# operand and so pushes toward a loud false refusal. The same parser is used for the
# other direction, where a truncated rhs makes a genuinely ledger-only read look
# union-anchored -- a MISSED UNION, which `tools/ledger-continuations.py:208-211` calls
# the one place a mistake is unsafe. The item is filed on the parser lying about what a
# read touched, not on the noise.
#
# Hermetic: mktemp only, no live ledger, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-continuations.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "setup: ledger-continuations.py not found at $TOOL"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/tree/relay/scripts" "$TMP/tree/docs/ledger-notes"

cat > "$TMP/tree/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue

- [ ] **Body read by a continuation-spanning union read.** <!-- id:cc03 -->
  - detail: PHRASE-CONT-OPERAND sits in this continuation line only.
- [ ] **Body read by a single-line union read (the control).** <!-- id:cc04 -->
  - detail: PHRASE-ONELINE-OPERAND sits in this continuation line only.
EOF

# The subject of interest: the notes operand sits on the CONTINUATION line.
cat > "$TMP/tree/relay/scripts/cont_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check_cont() {
  local hits
  hits=$(grep -rhF 'PHRASE-CONT-OPERAND' "$ROOT/ROADMAP.md" \
                                         "$ROOT/docs/ledger-notes")
  [[ -n "$hits" ]]
}
check_cont
EOF

# The positive control: the identical read written on ONE line. It is cleared today, and
# it must STILL be cleared after the fix -- a repair that widened everything into `union`
# would pass case (A) while destroying the predicate, so the control is what makes (A)
# mean anything.
cat > "$TMP/tree/relay/scripts/oneline_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check_oneline() {
  local hits
  hits=$(grep -rhF 'PHRASE-ONELINE-OPERAND' "$ROOT/ROADMAP.md" "$ROOT/docs/ledger-notes")
  [[ -n "$hits" ]]
}
check_oneline
EOF

run() { python3 "$TOOL" --file ROADMAP.md --root "$TMP/tree" --dry-run 2>&1; }
out="$(run)" || fail "setup: the tool exited non-zero on the fixture tree"

# Consumers read from a HERE-STRING, never a pipe: `producer | grep -q` lets SIGPIPE on the
# producer become the pipeline's status under `set -o pipefail` (id:81d5), and
# `tests/lint-pipefail-sigpipe.py` rejects that shape with no exemptions.

# --- (A) THE DEFECT -------------------------------------------------------------------
if grep -q 'id:cc03' <<<"$out"; then
  fail "(A) the continuation-spanning union read was traced as ledger-only and refused id:cc03 -- SH_ASSIGN_RE truncated the rhs at the end of the first physical line, so the docs/ledger-notes operand was never seen"
fi
pass "(A) a union read whose notes operand sits on a continuation line is cleared"

# --- (B) THE CONTROL ------------------------------------------------------------------
if grep -q 'id:cc04' <<<"$out"; then
  fail "(B) the single-line union read was refused -- the fix must not regress the shape that already works"
fi
pass "(B) the single-line union read stays cleared"

# --- (C) THE READ IS COUNTED AS UNION, NOT MERELY ABSENT FROM THE REFUSAL --------------
# A parser that stopped extracting the construct altogether would also satisfy (A), and
# would be a silent LOSS of a consumer rather than a fix. Both readers must be counted in
# the union-anchored tally.
uni="$(grep -oE '^union-anchored readers \(notes\)[ ]*: [0-9]+' <<<"$out" | grep -oE '[0-9]+$' || true)"
[[ -n "$uni" ]] || fail "(C) setup: could not read the union-anchored reader count from the report"
(( uni >= 2 )) || \
  fail "(C) union-anchored readers is $uni, expected >= 2 -- the continuation-spanning read must be COUNTED as a notes reader, not merely dropped from the refusal"
pass "(C) both union readers are counted as notes-anchored ($uni)"

echo "ALL PASS: id:e047 multi-line shell assignment rhs is parsed whole"
