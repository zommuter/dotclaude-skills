#!/usr/bin/env bash
# Defect fix — no `# roadmap:` header on purpose: this guards routed:15f3, which had no
# roadmap item, so its failures must ALWAYS count rather than being excused as expected-red.
#
# routed:15f3 — meeting/orphan-scan.sh --shipped ran EVERY discovered test with `bash`
# regardless of language. In a Python repo that shell-executes `tests/test_*.py` line by
# line, so `import csv` resolves to /usr/bin/import (ImageMagick), which writes a multi-MB
# PostScript SCREEN CAPTURE of the desktop into the repo root and blocks on a mouse click.
# `>/dev/null 2>&1` hid every trace. CONFIRMED live 2026-08-13 16:41-16:42 in
# linguistic-universals: 6 captures, 36 MB, and it blocked the relay pool via the
# dirty-tree guard. 23 own repos carry non-.sh `# roadmap:` tests and /todo-update runs
# this scan after EVERY prompt.
#
# This test reproduces the mechanism with a PATH shim standing in for ImageMagick's
# `import`, and asserts the shim is never reached.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$SRC_DIR/meeting/orphan-scan.sh"
fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails+1)); }

[[ -x "$SCAN" ]] || { echo "FAIL: orphan-scan.sh not executable at $SCAN"; exit 1; }
bash -n "$SCAN" || { echo "FAIL: orphan-scan.sh fails bash -n"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -r -- "$tmp" 2>/dev/null || true' EXIT
repo="$tmp/repo"; mkdir -p "$repo/tests"
export HOME="$tmp/home"; mkdir -p "$HOME"
export ORPHAN_SCAN_LOG="$tmp/scan.log"

git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t

# An OPEN item with no gate vocabulary, whose test is PYTHON.
cat > "$repo/TODO.md" <<'MD'
# TODO

## Current

- [ ] Ship the python-tested thing <!-- id:dd01 -->
- [ ] Ship the bash-tested thing <!-- id:b002 -->
- [ ] Ship the unidentifiable thing <!-- id:cc03 -->
MD

# The python test's FIRST executable line is the hazard: as shell, `import csv` runs the
# `import` binary. As python (or skipped) it never does.
cat > "$repo/tests/test_python_thing.py" <<'PY'
# roadmap:dd01
import csv
def test_ok():
    assert csv is not None
PY

# A bash test that genuinely passes — proves the fix did not break the working path.
cat > "$repo/tests/test_bash_thing.sh" <<'SH'
# roadmap:b002
exit 0
SH
chmod +x "$repo/tests/test_bash_thing.sh"

# UNIDENTIFIABLE language: no extension, no shebang. Carries the same `import csv` hazard,
# so if the scan falls back to bash the shim fires. Under the fix it must be SKIPPED.
cat > "$repo/tests/test_noext_thing" <<'NX'
# roadmap:cc03
import csv
NX

git -C "$repo" add -A >/dev/null 2>&1
git -C "$repo" commit -qm base >/dev/null 2>&1

# PATH shim: stand in for ImageMagick's `import`. If the scan ever shell-executes the .py,
# this fires and drops a marker — exactly as the real binary dropped 6 screen captures.
shim="$tmp/bin"; mkdir -p "$shim"
cat > "$shim/import" <<SHIM
#!/usr/bin/env bash
echo "IMAGEMAGICK-IMPORT-INVOKED \$*" >> "$tmp/import-invoked"
: > "$repo/\${1:-capture}"
exit 0
SHIM
chmod +x "$shim/import"

out="$(cd "$repo" && PATH="$shim:$PATH" "$SCAN" --shipped "$repo" 2>&1)"

# (1) THE DEFECT: the shim must never be reached.
if [[ -f "$tmp/import-invoked" ]]; then
  fail "(1) the .py test was SHELL-EXECUTED — ImageMagick's \`import\` was invoked $(wc -l < "$tmp/import-invoked") time(s) (THE DEFECT, routed:15f3). Invocations:
$(sed 's/^/      /' "$tmp/import-invoked")"
else
  pass "(1) the .py test was not shell-executed — \`import\` was never invoked"
fi

# (2) and it must not have written a stray capture file into the repo.
stray="$(cd "$repo" && git status --porcelain | awk '$1=="??"{print $2}' | grep -v '^tests/' || true)"
if [[ -n "$stray" ]]; then
  fail "(2) stray file(s) written into the repo root by the scan: $stray"
else
  pass "(2) no stray files written into the repo"
fi

# (3) the .py must be DISPATCHED correctly, not merely un-shell-executed. With pytest
# available a green python test SHOULD read TICK-READY — that is the fix working, not a
# leak. Without pytest it must be skipped and must not claim anything.
if command -v pytest >/dev/null 2>&1; then
  if grep -q 'id:dd01 — TICK-READY.*runner=py' <<<"$out"; then
    pass "(3) the .py was dispatched to pytest and its green result is honoured"
  else
    fail "(3) pytest is available but the .py was not dispatched to it. Output:
$(sed 's/^/      /' <<<"$out")"
  fi
else
  if grep -q 'id:dd01 — TICK-READY' <<<"$out"; then
    fail "(3) claimed TICK-READY for a .py with no runner available"
  else
    pass "(3) no pytest available, so the .py is skipped and claims nothing"
  fi
fi

# (4) THE SKIP CASE: an unidentifiable test is never executed, never claimed, and the skip
# is SURFACED (id:4347) — a silent skip makes an unrunnable test indistinguishable from a
# red one, so the item would sit un-tickable forever with no stated reason.
if grep -q 'id:cc03 — TICK-READY' <<<"$out"; then
  fail "(4) claimed TICK-READY for a test whose language could not be identified"
elif grep -q 'SKIPPED — language not identified' <<<"$out" && grep -q 'test_noext_thing' <<<"$out"; then
  pass "(4) the unidentifiable test was skipped, and the skip names the file loudly"
else
  fail "(4) the unidentifiable test was skipped SILENTLY (no surfaced reason). Output:
$(sed 's/^/      /' <<<"$out")"
fi

# (5) the working path must still work: a green .sh test still reports TICK-READY.
if grep -q 'id:b002 — TICK-READY' <<<"$out"; then
  pass "(5) a green .sh test still reports TICK-READY (fix did not break the working path)"
else
  fail "(5) REGRESSION: the green .sh test no longer reports TICK-READY. Output:
$(sed 's/^/      /' <<<"$out")"
fi

if (( fails )); then echo "FAIL: $fails assertion(s) failed"; exit 1; fi
echo "ALL PASS: orphan-scan dispatches on language and never shell-executes a .py (routed:15f3)"
