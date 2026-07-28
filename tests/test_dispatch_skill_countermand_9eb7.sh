#!/usr/bin/env bash
# roadmap:9eb7
#
# id:9eb7 step 1 — the dispatch prompt must COUNTERMAND the Skill load.
#
# WHY (measured, not inferred — loderite run relay-20260728-112417-3898, both dead children):
# each target repo's CLAUDE.md carries a `## Relay contract` pointer saying "Load `/relay
# executor` before working on any item". A child obeying it calls Skill(relay, executor) — and
# the Skill tool IGNORES the `executor` arg, injecting the ~26.4k-token ORCHESTRATOR SKILL.md
# instead of the contract. Verified from the transcripts' own API usage fields: entry [11]
# `cache_creation_input_tokens` = 26,394 in BOTH children, identical; the executor-contract body
# is absent from that payload (children Read it separately, +5,513). So the child pays ~26.4k to
# be told, by prose inside the payload, to ignore almost all of it.
#
# The fleet-wide fix (rewriting every managed repo's CLAUDE.md pointer) rides the review cycle
# and takes as long as the slowest repo. THIS countermand lands in one file and covers the dying
# population — pool children — immediately, regardless of fleet state.
#
# Guards the two ways this silently regresses:
#   (a) the countermand is dropped or reworded away, so children resume loading the orchestrator;
#   (b) the countermand lands but the direct contract Read does NOT, leaving a child with no
#       contract at all — strictly worse than the bug it replaces.
#
# SCOPE, stated honestly: this is a STATIC assertion over the dispatch template source. It proves
# the instruction is PRESENT, not that a Sonnet child obeys it (same limit as id:6f1c's contract
# grep — an instruction is not a guarantee; note both 07-28 children silently ignored the
# dispatch's existing "Read conventions.md" instruction). Evaluation of the template is already
# covered by tests/test_relay_loop_all_builders_exec.sh (id:aec5); this file deliberately does not
# duplicate that harness. The real acceptance is a measured drop in child context — record it on
# the item, not here.
#
# Hermetic: reads one source file; no repo/network/worktree touched.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LOOP" ]] || fail "relay-loop.js not found at $LOOP"

# Isolate the dispatch prompt builder so a stray match elsewhere in the file cannot satisfy this.
body="$(awk '/^function unitPrompt\(unit\) \{/,/^\}/' "$LOOP")"
[[ -n "$body" ]] || fail "could not locate the unitPrompt() dispatch builder in relay-loop.js"

# (a) the countermand must be present, inside unitPrompt, and name the exact call it forbids.
grep -qi 'do NOT invoke the Skill tool' <<<"$body" \
  || fail "dispatch prompt lost the Skill countermand (id:9eb7) — children will resume loading the ~26.4k orchestrator SKILL.md"
grep -q 'Skill(relay, executor)' <<<"$body" \
  || fail "countermand must name the exact call it forbids, Skill(relay, executor), or a child will not recognise what to skip"

# It must override the repo-side instruction explicitly — that pointer is what triggers the load,
# so a countermand that does not mention it reads as a mere preference and loses the conflict.
grep -qi 'CLAUDE.md' <<<"$body" \
  || fail "countermand must state that it OVERRIDES the target repo's CLAUDE.md '## Relay contract' pointer"

# (b) countermanding without redirecting is strictly worse than the bug: no contract at all.
grep -q 'executor-contract.md' <<<"$body" \
  || fail "countermand present but no direct Read of executor-contract.md — the child would end up with NO contract"

pass "dispatch prompt countermands Skill(relay, executor) and names the CLAUDE.md pointer it overrides"
pass "dispatch prompt still routes the child to executor-contract.md directly"

echo "ALL PASS: dispatch Skill countermand (id:9eb7 step 1)"
