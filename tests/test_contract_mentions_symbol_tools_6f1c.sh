#!/usr/bin/env bash
# roadmap:6f1c
#
# id:6f1c — teach the executor contract symbol-level exploration (it never
# mentions LSP / Grep / Glob) and the "don't re-read what you already hold"
# rule.
#
# WHY (measured, n=3 dead children, 2026-07-28 loderite cluster): every dead
# child explored with ONLY Bash/Read/Skill — zero Grep, zero Glob, zero LSP
# calls — despite LSP being enabled in settings.json. The tool-choice gap is a
# contract-prose gap, not a capability gap (documentSymbol ~600 tok vs a full
# Read ~3,500 tok on the same file). The bigger measured cost was repeated
# re-reads of the SAME file: one child re-read src/menu.ts five times for
# ~28k tokens on a single file.
#
# AMENDED 2026-07-28 (adversarial review): the original "bounded-survey" half
# is RETRACTED — id:b09e (dispatch names the item) obsoletes it. This test
# checks ONLY the tool-teaching half + the no-redundant-reread rule.
#
# HONEST LIMIT (stated on the item, restated here): this is a STATIC grep over
# contract TEXT. It proves the contract NAMES the tools and the rule; it
# cannot prove a Sonnet child's behaviour changes (same limit as id:9eb7's
# countermand test — an instruction is not a guarantee).
#
# Contract-surface discipline: executor-contract.md is a VERSIONED surface.
# Editing its rules requires bumping the `contract vN` marker in-file AND
# updating the CLAUDE.md `## Relay contract` pointer to match — this test
# also asserts those two markers agree (the existing double-load/stale-pointer
# failure mode this repo's own versioning doc exists to prevent).
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

# (a) tool-teaching half: the contract must name Grep, Glob, and LSP as
# preferred exploration tools over uncapped Bash/Read.
grep -qi '\bGrep\b' "$CONTRACT" \
  || fail "contract never mentions Grep — the tool-choice gap that starved n=3 dead children"
grep -qi '\bGlob\b' "$CONTRACT" \
  || fail "contract never mentions Glob"
grep -qi '\bLSP\b' "$CONTRACT" \
  || fail "contract never mentions LSP (documentSymbol etc. — ~600 tok vs ~3,500 tok for a full Read)"

# (b) the bigger measured cost: re-reading the same file repeatedly (one
# child burned ~28k tokens re-reading src/menu.ts five times). The contract
# must state that a file already read this session is already in context and
# must not be re-read.
grep -qiE 're-?read' "$CONTRACT" \
  || fail "contract does not warn against re-reading a file already held in context (measured ~28k-token cost)"

# (c) contract-surface discipline: the in-file vN marker and the CLAUDE.md
# pointer marker must agree — a stale pointer is exactly the silent-breakage
# class the vN marker exists to prevent (CLAUDE.md 'Versions live only on
# contract surfaces').
contract_v="$(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CONTRACT" | head -1 | grep -oE '[0-9]+')"
pointer_v="$(grep -oE '<!-- relay-executor contract v[0-9]+ -->' "$CLAUDE_MD" | head -1 | grep -oE '[0-9]+')"

[[ -n "$contract_v" ]] || fail "could not find the contract vN marker in executor-contract.md"
[[ -n "$pointer_v" ]] || fail "could not find the '## Relay contract' vN pointer marker in CLAUDE.md"
[[ "$contract_v" == "$pointer_v" ]] \
  || fail "contract marker v$contract_v disagrees with CLAUDE.md pointer v$pointer_v — bump discipline broken"

pass "contract names Grep/Glob/LSP as preferred exploration tools"
pass "contract warns against re-reading a file already held in context"
pass "contract vN marker ($contract_v) agrees with the CLAUDE.md pointer"

echo "ALL PASS: executor contract teaches symbol-level exploration (id:6f1c)"
