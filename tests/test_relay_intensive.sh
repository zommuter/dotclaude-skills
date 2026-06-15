#!/usr/bin/env bash
# roadmap:8d52 — [INTENSIVE — <resource>] gating in relay-loop.js (cluster step 5).
# Resource-heavy units (local-LLM benchmarks, big index rebuilds — the OOM risk that killed
# 6 sessions) are NEVER auto-dispatched; with --allow-intensive/--afk they run SERIALLY-ALONE
# after the normal wave, holding an exclusive resource:<name> claim. Static checks (live
# dispatch is the id:1ad7 pilot).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
command -v node >/dev/null && { node --check "$JS" || fail "relay-loop.js is not valid JS"; }

# (1) Opt-in flag: --allow-intensive / --afk.
grep -q "const ALLOW_INTENSIVE = !!A.allowIntensive || !!A.afk" "$JS" \
  || fail "ALLOW_INTENSIVE not derived from args.allowIntensive / args.afk"
pass "opt-in gate ALLOW_INTENSIVE (--allow-intensive / --afk)"

# (2) Discovery parses the tag (schema + prompt).
grep -qE "intensive: \{ type: 'string' \}" "$JS" || fail "DISCOVER_SCHEMA missing the 'intensive' field"
grep -q "INTENSIVE — <resource>" "$JS" || fail "discovery prompt does not parse the [INTENSIVE — <resource>] modifier"
pass "discovery detects [INTENSIVE — <resource>] (+ relay.toml intensive flag)"

# (3) Partition: intensive units pulled out of the parallel wave; gated when not allowed.
grep -q "intensiveUnits" "$JS" || fail "no intensiveUnits partition"
grep -q "intensiveDeferred" "$JS" || fail "no intensiveDeferred (skipped) partition"
grep -q "ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred" "$JS" \
  || fail "intensive units are not gated on ALLOW_INTENSIVE at partition time"
grep -qi "needs --allow-intensive" "$JS" || fail "skipped intensive units not surfaced with the reason"
pass "intensive units partitioned out + surfaced when not allowed (never auto-run)"

# (4) Serial run-alone phase AFTER the wave drains (two heavy loads never overlap).
grep -q "serial run-alone" "$JS" || fail "no serial run-alone phase for intensive units"
# the serial loop must drain each unit's integration before the next
awk '/for \(const unit of intensiveUnits\)/{f=1} f&&/Promise.all\(debts\)/{ok=1} END{exit ok?0:1}' "$JS" \
  || fail "serial intensive loop does not drain integration between units"
pass "intensive units run serially-alone after the parallel wave"

# (5) Exclusive resource claim: acquire in unitPrompt, release in integrator.
grep -q "claim.sh acquire resource:" "$JS" || fail "intensive unit does not acquire an exclusive resource: claim"
grep -q "claim.sh release resource:" "$JS" || fail "integrator does not release the resource: claim"
pass "intensive units hold an exclusive resource:<name> claim (cross-run)"

echo "ALL PASS: [INTENSIVE] gating + run-alone + resource claim (id:8d52)"
