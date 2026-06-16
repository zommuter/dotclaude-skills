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

# ── id:c8db F1: backslash in value is preserved verbatim (awk -v escape processing fixed) ──
seed_toml
# A value containing a literal backslash: awk -v would turn \n into newline, \t into tab, etc.
"$SH" toml-set foo last_ckpt '"relay-ckpt\\2026-06-15"'
grep -qxF 'last_ckpt = "relay-ckpt\\2026-06-15"' "$FABLES_CONFIG/relay.toml" \
  || fail "c8db-F1: backslash in value was mangled (awk -v escape processing still active)"
pass "c8db F1: backslash in value survives round-trip (no awk -v escape mangling)"

# ── id:c8db F2: key with regex metacharacter does NOT match the wrong line ──
# Use a repo whose key name contains a dot (regex wildcard). Construct a toml block where
# a regex-based key match would also match "last_ckpt" if key were e.g. "last.ckpt".
seed_toml
# Inject a key that looks like a regex metachar key (underscore is safe, but we test the
# literal-compare path with a key whose name shares a prefix with another key).
# Add a "last_ckpt_extra" key to the foo block, then set "last_ckpt" — with regex the
# pattern "^last_ckpt[ \t]*=" would also hit "last_ckpt_extra" because _ matches _ in
# both fixed and regex, but the substr-prefix logic adds the "rest must start with =/ "
# guard. We verify "last_ckpt_extra" is NOT clobbered.
cat >"$FABLES_CONFIG/relay.toml" <<'TOML'
[repos.foo]
classification = "own"
last_ckpt = "old"
last_ckpt_extra = "extra"

[repos.bar]
classification = "own"
TOML
"$SH" toml-set foo last_ckpt '"new"'
grep -qxF 'last_ckpt = "new"' "$FABLES_CONFIG/relay.toml" \
  || fail "c8db-F2: target key not updated"
grep -qxF 'last_ckpt_extra = "extra"' "$FABLES_CONFIG/relay.toml" \
  || fail "c8db-F2: adjacent key with shared prefix was clobbered (literal-compare not used)"
pass "c8db F2: literal key-prefix compare leaves keys with shared prefix intact"

# ── event-append (id:03a5): append-only JSONL history substrate ───────────────
EV="$FABLES_CONFIG/relay-events.jsonl"
rm -f "$EV"
printf '{"kind":"dispatch","repo":"a"}\n{"kind":"integrate","repo":"a"}\n' | "$SH" event-append "$EV"
printf '\n{"kind":"skip","repo":"b"}\n\n'                                   | "$SH" event-append "$EV"  # blank lines dropped
n=$(wc -l < "$EV")
[[ "$n" -eq 3 ]] || fail "event-append: expected 3 lines (blanks dropped), got $n"
grep -qxF '{"kind":"dispatch","repo":"a"}' "$EV" || fail "event-append: first line missing"
grep -qxF '{"kind":"skip","repo":"b"}'     "$EV" || fail "event-append: second-call line missing"
pass "event-append: appends across calls, drops blank lines"

# relative path is rejected (id:c34a — never a ~/$HOME literal)
echo '{}' | "$SH" event-append "relative/path.jsonl" && rc=0 || rc=$?
[[ "$rc" -eq 1 ]] || fail "event-append: relative path should exit 1 (got $rc)"
pass "event-append: rejects non-absolute path"

# empty stdin is a no-op (exit 0, file unchanged)
before=$(wc -l < "$EV")
printf '' | "$SH" event-append "$EV"
[[ "$(wc -l < "$EV")" -eq "$before" ]] || fail "event-append: empty stdin should not append"
pass "event-append: empty stdin is a no-op"

echo "ALL PASS: relay-state-write single-writer (id:ebfb, id:c8db, id:03a5)"
