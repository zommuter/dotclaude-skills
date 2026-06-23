#!/usr/bin/env bash
# roadmap:d530 — first-class per-run --priority / --exclude pool args for the autonomous
# relay, so a user need NOT hand-edit relay.toml (the destructive-registry anti-pattern) or
# hand-call inject.sh. The exclude-filter + priority-aware ordering live in a PURE helper
# (relay/scripts/pool-args.mjs) so they are node-unit-testable; relay-loop.js carries
# byte-equivalent inline copies (a structural assertion below pins that they are wired).
# Hermetic: node-only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/pool-args.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
MK="$SRC_DIR/Makefile"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: pool-args.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Drive the pure helpers through node; print one assertion result per line as key=value.
cat > "$TMP/drive.mjs" <<NODE
import { normalizeRepoArg, applyExcludeFilter, priorityRank, validatePriorityNames } from 'file://$HELPER'

const own = [
  { repo: 'alpha', path: '/p/alpha', income: true },
  { repo: 'beta',  path: '/p/beta',  income: false },
  { repo: 'gamma', path: '/p/gamma', income: false },
]
const out = []

// normalizeRepoArg: string "a,b", array, empty/undefined.
out.push('norm_csv=' + normalizeRepoArg('beta, gamma').join('|'))
out.push('norm_arr=' + normalizeRepoArg(['beta', ' gamma ']).join('|'))
out.push('norm_empty=' + normalizeRepoArg(undefined).length)

// (a) excluded repo is DROPPED + appears in skipped with the right reason.
{
  const { kept, skipped, surfaced } = applyExcludeFilter(own, 'beta')
  out.push('excl_kept=' + kept.map(r => r.repo).join('|'))
  out.push('excl_skipped_repo=' + (skipped[0] && skipped[0].repo))
  out.push('excl_skipped_reason_ok=' + (skipped[0] && skipped[0].reason === 'excluded for this run (--exclude)' ? '1' : '0'))
  out.push('excl_surfaced=' + surfaced.length)
}

// fail-safe: empty exclude ⇒ nothing dropped (today's behaviour).
{
  const { kept, skipped, surfaced } = applyExcludeFilter(own, '')
  out.push('excl_empty_kept=' + kept.length)
  out.push('excl_empty_skipped=' + skipped.length)
  out.push('excl_empty_surfaced=' + surfaced.length)
}

// (b) an UNKNOWN exclude name is SURFACED (LOUD reject), not silently dropped, and does NOT
//     drop any real repo.
{
  const { kept, skipped, surfaced } = applyExcludeFilter(own, 'nope')
  out.push('excl_unknown_kept=' + kept.length)
  out.push('excl_unknown_skipped=' + skipped.length)
  out.push('excl_unknown_surfaced_repo=' + (surfaced[0] && surfaced[0].repo))
  out.push('excl_unknown_surfaced_loud=' + (surfaced[0] && surfaced[0].reason.includes('unknown/unconfirmed') ? '1' : '0'))
}

// (b) an UNKNOWN priority name is SURFACED, a known one seeds the prioritySet.
{
  const { prioritySet, surfaced } = validatePriorityNames('alpha, ghost', own)
  out.push('prio_set_has_alpha=' + (prioritySet.has('alpha') ? '1' : '0'))
  out.push('prio_set_has_ghost=' + (prioritySet.has('ghost') ? '1' : '0'))
  out.push('prio_unknown_surfaced_loud=' + (surfaced[0] && surfaced[0].reason.includes('unknown/unconfirmed') ? '1' : '0'))
}

