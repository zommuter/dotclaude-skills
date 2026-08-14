#!/usr/bin/env bash
# roadmap:7517 — the dispatch-exclusion predicates must be VOCAB-COMPLETE and must honour
# `@owner-gated`.
#
# Three separate defects, one root cause (the lane-vocab migration left old-spelling greps
# behind in the DISPATCH path — every correctly re-laned item widens the hole):
#
#  (1) gather-repo-state.sh's `top_intensive` excluded human-gated items with an OLD-VOCAB-ONLY
#      grep (`[HARD — hands|meeting|decision gate]|@manual|@container|[MECHANICAL]|🚧|blocked`).
#      The capability-keyed replacements `[INPUT — access]` / `[INPUT — meeting]` /
#      `[INPUT — decision]` were absent, so a NEW-VOCAB human-gated [INTENSIVE] item passed the
#      filter and became the resource-claiming top item — re-creating the id:a707 defect
#      (2026-06-23 zomni: a human-gated [INTENSIVE — local-llm] item was auto-dispatched and
#      could not complete). `open_hard_pool` already handles BOTH spellings (roadmap_primary_lane
#      normalizes them); the two must be consistent.
#
#  (2) OWNER RULING 2026-08-14 (answers routed:34a2's open question): `@owner-gated` IS a
#      dispatch exclusion, alongside @manual/@container. Rationale: FAIL-SAFE — an owner-gated
#      item handed to an executor is wasted work, and the only thing protecting such items today
#      is the accidental substring match in lib-roadmap-sections.sh's parked-heading vocab
#      (`@owner-gated` happens to contain `gated`), which id:f391/id:6446 remove.
#
#  (3) routed:2d94 — the relay-loop.js HARD-execute child brief told the child to "Pick the TOP
#      open item tagged [HARD — pool] in ROADMAP.md", i.e. to RE-DERIVE the pool-lane enumeration
#      by raw grep on the RETIRED spelling. In loderite run relay-20260814-133435-24323 it found
#      0 and refused 5 real bare-[HARD] items. Mechanize-first: the resolved list already exists
#      (gather-repo-state.sh's open_hard_pool walk) — it must be HANDED to the child, and
#      re-deriving it forbidden.
#
# Hermetic: builds repos under mktemp; never touches ~/.claude or the network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
CLASSIFY="$SRC_DIR/relay/scripts/classify-repo.sh"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }
[[ -f "$LOOP" ]]   || { echo "FAIL: relay-loop.js missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }
jfield() { python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }

mkrepo() {  # mkrepo <name> <roadmap-body-file>; returns the path
  local name="$1"; local body="$2"; local r="$TMP/$name"
  mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@e; git -C "$r" config user.name t
  printf '# ROADMAP\n\n## Now\n%s\n' "$(cat "$body")" > "$r/ROADMAP.md"
  git -C "$r" add -A; git -C "$r" commit -qm init
  echo "$r"
}
gather() { RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" "$GATHER" --repo "$1" --path "$2" --runid test; }

empty_ti() { [[ "$1" == "None" || -z "$1" ]]; }

# ---------------------------------------------------------------------------
# A. top_intensive — NEW-VOCAB human gates must suppress, exactly as old vocab does.
# ---------------------------------------------------------------------------
b1="$TMP/b1"; printf '%s\n' \
  '- [ ] Provision the GPU box [INPUT — access] [INTENSIVE — local-llm] <!-- id:aaaa -->' \
  '- [ ] Decide the quantisation policy [INPUT — decision] [INTENSIVE — local-llm] <!-- id:bbbb -->' \
  '- [ ] Design the eval harness [INPUT — meeting] [INTENSIVE — gpu-bench] <!-- id:cccc -->' > "$b1"
r1="$(mkrepo r1 "$b1")"
ti="$(field top_intensive <<<"$(gather r1 "$r1")")"
empty_ti "$ti" \
  && ok "new-vocab [INPUT — access|decision|meeting] [INTENSIVE] → top_intensive empty" \
  || bad "top_intensive='$ti' for new-vocab human-gated [INTENSIVE] items — would force an undoable dispatch (id:7517)"

# Positive control (the acceptance clause insists on it — the suppression case alone would pass
# against a filter that excludes EVERYTHING).
b2="$TMP/b2"; printf '%s\n' \
  '- [ ] Provision the GPU box [INPUT — access] [INTENSIVE — local-llm] <!-- id:aaaa -->' \
  '- [ ] Benchmark sweep [ROUTINE] [INTENSIVE — gpu-bench] <!-- id:cccc -->' > "$b2"
r2="$(mkrepo r2 "$b2")"
ti2="$(field top_intensive <<<"$(gather r2 "$r2")")"
[[ "$ti2" == "gpu-bench" ]] \
  && ok "actionable [ROUTINE] [INTENSIVE] still emits its resource alongside a new-vocab gate" \
  || bad "top_intensive='$ti2', expected 'gpu-bench' — the fix must not suppress real work"

# B. @owner-gated is an exclusion for top_intensive (OWNER RULING 2026-08-14).
b3="$TMP/b3"; printf '%s\n' \
  '- [ ] Ratify the substrate choice @owner-gated [ROUTINE] [INTENSIVE — gpu-bench] <!-- id:dddd -->' > "$b3"
r3="$(mkrepo r3 "$b3")"
ti3="$(field top_intensive <<<"$(gather r3 "$r3")")"
empty_ti "$ti3" \
  && ok "@owner-gated [INTENSIVE] → top_intensive empty (owner ruling, routed:34a2)" \
  || bad "top_intensive='$ti3' for an @owner-gated item — an owner-gated item must never be auto-dispatched"

# ---------------------------------------------------------------------------
# C. open_hard_pool — @owner-gated excluded; bare [HARD] and [HARD — pool] both counted.
# ---------------------------------------------------------------------------
b4="$TMP/b4"; printf '%s\n' \
  '- [ ] Owner must ratify the ledger substrate @owner-gated [HARD] <!-- id:eeee -->' \
  '- [ ] Real pool work, new spelling [HARD] <!-- id:ffff -->' \
  '- [ ] Real pool work, old spelling [HARD — pool] <!-- id:1111 -->' > "$b4"
r4="$(mkrepo r4 "$b4")"
g4="$(gather r4 "$r4")"
ohp="$(field open_hard_pool <<<"$g4")"
[[ "$ohp" == "2" ]] \
  && ok "open_hard_pool=2 — @owner-gated excluded, both [HARD] spellings counted" \
  || bad "open_hard_pool='$ohp', expected 2 (@owner-gated must not count; both spellings must)"

# D. The RESOLVED list is emitted, not just its count (routed:2d94 — the child must be HANDED it).
ids="$(jfield open_hard_pool_ids <<<"$g4")"
[[ "$ids" == '["ffff", "1111"]' ]] \
  && ok "open_hard_pool_ids emits the resolved ids in ROADMAP file order" \
  || bad "open_hard_pool_ids=$ids, expected [\"ffff\", \"1111\"] (the resolved pool-lane list the HARD child must consume)"

# ---------------------------------------------------------------------------
# C2. THE REAL routed:2d94 FIXTURE — the literal ledger lines the loderite child read
# (loderite ROADMAP.md@e68c143, run relay-20260814-133435-24323). The shape VARIETY is the
# point, and the matcher must handle all three: a bare `[HARD] **`, one with an `@owner-gated`
# marker sitting BETWEEN the lane tag and the title (so a line-START-anchored test would MISS
# it), and two with an em-dash separator `[HARD] — **`. The child's sweep matched only
# `[HARD — pool]` and found NONE of them.
#
# EXPECTED: 4 dispatchable, NOT 5 — 0873 is EXCLUDED because `@owner-gated` is now a
# first-class dispatch exclusion (owner ruling 2026-08-14). That count change is DELIBERATE.
#
# routed:3ad9 hazard, live in this fixture: the 3890 and ef07 lines each carry TWO id comments,
# trailing in a reference to `50f3` — which is a CLOSED [x] item. A last-match/greedy extractor
# attributes those OPEN items to the CLOSED id. They must NEVER be attributed to 50f3.
# ---------------------------------------------------------------------------
b5="$TMP/b5"; printf '%s\n' \
  '- [ ] [HARD] **Add explicit `renderer` + `metricClass` fields to the layer descriptor** <!-- id:c040 -->' \
  '- [ ] [HARD] **Reference-slot hotbar core (customizable hotbar v1)** <!-- id:a728 -->' \
  '- [ ] [HARD] `@owner-gated` **Feature-EXISTENCE-cost benchmark before any new layer lands** <!-- id:0873 -->' \
  '- [ ] [HARD] — **50f3 (a)-emission: contiguous same-(material, flavor) run emission** <!-- id:3890 --> <!-- id:50f3 -->' \
  '- [ ] [HARD] — **50f3 (b)-interior: two-way interior/boundary segment cull** <!-- id:ef07 --> <!-- id:50f3 -->' \
  '- [x] [HARD] **50f3 parent (CLOSED)** <!-- id:50f3 -->' > "$b5"
r5="$(mkrepo r5 "$b5")"
g5="$(gather r5 "$r5")"
ohp5="$(field open_hard_pool <<<"$g5")"
[[ "$ohp5" == "4" ]] \
  && ok "real loderite fixture: open_hard_pool=4 (all 5 [HARD] shapes seen; @owner-gated 0873 excluded)" \
  || bad "open_hard_pool='$ohp5', expected 4 — bare [HARD], '[HARD] — ' em-dash, and mid-line @owner-gated must all be handled"

ids5="$(jfield open_hard_pool_ids <<<"$g5")"
case "$ids5" in
  *'"0873"'*) bad "open_hard_pool_ids contains 0873 — the @owner-gated item must never be dispatchable" ;;
  *)          ok "open_hard_pool_ids excludes the mid-line @owner-gated item (0873)" ;;
