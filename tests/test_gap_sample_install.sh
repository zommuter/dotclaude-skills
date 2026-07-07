#!/usr/bin/env bash
# roadmap:bf7a — relay-gap-sample hardening: hermetic behavior spec + make install/uninstall
# targets + SKILL.md doc line (RED spec, relay handoff 2026-07-07).
#
# The logger itself (tools/relay-gap-sample.sh + .service/.timer) shipped 2026-07-02 but
# landed test-less and without install plumbing. This file is BOTH:
#   (1) the hermetic regression spec of the shipped behavior (change-line on first tick,
#       tick-only on an unchanged second run, loud ERROR verdict on classify failure) —
#       these sections may already pass; and
#   (2) the RED spec for the missing pieces: `make install-gap-sample` /
#       `make uninstall-gap-sample` targets mirroring install-quota-timer, and a
#       relay SKILL.md "Shared resources" doc line.
# Hermetic: mktemp everything, RELAY_SCRIPTS pointed at stub scripts, never touches
# ~/.config/relay or systemctl (make targets are asserted with `make -n` only).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAP="$ROOT/tools/relay-gap-sample.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$GAP" ]] || fail "tools/relay-gap-sample.sh missing or not executable"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- stub RELAY_SCRIPTS island (deterministic, no git, no LLM) --------------------
mkdir -p "$tmp/stubs" "$tmp/src/r1"
cat > "$tmp/stubs/heartbeat.sh" <<'EOF'
#!/usr/bin/env bash
# stub: no live pool runs
exit 0
EOF
cat > "$tmp/stubs/discover-sig.sh" <<'EOF'
#!/usr/bin/env bash
# stub: constant controllable sig per repo (env STUB_SIG)
jq -c '.repos[] | {repo: .repo, sig: env.STUB_SIG}'
EOF
cat > "$tmp/stubs/classify-repo.sh" <<'EOF'
#!/usr/bin/env bash
# stub: controllable classify outcome (env STUB_CLASSIFY_FAIL)
if [[ "${STUB_CLASSIFY_FAIL:-0}" == "1" ]]; then
  echo "stub classify exploded" >&2
  exit 1
fi
echo '{"verdict":"execute","reason":"stub reason"}'
EOF
chmod +x "$tmp/stubs/"*.sh

cat > "$tmp/relay.toml" <<EOF
[repos.r1]
classification = "own"
path = "$tmp/src/r1"
EOF

export RELAY_TOML="$tmp/relay.toml"
export SRC_DIR="$tmp/src"
export RELAY_GAP_SAMPLES="$tmp/samples.jsonl"
export RELAY_GAP_STATE="$tmp/state.json"
export RELAY_GAP_LOG="$tmp/gap.log"
export RELAY_SCRIPTS="$tmp/stubs"

# --- tick 1: fresh state → change line + tick summary ------------------------------
export STUB_SIG="sig-aaa"
"$GAP" >/dev/null || fail "tick 1: relay-gap-sample.sh exited nonzero"
[[ -f "$RELAY_GAP_SAMPLES" ]] || fail "tick 1: samples JSONL not written"
change_1="$(jq -c 'select(.kind=="change" and .repo=="r1")' "$RELAY_GAP_SAMPLES" | wc -l)"
[[ "$change_1" == "1" ]] || fail "tick 1: expected exactly 1 change line for r1, got $change_1"
jq -e 'select(.kind=="change" and .repo=="r1") | .verdict=="execute" and .sig=="sig-aaa"' \
  "$RELAY_GAP_SAMPLES" >/dev/null || fail "tick 1: change line lacks verdict/sig"
tick_1="$(jq -c 'select(.kind=="tick")' "$RELAY_GAP_SAMPLES" | tail -1)"
[[ "$(jq -r '.checked' <<<"$tick_1")" == "1" ]] || fail "tick 1: tick.checked != 1"
[[ "$(jq -r '.changed' <<<"$tick_1")" == "1" ]] || fail "tick 1: tick.changed != 1"
pass "tick 1: change line + tick summary on first sample"

# --- tick 2: unchanged sig → tick-only, NO new change line -------------------------
"$GAP" >/dev/null || fail "tick 2: relay-gap-sample.sh exited nonzero"
change_2="$(jq -c 'select(.kind=="change" and .repo=="r1")' "$RELAY_GAP_SAMPLES" | wc -l)"
[[ "$change_2" == "1" ]] || fail "tick 2: unchanged repo re-emitted a change line ($change_2 total)"
tick_2="$(jq -c 'select(.kind=="tick")' "$RELAY_GAP_SAMPLES" | tail -1)"
[[ "$(jq -r '.changed' <<<"$tick_2")" == "0" ]] || fail "tick 2: tick.changed != 0 on unchanged sig"
pass "tick 2: unchanged sig → tick-only (sig-cache honored)"

# --- tick 3: changed sig + classify failure → LOUD ERROR verdict, counted ----------
export STUB_SIG="sig-bbb" STUB_CLASSIFY_FAIL=1
"$GAP" >/dev/null || fail "tick 3: relay-gap-sample.sh exited nonzero (classify failure must not kill the sampler)"
jq -e 'select(.kind=="change" and .repo=="r1" and .sig=="sig-bbb") | .verdict=="ERROR"' \
  "$RELAY_GAP_SAMPLES" >/dev/null || fail "tick 3: classify failure not recorded as verdict ERROR change line"
tick_3="$(jq -c 'select(.kind=="tick")' "$RELAY_GAP_SAMPLES" | tail -1)"
[[ "$(jq -r '.classify_errors' <<<"$tick_3")" == "1" ]] || fail "tick 3: tick.classify_errors != 1"
pass "tick 3: classify failure is loud (ERROR change line + counted in tick)"
unset STUB_CLASSIFY_FAIL

# --- make targets (RED until bf7a lands): mirror install-quota-timer ---------------
make -C "$ROOT" -n install-gap-sample >"$tmp/make-install.out" 2>&1 \
  || fail "make install-gap-sample target missing (RED)"
grep -q 'relay-gap-sample.timer' "$tmp/make-install.out" \
  || fail "install-gap-sample recipe does not reference relay-gap-sample.timer"
grep -q 'relay-gap-sample.service' "$tmp/make-install.out" \
  || fail "install-gap-sample recipe does not reference relay-gap-sample.service"
make -C "$ROOT" -n uninstall-gap-sample >/dev/null 2>&1 \
  || fail "make uninstall-gap-sample target missing (RED)"
pass "Makefile install-gap-sample / uninstall-gap-sample targets exist"

# --- doc line: relay SKILL.md Shared resources must mention the logger -------------
grep -q 'relay-gap-sample' "$ROOT/relay/SKILL.md" \
  || fail "relay/SKILL.md lacks a relay-gap-sample doc line (Shared resources)"
pass "relay SKILL.md documents relay-gap-sample"

echo "ALL PASS: gap-sample behavior spec + install plumbing present"
