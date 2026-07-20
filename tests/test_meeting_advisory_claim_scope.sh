#!/usr/bin/env bash
# roadmap:0ee1
# RED spec (authored by /relay handoff 2026-07-20, apex) for the meeting↔executor
# lease scope fix, branch b (owner-ratified D1, meeting
# docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md,
# routed:4361).
#
# The bug: claim.sh acquire is mode-blind — /meeting's setup claim sits on the SAME
# key the hard code lease uses (`acquire <repo> --mode meeting`, meeting/SKILL.md
# step 2-setup-claim), so a parallel executor's `acquire <repo> --mode execute` is
# hard-REFUSED, violating claim.sh's own SCOPE INVARIANT (the hard lease guards
# code/worktree integration ONLY; a meeting is ledger-only/advisory).
#
# The fix (branch b): the meeting advisory claim moves to a DISTINCT key
# (`meeting:<repo>`) and MUST pass `--repo <root-basename>` (else it is invisible
# to every repo-field matcher, e.g. relay-loop.js:909's live-repo set). The
# hard-lease key `<repo>` is never touched by a meeting; an executor acquire
# WARNs-and-proceeds past a live meeting advisory claim, never refused. The
# two-real-executors-refuse-each-other invariant is UNCHANGED. The pool→meeting
# dispatch-time skip is ASPIRATIONAL (gated id:9000 / possibly dissolved id:5a39)
# and is NOT built here — only recorded in the SCOPE INVARIANT block.
#
# EXPECTED-RED while roadmap:0ee1 is unticked (does not fail the suite).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIM="$ROOT/relay/scripts/claim.sh"
SKILL="$ROOT/meeting/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CLAIM" ]] || fail "claim.sh not found/executable at $CLAIM"
[[ -f "$SKILL" ]] || fail "meeting/SKILL.md not found at $SKILL"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAIM_BASE="$TMP/claimbase"
export CLAIM_LOG="$TMP/claim.log"

# ── (A) Doc surface: meeting/SKILL.md step 2-setup-claim uses the DISTINCT key ──
# Extract the 2-setup-claim block (up to the next step heading, 2b).
section="$(sed -n '/^2-setup-claim\./,/^2b\./p' "$SKILL")"
[[ -n "$section" ]] || fail "(A) could not extract the 2-setup-claim section from meeting/SKILL.md"

grep -qE 'claim\.sh acquire ["'"'"']?meeting:' <<<"$section" \
  || fail "(A) 2-setup-claim acquire does not use the distinct advisory key form 'meeting:<root-basename>' (still the hard-lease repo key?)"
grep -q -- '--repo' <<<"$section" \
  || fail "(A) 2-setup-claim acquire does not pass --repo <root-basename> — the advisory claim would be invisible to relay-loop.js:909's repo-set matcher"
grep -qE 'claim\.sh release ["'"'"']?meeting:' <<<"$section" \
  || fail "(A) 2-setup-claim release does not release the distinct 'meeting:<root-basename>' key"
pass "(A) SKILL.md 2-setup-claim acquires+releases on the distinct meeting:<repo> key with --repo"

# ── (B) Behavior: advisory claim on the distinct key is visible in peek's repo-set ──
"$CLAIM" acquire "meeting:fixrepo" --repo fixrepo --mode meeting --run mtgA >/dev/null 2>&1 \
  || fail "(B) advisory acquire on distinct key meeting:fixrepo failed"
peek_repos="$("$CLAIM" peek | python3 -c 'import sys,json
for l in sys.stdin:
    l=l.strip()
    if l: print(json.loads(l).get("repo",""))')"
grep -qx 'fixrepo' <<<"$peek_repos" \
  || fail "(B) fixrepo does not appear in claim.sh peek's repo-set after the meeting advisory acquire (peek repos: $peek_repos)"
pass "(B) meeting advisory claim (distinct key + --repo) appears in peek's repo-set"

# ── (C) Behavior: a concurrent EXECUTE acquire on the repo key SUCCEEDS while the
#        meeting advisory claim is live (today: wrongly REFUSED under the same-key
#        recipe; with the distinct key it must succeed) ──
exec_err="$TMP/exec.err"
if ! "$CLAIM" acquire fixrepo --mode execute --run execB >/dev/null 2>"$exec_err"; then
  fail "(C) 'acquire fixrepo --mode execute' was REFUSED while a meeting advisory claim is live — the executor-unblock (branch b) is the point of id:0ee1"
fi
pass "(C) concurrent execute acquire succeeds while the meeting advisory claim is live"

# ── (D) WARN-and-proceed: the successful execute acquire names the live meeting
#        advisory claim on stderr (a manual drain proceeds WITH awareness) ──
grep -qi 'WARN' "$exec_err" || fail "(D) execute acquire past a live meeting advisory claim printed no WARN on stderr"
grep -qi 'meeting' "$exec_err" || fail "(D) the WARN does not name the meeting advisory claim"
pass "(D) execute acquire WARNs-and-proceeds, naming the live meeting advisory claim"

# ── (E) Regression control: two REAL executors still refuse each other ──
if "$CLAIM" acquire fixrepo --mode execute --run execC >/dev/null 2>&1; then
  fail "(E) a SECOND execute acquire on the held repo key was accepted — the two-real-executors invariant must be unchanged"
fi
pass "(E) two-real-executors-refuse-each-other invariant unchanged"

# ── (F) SCOPE INVARIANT block records the pool→meeting dispatch-time skip as
#        aspirational, gated on id:9000 / possibly dissolved by id:5a39 ──
grep -q '9000' "$CLAIM" || fail "(F) claim.sh SCOPE INVARIANT does not reference id:9000 (bilateral advisory honor gate)"
grep -q '5a39' "$CLAIM" || fail "(F) claim.sh SCOPE INVARIANT does not reference id:5a39 (meeting-as-relay-producer dissolution) — the aspirational dispatch-time skip must be recorded, not built"
pass "(F) SCOPE INVARIANT records the aspirational pool→meeting skip (id:9000/id:5a39)"

echo "OK: all meeting-advisory-claim-scope assertions passed"
