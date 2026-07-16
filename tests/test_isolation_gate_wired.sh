#!/usr/bin/env bash
# roadmap:7612 — the isolation gate must be WIRED into the integrator, and its signal must
# be unambiguous (main-HEAD discriminator).
#
# Two halves, and the first is the point:
#
# (a) WIRING. id:f682 built verify-isolation.sh, tested it thoroughly (cases a-d), ticked
#     green — and it was never called by anything. Its acceptance asserted the SCRIPT's
#     behaviour but never that a CALL SITE exists, so "the integrator runs it" was satisfied
#     by SKILL.md prose. A gate no code invokes is not a gate. These tests assert the call
#     site itself so it cannot regress to documentation again.
#
# (b) DISCRIMINATOR. "worktree empty" is ambiguous: it is the signature of BOTH a legitimate
#     no-op review (id:8e3e — child audited its window, found nothing; a handback there
#     re-dispatches forever, observed 3x on 2026-07-01) AND an isolation breach (child wrote
#     to the main checkout instead). The breach signature is "empty AND main advanced with a
#     non-merge commit". merge-base(worktree, main) IS the dispatch-time main HEAD, so both
#     facts are derivable from the repo the gate already receives — no pool plumbing needed.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/verify-isolation.sh"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "verify-isolation.sh not found/executable at $SH"
[[ -f "$LOOP" ]] || fail "relay-loop.js not found at $LOOP"

export VERIFY_ISOLATION_LOG=/dev/null

# ── (a) WIRING — the integrator must actually call the gate ──────────────────
# Strip comment-only lines so a "we should call verify-isolation" note can never satisfy this.
loop_code="$(grep -vE '^[[:space:]]*//' "$LOOP")"

printf '%s\n' "$loop_code" | grep -q 'verify-isolation\.sh' \
  || fail "wiring: relay-loop.js never calls verify-isolation.sh — the gate is documented but not wired (the id:f682 gap this item closes)"
pass "wiring: relay-loop.js references verify-isolation.sh"

# Absolute installed path, like every other integrator gate. The repo-relative form
# (relay/scripts/verify-isolation.sh) only resolves when cwd is dotclaude-skills itself, so
# in any other target repo it would fail even when installed.
printf '%s\n' "$loop_code" | grep -q '~/\.claude/skills/relay/scripts/verify-isolation\.sh' \
  || fail "wiring: verify-isolation.sh must be invoked via the absolute ~/.claude/skills/... path (the repo-relative form only resolves when cwd is dotclaude-skills)"
pass "wiring: gate invoked via the absolute ~/.claude/skills/... path"

# The call must carry an ABORT instruction, mirroring step 1's clean-tree-gate text.
# Look at the recipe line containing the call.
call_line="$(printf '%s\n' "$loop_code" | grep 'verify-isolation\.sh' | head -1)"
printf '%s' "$call_line" | grep -qi 'ABORT' \
  || fail "wiring: the verify-isolation.sh recipe step must instruct ABORT on non-zero exit (mirroring step 1 clean-tree-gate); got: ${call_line:0:160}"
pass "wiring: recipe step instructs ABORT on non-zero exit"

# It must gate the MERGE, i.e. appear before the merge --no-ff step in the recipe text.
call_pos="$(printf '%s\n' "$loop_code" | grep -n 'verify-isolation\.sh' | head -1 | cut -d: -f1)"
merge_pos="$(printf '%s\n' "$loop_code" | grep -n 'merge --no-ff' | head -1 | cut -d: -f1)"
if [[ -n "$call_pos" && -n "$merge_pos" ]]; then
  [[ "$call_pos" -lt "$merge_pos" ]] \
    || fail "wiring: the gate must run BEFORE 'merge --no-ff' (call at line $call_pos, merge at $merge_pos) — a gate after the merge guards nothing"
  pass "wiring: gate runs before the merge --no-ff step"
else
  fail "wiring: could not locate both the gate call and the merge --no-ff step in relay-loop.js"
fi

