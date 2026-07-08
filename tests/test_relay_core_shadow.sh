#!/usr/bin/env bash
# (no roadmap token — id:82c4 island-1 shadow wiring is tracked in TODO.md, not
#  ROADMAP.md; this test always counts.)
#
# Spec for the relay-core SHADOW seam in classify-repo.sh (id:82c4, meeting id:23ab
# D3/a0b6 strangler) + the relay-doctor live-path line:
#   (1) binary ABSENT  → classify-repo output byte-identical to a no-shadow run,
#       zero shadow-log writes (zero behavior change).
#   (2) fake binary present + AGREEING → shadow log gains a "match" line; the
#       authoritative (bash) stdout is UNCHANGED.
#   (3) fake binary DISAGREEING → MISMATCH logged loudly (log entry + stderr), the
#       authoritative stdout STILL unchanged, exit code still 0.
#   (4) relay-doctor emits the live-path line for both states.
# Hermetic: mktemp -d fixtures, RELAY_CORE_SHADOW_LOG + RELAY_CORE_BIN/PATH overrides;
# never touches the real ~/.claude or the network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh not found: $CR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Hermetic gather: empty relay.toml + isolated worktree base (same as test_classify_repo.sh).
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_CORE_SHADOW_LOG="$tmp/shadow.jsonl"

# One tiny repo fixture with an open [ROUTINE] item (verdict: execute).
R="$tmp/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e; git -C "$R" config user.name t
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:1111 -->
EOF
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

run_cr() { "$CR" --repo repo --path "$R"; }

# --- (1) binary absent: kill switch (set-but-not-executable RELAY_CORE_BIN) --------
# Also proves a future real `relay-core` install can never leak into hermetic tests.
out_absent="$(RELAY_CORE_BIN="$tmp/does-not-exist" run_cr)"
[[ -n "$out_absent" ]] || { echo "FAIL (1): classify-repo emitted nothing"; exit 1; }
[[ ! -e "$RELAY_CORE_SHADOW_LOG" ]] || { echo "FAIL (1): binary absent must write NO shadow log"; exit 1; }

# Baseline for byte-identity: a second absent-run must be byte-identical (determinism),
# and each shadowed run below must equal this authoritative output byte-for-byte.
out_absent2="$(RELAY_CORE_BIN="$tmp/does-not-exist" run_cr)"
[[ "$out_absent" == "$out_absent2" ]] || { echo "FAIL (1): absent-run output not deterministic"; exit 1; }

# --- (2) fake AGREEING binary on a prepended PATH ----------------------------------
# The fake re-execs the real bash classifier — output canonically identical.
fakebin="$tmp/bin"; mkdir -p "$fakebin"
cat > "$fakebin/relay-core" <<EOF
#!/usr/bin/env bash
exec "$ROOT/relay/scripts/classify-verdict.sh"
EOF
chmod +x "$fakebin/relay-core"

out_agree="$(PATH="$fakebin:$PATH" run_cr)"
[[ "$out_agree" == "$out_absent" ]] || { echo "FAIL (2): authoritative output changed under agreeing shadow"; exit 1; }
[[ -f "$RELAY_CORE_SHADOW_LOG" ]] || { echo "FAIL (2): agreeing shadow must append a log line"; exit 1; }
[[ "$(wc -l < "$RELAY_CORE_SHADOW_LOG")" == "1" ]] || { echo "FAIL (2): expected exactly 1 log line"; exit 1; }
grep -q '"result":"match"' "$RELAY_CORE_SHADOW_LOG" || { echo "FAIL (2): log line must be a match"; exit 1; }
# Log line is valid JSON with ts + input_hash.
python3 -c '
import json,sys
o=json.loads(open(sys.argv[1]).readline())
assert o["result"]=="match" and o["ts"] and o["input_hash"], o
' "$RELAY_CORE_SHADOW_LOG" || { echo "FAIL (2): malformed shadow log entry"; exit 1; }

# --- (3) fake DISAGREEING binary → LOUD MISMATCH, authoritative output unchanged ----
cat > "$fakebin/relay-core" <<'EOF'
#!/usr/bin/env bash
echo '{"verdict":"idle","reason":"wrong","evidence":[],"ambiguous":false,"priority_rank":7,"intensive":""}'
EOF

