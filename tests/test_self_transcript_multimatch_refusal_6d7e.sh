#!/usr/bin/env bash
# roadmap:6d7e — a marker matching MORE THAN ONE transcript is an UNRESOLVED IDENTITY,
# not a tie to be broken. It must exit non-zero and name every candidate.
#
# THE DEFECT (relay/scripts/self-transcript.sh:239, unchanged by id:5295's fix):
#
#   echo "self-transcript.sh: ${#candidates[@]} transcripts matched — choosing the most
#     recently modified ($winner). Candidates: ${candidates[*]}" >&2
#
# A warning on stderr, a path on stdout, exit 0. The zero-match branch twenty lines up
# (:219) exits 4 for the same underlying failure — "I cannot tell which transcript is
# mine" — and THAT ASYMMETRY IS THE BUG. `context-budget.sh --self` fails OPEN on a
# non-zero resolver (verdict `unknown`), so the zero-match case degrades honestly while
# the multi-match case returns a confident `ok`/`handback` computed from POSSIBLY ANOTHER
# CHILD'S byte count. Executor-contract rule 2c then acts on it.
#
# WHY THIS IS NOT THEORETICAL: a relay worktree path is not unique to one child. The
# id:34b7 `provision-worktree.sh` mechanical child's own dispatch prompt names the SAME
# worktree as a command argument, so EVERY pooled unit has at least two transcripts
# carrying its marker. Measured live 2026-09-09 in session `88e0cae7`: the tilde-spelled
# probe matched 2 of 707. id:5295 turned "matches 0" into "matches 2" — it made the guard
# reachable and, in the same stroke, made it capable of being confidently wrong.
#
# OWNER RULING (2026-09-09, user-injected): the open REVIEW_ME box against id:5295 offered
# (a) keep the mtime tie-break or (b) refuse. He ruled (b), reason stated: a wrong byte
# count is worse than `unknown` because it looks authoritative. The most-recent behaviour
# survives only behind an explicit opt-in, `--allow-ambiguous`.
#
# TRIANGULATION (id:108e): the cases below pin BOTH directions, so neither "always fail"
# nor "special-case N==2" passes — a 3-way match, a single-match control, a zero-match
# control, and the opt-in path are all asserted.
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

FAKE_HOME="$tmpdir/home/relayuser"
mkdir -p "$FAKE_HOME"

SESSION="6d7ebbbb-0000-0000-0000-000000000000"
PROJ="$tmpdir/projects"
SUBS="$PROJ/-home-relayuser-src-dotclaude-skills/$SESSION/subagents"
WFDIR="$SUBS/workflows/wf_6d7ec0de-abc"
mkdir -p "$SUBS" "$WFDIR"

# The real dispatch shape: `worktreePathFor()` emits a LITERAL TILDE, the child answers
# with an absolute `$(pwd)`. id:5295 made those two spellings match; this file is about
# what happens once they do.
WT_TILDE='~/.cache/relay/worktrees/dotclaude-skills/relay-20260909-205831-5121-handoff-6d7e-0'
WT_ABS="$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/relay-20260909-205831-5121-handoff-6d7e-0"

# A DIFFERENT unit of the same run, carried by exactly ONE transcript — the control that
# stops the fix from being "always fail".
SOLO_TILDE='~/.cache/relay/worktrees/dotclaude-skills/relay-20260909-205831-5121-execute-9c31-0'
SOLO_ABS="$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/relay-20260909-205831-5121-execute-9c31-0"

mk_child() {  # mk_child <dir> <agentid> <prompt-worktree-spelling> <padding-bytes>
  local f="$1/agent-$2.jsonl"
  printf '{"agentId":"%s","type":"user","message":{"role":"user","content":"You are a relay HANDOFF child for the repo dotclaude-skills. Your worktree %s on branch relay/x was already created for you before dispatch (id:34b7). Work EXCLUSIVELY in that worktree."}}\n' "$2" "$3" > "$f"
  if (( $4 > 0 )); then
    head -c "$4" /dev/zero | tr '\0' 'x' >> "$f"
    printf '\n' >> "$f"
  fi
  echo "$f"
}

# The unit child. 349,000 B of padding puts it over context-budget.sh's handback
# threshold, so a wrong pick here is not merely wrong — it is a HANDBACK verdict handed
# to a child whose own context may be nearly empty.
F_ME="$(mk_child "$WFDIR" a6d7e00000000001 "$WT_TILDE" 349000)"
# The id:34b7 provisioner, whose prompt names the same worktree as a bare command
# argument. Written in that real shape, not as prose.
F_PROV="$WFDIR/agent-a6d7e00000000002.jsonl"
printf '{"agentId":"a6d7e00000000002","type":"user","message":{"role":"user","content":"Run exactly this one command and report its stdout VERBATIM (id:34b7 pre-dispatch worktree creation):\\n```relay-mech\\n~/.claude/skills/relay/scripts/provision-worktree.sh /src/dotclaude-skills %s relay/x\\n```"}}\n' "$WT_TILDE" > "$F_PROV"
head -c 4000 /dev/zero | tr '\0' 'x' >> "$F_PROV"
printf '\n' >> "$F_PROV"
# The single-match control, a genuinely different unit.
F_SOLO="$(mk_child "$SUBS" a6d7e00000000003 "$SOLO_TILDE" 3000)"

