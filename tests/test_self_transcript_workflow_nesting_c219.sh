#!/usr/bin/env bash
# id:c219 — self-transcript.sh must find WORKFLOW-NESTED child transcripts.
#
# NO `# roadmap:XXXX` header ON PURPOSE: this is a defect-fix test with no ROADMAP unit
# of its own (same posture as its sibling test_self_transcript_wiring_ff30.sh), so there
# is no checkbox for the EXPECTED-RED machinery to consult. Failures here always count.
#
# THE DEFECT (observed live, run relay-20260827-084504-10452, repo inflownistration):
#
#   self-transcript.sh --marker '<worktree basename>' matched none of the 1 transcript(s)
#   for the session
#
# so rule 2c's mandatory pre-first-edit budget check returned `verdict unknown`
# (fail-open) on the very dispatch shape it was written for — i.e. it is silently a
# no-op on every pool run.
#
# ROOT CAUSE: the resolver collects candidates from exactly ONE glob,
# `<projects>/*/<session>/subagents/agent-*.jsonl`. A Workflow-dispatched child (which
# is what the relay pool actually produces for handoff/execute units) writes to
# `<projects>/*/<session>/subagents/workflows/wf_<id>/agent-<agentid>.jsonl` — one
# directory level deeper. The resolver therefore scanned a REAL directory and found the
# one non-workflow sibling, which legitimately did not carry the marker. Census of the
# live tree on 2026-08-27: 25,620 transcripts in the workflow shape vs 2,476 in the flat
# shape — the shape the resolver misses is the DOMINANT one.
#
# Hermetic: fake projects tree in `mktemp -d`, injected --projects-root/--session-id.
# Never reads $HOME/.claude, never touches the network, never runs a real agent.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT/relay/scripts/self-transcript.sh"
BUDGET="$ROOT/relay/scripts/context-budget.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$RESOLVER" ]] || fail "$RESOLVER missing or not executable"
[[ -x "$BUDGET" ]]   || fail "$BUDGET missing or not executable"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ------------------------------------------------------------------ fake harness tree
# Mirrors the layout verified on claude-code 2.1.247 for a Workflow-dispatched pool:
#   <projects>/<cwd-slug>/<SESSION>/subagents/agent-<id>.jsonl              (flat sibling)
#   <projects>/<cwd-slug>/<SESSION>/subagents/workflows/wf_<id>/agent-<id>.jsonl
#   <projects>/<cwd-slug>/<SESSION>/subagents/workflows/wf_<id>/journal.jsonl
SESSION="717457a5-0000-0000-0000-000000000000"
PROJ="$tmpdir/projects"
SUBS="$PROJ/-home-someone-src-somerepo/$SESSION/subagents"
WFDIR="$SUBS/workflows/wf_341bb111-37d"
mkdir -p "$SUBS" "$WFDIR"

# Line 1 of a child transcript is its verbatim dispatch prompt — that is what carries
# the marker.
mk_child() {  # mk_child <dir> <agentid> <marker> <padding-bytes>
  local f="$1/agent-$2.jsonl"
  printf '{"agentId":"%s","type":"user","message":{"role":"user","content":"You are a relay HANDOFF child. Your worktree /home/x/.cache/relay/worktrees/%s on branch relay/x was already created for you."}}\n' "$2" "$3" > "$f"
  if (( $4 > 0 )); then
    head -c "$4" /dev/zero | tr '\0' 'x' >> "$f"
    printf '\n' >> "$f"
  fi
  echo "$f"
}

# The marker a relay child actually passes: its worktree BASENAME.
MARK_ME="relay-20260827-084504-10452-handoff-repo-0"
MARK_OTHER="relay-20260827-084504-10452-handoff-repo-1"

# The ONE flat sibling that existed live — an unrelated child, no marker match. This is
# the "1 transcript(s)" the live error message counted.
F_FLAT="$(mk_child "$SUBS" aadfd7dd697e30e64 "some-other-unrelated-thing" 2000)"

# The real handoff child, workflow-nested, 349,393 B live — over the 300,000 B handback
# threshold, so the fail-open masked a HANDBACK verdict, not merely an unknown one.
F_ME="$(mk_child "$WFDIR" a94dfa8ae227cb9d2 "$MARK_ME" 349000)"
# A workflow sibling working a different repo unit.
F_SIB="$(mk_child "$WFDIR" abe9e2cb573fa8a0a "$MARK_OTHER" 5000)"
# The workflow journal — NOT an agent transcript; must never be a candidate.
printf '{"journal":true,"marker":"%s"}\n' "$MARK_ME" > "$WFDIR/journal.jsonl"

run_resolver() { "$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" "$@"; }

# ------------------------------------------------------------------ 1. THE DEFECT
set +e
out="$(run_resolver --marker "$MARK_ME" 2>"$tmpdir/e1")"; rc=$?
set -e
(( rc == 0 )) || fail "a workflow-nested child could not resolve its own transcript (rc=$rc): $(cat "$tmpdir/e1")"
[[ "$out" == "$F_ME" ]] \
  || fail "workflow-nested marker '$MARK_ME' resolved to '$out', expected '$F_ME'"
