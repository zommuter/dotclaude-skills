#!/usr/bin/env bash
# roadmap:d58f — fleet-quiescence drain: the loop must wind down when all remaining work is
# gated/finished instead of spinning rounds re-confirming an already-drained fleet. The
# substantive-progress predicate + the wind-down classifier live in a PURE helper
# (relay/scripts/drain.mjs) so they are node-unit-testable; relay-loop.js carries byte-equivalent
# inline copies (a structural assertion below pins the wiring). Hermetic: node-only, no git/net.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/drain.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
MK="$SRC_DIR/Makefile"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: drain.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/drive.mjs" <<NODE
import { unitIsSubstantive, classifyDrainBacklog } from 'file://$HELPER'
const out = []

// unitIsSubstantive: execute/hard/handoff checkpoints are always substantive.
out.push('exec=' + unitIsSubstantive('execute', {}))
out.push('hard=' + unitIsSubstantive('hard', {}))
out.push('handoff=' + unitIsSubstantive('handoff', {}))

// review: substantive ONLY if it changed the backlog.
out.push('review_reopened=' + unitIsSubstantive('review', { reopened: ['id1'], routine_open: 0, gaming_flags: [] }))
out.push('review_routine=' + unitIsSubstantive('review', { reopened: [], routine_open: 2, gaming_flags: [] }))
out.push('review_gaming=' + unitIsSubstantive('review', { reopened: [], routine_open: 0, gaming_flags: ['x: skipped'] }))
// THE key case: a confirming-only review (verified-green, reopened/added nothing) is NOT progress.
out.push('review_confirming=' + unitIsSubstantive('review', { reopened: [], routine_open: 0, gaming_flags: [], verified_green: ['a','b'] }))
out.push('review_null=' + unitIsSubstantive('review', null))

// classifyDrainBacklog buckets by reason + names the gated repos with a human pointer.
{
  const blocked = [
    { repo: 'fin1', reason: 'finished repo (0 open items, clean, no unaudited commits) — not dispatched (anti-false-handoff guard id:000d)' },
    { repo: 'gate1', reason: 'HARD backlog is gated — needs a /meeting to unblock/re-scope (items: id:abcd [HARD — meeting])' },
    { repo: 'gate2', reason: 'HARD backlog is [HARD — hands] only (open_hard_pool=0)' },
    { repo: 'cb1', reason: 'circuit breaker (id:365b): cb1 idle dispatched >3x this run with no substantive change' },
    { repo: 'dirty1', reason: "dirty main tree (porcelain: ' M ROADMAP.md') — not dispatched" },
  ]
  const c = classifyDrainBacklog(blocked)
  out.push('cls_finished=' + c.finished.join('|'))
  out.push('cls_gated=' + c.gated.join('|'))
  out.push('cls_cb=' + c.circuitBroken.join('|'))
  out.push('cls_dirty=' + c.dirty.join('|'))
  out.push('cls_summary_has_human=' + (/\/relay human|\/meeting/.test(c.summary) ? '1' : '0'))
  out.push('cls_summary_names_gated=' + (c.summary.includes('gate1') && c.summary.includes('gate2') ? '1' : '0'))
}
// empty backlog → benign summary, no crash.
out.push('cls_empty=' + classifyDrainBacklog([]).summary)
out.push('cls_undef=' + classifyDrainBacklog(undefined).summary)

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

# unitIsSubstantive
[[ "$(get exec)" == "true" && "$(get hard)" == "true" && "$(get handoff)" == "true" ]] \
  && ok "execute/hard/handoff checkpoints are always substantive" || bad "work-verdict substantive wrong"
