#!/usr/bin/env bash
# roadmap:d808
# RED SPEC for id:d808 — `gather-repo-state.sh`'s `open_hard_pool` counter must exclude
# `@container` epics, and its BLOCKED glob must not be defeated by a punctuation variant.
#
# The defect, verified in-code 2026-08-01 (gather-repo-state.sh ~:408-421):
#   while read line; do
#     [[ "$line" =~ ^[[:space:]]*-\ \[\ \]\  ]] || continue
#     [[ "$(roadmap_primary_lane "$line")" == "[HARD — pool]" ]] || continue
#     case "$line" in *'🚧'*|*'BLOCKED on'*|*'blocked on'*) continue ;; esac
#     ...
#     open_hard_pool=$((open_hard_pool + 1))
#   done
# `@container` appears NOWHERE in that filter, so a DECOMPOSED epic — whose seams are the
# real units — is counted as a dispatchable pool-lane leaf.
#
# LIVE CONSEQUENCE (run relay-20260731-221039-22914, loderite): the repo's two container
# epics (id:16b2, id:ca44) were counted, every descendant was already closed / decision-gated /
# sequenced-gated, so there was NO un-gated pool-lane leaf to pick. The repo draws `hard`
# forever, dispatching an apex Opus child that hands back at zero work every round. The
# reporting child sized out pre-start with a completely clean worktree.
#
# THE REAL DEFECT IS THE DISAGREEMENT, not the missing token: `classify-repo.sh` ALREADY
# excludes `@container` (id:0cf5 added it to `is_human` for exactly this reason). Two
# counters over one marker return two answers. Case 5 pins that parity so the fix cannot
# land on one side only.
#
# Second brittleness folded in per the item: loderite's `ca44` evades the block filter by
# writing `BLOCKED (b225…` — the glob only matches `BLOCKED on`/`blocked on`.
#
# FULLY BEHAVIOURAL and hermetic: real `git init` fixtures, RELAY_TOML/RELAY_WORKTREE_BASE
# sandboxed into a mktemp dir, no network, never reads ~/.config/relay. Idiom:
# tests/test_container_dispatch_exclusion.sh.
#
# TRIANGULATION (id:108e): six cases over three concerns (marker exclusion, block-glob
# widening, cross-collector parity), each paired with its DISCRIMINATING control — a fix
# that simply zeroes the counter, or that special-cases one literal string, fails here.
#
# RED until @container joins the open_hard_pool filter. roadmap:d808 unticked => EXPECTED-RED.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATHER="$ROOT/relay/scripts/gather-repo-state.sh"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"
for f in "$GATHER" "$CLASSIFY"; do
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

# ohp_of <roadmap-body> → gather-repo-state.sh's open_hard_pool
ohp_of() {
  local repo; repo="$(fixture_repo "$1")"
  "$GATHER" --repo fixture --path "$repo" --runid test 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))'
}

# ── Case 1 (POSITIVE CONTROL): a plain pool-lane leaf still counts ───────────────
# Without this, a fix that hard-codes open_hard_pool=0 would pass every other case.
got="$(ohp_of '- [ ] [HARD] A genuine un-gated pool leaf <!-- id:0001 -->')"
[[ "$got" == "1" ]] && ok "control: pool-lane leaf without @container counts (open_hard_pool=1)" \
                    || bad "control: pool-lane leaf should count 1, got '$got'"

# ── Case 2: @container must NOT count ───────────────────────────────────────────
got="$(ohp_of '- [ ] [HARD] DECOMPOSED epic — its seams are the units @container <!-- id:0002 -->')"
[[ "$got" == "0" ]] && ok "@container pool-lane epic is excluded (open_hard_pool=0)" \
                    || bad "@container pool-lane epic should be excluded (0), got '$got'"

# ── Case 3: a @container epic must not SUPPRESS an unrelated real leaf ──────────
# The under-dispatch direction is safe but not free: excluding the marker must be
# per-line, not a whole-file bail-out.
body='- [ ] [HARD] DECOMPOSED epic @container <!-- id:0003 -->
- [ ] [HARD] A real un-gated seam sibling <!-- id:0004 -->'
got="$(ohp_of "$body")"
[[ "$got" == "1" ]] && ok "@container excludes per-LINE: sibling leaf still counts (1)" \
                    || bad "@container must exclude per-line; expected 1 (the sibling), got '$got'"

# ── Case 4: the BLOCKED glob must not be defeated by punctuation ─────────────────
# Item d808's second brittleness: loderite's ca44 wrote `BLOCKED (b225…` and slipped past
# a glob that only knows `BLOCKED on`. Three punctuation variants + a case check, so a fix
# that appends one more literal to the case list does not satisfy it.
for variant in 'BLOCKED (b225 must land first)' 'BLOCKED: b225 must land first' 'BLOCKED — b225 must land first'; do
  got="$(ohp_of "- [ ] [HARD] Epic seam $variant <!-- id:0005 -->")"
  [[ "$got" == "0" ]] && ok "block glob: '$variant' excludes the item (0)" \
                      || bad "block glob: '$variant' should exclude the item (0), got '$got'"
done
got="$(ohp_of '- [ ] [HARD] Epic seam blocked: b225 must land first <!-- id:0006 -->')"
[[ "$got" == "0" ]] && ok "block glob: lower-case 'blocked:' excludes too (case parity with BLOCKED on/blocked on)" \
                    || bad "block glob: lower-case 'blocked:' should exclude (0), got '$got'"

# ── Case 5 (PARITY, behavioural on both sides): the two collectors must agree ────
# classify-repo.sh already excludes @container (id:0cf5). gather-repo-state.sh does not.
# That disagreement IS the defect the item names, so assert it directly rather than
# asserting only the gather side.
repo="$(fixture_repo '- [ ] [HARD] DECOMPOSED epic @container <!-- id:0007 -->')"
aro="$("$CLASSIFY" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
ohp="$("$GATHER" --repo fixture --path "$repo" --runid test 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))')"
if [[ "$aro" == "0" && "$ohp" == "0" ]]; then
  ok "parity: classify-repo and gather-repo-state both exclude the same @container line (0/0)"
else
  bad "parity: the two collectors disagree on one @container line — classify aro='$aro', gather open_hard_pool='$ohp' (both must be 0)"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
