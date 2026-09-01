#!/usr/bin/env bash
# Spec for id:413c — transcript-shape-preflight.sh.
#
# No `# roadmap:` header: this is a defect-prevention script with no ROADMAP item, so its
# failures ALWAYS count (same posture as test_self_transcript_wiring_ff30.sh).
#
# WHAT THIS PINS, AND WHY IT IS NOT CIRCULAR
# ------------------------------------------
# id:c219 was invisible to a green suite because the suite only ever fed the resolver the
# ONE transcript shape its author had seen. A test that feeds the preflight only the
# shapes we currently know about would repeat exactly that mistake.
#
# So the load-bearing case here is (2): a transcript nested DEEPER than the resolver's own
# `-maxdepth 4` — i.e. a shape nobody has implemented support for. The preflight must
# report it as uncovered. That is the test standing in for "the harness changed its layout
# in a way we did not anticipate", which is the whole reason this script exists.
# fails-against: rev 62b59f3436e9 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix Makefile, relay/SKILL.md, relay/scripts/self-transcript.sh (+1 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 62b59f3436e9 -- Makefile relay/SKILL.md relay/scripts/self-transcript.sh relay/scripts/transcript-shape-preflight.sh
# fails-against-assertion: expected --list-candidates to print 2 paths at rc=0;

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
PREFLIGHT="$REPO/relay/scripts/transcript-shape-preflight.sh"
RESOLVER="$REPO/relay/scripts/self-transcript.sh"

