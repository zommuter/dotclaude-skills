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
# COVERAGE HONESTY: cases 1-4 are BEHAVIOURAL (they run the collector and read its output).
# Case 5 is a SOURCE-PARITY drift guard, not a behavioural proof — discover-repo.sh's
# routine_open is only reachable through an orphan-suppress reconcile fixture, which costs
# more setup than the fail-OPEN bug it guards is worth. It is labelled as a parity guard
# here rather than dressed up as a third behavioural case. Its rationale is the
# lib-state-claim.sh header rule: twin consumers of one predicate must return one answer.
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
got="$(aro_of '- [ ] [HARD — pool] @wire DECOMPOSED parent @container <!-- id:0003 -->')"
[[ "$got" == "0" ]] && ok "classify-repo: @container @wire [HARD — pool] is excluded (aro=0)" \
                    || bad "classify-repo: @container @wire pool-lane should be excluded (aro=0), got '$got'"
# ...and the same line WITHOUT the marker must still count, else case 3 is vacuous.
got="$(aro_of '- [ ] [HARD — pool] @wire DECOMPOSED parent <!-- id:0004 -->')"
[[ "$got" == "1" ]] && ok "control: @wire [HARD — pool] without @container counts (aro=1)" \
                    || bad "control: @wire pool-lane without @container should count 1, got '$got'"

# ── Case 4: gather-repo-state.sh must not surface an @container item as top_intensive ──
got="$(intensive_of '- [ ] [ROUTINE] [INTENSIVE — local-llm] DECOMPOSED parent <!-- id:0005 -->')"
[[ -n "$got" ]] && ok "control: [INTENSIVE] without @container surfaces as top_intensive ('$got')" \
                || bad "control: [INTENSIVE] without @container should surface, got empty"
got="$(intensive_of '- [ ] [ROUTINE] [INTENSIVE — local-llm] DECOMPOSED parent @container <!-- id:0006 -->')"
[[ -z "$got" ]] && ok "gather-repo-state: @container [INTENSIVE] not surfaced as top_intensive" \
                || bad "gather-repo-state: @container [INTENSIVE] should not surface, got '$got'"

# ── Case 5 (SOURCE-PARITY drift guard — NOT a behavioural proof; see header) ─────
# discover-repo.sh:154's routine_open filter is only reachable via an orphan-suppress
# reconcile fixture. Its bug is fail-OPEN (a stray @container id keeps the SAME-ITEM
# carve-out from dropping a duplicate execute unit), so it over-dispatches rather than
# wrong-suppresses. Asserted at source level so the third copy of the predicate cannot
# silently drift from the two proven above.
if grep -q '"@manual" not in line' "$DISCOVER"; then
  grep -q '"@container" not in line' "$DISCOVER" \
    && ok "parity: discover-repo.sh routine_open filter names @container" \
    || bad "parity: discover-repo.sh routine_open filter omits @container (fail-open dup-dispatch)"
else
  bad "parity: discover-repo.sh routine_open filter not found — test anchor stale, re-derive it"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
