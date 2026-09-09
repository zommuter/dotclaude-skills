#!/usr/bin/env bash
# roadmap:5295 — a self-marker must match across the TILDE/ABSOLUTE spelling boundary.
#
# THE DEFECT (reproduced live 2026-09-09, session 88e0cae7-804a-48e4-9975-ef2568e05095,
# worktree relay-20260909-185356-12943-handoff-5295-0):
#
#   self-transcript.sh: marker '/home/<user>/.cache/relay/worktrees/<repo>/<run>-handoff-…'
#     matched none of the 707 transcript(s) for session 88e0cae7-… — cannot identify
#     which one is mine
#
# so `context-budget.sh --self` failed OPEN to verdict `unknown` and executor-contract
# rule 2c produced zero usable verdicts for the whole run. Four children then died
# `Prompt is too long` and parked as `relay/orphan/*`.
#
# ROOT CAUSE — two strings that both already exist, spelled differently:
#   * `worktreePathFor()` at relay/scripts/relay-loop.js:2957 builds the path as the
#     template literal `~/.cache/relay/worktrees/${repo}/${runId}-${key}`. Nothing
#     expands the tilde, so the dispatch prompt rendered at :3262 ("Your worktree ${wt}
#     on branch …") puts the TILDE form into line 1 of the child's transcript.
#   * executor-contract.md:81 asks the child for "<your worktree path>", and a child that
#     answers `$(pwd)` answers the ABSOLUTE form.
#   * self-transcript.sh filters with a literal `[[ "$head_bytes" == *"$marker"* ]]`.
# The match is therefore structurally impossible. Measured on the live transcript above:
# the tilde form sits at byte 457 (inside the 128 KiB marker scan); the absolute form
# appears only at byte 464811, written by that session's own later tool output, i.e. it
# was not in the file at all at dispatch time.
#
# WHY id:c219's FIXTURE DID NOT CATCH IT: tests/test_self_transcript_workflow_nesting_c219.sh
# writes its fake dispatch prompt as `Your worktree /home/x/.cache/relay/worktrees/<marker>`
# — an ABSOLUTE path — and passes the worktree BASENAME as the marker. Both halves diverge
# from what the dispatcher really emits, so that fixture models a shape which cannot fail
# this way. This file models the REAL shape: tilde in the prompt, absolute at the caller.
#
# NOT id:c219 (a path-glob defect: the nested shape was never enumerated) and NOT id:ff30
# (no marker at all). Here the enumeration is correct and the marker COMPARISON fails.
#
# Hermetic: fake projects tree + fake HOME in `mktemp -d`, injected
# --projects-root/--session-id. Never reads the real $HOME/.claude, never touches the
# network, never runs a real agent.

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
# A FAKE HOME, so the tilde/absolute normalization has to consult $HOME rather than
# assume /home/<something>. A resolver that hardcodes a home prefix fails case 4.
FAKE_HOME="$tmpdir/home/relayuser"
mkdir -p "$FAKE_HOME"

SESSION="5295aaaa-0000-0000-0000-000000000000"
PROJ="$tmpdir/projects"
SUBS="$PROJ/-home-relayuser-src-dotclaude-skills/$SESSION/subagents"
WFDIR="$SUBS/workflows/wf_5295c0de-abc"
mkdir -p "$SUBS" "$WFDIR"

# The two spellings of ONE worktree. This pair is the whole subject of the file.
WT_TILDE='~/.cache/relay/worktrees/dotclaude-skills/relay-20260909-185356-12943-handoff-5295-0'
WT_ABS="$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/relay-20260909-185356-12943-handoff-5295-0"

# A DIFFERENT unit in the same run — used to prove normalization did not become a fuzzy
# match. Shares a long prefix with the pair above and differs only in the trailing key.
OTHER_TILDE='~/.cache/relay/worktrees/dotclaude-skills/relay-20260909-185356-12943-execute-aa5e-0'
OTHER_ABS="$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/relay-20260909-185356-12943-execute-aa5e-0"

# Line 1 of a child transcript is its verbatim dispatch prompt — that is what carries the
# marker, and `unitPrompt()` writes the worktree into it EXACTLY as given here.
mk_child() {  # mk_child <dir> <agentid> <prompt-worktree-spelling> <padding-bytes>
  local f="$1/agent-$2.jsonl"
  printf '{"agentId":"%s","type":"user","message":{"role":"user","content":"You are a relay HANDOFF child for the repo dotclaude-skills. Your worktree %s on branch relay/x was already created for you before dispatch (id:34b7). Work EXCLUSIVELY in that worktree."}}\n' "$2" "$3" > "$f"
  if (( $4 > 0 )); then
    head -c "$4" /dev/zero | tr '\0' 'x' >> "$f"
    printf '\n' >> "$f"
  fi
  echo "$f"
}

