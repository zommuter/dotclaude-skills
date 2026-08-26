#!/usr/bin/env bash
# roadmap:7354 — the id:1432 repeat-handback ALERT must count EVERY handback, not just
# the child-report one.
#
# RED SPEC authored at review 2026-08-26 (run relay-20260826-122101-7415).
#
# INCIDENT: RELAY_STATUS.md's "## Repeat-handback ALERTs (id:1432 — >=2× this run, a bug
# signal)" printed `_(none)_` while the Blocked section of the SAME file listed `lean4btc`
# twice and `it-infra` twice. On the section's own stated threshold both should have alerted.
#
# DIAGNOSIS (verified against the code, and it REFUTES the hypothesis id:7354 was filed with —
# the TODO guessed the counter keys on a per-attempt worktree suffix): `trackHandback()` keys
# on `${repo}:${verdict}`, which is exactly right. The defect is at the CALL SITES:
# relay-loop.js has 11 `state.handbacks.push(` sites and `trackHandback(handbackTracker, …)`
# is called at exactly ONE of them (the child-report path). Every other blocked path —
# integrate failure, landed-unfinished, prompt-size gate, provisioning failure, sibling
# conflict, INTENSIVE fail-closed, terminal child failure — lands in the Blocked section but
# never increments the tracker. So the ALERT can only ever fire for the case that is least
# likely to repeat, and is structurally blind to a repo failing the same way twice, which is
# the entire point of id:1432. [[relay-builtgreen-but-unreferenced]] shape.
#
# SPEC: every accumulator push is tracked. The check is PROXIMITY-based, not a count match, so
# a legitimate refactor into a single `recordHandback()` helper (push + track together) passes.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LOOP" ]] || fail "relay-loop.js not found at $LOOP"
node --check "$LOOP" || fail "relay-loop.js fails node --check"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ── (1) the tracker keys on (repo, verdict) — the property the TODO wrongly doubted ────────
awk '/^function trackHandback\(/,/^\}$/' "$LOOP" > "$tmpdir/track.js"
grep -q 'function trackHandback' "$tmpdir/track.js" \
  || fail "could not extract trackHandback from relay-loop.js"
grep -Eq '\$\{repo\}:\$\{verdict\}' "$tmpdir/track.js" \
  || fail "trackHandback no longer keys on (repo, verdict) — a per-attempt key can never repeat"
pass "trackHandback keys on (repo, verdict)"

# ── (2) EVERY state.handbacks.push site is accompanied by a tracker registration ───────────
# Proximity window: a push and its tracking call must sit within +/-10 lines of each other,
# so a single push+track helper satisfies this as easily as per-site calls do.
mapfile -t push_lines < <(grep -n 'state\.handbacks\.push(' "$LOOP" | cut -d: -f1)
[[ ${#push_lines[@]} -gt 0 ]] || fail "no state.handbacks.push( sites found — the accumulator moved; re-derive this spec"

untracked=()
for ln in "${push_lines[@]}"; do
  lo=$(( ln - 10 )); [[ $lo -lt 1 ]] && lo=1
  hi=$(( ln + 10 ))
  if ! grep -q 'trackHandback(' < <(sed -n "${lo},${hi}p" "$LOOP"); then
    untracked+=( "$ln" )
  fi
done

if [[ ${#untracked[@]} -gt 0 ]]; then
  echo "FAIL: ${#untracked[@]} of ${#push_lines[@]} state.handbacks.push( site(s) never reach trackHandback()," >&2
  echo "      so a repo blocked via these paths can hand back N times and the id:1432 ALERT stays _(none)_:" >&2
  for ln in "${untracked[@]}"; do
    printf '    relay-loop.js:%s  %s\n' "$ln" "$(sed -n "${ln}p" "$LOOP" | sed 's/^ *//' | cut -c1-110)" >&2
  done
  exit 1
fi
pass "all ${#push_lines[@]} handback-accumulator sites register with the repeat-handback tracker"

# ── (3) behavioural: two handbacks from a NON-child path must produce an alert ─────────────
awk '/^function trackHandback\(/,/^\}$/'  "$LOOP" >  "$tmpdir/alerts.js"
awk '/^function handbackAlerts\(/,/^\}$/' "$LOOP" >> "$tmpdir/alerts.js"
grep -q 'function handbackAlerts' "$tmpdir/alerts.js" \
  || fail "could not extract handbackAlerts from relay-loop.js"

cat >> "$tmpdir/alerts.js" <<'JS'
const bad = []
const t = {}
// The observed incident: the SAME repo+verdict blocked twice on an integrate failure —
// two distinct worktrees (…-hard-repo-0 / …-hard-repo-1), one repo, one verdict.
trackHandback(t, 'lean4btc', 'hard', 'integrate.sh produced no merged= line')
trackHandback(t, 'lean4btc', 'hard', 'integrate.sh produced no merged= line')
trackHandback(t, 'it-infra', 'handoff', 'prompt-size gate: NOT dispatched')
trackHandback(t, 'it-infra', 'handoff', 'prompt-size gate: NOT dispatched')
trackHandback(t, 'quiet-repo', 'execute', 'one-off')

const alerts = handbackAlerts(t, 2)
if (alerts.length !== 2) bad.push('expected 2 alerts at threshold 2, got ' + alerts.length)
if (!alerts.some(a => a.repo === 'lean4btc' && a.count === 2)) bad.push('lean4btc x2 did not alert')
if (!alerts.some(a => a.repo === 'it-infra' && a.count === 2)) bad.push('it-infra x2 did not alert')
if (alerts.some(a => a.repo === 'quiet-repo')) bad.push('a single handback alerted (cry-wolf)')

if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS

node "$tmpdir/alerts.js" >"$tmpdir/out" 2>&1 \
  || { echo "FAIL: repeat handbacks from a non-child path do not alert:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "two same-(repo,verdict) handbacks alert; a single one does not"

# ── (4) the engine still lints (backtick-in-template hazard, the id:5bac crash class) ──────
LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || fail "relay-loop.js has a template-literal violation after the 7354 edit"
  pass "relay-loop.js passes the workflow-template lint"
fi

echo "ALL PASS: every handback path feeds the id:1432 repeat-handback ALERT (7354)"
