#!/usr/bin/env bash
# roadmap:0cf5 — `@container` must exclude a line from the DISPATCH collectors, not only
# from the lint/human ones.
#
# Bug (routed:02d9, found in loderite 2026-07-29 with ids c19e + 2b24 still dispatchable):
# `relay/references/handoff.md:233` and `review.md:304` tell an author to mark a DECOMPOSED
# parent `@container` because "collectors exclude that marker". Two collectors do —
# roadmap-lint.sh (the check that INSTRUCTS you to add it) and gather-human-backlog.sh
# (`if (line ~ /@container/) next`). The dispatch-side collectors do not:
#   * classify-repo.sh  — `is_human` tests HUMAN_GATES / @manual / @owner-verify only, so an
#                         @container [ROUTINE] parent enters actionable_routine_ids and fires
#                         verdict=execute on a container whose seams are the real work.
#   * gather-repo-state.sh — the top_intensive `grep -vP` exclusion list omits it.
#   * discover-repo.sh  — the SAME-ITEM orphan carve-out's routine_open filter omits it.
#
# UPDATED 2026-09-11 (id:790d): discover-repo.sh's copy of the predicate is GONE. The
# SAME-ITEM carve-out no longer re-derives a routine_open set from ROADMAP.md at all; it reads
# the unit's own `actionable_routine_ids`, which classify-repo.sh computed with the strict
# predicate case 1 below proves. So @container parity there is now structural rather than
# textual: there is no second spelling that CAN drift. Case 5 is re-aimed accordingly -- it now
# pins the ABSENCE of a re-derivation instead of the presence of an @container clause in one.
# That is a strictly stronger guard (it fails on ANY resurrected copy, not only on one that
# forgets @container), and it is why the old anchor `'"@manual" not in line'` no longer exists.
#
# COVERAGE HONESTY: cases 1-4 are BEHAVIOURAL (they run the collector and read its output).
# Case 5 is a SOURCE-level structural guard, not a behavioural proof. The BEHAVIOURAL proof
# that the carve-out now agrees with the strict predicate lives in
# tests/test_same_item_carveout_strict_predicate_790d.sh, which drives discover-repo.sh through
# a real orphan-suppress reconcile fixture -- the setup this file declined to pay for. Its
# rationale is the lib-state-claim.sh header rule: twin consumers of one predicate must return
# one answer, and the cheapest way to guarantee that is to have only one consumer.
#
# RED until `@container` is added to all three per-line exclusions.
# Hermetic: mktemp git repos, RELAY_TOML/RELAY_WORKTREE_BASE sandboxed, no ~/.config touch.
# Idiom: tests/test_classify_repo_gated_section.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"
GATHER="$ROOT/relay/scripts/gather-repo-state.sh"
DISCOVER="$ROOT/relay/scripts/discover-repo.sh"
for f in "$CLASSIFY" "$GATHER" "$DISCOVER"; do
  [[ -x "$f" ]] || { echo "FAIL: missing/not executable: $f"; exit 1; }
done

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

# fixture_repo <roadmap-body> → path to a hermetic git repo carrying that ROADMAP.md
fixture_repo() {
  local body="$1"
  local repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"
  git -C "$repo" config user.name "T"
  { printf '# Roadmap\n## Items\n'; printf '%s\n' "$body"; } > "$repo/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

# aro_of <roadmap-body> → classify-repo.sh's actionable_routine_open
aro_of() {
  local repo; repo="$(fixture_repo "$1")"
  "$CLASSIFY" --emit unit --repo fixture --path "$repo" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))'
}

# intensive_of <roadmap-body> → gather-repo-state.sh's top_intensive
intensive_of() {
  local repo; repo="$(fixture_repo "$1")"
  "$GATHER" --repo fixture --path "$repo" --runid test 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("top_intensive") or "")'
}

