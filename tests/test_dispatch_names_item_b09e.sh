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
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
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

# ---------------------------------------------------------------------------------------
# ADDED CASES (build-time, 2026-07-28) — the four contract clauses above are necessary but
# not sufficient: clause (4)'s second grep is already satisfied by the pre-existing
# `unit.inject_item` (user-injection) branch, so it can pass while the CLASSIFIER's ids
# still reach nothing. These pin the actual deliverable. Nothing above was weakened.
# ---------------------------------------------------------------------------------------

# (5) the naming must be WIRED TO THE CLASSIFIER, not only to user injection.
grep -q 'actionable_routine_ids' "$LOOP" \
  || note "(5) relay-loop.js never reads classify-repo.sh's actionable_routine_ids — the emitted ids reach no dispatch prompt, so the survey is not deleted"

# (6) end-to-end render: an execute unit carrying classifier ids must produce a NAMED
# instruction, and a unit carrying none must fail OPEN to the historical plural one.
# The b09e helpers are extracted by their anchored source markers and evaluated directly.
if command -v node >/dev/null 2>&1; then
  node - "$LOOP" <<'JS' || note "(6) executeNamedInstruction() does not name the classifier-selected item (see node output above)"
const fs = require('node:fs')
const src = fs.readFileSync(process.argv[2], 'utf8')
const start = src.indexOf('// id:b09e — NAME the item')
const end   = src.indexOf('function unitPrompt(')
if (start < 0 || end < 0 || end <= start) { console.error('cannot locate the id:b09e dispatch-naming block in relay-loop.js'); process.exit(1) }
const block = src.slice(start, end)
let fn
try { fn = new Function(block + '\nreturn executeNamedInstruction')() } catch (e) { console.error('id:b09e block failed to evaluate: ' + e); process.exit(1) }
const executeInstruction = fn

const named = executeInstruction({ verdict: 'execute', actionable_routine_ids: ['aaa1', 'aaa2', 'aaa3', 'aaa4'] })
let bad = 0
const need = (cond, msg) => { if (!cond) { console.error('  ' + msg); bad = 1 } }
need(/<!-- id:aaa1 -->/.test(named), 'named dispatch does not mention the selected item id:aaa1')
need(!/Work the open \[ROUTINE\] items/.test(named), 'named dispatch still carries the plural "Work the open [ROUTINE] items" survey instruction')
need(!/aaa4/.test(named), 'named dispatch leaks a 4th candidate — the candidate list must stay bounded')
need(/id:08c0/.test(named), 'named dispatch dropped the SIZE-OUT rule (id:08c0)')

// injection still outranks the classifier pick
const inj = executeInstruction({ verdict: 'execute', inject_item: 'bbbb', actionable_routine_ids: ['aaa1'] })
need(/<!-- id:bbbb -->/.test(inj), 'a user-injected --item must outrank the classifier pick')

// fail-open: no ids at all -> '' so the caller uses the historical plural instruction inline
const none = executeInstruction({ verdict: 'execute' })
need(none === '', 'with no ids available the named branch must yield \'\' so dispatch falls OPEN to the historical plural instruction')

// deterministic: same input -> same instruction
need(executeInstruction({ verdict: 'execute', actionable_routine_ids: ['aaa1', 'aaa2'] })
  === executeInstruction({ verdict: 'execute', actionable_routine_ids: ['aaa1', 'aaa2'] }), 'selection is not deterministic')

process.exit(bad)
JS
fi

# (7) the id-emitting path must stay SIDE-EFFECT-FREE: re-running classify-repo.sh must leave
# the fixture repo byte-identical (no ledger write, no commit, no new file).
before="$(git -C "$repo" status --porcelain)$(git -C "$repo" rev-parse HEAD)"
RELAY_TOML="$tmp/none.toml" "$CLASSIFY" --repo fixture --path "$repo" >/dev/null 2>&1 || true
after="$(git -C "$repo" status --porcelain)$(git -C "$repo" rev-parse HEAD)"
[[ "$before" == "$after" ]] || note "(7) classify-repo.sh mutated the repo — it is declared SIDE-EFFECT-FREE"

# ── (8) WIRING — the feature must actually be CALLED, not merely defined. ───────────
# An independent reviewer PROVED the earlier assertions stayed green on a fully-unwired build:
# reverting the dispatch template to the plural instruction while leaving executeNamedInstruction
# defined-but-never-called still passed, because case (5) greps the whole file and the token
# appears in comments. That is the banked [[relay-builtgreen-but-unreferenced]] class — built,
# tested, green, and referenced by nothing. Pin the CALL SITE, not the token.
tmpl="$(grep -n 'executeNamedInstruction(unit)' "$LOOP" | grep -v '^\s*//' || true)"
[[ -n "$tmpl" ]] \
  || note "(8) executeNamedInstruction is never CALLED — the naming feature is defined but unwired; the dispatch template still emits the plural instruction"

# It must be called from the execute branch of the dispatch template, not some dead helper.
grep -q 'executeNamedInstruction' < <(awk "/verdict === 'execute'/{print}" "$LOOP") \
  || note "(8) executeNamedInstruction is not called from the execute-verdict dispatch line — naming cannot reach a child"

# ── (9) ORPHAN-SUPPRESS must subtract — a named item must never be one the reason forbids. ──
# discover-repo.sh appends "orphan-parked (id:X) — reconcile-first, do NOT work id:X" to
# unit.reason; both strings reach the same child prompt. Naming a suppressed id imperatively
# overrides the instruction beside it (benign pre-b09e, a live conflict after).
awk '/^const namedItemsFor = /,/^\}/' "$LOOP" > "$tmpdir/picker.js"
cat >> "$tmpdir/picker.js" <<'JS'
const out = namedItemsFor({ actionable_routine_ids: ['aaa1','bbb2'], suppressed_item_ids: ['aaa1'] })
if (out[0] === 'aaa1') { console.error('suppressed id aaa1 was NAMED'); process.exit(1) }
if (out.join(',') !== 'bbb2') { console.error('unexpected: ' + out.join(',')); process.exit(1) }
const up = namedItemsFor({ actionable_routine_ids: ['AAA1'], suppressed_item_ids: [] })
if (up.join(',') !== 'aaa1') { console.error('uppercase-hex not normalised: ' + up.join(',')); process.exit(1) }
JS
node "$tmpdir/picker.js" 2>/dev/null \
  || note "(9) namedItemsFor does not subtract unit.suppressed_item_ids (or does not case-normalise) — it can name an item the classifier told the child NOT to work"

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:b09e not built yet" >&2; exit 1; }
echo "ALL PASS: dispatch names the item; emitted ids match the predicate and the count (id:b09e)"
