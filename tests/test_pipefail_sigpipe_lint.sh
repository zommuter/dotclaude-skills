#!/usr/bin/env bash
# roadmap:81d5
# Spec for tests/lint-pipefail-sigpipe.py (id:81d5) — the ban on the
# `pipefail` + early-exiting-pipe-consumer race that caused id:7518.
#
# The defect class: under `set -o pipefail`, `producer | grep -q P` (or `| head -N`,
# `| sed Nq`, `| awk '…exit…'`, `| grep -m N`) fails INTERMITTENTLY on a TRUE
# assertion. The consumer exits at its first match while the producer is still
# writing; the producer dies of SIGPIPE (141); `pipefail` promotes 141 to the
# pipeline's status; the caller's `|| fail` or bare `set -e` fires. Measured 8/400
# on a 262-line static producer under load, and 400/400 for
# `git log … | grep -q <first-line-match>` — near-deterministic once the producer
# has more to write than the consumer reads.
#
# Every assertion RUNS the lint over purpose-built fixtures under $tmpdir, plus one
# assertion that runs it over the REAL repo (the regression gate: the shape must not
# come back). There is deliberately NO exemption/allowlist mechanism to test.
#
# Hermetic apart from the final whole-repo run, which is read-only.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/tests/lint-pipefail-sigpipe.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-pipefail-sigpipe.py not found at $LINT (id:81d5 not built)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mk() {  # mk <name> <body-line>
  { printf '#!/usr/bin/env bash\nset -euo pipefail\n'; printf '%s\n' "$2"; } > "$tmpdir/$1"
}

# run the lint on ONE fixture; echo its exit status (never let set -e kill us)
lint_rc() { python3 "$LINT" "$tmpdir/$1" >/dev/null 2>&1 && echo 0 || echo 1; }

# ---------------------------------------------------------------- POSITIVE controls
# Each of these IS the banned shape and MUST be flagged. If any stops being flagged,
# the detector has silently stopped detecting and the whole gate is theatre.
i=0
for body in \
  'cat /etc/hosts | grep -q localhost' \
  'cat /etc/hosts | grep -qF localhost' \
  'cat /etc/hosts | grep -qiE local' \
  'cat /etc/hosts | grep --quiet localhost' \
  'cat /etc/hosts | grep -m1 localhost' \
  'cat /etc/hosts | grep -l localhost' \
  'cat /etc/hosts | head -1' \
  'cat /etc/hosts | head -n 3 | cut -d" " -f1' \
  'cat /etc/hosts | sed -n 1q' \
  'cat /etc/hosts | awk "/x/{print; exit}"' \
  'if printf "%s" "$v" | grep -q x; then :; fi' \
  'printf "%s" "$v" | tr a b | grep -q x || true' \
  'x=$(git log --oneline | head -1)' \
  ; do
  i=$((i + 1))
  mk "pos$i.sh" "$body"
  [[ "$(lint_rc "pos$i.sh")" == 1 ]] \
    || fail "positive control NOT flagged: $body"
done
pass "all $i positive controls flagged (grep -q/-m/-l/--quiet, head, sed q, awk exit, nested, \$( ) )"

# ---------------------------------------------------------------- NEGATIVE controls
# Consumers that DRAIN to EOF cannot SIGPIPE their producer, and the safe rewrites
# must not be flagged either. A lint that fires on these is unusable and would push
# people toward an exemption mechanism — which this item forbids.
j=0
for body in \
  'cat /etc/hosts | grep -c localhost' \
  'cat /etc/hosts | grep localhost' \
  'cat /etc/hosts | wc -l' \
  'cat /etc/hosts | tail -1' \
  'cat /etc/hosts | sort | uniq' \
  'cat /etc/hosts | sed -n "1,5p"' \
  'cat /etc/hosts | awk "{print \$1}"' \
  'grep -q localhost < <(cat /etc/hosts)' \
  'grep -q localhost <<<"$v"' \
  'head -1 < <(cat /etc/hosts)' \
  'out=$(cat /etc/hosts); grep -q localhost <<<"$out"' \
  'echo "a | grep -q b"' \
  ; do
  j=$((j + 1))
  mk "neg$j.sh" "$body"
  [[ "$(lint_rc "neg$j.sh")" == 0 ]] \
    || fail "false positive on a SAFE form: $body"
done
pass "all $j negative controls clean (EOF-draining consumers, < <(), <<<, quoted text)"

# ---------------------------------------------------------------- pipefail gating
# Without `pipefail` the producer's 141 never reaches the caller, so the shape is
# not the defect. Gating on pipefail is the DEFINITION of the shape, not an exemption.
printf '#!/usr/bin/env bash\nset -eu\ncat /etc/hosts | grep -q localhost\n' > "$tmpdir/nopf.sh"
[[ "$(lint_rc nopf.sh)" == 0 ]] || fail "flagged a file that does not set pipefail"
pass "a file without pipefail is not flagged"

# ---------------------------------------------------------------- no exemption hatch
# The acceptance forbids a suppression mechanism. Assert the lint offers none:
# a marker comment that a naive implementation might honour must NOT silence it.
# Asserted BEHAVIOURALLY (three spellings a suppression hatch would plausibly use),
# never by grepping the lint's own source — that is the vacuous-fixture anti-pattern.
for hatch in '# noqa: pipefail-sigpipe' '# lint-ok: pipefail-sigpipe' '# pipefail-sigpipe: allow'; do
  mk "hatch.sh" "cat /etc/hosts | grep -q localhost  $hatch"
  [[ "$(lint_rc hatch.sh)" == 1 ]] \
    || fail "a marker comment ($hatch) silenced the lint — no exemption mechanism is allowed"
done
pass "no suppression hatch: marker comments do not silence the lint"

# ---------------------------------------------------------------- detector, not grep
# It must classify by PARSING, not by matching a marker: a `-q` that appears only
# inside a quoted PATTERN is not a flag and must not be flagged.
mk "quoted.sh" 'cat /etc/hosts | grep -c -- "-q localhost"'
[[ "$(lint_rc quoted.sh)" == 0 ]] || fail "a '-q' inside a quoted pattern was mistaken for a flag"
pass "classification is by parsed flags, not by substring"

# ---------------------------------------------------------------- REGRESSION GATE
# The whole point: the repo itself must stay free of the shape, with zero exemptions.
if ! out="$(python3 "$LINT" "$ROOT" 2>&1)"; then
  echo "$out"
  fail "the repo contains the pipefail + early-exiting-pipe-consumer shape (id:81d5 regression)"
fi
pass "repo is free of the banned shape (zero exemptions)"

echo "ALL PASS"
