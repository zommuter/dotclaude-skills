#!/usr/bin/env bash
# roadmap:4a46 — the handback event log must be COMPLETE: every REAL handback (a held
# worktree) must ALSO emit a `handback` event, and `assertHandbackInvariant` must catch a
# gap in EITHER direction (equality over the real-worktree subset), not just the forward
# `emitted ⊆ accumulator` direction it checks today.
#
# BACKGROUND (owner decision, relay human 2026-07-19): id:1735 split handbacks into a
# persistent accumulator (`state.handbacks`) + a per-round surfaced view, and added a loud
# backstop `assertHandbackInvariant(emittedEvents, accumulator)`. That backstop is ONE-
# DIRECTIONAL: it flags an emitted event with no accumulator entry, but NOT an accumulator
# entry (a real handback) with no emitted event. Today three `state.handbacks.push` sites in
# relay-loop.js do NOT emit an event: the terminal-child-failure site, the contract_met=false
# site (both REAL worktrees), and the id:5ac6 INTENSIVE fail-closed site (worktreePath:'-').
# So `~/.config/relay/relay-events.jsonl` under-reports real handbacks and the invariant
# cannot detect it. The owner ruled the log is meant to be COMPLETE: emit at the two REAL-
# worktree sites and tighten the invariant to equality — EXCLUDING the `worktreePath:'-'`
# INTENSIVE entry, exactly as `reconcileHandbacks` already excludes it.
#
# HONEST COVERAGE LIMIT (same as id:1735 precedent): relay-loop.js is a Workflow module that
# cannot be imported/executed in this harness (id:2ec4). The pure-helper cases below drive
# `assertHandbackInvariant` (handback-summary.mjs) directly through node — they cover the real
# LOGIC (the bidirectional equality). The structural grep only pins that relay-loop.js WIRES
# the two new emit sites; it does not prove they fire end-to-end in a live pool round.
#
# Hermetic: node-only, no git, no network, no ~/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-summary.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-summary.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Pure-logic cases: assertHandbackInvariant must be BIDIRECTIONAL (equality over the
#    real-worktree subset). ──────────────────────────────────────────────────────────────────
cat > "$TMP/drive.mjs" <<NODE
import { assertHandbackInvariant } from 'file://$HELPER'
const out = []

// (a) THE RED ASSERTION — reverse direction: an accumulator entry with a REAL worktree but NO
// matching emitted event is the exact under-report the owner ruled must be caught. Today's
// one-directional check MISSES this (returns ok:true); equality must flag it.
{
  const emitted = []  // nothing emitted
  const acc = [{ repo: 'loderite', reason: 'contract_met=false', worktreePath: '/cache/relay/worktrees/loderite/run1-execute' }]
  const inv = assertHandbackInvariant(emitted, acc)
  out.push('reverse_gap_flagged=' + (inv.ok === false && inv.violations.length >= 1 ? '1' : '0'))
  out.push('reverse_gap_names_repo=' + (inv.violations.some(v => v && v.repo === 'loderite') ? '1' : '0'))
}

// (b) forward direction PRESERVED: an emitted event with no accumulator entry is still a violation.
{
  const emitted = [{ repo: 'ghost-repo', reason: 'never recorded' }]
  const acc = []
  const inv = assertHandbackInvariant(emitted, acc)
  out.push('forward_gap_flagged=' + (inv.ok === false && inv.violations.some(v => v && v.repo === 'ghost-repo') ? '1' : '0'))
}

// (c) INTENSIVE exclusion: an accumulator entry with worktreePath:'-' and NO emitted event is
// NOT a violation (it is not a handback in the summary sense — mirrors reconcileHandbacks).
{
  const emitted = []
  const acc = [{ repo: 'intense', reason: 'INTENSIVE fail-closed (id:5ac6)', worktreePath: '-' }]
  const inv = assertHandbackInvariant(emitted, acc)
  out.push('intensive_dash_not_violation=' + (inv.ok === true && inv.violations.length === 0 ? '1' : '0'))
}

// (c2) INTENSIVE exclusion with a real handback alongside: only the real one is checked; the
// dash entry contributes no reverse violation, and the real one IS matched by its event.
{
  const emitted = [{ repo: 'a', reason: 'real' }]
  const acc = [
    { repo: 'a', reason: 'real', worktreePath: '/cache/relay/worktrees/a/run1' },
    { repo: 'b', reason: 'INTENSIVE fail-closed', worktreePath: '-' },
  ]
  const inv = assertHandbackInvariant(emitted, acc)
  out.push('mixed_only_real_checked=' + (inv.ok === true && inv.violations.length === 0 ? '1' : '0'))
}

// (d) full bidirectional match ⇒ ok:true, no violations.
{
  const emitted = [{ repo: 'x', reason: 'r1' }, { repo: 'y', reason: 'r2' }]
  const acc = [
    { repo: 'x', reason: 'r1', worktreePath: '/w/x' },
    { repo: 'y', reason: 'r2', worktreePath: '/w/y' },
  ]
  const inv = assertHandbackInvariant(emitted, acc)
  out.push('full_match_ok=' + (inv.ok === true && inv.violations.length === 0 ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

[[ "$(get reverse_gap_flagged)" == "1" ]] && ok "a real-worktree accumulator entry with NO emitted event is flagged (reverse direction — the RED assertion)" || bad "reverse gap NOT flagged: assertHandbackInvariant is still one-directional (emitted ⊆ accumulator only)"
[[ "$(get reverse_gap_names_repo)" == "1" ]] && ok "the reverse violation names the under-reported repo" || bad "reverse violation does not name the repo"
[[ "$(get forward_gap_flagged)" == "1" ]] && ok "forward direction preserved: an emitted event with no accumulator entry is still a violation" || bad "forward direction regressed"
[[ "$(get intensive_dash_not_violation)" == "1" ]] && ok "an accumulator entry with worktreePath:'-' (INTENSIVE) and no event is NOT a violation" || bad "INTENSIVE worktreePath:'-' entry wrongly flagged as a reverse violation"
[[ "$(get mixed_only_real_checked)" == "1" ]] && ok "with a real + a dash entry, only the real one is subject to the reverse check" || bad "mixed real/dash accumulator mis-handled"
[[ "$(get full_match_ok)" == "1" ]] && ok "full bidirectional match ⇒ ok:true, no violations" || bad "full match should be clean"

# ── Structural backstop: relay-loop.js must emit at the two REAL-worktree handback sites that
#    are silent today (terminal-child-failure + contract_met=false), so emittedHandbackEvents is
#    pushed at >=4 sites (up from 2). The id:5ac6 INTENSIVE site stays non-emitting. ────────────
emit_sites=$(grep -cE 'emittedHandbackEvents\.push\(' "$JS" || true)
[[ "$emit_sites" -ge 4 ]] && ok "relay-loop.js pushes emittedHandbackEvents at >=4 sites ($emit_sites found — the two missing real-worktree sites now emit)" || bad "only $emit_sites emittedHandbackEvents.push site(s); expected >=4 (the terminal-fail + contract_met=false sites must now emit)"

# The INTENSIVE fail-closed handback (worktreePath:'-') must remain, and must NOT gain an emit —
# its presence is the exclusion the equality relies on.
grep -qE "worktreePath:\s*'-'" "$JS" && ok "the INTENSIVE fail-closed handback (worktreePath:'-') is still present (the deliberate non-emitting exclusion)" || bad "the worktreePath:'-' INTENSIVE handback entry is gone — the exclusion the equality relies on is missing"

echo "test_handback_invariant_equality: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
