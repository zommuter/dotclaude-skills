#!/usr/bin/env bash
# roadmap:b09e
#
# RED SPEC — authored 2026-07-28 (handoff C3), NOT implemented. EXPECTED-RED while id:b09e is
# unticked. Do not weaken this to make it pass.
#
# WHY THIS IS THE CRITICAL-PATH ITEM (refuted by experiment, not argued): a loderite child died
# `Prompt is too long` with BOTH landed fixes in force — `Skill call: None` (the id:9eb7
# countermand held, ~26.4k of fixed overhead gone) and the ledger 6x smaller after archiving. It
# still exhausted the window, and its dispatch still read "Work the open [ROUTINE] items in
# ROADMAP.md" — plural, unnamed. Removing fixed overhead and 5/6 of the ledger was NOT sufficient:
# the unbounded survey alone is fatal. (This refuted the earlier 9eb7 > b09e reordering, which was
# correct arithmetic about the wrong quantity — fixed overhead, not the variable survey.)
#
# THE DATA ALREADY EXISTS AND IS THROWN AWAY: classify-repo.sh evaluates the actionable predicate
# PER LINE with the item's own 4-hex id in scope (`own_id`), then keeps only an integer COUNT and
# discards which items qualified. And the naming slot ALREADY EXISTS in unitPrompt: the
# `unit.inject_item` branch renders "Work specifically the ROADMAP.md item tagged <!-- id:XXXX -->".
# So the build is mostly plumbing an existing value into an existing slot — not a new mechanism.
#
# CONTRACT:
#   1. classify-repo.sh emits the qualifying actionable item id(s) — not just the count. Field name
#      is the implementer's choice; the spec reads whatever is emitted as JSON and requires the ids
#      to be present and correct.
#   2. The emitted set matches EXACTLY the items the actionable predicate accepts: gated (🚧),
#      @manual/human-lane and non-[ROUTINE] items are excluded, same as the count.
#   3. The count and the id list can never disagree — len(ids) == actionable_routine_open. This is
#      the invariant that stops the two drifting apart later.
#   4. The dispatch prompt NAMES a specific item when one is available, so the child does not survey.
#
# NOT in scope: choosing WHICH of several candidates to dispatch (top-N ordering is the
# implementer's call, pin only that it is deterministic); the review/handoff prompts.
#
# Hermetic: fixture repo in mktemp -d; no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
[[ -x "$CLASSIFY" ]] || { note "classify-repo.sh missing"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; mkdir -p "$repo"
git init -q "$repo"; git -C "$repo" config user.email t@e; git -C "$repo" config user.name t

cat > "$repo/ROADMAP.md" <<'MD'
# Roadmap
- [ ] [ROUTINE] first actionable thing <!-- id:aaa1 -->
- [ ] [ROUTINE] second actionable thing <!-- id:aaa2 -->
- [ ] [ROUTINE] gated thing 🚧 GATED (DEP: id:zzzz) <!-- id:bbb1 -->
- [ ] [HARD] not routine <!-- id:ccc1 -->
- [x] [ROUTINE] already done <!-- id:ddd1 -->
MD
: > "$repo/RELAY_LOG.md"; : > "$repo/TODO.md"
git -C "$repo" add -A; git -C "$repo" commit -qm init

out="$(RELAY_TOML="$tmp/none.toml" "$CLASSIFY" --repo fixture --path "$repo" 2>/dev/null)" || true
[[ -n "$out" ]] || note "classify-repo.sh produced no output for the fixture"

# (1)+(2) the qualifying ids must be emitted, and must be exactly {aaa1, aaa2}.
ids="$(jq -r '[.. | strings] | map(select(test("^[0-9a-f]{4}$"))) | unique | join(",")' <<<"$out" 2>/dev/null)"
case "$ids" in
  *aaa1*) : ;;
  *) note "(1) classify-repo.sh does not emit the qualifying actionable item ids (got: '${ids:-none}') — the id:b09e deliverable; today only a count survives" ;;
esac
case "$ids" in
  *bbb1*) note "(2) a GATED item leaked into the emitted actionable ids — must match the predicate exactly" ;;
esac
case "$ids" in
  *ccc1*) note "(2) a [HARD] item leaked into the emitted actionable ROUTINE ids" ;;
esac
case "$ids" in
  *ddd1*) note "(2) a CLOSED item leaked into the emitted actionable ids" ;;
esac

# (3) count and id-list must never disagree.
cnt="$(jq -r '[.. | objects | to_entries[] | select(.key|test("actionable_routine_open")) | .value] | first // empty' <<<"$out" 2>/dev/null)"
if [[ -n "$cnt" && -n "$ids" ]]; then
  n=$(awk -F, '{print NF}' <<<"$ids")
  [[ "$n" == "$cnt" ]] || note "(3) emitted id count ($n) != actionable_routine_open ($cnt) — the two must never drift"
fi

# (4) the dispatch prompt must NAME an item rather than say "the open [ROUTINE] items".
if grep -q 'Work the open \[ROUTINE\] items in ROADMAP.md' "$LOOP"; then
  grep -q 'unit.dispatch_item\|unit.named_item\|Work specifically the ROADMAP.md item' "$LOOP" \
    || note "(4) unitPrompt still tells the child to 'Work the open [ROUTINE] items in ROADMAP.md' (plural, unnamed) with no named-item branch for the execute verdict — this is the survey that kills children"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:b09e not built yet" >&2; exit 1; }
echo "ALL PASS: dispatch names the item; emitted ids match the predicate and the count (id:b09e)"