esac
case "$ids5" in
  *'"50f3"'*) bad "open_hard_pool_ids contains 50f3 — an OPEN item was attributed to a CLOSED id (routed:3ad9 greedy-extraction bug)" ;;
  *)          ok "no open item is attributed to the trailing CLOSED id 50f3 (routed:3ad9)" ;;
esac
case "$ids5" in
  '["c040", "a728"'*) ok "the two unambiguous [HARD] items are named, in ROADMAP file order" ;;
  *)                  bad "open_hard_pool_ids=$ids5, expected it to start [\"c040\", \"a728\"]" ;;
esac
# The two multi-marker lines are AMBIGUOUS under the shared own-id rule: they still COUNT (the
# demote-guard must not regress) but resolve to no nameable id. Under-dispatch-safe and
# recoverable, unlike a mis-attribution.
n_ids="$(printf '%s' "$ids5" | python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))')"
[[ "$n_ids" == "$ohp5" ]] \
  && ok "len(open_hard_pool_ids) == open_hard_pool ($n_ids) — list and count cannot drift" \
  || bad "len(open_hard_pool_ids)=$n_ids but open_hard_pool=$ohp5 — the list/count invariant is broken"

# E. classify-repo.sh passes the resolved list through to the unit (the dispatch site reads it).
if [[ -x "$CLASSIFY" ]]; then
  if grep -q 'open_hard_pool_ids' "$CLASSIFY"; then
    ok "classify-repo.sh passes open_hard_pool_ids through to the unit"
  else
    bad "classify-repo.sh never mentions open_hard_pool_ids — the resolved list cannot reach the dispatch site"
  fi
