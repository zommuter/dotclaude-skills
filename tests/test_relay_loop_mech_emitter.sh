#!/usr/bin/env bash
# roadmap:6176 — relay-loop.js must emit its proxy-eligible mechanical hops as
# model:"bash" + a ```relay-mech fence, so mechanical-proxy.py (id:176f) intercepts
# and runs them locally with ZERO upstream inference. Wiring child of id:176f.
#
# Static structure test (a grep/parse of relay-loop.js, like
# tests/test_relay_loop_structure.sh) — NO live pool, NO network. It asserts the
# EMITTER SHAPE only; whether model:"bash" actually reaches the proxy is a
# runtime/deploy concern (ANTHROPIC_BASE_URL must point at the proxy) and is
# deliberately OUT of scope here.
#
# SCOPE (the convertible set): only the hops whose command is a SINGLE allowlisted
# relay-script pipeline the proxy's _command_allowed() accepts — no heredoc, no
# `&&`/`;`, no `$(...)`, no `>>`, no python3. Those are:
#   file-surface:  -> file-surface-decisions.sh
#   quota:         -> quota-stop.sh
#   inject-take    -> inject.sh take
#   heartbeat-beat -> heartbeat.sh beat
#   heartbeat-stop -> heartbeat.sh stop
# The OTHER haiku hops are NOT proxy-eligible and MUST NOT be flipped: the
# discover-prelude (multi-command + LLM JSON assembly) and the discover-run
# classify shard (the id:7402 residual LLM read) stay model:'haiku'. This test
# guards that boundary in BOTH directions.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) At least one ```relay-mech fenced block exists (the proxy's extraction anchor).
grep -q '```relay-mech' "$JS" \
  || fail "no relay-mech fenced block — proxy (mechanical-proxy.py) cannot extract any mechanical command"
pass "at least one relay-mech fence present"

# (2) The 5 convertible hops now dispatch as `model: MECH_MODEL` — the id:4239 run-level flag
# that DEFAULTS to 'bash' (proxy-eligible) and flips to 'haiku' ONLY on the mode-a preflight
# (session not launched through the proxy). So the static assertion is >=5 `model: MECH_MODEL`
# dispatches, plus the MECH_MODEL definition defaulting to 'bash' (checked in (2b)).
mech_count=$(grep -Eo "model: *MECH_MODEL" "$JS" | wc -l)
[[ "$mech_count" -ge 5 ]] \
  || fail "expected >=5 'model: MECH_MODEL' dispatches (the 5 convertible mechanical hops); found $mech_count"
pass "model: MECH_MODEL dispatched for the mechanical hops ($mech_count found)"

# (2b) MECH_MODEL (id:4239) must be defined to DEFAULT to 'bash' and flip to 'haiku' only when
# the preflight signalled 'fallback-haiku' — so an un-preflighted run keeps the proxy-eligible
# model:"bash" contract (id:6176) unchanged, and the mode-a fallback is the ONLY haiku path.
grep -qE "MECH_MODEL *= *MECH_FALLBACK *=== *'fallback-haiku' *\? *'haiku' *: *'bash'" "$JS" \
  || fail "MECH_MODEL must be defined as: MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash' (id:4239 run-level flag defaulting to bash)"
pass "MECH_MODEL defaults to 'bash', flips to 'haiku' only on the mode-a preflight (id:4239)"

