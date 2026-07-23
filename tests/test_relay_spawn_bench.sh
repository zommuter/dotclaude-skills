#!/usr/bin/env bash
# roadmap:dfb9 — speedtest host `claude -p` spawn vs the Workflow `agent()` spawn.
#
# Deliverable spec (what the executor must build): relay/scripts/relay-spawn-bench.sh, a
# timing harness with three subcommands, all emitting ONE JSON line to stdout:
#   claude-p     [--n N] [--prompt TEXT]   time N host `claude -p "<trivial>"` spawns; emit
#                                          {"mode":"claude-p","n":N,"median_ms":<num>,"p90_ms":<num>,"samples_ms":[...]}
#   agent-record [--from FILE]             read the newest profile-run.sh --json records (or FILE)
#                                          and emit the median agent() dispatch cost as
#                                          {"mode":"agent","n":<count>,"median_ms":<num>,...} — the
#                                          agent() side is NOT re-spawned here (only a Workflow can
#                                          dispatch agent(); its durations are already instrumented).
#   compare      [--from FILE] [--n N]     emit both of the above PLUS
#                                          {"mode":"compare","claude_p_median_ms":..,"agent_median_ms":..,"ratio":..}
# Env: CLAUDE_BIN overrides the `claude` binary (this test stubs it → hermetic, no real spawns,
#      no network, no auto-spend). A missing/unrunnable claude MUST fail LOUDLY (nonzero), never
#      silently emit a 0 (a silent-zero benchmark is worse than none).
#
# The REAL measurement is a live run (documented, not hermetic); this test proves only the
# harness plumbing + output shape. RED until relay-spawn-bench.sh exists.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$SRC_DIR/relay/scripts/relay-spawn-bench.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

if [[ ! -f "$BENCH" ]]; then
  echo "FAIL: relay/scripts/relay-spawn-bench.sh does not exist yet (RED spec, roadmap:dfb9)"
  exit 1
fi
if [[ ! -x "$BENCH" ]]; then
  echo "FAIL: relay-spawn-bench.sh exists but is not executable"
  exit 1
fi

command -v jq >/dev/null || { echo "FAIL: jq required for this test"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub `claude`: sleep a hair (so a duration is measurable) then print a token. No network.
CLAUDE_STUB="$TMP/claude"
cat >"$CLAUDE_STUB" <<'EOF'
#!/usr/bin/env bash
# ignore all args; emulate a fast `claude -p` returning one token
sleep 0.02
printf 'pong\n'
EOF
chmod +x "$CLAUDE_STUB"

# ── (a) claude-p mode emits valid JSON with the required shape ────────────────
out="$(CLAUDE_BIN="$CLAUDE_STUB" "$BENCH" claude-p --n 3 --prompt 'ping' 2>/dev/null)" || out=""
if echo "$out" | jq -e . >/dev/null 2>&1; then
  mode=$(echo "$out" | jq -r '.mode // empty')
  n=$(echo "$out" | jq -r '.n // empty')
  med=$(echo "$out" | jq -r '.median_ms // empty')
  [[ "$mode" == "claude-p" ]] && ok "(a) claude-p mode tag" || bad "(a) mode=claude-p (got '$mode')"
  [[ "$n" == "3" ]] && ok "(a) n honored" || bad "(a) n=3 (got '$n')"
  { [[ -n "$med" ]] && awk "BEGIN{exit !($med >= 0)}"; } && ok "(a) numeric median_ms present" || bad "(a) median_ms numeric (got '$med')"
else
  bad "(a) claude-p emits a single valid JSON object (got: ${out:0:80})"
fi

# ── (b) missing claude MUST fail loudly, never a silent zero ──────────────────
if CLAUDE_BIN="$TMP/nope-does-not-exist" "$BENCH" claude-p --n 1 >/dev/null 2>&1; then
  bad "(b) a missing claude binary must exit nonzero (no silent-zero benchmark)"
else
  ok "(b) missing claude fails loudly (nonzero exit)"
fi

# ── (c) agent-record reads a profile-run JSON and emits the agent-side median ──
prof="$TMP/profile.json"
cat >"$prof" <<'EOF'
{"records":[{"category":"status","dur_ms":800},{"category":"status","dur_ms":1200},{"category":"status","dur_ms":1000}]}
EOF
out="$(CLAUDE_BIN="$CLAUDE_STUB" "$BENCH" agent-record --from "$prof" 2>/dev/null)" || out=""
if echo "$out" | jq -e '.mode=="agent" and (.median_ms|type=="number")' >/dev/null 2>&1; then
  ok "(c) agent-record emits {mode:agent, median_ms:<num>} from profile records"
else
  bad "(c) agent-record shape (got: ${out:0:80})"
fi

# ── (d) compare emits both sides + a ratio ────────────────────────────────────
out="$(CLAUDE_BIN="$CLAUDE_STUB" "$BENCH" compare --from "$prof" --n 2 2>/dev/null)" || out=""
if echo "$out" | jq -e '.mode=="compare" and (.claude_p_median_ms|type=="number") and (.agent_median_ms|type=="number") and (.ratio|type=="number")' >/dev/null 2>&1; then
  ok "(d) compare emits claude_p_median_ms + agent_median_ms + ratio"
else
  bad "(d) compare shape (got: ${out:0:80})"
fi

echo
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