fi

# ---------------------------------------------------------------------------
# F. relay-loop.js HARD-child brief — hand the list, FORBID re-derivation by grep.
# ---------------------------------------------------------------------------
hard_brief="$(grep -n "You are an Opus-apex HARD-execute child" "$LOOP" || true)"
if [[ -z "$hard_brief" ]]; then
  bad "could not locate the HARD-execute child brief in relay-loop.js"
else
  if grep -q 'Pick the TOP open "- \[ \]" item tagged \[HARD — pool\] in ROADMAP.md' "$LOOP"; then
    bad "HARD brief still tells the child to grep ROADMAP.md for the RETIRED [HARD — pool] spelling (routed:2d94)"
  else
    ok "HARD brief no longer instructs a raw-grep re-derivation on the retired spelling"
  fi
  if grep -q 'hardPoolIdsFor' "$LOOP"; then
    ok "relay-loop.js has a hardPoolIdsFor helper feeding the brief the resolved list"
  else
    bad "relay-loop.js has no helper threading open_hard_pool_ids into the HARD brief"
  fi
  # The brief must carry the resolved ids AND an explicit prohibition on re-deriving them.
  if grep -q 'do NOT re-derive it by grepping' "$LOOP"; then
    ok "HARD brief explicitly FORBIDS re-deriving the pool-lane list by grep"
  else
    bad "HARD brief carries no prohibition on re-deriving the pool-lane list (mechanize-first, routed:2d94)"
  fi
  if grep -q 'open_hard_pool_ids' "$LOOP"; then
    ok "relay-loop.js discover schema carries open_hard_pool_ids"
  else
    bad "relay-loop.js never mentions open_hard_pool_ids — the resolved list is dropped before dispatch"
  fi
fi

echo "---"
echo "test_dispatch_vocab_owner_gate: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
