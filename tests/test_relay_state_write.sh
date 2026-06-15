#!/usr/bin/env bash
# roadmap:ebfb — flock'd single-writer for relay shared state (relay.toml / RELAY_STATUS.md).
# Covers relay-state-write.sh (toml-set / status-write) hermetically: field-scoped REPLACE,
# ADD-missing within the correct block, verbatim bare values, missing-block abort,
# atomic status-write with abs-path guard (id:c34a), and a concurrency smoke test.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/relay-state-write.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-state-write.sh not found/executable at $SH"

# ── Hermetic base ──
export FABLES_CONFIG; FABLES_CONFIG="$(mktemp -d)"
export RELAY_STATE_WRITE_LOG=/dev/null
trap 'rm -rf "$FABLES_CONFIG"' EXIT

seed_toml() {
  cat >"$FABLES_CONFIG/relay.toml" <<'EOF'
[repos.foo]
classification = "own"
last_ckpt = "old"

[repos.bar]
classification = "own"
EOF
}

# ── toml-set REPLACE ──
seed_toml
"$SH" toml-set foo last_ckpt '"new"'
grep -qxF 'last_ckpt = "new"' "$FABLES_CONFIG/relay.toml" || fail "REPLACE: foo last_ckpt not set to \"new\""
grep -qxF 'last_ckpt = "old"' "$FABLES_CONFIG/relay.toml" && fail "REPLACE: old value still present"
# bar block + foo classification untouched
grep -qxF '[repos.bar]' "$FABLES_CONFIG/relay.toml" || fail "REPLACE: bar block lost"
[[ "$(grep -c 'classification = "own"' "$FABLES_CONFIG/relay.toml")" -eq 2 ]] || fail "REPLACE: classification lines disturbed"
pass "toml-set REPLACE updates foo's key, leaves bar + classification intact"

# ── toml-set ADD-missing ──
seed_toml
"$SH" toml-set foo status '"active"'
grep -qxF 'status = "active"' "$FABLES_CONFIG/relay.toml" || fail "ADD: status not added"
# The status line must be inside the foo block (before [repos.bar]), not in bar.
foo_start="$(grep -n '\[repos.foo\]' "$FABLES_CONFIG/relay.toml" | cut -d: -f1)"
bar_start="$(grep -n '\[repos.bar\]' "$FABLES_CONFIG/relay.toml" | cut -d: -f1)"
status_line="$(grep -n 'status = "active"' "$FABLES_CONFIG/relay.toml" | cut -d: -f1)"
[[ "$status_line" -gt "$foo_start" && "$status_line" -lt "$bar_start" ]] \
  || fail "ADD: status not inside foo block (foo=$foo_start status=$status_line bar=$bar_start)"
pass "toml-set ADD-missing inserts key inside the foo block"

# ── toml-set bare value ──
seed_toml
"$SH" toml-set foo fable_rechecked false
grep -qxF 'fable_rechecked = false' "$FABLES_CONFIG/relay.toml" || fail "bare: line not exactly 'fable_rechecked = false'"
pass "toml-set writes bare (unquoted) values verbatim"

# ── toml-set on a missing block → non-zero, file unchanged ──
seed_toml
before="$(cat "$FABLES_CONFIG/relay.toml")"
if "$SH" toml-set nope key '"v"' 2>/dev/null; then fail "toml-set on missing block should fail"; fi
[[ "$(cat "$FABLES_CONFIG/relay.toml")" == "$before" ]] || fail "missing block: file was modified"
pass "toml-set on a missing block exits non-zero and leaves the file unchanged"

# ── toml-set on a missing file → non-zero ──
rm -f "$FABLES_CONFIG/relay.toml"
if "$SH" toml-set foo k '"v"' 2>/dev/null; then fail "toml-set on missing file should fail"; fi
[[ ! -f "$FABLES_CONFIG/relay.toml" ]] || fail "missing file: relay.toml was created"
pass "toml-set on a missing file exits non-zero and does not create it"

# ── status-write: abs path, exact content ──
target="$FABLES_CONFIG/status/RELAY_STATUS.md"
printf 'hello\n## X' | "$SH" status-write "$target"
[[ -f "$target" ]] || fail "status-write did not create the target"
[[ "$(cat "$target")" == "$(printf 'hello\n## X')" ]] || fail "status-write content mismatch"
pass "status-write writes STDIN content to an abs path atomically (mkdir -p)"

# ── status-write: relative / ~ path → non-zero, nothing written ──
if printf 'x' | "$SH" status-write "relative/path.md" 2>/dev/null; then fail "relative path should be refused"; fi
if printf 'x' | "$SH" status-write '~/RELAY_STATUS.md' 2>/dev/null; then fail "~ path should be refused"; fi
[[ ! -e "$FABLES_CONFIG/relative" ]] || fail "relative path: something was written"
pass "status-write refuses non-absolute paths (id:c34a)"

# ── concurrency smoke: two toml-set on DIFFERENT keys, backgrounded; both survive ──
seed_toml
"$SH" toml-set foo k1 '"a"' &
"$SH" toml-set foo k2 '"b"' &
wait
grep -qxF 'k1 = "a"' "$FABLES_CONFIG/relay.toml" || fail "concurrency: k1 lost"
grep -qxF 'k2 = "b"' "$FABLES_CONFIG/relay.toml" || fail "concurrency: k2 lost (flock did not serialize)"
pass "concurrent toml-set on different keys both persist (flock serialized)"

echo "ALL PASS: relay-state-write single-writer (id:ebfb)"
