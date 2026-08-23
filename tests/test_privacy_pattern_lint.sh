#!/usr/bin/env bash
# Regression spec for the privacy pattern-authoring lint (id:9bfc part (b)).
#
# No `# roadmap:` header on purpose: id:9bfc lives in TODO.md, not ROADMAP.md, so this is a
# defect-fix test and its failures ALWAYS count — it is never EXPECTED-RED.
#
# Why this exists: on 2026-08-22 a 3-character unanchored name pattern matched inside a
# common English word 63 times with ZERO standalone occurrences. That noise camouflaged a
# genuine hit — on the very ledger line documenting the noise — and the leak went public.
# The real pattern file is PRIVATE and never committed, so every case here is SYNTHETIC.
#
# THE FIXTURES BELOW MUST STAY SYNTHETIC. A first draft of this file used the actual private
# token as a fixture, and a fragment of the real username as another — reproducing, inside the
# regression test for the leak, the exact leak it specs. Use invented tokens with no relation
# to any real name, and a made-up containing word (Zep/Zeppelin) for the substring case.
set -uo pipefail

# PRIVACY_AUDIT_BIN lets a mutation check point this spec at a deliberately-broken copy, to
# prove the assertions actually fire. A green suite where no assertion has ever failed is
# not evidence.
AUDIT="${PRIVACY_AUDIT_BIN:-$(git rev-parse --show-toplevel)/tools/privacy-audit.sh}"
pass=0; fail=0
ok()   { printf 'PASS: %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL: %s\n' "$1"; fail=$((fail+1)); }

tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT

lint() { PRIVACY_AUDIT_LINT_SELFTEST="$1" bash "$AUDIT"; }

# --- positive controls: collision-prone, MUST be flagged --------------------------------
printf '%s\n' Zep Bob Ann quo > "$tmp/short.txt"
out=$(lint "$tmp/short.txt"); rc=$?
n=$(printf '%s\n' "$out" | grep -c 'SHORT')
if [ "$rc" -ne 0 ] && [ "$n" -eq 4 ]; then
  ok "all 4 short unanchored literals flagged (nonzero exit)"
else
  bad "expected 4 flagged + nonzero exit; got n=$n rc=$rc"
fi

# --- THE security property: the lint must NEVER echo the pattern itself -----------------
leaked=0
for secret in Zep Bob Ann quo; do
  grep -qF -- "$secret" <<<"$out" && leaked=1   # herestring: no SIGPIPE under pipefail
done
if [ "$leaked" -eq 0 ]; then
  ok "lint output names INDICES only — no pattern text echoed"
else
  bad "lint LEAKED a pattern into its own output (the id:9bfc failure mode)"
fi

# --- negative controls: MUST NOT be flagged ---------------------------------------------
{
  printf '%s\n' '\bZep\b'                    # anchored short literal — the prescribed fix
  printf '%s\n' '^Ann$'                      # fully anchored
  printf '%s\n' 'Bob\b'                      # trailing anchor
  printf '%s\n' 'averylongliteralname'       # long enough to be specific
  printf '%s\n' '[0-9a-f]{8}-[0-9a-f]{4}'    # regex class + quantifier
  printf '%s\n' 'foo|bar|baz'                # alternation
  printf '%s\n' 'example\.com'               # escaped metachar
} > "$tmp/clean.txt"
out2=$(lint "$tmp/clean.txt"); rc2=$?
if [ "$rc2" -eq 0 ] && [ -z "$(printf '%s' "$out2" | tr -d '[:space:]')" ]; then
  ok "anchored / long / regex patterns are all clean (zero exit, no output)"
else
  bad "expected clean pass; got rc=$rc2 out='$out2'"
fi

# --- the exact incident shape: unanchored short literal matches inside a longer word -----
# Demonstrates WHY the lint exists, using grep directly rather than trusting the claim.
if grep -qE -- 'Zep' <<<'Zeppelin' && ! grep -qE -- '\bZep\b' <<<'Zeppelin'; then
  ok "unanchored literal matches inside a word; the \\b form does not (the fix works)"
else
  bad "word-boundary semantics not as specified"
fi

# --- boundary of the length rule --------------------------------------------------------
printf '%s\n' 'abcdef' > "$tmp/six.txt"      # == default threshold 6 → NOT flagged
printf '%s\n' 'abcde'  > "$tmp/five.txt"     # <  threshold            → flagged
lint "$tmp/six.txt"  >/dev/null 2>&1 && r6=0 || r6=1
lint "$tmp/five.txt" >/dev/null 2>&1 && r5=0 || r5=1
if [ "$r6" -eq 0 ] && [ "$r5" -eq 1 ]; then
  ok "length threshold is exclusive at PRIVACY_AUDIT_SHORT_LEN (6 clean, 5 flagged)"
else
  bad "threshold boundary wrong: 6-char rc=$r6 (want 0), 5-char rc=$r5 (want 1)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