# The provisioner finishes FIRST, so the unit child is the newest — i.e. the old
# tie-break happened to pick correctly here. That is deliberate: the point is that a
# correct guess is still a guess, and a fix must refuse anyway.
touch -d '2026-09-09 20:58:00' "$F_PROV"
touch -d '2026-09-09 21:05:00' "$F_ME"

run_resolver() {
  HOME="$FAKE_HOME" "$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" "$@"
}
run_budget() {
  HOME="$FAKE_HOME" "$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" "$@"
}

# ------------------------------------------------------------------ 1. TWO matches: REFUSE
set +e
out="$(run_resolver --marker "$WT_ABS" 2>"$tmpdir/e1")"; rc=$?
set -e
err1="$(cat "$tmpdir/e1")"
(( rc != 0 )) \
  || fail "a marker matching TWO transcripts exited 0 and returned '$out' — an ambiguous identity must REFUSE, not pick (the :219 zero-match branch already exits non-zero for the same failure)"
(( rc == 4 )) \
  || fail "the multi-match refusal exited $rc; expected 4, the resolver's documented UNRESOLVED code, so context-budget.sh --self fails OPEN to 'unknown' rather than treating it as a crash"
[[ -z "$out" ]] \
  || fail "the multi-match refusal still printed '$out' on stdout — a refusing resolver must print NOTHING a caller could consume"
[[ "$err1" == *"$F_ME"* ]] \
  || fail "the refusal did not name the unit-child candidate $F_ME on stderr"
[[ "$err1" == *"$F_PROV"* ]] \
  || fail "the refusal did not name the provisioner candidate $F_PROV on stderr"
pass "a marker matching two transcripts exits 4 with an empty stdout and both candidates named"

# ------------------------------------------------------------------ 2. not the zero-match message
# The two failures are different and must read differently: a caller (and a human reading
# a run log) has to be able to tell "no such marker" from "that marker is not unique",
# because the remedies are opposite — fix the marker string vs. make the marker unique.
[[ "$err1" != *"matched none"* ]] \
  || fail "the multi-match refusal reported the ZERO-match reason ('matched none'): the two failures must be distinguishable"
pass "the ambiguity refusal states its own reason, distinct from the zero-match one"

# ------------------------------------------------------------------ 3. THREE matches
# A fix that special-cases exactly two candidates (e.g. "if the extra one is the
# provisioner, drop it") passes case 1 and fails here.
F_THIRD="$(mk_child "$WFDIR" a6d7e00000000004 "$WT_TILDE" 1000)"
touch -d '2026-09-09 21:09:00' "$F_THIRD"
set +e
out="$(run_resolver --marker "$WT_ABS" 2>"$tmpdir/e3")"; rc=$?
set -e
err3="$(cat "$tmpdir/e3")"
(( rc == 4 )) || fail "a marker matching THREE transcripts exited $rc (expected 4) and returned '${out:-<nothing>}'"
for f in "$F_ME" "$F_PROV" "$F_THIRD"; do
  [[ "$err3" == *"$f"* ]] || fail "the three-way refusal did not name candidate $f — EVERY candidate must be listed, not a sample"
done
pass "a three-way match refuses and names all three candidates"
rm -- "$F_THIRD"

# ------------------------------------------------------------------ 4. single match still resolves
# The control that forbids "always fail". Both output forms.
got="$(run_resolver --marker "$SOLO_ABS")"
[[ "$got" == "$F_SOLO" ]] \
  || fail "a UNIQUELY-matching marker resolved to '$got', expected '$F_SOLO' — the refusal must be scoped to ambiguity"
got="$(run_resolver --marker "$SOLO_ABS" --bytes)"
[[ "$got" == "$(wc -c < "$F_SOLO" | tr -d '[:space:]')" ]] \
  || fail "--bytes on a uniquely-matching marker printed '$got', expected the file's real size"
pass "a uniquely-matching marker still resolves, as path and as --bytes"

