#!/usr/bin/env bash
# No `# roadmap:XXXX` header: id:54fc has a TODO.md entry (design-record
# docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md, meeting Item 3
# forward-flag) but no matching ROADMAP.md item, so the expected-red/EXPECTED-RED gate
# doesn't apply here — this test's failures always count, per the testing convention
# in CLAUDE.md.
#
# Spec for the SECOND liveness domain (id:54fc): the mechanical discovery producer
# (relay/scripts/discover-repos-mechanical.sh, id:9d97, driven by a `--user` .timer) is a
# process separate from the dispatch loop that id:e149/id:98f0 already cover. A dead/stale
# producer must read as "discovery DOWN", distinctly from "dispatch pool idle / no work" —
# NOT be silently absorbed into the existing dispatch-loop dead-run check.
#
# Contract under test:
#   (a) after discover-repos-mechanical.sh runs successfully, its OWN heartbeat marker
#       (runId = DISCOVERY_PRODUCER_RUN_ID, default "discovery-producer") exists and is fresh.
#   (b) a STALE producer marker makes relay-watchdog.sh report the producer-down condition
#       DISTINCTLY (its own notify title/body, separate from the dispatch-loop message; the
#       dispatch-loop domain must remain silent when it has no dead runs of its own).
#   (c) a FRESH producer marker → relay-watchdog.sh does NOT report producer-down.
#
# Hermetic: HEARTBEAT_BASE/RELAY_TOML/RELAY_DISCOVERY_QUEUE_DIR/watchdog state+evidence all
# under mktemp -d; no real ~/.claude, ~/.config, or network touched.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD="$ROOT/relay/scripts/discover-repos-mechanical.sh"
HB="$ROOT/relay/scripts/heartbeat.sh"
WD="$ROOT/tools/relay-watchdog.sh"

