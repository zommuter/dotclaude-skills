#!/usr/bin/env bash
# roadmap:60eb
#
# THE DEFECT: `relay/scripts/todo-conformance.sh` measured the SAME line twice and disagreed
# with itself about what a detail pointer is. `shape_residue`/`shape_class` (id:30fe) strip
# the `-- detail: <dir>/<id>.md` pointer and the must-keep lane/gate tokens before measuring;
# `grammar_item_class`'s step 5 (`grammar-item-title-long`, id:b048) did NOT, and counted
# both AS TITLE TEXT.
#
# Why that is not cosmetic: the id:0d7c topology REQUIRES a pointer on any item whose body
# was relocated, and roadmap-lint.sh rule 3(c) (id:e95b) reports DETAIL-POINTER-MISSING when
# it is absent. So planting a MANDATORY pointer pushed a conforming item over the title
# budget with no prose added at all -- the checker penalised the item for obeying the format.
# Observed live in commit 39146fc7 (the id:40c0 migration) on id:7408 and id:372a. Measured
# on this repo 2026-09-03: 147 -> 58 `grammar-item-title-long` findings on TODO.md, i.e. 89
# of 147 were this artifact, and 12 -> 10 on ROADMAP.md.
#
# THE FIX, and case (d) is the half that keeps it fixed: ONE stripper (`strip_chrome`) serves
# both the actor-side shape rule and the checker-side grammar rule. A second spelling of the
# pointer pattern is the id:4983 defect ("make ONE source serve both the actor and the
# checker"); two copies drift, and drift here is silent.
#
# NOT CHANGED HERE, deliberately: `grammar_item_class` returns on its FIRST failure ("ONE
# finding per non-conforming LINE, first failure wins"), so an item with a
# `grammar-item-after-id` finding never reaches the title check at all. That hides genuinely
# long titles (measured 2026-09-03: 6 on ROADMAP.md, 3 on TODO.md). It is a separate
# decision, and case (e) pins the first-failure-wins behaviour so this fix cannot be read as
# having quietly altered it.
#
# NEGATIVE CASE -- recorded as prose, deliberately, and NOT spelled as the machine-readable
# directive. This file carries a `# roadmap:60eb` header, and verify-negative-cases.py's
# roadmap carve-out CANCELS any such declaration on such a file: it is reported as a
# ROADMAP-SHADOWED DECLARATION and never executed, which is a declaration that looks verified
# and is not. So the case is recorded with its OBSERVED result instead.
#
# The case, run by hand 2026-09-03 in a copy of relay/ + tests/ under a scratch dir:
#   mutation:  delete the single line `title="$(strip_chrome "$title")"` from
#              grammar_item_class (the shipped fix; the spec and the rule land together, so
#              there is no ancestor revision to check out).
#   observed:  `FAIL: (a) a required detail pointer must not push a short title over budget`
#              and nothing else -- the file exits at that assertion, which is the one it
#              claims to pin, not an earlier one.
# The fixture margin is what makes that non-vacuous: `SHORT` is 193 chars and the pointer is
# 39, so the mutant measures 232 and only just fires. A comfortably-short fixture would have
# passed under the mutation -- and did, on the first cut of this file.
#
# Hermetic: fixture ledgers in a mktemp -d; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONF" ]] || fail "sanity: todo-conformance.sh must exist and be executable"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# HERMETICITY (id:e350): todo-conformance.sh defaults ALL THREE ratchet baselines to
# committed files, and these fixtures use the real ledger basenames, so without these
# overrides the live repo's baselines would decide this test's verdict.
export SHAPE_BASELINE="$TMP/absent-shape-baseline.txt"
export LENGTH_BASELINE="$TMP/absent-length-baseline.txt"
export STATE_CLAIM_BASELINE="$TMP/absent-state-claim-baseline.txt"

# --- fixture ------------------------------------------------------------------------
# `SHORT` is 193 chars of title, inside the 200-char budget. The pointer adds 39, so the
# PRE-FIX measurement put the pointered twin at 232 and reported it while the bare twin was
# silent -- same prose, one mandatory token apart. The margin is deliberately narrow: a
# fixture comfortably under budget even WITHOUT the strip passes vacuously, which is exactly
# how a negative case gets fooled into a false green.
SHORT='**A title that sits comfortably inside the two-hundred character budget on its own merits and gains nothing at all except the one mandatory detail pointer token the format obliges it to carry**'
LONG='**A title that runs on well past the two-hundred character budget entirely under its own steam, with no pointer and no lane tag anywhere on the line to blame for it, which is exactly the case the rule exists to catch and must keep catching after the pointer stops counting**'


