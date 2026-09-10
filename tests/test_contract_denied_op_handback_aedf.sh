#!/usr/bin/env bash
# Defect-fix test (NO roadmap item — id:aedf lives only in TODO.md, never promoted to
# ROADMAP.md, so per CLAUDE.md §Testing this file deliberately omits a `# roadmap:` header
# and its failures always count).
#
# id:aedf — a DENIED destructive op must be a HANDBACK, not a puzzle.
#
# WHY (observed live, code-lawless-3b, 2026-09-09, id:9d8c): an execute child wrote its work
# into the MAIN CHECKOUT instead of its worktree (id:c6c8), caught itself, found `git reset
# --hard`, `revert`, `checkout` and `restore` ALL denied by the destructive-op classifier, and
# then worked around the denial with `reset --soft` + unstage + `git show <path> | cp`. The end
# state it reached was verified correct. The pattern is still the violation: the owner ruled on
# exactly this on 2026-08-26 ("devious, don't try something like that again") — the guard binds
# the OUTCOME, not the command.
#
# The gap this pins is a DISTRIBUTION gap, not a judgment gap. That ruling lived only in
# ~/.claude/CLAUDE.md and a private memory file, NEITHER of which an executor child loads —
# `/relay executor` loads relay/references/executor-contract.md and nothing else. So the child
# could reach for the workaround in good conscience. A rule an agent cannot read is not a rule.
#
# HONEST LIMIT (same as id:6f1c's contract test, stated rather than implied): this is a STATIC
# grep over contract TEXT. It proves the contract CARRIES the rule and that the versioned
# surface's bump discipline was followed. It cannot prove a Sonnet child obeys it — an
# instruction is not a guarantee. What it does prevent is the rule silently vanishing in a
# future contract trim, which is how it came to be missing in the first place.
#
# fails-against: added in the same commit as the contract rule, so there is no ancestor tree to
#   overlay. The negative case is a MUTATION that deletes exactly the outcome-not-spelling
#   sentence this file's part (a) exists to pin, leaving rules 5b/5c and the v19 marker intact —
#   i.e. it models the realistic regression (a trim that keeps the heading and drops the
#   load-bearing clause), not a wholesale revert. Relative path only, inside the scratch tree.
# fails-against-mutation: sed -i '/denial binds the OUTCOME, not the spelling/d' relay/references/executor-contract.md
# fails-against-assertion: contract never states that a DENIAL BINDS THE OUTCOME
#
# Hermetic: reads two source files; no repo/network/worktree touched.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$SRC_DIR/relay/references/executor-contract.md"
CLAUDE_MD="$SRC_DIR/CLAUDE.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CONTRACT" ]] || fail "executor-contract.md not found at $CONTRACT"
[[ -f "$CLAUDE_MD" ]] || fail "CLAUDE.md not found at $CLAUDE_MD"

# (a) THE LOAD-BEARING CLAUSE. Not "the contract mentions denials" — the specific thing the
# code-lawless child did not know: the denial binds the end STATE, so another spelling that
# reaches it is still a violation. A contract that only said "don't run denied commands" would
# have permitted the exact workaround that happened.
grep -qi 'denial binds the OUTCOME, not the spelling' "$CONTRACT" \
  || fail "contract never states that a DENIAL BINDS THE OUTCOME (not the spelling) — the id:9d8c workaround stays permissible"

# (b) The rule must be ACTIONABLE, not merely prohibitive. A child told only "stop" with no
# disposition has no legal move and will improvise one — which is how the original workaround
# happened. The contract must route the denial into the existing structured handback and say
# the needed commands go back verbatim for a human to run at an approved prompt.
grep -qiE 'hand ?back' "$CONTRACT" \
  || fail "contract does not route a denied op into a handback — a prohibition with no disposition invites improvisation"
grep -qi 'verbatim' "$CONTRACT" \
  || fail "contract does not say the needed commands are handed back VERBATIM for a human to run"

# (c) The rule must be reachable as a NUMBERED rule, not buried in a note. Children are told to
# "follow these rules exactly"; prose outside the numbered list is demonstrably skippable (6 of
# 12 children in the 2026-09-09 cohort read no governing doc at all — id:73a0).
grep -qE '^5d\. ' "$CONTRACT" \
  || fail "the denied-op rule is not a NUMBERED contract rule (expected a '5d.' entry beside 5b's no-discarding rule)"

# (d) Versioned-surface discipline: adding a rule an in-flight executor must know bumps the
# in-file vN marker, the CLAUDE.md pointer follows it, and the Maintenance log records WHY.
# A silent rule addition is the stale-pointer failure class the marker exists to prevent.
# NOTE the `head -1 < <(...)` idiom rather than `grep … | head -1`: under `set -euo pipefail`
# the pipe form is the id:81d5 SIGPIPE shape this repo lints against (tests/
# test_pipefail_sigpipe_lint.sh), since `head` exits first and kills the producer.
contract_v="$(grep -oE '[0-9]+' < <(head -1 < <(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CONTRACT")))"
pointer_v="$(grep -oE '[0-9]+' < <(head -1 < <(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CLAUDE_MD")))"

[[ -n "$contract_v" ]] || fail "could not find the contract vN marker in executor-contract.md"
[[ -n "$pointer_v" ]] || fail "could not find the '## Relay contract' vN pointer marker in CLAUDE.md"
[[ "$contract_v" == "$pointer_v" ]] \
  || fail "contract marker v$contract_v disagrees with CLAUDE.md pointer v$pointer_v — bump discipline broken"
[[ "$contract_v" -ge 19 ]] \
  || fail "contract is v$contract_v but rule 5d landed at v19 — the rule was added without bumping the marker"
grep -qE '^\*\*v18 . v19 \(id:aedf\)' "$CONTRACT" \
  || fail "Maintenance log has no 'v18 -> v19 (id:aedf)' entry explaining why the rule bumps the contract"

pass "contract states a denial binds the OUTCOME, not the spelling"
pass "denied op routes into a structured handback with the commands returned verbatim"
pass "the rule is numbered (5d), beside rule 5b's no-discarding rule"
pass "contract marker v$contract_v, CLAUDE.md pointer v$pointer_v, Maintenance entry present"

echo "ALL PASS: executor contract makes a denied destructive op a handback (id:aedf)"
