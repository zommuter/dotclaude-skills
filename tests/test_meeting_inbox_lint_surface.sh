#!/usr/bin/env bash
# roadmap:de36 — `/meeting` step 7b must LINT the inbox it surfaces, not just grep it.
#
# INCIDENT (2026-07-17): `todo-conformance.sh --inbox` correctly flagged the broken acc7 line
# (`<!-- routed:$ID -->`, a literal shell variable) as `orphan` — the sole non-conformer of 13.
# But nothing routine runs it: it is reachable only via `scan-routed.sh` (report-only,
# auto-write gated per id:678e) or a manual step in the global CLAUDE.md. The detector existed
# and the defect shipped anyway. A loud detector whose invocation is optional is not a
# detector (CLAUDE.md: mechanize-first, no-silent-swallow).
#
# Step 7b already greps the inbox for `- [ ] [<repo>]` lines and surfaces them; it must also
# run the lint and surface non-conformers. Surface-only — no auto-fix, no blocking.
#
# RED until id:de36 lands.
#
# COVERAGE LIMIT (read before trusting a green): SKILL.md is prose the model follows, not code
# the harness executes. These assertions prove the INSTRUCTION is present and well-formed; they
# cannot prove a live meeting obeys it. That is a real gap, not a passing grade — it is the same
# limit every SKILL.md step carries. The one thing genuinely executable here is that the
# detector the instruction names exists and behaves as the instruction claims, so that half is
# tested for real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"
LINT="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "meeting/SKILL.md not found at $SKILL"
[[ -f "$LINT" ]]  || fail "todo-conformance.sh not found at $LINT"

# --- the instruction is present, and lives in step 7b (the inbox surface) --------------
# Extract step 7b: from the `7b.` marker to the next top-level step or heading.
step7b="$(awk '/^7b\. /{f=1} f{print} f && /^(##|[0-9]+[a-z]?\. )/ && !/^7b\. /{exit}' "$SKILL")"
[[ -n "$step7b" ]] || fail "could not locate step 7b (the inbox surface) in meeting/SKILL.md"

grep -q 'todo-conformance.sh' <<<"$step7b" \
  || fail "step 7b does not invoke todo-conformance.sh — the inbox is surfaced but never linted (id:de36)"
pass "step 7b invokes todo-conformance.sh"

grep -q -- '--inbox' <<<"$step7b" \
  || fail "step 7b names todo-conformance.sh but not its --inbox mode"
pass "step 7b uses the --inbox mode"

# It must SURFACE non-conformers, and say so distinctly from the routed-item list.
grep -qiE 'non-conform|conformance' <<<"$step7b" \
  || fail "step 7b runs the lint but never says to display its output — a detector whose result is dropped is the id:de36 defect itself"
pass "step 7b instructs that non-conformers are displayed"

# Surface-only: step 7b's existing contract is read-only. The lint must not auto-fix or block.
if grep -qiE 'auto-fix|automatically (fix|repair|correct)|abort the meeting|block the meeting' <<<"$step7b"; then
  fail "step 7b's lint must be SURFACE-ONLY — no auto-fix, no blocking (consistent with its read-only contract)"
fi
pass "step 7b's lint is surface-only (no auto-fix, no blocking)"

# --- no reimplementation: the lint is invoked, never inlined ---------------------------
# scan-routed.sh:19 already records the no-reimplementation decision; SKILL.md must not grow
# a second copy of the conforming-form regex (CLAUDE.md: prefer existing tooling, no NIH).
if grep -qE 'routed:\[0-9a-f\]|\[0-9a-f\]\\?\{4\\?\}' <<<"$step7b"; then
  fail "step 7b inlines a conforming-form regex — invoke todo-conformance.sh, never reimplement it (cf. scan-routed.sh:19)"
fi
pass "step 7b does not inline a second conforming-form regex"

# --- the detector the instruction names actually works (the executable half) -----------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
INBOX="$TMP/todo-inbox.md"
cat > "$INBOX" <<'EOF'
# Cross-project inbox

- [ ] [dotclaude-skills] a conforming item (from meeting, note) <!-- routed:1234 -->
- [ ] [dotclaude-skills] the acc7 shape — literal shell var in the marker (from meeting, note) <!-- routed:$ID -->
EOF

out="$("$LINT" --inbox "$INBOX" 2>&1)"
grep -q 'routed:\$ID' <<<"$out" \
  || fail "todo-conformance.sh --inbox did not flag the literal-\$ID entry — the instruction in step 7b would surface nothing; got: $out"
pass "todo-conformance.sh --inbox flags the acc7-shaped entry"

if grep -q 'routed:1234' <<<"$out"; then
  fail "todo-conformance.sh --inbox flagged the CONFORMING entry (routed:1234) — a lint that cries wolf at the inbox surface trains everyone to ignore it"
fi
pass "todo-conformance.sh --inbox leaves the conforming entry alone"

# A clean inbox must surface nothing — step 7b's existing "skip silently" contract.
cat > "$INBOX" <<'EOF'
# Cross-project inbox

- [ ] [dotclaude-skills] a conforming item (from meeting, note) <!-- routed:1234 -->
EOF
out="$("$LINT" --inbox "$INBOX" 2>&1)"
[[ -z "$out" ]] \
  || fail "todo-conformance.sh --inbox emitted output for a fully-conforming inbox — step 7b must stay silent when there is nothing to say; got: $out"
pass "clean inbox surfaces nothing"

echo "ALL PASS"
