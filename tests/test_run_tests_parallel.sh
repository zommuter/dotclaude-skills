#!/usr/bin/env bash
# Invariants of the parallel test runner (tests/run-tests.sh).
# No `# roadmap:` header on purpose — this is a harness-integrity test, so its
# failures must ALWAYS count (never EXPECTED-RED).
#
# Asserted here:
#   1. concurrency actually happens at -j >1
#   2. `-j 1` is serial
#   3. RUN_TESTS_NESTED=1 forces serial even when -j >1 is requested
#   4. an explicit -j beats the JOBS env var
#   5. the `summary: P passed, F failed, X expected-red` triple is emitted
#   6. results are emitted in stable FILE order, not completion order
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/tests/run-tests.sh"
fails=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$3', got '$2'"; fails=$((fails+1)); fi; }

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

# Fixture root: a throwaway ROOT/tests/ holding tests that report how many of their
# peers were running concurrently with them.
mkdir -p "$WORK/root/tests"
cp "$RUNNER" "$WORK/root/tests/run-tests.sh"
FIXRUN="$WORK/root/tests/run-tests.sh"
OBS="$WORK/obs"        # each fixture test appends its observed concurrency here
LIVE="$WORK/live"      # one marker file per currently-running fixture test
mkdir -p "$LIVE"

# Deliberately NOT alphabetical-by-duration: zz sleeps longest, so under
# longest-first scheduling it starts first — yet must still be REPORTED last.
for spec in "aa 0.5" "bb 0.5" "cc 0.5" "zz 0.9"; do
  set -- $spec
  cat >"$WORK/root/tests/test_${1}.sh" <<EOF
#!/usr/bin/env bash
touch "$LIVE/\$\$"
sleep $2
ls "$LIVE" | wc -l >> "$OBS"
rm -f -- "$LIVE/\$\$"
echo "marker-$1"
exit 0
EOF
done

# Returns the maximum concurrency observed during one fixture run.
run_fixture() {  # $@ = args/env passthrough already applied by caller
  : >"$OBS"; rm -f -- "$LIVE"/*
  "$@" >"$WORK/out.txt" 2>&1
  echo "$?" >"$WORK/rc.txt"
  sort -n "$OBS" | tail -1
}

# --- 1. parallel really is parallel -------------------------------------------
maxc="$(run_fixture env -u RUN_TESTS_NESTED bash "$FIXRUN" -j 4)"
if (( maxc > 1 )); then echo "ok   - -j 4 runs tests concurrently (max observed: $maxc)"
else echo "FAIL - -j 4 did not run concurrently (max observed: $maxc)"; fails=$((fails+1)); fi

# --- 5. summary triple, and 6. stable file order -------------------------------
check "summary triple emitted" \
  "$(grep -c '^summary: 4 passed, 0 failed, 0 expected-red' "$WORK/out.txt")" "1"
check "exit 0 on all-pass" "$(cat "$WORK/rc.txt")" "0"
check "results emitted in file order, not completion order" \
  "$(grep -oE 'test_[a-z]+\.sh' "$WORK/out.txt" | tr '\n' ' ')" \
  "test_aa.sh test_bb.sh test_cc.sh test_zz.sh "

# --- 2. -j 1 is serial ---------------------------------------------------------
maxc="$(run_fixture env -u RUN_TESTS_NESTED bash "$FIXRUN" -j 1)"
check "-j 1 is serial" "$maxc" "1"

# --- 3. nested marker forces serial despite -j 4 -------------------------------
maxc="$(run_fixture env RUN_TESTS_NESTED=1 bash "$FIXRUN" -j 4)"
check "RUN_TESTS_NESTED=1 forces serial even with -j 4" "$maxc" "1"
maxc="$(run_fixture env RUN_TESTS_NESTED=1 JOBS=4 bash "$FIXRUN")"
check "RUN_TESTS_NESTED=1 forces serial even with JOBS=4" "$maxc" "1"

# --- 4. explicit -j beats JOBS -------------------------------------------------
maxc="$(run_fixture env -u RUN_TESTS_NESTED JOBS=4 bash "$FIXRUN" -j 1)"
check "-j 1 overrides JOBS=4" "$maxc" "1"
maxc="$(run_fixture env -u RUN_TESTS_NESTED JOBS=4 bash "$FIXRUN")"
if (( maxc > 1 )); then echo "ok   - JOBS=4 honoured when no -j given (max observed: $maxc)"
else echo "FAIL - JOBS=4 ignored (max observed: $maxc)"; fails=$((fails+1)); fi

# --- the runner itself exports the nested marker to its children ---------------
cat >"$WORK/root/tests/test_aa.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${RUN_TESTS_NESTED:-}" == 1 ]] || { echo "child did not see RUN_TESTS_NESTED"; exit 1; }
exit 0
EOF
env -u RUN_TESTS_NESTED bash "$FIXRUN" -j 4 >"$WORK/out2.txt" 2>&1
check "children inherit RUN_TESTS_NESTED=1" \
  "$(grep -c '^summary: 4 passed, 0 failed' "$WORK/out2.txt")" "1"

# --- a bogus -j is rejected loudly, not silently defaulted ---------------------
env -u RUN_TESTS_NESTED bash "$FIXRUN" -j 0 >"$WORK/out3.txt" 2>&1
rc3=$?
check "-j 0 is rejected with exit 2" "$rc3" "2"

if (( fails > 0 )); then echo "$fails check(s) failed"; exit 1; fi
echo "all run-tests.sh parallelism invariants hold"
exit 0
