#!/usr/bin/env bash
# Defect-class test (no roadmap item; TODO id:4347): the no-silent-swallow guard.
# Verifies tools/check-no-silent-swallow.sh's contract on a hermetic fixture tree:
#   - un-annotated 2>/dev/null / || true / || : are violations
#   - a non-empty `# swallow-ok: <reason>` (same line OR line above) clears it
#   - an EMPTY `# swallow-ok:` still fails (no rubber-stamp)
#   - pure-comment lines never count
#   - advisory (default) always exits 0; --enforce exits 1 over baseline
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECK="$ROOT/tools/check-no-silent-swallow.sh"

fail=0
check() { if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3 (got '$1' want '$2')"; fail=1; fi; }
contains() { if printf '%s' "$1" | grep -qF "$2"; then echo "  ok  $3"; else echo "  FAIL $3 (missing '$2')"; fail=1; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture skill tree -------------------------------------------------------
mkdir -p "$TMP/skill" "$TMP/skill/tests"

# 3 genuine violations: same-pattern variety.
cat > "$TMP/skill/bad.sh" <<'SH'
#!/usr/bin/env bash
foo 2>/dev/null
bar || true
baz ||:
SH

# All cleared: same-line annotation, line-above annotation, and a py file.
cat > "$TMP/skill/good.sh" <<'SH'
#!/usr/bin/env bash
command -v foo 2>/dev/null  # swallow-ok: probing for an optional tool
# swallow-ok: absence is expected on first run
rm -f "$lock" 2>/dev/null
SH
cat > "$TMP/skill/good.py" <<'PY'
import subprocess
subprocess.run(["x"])  # noqa
# a comment mentioning 2>/dev/null must not count
PY

# Empty reason must STILL fail (1 violation).
cat > "$TMP/skill/empty_reason.sh" <<'SH'
#!/usr/bin/env bash
flaky 2>/dev/null  # swallow-ok:
SH

# A tests/ path component is skipped (fixtures legitimately contain the text).
cat > "$TMP/skill/tests/fixture.sh" <<'SH'
#!/usr/bin/env bash
should_be_ignored 2>/dev/null
SH

echo "== advisory mode: counts the 4 un-annotated violations (3 in bad.sh + 1 empty-reason) =="
out="$(bash "$CHECK" "$TMP/skill")"; rc=$?
check "$rc" "0" "advisory exits 0"
contains "$out" "un-annotated swallows: 4" "advisory reports 4 violations"
contains "$out" "bad.sh" "names the offending file"

echo "== pure-comment line + tests/ fixture are NOT counted, annotated lines cleared =="
# good.sh/good.py contribute 0; tests/fixture.sh is skipped -> total stays 4.
contains "$out" "2>/dev/null=2" "pattern breakdown: two 2>/dev/null (bad.sh + empty_reason.sh)"
contains "$out" "|| true=1" "pattern breakdown: one || true"

echo "== enforce mode fails over baseline 0 =="
out2="$(SWALLOW_BAN_ENFORCE=1 bash "$CHECK" "$TMP/skill" 2>&1)"; rc2=$?
check "$rc2" "1" "enforce exits 1 when violations present"
contains "$out2" "FAIL" "enforce prints FAIL"

echo "== enforce mode passes when baseline covers the count =="
out3="$(SWALLOW_BAN_ENFORCE=1 SWALLOW_BAN_BASELINE=4 bash "$CHECK" "$TMP/skill" 2>&1)"; rc3=$?
check "$rc3" "0" "enforce within baseline exits 0"

echo "== a clean tree reports 0 and passes enforce =="
mkdir -p "$TMP/clean"
printf '#!/usr/bin/env bash\necho hi\n' > "$TMP/clean/ok.sh"
out4="$(SWALLOW_BAN_ENFORCE=1 bash "$CHECK" "$TMP/clean")"; rc4=$?
check "$rc4" "0" "clean tree passes enforce"
contains "$out4" "un-annotated swallows: 0" "clean tree reports 0"

echo
if [ "$fail" = "0" ]; then echo "PASS test_no_silent_swallow"; else echo "FAIL test_no_silent_swallow"; fi
exit "$fail"
