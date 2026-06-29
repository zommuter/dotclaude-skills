#!/usr/bin/env bash
# Tracks TODO id:6f61 — flock the meeting memory writes.
# No `# roadmap:XXXX` header: this is a TODO-id fix, not a ROADMAP item.
# Failures always count.
#
# Contract:
#   1. Two CONCURRENT pointer appends to the same MEMORY.md both land (no lost update).
#   2. Script creates the target file and parent directory when absent.
#   3. Each pointer is written as its own line (no line-merging / corruption).
#   4. Idempotent-safe: repeated appends do not corrupt the file.
#
# Hermetic: works in mktemp -d, never touches ~/.claude or the network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC_DIR/meeting/memory-append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SCRIPT" ]] || fail "memory-append.sh not found at $SCRIPT"
[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── 1. Creates target and parents when absent ────────────────────────────────
nested="$tmp/a/b/c/MEMORY.md"
"$SCRIPT" "$nested" "- [pointer-auto-create](fact.md) — auto" \
  || fail "should create parents and file when absent"
[[ -f "$nested" ]] || fail "MEMORY.md not created"
grep -qF "pointer-auto-create" "$nested" || fail "pointer not written"
pass "creates file and parent dirs when absent"

# ── 2. Sequential appends all land ──────────────────────────────────────────
mem="$tmp/sequential/MEMORY.md"
"$SCRIPT" "$mem" "- [fact-A](a.md) — first"
"$SCRIPT" "$mem" "- [fact-B](b.md) — second"
"$SCRIPT" "$mem" "- [fact-C](c.md) — third"
grep -qF "fact-A" "$mem" || fail "fact-A missing"
grep -qF "fact-B" "$mem" || fail "fact-B missing"
grep -qF "fact-C" "$mem" || fail "fact-C missing"
# each pointer on its own line
line_count="$(grep -c 'fact-' "$mem")"
[[ "$line_count" -eq 3 ]] || fail "expected 3 pointer lines, got $line_count"
pass "sequential appends all land on their own lines"

# ── 3. CONCURRENT appends — core no-lost-update contract ────────────────────
mem_c="$tmp/concurrent/MEMORY.md"
PIDS=()
for i in $(seq 1 20); do
  "$SCRIPT" "$mem_c" "- [fact-concurrent-${i}](c${i}.md) — entry ${i}" &
  PIDS+=($!)
done
for pid in "${PIDS[@]}"; do
  wait "$pid" || fail "a background memory-append.sh call failed (pid $pid)"
done

# Every pointer must appear exactly once
for i in $(seq 1 20); do
  # Match the exact bracket-close after the number to avoid "1" matching "10", "11", etc.
  count="$(grep -cF "fact-concurrent-${i}]" "$mem_c" || true)"
  [[ "$count" -eq 1 ]] \
    || fail "fact-concurrent-${i}: expected 1 occurrence, got $count (lost-update or duplicate)"
done
# Exactly 20 pointer lines (no line corruption / merging)
total="$(grep -c 'fact-concurrent-' "$mem_c")"
[[ "$total" -eq 20 ]] || fail "expected 20 pointer lines, got $total"
pass "20 concurrent appends — all 20 land exactly once (no lost update)"

# ── 4. Error on missing args ────────────────────────────────────────────────
if "$SCRIPT" 2>/dev/null; then fail "should exit non-zero with no args"; fi
if "$SCRIPT" "$tmp/x.md" "" 2>/dev/null; then fail "should exit non-zero with empty pointer"; fi
pass "error on missing / empty args"

echo "ALL PASS: memory-append.sh flock contract (TODO id:6f61)"
