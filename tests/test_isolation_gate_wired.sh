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
# id:087b RELOCATION — the integrator moved out of an LLM prompt in relay-loop.js into
# relay/scripts/integrate.sh, which relay-loop.js dispatches as one mechanical hop. The
# wiring invariant is UNCHANGED and in fact stronger (the gate is now an executed
# `if ! "$VERIFY_ISO" …; then handback …` rather than a recipe line an agent must obey), so
# the assertions below now read integrate.sh — with the dispatch from relay-loop.js asserted
# separately, since a gate in an unreachable script guards nothing.
INTEG="$SRC_DIR/relay/scripts/integrate.sh"
[[ -x "$INTEG" ]] || fail "integrate.sh not found/executable at $INTEG"
grep -q 'relay/scripts/integrate\.sh' "$LOOP" \
  || fail "wiring: relay-loop.js does not dispatch integrate.sh — the isolation gate is unreachable"
# Strip comment-only lines so a "we should call verify-isolation" note can never satisfy this.
loop_code="$(grep -vE '^[[:space:]]*#' "$INTEG")"

# NOTE (id:b780): feed $loop_code via herestring, NEVER `printf ... | grep`. relay-loop.js is
# ~91 KB — larger than the 64 KB pipe buffer — so printf BLOCKS mid-write while an early-exiting
# reader (`grep -q`, or a `| head -1`) can match at ~63 KB and exit first. printf then dies of
# SIGPIPE (141) and `set -o pipefail` promotes that to a pipeline failure even though grep
# matched (PIPESTATUS=[0]). That made this suite fail ~4% idle and ~55% under load — a spurious
# red that indicts the gate rather than the test. A herestring has no early-exiting reader.
# Same reason `grep -m1` replaces `| head -1` below.
grep -q 'verify-isolation\.sh' <<< "$loop_code" \
  || fail "wiring: integrate.sh never calls verify-isolation.sh — the gate is documented but not wired (the id:f682 gap this item closes)"
pass "wiring: integrate.sh references verify-isolation.sh"

# CWD-INDEPENDENT resolution. The old requirement was the literal
# ~/.claude/skills/relay/scripts/... path, because a repo-relative form spliced into an agent
# prompt only resolves when cwd happens to be dotclaude-skills. integrate.sh resolves its
# helpers from its OWN location ($SCRIPT_DIR, derived from BASH_SOURCE) — the same property,
# obtained more robustly: it holds no matter which repo the integrator is run against, and it
# is also the failure-injection seam the hermetic tests override. The invariant asserted is
# therefore "resolved absolutely, never relative to cwd", not one specific spelling.
grep -qE 'INTEGRATE_VERIFY_ISOLATION:-\$SCRIPT_DIR/verify-isolation\.sh' "$INTEG" \
  || fail "wiring: verify-isolation.sh must be resolved from integrate.sh's own \$SCRIPT_DIR (cwd-independent), not a bare/relative name"
grep -qE 'SCRIPT_DIR="\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)" && pwd\)"' "$INTEG" \
  || fail "wiring: integrate.sh's \$SCRIPT_DIR is not derived from BASH_SOURCE — helper resolution would depend on cwd"
pass "wiring: gate resolved via integrate.sh's own absolute \$SCRIPT_DIR (cwd-independent)"

# The call must ABORT on non-zero, mirroring step 1's clean-tree gate: in the mechanized
# integrator that means a loud, distinctly-coded handback, not a logged warning.
grep -qE 'handback verify-isolation' "$INTEG" \
  || fail "wiring: a non-zero verify-isolation.sh exit must ABORT via a loud HANDBACK[verify-isolation], mirroring step 1's clean-tree gate"
grep -qE 'if ! iso_out=.*VERIFY_ISO' "$INTEG" \
  || fail "wiring: verify-isolation.sh's exit status is not tested — a failing gate would be ignored"