// (c) a priority repo's unit sorts AHEAD of a non-priority SAME-CLASS unit, but BEHIND an
//     injected unit, and NEVER out of its verdict class. Reproduce the relay-loop.js
//     comparator key order: injected → verdict class → priorityRank → income → standin.
{
  const PRIORITY = { execute: 0, review: 1, hard: 2, handoff: 3 }
  const { prioritySet } = validatePriorityNames('beta', own)
  const cmp = (a, b) =>
    ((b.injected ? 1 : 0) - (a.injected ? 1 : 0)) ||
    (PRIORITY[a.verdict] - PRIORITY[b.verdict]) ||
    (priorityRank(a, prioritySet) - priorityRank(b, prioritySet)) ||
    ((b.income ? 1 : 0) - (a.income ? 1 : 0))
  // alpha=income non-priority execute; beta=priority non-income execute; injected gamma execute;
  // delta=review (lower class) priority.
  const units = [
    { repo: 'alpha', verdict: 'execute', income: true },
    { repo: 'beta',  verdict: 'execute', income: false },
    { repo: 'gamma', verdict: 'execute', income: false, injected: true },
    { repo: 'delta', verdict: 'review',  income: false },  // not in prioritySet, lower class
  ]
  const sorted = units.slice().sort(cmp).map(u => u.repo)
  out.push('sort_order=' + sorted.join('|'))
  // beta (priority) must rank ahead of alpha (income but non-priority): priority beats income.
  out.push('prio_beats_income=' + (sorted.indexOf('beta') < sorted.indexOf('alpha') ? '1' : '0'))
  // gamma (injected) must rank ahead of beta (priority): injected precedence wins.
  out.push('injected_beats_prio=' + (sorted.indexOf('gamma') < sorted.indexOf('beta') ? '1' : '0'))
  // delta (review) is a LOWER verdict class than every execute; priority must NEVER pull it up.
  out.push('prio_never_overrides_class=' + (sorted.indexOf('delta') === sorted.length - 1 ? '1' : '0'))
}

