#!/usr/bin/env bash
# id:ff30 — spec for the wiring that makes executor-contract rule 2c RUNNABLE.
#
# NO `# roadmap:XXXX` header ON PURPOSE: id:ff30 is a TODO-only defect item (it has no
# ROADMAP entry of its own — it is the gap left by id:5eeb's ROADMAP unit), so there is
# no checkbox for the EXPECTED-RED machinery to consult. Failures here always count.
#
# THE DEFECT: `relay/scripts/context-budget.sh` (id:5eeb) shipped built, tested and
# green, and was UNREACHABLE. Rule 2c told a pooled executor to run it
# `--transcript <your transcript path>`, but nothing in the dispatch chain ever
# communicated that path to a child, and `--bytes N` needed a size obtainable by no
# means either. This file pins the fix: a child can resolve its OWN transcript.
#
# Hermetic: every assertion runs against a fake projects tree in `mktemp -d` with an
# injected --projects-root/--session-id. Never reads $HOME/.claude, never touches the
# network, never runs a real agent.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT/relay/scripts/self-transcript.sh"
BUDGET="$ROOT/relay/scripts/context-budget.sh"
CONTRACT="$ROOT/relay/references/executor-contract.md"
REPO_CLAUDE_MD="$ROOT/CLAUDE.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# ------------------------------------------------------------------ 1. it exists
[[ -f "$RESOLVER" ]] \
  || fail "relay/scripts/self-transcript.sh not found at $RESOLVER — rule 2c is still unrunnable (id:ff30)"
[[ -x "$RESOLVER" ]] \
  || fail "relay/scripts/self-transcript.sh is not executable"
pass "self-transcript.sh exists and is executable"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ------------------------------------------------------------------ fake harness tree
# Mirrors the layout verified on claude-code 2.1.246:
#   <projects>/<cwd-slug>/<SESSION>/subagents/agent-<id>.jsonl
SESSION="11111111-2222-3333-4444-555555555555"
PROJ="$tmpdir/projects"
SUBS="$PROJ/-home-someone-src-somerepo/$SESSION/subagents"
mkdir -p "$SUBS"
# a decoy project dir for a DIFFERENT session — must never be selected
mkdir -p "$PROJ/-home-someone-src-otherrepo/99999999-0000-0000-0000-000000000000/subagents"
: > "$PROJ/-home-someone-src-otherrepo/99999999-0000-0000-0000-000000000000/subagents/agent-decoy.jsonl"

# Three siblings, as a real `--agents 3` pool produces. Line 1 of each is its verbatim
# dispatch prompt — that is what carries the marker.
mk_child() {  # mk_child <agentid> <worktree-marker> <padding-bytes>
  local f="$SUBS/agent-$1.jsonl"
  printf '{"agentId":"%s","type":"user","message":{"role":"user","content":"You are a relay EXECUTE child. Your worktree %s on branch relay/x was already created for you."}}\n' "$1" "$2" > "$f"
  if (( $3 > 0 )); then
    head -c "$3" /dev/zero | tr '\0' 'x' >> "$f"
    printf '\n' >> "$f"
  fi
  echo "$f"
}

WT_A="/home/x/.cache/relay/worktrees/alpha-run1-execute-repo-0"
WT_B="/home/x/.cache/relay/worktrees/beta-run1-execute-repo-0"
WT_C="/home/x/.cache/relay/worktrees/gamma-run1-execute-repo-0"

F_A="$(mk_child aaaa1111 "$WT_A" 1000)"
F_B="$(mk_child bbbb2222 "$WT_B" 400000)"
F_C="$(mk_child cccc3333 "$WT_C" 250000)"

run_resolver() { "$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" "$@"; }

# ------------------------------------------------------------------ 2. picks MY file
got="$(run_resolver --marker "$WT_A")"
[[ "$got" == "$F_A" ]] || fail "marker '$WT_A' resolved to '$got', expected '$F_A'"
got="$(run_resolver --marker "$WT_B")"
[[ "$got" == "$F_B" ]] || fail "marker '$WT_B' resolved to '$got', expected '$F_B'"
pass "a child picks its OWN transcript out of 3 siblings by its worktree marker"

