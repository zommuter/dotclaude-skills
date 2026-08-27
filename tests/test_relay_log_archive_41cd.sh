#!/usr/bin/env bash
# Defect/feature test for the newly-built relay-log-archive.sh (no ROADMAP.md item
# backs this — RELAY_LOG.md's rotator was a gap found during a size-audit, not a
# ticketed roadmap item — so the `# roadmap:XXXX` header is intentionally omitted;
# failures here always count, per tests/run-tests.sh's own convention.)
#
# Hermetic (mktemp only; no ~/.claude or network) coverage:
#   1. Size floor: a small RELAY_LOG.md (<MIN_LINES) is left completely untouched.
#   2. Age gate + tail floor: an old entry outside the protected tail is archived;
#      a fresh entry is not; an old entry INSIDE the protected tail is not.
#   3. Entry integrity: the archived entry's full multi-paragraph body moves as
#      one unit, verbatim, into RELAY_LOG.archive.md.
#   4. Unparseable header: an entry whose header doesn't start with `## YYYY-MM-DD`
#      is left in place even though it's clearly old content.
#   5. Idempotence: running twice does not duplicate or further shrink anything.
#   6. --dry-run mutates nothing.
#   7. Lock contention: a second concurrent invocation backs off cleanly (exit 0,
#      no mutation) while the lock is held.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/relay-log-archive.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-log-archive.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Helper: emit N padded entries so the file clears any line-count floor. ──
# Each entry header carries a distinct date; body lines are padded so the file
# is comfortably over MIN_LINES for the tests that need to trip the archiver.
gen_entry() {
    local d="$1" tag="$2" pad="${3:-5}"
    printf '## %s — executor (Sonnet) id:%s\n\n' "$d" "$tag"
    printf 'Worked id:%s — entry body line for %s.\n' "$tag" "$tag"
    local k=0
    while (( k < pad )); do
        printf 'padding line %d for %s\n' "$k" "$tag"
        k=$((k+1))
    done
    printf '\n'
}

old_date=$(date -d '60 days ago' '+%Y-%m-%d')
recent_date=$(date -d '5 days ago' '+%Y-%m-%d')

# ─────────────────────────────────────────────────
# Test 1: size floor — small file is untouched
# ─────────────────────────────────────────────────
repo1="$tmp/repo1"
mkdir -p "$repo1"
{
    echo "# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->"
    echo
    gen_entry "$old_date" aaaa 1
} > "$repo1/RELAY_LOG.md"
before1=$(cat "$repo1/RELAY_LOG.md")
MIN_LINES=500 bash "$SCRIPT" "$repo1" 2>/dev/null
after1=$(cat "$repo1/RELAY_LOG.md")
[[ "$before1" == "$after1" ]] || fail "T1: small RELAY_LOG.md was mutated despite size floor"
[[ ! -f "$repo1/RELAY_LOG.archive.md" ]] || fail "T1: archive file created despite size floor"
pass "T1: size floor leaves a small RELAY_LOG.md untouched"

# ─────────────────────────────────────────────────
# Test 2-5: age gate, tail floor, entry integrity, unparseable header
# ─────────────────────────────────────────────────
repo2="$tmp/repo2"
mkdir -p "$repo2"
{
    echo "# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->"
    echo
    gen_entry "$old_date" old1 40         # old, WILL be outside the tail
    echo "## relay(execute): id:zzzz — anchor something ($old_date)"
    echo
    echo "Unparseable-header entry body, old content but no leading date."
    echo
    gen_entry "$recent_date" fresh1 3     # recent — protected by age
    gen_entry "$old_date" tail1 3         # old but inside the protected tail
} > "$repo2/RELAY_LOG.md"

wc2=$(wc -l < "$repo2/RELAY_LOG.md")
(( wc2 >= 40 )) || fail "T2 setup: fixture too small ($wc2 lines)"

MIN_LINES=40 KEEP_TAIL_ENTRIES=1 bash "$SCRIPT" "$repo2" 2>/dev/null
arch2="$repo2/RELAY_LOG.archive.md"
log2="$repo2/RELAY_LOG.md"

[[ -f "$arch2" ]] || fail "T2: RELAY_LOG.archive.md was not created"
grep -q 'id:old1' "$arch2" || fail "T2: old, non-tail entry not archived"
grep -q 'id:old1' "$log2" && fail "T2: old, non-tail entry still in RELAY_LOG.md"
pass "T2: age-gated, non-tail entry is archived"