# The unit child, workflow-nested, with the TILDE spelling the real dispatcher emits.
# 349,000 B of padding puts it over context-budget.sh's handback threshold, so a
# fail-open `unknown` here masks a HANDBACK verdict, not merely an unknown one.
F_ME="$(mk_child "$WFDIR" a7e1a9161a4073ef0 "$WT_TILDE" 349000)"
# A sibling working a DIFFERENT unit of the same run, also tilde-spelled.
F_OTHER="$(mk_child "$WFDIR" a110c471b6edaeae0 "$OTHER_TILDE" 5000)"
# An unrelated FLAT child, so the flat shape stays exercised.
F_FLAT="$(mk_child "$SUBS" aadfd7dd697e30e64 '~/.cache/relay/worktrees/somewhere-else/run-x' 2000)"
# The workflow journal — never a candidate.
printf '{"journal":true,"worktree":"%s"}\n' "$WT_TILDE" > "$WFDIR/journal.jsonl"

run_resolver() {
  HOME="$FAKE_HOME" "$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" "$@"
}

# ------------------------------------------------------------------ 1. THE DEFECT
# The exact live failure: the prompt says `~/…`, the child passes `$(pwd)`.
set +e
out="$(run_resolver --marker "$WT_ABS" 2>"$tmpdir/e1")"; rc=$?
set -e
(( rc == 0 )) || fail "an absolute-path marker did not match a tilde-spelled dispatch prompt (rc=$rc): $(cat "$tmpdir/e1")"
[[ "$out" == "$F_ME" ]] \
  || fail "absolute marker resolved to '$out', expected '$F_ME'"
pass "an absolute \$(pwd) marker matches the tilde-spelled worktree in the dispatch prompt"

# ------------------------------------------------------------------ 2. the other direction
# A dispatcher that one day writes the ABSOLUTE form must not break a child that pastes
# the tilde form out of its brief. Normalization has to be symmetric, not a one-way
# special case for today's spelling.
WFDIR2="$SUBS/workflows/wf_5295beef-def"
mkdir -p "$WFDIR2"
F_ABSPROMPT="$(mk_child "$WFDIR2" ab437c0ffee123450 "$WT_ABS" 1000)"
set +e
out="$(run_resolver --marker "$WT_TILDE" 2>"$tmpdir/e2")"; rc=$?
set -e
(( rc == 0 )) || fail "a tilde marker did not match an absolute-spelled dispatch prompt (rc=$rc): $(cat "$tmpdir/e2")"
[[ "$out" == "$F_ABSPROMPT" ]] \
  || fail "tilde marker resolved to '$out', expected '$F_ABSPROMPT'"
pass "a tilde marker matches an absolute-spelled dispatch prompt (normalization is symmetric)"
rm -rf "$WFDIR2"

# ------------------------------------------------------------------ 3. exact match unchanged
# The pre-existing behaviour — marker spelled the same way as the prompt — must survive.
got="$(run_resolver --marker "$WT_TILDE")"
[[ "$got" == "$F_ME" ]] \
  || fail "an EXACTLY-matching tilde marker regressed: resolved '$got', expected '$F_ME'"
got="$(run_resolver --marker "relay-20260909-185356-12943-handoff-5295-0")"
[[ "$got" == "$F_ME" ]] \
  || fail "a BASENAME marker regressed: resolved '$got', expected '$F_ME' (id:c219's fixture passes this shape)"
pass "exact-spelling and basename markers still resolve (additive fix, no regression)"

# ------------------------------------------------------------------ 4. $HOME, not a guess
# Normalization must expand `~` using the CALLER'S $HOME. Point HOME somewhere else and
# the absolute marker built from the OLD home must stop matching — a resolver that
# hardcodes a `/home/*` prefix, or that strips any leading directory, passes case 1 and
# fails here.
set +e
out="$(HOME="$tmpdir/home/someone-else" "$RESOLVER" --session-id "$SESSION" \
        --projects-root "$PROJ" --marker "$WT_ABS" 2>/dev/null)"; rc=$?
set -e
(( rc != 0 )) \
  || fail "an absolute marker under a DIFFERENT \$HOME still matched ('$out') — the tilde expansion is not anchored to \$HOME"
pass "tilde expansion is anchored to \$HOME, not to a hardcoded home prefix"

# ------------------------------------------------------------------ 5. not a fuzzy match
# Normalizing the spelling must not degrade the comparison into a prefix/suffix match.
# These two paths differ only in their trailing unit key.
got="$(run_resolver --marker "$OTHER_ABS")"
[[ "$got" == "$F_OTHER" ]] \
  || fail "a sibling unit's absolute marker resolved to '$got', expected '$F_OTHER' — normalization must still discriminate the trailing unit key"
pass "sibling units with a shared prefix are still discriminated, not conflated"

