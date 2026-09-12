#!/usr/bin/env bash
# roadmap:6294
# RED spec for id:6294 — `lint-pipefail-sigpipe.py` must recognise a SCRIPT consumer.
#
# id:81d5 fixed the `pipefail` + early-exiting-consumer race for a FIXED list of
# consumers: `grep -q/-m/-l`, `head`, `read`, `sed Nq`, `awk … exit`. A shell script
# invoked as `producer | bash <script>` is in none of those classes, so
# `early_exit_reason()` falls through to `return None` and the site is invisible.
#
# That is not a theoretical hole. Reproduced live in the suite on 2026-09-12
# (review run relay-20260912-191938-25818, load average 22.09):
# `tests/test_privacy_gate_prepush.sh` printed 8 `ok:` lines, zero `bad:` lines and
# no `---- N ok, M bad ----` summary, and the runner still marked it FAIL — it died
# mid-file with every assertion it reached TRUE, then passed standalone. Cause, at
# the exact line pair: `tests/test_privacy_gate_prepush.sh:114` pipes `printf` into
# `bash "$HOOK"` with the pattern file absent, and
# `hooks/pre-push-privacy-gate.sh` takes its D4 `exit 0` at :48 — BEFORE its
# `while IFS= read -r line` at :54. The hook never drains stdin, `printf` dies of
# SIGPIPE, `pipefail` promotes 141.
#
# So the id:81d5 population (427 sites / 162 files) UNDERCOUNTS the real one. This
# spec pins the widening; it does not re-litigate the mechanism.
#
# NOTE the negative controls below are as load-bearing as the positive ones: a lint
# that flags every pipeline would pass case 1 and be useless. Cases 3 and 4 are what
# make case 1 mean anything.
#
# Hermetic: every fixture lives under a mktemp dir; the lint is read-only.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/tests/lint-pipefail-sigpipe.py"

pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

[[ -f "$LINT" ]] || { echo "FAIL: lint not found at $LINT"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mk() {  # mk <name> <body-line>
  { printf '#!/usr/bin/env bash\nset -euo pipefail\n'; printf '%s\n' "$2"; } > "$tmpdir/$1"
}

# Exit status of the lint over ONE fixture. 0 = clean, non-zero = flagged.
# Written WITHOUT a pipe on purpose — this file must not contain the defect it specs.
lint_rc() {
  local rc=0
  python3 "$LINT" "$tmpdir/$1" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# ── Case 1: the reproduced shape — producer piped into a script consumer ─────────
mk script_consumer.sh 'printf "%s\n" "$line" | bash "$HOOK" origin url'
[[ "$(lint_rc script_consumer.sh)" != "0" ]] \
  && ok "producer | bash <script> is flagged (the id:6294 shape)" \
  || bad "producer | bash <script> NOT flagged — early_exit_reason() still falls through to None for a script consumer, so the 427-site sweep keeps undercounting"

# ── Case 2: same hole via `sh`, so the fix cannot be spelled for one interpreter ──
mk sh_consumer.sh 'cat "$f" | sh "$HELPER"'
[[ "$(lint_rc sh_consumer.sh)" != "0" ]] \
  && ok "producer | sh <script> is flagged too (not bash-only)" \
  || bad "producer | sh <script> NOT flagged — a bash-only fix leaves the identical hole open under sh"

# ── Case 3 (NEGATIVE CONTROL): a drain-to-EOF consumer must STAY clean ───────────
# Without this, a lint that flagged every pipeline would pass cases 1 and 2.
mk drains.sh 'git log --oneline | wc -l'
[[ "$(lint_rc drains.sh)" == "0" ]] \
  && ok "negative control: a drain-to-EOF consumer (wc -l) stays clean" \
  || bad "negative control FAILED: wc -l was flagged — the fix over-reached into every pipeline"

# ── Case 4 (NEGATIVE CONTROL): the safe rewrite must STAY clean ─────────────────
# This is the form the fix tells authors to move to; flagging it would make the
# lint's own advice unfollowable.
mk safe_form.sh 'bash "$HOOK" origin url < <(printf "%s\n" "$line")'
[[ "$(lint_rc safe_form.sh)" == "0" ]] \
  && ok "negative control: the recommended non-pipe form < <(producer) stays clean" \
  || bad "negative control FAILED: the recommended rewrite was itself flagged"

# ── Case 5: the real call sites this was found at are clean under the lint ──────
# Acceptance clause (b): the seven `printf ... | bash \"\$HOOK\"` sites in the
# privacy-gate test are rewritten. Runs the lint over the REAL file, read-only.
REALTEST="$ROOT/tests/test_privacy_gate_prepush.sh"
if [[ -f "$REALTEST" ]]; then
  rc=0; python3 "$LINT" "$REALTEST" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "0" ]] \
    && ok "tests/test_privacy_gate_prepush.sh is clean under the lint (clause b)" \
    || bad "tests/test_privacy_gate_prepush.sh still carries a flagged producer|consumer site — this is the file that actually flaked the suite"
else
  bad "tests/test_privacy_gate_prepush.sh not found — test anchor stale, re-derive it"
fi

# ── Cases 6-8 (ADDED WITH THE FIX): the narrowing the flag-outright branch rests on ─
# The fix flags an interpreter GIVEN A SCRIPT OPERAND. Two shapes are deliberately
# NOT flagged, and nothing else in the suite pins that, so a later refactor could
# widen into them silently — which would break the `curl … | bash` idiom's status and
# push authors toward the exemption mechanism id:81d5 forbids.
mk bare_bash.sh 'curl -fsSL https://example.invalid/install | bash'
[[ "$(lint_rc bare_bash.sh)" == "0" ]] \
  && ok "narrowing: bare \`| bash\` stays clean (the script IS stdin, so it drains to EOF)" \
  || bad "narrowing FAILED: bare \`| bash\` was flagged — it reads the script from stdin and cannot SIGPIPE"

mk dash_s.sh 'printf "%s\n" "$x" | bash -s -- --flag'
[[ "$(lint_rc dash_s.sh)" == "0" ]] \
  && ok "narrowing: \`| bash -s\` stays clean (-s also reads the script from stdin)" \
  || bad "narrowing FAILED: \`| bash -s\` was flagged"

mk dash_c.sh 'printf "%s\n" "$x" | bash -c "cat >/dev/null"'
[[ "$(lint_rc dash_c.sh)" == "0" ]] \
  && ok "narrowing: \`| bash -c <cmd>\` stays clean (no script operand; stdin is the cmd's)" \
  || bad "narrowing FAILED: \`| bash -c <cmd>\` was flagged — its command string is not a script path"

# ── Case 9 (ADDED WITH THE FIX): the shape must be seen when the author WRAPPED it ─
# The site this item was found at puts the `|` on one physical line and the `bash`
# consumer on the next, joined by a backslash. A line-oriented scan sees an empty
# 2nd stage and a consumer with no pipe, and reports nothing — so without this the
# fix would be green against fixtures and blind at the one real call site.
{ printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'out="$( printf "%%s" "$l" | \\\n    FOO=bar bash "$HOOK" origin url )"\n'
} > "$tmpdir/wrapped.sh"
[[ "$(lint_rc wrapped.sh)" != "0" ]] \
  && ok "a backslash-continued pipeline is joined and flagged (the real call-site shape)" \
  || bad "a backslash-continued pipeline was NOT flagged — the scan is physical-line-bound, so any wrapped instance of the defect is invisible"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: script-consumer SIGPIPE lint (roadmap:6294)"