# T3: multi-line body moved as one unit, verbatim.
for k in 0 1 2 3 4 5 6 7 8 9; do
    grep -q "padding line $k for old1" "$arch2" || fail "T3: padding line $k missing from archive"
done
pass "T3: full multi-line entry body moved verbatim as one unit"

# T4: fresh entry (age-protected) stays in the live file.
grep -q 'id:fresh1' "$log2" || fail "T4: fresh (age-protected) entry was archived"
grep -q 'id:fresh1' "$arch2" && fail "T4: fresh entry wrongly present in archive"
pass "T4: age-protected fresh entry left in RELAY_LOG.md"

# T5: old entry INSIDE the protected tail (last KEEP_TAIL_ENTRIES=1 entry) stays live.
grep -q 'id:tail1' "$log2" || fail "T5: tail-protected old entry was archived"
grep -q 'id:tail1' "$arch2" && fail "T5: tail-protected entry wrongly present in archive"
pass "T5: tail-floor protects the most recent entries regardless of age"

# T6: unparseable-header entry is left in place even though clearly old.
grep -q 'id:zzzz' "$log2" || fail "T6: unparseable-header entry was removed from RELAY_LOG.md"
grep -q 'Unparseable-header entry body' "$log2" || fail "T6: unparseable-header entry body missing"
pass "T6: entry with an unparseable header is conservatively left in place"

# Preamble / doctrine comment preserved.
grep -q 'merge=union; append-only' "$log2" || fail "T6b: H1 doctrine line was lost from RELAY_LOG.md"
pass "T6b: H1 title / doctrine comment preserved"

# ─────────────────────────────────────────────────
# Test 7: idempotence — second run is a clean no-op
# ─────────────────────────────────────────────────
before_log=$(cat "$log2")
before_arch=$(cat "$arch2")
MIN_LINES=40 KEEP_TAIL_ENTRIES=1 bash "$SCRIPT" "$repo2" 2>/dev/null
after_log=$(cat "$log2")
after_arch=$(cat "$arch2")
[[ "$before_log" == "$after_log" ]]   || fail "T7: second run mutated RELAY_LOG.md"
[[ "$before_arch" == "$after_arch" ]] || fail "T7: second run mutated RELAY_LOG.archive.md (duplicate entries?)"
pass "T7: second run is idempotent"

# ─────────────────────────────────────────────────
# Test 8: --dry-run mutates nothing
# ─────────────────────────────────────────────────
repo3="$tmp/repo3"
mkdir -p "$repo3"
{
    echo "# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->"
    echo
    gen_entry "$old_date" dry1 40
    gen_entry "$recent_date" dry2 3
} > "$repo3/RELAY_LOG.md"
before3=$(cat "$repo3/RELAY_LOG.md")
MIN_LINES=40 KEEP_TAIL_ENTRIES=0 bash "$SCRIPT" --dry-run "$repo3" 2>/dev/null
after3=$(cat "$repo3/RELAY_LOG.md")
[[ "$before3" == "$after3" ]] || fail "T8: --dry-run mutated RELAY_LOG.md"
[[ ! -f "$repo3/RELAY_LOG.archive.md" ]] || fail "T8: --dry-run created an archive file"
pass "T8: --dry-run mutates nothing"

# ─────────────────────────────────────────────────
# Test 9: lock contention backs off cleanly
# ─────────────────────────────────────────────────
repo4="$tmp/repo4"
mkdir -p "$repo4"
{
    echo "# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->"
    echo
    gen_entry "$old_date" lock1 40
} > "$repo4/RELAY_LOG.md"
before4=$(cat "$repo4/RELAY_LOG.md")
lockfile="$repo4/.relay-log-archive.lock"
# Hold the lock in a background subshell for the duration of the contended call.
(
    exec 9>"$lockfile"
    flock 9
    sleep 2
) &
holder_pid=$!
sleep 0.3   # let the background holder acquire the lock first
out=$(MIN_LINES=40 bash "$SCRIPT" "$repo4" 2>&1)
rc=$?
wait "$holder_pid"
[[ $rc -eq 0 ]] || fail "T9: contended run exited non-zero ($rc)"
grep -qi 'another instance' <<<"$out" || fail "T9: contended run did not report lock contention"
after4=$(cat "$repo4/RELAY_LOG.md")
[[ "$before4" == "$after4" ]] || fail "T9: contended run mutated RELAY_LOG.md"
pass "T9: lock contention backs off cleanly, no mutation"

echo "ok"
