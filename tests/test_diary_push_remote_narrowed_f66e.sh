#!/usr/bin/env bash
# id:f66e — git-diary-workflow must never publish to a PUBLIC remote automatically.
#
# NO `# roadmap:` header ON PURPOSE: id:f66e is TODO-only (TODO.md); it has no ROADMAP.md
# checkbox, so the harness's expected-red semantics do not apply and every failure in this
# file is a REAL failure.
#
# fails-against: mutation — add `--all` to any git-lock-push.sh invocation in
# git-diary-workflow/SKILL.md's mandatory post-prompt steps. Assertion (1) then goes RED
# naming the over-broadened line. Verified by mutation before commit — both directions
# observed.
#
# WHY (owner decision 2026-08-22, AMENDED 2026-08-26 by the git-lock-push.sh default flip):
# originally, `git-lock-push.sh` pushed to EVERY remote when `--remote` was absent — its
# own documented default was "ABSENT -> push to ALL remotes". git-diary-workflow runs
# after every prompt in every session, so that default published to public GitHub from
# unattended --afk pools and parallel sessions with no human in the loop. Measured that
# day: 77 commits reached github.com/zommuter/dotclaude-skills while a handover doc and a
# July RELAY_STATUS line both asserted the repo was "held" — a hold that existed only as
# PROSE, which nothing reads. The per-remote narrowing (id:4d44) was already built and had
# two dedicated test files; it was simply never passed at this call site.
#
# 2026-08-26: the owner closed this class of footgun at its root — git-lock-push.sh's
# ABSENT-flag default is now `origin` ONLY (private), and pushing every remote requires
# the NEW, explicit `--all` flag. So a bare `git-lock-push.sh` call in SKILL.md is now
# private-only BY DEFAULT; the danger this test guards against is inverted — it is now
# `--all` (or `--remote` naming a non-private remote) creeping into a mandatory
# post-prompt step that must stay private. This test exists so the rule cannot silently
# regress, in either the old or the new form.
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

# ── (1) NO git-lock-push.sh invocation carries --all ────────────────────────────
# An invocation is a line that actually calls the script (starts with the path), not a
# prose mention of its name. Anchoring on the path is what keeps assertion (1) from
# passing vacuously off the narrative paragraphs that also say "git-lock-push.sh". Since
# the 2026-08-26 default flip, a BARE invocation (no --remote, no --all) is private-only
# by construction — the hazard this test now guards is `--all` (every remote, public
# included) creeping into a mandatory per-prompt step.
invocations=0
broadened=""
while IFS= read -r line; do
    invocations=$((invocations + 1))
    case "$line" in
        *--all*) broadened="$broadened
    $line" ;;
        *) ;;
    esac
done < <(grep -E '^[^#]*git-diary-workflow/git-lock-push\.sh' "$SKILL")

if [ "$invocations" -eq 0 ]; then
    fail "no git-lock-push.sh invocations found in SKILL.md — the grep anchor is wrong, so (1) would pass vacuously"
elif [ -n "$broadened" ]; then
    fail "git-lock-push.sh invoked WITH --all (pushes to ALL remotes, incl. public) in a mandatory post-prompt step:$broadened"
else
    pass "none of the $invocations git-lock-push.sh invocations carry --all"
fi

# ── (2) the default-to-origin contract is documented, not left implicit ────────
# --remote-free invocations rely on the helper's OWN default; SKILL.md must say so, or a
# reader (or a future edit) could reintroduce --all under the mistaken belief that a bare
# call still means "push everything".
if grep -qi 'origin is the DEFAULT remote' "$SKILL" || grep -qi 'default is now `origin`' "$SKILL"; then
    pass "SKILL.md documents that origin is the default (private-only) remote"
else
    fail "SKILL.md does not document the origin-is-default contract — a bare git-lock-push.sh call's safety is unexplained"
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
