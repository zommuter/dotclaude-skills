#!/usr/bin/env bash
# roadmap:b9b5 — RED spec for tools/model-probe.sh grade-arm flag/escape robustness.
#
# The grade arm pipes `echo "$output"` into grep. The bash `echo` builtin treats an
# output that is EXACTLY `-n`/`-e`/`-E`/`-ne`… as an option token and prints nothing
# (dropping the operand), so grading such an output silently mismatches. `printf '%s\n'`
# is robust. These cases are RED against the `echo` form and GREEN after the one-line
# `echo "$output"` → `printf '%s\n' "$output"` change at tools/model-probe.sh:38.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/tools/model-probe.sh"
[[ -x "$SCRIPT" ]] || { echo "tools/model-probe.sh missing or not executable"; exit 1; }

rc=0

# Each output below is a valid literal string that begins with (or is exactly) an
# `echo`-flag token; the regex `.` matches ANY non-empty output. A correct grade must
# therefore exit 0 (the output is non-empty). The `echo` form drops the token and
# grades empty → exit 1.
for out in "-n" "-e" "-E" "-ne"; do
  if "$SCRIPT" grade '.' "$out"; then
    : # exit 0 == correct (output is non-empty)
  else
    echo "FAIL: grade '.' '$out' should exit 0 (output is non-empty) but exited nonzero"
    echo "      -> 'echo \"\$output\"' consumed '$out' as a flag; use printf '%s\\n'"
    rc=1
  fi
done

# A literal that starts with a flag token followed by real content must still grade on
# its full text, not the echo-truncated remainder.
if ! "$SCRIPT" grade '^-n$' "-n"; then
  echo "FAIL: grade '^-n\$' '-n' should exit 0 — the literal output IS '-n'"
  rc=1
fi

(( rc == 0 )) && echo "PASS: model-probe grade arm is flag/escape-robust"
exit "$rc"