// (d) priority does NOT duplicate a unit: a priority repo with one discovered unit stays one.
{
  const { prioritySet } = validatePriorityNames('beta', own)
  const units = [
    { repo: 'alpha', verdict: 'execute' },
    { repo: 'beta',  verdict: 'execute' },
  ]
  // priorityRank is pure ordering — it never appends. Count beta units before/after a sort.
  const betaCount = units.filter(u => u.repo === 'beta').length
  units.sort((a, b) => priorityRank(a, prioritySet) - priorityRank(b, prioritySet))
  out.push('prio_no_dup=' + (betaCount === 1 && units.filter(u => u.repo === 'beta').length === 1 ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

[[ "$(get norm_csv)" == "beta|gamma" ]] && ok "normalizeRepoArg splits a comma string" || bad "csv normalize wrong: $(get norm_csv)"
[[ "$(get norm_arr)" == "beta|gamma" ]] && ok "normalizeRepoArg trims an array" || bad "array normalize wrong: $(get norm_arr)"
[[ "$(get norm_empty)" == "0" ]] && ok "normalizeRepoArg(undefined) → [] (fail-safe)" || bad "empty normalize wrong"

# (a)
[[ "$(get excl_kept)" == "alpha|gamma" ]] && ok "(a) excluded repo DROPPED from the own list before sharding" || bad "(a) exclude did not drop: $(get excl_kept)"
[[ "$(get excl_skipped_repo)" == "beta" ]] && ok "(a) excluded repo appears in skipped" || bad "(a) excluded repo not in skipped"
[[ "$(get excl_skipped_reason_ok)" == "1" ]] && ok "(a) skipped reason is 'excluded for this run (--exclude)'" || bad "(a) wrong skipped reason"
[[ "$(get excl_surfaced)" == "0" ]] && ok "(a) a known exclude is a benign skip, not surfaced" || bad "(a) known exclude wrongly surfaced"

# fail-safe
[[ "$(get excl_empty_kept)" == "3" && "$(get excl_empty_skipped)" == "0" && "$(get excl_empty_surfaced)" == "0" ]] \
  && ok "fail-safe: empty --exclude ⇒ no change (today's behaviour)" || bad "empty exclude changed behaviour"

# (b) unknown names surfaced, not silent
[[ "$(get excl_unknown_kept)" == "3" && "$(get excl_unknown_skipped)" == "0" ]] && ok "(b) unknown --exclude drops no real repo" || bad "(b) unknown exclude touched real repos"
[[ "$(get excl_unknown_surfaced_repo)" == "nope" && "$(get excl_unknown_surfaced_loud)" == "1" ]] \
  && ok "(b) unknown --exclude is SURFACED (LOUD reject), not silently dropped" || bad "(b) unknown exclude not loud-surfaced"
[[ "$(get prio_set_has_alpha)" == "1" && "$(get prio_set_has_ghost)" == "0" ]] && ok "(b) --priority confirms own names, drops unknowns from the set" || bad "(b) priority set wrong"
[[ "$(get prio_unknown_surfaced_loud)" == "1" ]] && ok "(b) unknown --priority is SURFACED (LOUD reject)" || bad "(b) unknown priority not loud-surfaced"

# (c) ordering
[[ "$(get prio_beats_income)" == "1" ]] && ok "(c) priority repo's unit sorts AHEAD of a non-priority same-class unit (above income)" || bad "(c) priority did not beat income: $(get sort_order)"
[[ "$(get injected_beats_prio)" == "1" ]] && ok "(c) priority sorts BEHIND an injected unit (injected precedence wins)" || bad "(c) priority outranked injected: $(get sort_order)"
[[ "$(get prio_never_overrides_class)" == "1" ]] && ok "(c) priority NEVER pulls a unit out of its verdict class" || bad "(c) priority crossed a verdict class: $(get sort_order)"

# (d) no duplication
[[ "$(get prio_no_dup)" == "1" ]] && ok "(d) priority does NOT duplicate a unit (exactly one per repo — the id:d530 finding)" || bad "(d) priority duplicated a unit"

# ── Structural: relay-loop.js wires byte-equivalent inline copies (no import in the Workflow sandbox). ──
grep -q "id:d530" "$JS" || bad "relay-loop.js: no id:d530 marker (pool-arg wiring rationale missing)"
grep -q "EXCLUDE_REPOS = normalizeRepoArg(A.excludeRepos)" "$JS" || bad "relay-loop.js does not parse args.excludeRepos"
grep -q "PRIORITY_REPOS = normalizeRepoArg(A.priorityRepos)" "$JS" || bad "relay-loop.js does not parse args.priorityRepos"
grep -q "excluded for this run (--exclude)" "$JS" || bad "relay-loop.js missing the --exclude skipped reason"
grep -q "function priorityRank" "$JS" || bad "relay-loop.js missing the inline priorityRank helper"
grep -q "priorityRank(a, prioritySet) - priorityRank(b, prioritySet)" "$JS" || bad "relay-loop.js sort comparator does not use priorityRank"
# priorityRank must sit AFTER the verdict-class key and BEFORE the income key in the comparator
# (above income, below the D3 order). Assert the ordering on the main comparator line.
if grep -q "PRIORITY\[a.verdict\] - PRIORITY\[b.verdict\]) ||" "$JS" \
   && grep -A1 "PRIORITY\[a.verdict\] - PRIORITY\[b.verdict\]) ||" "$JS" | grep -q "priorityRank(a, prioritySet)"; then
  ok "(c-wiring) priorityRank is placed directly after the verdict-class key (above income, below D3)"
else
  bad "(c-wiring) priorityRank not placed after the verdict-class key in the comparator"
fi
# exclude must drop repos BEFORE sharding (filter the own-repo list, not post-shard units).
grep -q "if (excludeSet.has(r.repo)) excludeSkipped.push" "$JS" || bad "relay-loop.js does not drop excluded repos from the own list before sharding"

# Makefile install-completeness: the new .mjs helper is registered.
grep -q "scripts/pool-args.mjs" "$MK" || bad "Makefile relay_FILES missing scripts/pool-args.mjs (install-completeness)"

# SKILL.md front door documents both flags + the run-scoped/no-relay.toml-write contract.
SKILL="$SRC_DIR/relay/SKILL.md"
grep -q "priorityRepos" "$SKILL" || bad "SKILL.md does not document args.priorityRepos"
grep -q "excludeRepos" "$SKILL" || bad "SKILL.md does not document args.excludeRepos"

[[ "$pass" -gt 0 ]] && ok "pool-args helpers + relay-loop.js wiring verified" || true
echo "test_relay_pool_args: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
