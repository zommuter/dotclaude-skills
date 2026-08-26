#!/usr/bin/env bash
# No `# roadmap:` header — id:2e7a is a TODO-ledger defect fix with no ROADMAP item, so its
# failures ALWAYS count (never EXPECTED-RED). Deliberate, per tests/README conventions.
#
# id:2e7a — relay-loop.js's mechArg() must neutralise the four command-substitution markers
# (backtick, `$(`, `<(`, `>(`) before fencing an argument into a mechanical hop.
#
# THE INCIDENT (run relay-20260826-122101-7415, 2026-08-26): three integrate hops —
# [integrate:git-annex] ×1, [integrate:lean4btc] ×2 — failed with "There's an issue with the
# selected model (bash)". That is the 404 signature of mechanical-proxy.py REFUSING the hop and
# FAILING OPEN to the real API. Cause: `_command_allowed()` (mechanical-proxy.py) refuses those
# markers ANYWHERE in the command via a BARE SUBSTRING scan with no quote-awareness — unlike its
# quote-aware siblings for sequence operators and redirection. Executor summaries quote command
# names in markdown backticks routinely ("added `toc` subcommand", "`lake exe bench`"), so a
# perfectly safe single-quoted backtick in prose killed the hop. It fired on CONTENT, not on any
# repo property — which is exactly why it looked intermittent (git-annex integrated FINE twice
# the same run with differently-worded summaries).
#
# NOT tested here, deliberately: loosening `_command_allowed()`. That was tried and REVERTED —
# it breaks test_mech_stdin_channel_33b2.sh (id:a05c), which ratifies that even a SAFELY
# single-quoted backtick stays refused. The proxy's paranoia is the contract; the emitting side
# is what had to change.
#
# Hermetic: reads two repo files, executes mechArg extracted VERBATIM from relay-loop.js (never
# hand-duplicated), and calls the REAL _command_allowed(). No ~/.claude, no ~/.config/relay,
# no network, no writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
PROXY="$SRC_DIR/relay/scripts/mechanical-proxy.py"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass + 1)); }
bad() { echo "FAIL: $*"; fail=$((fail + 1)); }

[[ -f "$JS"    ]] || { echo "FAIL: relay-loop.js not found";       exit 1; }
[[ -f "$PROXY" ]] || { echo "FAIL: mechanical-proxy.py not found"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. Extract mechArg VERBATIM from relay-loop.js and exercise it. Extraction (not a
# hand-written copy) is the point: a future edit that drops a replace() must fail this test. ──
awk '/^const mechArg = /{f=1} f{print} f&&/\+ "'"'"'"$/{exit}' "$JS" > "$TMP/mecharg.js"
# `awk` with no early-exit-on-pipe; no `| head` (id:81d5 pipefail lint).
if [[ -s "$TMP/mecharg.js" ]]; then
  ok "extracted mechArg() verbatim from relay-loop.js"
else
  bad "could not extract mechArg() from relay-loop.js"; echo "$pass passed, $fail failed"; exit 1
fi

cat >> "$TMP/mecharg.js" <<'NODE'
const cases = [
  ['annex-catalogue: added `toc` subcommand exporting a drive-toc-compatible gzipped TSV', 'git-annex live casualty'],
  ['lean4btc: `lake exe bench` regression', 'lean4btc live casualty'],
  ['uses $(date) inline', 'dollar-paren'],
  ['uses <(cmd) and >(cmd)', 'process substitution'],
]
const out = {}
for (const [text, name] of cases) out[name] = mechArg(text)
console.log(JSON.stringify(out))
NODE
sanitised_json="$(node "$TMP/mecharg.js")"

for marker in '`' '$(' '<(' '>('; do
  if [[ "$sanitised_json" == *"$marker"* ]]; then
    bad "mechArg() output still contains the refused marker: $marker"
  else
    ok "mechArg() neutralises $marker"
  fi
done

# ── 2. The assertion that actually matters: feed the REAL predicate a reconstructed integrate
# command, sanitised vs raw. The raw side is the NEGATIVE CONTROL and must be observed FAILING —
# an unreached or erroring fixture is not a passing negative control. ──
verdicts="$(python3 - "$PROXY" "$sanitised_json" <<'PY'
import importlib.util, json, sys
proxy_path, sanitised = sys.argv[1], json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("mechanical_proxy", proxy_path)
mp = importlib.util.module_from_spec(spec); spec.loader.exec_module(mp)
P = "~/.claude/skills/relay/scripts/integrate.sh"
raw = P + " --repo 'git-annex' --summary 'added `toc` subcommand' --label 'executor (sonnet)'"
san = P + " --repo 'git-annex' --summary " + sanitised['git-annex live casualty'] + " --label 'executor (sonnet)'"
print("True" if mp._command_allowed(raw) else "False")
print("True" if mp._command_allowed(san) else "False")
PY
)"
mapfile -t v <<< "$verdicts"   # array, not `| sed -n Np | grep -q` (id:81d5 pipefail lint)

[[ "${v[0]:-}" == "False" ]] \
  && ok "NEGATIVE CONTROL observed failing: the RAW backtick summary is REJECTED by the real _command_allowed() (this is the live 404)" \
  || bad "negative control did not reproduce — raw backtick summary was ACCEPTED, so this test proves nothing"

[[ "${v[1]:-}" == "True" ]] \
  && ok "the mechArg-sanitised integrate command is ACCEPTED by the real _command_allowed() (no silent 404)" \
  || bad "sanitised integrate command is STILL rejected — the hop would fail open and 404"

# ── 3. Guard the comment that caused the bug: the old text asserted backticks are "preserved
# VERBATIM", which is true of bash and false of the proxy. It must not come back. ──
if grep -q 'is inert inside single quotes and is preserved VERBATIM' "$JS"; then
  bad "the pre-id:2e7a claim that backticks are 'preserved VERBATIM' is back in relay-loop.js — it is false of the proxy and caused the outage"
else
  ok "relay-loop.js no longer claims command-substitution markers are preserved verbatim"
fi

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