err3="$tmp/err3"
out_disagree="$(PATH="$fakebin:$PATH" run_cr 2> "$err3")"
rc=$?
[[ "$rc" == "0" ]] || { echo "FAIL (3): mismatch must never alter classify-repo exit code (got $rc)"; exit 1; }
[[ "$out_disagree" == "$out_absent" ]] || { echo "FAIL (3): authoritative output changed under disagreeing shadow"; exit 1; }
[[ "$(wc -l < "$RELAY_CORE_SHADOW_LOG")" == "2" ]] || { echo "FAIL (3): expected a 2nd log line"; exit 1; }
tail -1 "$RELAY_CORE_SHADOW_LOG" | grep -q '"result":"MISMATCH"' || { echo "FAIL (3): 2nd line must be MISMATCH"; exit 1; }
# MISMATCH entry carries both canonical forms for diagnosis.
python3 -c '
import json,sys
o=json.loads(open(sys.argv[1]).readlines()[-1])
assert o["result"]=="MISMATCH" and o["bash"] and o["lean"] and o["bash"]!=o["lean"], o
' "$RELAY_CORE_SHADOW_LOG" || { echo "FAIL (3): MISMATCH entry must carry bash+lean forms"; exit 1; }
# LOUD on stderr too.
grep -q "SHADOW MISMATCH" "$err3" || { echo "FAIL (3): MISMATCH must be loud on stderr"; exit 1; }

# --- (3b) crashing shadow binary → recorded, never propagates ------------------------
cat > "$fakebin/relay-core" <<'EOF'
#!/usr/bin/env bash
echo "relay-core: simulated crash" >&2
exit 3
EOF
out_crash="$(PATH="$fakebin:$PATH" run_cr 2> "$tmp/err3b")"
[[ "$out_crash" == "$out_absent" ]] || { echo "FAIL (3b): crashing shadow must not alter output"; exit 1; }
tail -1 "$RELAY_CORE_SHADOW_LOG" | grep -q '"result":"MISMATCH"' || { echo "FAIL (3b): crash must log a MISMATCH"; exit 1; }
tail -1 "$RELAY_CORE_SHADOW_LOG" | grep -q 'INVALID-JSON' || { echo "FAIL (3b): crash entry must carry the INVALID-JSON marker"; exit 1; }

# --- (4) relay-doctor live-path line -------------------------------------------------
if [[ -x "$DOCTOR" ]]; then
  # absent → legacy-bash line (doctor is report-only; scope = the tiny fixture repo)
  d_absent="$(RELAY_CORE_BIN="$tmp/does-not-exist" RELAY_DOCTOR_LOG="$tmp/doctor.log" "$DOCTOR" "$R" 2>>"$tmp/doctor.err" || true)"
  grep -q "mechanical core absent — legacy bash path" <<<"$d_absent" \
    || { echo "FAIL (4): doctor must report the legacy-bash live path"; exit 1; }
  # present → active line with counts. The doctor's own check 10 runs classify-repo
  # --emit unit, which itself shadow-logs one more round; with the AGREEING fake that
  # +1 round is deterministic: 3 prior (1 match + 2 MISMATCH) + 1 match = 4 rounds, 2 mismatches.
  cat > "$fakebin/relay-core" <<EOF
#!/usr/bin/env bash
exec "$ROOT/relay/scripts/classify-verdict.sh"
EOF
  chmod +x "$fakebin/relay-core"
  d_active="$(PATH="$fakebin:$PATH" RELAY_DOCTOR_LOG="$tmp/doctor.log" "$DOCTOR" "$R" 2>>"$tmp/doctor.err" || true)"
  grep -q "relay-core shadow active: 4 rounds, 2 mismatches" <<<"$d_active" \
    || { echo "FAIL (4): doctor must report shadow rounds/mismatch counts from the log"; exit 1; }
else
  echo "SKIP (4): relay-doctor.sh not found"
fi

# --- side-effect-free on the repo itself ---------------------------------------------
[[ -z "$(git -C "$R" status --porcelain)" ]] || { echo "FAIL: fixture repo dirtied"; exit 1; }

echo "PASS test_relay_core_shadow"
