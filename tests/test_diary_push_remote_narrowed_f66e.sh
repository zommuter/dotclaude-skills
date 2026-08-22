#!/usr/bin/env bash
# id:f66e — git-diary-workflow must never publish to a PUBLIC remote automatically.
#
# NO `# roadmap:` header ON PURPOSE: id:f66e is TODO-only (TODO.md); it has no ROADMAP.md
# checkbox, so the harness's expected-red semantics do not apply and every failure in this
# file is a REAL failure.
#
# fails-against: mutation — drop `--remote origin` from any git-lock-push.sh invocation in
# git-diary-workflow/SKILL.md (e.g. revert line ~42 to a bare `git-lock-push.sh`).
# Assertion (1) then goes RED naming the un-narrowed line. Verified by mutation before
# commit — both directions observed.
#
# WHY (owner decision 2026-08-22): `git-lock-push.sh` pushes to EVERY remote when
# `--remote` is absent — its own documented default ("ABSENT -> push to ALL remotes").
# git-diary-workflow runs after every prompt in every session, so that default published
# to public GitHub from unattended --afk pools and parallel sessions with no human in the
# loop. Measured that day: 77 commits reached github.com/zommuter/dotclaude-skills while
# a handover doc and a July RELAY_STATUS line both asserted the repo was "held" — a hold
# that existed only as PROSE, which nothing reads. The per-remote narrowing (id:4d44) was
# already built and had two dedicated test files; it was simply never passed at this call
# site. This test exists so the rule cannot silently regress into prose again.
#
# SCOPE: asserts the SKILL.md contract only. It does NOT push, does not touch any remote,
# and does not read ~/.claude — the canonical repo file is the single source under test.

set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel)}"
SKILL="$ROOT/git-diary-workflow/SKILL.md"

fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

[ -f "$SKILL" ] || { echo "missing $SKILL"; exit 1; }

# ── (1) every git-lock-push.sh INVOCATION carries --remote ────────────────────
# An invocation is a line that actually calls the script (starts with the path), not a
# prose mention of its name. Anchoring on the path is what keeps assertion (1) from
# passing vacuously off the narrative paragraphs that also say "git-lock-push.sh".
invocations=0
unnarrowed=""
while IFS= read -r line; do
    invocations=$((invocations + 1))
    case "$line" in
        *--remote*) ;;
        *) unnarrowed="$unnarrowed
    $line" ;;
    esac
done < <(grep -E '^[^#]*git-diary-workflow/git-lock-push\.sh' "$SKILL")

if [ "$invocations" -eq 0 ]; then
    fail "no git-lock-push.sh invocations found in SKILL.md — the grep anchor is wrong, so (1) would pass vacuously"
elif [ -n "$unnarrowed" ]; then
    fail "git-lock-push.sh invoked WITHOUT --remote (pushes to ALL remotes, incl. public):$unnarrowed"
else
    pass "all $invocations git-lock-push.sh invocations carry --remote"
fi

# ── (2) the DEFAULT/post-prompt invocations narrow to origin specifically ──────
# --remote alone is not enough: `--remote github` would satisfy (1) while publishing.
if [ "$(grep -cE '^[^#]*git-diary-workflow/git-lock-push\.sh.*--remote origin' "$SKILL")" -ge 3 ]; then
    pass "the three post-prompt invocations (Step 1, 1b, 1c) narrow to origin"
else
    fail "fewer than 3 invocations narrow to '--remote origin' — Step 1, 1b and 1c must all be private-only"
fi

# ── (3) publishing is documented as a SEPARATE, deliberate step ───────────────
if grep -q -- '--remote github' "$SKILL"; then
    pass "an explicit publish step naming a public remote is documented"
else
    fail "no explicit '--remote github' publish step — the deliberate path must be written down, or it will be improvised"
fi

# ── (4) the privacy gate is NOT presented as a safety net ────────────────────
# Guards the framing the owner corrected: the gate is warn-only AND diff-scoped.
if grep -qi 'NOT a safety net' "$SKILL"; then
    pass "SKILL.md states the privacy gate is not a safety net"
else
    fail "SKILL.md must state the pre-push privacy gate is NOT a safety net (warn-only, diff-scoped — id:9bfc)"
fi

[ $fails -eq 0 ] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All git-diary-workflow push-narrowing tests passed."