# ------------------------------------------------------------------ 3. never the decoy
[[ "$(run_resolver --marker "$WT_C")" == "$F_C" ]] \
  || fail "marker '$WT_C' did not resolve to $F_C"
out="$(run_resolver --marker "agent-decoy" 2>/dev/null || true)"
[[ -z "$out" ]] \
  || fail "resolver reached a DIFFERENT session's transcript ('$out') — session scoping is broken"
pass "a different session's transcripts are never candidates"

# ------------------------------------------------------------------ 4. --bytes
b="$(run_resolver --marker "$WT_A" --bytes)"
real="$(wc -c < "$F_A" | tr -d '[:space:]')"
[[ "$b" == "$real" ]] || fail "--bytes reported '$b', file is '$real' bytes"
pass "--bytes reports the transcript's true size ($real B)"

# ------------------------------------------------------------------ 5. LOUD on failure
set +e
out="$("$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" --marker "no-such-worktree" 2>"$tmpdir/err")"
rc=$?
set -e
(( rc != 0 )) || fail "an unmatched marker exited 0 — an unresolvable transcript must be loud, not silently wrong"
[[ -z "$out" ]] || fail "an unmatched marker still printed '$out' to stdout"
[[ -s "$tmpdir/err" ]] || fail "an unmatched marker produced an EMPTY stderr (id:4347 no-silent-swallow)"
pass "unresolvable → nonzero exit, empty stdout, non-empty stderr (rc=$rc)"

set +e
"$RESOLVER" --session-id "$SESSION" --projects-root "$tmpdir/nope" >"$tmpdir/o2" 2>"$tmpdir/e2"
rc=$?
set -e
(( rc != 0 )) || fail "a missing projects root exited 0"
[[ -s "$tmpdir/e2" ]] || fail "a missing projects root produced an empty stderr"
pass "a missing projects root is loud too (rc=$rc)"

# ------------------------------------------------------------------ 6. ambiguity policy
# Two transcripts carrying the SAME marker (a resume child reusing a worktree path):
# newest mtime wins, and EVERY candidate is named on stderr.
F_DUP="$(mk_child dddd4444 "$WT_A" 500)"
touch -d '2020-01-01 00:00:00' "$F_A"
touch -d '2030-01-01 00:00:00' "$F_DUP"
got="$("$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" --marker "$WT_A" 2>"$tmpdir/e3")"
[[ "$got" == "$F_DUP" ]] || fail "ambiguous marker chose '$got'; the most-recently-modified '$F_DUP' should win"
[[ -s "$tmpdir/e3" ]] || fail "an ambiguous marker resolved SILENTLY — every candidate must be named on stderr"
err3="$(cat "$tmpdir/e3")"
[[ "$err3" == *"$F_A"* ]] || fail "the ambiguity warning did not name the losing candidate $F_A"
pass "ambiguous marker → newest wins, all candidates named on stderr"
rm -- "$F_DUP"
touch "$F_A"

# ------------------------------------------------------------------ 7. context-budget --self
# THE POINT OF THE WHOLE ITEM: the executor's rule-2c command runs end to end with
# nothing but a marker it already has.
budget() { "$BUDGET" --self --session-id "$SESSION" --projects-root "$PROJ" "$@"; }

set +e
out="$(budget --marker "$WT_A" 2>"$tmpdir/be1")"; rc=$?
set -e
[[ "$out" == "context-budget: ok bytes=$(wc -c < "$F_A" | tr -d '[:space:]') "* ]] \
  || fail "--self on the small transcript printed '$out' (expected an 'ok' verdict with its real byte count)"
(( rc == 0 )) || fail "--self ok verdict exited $rc, expected 0"
pass "context-budget.sh --self --marker <wt> resolves and reports: $out"

set +e
out="$(budget --marker "$WT_B" 2>/dev/null)"; rc=$?
set -e
[[ "$out" == "context-budget: handback "* ]] \
  || fail "--self on the 400 KB transcript printed '$out', expected a handback verdict"
(( rc == 3 )) || fail "--self handback exited $rc, expected 3 (host-gate.sh convention)"
pass "--self over the handback threshold → verdict handback, exit 3"