# ------------------------------------------------------------------ 5. zero match unchanged
set +e
out="$(run_resolver --marker "$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/run-that-never-existed-0" 2>"$tmpdir/e5")"; rc=$?
set -e
(( rc == 4 )) || fail "a marker matching nothing exited $rc (expected 4), returning '${out:-<nothing>}'"
[[ -s "$tmpdir/e5" ]] || fail "an unmatched marker said nothing on stderr (id:4347 no-silent-swallow)"
pass "the zero-match branch is unchanged: exit 4, loud"

# ------------------------------------------------------------------ 6. --allow-ambiguous opt-in
# The escape hatch the ruling requires: a caller that genuinely wants the old behaviour
# must ASK for it. It restores the newest-mtime pick and STAYS LOUD — the opt-in buys a
# usable answer, never silence (id:4347).
set +e
got="$(run_resolver --allow-ambiguous --marker "$WT_ABS" 2>"$tmpdir/e6")"; rc=$?
set -e
err6="$(cat "$tmpdir/e6")"
(( rc == 0 )) \
  || fail "--allow-ambiguous exited $rc on a two-way match; the explicit opt-in must resolve (stderr: $err6)"
[[ "$got" == "$F_ME" ]] \
  || fail "--allow-ambiguous chose '$got'; the most-recently-modified '$F_ME' is the documented tie-break"
[[ "$err6" == *"$F_ME"* && "$err6" == *"$F_PROV"* ]] \
  || fail "--allow-ambiguous resolved without naming every candidate on stderr — the opt-in relaxes the REFUSAL, not the loudness"
pass "--allow-ambiguous restores the newest-mtime pick and still names every candidate"

# ------------------------------------------------------------------ 7. opt-in is not a wildcard
# It must relax AMBIGUITY only. A marker that matches nothing is still unresolved.
set +e
out="$(run_resolver --allow-ambiguous --marker "$FAKE_HOME/.cache/relay/worktrees/dotclaude-skills/run-that-never-existed-0" 2>/dev/null)"; rc=$?
set -e
(( rc == 4 )) \
  || fail "--allow-ambiguous made a ZERO-match marker exit $rc (expected 4), returning '${out:-<nothing>}' — the flag must not become a general fail-open switch"
pass "--allow-ambiguous does not weaken the zero-match branch"

# ------------------------------------------------------------------ 8. rule 2c reports UNKNOWN
# THE POINT OF THE ITEM. `--self` passes no opt-in, so an ambiguous identity must reach
# the executor as `unknown` — not as a verdict computed from F_ME's 349 KB, which is
# exactly the authoritative-looking wrong answer the owner ruled against.
wrong_bytes="$(wc -c < "$F_ME" | tr -d '[:space:]')"
set +e
out="$(run_budget --marker "$WT_ABS" 2>"$tmpdir/e8")"; rc=$?
set -e
[[ "$out" == "context-budget: unknown "* ]] \
  || fail "--self on an ambiguous marker printed '$out'; expected an 'unknown' verdict (stderr: $(cat "$tmpdir/e8"))"
[[ "$out" != *"bytes=$wrong_bytes"* ]] \
  || fail "--self reported bytes=$wrong_bytes — a byte count taken from a GUESSED transcript, which is the defect"
(( rc == 0 )) \
  || fail "--self exited $rc on an unresolvable identity; the fail-open path must exit 0 so a measurement failure never blocks work"
[[ -s "$tmpdir/e8" ]] \
  || fail "--self degraded to 'unknown' without a word on stderr (id:4347)"
pass "context-budget.sh --self reports 'unknown' on an ambiguous marker: $out"

# ------------------------------------------------------------------ 9. --self is not disarmed
# The other half of the control: a child whose marker IS unique must still get a real
# verdict, or the fix has simply turned rule 2c off.
set +e
out="$(run_budget --marker "$SOLO_ABS" 2>/dev/null)"; rc=$?
set -e
[[ "$out" == "context-budget: ok bytes=$(wc -c < "$F_SOLO" | tr -d '[:space:]') "* ]] \
  || fail "--self on a uniquely-matching marker printed '$out', expected a real 'ok' verdict with its byte count"
(( rc == 0 )) || fail "--self ok verdict exited $rc, expected 0"
pass "--self still produces a real verdict when the marker identifies exactly one transcript"

# ------------------------------------------------------------------ 10. read-only
before="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
run_resolver --marker "$WT_ABS" >/dev/null 2>&1 || true
run_resolver --allow-ambiguous --marker "$WT_ABS" >/dev/null 2>&1 || true
run_budget --marker "$WT_ABS" >/dev/null 2>&1 || true
after="$(find "$PROJ" -type f -printf '%p %s\n' | sort)"
[[ "$before" == "$after" ]] \
  || fail "the resolver / --self created, removed or grew a file — both must be pure read-only checks"
pass "resolver and --self remain read-only, refusing and opted-in alike"

echo "ALL PASS: id:6d7e — an ambiguous self-marker refuses loudly instead of guessing"
