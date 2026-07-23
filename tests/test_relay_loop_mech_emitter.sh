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
# The discovery hops were originally EXCLUDED from this set (multi-step per-repo loops), but
# have since been mechanized into single fenced commands of their own: the discover-prelude ->
# discover-prelude.sh (id:86a2) and the discover-run SHARD -> discover-chunk.sh (id:24ec), each a
# model:'bash' dispatch. Their per-repo loops moved INTO those wrappers (asserted by their own
# tests: test_prelude_mechanized_86a2.sh / test_discover_chunk_mechanized_24ec.sh), so they are
# no longer "must-stay-haiku" here. The only residual LLM discovery read left is the CASE-A
# content-address copy (id:7402), a gated follow-on (id:6eb3) not yet a model:'bash' hop. This
# test guards the convertible-set boundary in BOTH directions AND (section 5) that the two
# mechanized discovery hops are not silently re-pinned to haiku.

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

# (5) Boundary guard — the NON-eligible LLM hops must STAY model:'haiku' (a lazy executor
# must not flip a residual LLM read to bash).
# id:86a2 (2026-07-23): the discover-prelude was removed from this list — mechanized to a
# model:'bash' dispatch of discover-prelude.sh (never classifies; every step is already shell).
# id:24ec (2026-07-23): the discover-run SHARD is likewise NO LONGER on this list — it was
# owner-ratified + mechanized (CASE B) into a deterministic model:'bash' dispatch of
# discover-chunk.sh (per-repo reconcile+classify via discover-repo.sh, concatenated; no LLM
# judgment — classify-verdict never emits AMBIGUOUS). Its boundary/parity is now asserted by
# test_discover_chunk_mechanized_24ec.sh (the wrapper's own test), the faithful-relocation
# pattern id:86a2 used for the prelude — coverage MOVED, not dropped. The CASE-A content-address
# copy (the id:7402 residual LLM read) remains the gated follow-on id:6eb3; when it too becomes a
# model:'bash' hop this guard's list may empty entirely.
# The list is currently EMPTY (both discovery LLM hops are mechanized). If a future hop is a
# genuine LLM read that must NOT be proxy-converted, add its label here.
must_stay_haiku=()
for label in "${must_stay_haiku[@]}"; do
  line=$(grep -nE "label: *[\`']$label" "$JS" | grep "model:" || true)
  [[ -n "$line" ]] || fail "boundary guard: could not locate the '$label' hop option object"
  echo "$line" | grep -qE "model: *['\"]haiku['\"]" \
    || fail "boundary guard: the LLM hop '$label' must STAY model:'haiku' (not proxy-eligible — do not convert)"
done
# Positive assertion that the relocation actually happened: discover-run is now model:'bash',
# NOT a static model:'haiku' (guards against a silent regression that re-pins it to haiku).
dr_line=$(grep -nE "label: *[\`']discover-run:" "$JS" | grep "model:" || true)
[[ -n "$dr_line" ]] || fail "boundary guard: could not locate the discover-run hop option object"
echo "$dr_line" | grep -qE "model: *['\"]haiku['\"]" \
  && fail "boundary guard: discover-run is mechanized (id:24ec) — it must NOT be static model:'haiku' anymore"
echo "$dr_line" | grep -qE "model: *['\"]bash['\"]" \
  || fail "boundary guard: discover-run must dispatch model:'bash' (id:24ec mechanized shard)"
pass "boundary guard: discover-prelude (id:86a2) + discover-run (id:24ec) are both mechanized to model:'bash'; no LLM discovery hop remains pinned haiku"

echo "ALL PASS"
