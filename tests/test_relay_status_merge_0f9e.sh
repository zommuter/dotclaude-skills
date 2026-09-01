#!/usr/bin/env bash
# id:0f9e — RELAY_STATUS.md is merged per-run, not replaced wholesale. (Defect-fix test: no
# ROADMAP item, so no `roadmap:` header — its failures always count, never expected-red.)
#
# Trigger (observed live 2026-08-18): RELAY_STATUS_PATH is ONE global path with no runId in it
# (relay-loop.js:43) and buildRelayStatus renders the WHOLE file from ONE run's state, while
# id:11c6's singleton guard EXEMPTS --afk and every directed/scoped mode — so parallel pools are
# the DESIGNED normal case. The write was atomic but last-writer-wins, so at any instant the file
# described exactly one run and every other live run's status was gone (loderite
# relay-20260818-154017-12780 overlapping cartulary relay-20260818-152657-28729; csgebra
# relay-20260818-205434-31345 alongside the discovery producer). Atomicity prevents a TORN write,
# never a LOST update — the two are different properties and only the first was held.
#
# Hermetic: sandboxed HOME/FABLES_CONFIG/HEARTBEAT_BASE under mktemp; no network, no ~/.claude.
# fails-against: rev 3357bf43c352 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/lib-ledger-only-diff.sh, relay/scripts/relay-loop.js, relay/scripts/relay-status-publish.sh (+2 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 3357bf43c352 -- relay/scripts/lib-ledger-only-diff.sh relay/scripts/relay-loop.js relay/scripts/relay-status-publish.sh relay/scripts/status-accounting.mjs relay/scripts/verify-isolation.sh
# fails-against-assertion: (1) two live runs must yield TWO run sections, got

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$SRC_DIR/relay/scripts/relay-status-publish.sh"
HB="$SRC_DIR/relay/scripts/heartbeat.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$PUB" ]] || fail "relay-status-publish.sh not found/executable"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export FABLES_CONFIG="$TMP/.config/relay"
export HEARTBEAT_BASE="$TMP/hb"
mkdir -p "$FABLES_CONFIG" "$HEARTBEAT_BASE"
STATUS="$FABLES_CONFIG/RELAY_STATUS.md"
EVENTS="$FABLES_CONFIG/relay-events.jsonl"

body() {  # $1=runId $2=inflight $3=completed $4=blocked
  printf '# RELAY_STATUS — last updated 2026-08-18T21:00:00+02:00  run: %s\n\n## Run progress\n- round=1\n- in-flight=%s\n- completed=%s\n- blocked=%s\n' "$1" "$2" "$3" "$4"
}
sections() { grep -c '<!-- relay-run:' "$STATUS" 2>/dev/null || echo 0; }
has_run()  { grep -q "<!-- relay-run:$1 -->" "$STATUS"; }

"$HB" beat run-AAA >/dev/null 2>&1 || fail "could not create heartbeat marker for run-AAA"
"$HB" beat run-BBB >/dev/null 2>&1 || fail "could not create heartbeat marker for run-BBB"

# ── (1) Two LIVE runs publishing to the same path must BOTH survive. This is the whole item. ──
body run-AAA 1 2 0 | "$PUB" --path "$STATUS" --run run-AAA --events-path "$EVENTS" >/dev/null
body run-BBB 2 5 1 | "$PUB" --path "$STATUS" --run run-BBB --events-path "$EVENTS" >/dev/null
[[ "$(sections)" == "2" ]] || fail "(1) two live runs must yield TWO run sections, got $(sections) — the clobber is back"
has_run run-AAA || fail "(1) run-AAA's section was clobbered by run-BBB's publish"
has_run run-BBB || fail "(1) run-BBB's own section is missing"
pass "(1) two live runs publishing to one path both keep a section"

# ── (2) The aggregate is SUMMED over the sections actually present, never one run's scope. ──
grep -q '^- run sections=2$' "$STATUS" || fail "(2) aggregate must count both run sections"
grep -q '^- in-flight=3$' "$STATUS"     || fail "(2) aggregate in-flight must be 1+2=3"
grep -q '^- completed=7$' "$STATUS"     || fail "(2) aggregate completed must be 2+5=7"
grep -q '^- blocked=1$' "$STATUS"       || fail "(2) aggregate blocked must be 0+1=1"
pass "(2) aggregate sums across run sections"

# ── (2b) id:15bd — the statusline greps `^- in-flight=` etc with `head -1`, so the AGGREGATE
#        must be the first such line in the file; otherwise the bar reports whichever run
#        section happens to sit first, which is the nondeterminism this item removes. ────────
[[ "$(grep -m1 -oP '^- in-flight=\K[0-9]+' "$STATUS")" == "3" ]] \
  || fail "(2b) first ^- in-flight= line must be the aggregate (statusline reads it with head -1)"