pass "wiring: a non-zero gate exit aborts with a loud HANDBACK[verify-isolation]"

# It must gate the MERGE, i.e. run before the merge --no-ff step.
call_pos="$(grep -nm1 'verify-isolation\.sh' <<< "$loop_code" | cut -d: -f1)"
merge_pos="$(grep -nm1 'merge --no-ff' <<< "$loop_code" | cut -d: -f1)"
if [[ -n "$call_pos" && -n "$merge_pos" ]]; then
  [[ "$call_pos" -lt "$merge_pos" ]] \
    || fail "wiring: the gate must run BEFORE 'merge --no-ff' (call at line $call_pos, merge at $merge_pos) — a gate after the merge guards nothing"
  pass "wiring: gate runs before the merge --no-ff step"
else
  fail "wiring: could not locate both the gate call and the merge --no-ff step in integrate.sh"
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

# ── (b1-dirty) EMPTY worktree + DIRTY tree + main UNMOVED → exit 2 (id:1b13) ──
# Owner-decided 2026-08-14: an empty worktree carrying uncommitted changes is NOT a
# legitimate id:8e3e no-op review — it is the closest signature to "the child worked but
# never committed" (the same breach family this gate exists for), even when main never
# moved. Must fail BEFORE the (b1) main-unmoved short-circuit ever waves it through.
r="$(mkrepo b1dirty)"; w="$(mkwt "$r" b1dirty)"
printf 'uncommitted\n' > "$w/dirty.txt"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 2 ]] || fail "empty + dirty + main unmoved: expected exit 2 (id:1b13 breach-shaped), got $rc — out: $out"
grep -qi 'dirty' <<<"$out" \
  || fail "empty + dirty + main unmoved: exit-2 output should name the dirty entries, got: $out"
grep -q 'dirty.txt' <<<"$out" \
  || fail "empty + dirty + main unmoved: exit-2 output should name dirty.txt, got: $out"
pass "empty worktree + dirty tree + main unmoved → exit 2, names dirty entries (id:1b13 b1)"

# ── (b3-dirty) EMPTY worktree + DIRTY tree + main advanced ONLY by a merge → exit 2 (id:1b13) ──
r="$(mkrepo b3dirty)"; w="$(mkwt "$r" b3dirty)"
git -C "$r" checkout -q -b other main
printf 'other unit work\n' > "$r/other.txt"
git -C "$r" add -A
git -C "$r" commit -qm "other unit"
git -C "$r" checkout -q main
git -C "$r" merge --no-ff -q other -m "merge(relay): other unit"
printf 'uncommitted\n' > "$w/dirty.txt"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 2 ]] || fail "empty + dirty + main advanced only by merge: expected exit 2 (id:1b13 breach-shaped), got $rc — out: $out"
grep -qi 'dirty' <<<"$out" \
  || fail "empty + dirty + main advanced only by merge: exit-2 output should name the dirty entries, got: $out"
grep -q 'dirty.txt' <<<"$out" \
  || fail "empty + dirty + main advanced only by merge: exit-2 output should name dirty.txt, got: $out"
pass "empty worktree + dirty tree + main advanced only by merge → exit 2, names dirty entries (id:1b13 b3)"

# ── (b1-clean) EMPTY worktree + CLEAN tree + main UNMOVED → still exit 0 (id:8e3e regression guard) ──
# Already covered by (b1) above, restated here explicitly per the id:1b13 acceptance to pin
# that the legitimate no-op review must NOT regress alongside the new dirty check.
r="$(mkrepo b1clean)"; w="$(mkwt "$r" b1clean)"
set +e
out="$("$SH" "$w" --base main 2>&1)"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "empty + clean + main unmoved: expected exit 0 (id:8e3e no-op review must not regress), got $rc — out: $out"
pass "empty worktree + clean tree + main unmoved → exit 0 (id:8e3e no-op review unaffected by id:1b13)"

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