pass=0; fail=0
ok()   { echo "PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

SESSION="99999999-0000-0000-0000-000000000000"
ROOT="$TMP/projects"
SDIR="$ROOT/-home-someone-src-somerepo/$SESSION"

mk() { mkdir -p -- "$(dirname -- "$1")"; printf '%s\n' "$2" > "$1"; }

# A realistic dispatch-prompt first line: the marker is the worktree basename.
prompt_line() {
  printf '{"type":"user","content":"You are a relay executor. Your worktree /home/x/.cache/relay/worktrees/%s on branch relay/%s was already created for you. Work ONE item."}' "$1" "$1"
}

# ---------------------------------------------------------------- (1) all shapes covered
mk "$SDIR/subagents/agent-flat001.jsonl"                      "$(prompt_line relay-20260827-100000-111-execute-repo-0)"
mk "$SDIR/subagents/workflows/wf_abc123/agent-nested01.jsonl" "$(prompt_line relay-20260827-100000-111-handoff-repo-1)"

out="$("$PREFLIGHT" --session-id "$SESSION" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 0 )) && grep -q '(A) coverage OK' <<<"$out"; then
  ok "both known shapes (flat + workflow-nested) are reported covered"
else
  bad "expected rc=0 and coverage OK for known shapes; rc=$rc out=$out"
fi

# ---------------------------------------------------------------- (2) THE LOAD-BEARING CASE
# A shape deeper than the resolver's -maxdepth 4 — an unanticipated future nesting.
# The preflight MUST notice, or it is no better than the suite that missed c219.
mk "$SDIR/subagents/a/b/c/d/agent-deep01.jsonl" "$(prompt_line relay-20260827-100000-111-execute-repo-9)"

out="$("$PREFLIGHT" --session-id "$SESSION" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 3 )) && grep -q 'agent-deep01.jsonl' <<<"$out"; then
  ok "a transcript nested beyond the resolver's reach is reported UNCOVERED (rc=3, path named)"
else
  bad "expected rc=3 naming agent-deep01.jsonl; rc=$rc out=$out"
fi

if grep -q 'REMEDY' <<<"$out" && grep -q 'depth-agnostic' <<<"$out"; then
  ok "the uncovered-shape failure names a remedy and warns against another fixed glob"
else
  bad "uncovered-shape failure should carry an actionable remedy; out=$out"
fi

rm -rf -- "$SDIR/subagents/a"

# ---------------------------------------------------------------- (3) end-to-end (C)
out="$("$PREFLIGHT" --session-id "$SESSION" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 0 )) && grep -q '(C) end-to-end OK' <<<"$out"; then
  ok "(C) resolves a unique dispatch marker back to its own transcript"
else
  bad "expected (C) end-to-end OK; rc=$rc out=$out"
fi

# ---------------------------------------------------------------- (4) (C) skip is LOUD
# (C) can only run on a marker that identifies exactly ONE transcript. It scans for ANY
# such marker, so duplicating just one is not enough to force the skip — an earlier draft
# of this test did exactly that, still saw "(C) end-to-end OK", and only reading the
# OUTPUT (not the exit code) caught it. Use a session in which EVERY marker is shared.
SESSION_DUP="88888888-0000-0000-0000-000000000000"
SDIR_DUP="$ROOT/-home-someone-src-somerepo/$SESSION_DUP"
mk "$SDIR_DUP/subagents/agent-twinA.jsonl" "$(prompt_line relay-20260827-100000-111-execute-repo-0)"
mk "$SDIR_DUP/subagents/agent-twinB.jsonl" "$(prompt_line relay-20260827-100000-111-execute-repo-0)"

out="$("$PREFLIGHT" --session-id "$SESSION_DUP" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 0 )) && grep -q '(C) SKIPPED' <<<"$out" && grep -q 'NOT exercised' <<<"$out"; then
  ok "(C) announces a skip explicitly when no marker uniquely identifies a transcript"
else
  bad "a (C) skip must be stated, never silent; rc=$rc out=$out"
fi

# And the converse, so the skip above is a real negative control rather than an artifact:
# adding one uniquely-marked transcript to that same session makes (C) run.
mk "$SDIR_DUP/subagents/agent-uniq.jsonl" "$(prompt_line relay-20260827-100000-111-review-repo-7)"
out="$("$PREFLIGHT" --session-id "$SESSION_DUP" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 0 )) && grep -q '(C) end-to-end OK' <<<"$out"; then
  ok "(C) runs as soon as ANY marker is unique — the skip above was the fixture, not a dead code path"
else
  bad "expected (C) to run once a unique marker exists; rc=$rc out=$out"
fi

# ---------------------------------------------------------------- (5) INDETERMINATE ≠ OK
out="$("$PREFLIGHT" --session-id "" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 4 )) && grep -q 'INDETERMINATE' <<<"$out"; then
  ok "no session id yields INDETERMINATE (4), distinct from both OK and FAIL"
else
  bad "expected rc=4 INDETERMINATE with no session id; rc=$rc out=$out"
fi

out="$("$PREFLIGHT" --session-id "deadbeef-0000-0000-0000-000000000000" --projects-root "$ROOT" 2>&1)"; rc=$?
if (( rc == 4 )); then
  ok "an unknown session yields INDETERMINATE (4), not a false all-clear"
else
  bad "expected rc=4 for an unknown session; rc=$rc out=$out"
fi

# ---------------------------------------------------------------- (6) the seam itself
out="$("$RESOLVER" --list-candidates --session-id "$SESSION" --projects-root "$ROOT" 2>&1)"; rc=$?
n="$(grep -c . <<<"$out")"
if (( rc == 0 )) && (( n == 2 )); then
  ok "--list-candidates reports the resolver's own candidate set (2 paths), pre-marker-filter"
else
  bad "expected --list-candidates to print 2 paths at rc=0; rc=$rc n=$n out=$out"
fi

if ! grep -q 'journal' <<<"$out"; then
  mk "$SDIR/subagents/workflows/wf_abc123/journal.jsonl" '{"type":"result"}'
  out2="$("$RESOLVER" --list-candidates --session-id "$SESSION" --projects-root "$ROOT" 2>&1)"
  if ! grep -q 'journal.jsonl' <<<"$out2"; then
    ok "journal.jsonl is never a candidate (filename pattern still constrains the widened search)"
  else
    bad "journal.jsonl leaked into the candidate set: $out2"
  fi
fi

echo
echo "summary: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