# ── Case 1 (positive control): a plain [ROUTINE] item counts ─────────────────────
# Proves the exclusion under test is marker-scoped, not a blanket suppression of the
# fixture shape. If this ever goes to 0 the other cases prove nothing.
got="$(aro_of '- [ ] [ROUTINE] DECOMPOSED parent, marker deliberately absent <!-- id:0001 -->')"
[[ "$got" == "1" ]] && ok "control: [ROUTINE] without @container counts (aro=1)" \
                    || bad "control: [ROUTINE] without @container should count 1, got '$got'"

# ── Case 2: @container excludes a [ROUTINE] item from actionable_routine_open ────
got="$(aro_of '- [ ] [ROUTINE] DECOMPOSED into seams — parent is a container @container <!-- id:0002 -->')"
[[ "$got" == "0" ]] && ok "classify-repo: @container [ROUTINE] is excluded (aro=0)" \
                    || bad "classify-repo: @container [ROUTINE] should be excluded (aro=0), got '$got'"

# ── Case 3: the @wire-on-pool-lane branch shares the predicate, so it shares the fix ──
got="$(aro_of '- [ ] [HARD - pool] @wire DECOMPOSED parent @container <!-- id:0003 -->')"
[[ "$got" == "0" ]] && ok "classify-repo: @container @wire [HARD - pool] is excluded (aro=0)" \
                    || bad "classify-repo: @container @wire pool-lane should be excluded (aro=0), got '$got'"
# ...and the same line WITHOUT the marker must still count, else case 3 is vacuous.
got="$(aro_of '- [ ] [HARD - pool] @wire DECOMPOSED parent <!-- id:0004 -->')"
[[ "$got" == "1" ]] && ok "control: @wire [HARD - pool] without @container counts (aro=1)" \
                    || bad "control: @wire pool-lane without @container should count 1, got '$got'"

# ── Case 4: gather-repo-state.sh must not surface an @container item as top_intensive ──
got="$(intensive_of '- [ ] [ROUTINE] [INTENSIVE - local-llm] DECOMPOSED parent <!-- id:0005 -->')"
[[ -n "$got" ]] && ok "control: [INTENSIVE] without @container surfaces as top_intensive ('$got')" \
                || bad "control: [INTENSIVE] without @container should surface, got empty"
got="$(intensive_of '- [ ] [ROUTINE] [INTENSIVE - local-llm] DECOMPOSED parent @container <!-- id:0006 -->')"
[[ -z "$got" ]] && ok "gather-repo-state: @container [INTENSIVE] not surfaced as top_intensive" \
                || bad "gather-repo-state: @container [INTENSIVE] should not surface, got '$got'"

# ── Case 5 (SOURCE-level STRUCTURAL guard -- NOT a behavioural proof; see header) ─────
# The strongest form of parity is having nothing to keep in parity with. Since id:790d the
# SAME-ITEM carve-out reads the unit's own actionable_routine_ids, so the only per-line
# [ROUTINE]/@manual/@container predicate in the dispatch path is classify-repo.sh's, proven
# behaviourally by case 1 above. Assert BOTH halves: no resurrected line predicate, and the
# carve-out really does consume the classifier's list.
if grep -qE '"@manual" not in line|"@container" not in line' "$DISCOVER"; then
  bad "parity: discover-repo.sh has grown a per-line [ROUTINE] predicate again (id:790d removed it). A second spelling WILL drift from classify-repo.sh's; the carve-out must consume actionable_routine_ids instead"
else
  ok "parity: discover-repo.sh carries no per-line [ROUTINE]/@manual/@container predicate of its own"
fi
grep -q 'actionable_routine_ids' "$DISCOVER" \
  && ok "parity: discover-repo.sh's SAME-ITEM carve-out consumes the classifier's actionable_routine_ids" \
  || bad "parity: discover-repo.sh no longer reads actionable_routine_ids -- the carve-out has lost its strict input and must be re-deriving the set somewhere"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
