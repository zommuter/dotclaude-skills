#!/usr/bin/env bash
# roadmap:aa26 — fable-config.sh: explicit Fable-availability CONFIG reader.
# Retires the probe-fable.sh cache-manager + agent-probe procedure (constraint
# archaeology: Fable is now a fixed part of the Max subscription, so there is nothing
# left to probe). Hermetic: mktemp relay.toml, RELAY_TOML override, no network/model.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/fable-config.sh"
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "fable-config.sh not found/executable at $SCRIPT"

# --- config absent (no relay.toml at all) ⇒ available (the Max default) ---
out="$(RELAY_TOML="$TMPDIR_T/does-not-exist.toml" "$SCRIPT" check)" && rc=0 || rc=$?
[[ "$out" == "available" && "$rc" -eq 0 ]] \
  || fail "absent config: expected 'available' rc=0, got '$out' rc=$rc"
pass "absent relay.toml ⇒ available (Max default)"

# --- relay.toml present but with no [relay] section ⇒ available ---
cat > "$TMPDIR_T/no-relay-section.toml" <<'EOF'
[repos.foo]
classification = "own"
EOF
out="$(RELAY_TOML="$TMPDIR_T/no-relay-section.toml" "$SCRIPT" check)" && rc=0 || rc=$?
[[ "$out" == "available" && "$rc" -eq 0 ]] \
  || fail "no [relay] section: expected 'available' rc=0, got '$out' rc=$rc"
pass "relay.toml without [relay] section ⇒ available"

# --- fable_available = true ⇒ available ---
cat > "$TMPDIR_T/true.toml" <<'EOF'
[relay]
fable_available = true
EOF
out="$(RELAY_TOML="$TMPDIR_T/true.toml" "$SCRIPT" check)" && rc=0 || rc=$?
[[ "$out" == "available" && "$rc" -eq 0 ]] \
  || fail "fable_available=true: expected 'available' rc=0, got '$out' rc=$rc"
pass "fable_available = true ⇒ available"

# --- fable_available = false ⇒ unavailable, exit 1 ---
cat > "$TMPDIR_T/false.toml" <<'EOF'
[relay]
fable_available = false
EOF
out="$(RELAY_TOML="$TMPDIR_T/false.toml" "$SCRIPT" check)" && rc=0 || rc=$?
[[ "$out" == "unavailable" && "$rc" -eq 1 ]] \
  || fail "fable_available=false: expected 'unavailable' rc=1, got '$out' rc=$rc"
pass "fable_available = false ⇒ unavailable, exit 1"

# --- never spawns a model / agent-probe: the script must not reference an agent
#     invocation, and it must return in well under a second (a real probe would
#     spawn a subagent and take far longer). ---
grep -qi "claude-fable-5\|Task tool\|subagent" "$SCRIPT" \
  && fail "fable-config.sh must never reference spawning a model/agent-probe"
pass "fable-config.sh contains no agent-spawn machinery"

start=$(date +%s%N)
RELAY_TOML="$TMPDIR_T/true.toml" "$SCRIPT" check >/dev/null
end=$(date +%s%N)
elapsed_ms=$(( (end - start) / 1000000 ))
[[ "$elapsed_ms" -lt 2000 ]] || fail "fable-config.sh check took ${elapsed_ms}ms — too slow for a pure config read"
pass "fable-config.sh check is fast (${elapsed_ms}ms, no model spawn)"

# --- no code path reads or writes the old fable-probe.json cache. The active-code
#     check is PROBE_CACHE (the variable the retired script used to read/write it) —
#     a bare filename mention survives as a historical/generic example in
#     migrate-state-dirs.sh's directory-migration comment, and fable-config.sh's own
#     header explains what it deliberately does NOT have; neither is a live code path.
if grep -rq "PROBE_CACHE" "$SRC_DIR/relay/scripts/"*.sh 2>/dev/null; then
  fail "a script still reads/writes the retired PROBE_CACHE (fable-probe.json)"
fi
pass "no script reads/writes the retired PROBE_CACHE (fable-probe.json)"

[[ ! -f "$SRC_DIR/relay/scripts/probe-fable.sh" ]] \
  || fail "probe-fable.sh should be retired but still exists"
pass "probe-fable.sh is retired"

# --- SKILL.md step 0 no longer describes the probe procedure ---
SKILL="$SRC_DIR/relay/SKILL.md"
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"
grep -q "fable-config.sh check" "$SKILL" || fail "SKILL.md step 0 does not call fable-config.sh"
pass "SKILL.md step 0 calls fable-config.sh"

if grep -qE "spawn ONE tiny agent pinned to \`?model: ?claude-fable-5\`?" "$SKILL"; then
  fail "SKILL.md still describes spawning a tiny Fable agent-probe"
fi
pass "SKILL.md no longer describes the agent-probe procedure"

echo "All fable-config (id:aa26) tests passed."
