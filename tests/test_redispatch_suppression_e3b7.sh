#!/usr/bin/env bash
# roadmap:e3b7 — re-dispatch SUPPRESSION after a context death (in-sandbox half of id:61fa).
#
# Defect: the `report == null` terminal-fail path in relay-loop.js's integrate() (a child
# died with no report at all — API error / context death) pushes a handback but does NOT
# stamp the id:1432 noWorkNegCache. Only the `contract_met=false` + route=none path stamps it
# (see test_handback_guard.sh). Combined with the discovery signature cache reusing an
# unchanged verdict, the SAME repo can re-dispatch straight back into the identical death next
# round (observed: 2x same-day deaths on 2026-07-26).
#
# Fix: on a null-report handback, ALSO call recordNoWorkHandback(noWorkNegCache, unit.repo,
# unit.verdict, unit.work_sig || '') — reusing the SAME pure helper + negative-cache object
# the route=none path already uses, so applyNoWorkSuppression's existing pre-filter (and its
# existing RELAY_STATUS "Blocked" surfacing via `surfaced.push`) suppresses the re-dispatch for
# free. A NORMAL handback (contract_met=false with a route) must keep today's behaviour
# unchanged — this only adds the null-report case.
#
# This is the in-sandbox half of id:61fa: no filesystem access needed, a pure cache stamp.
# Parent id:61fa keeps the transcript-parsing half (BLOCKED on the Workflow-sandbox-has-no-fs
# architecture question).
#
# Hermetic: node + grep only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-guard.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-guard.mjs missing"; exit 1; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- (1) Functional: the SAME negative-cache mechanism a null-report stamp would drive ------
# (recordNoWorkHandback / applyNoWorkSuppression are the pure helpers relay-loop.js's
# null-report branch must call; this proves the mechanism suppresses correctly once stamped.)
cat > "$TMP/drive.mjs" <<NODE
import { recordNoWorkHandback, applyNoWorkSuppression } from 'file://$HELPER'
const out = []

// A null-report (context-death) handback for loderite/execute stamps the negative cache
// with the work_sig that was in flight when the child died.
const neg = {}
recordNoWorkHandback(neg, 'loderite', 'execute', 'SIG-DEATH')

// Same work_sig next round (repo's ROADMAP hasn't shrunk) → SUPPRESSED, not re-dispatched
// straight back into the identical death.
{
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'loderite', verdict: 'execute', work_sig: 'SIG-DEATH' }], neg, 'run1')
  out.push('samesig_kept=' + kept.length)
  out.push('samesig_suppressed=' + suppressed.length)
  if (suppressed.length) out.push('samesig_reason_mentions_suppression=' + (/suppress/i.test(suppressed[0].reason) ? '1' : '0'))
}

// The repo's ROADMAP genuinely shrinks (work_sig changes) → suppression clears, re-dispatch resumes.
{
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'loderite', verdict: 'execute', work_sig: 'SIG-FIXED' }], neg, 'run1')
  out.push('changedsig_kept=' + kept.length)
  out.push('changedsig_suppressed=' + suppressed.length)
}

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

[[ "$(get samesig_kept)" == "0" && "$(get samesig_suppressed)" == "1" ]] && ok "null-report handback, same work_sig ⇒ SUPPRESSED (not re-dispatched into the same death)" || bad "same-sig should suppress after a stamped death"
[[ "$(get samesig_reason_mentions_suppression)" == "1" ]] && ok "suppression reason is not silent — names the suppression" || bad "suppression reason missing"
[[ "$(get changedsig_kept)" == "1" && "$(get changedsig_suppressed)" == "0" ]] && ok "work_sig genuinely changes ⇒ re-dispatch resumes" || bad "changed sig should clear suppression"

# --- (2) Structural: relay-loop.js's null-report branch must stamp the negative cache ------
# Extract the `if (!report) { ... }` block bounded to the FIRST such block in integrate() (the
# terminal-fail / context-death path) and assert it calls recordNoWorkHandback — today it only
# pushes a handback and returns, silently skipping the stamp that the contract_met=false/
# route=none sibling branch already does.
#
# id:98ea — extraction is by BRACE DEPTH, not by matching a hardcoded terminator line. The
# prior `/^  return$/` terminator assumed a 2-space-indented bare `return` closes the block;
# relay-loop.js actually 4-space-indents it (`    return`), so that terminator NEVER matched
# and the "block" silently ran to EOF (674 of 2600 lines captured), making the structural
# assertions below pass or fail on text far outside the intended branch — a latent false-pass/
# false-fail generator independent of any timing flake. Brace counting is robust to
# reindentation and doesn't encode an assumption about how the block happens to be formatted.
NULL_REPORT_BLOCK="$(awk '
  /if \(!report\) \{/ { flag=1; depth=0 }
  flag {
    print
    line=$0
    opens=gsub(/\{/,"{",line)
    closes=gsub(/\}/,"}",line)
    depth+=opens-closes
    if (depth==0) exit
  }
' "$JS")"
[[ -n "$NULL_REPORT_BLOCK" ]] || { echo "FAIL: could not locate the 'if (!report)' branch in $JS"; exit 1; }

echo "$NULL_REPORT_BLOCK" | grep -q "recordNoWorkHandback(noWorkNegCache, unit.repo, unit.verdict" \
  && ok "relay-loop.js's null-report (context-death) branch stamps noWorkNegCache" \
  || bad "relay-loop.js's null-report branch does NOT call recordNoWorkHandback — a context-death repo can re-dispatch straight back into the same death"

echo "$NULL_REPORT_BLOCK" | grep -q "id:e3b7" \
  && ok "null-report suppression stamp is tagged id:e3b7" \
  || bad "null-report suppression stamp missing an id:e3b7 tag"

# --- (3) Regression guard: a NORMAL handback (route present, e.g. decision-gate/hard-split)
# must keep today's behaviour — it is durably gated by handback-followup.py (id:3801) instead,
# and must NOT also get double-stamped into the whole-dispatch negative cache.
CONTRACT_MET_BLOCK="$(awk '/if \(!report\.contract_met\) \{/{flag=1} flag{print} /durableHandbackFollowup\(unit, report\)/{exit}' "$JS")"
[[ -n "$CONTRACT_MET_BLOCK" ]] || { echo "FAIL: could not locate the contract_met=false branch in $JS"; exit 1; }
echo "$CONTRACT_MET_BLOCK" | grep -q "report.route === 'none'" \
  && ok "the contract_met=false branch still gates its own stamp on route=none (unchanged)" \
  || bad "regression: contract_met=false branch's route=none gate was removed"

echo "test_redispatch_suppression_e3b7: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