# ── Hermetic repo helpers ───────────────────────────────────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkrepo() { # <name> → prints repo path; a repo with one commit on main
  local r="$TMP/$1"
  git init -q -b main "$r"
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
  printf 'seed\n' > "$r/a.txt"
  git -C "$r" add -A
  git -C "$r" commit -qm init
  printf '%s' "$r"
}

mkwt() { # <repo> <name> → prints worktree path; branch relay/<name> cut from main HEAD
  local r="$1" n="$2"
  git -C "$r" worktree add -q "$r-wt-$n" -b "relay/$n" main
  printf '%s' "$r-wt-$n"
}

# ── (b1) empty worktree + main UNMOVED → exit 0 (legitimate id:8e3e no-op review) ──
r="$(mkrepo b1)"; w="$(mkwt "$r" b1)"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "empty + main unmoved: expected exit 0 (legitimate id:8e3e no-op review — a handback here re-dispatches the same review forever), got $rc — out: $out"
pass "empty worktree + main unmoved → exit 0 (id:8e3e no-op review not misread as a breach)"

# ── (b2) empty worktree + main advanced by a NON-MERGE commit → exit 2 (breach) ──
# This is the loderite/jobAI signature: the child bypassed its worktree and committed to main.
r="$(mkrepo b2)"; w="$(mkwt "$r" b2)"
printf 'child wrote here instead\n' > "$r/leaked.txt"
git -C "$r" add -A
git -C "$r" commit -qm "leaked: child committed straight to main"
leak="$(git -C "$r" rev-parse --short HEAD)"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 2 ]] || fail "empty + main advanced by non-merge: expected exit 2 (isolation breach), got $rc — out: $out"
printf '%s' "$out" | grep -q "$leak" \
  || fail "empty + main advanced: failure output must NAME the offending commit ($leak) so it can be recovered under the id:15d5 lease — got: $out"
pass "empty worktree + main advanced by non-merge commit → exit 2, names the offending commit"

# ── (b3) empty worktree + main advanced ONLY by a MERGE commit → exit 0 ──
# Another unit's --no-ff integration is not this child's breach.
r="$(mkrepo b3)"; w="$(mkwt "$r" b3)"
git -C "$r" checkout -q -b other main
printf 'other unit work\n' > "$r/other.txt"
git -C "$r" add -A
git -C "$r" commit -qm "other unit"
git -C "$r" checkout -q main
git -C "$r" merge --no-ff -q other -m "merge(relay): other unit"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "empty + main advanced only by a merge commit: expected exit 0 (another unit's --no-ff integration is not this child's breach), got $rc — out: $out"
pass "empty worktree + main advanced only by a merge → exit 0 (not a breach)"

# ── (b4) non-empty worktree + clean tree → exit 0 (unchanged behaviour) ──
r="$(mkrepo b4)"; w="$(mkwt "$r" b4)"
printf 'real work\n' > "$w/work.txt"
git -C "$w" add -A
git -C "$w" commit -qm "work in the worktree, as designed"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "non-empty + clean: expected exit 0, got $rc — out: $out"
pass "non-empty worktree + clean tree → exit 0"

# ── (b5) non-empty worktree + DIRTY tree → exit 2 (unchanged behaviour) ──
r="$(mkrepo b5)"; w="$(mkwt "$r" b5)"
printf 'real work\n' > "$w/work.txt"
git -C "$w" add -A
git -C "$w" commit -qm "work in the worktree"
printf 'uncommitted\n' > "$w/dirty.txt"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 2 ]] || fail "non-empty + dirty: expected exit 2, got $rc — out: $out"
pass "non-empty worktree + dirty tree → exit 2"

# ── (c) the gate still mutates nothing ──
code="$(grep -vE '^[[:space:]]*#' "$SH" | grep -vE '(^[[:space:]]*(log|echo)\b|[[:space:]]*msg=)')"
printf '%s\n' "$code" | grep -Eq -- 'git[[:space:]]+(-C[[:space:]]+[^ ]+[[:space:]]+)?(stash|clean)|reset[[:space:]]+--hard|checkout[[:space:]]+--' \
  && fail "gate must be observe-only: it executes a mutating git verb"
pass "gate executes no mutating git verb (observe-only)"

echo "ALL PASS"