# (3) Per-hop: each convertible hop's option object uses `model: MECH_MODEL`, NOT a static
# model:'haiku'. The label + model live on the same single-line option object for all five.
check_hop_model_bash() {
  local label_re="$1" human="$2"
  local line
  line=$(grep -nE "label: *[\`'\"]$label_re" "$JS" | grep "model:" || true)
  [[ -n "$line" ]] || fail "$human: no single-line option object matching label '$label_re' with a model field"
  if echo "$line" | grep -qE "model: *['\"]haiku['\"]"; then
    fail "$human: hop still dispatched with a STATIC model:'haiku' — must be model: MECH_MODEL (id:4239 proxy-eligible mechanical hop, bash-by-default)"
  fi
  echo "$line" | grep -qE "model: *MECH_MODEL" \
    || fail "$human: hop's model is not MECH_MODEL — expected model: MECH_MODEL (id:4239, bash-by-default)"
  pass "$human: dispatched with model: MECH_MODEL (bash-by-default, not static haiku)"
}
check_hop_model_bash "file-surface:" "file-surface hop"
check_hop_model_bash "quota:"        "quota hop"
check_hop_model_bash "inject-take'"  "inject-take hop"
check_hop_model_bash "heartbeat-beat'" "heartbeat-beat hop"
check_hop_model_bash "heartbeat-stop'" "heartbeat-stop hop"

# (4) Each convertible hop emits a ```relay-mech fence marker AND all convertible
# commands are present. (id:6176 handback fix: the ORIGINAL check parsed the SOURCE
# for a literal ``` followed by a REAL newline byte — which is UNSATISFIABLE. Valid JS
# cannot contain a literal ``` adjacent to a raw newline: raw newlines exist only in
# template literals, whose delimiter IS the backtick, so ``` must be escaped as \`\`\`
# — which then has no literal ```. Both valid source forms, the '```relay-mech\n'+cmd
# concatenation AND a \`\`\`relay-mech template, render at RUNTIME to a real fence the
# proxy accepts — that runtime shape is pinned by test_mechanical_proxy.sh. So this
# check matches the SOURCE forms and stays non-trivial: >=5 fence markers, one per
# convertible hop, plus every convertible relay script present.)
python3 - "$JS" <<'PYEOF'
import re, sys
js = open(sys.argv[1]).read()
# A fence marker in JS SOURCE is three backticks OR three escaped backticks, then relay-mech.
markers = re.findall(r"(?:```|(?:\\`){3})relay-mech", js)
required = [
    "file-surface-decisions.sh",
    "quota-stop.sh",
    "inject.sh",
    "heartbeat.sh",
]
missing = [c for c in required if c not in js]
if len(markers) < 5:
    sys.exit(f"FAIL: expected >=5 ```relay-mech fence markers (one per convertible hop), found {len(markers)}")
if missing:
    sys.exit("FAIL: these convertible-hop relay scripts are absent from relay-loop.js: " + ", ".join(missing))
print(f"PASS: {len(markers)} relay-mech fence markers + all convertible relay commands present")
PYEOF

# (5) Boundary guard — the NON-eligible LLM hop must STAY model:'haiku' (a lazy
# executor must not flip the residual LLM read to bash). The classify shard (label
# discover-run:) is the id:7402 residual LLM surface — a sig-gated cat-and-copy of an
# already-mechanical verdict, still an LLM hop until the id:24ec mechanization lands —
# so it is wrong to route through the mechanical proxy today.
# id:86a2 (2026-07-23): the discover-prelude is NO LONGER on this list — it was
# owner-ratified as mechanizable (it never classifies; every step is already shell) and
# is now a model:'bash' dispatch of discover-prelude.sh (its own boundary is asserted by
# test_prelude_mechanized_86a2.sh + test_discover_cache.sh D1). Only discover-run remains.
for label in "discover-run:"; do
  line=$(grep -nE "label: *[\`']$label" "$JS" | grep "model:" || true)
  [[ -n "$line" ]] || fail "boundary guard: could not locate the '$label' hop option object"
  echo "$line" | grep -qE "model: *['\"]haiku['\"]" \
    || fail "boundary guard: the LLM hop '$label' must STAY model:'haiku' (not proxy-eligible — do not convert)"
done
pass "boundary guard: classify-shard (discover-run) stays model:'haiku' (LLM, not mechanical); prelude is now bash per id:86a2"

echo "ALL PASS"