[[ "$(get review_reopened)" == "true" ]] && ok "a review that reopened a ROADMAP item is substantive" || bad "reopened review not substantive"
[[ "$(get review_routine)" == "true" ]] && ok "a review that surfaced open [ROUTINE] (routine_open>0) is substantive" || bad "routine_open review not substantive"
[[ "$(get review_gaming)" == "true" ]] && ok "a review that raised a gaming flag is substantive" || bad "gaming-flag review not substantive"
[[ "$(get review_confirming)" == "false" ]] \
  && ok "a CONFIRMING-only review (verified-green, reopened/added nothing) is NOT substantive — the spin-stopper (id:d58f)" \
  || bad "confirming-only review wrongly counted substantive — the pool would never drain"
[[ "$(get review_null)" == "false" ]] && ok "a null/garbled review report is conservatively NON-substantive" || bad "null review wrongly substantive"

# classifyDrainBacklog
[[ "$(get cls_finished)" == "fin1" ]] && ok "finished repos bucketed" || bad "finished bucket wrong: $(get cls_finished)"
[[ "$(get cls_gated)" == "gate1|gate2" ]] && ok "gated [HARD] repos bucketed (meeting + hands lanes)" || bad "gated bucket wrong: $(get cls_gated)"
[[ "$(get cls_cb)" == "cb1" ]] && ok "circuit-broken repos bucketed" || bad "circuit-broken bucket wrong: $(get cls_cb)"
[[ "$(get cls_dirty)" == "dirty1" ]] && ok "dirty repos bucketed" || bad "dirty bucket wrong: $(get cls_dirty)"
[[ "$(get cls_summary_has_human)" == "1" ]] && ok "wind-down summary points the human at /relay human or /meeting" || bad "summary lacks human pointer"
[[ "$(get cls_summary_names_gated)" == "1" ]] && ok "wind-down summary NAMES the gated repos to take to a human" || bad "summary does not name gated repos"
[[ -n "$(get cls_empty)" && -n "$(get cls_undef)" ]] && ok "classifyDrainBacklog handles empty/undefined without crashing" || bad "empty/undefined backlog crashed"

# ── Structural: relay-loop.js wires byte-equivalent inline copies + flips the dry check. ──
grep -q "id:d58f" "$JS" || bad "relay-loop.js: no id:d58f marker (drain wiring rationale missing)"
grep -q "function unitIsSubstantive" "$JS" || bad "relay-loop.js missing the inline unitIsSubstantive helper"
grep -q "function classifyDrainBacklog" "$JS" || bad "relay-loop.js missing the inline classifyDrainBacklog helper"
grep -q "substantive: unitIsSubstantive(unit.verdict, report)" "$JS" || bad "relay-loop.js does not tag completions with substantive"
# id:4ca8 (2026-07-17): the dry-detector was extracted into the isDryRound(r) pure predicate
# (relay/scripts/drain.mjs) so it could also distinguish a genuinely-empty round from a
# BLOCKED one (isBlockedRound) — see tests/test_relay_loop_drain_vs_blocked.sh for that spec.
# The underlying key (substantive, not produced) is unchanged; only the call site's shape is.
grep -q "if (isDryRound(r))" "$JS" || bad "relay-loop.js dry-detector is not gated on isDryRound(r)"
grep -q "(r.substantive || 0) === 0 && (r.surfaced || 0) === 0" "$JS" || bad "relay-loop.js dry-detector does not key on r.substantive (still on produced?)"
grep -q "classifyDrainBacklog(state.surfaced)" "$JS" || bad "relay-loop.js does not emit the wind-down backlog summary on drain"
# regression guard: the dry detector must NOT have been left keyed on produced.
grep -q "if ((r.produced || 0) === 0)" "$JS" && bad "relay-loop.js still has the old produced-based dry check (id:d58f not applied)" || ok "old produced-based dry check is gone (id:d58f applied)"

# Makefile install-completeness: the new .mjs helper is registered.
grep -q "scripts/drain.mjs" "$MK" || bad "Makefile relay_FILES missing scripts/drain.mjs (install-completeness)"

[[ "$pass" -gt 0 ]] && ok "drain helpers + relay-loop.js wiring verified" || true
echo "test_relay_drain: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