T="$TMP/TODO.md"
cat >"$T" <<MD
# TODO

## Current

- [ ] [ROUTINE] $SHORT <!-- id:aa01 -->
- [ ] [ROUTINE] $SHORT -- detail: \`docs/ledger-notes/aa02.md\` <!-- id:aa02 -->
- [ ] [ROUTINE] $SHORT -- detail: \`docs/roadmap-notes/aa06.md\` <!-- id:aa06 -->
- [ ] [ROUTINE] $LONG <!-- id:aa03 -->
- [ ] $SHORT -- detail: \`docs/ledger-notes/aa04.md\` [HARD] [INPUT — decision] 🚧 <!-- id:aa04 -->
- [ ] [ROUTINE] $LONG -- detail: \`docs/ledger-notes/aa05.md\` <!-- id:aa05 --> trailing
- [ ] [ROUTINE] $LONG -- detail: \`docs/ledger-notes/aa07.md\` <!-- id:aa07 -->
MD

out="$(bash "$CONF" "$T" 2>/dev/null || true)"

flagged() { grep -q "^grammar-item-title-long.*<!-- id:$1 -->" <<<"$out"; }

# (a) THE DEFECT. Same title, one mandatory pointer apart -- the verdicts must agree.
flagged aa01 && fail "fixture is wrong: the bare-title twin id:aa01 must be UNDER budget"
if flagged aa02; then
  fail "(a) a required detail pointer must not push a short title over budget"
fi
pass "(a) a required detail pointer does not push a short title over budget"

# (b) A FOREIGN notes directory is a pointer too. loderite's pointers say docs/roadmap-notes,
#     and a strip that only knows its own repo's spelling re-creates the defect next door.
flagged aa06 && fail "(b) a pointer into a foreign notes directory was counted as title text"
pass "(b) a pointer into a foreign notes directory is stripped like a local one"

# (c) NO UNDER-REPORTING. The strip must remove chrome, never real prose: a title that is
#     long on its own merits is still reported, with and without a pointer.
flagged aa03 || fail "(c) a genuinely over-budget title stopped being reported"
flagged aa07 || fail "(c) an over-budget title carrying a pointer stopped being reported"
pass "(c) genuinely over-budget titles are still reported, pointered or not"

# (d) ONE STRIPPER (id:4983). The grammar rule must go THROUGH the shared helper, not carry a
#     second spelling of the pointer pattern. Asserted structurally, because a behavioural
#     test cannot see a duplicate that currently happens to agree.
grep -q '^strip_chrome()' "$CONF" || fail "(d) the shared strip_chrome helper is missing"
n_shape="$(grep -c 'SHAPE_POINTER_RE}' "$CONF" || true)"
(( n_shape == 1 )) || fail "(d) SHAPE_POINTER_RE is applied in $n_shape places; exactly one (strip_chrome) is the contract"
n_call="$(grep -c 'strip_chrome "' "$CONF" || true)"
(( n_call >= 2 )) || fail "(d) strip_chrome has $n_call callers; both shape_residue and grammar_item_class must use it"
pass "(d) one stripper serves both the shape rule and the grammar rule"

# (e) FIRST-FAILURE-WINS is UNCHANGED. id:aa05 carries text after its id marker; the grammar
#     reports that, not the title, and this fix must not have altered that ordering.
grep -q "^grammar-item-after-id.*id:aa05" <<<"$out" \
  || fail "(e) first-failure-wins changed: id:aa05 should report grammar-item-after-id"
pass "(e) first-failure-wins is unchanged (after-id still pre-empts the title check)"

# (f) THE SHAPE RULE IS UNDISTURBED by the refactor: a conforming pointered line still
#     reports no prose residue, which is what shape_residue said before strip_chrome existed.
grep -q "^shape-.*id:aa02" <<<"$out" \
  && fail "(f) the shape rule regressed: a conforming pointered line now reports prose"
pass "(f) shape_residue is unchanged by routing through strip_chrome"

# (g) MUST-KEEP TOKENS the shrinker relocated MID-LINE are chrome too. The leading-bracket
#     strip cannot reach a lane tag that ended up after the pointer, and those tags are what
#     the id:0d7c shrinker parks there.
flagged aa04 && fail "(g) mid-line lane and gate tokens were counted as title text"
pass "(g) mid-line lane/gate tokens are chrome, not title"

echo "ALL PASS: $(basename "$0")"
