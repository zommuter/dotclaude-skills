#!/usr/bin/env bash
# roadmap:373e
# Regression-guard test for tools/check-no-bare-rm-f.sh (id:373e / decision D6).
# Verifies the no-bare-rm-f guard's contract on a hermetic fixture tree:
#   - un-annotated non-recursive `rm -f` / `rm --force` are violations
#   - recursive `rm -rf` / `rm -fr` are EXEMPT (sanctioned mktemp-cleanup idiom)
#   - a non-empty `# force-ok: <reason>` (same line OR line above) clears it
#   - an EMPTY `# force-ok:` still fails (no rubber-stamp)
#   - pure-comment lines never count
#   - advisory (default) always exits 0; --enforce exits 1 over baseline
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHECK="$ROOT/tools/check-no-bare-rm-f.sh"

fail=0
check() { if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3 (got '$1' want '$2')"; fail=1; fi; }
contains() { if printf '%s' "$1" | grep -qF "$2"; then echo "  ok  $3"; else echo "  FAIL $3 (missing '$2')"; fail=1; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture skill tree -------------------------------------------------------
mkdir -p "$TMP/skill" "$TMP/skill/tests"

# 2 genuine violations: -f and --force. Recursive forms below are exempt.
cat > "$TMP/skill/bad.sh" <<'SH'
#!/usr/bin/env bash
rm -f "$x"
rm --force "$y"
rm -rf "$tmpdir"
rm -fr "$d"
SH

# All cleared: same-line annotation, line-above annotation.
cat > "$TMP/skill/good.sh" <<'SH'
#!/usr/bin/env bash
rm -f "$x"  # force-ok: needed because the shipping upstream cannot yet ENOENT-tolerate
# force-ok: absence expected on first run
rm -f "$x"
SH

# Empty reason must STILL fail (1 violation), plus a pure-comment mention (0).
cat > "$TMP/skill/empty_reason.sh" <<'SH'
#!/usr/bin/env bash
# force-ok:
rm -f "$x"
# a comment mentioning rm -f must not count
SH

# A tests/ path component is skipped (fixtures legitimately contain the text).
cat > "$TMP/skill/tests/fixture.sh" <<'SH'
#!/usr/bin/env bash
rm -f "$ignored"
SH

echo "== advisory mode: counts the 3 un-annotated violations (2 in bad.sh + 1 empty-reason) =="
out="$(bash "$CHECK" "$TMP/skill")"; rc=$?
check "$rc" "0" "advisory exits 0"
contains "$out" "non-recursive force-flag rm violations: 3" "advisory reports 3 violations"
contains "$out" "bad.sh" "names the offending file"

echo "== recursive rm -rf / rm -fr are exempt; annotated + pure-comment + tests/ not counted =="
# bad.sh: -f + --force = 2 (the -rf and -fr lines exempt). good.sh: 0 (both cleared).
# empty_reason.sh: 1 (empty reason fails; comment line ignored). tests/ skipped. total=3.
contains "$out" "non-recursive force-flag rm violations: 3" "recursive forms + annotations excluded"

echo "== enforce mode fails over baseline 0 =="
out2="$(RM_F_BAN_ENFORCE=1 bash "$CHECK" "$TMP/skill" 2>&1)"; rc2=$?
check "$rc2" "1" "enforce exits 1 when violations present"
contains "$out2" "FAIL" "enforce prints FAIL"

echo "== enforce mode passes when baseline covers the count =="
out3="$(RM_F_BAN_ENFORCE=1 RM_F_BAN_BASELINE=3 bash "$CHECK" "$TMP/skill" 2>&1)"; rc3=$?
check "$rc3" "0" "enforce within baseline exits 0"

echo "== a clean tree reports 0 and passes enforce =="
mkdir -p "$TMP/clean"
printf '#!/usr/bin/env bash\nrm -- "$f"\ntrap '\''rm -rf "$t"'\'' EXIT\n' > "$TMP/clean/ok.sh"
out4="$(RM_F_BAN_ENFORCE=1 bash "$CHECK" "$TMP/clean")"; rc4=$?
check "$rc4" "0" "clean tree passes enforce"
contains "$out4" "non-recursive force-flag rm violations: 0" "clean tree reports 0"

echo
if [ "$fail" = "0" ]; then echo "PASS test_no_bare_rm_f"; else echo "FAIL test_no_bare_rm_f"; fi
exit "$fail"