[[ -x "$PROD" ]] || { echo "discover-repos-mechanical.sh not found (RED): $PROD"; exit 1; }
[[ -x "$HB" ]]   || { echo "heartbeat.sh not found: $HB"; exit 1; }
[[ -x "$WD" ]]   || { echo "relay-watchdog.sh not found: $WD"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

export SRC_DIR="$tmp/src"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_DISCOVERY_QUEUE_DIR="$tmp/queue"
export RELAY_WORKTREE_BASE="$tmp/wt"
export HEARTBEAT_BASE="$tmp/heartbeats"
export HEARTBEAT_LOG=/dev/null
export DISCOVERY_PRODUCER_RUN_ID="discovery-producer-test"
mkdir -p "$SRC_DIR"

# minimal fixture repo so own_repos() has something to enumerate (content doesn't matter here)
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  printf '# Roadmap\n## Items\n' > "$d/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$d/TODO.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}
mkrepo "$SRC_DIR/r1"
cat > "$RELAY_TOML" <<EOF
[repos.r1]
classification = "own"
EOF

marker_file() {
  local safe; safe="$(printf '%s' "$DISCOVERY_PRODUCER_RUN_ID" | tr '/:' '__')"
  printf '%s/%s.json' "$HEARTBEAT_BASE" "$safe"
}

# ── (a) a successful producer run beats its own heartbeat marker ─────────────
"$PROD" --runid t1 --live-claims "" --main-branch main >/dev/null
mf="$(marker_file)"
[[ -f "$mf" ]] || fail "producer run did not create its heartbeat marker at $mf"
jq -e --arg id "$DISCOVERY_PRODUCER_RUN_ID" '.runId==$id and (.heartbeat_ts|type=="number")' "$mf" >/dev/null \
  || fail "producer heartbeat marker missing runId/heartbeat_ts"
[[ "$(HEARTBEAT_TTL=3600 "$HB" status "$DISCOVERY_PRODUCER_RUN_ID")" == alive ]] \
  || fail "a fresh producer heartbeat should read alive"
pass "a successful producer run beats its own heartbeat marker (id:54fc)"

# ── watchdog plumbing (shared across b/c) ─────────────────────────────────────
export RELAY_HEARTBEAT_SH="$HB"
export RELAY_WATCHDOG_STATE="$tmp/notified"
export RELAY_WATCHDOG_EVIDENCE="$tmp/outage.jsonl"
export RELAY_WATCHDOG_LOG=/dev/null
export RELAY_WATCHDOG_PRODUCER_TTL=5
NOTIFS="$tmp/notifs"
STUB="$tmp/notify-stub.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "%s"\n' "$NOTIFS" > "$STUB"
chmod +x "$STUB"
export RELAY_WATCHDOG_NOTIFY_CMD="$STUB"

# ── (c) a fresh producer marker → no producer-down report ────────────────────
: > "$NOTIFS"
bash "$WD" >/dev/null 2>&1
if grep -qi "discovery producer" "$NOTIFS" 2>/dev/null; then
  fail "watchdog reported producer-down for a FRESH marker"
fi
pass "a fresh producer marker produces no producer-down report (id:54fc)"

# ── (b) a STALE producer marker makes the watchdog report it DISTINCTLY ──────
sleep 6  # exceed RELAY_WATCHDOG_PRODUCER_TTL=5s
: > "$NOTIFS"
rm -f "$RELAY_WATCHDOG_EVIDENCE"
bash "$WD" >/dev/null 2>&1
grep -qi "discovery producer" "$NOTIFS" || fail "watchdog did not report the stale producer marker distinctly"
if grep -qi "relay loop died" "$NOTIFS"; then
  fail "producer-down report bled into the generic dispatch-loop 'Relay loop died' message"
fi
grep -q "discovery-producer" "$RELAY_WATCHDOG_EVIDENCE" || fail "producer staleness not recorded in the evidence log"
jq -e '.domain=="discovery-producer"' "$RELAY_WATCHDOG_EVIDENCE" >/dev/null \
  || fail "evidence entry missing domain=discovery-producer tag"
pass "a stale producer marker is reported DISTINCTLY from the dispatch-loop domain (id:54fc)"

# de-dup: a second tick on the same stale marker should not re-notify
: > "$NOTIFS"
bash "$WD" >/dev/null 2>&1
[[ -s "$NOTIFS" ]] && fail "watchdog re-notified an already-known stale producer marker (spam)"
pass "a known stale producer marker is not re-notified on later ticks (id:54fc)"

# ── (d) cross-domain alarm suppression: a scoped dispatch-loop reap must NOT
# archive the (still-stale) producer marker (strong-model audit run 70 finding 2).
# reap uses heartbeat.sh's DEFAULT HEARTBEAT_TTL (3600s), not the watchdog's
# separate RELAY_WATCHDOG_PRODUCER_TTL — so both markers must be backdated well
# past 3600s to be "present-but-stale" from reap's point of view (matching the
# real scenario: a restart happening well after an outage). Simulate a
# dispatch-loop restart's auto-reconcile-on-restart reap, which relay-loop.js
# now scopes with --prefix 'relay-*' (its own runId namespace) — the producer
# marker's runId ("discovery-producer-test") must NOT match that glob, so it
# must survive the reap untouched, while a genuine relay-* dispatch marker in
# the same heartbeat dir DOES get archived.
backdate() {
  python3 - "$1" <<'PY'
import json, sys, time
p = sys.argv[1]
d = json.load(open(p))
d["heartbeat_ts"] = int(time.time()) - 999999
json.dump(d, open(p, "w"))
PY
}
pmf="$(marker_file)"
[[ -f "$pmf" ]] || fail "setup: producer marker missing before scoped-reap check"
backdate "$pmf"  # producer marker from parts (a)-(c) above, now backdated stale too
"$HB" beat "relay-20260101-000000-1" >/dev/null
backdate "$HEARTBEAT_BASE/relay-20260101-000000-1.json"
reap_out="$("$HB" reap --prefix 'relay-*' 2>&1 >/dev/null)"
[[ -f "$pmf" ]] || fail "scoped reap (--prefix 'relay-*') archived the discovery-producer marker — cross-domain alarm suppression regression"
[[ -f "$HEARTBEAT_BASE/relay-20260101-000000-1.json" ]] && fail "scoped reap left a matching relay-* marker un-reaped"
[[ -f "$tmp/heartbeats.done/relay-20260101-000000-1.json" ]] || fail "scoped reap did not archive the matching relay-* marker into heartbeats.done"
echo "$reap_out" | grep -q "reaped 1" || fail "scoped reap should report exactly 1 reaped marker, got: $reap_out"
pass "a --prefix 'relay-*' reap archives the dispatch-loop marker but leaves the discovery-producer marker intact (id:54fc / cross-domain suppression fix)"

# ── (e) cross-domain alarm suppression on the DETECTION side: an aged
# discovery-producer marker must NOT appear in `dead-runs --prefix 'relay-*'`, so the
# dispatch-loop consumers (relay-watchdog.sh domain 1, relay-loop.js auto-reconcile-on-restart)
# stay quiet for it — while an unscoped `dead-runs` and the domain-2 `dead-runs --prefix
# 'discovery-*'` still see it (2026-07-07 Fable second-opinion finding 2: reap gained --prefix
# but dead-runs did not, so the producer marker still tripped domain-1 detection).
# Rebuild a fresh, backdated-stale producer marker + a stale relay-* dispatch marker in a
# clean heartbeat dir (parts (a)-(d) archived theirs into heartbeats.done).
export HEARTBEAT_BASE2="$tmp/heartbeats2"
mkdir -p "$HEARTBEAT_BASE2"
HB_D() { HEARTBEAT_BASE="$HEARTBEAT_BASE2" "$HB" "$@"; }
HB_D beat "$DISCOVERY_PRODUCER_RUN_ID" >/dev/null
HB_D beat "relay-20260202-000000-9" >/dev/null
backdate "$HEARTBEAT_BASE2/$(printf '%s' "$DISCOVERY_PRODUCER_RUN_ID" | tr '/:' '__').json"
backdate "$HEARTBEAT_BASE2/relay-20260202-000000-9.json"

scoped_dead="$(HEARTBEAT_BASE="$HEARTBEAT_BASE2" HEARTBEAT_TTL=3600 "$HB" dead-runs --prefix 'relay-*')"
echo "$scoped_dead" | jq -e 'select(.runId=="'"$DISCOVERY_PRODUCER_RUN_ID"'")' >/dev/null 2>&1 \
  && fail "dead-runs --prefix 'relay-*' leaked the discovery-producer marker into the dispatch domain"
echo "$scoped_dead" | jq -e 'select(.runId=="relay-20260202-000000-9")' >/dev/null 2>&1 \
  || fail "dead-runs --prefix 'relay-*' dropped the matching stale relay-* dispatch marker"
pass "dead-runs --prefix 'relay-*' excludes the discovery-producer marker but keeps stale relay-* markers (id:54fc detection-side scoping)"

# domain-2 still SEES the producer via its own prefix (and the unscoped default too).
prod_dead="$(HEARTBEAT_BASE="$HEARTBEAT_BASE2" HEARTBEAT_TTL=3600 "$HB" dead-runs --prefix 'discovery-*')"
echo "$prod_dead" | jq -e 'select(.runId=="'"$DISCOVERY_PRODUCER_RUN_ID"'")' >/dev/null 2>&1 \
  || fail "dead-runs --prefix 'discovery-*' should still surface the stale producer marker (domain-2 must keep alarming)"
unscoped_dead="$(HEARTBEAT_BASE="$HEARTBEAT_BASE2" HEARTBEAT_TTL=3600 "$HB" dead-runs)"
echo "$unscoped_dead" | jq -e 'select(.runId=="'"$DISCOVERY_PRODUCER_RUN_ID"'")' >/dev/null 2>&1 \
  || fail "unscoped dead-runs (legacy default) should still emit every stale marker incl. the producer"
pass "domain-2 (--prefix 'discovery-*') and the legacy unscoped default still see the producer marker (id:54fc)"

echo "ALL PASS: discovery-producer heartbeat + distinct watchdog domain (id:54fc)"