# ------------------------------------------------------------------ 6. genuine miss still fails
# A marker that names nothing must still exit 4 loudly. A normalization that matches
# everything would satisfy cases 1-3 and destroy the guard.
set +e
out="$(run_resolver --marker "$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/run-that-never-existed-0" 2>"$tmpdir/e6")"; rc=$?
set -e
(( rc == 4 )) || fail "a marker matching nothing exited $rc (expected 4) and printed '$out' — the resolver must still fail LOUDLY"
[[ -s "$tmpdir/e6" ]] || fail "an unresolvable marker said nothing on stderr (id:4347 no-silent-swallow)"
pass "a marker that genuinely matches nothing still exits 4 with a reason on stderr"

# ------------------------------------------------------------------ 7. journal still excluded
set +e
out="$(run_resolver --marker '"journal":true' 2>/dev/null)"; rc=$?
set -e
(( rc != 0 )) || fail "journal.jsonl was accepted as an agent transcript ('$out')"
pass "workflows/wf_*/journal.jsonl is never a candidate"

# ------------------------------------------------------------------ 8. MULTI-SIBLING: LOUD
# The second, latent defect. A worktree path is NOT unique per child: the id:34b7
# `provision-worktree.sh` mechanical child's own dispatch prompt names the SAME worktree
# as a command argument. Measured live 2026-09-09: the tilde-form probe matched TWO
# transcripts (agent-aa1b3d25b1ab57ce3, the provisioner, and agent-a7e1a9161a4073efc,
# the unit child). The documented AMBIGUITY POLICY then picks the newest mtime.
#
# This case pins the LOUDNESS only — every candidate named on stderr, never a silent
# pick. Whether a multi-match should instead be a hard refusal is an OWNER call, filed
# in REVIEW_ME.md against id:5295. Do not change the tie-break to make this pass.
F_PROVISIONER="$(mk_child "$WFDIR" aa1b3d25b1ab57ce3 "$WT_TILDE" 500)"
# Make the provisioner's prompt the real shape: a bare command argument, no prose.
printf '{"agentId":"aa1b3d25b1ab57ce3","type":"user","message":{"role":"user","content":"Run exactly this one command and report its stdout VERBATIM (id:34b7 pre-dispatch worktree creation):\\n```relay-mech\\n~/.claude/skills/relay/scripts/provision-worktree.sh /src/dotclaude-skills %s relay/x\\n```"}}\n' "$WT_TILDE" > "$F_PROVISIONER"
touch -d '2020-01-01 00:00:00' "$F_PROVISIONER"
touch -d '2030-01-01 00:00:00' "$F_ME"

set +e
got="$(run_resolver --marker "$WT_ABS" 2>"$tmpdir/e8")"; rc=$?
set -e
err8="$(cat "$tmpdir/e8")"
[[ -s "$tmpdir/e8" ]] \
  || fail "a marker matching TWO transcripts resolved SILENTLY (id:4347 no-silent-swallow)"
[[ "$err8" == *"$F_PROVISIONER"* ]] \
  || fail "the multi-match report did not name the provisioner candidate $F_PROVISIONER"
[[ "$err8" == *"$F_ME"* ]] \
  || fail "the multi-match report did not name the unit-child candidate $F_ME"
if (( rc == 0 )); then
  [[ "$got" == "$F_ME" ]] \
    || fail "the multi-match tie-break chose '$got'; the most-recently-modified '$F_ME' should win under the documented policy"
fi
pass "a marker matching two transcripts is LOUD: every candidate named on stderr (rc=$rc)"
rm -- "$F_PROVISIONER"
touch "$F_ME"

# ------------------------------------------------------------------ 9. rule 2c end to end
# The point of the whole item: the live run should have produced a HANDBACK, not `unknown`.
real="$(wc -c < "$F_ME" | tr -d '[:space:]')"
set +e
out="$(HOME="$FAKE_HOME" "$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" \
        --marker "$WT_ABS" 2>"$tmpdir/e9")"; rc=$?
set -e
[[ "$out" != *"unknown"* ]] \
  || fail "rule 2c still fails open on the real dispatch spelling: '$out' (stderr: $(cat "$tmpdir/e9"))"
[[ "$out" == "context-budget: handback bytes=$real "* ]] \
  || fail "--self printed '$out', expected a handback verdict at bytes=$real"
(( rc == 3 )) || fail "--self handback exited $rc, expected 3 (host-gate.sh convention)"
pass "context-budget.sh --self --marker \"\$(pwd)\" now yields: $out"

# ------------------------------------------------------------------ 10. read-only
before="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
run_resolver --marker "$WT_ABS" >/dev/null 2>&1 || true
HOME="$FAKE_HOME" "$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" \
  --marker "$WT_ABS" >/dev/null 2>&1 || true
after="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
[[ "$before" == "$after" ]] \
  || fail "the resolver / --self created, removed or grew a file — both must be pure read-only checks"
pass "resolver and --self remain read-only"

echo "ALL PASS: id:5295 — the self-marker matches across the tilde/absolute spelling boundary"