pass "a Workflow-dispatched child resolves its own subagents/workflows/wf_*/agent-*.jsonl"

# ------------------------------------------------------------------ 2. sibling isolation
got="$(run_resolver --marker "$MARK_OTHER")"
[[ "$got" == "$F_SIB" ]] \
  || fail "sibling marker '$MARK_OTHER' resolved to '$got', expected '$F_SIB'"
pass "workflow siblings are disambiguated by marker, not guessed"

# ------------------------------------------------------------------ 3. journal is not a transcript
set +e
out="$(run_resolver --marker '"journal":true' 2>/dev/null)"; rc=$?
set -e
(( rc != 0 )) || fail "journal.jsonl was accepted as an agent transcript ('$out') — only agent-*.jsonl may be a candidate"
pass "workflows/wf_*/journal.jsonl is never a candidate"

# ------------------------------------------------------------------ 4. flat shape still works
# id:ff30's shape resolved correctly before this fix (verified live 2026-08-26,
# bytes=170510 verdict=ok). This must be an ADDITIVE fix, never a replacement.
got="$(run_resolver --marker "some-other-unrelated-thing")"
[[ "$got" == "$F_FLAT" ]] \
  || fail "the FLAT subagents/agent-*.jsonl shape regressed: resolved '$got', expected '$F_FLAT'"
pass "the pre-existing flat shape still resolves (no regression)"

# ------------------------------------------------------------------ 5. --bytes
b="$(run_resolver --marker "$MARK_ME" --bytes)"
real="$(wc -c < "$F_ME" | tr -d '[:space:]')"
[[ "$b" == "$real" ]] || fail "--bytes reported '$b', file is '$real' bytes"
pass "--bytes measures the workflow-nested transcript ($real B)"

# ------------------------------------------------------------------ 6. rule 2c end to end
# The whole point: the live run should have produced a HANDBACK, not `unknown`.
set +e
out="$("$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" --marker "$MARK_ME" 2>"$tmpdir/e6")"; rc=$?
set -e
[[ "$out" != *"unknown"* ]] \
  || fail "rule 2c still fails open on the real dispatch shape: '$out' (stderr: $(cat "$tmpdir/e6"))"
[[ "$out" == "context-budget: handback bytes=$real "* ]] \
  || fail "--self on the 349 KB workflow-nested transcript printed '$out', expected a handback verdict at bytes=$real"
(( rc == 3 )) || fail "--self handback exited $rc, expected 3 (host-gate.sh convention)"
pass "context-budget.sh --self --marker <worktree-basename> now yields: $out"

# ------------------------------------------------------------------ 7. ambiguity stays LOUD
# Same marker in a flat child AND a workflow child (a resumed unit). Existing policy:
# newest mtime wins and EVERY candidate is named on stderr — never a silent guess.
F_DUP="$(mk_child "$SUBS" adddd4444dddd4444 "$MARK_ME" 500)"
touch -d '2020-01-01 00:00:00' "$F_ME"
touch -d '2030-01-01 00:00:00' "$F_DUP"
got="$(run_resolver --marker "$MARK_ME" 2>"$tmpdir/e7")"
[[ "$got" == "$F_DUP" ]] \
  || fail "ambiguous marker across shapes chose '$got'; the most-recently-modified '$F_DUP' should win"
[[ -s "$tmpdir/e7" ]] || fail "an ambiguous marker resolved SILENTLY (id:4347 no-silent-swallow)"
err7="$(cat "$tmpdir/e7")"
[[ "$err7" == *"$F_ME"* ]] || fail "the ambiguity warning did not name the losing candidate $F_ME"
pass "ambiguity across flat+workflow shapes → newest wins, all candidates named on stderr"
rm -- "$F_DUP"
touch "$F_ME"

# ------------------------------------------------------------------ 8. session scoping
# A workflow-nested transcript under a DIFFERENT session must never be reachable.
OTHER="$PROJ/-home-someone-src-otherrepo/99999999-0000-0000-0000-000000000000/subagents/workflows/wf_deadbeef-000"
mkdir -p "$OTHER"
mk_child "$OTHER" adecoy0000000000 "$MARK_ME" 100 >/dev/null
got="$(run_resolver --marker "$MARK_ME")"
[[ "$got" == "$F_ME" ]] \
  || fail "resolver reached ANOTHER session's workflow transcript ('$got') — session scoping is broken"
pass "another session's workflow transcripts are never candidates"

# ------------------------------------------------------------------ 9. read-only
before="$(find "$PROJ" -type f | sort)"
run_resolver --marker "$MARK_ME" >/dev/null 2>&1 || true
"$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" --marker "$MARK_ME" >/dev/null 2>&1 || true
after="$(find "$PROJ" -type f | sort)"
[[ "$before" == "$after" ]] \
  || fail "the resolver / --self created or removed files — both must be pure read-only checks"
pass "resolver and --self remain read-only on the nested shape"

echo "ALL PASS: id:c219 — rule 2c's budget check runs on the Workflow dispatch shape"
