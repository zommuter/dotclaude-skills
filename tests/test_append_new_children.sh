#!/usr/bin/env bash
# (No `# roadmap:` header — this test pins the SHIPPED `append.sh new-children` behaviour
#  tracked in TODO.md id:06e3, verified green this 2026-07-10 review. Failures always count.)
#
# `append.sh new-children N [root]` mints N collision-free child tokens for a parent SPLIT
# and, in the SAME call, emits the parent's typed `children:` marker (form C) so the corpus
# stops accruing umbrella blindspots (id:06e3, typed-ledger-edges 2026-07-10). Emit-only:
# it never edits a ledger. Hermetic — runs against a mktemp -d fixture root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# A fixture root with a TODO.md that already carries a token, so collision-avoidance is
# exercised against real existing ids.
printf '# TODO\n\n- [ ] existing item <!-- id:abcd -->\n' > "$TMP/TODO.md"

OUT="$(RELAY_INBOX=/dev/null "$SH" new-children 3 "$TMP")"

# Exactly 4 output lines: 3 tokens + 1 marker line.
nlines=$(printf '%s\n' "$OUT" | grep -c .)
[[ "$nlines" -eq 4 ]] || fail "expected 3 tokens + 1 marker line, got $nlines lines: $OUT"
pass "new-children 3 emits 3 tokens + 1 marker line"

# The first three lines are bare 4-hex tokens, all distinct, none colliding with id:abcd.
mapfile -t lines <<<"$OUT"
toks=("${lines[0]}" "${lines[1]}" "${lines[2]}")
for t in "${toks[@]}"; do
  [[ "$t" =~ ^[0-9a-f]{4}$ ]] || fail "token '$t' is not a bare 4-hex token"
  [[ "$t" != "abcd" ]] || fail "minted token collides with the existing id:abcd"
done
uniq_count=$(printf '%s\n' "${toks[@]}" | sort -u | wc -l)
[[ "$uniq_count" -eq 3 ]] || fail "minted tokens are not all distinct: ${toks[*]}"
pass "three distinct collision-free 4-hex tokens"

# The final line is the typed children marker listing exactly those three tokens in order.
marker="${lines[3]}"
expected="<!-- children:${toks[0]},${toks[1]},${toks[2]} -->"
[[ "$marker" == "$expected" ]] || fail "marker mismatch: expected '$expected', got '$marker'"
pass "final line is the form-C children marker for the minted tokens"

echo "ALL PASS"
