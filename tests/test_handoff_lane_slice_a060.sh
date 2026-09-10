#!/usr/bin/env bash
# (no roadmap token -- DEFECT-FIX regression test for TODO id:a060, always counts.)
#
# THE DEFECT: the `handoff` lane could never be sliced, so a big-ledger repo could never
# RECEIVE a handoff -- the one verdict that would have shrunk its ledgers. `relay-loop.js`'s
# sliceLedgerForUnit had exactly three slice shapes: `--id` (execute, from dispatchItemFor),
# `--since-last-review` (review, id:dd59) and `--ids` (hard, id:f957). A handoff names NO
# dispatch item BY CONSTRUCTION -- its job is C2 promotion, so the ROADMAP item does not exist
# yet -- so `!item && !useReviewSet && !useHardSet` was always true, the unit fell through to
# the fail-open branch and was sized on the WHOLE ledgers. MEASURED on loderite 2026-09-10:
# 417,734 tok of ledger fields plus ~66,351 tok of brief overhead against a 300,000 Opus
# budget, a byte-identical refusal every round, 0 integrates across two separate runs.
#
# THE FIX, mirroring id:f957 one lane over: classify-repo.sh emits `unpromoted_ids` -- the
# open TODO.md ids with no ROADMAP twin, dispositions `promote` + `surface`, straight from the
# unpromoted-scan.sh TSV it already runs -- and relay-loop.js slices a handoff on that set via
# `--ids`. That set is precisely what handoff C2 works from ("`promote`-disposition items get
# sized into ROADMAP here; `surface` ones get lane-triaged below", handoff.md C2).
#
# WHAT THIS PINS, in the order the cases run:
#   (a) the id set is exactly promote+surface, in TODO.md file order;
#   (b) `laned` is excluded (verdict-neutral -- classify-verdict folds neither) and
#       `untracked` is excluded STRUCTURALLY (unpromoted-scan emits `----`, not an id);
#   (c) ledger-slice.sh --ids over that set writes a slice carrying those items and not the
#       excluded ones;
#   (d) relay-loop.js dispatches the handoff slice as `--ids` (never `--id`, which would
#       convert the C2 SURVEY into named-item dispatch), and its fail-open branch still fires
#       when the set is empty;
#   (e) fail-open: a repo with no promote/surface rows emits an EMPTY list, which leaves the
#       no-slice branch firing and the handoff dispatching unsliced exactly as before.
#
# fails-against: the pre-a060 tree, where classify-repo.sh emitted no `unpromoted_ids` field
# and relay-loop.js's slice bail had no handoff branch.
# fails-against-mutation: sed -i 's/^    "unpromoted_ids": unpromoted_ids,$//' relay/scripts/classify-repo.sh
# fails-against-assertion: (a) unpromoted_ids must be exactly the promote+surface ids in TODO order
# fails-against-mutation: sed -i 's/!useHardSet && !useHandoffSet) {/!useHardSet) {/' relay/scripts/relay-loop.js
# fails-against-assertion: (d3) the slice bail must also require !useHandoffSet
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
LS="$ROOT/relay/scripts/ledger-slice.sh"
JS="$ROOT/relay/scripts/relay-loop.js"
for f in "$CR" "$LS"; do [[ -x "$f" ]] || { echo "FAIL: missing helper $f"; exit 1; }; done
[[ -f "$JS" ]] || { echo "FAIL: missing $JS"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Hermetic: every path the helpers write or read is redirected into the scratch. RELAY_CORE_BIN
# set-but-not-executable is classify-repo.sh's documented shadow kill switch, so a real
# relay-core install can never leak a parity-log write into this test.
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_CORE_BIN="$tmp/nonexistent-relay-core"
export RELAY_DECISION_QUEUE="$tmp/decision-queue.jsonl"; : > "$RELAY_DECISION_QUEUE"
export UNPROMOTED_SCAN_LOG="$tmp/unpromoted-scan.log"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# --- fixture: an un-promoted TODO backlog with one row of every disposition ----------------
R="$tmp/handoffrepo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t
# ROADMAP with nothing open and NO twin for any TODO id: exactly the shape that makes
# unpromoted-scan report the whole TODO backlog as un-promoted.
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap

## Items

- [x] [ROUTINE] something already shipped <!-- id:bb01 -->
EOF
# One row per disposition, in a deliberate order so "file order" is testable:
#   aa01 promote ([ROUTINE]) / aa02 laned ([INPUT - decision]) / aa03 surface (untagged)
#   aa04 promote (bare [HARD], the new pool spelling) / no-id row -> untracked
cat > "$R/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [ROUTINE] a directly promotable executor item <!-- id:aa01 -->
- [ ] [INPUT - decision] a question only the owner can answer <!-- id:aa02 -->
- [ ] an untagged backlog line whose lane nobody has decided yet <!-- id:aa03 -->
- [ ] [HARD] a pool-lane item in the new vocabulary <!-- id:aa04 -->
- [ ] a real checkbox item that carries no id token at all
EOF
git -C "$R" add -A
git -C "$R" commit -qm init

# Fixture sanity, stated as its own check so a later assertion can never be red merely
# because unpromoted-scan disagreed with the comment above about what this fixture is.
scan="$("$ROOT/relay/scripts/unpromoted-scan.sh" "$R" 2>/dev/null)" || fail "unpromoted-scan.sh failed on the fixture"
disp() { printf '%s\n' "$scan" | awk -F'\t' -v id="$1" '$2==id {print $3}'; }
[[ "$(disp aa01)" == "promote" ]] || fail "fixture sanity: aa01 must disposition promote, got '$(disp aa01)'"
[[ "$(disp aa02)" == "laned" ]]   || fail "fixture sanity: aa02 must disposition laned, got '$(disp aa02)'"
[[ "$(disp aa03)" == "surface" ]] || fail "fixture sanity: aa03 must disposition surface, got '$(disp aa03)'"
[[ "$(disp aa04)" == "promote" ]] || fail "fixture sanity: aa04 must disposition promote, got '$(disp aa04)'"
[[ "$(disp ----)" == "untracked" ]] || fail "fixture sanity: the id-less row must disposition untracked, got '$(disp ----)'"
pass "fixture carries one row of every unpromoted-scan disposition"

# --- (a) the emitted id set ---------------------------------------------------------------
unit="$("$CR" --emit unit --repo handoffrepo --path "$R" 2>"$tmp/cr.err")" \
  || fail "classify-repo.sh --emit unit failed: $(cat "$tmp/cr.err")"
ids="$(printf '%s' "$unit" | python3 -c '
import sys, json
d = json.load(sys.stdin)
v = d.get("unpromoted_ids", "<<MISSING>>")
print(",".join(v) if isinstance(v, list) else v)
')" || fail "classify-repo.sh --emit unit emitted non-JSON"
[[ "$ids" == "aa01,aa03,aa04" ]] \
  || fail "(a) unpromoted_ids must be exactly the promote+surface ids in TODO order (expected aa01,aa03,aa04) -- got '$ids'"
pass "(a) unpromoted_ids = aa01,aa03,aa04"

# --- (b) the two exclusions, each named so a regression says WHICH one broke ---------------
[[ ",$ids," != *",aa02,"* ]] \
  || fail "(b1) a laned row must NOT be sliced -- it is verdict-neutral and a handoff neither promotes nor triages it"
[[ "$ids" != *"----"* && "$ids" != *",,"* ]] \
  || fail "(b2) an untracked row carries no id, so it must never reach the --ids CSV (got '$ids')"
pass "(b) laned and untracked rows are excluded"

# --- (c) the slice built from that set ----------------------------------------------------
slice_out="$("$LS" --repo handoffrepo --path "$R" --ids "$ids" --out "$tmp/slice.md" 2>"$tmp/ls.err")" \
  || fail "(c1) ledger-slice.sh --ids failed on a TODO-only handoff set: $(cat "$tmp/ls.err")"
[[ -f "$tmp/slice.md" ]] || fail "(c2) ledger-slice.sh wrote no slice file"
printf '%s\n' "$slice_out" | grep -qE '^slice-bytes: [0-9]+$' \
  || fail "(c3) the slice must report slice-bytes so the prompt-size gate can size the unit on it"
for want in aa01 aa03 aa04; do
  grep -q "$want" "$tmp/slice.md" || fail "(c4) the slice must carry the un-promoted item $want"
done
if grep -q "aa02" "$tmp/slice.md"; then
  fail "(c5) the slice must not carry the excluded laned item aa02"
fi
# The REPORTED byte count must be the written file's real size. Deliberately NOT "the slice is
# smaller than the ledgers": at fixture scale the slice's own repo-state header outweighs a
# five-line TODO, so that comparison would pin nothing here. The size WIN is a property of a
# real big-ledger repo -- measured by hand on loderite (14 ids, 6,716 B against 1,670,936 B of
# ledgers) -- while what a fixture CAN pin is that the number is measured rather than guessed,
# which is the property the id:35b7 prompt-size gate keys on.
reported="$(printf '%s\n' "$slice_out" | sed -n 's/^slice-bytes: \([0-9]\+\)$/\1/p' | tail -1)"
actual="$(wc -c < "$tmp/slice.md")"
[[ "$reported" == "$actual" ]] \
  || fail "(c6) slice-bytes must be MEASURED on the written file (reported $reported, actual $actual)"
pass "(c) the handoff slice is scoped to the un-promoted set and honestly measured ($actual B)"

# --- (d) the relay-loop.js wiring ---------------------------------------------------------
# Source-text assertions only: relay-loop.js runs inside the Workflow sandbox and no test here
# executes it (see tests/test_relay_loop_discovery_exec.sh for the same convention).
grep -q "unpromoted_ids: { type: 'array', items: { type: 'string' } }" "$JS" \
  || fail "(d1) DISCOVER_SCHEMA must declare unpromoted_ids so the field survives the discovery hop"
grep -q "unpromotedIdsFor(unit)" "$JS" \
  || fail "(d2) sliceLedgerForUnit must read the un-promoted set through unpromotedIdsFor"
grep -q '!useHardSet && !useHandoffSet) {' "$JS" \
  || fail "(d3) the slice bail must also require !useHandoffSet, or a handoff still falls through to the unsliced brief"
grep -q "useHandoffSet ? \`--ids \${handoffIds.join(',')}\`" "$JS" \
  || fail "(d4) a handoff must slice with --ids (a single --id would convert the C2 survey into named-item dispatch)"
grep -q "unit.verdict === 'handoff' ? ' and no unpromoted_ids" "$JS" \
  || fail "(d5) the fail-open branch must log WHY a handoff produced no slice (the id:f499 rule)"
pass "(d) relay-loop.js slices a handoff on --ids and logs its fail-open branch"

# --- (e) fail-open on an empty set --------------------------------------------------------
# A repo whose whole un-promoted backlog is `laned` yields NO promote/surface row. The field
# must be an empty list, not absent-and-guessed and not a malformed CSV: relay-loop's no-item
# branch then fires and the handoff dispatches unsliced, exactly as it did before a060.
R2="$tmp/lanedonly"; mkdir -p "$R2"
git -C "$R2" init -q
git -C "$R2" config user.email t@e
git -C "$R2" config user.name t
printf '# Roadmap\n\n## Items\n\n- [x] [ROUTINE] shipped <!-- id:cc01 -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] [INPUT - meeting] needs a design session <!-- id:dd01 -->\n' > "$R2/TODO.md"
git -C "$R2" add -A
git -C "$R2" commit -qm init
unit2="$("$CR" --emit unit --repo lanedonly --path "$R2" 2>"$tmp/cr2.err")" \
  || fail "classify-repo.sh --emit unit failed on the laned-only repo: $(cat "$tmp/cr2.err")"
kind="$(printf '%s' "$unit2" | python3 -c '
import sys, json
v = json.load(sys.stdin).get("unpromoted_ids", "<<MISSING>>")
print("empty-list" if isinstance(v, list) and not v else repr(v))
')" || fail "classify-repo.sh --emit unit emitted non-JSON for the laned-only repo"
[[ "$kind" == "empty-list" ]] \
  || fail "(e) a repo with no promote/surface row must emit unpromoted_ids as an EMPTY LIST (fail-open) -- got $kind"
pass "(e) an all-laned backlog fails open to an empty set"

echo "PASS test_handoff_lane_slice_a060"