set +e
out="$(budget --marker "$WT_C" --warn-bytes 100000 --handback-bytes 900000 2>/dev/null)"; rc=$?
set -e
[[ "$out" == "context-budget: warn "* ]] || fail "--self warn band printed '$out'"
(( rc == 0 )) || fail "--self warn exited $rc, expected 0"
pass "--self honours --warn-bytes/--handback-bytes overrides"

# ------------------------------------------------------------------ 8. --self FAILS OPEN
set +e
out="$(budget --marker "definitely-not-a-worktree" 2>"$tmpdir/be2")"; rc=$?
set -e
(( rc == 0 )) || fail "--self with an unresolvable marker exited $rc — a measurement failure must NEVER block work"
[[ "$out" == "context-budget: unknown bytes=0 "* ]] \
  || fail "--self with an unresolvable marker printed '$out', expected the fail-open 'unknown' line"
[[ -s "$tmpdir/be2" ]] || fail "--self fail-open was SILENT (id:4347)"
pass "--self fails OPEN and LOUD when it cannot resolve (verdict unknown, exit 0, stderr non-empty)"

# an explicit --transcript still wins over --self
out="$("$BUDGET" --self --transcript "$F_A" --session-id "$SESSION" --projects-root "$PROJ")"
[[ "$out" == "context-budget: ok bytes=$(wc -c < "$F_A" | tr -d '[:space:]') "* ]] \
  || fail "an explicit --transcript alongside --self did not win: '$out'"
pass "an explicit --transcript still takes precedence over --self"

# ------------------------------------------------------------------ 9. the CONTRACT is wired
contract_text="$(cat "$CONTRACT")"
[[ "$contract_text" == *"--self"* ]] \
  || fail "executor-contract.md rule 2c never names --self — the executor still has no runnable command"
[[ "$contract_text" == *"self-transcript.sh"* ]] \
  || fail "executor-contract.md never names self-transcript.sh"
[[ "$contract_text" != *"--transcript <your transcript path>"* ]] \
  || fail "executor-contract.md still instructs '--transcript <your transcript path>' — that placeholder is exactly the unrunnable form id:ff30 removes"
pass "rule 2c carries a runnable command (--self + self-transcript.sh) and the dead placeholder is gone"

# ------------------------------------------------------------------ 10. versioned-contract discipline
marker_v="$(grep -oE 'relay-executor contract v[0-9]+' "$CONTRACT" | grep -oE '[0-9]+' | sort -rn | awk 'NR==1')"
pointer_v="$(grep -oE 'relay-executor contract v[0-9]+' "$REPO_CLAUDE_MD" | grep -oE '[0-9]+' | sort -rn | awk 'NR==1')"
[[ -n "$marker_v" ]] || fail "no 'relay-executor contract vN' marker in $CONTRACT"
(( marker_v >= 14 )) || fail "contract marker is v$marker_v; changing rule 2c's command is behaviour an in-flight executor must know — it must be >= v14"
[[ "$pointer_v" == "$marker_v" ]] \
  || fail "CLAUDE.md '## Relay contract' pointer is v$pointer_v but the contract marker is v$marker_v — they must agree"
[[ "$contract_text" == *"v13 → v14"* ]] \
  || fail "the contract's ## Maintenance section has no 'v13 → v14' entry"
pass "contract marker v$marker_v, CLAUDE.md pointer v$pointer_v, Maintenance entry present"

# ------------------------------------------------------------------ 11. read-only
before="$(find "$PROJ" -type f | sort)"
"$RESOLVER" --session-id "$SESSION" --projects-root "$PROJ" --marker "$WT_A" >/dev/null 2>&1 || true
budget --marker "$WT_A" >/dev/null 2>&1 || true
after="$(find "$PROJ" -type f | sort)"
[[ "$before" == "$after" ]] \
  || fail "the resolver / --self created or removed files — both must be pure read-only checks"
pass "self-transcript.sh and context-budget.sh --self are read-only"

echo "ALL PASS: id:ff30 — an executor can resolve its own transcript, so rule 2c actually runs"