[[ "$(grep -m1 -oP '^- completed=\K[0-9]+' "$STATUS")" == "7" ]] \
  || fail "(2b) first ^- completed= line must be the aggregate"
pass "(2b) the statusline's head -1 counters resolve to the fleet aggregate"

# ── (2c) The per-run `## Run progress` heading must be DEMOTED on merge. Before the merge it was
#        unique per file; after it appears once PER RUN, so a fleet reader doing
#        `grep -A6 '## Run progress'` silently lands in one run's block and reads that run's
#        counters as totals (reported live by the csgebra session 2026-08-18). The headings the
#        id:15bd statusline's awk fallbacks anchor on must NOT be demoted. ──────────────────────
[[ "$(grep -c '^## Run progress$' "$STATUS")" == "0" ]] \
  || fail "(2c) '## Run progress' must not survive at H2 — it collides across run sections and misreads as fleet totals"
[[ "$(grep -c '^### Run progress (this run)$' "$STATUS")" == "2" ]] \
  || fail "(2c) each run section must carry its own demoted '### Run progress (this run)' heading"
# the statusline's awk anchors must be untouched by the demotion
printf '# RELAY_STATUS — x  run: anchor-run\n\n## Run progress\n- round=1\n- in-flight=1\n- completed=0\n- blocked=0\n\n## In-flight\n- repo-x  mode=execute\n\n## Completed this run\n- repo-y  mode=review\n' \
  | "$PUB" --path "$STATUS" --run anchor-run --events-path "$EVENTS" >/dev/null
grep -q '^## In-flight$' "$STATUS"          || fail "(2c) '## In-flight' must stay at H2 — the id:15bd statusline awk fallback anchors on it"
grep -q '^## Completed this run$' "$STATUS" || fail "(2c) '## Completed this run' must stay at H2 — same reason"
pass "(2c) per-run progress heading demoted; statusline awk anchors preserved"

# ── (3) A republish replaces ONLY its own section and leaves the other run's untouched. ──
body run-AAA 9 9 9 | "$PUB" --path "$STATUS" --run run-AAA --events-path "$EVENTS" >/dev/null
[[ "$(sections)" == "2" ]] || fail "(3) republish must not drop the other run's section"
grep -q -- '- in-flight=9' < <(sed -n '/<!-- relay-run:run-AAA -->/,/<!-- \/relay-run:run-AAA -->/p' "$STATUS") \
  || fail "(3) run-AAA's own section was not refreshed"
grep -q -- '- in-flight=2' < <(sed -n '/<!-- relay-run:run-BBB -->/,/<!-- \/relay-run:run-BBB -->/p' "$STATUS") \
  || fail "(3) run-BBB's section must be carried forward VERBATIM, not re-rendered from AAA's state"
pass "(3) republish refreshes only the publishing run's section"

# ── (4) A run that is no longer alive is garbage collected on the next publish. ──
"$HB" stop run-AAA >/dev/null 2>&1 || fail "heartbeat stop run-AAA failed"
[[ -z "$("$HB" live-runs 2>/dev/null | grep -F 'run-AAA' || true)" ]] || fail "(4) precondition: run-AAA should no longer be live"
body run-BBB 2 5 1 | "$PUB" --path "$STATUS" --run run-BBB --events-path "$EVENTS" >/dev/null
has_run run-AAA && fail "(4) a dead run's section must be garbage collected"
has_run run-BBB || fail "(4) the live publishing run must survive its own GC pass"
pass "(4) a dead run's section is garbage collected"

# ── (5) FAIL-OPEN: liveness unknown ⇒ keep every section + say so. Never delete on uncertainty. ──
export HEARTBEAT_BASE="$TMP/hb-empty"; mkdir -p "$HEARTBEAT_BASE"
body run-CCC 0 0 0 | "$PUB" --path "$STATUS" --run run-CCC --events-path "$EVENTS" >/dev/null
has_run run-BBB || fail "(5) with liveness unknown, an existing section must be KEPT, not reaped"
has_run run-CCC || fail "(5) the publishing run's own section is missing"
grep -q 'liveness UNKNOWN' "$STATUS" || fail "(5) an unknown-liveness merge must SAY so in the file (id:4347, no silent fallback)"
pass "(5) unknown liveness keeps every section and surfaces the degradation"
echo "ALL PASS: RELAY_STATUS merges per-run instead of clobbering (id:0f9e)"
