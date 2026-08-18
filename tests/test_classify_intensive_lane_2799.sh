#!/usr/bin/env bash
# Defect-fix test for id:2799 (TODO-only, no ROADMAP entry — per CLAUDE.md Testing this file
# deliberately OMITS the `# roadmap:XXXX` header, so its failures always count, never
# EXPECTED-RED).
#
# Defect: a repo-level [INTENSIVE] flag stamped the WHOLE dispatch unit, so an unrelated
# [HARD] [INTENSIVE] item deferred every unrelated [ROUTINE] item behind --intensive.
# Observed live in relay run relay-20260818-152657-28729: dotclaude-skills classified
# verdict:"execute", actionable_routine_open:6 (b8ae/4438/cc7e/f69b/5bef/dd7d) AND
# intensive:"disk-io" — the only open [INTENSIVE] item was id:3c9d, a [HARD] item, NOT one
# of the six routine ones. The pool partitioned the whole unit into intensiveDeferred and
# worked none of the six.
#
# Fix: gather-repo-state.sh now emits top_intensive_routine / top_intensive_hard (the
# resource of the top open [INTENSIVE] item PER LANE, "" when that lane has none), and
# classify-verdict.sh selects `intensive` from the field matching the verdict's OWN lane
# (execute <- top_intensive_routine, hard <- top_intensive_hard) instead of the lane-blind
# top_intensive. relay-loop.js's id:ad74 patch-backstop was updated the same way.
#
# Hermetic: builds fixture repos under mktemp; no network, no ~/.claude touched.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
CLASSIFY_REPO="$SRC_DIR/relay/scripts/classify-repo.sh"
[[ -x "$GATHER" ]]        || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }
[[ -x "$CLASSIFY_REPO" ]] || { echo "FAIL: classify-repo.sh missing/not executable"; exit 1; }

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

mkrepo() {  # mkrepo <name> <roadmap-body-file>; prints the repo path
  local name="$1"; local body="$2"; local r="$TMP/$name"
  mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@e; git -C "$r" config user.name t
  printf '# ROADMAP\n\n## Now\n%s\n' "$(cat "$body")" > "$r/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$r/TODO.md"
  git -C "$r" add -A; git -C "$r" commit -qm init
  # Mark HEAD already audited (a checkpoint tag right at init) so substantive_unaudited is
  # false and the `review` verdict (which otherwise outranks `hard` in the D3 cascade) never
  # fires ahead of the verdict this test is actually exercising — mirrors test_classify_repo.sh's
  # ckpt_head helper.
  git -C "$r" tag -a "relay-ckpt-20260101-0000" -m ckpt
  echo "$r"
}
classify() {  # classify <name> <path>; prints classify-repo.sh's default (verdict.json-shaped) output
  RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" \
    "$CLASSIFY_REPO" --repo "$1" --path "$2"
}

# === (1) THE REGRESSION: open [ROUTINE] items + an unrelated [HARD] [INTENSIVE] item ======
# ⇒ verdict execute, intensive EMPTY (the unrelated HARD-lane resource must not stamp the
# routine dispatch — this is the exact dotclaude-skills relay-20260818-152657-28729 shape).
b1="$TMP/b1"; printf '%s\n' \
  '- [ ] [ROUTINE] fix widget A <!-- id:1a1a -->' \
  '- [ ] [ROUTINE] fix widget B <!-- id:1b1b -->' \
  '- [ ] [HARD] a big unrelated audit [INTENSIVE — disk-io] <!-- id:1c1c -->' > "$b1"
r1="$(mkrepo repo1 "$b1")"
out1="$(classify repo1 "$r1")"
v1="$(field verdict <<<"$out1")"
i1="$(field intensive <<<"$out1")"
[[ "$v1" == "execute" ]] \
  && ok "(1) unrelated [HARD][INTENSIVE] alongside open [ROUTINE] work -> verdict=execute" \
  || bad "(1) verdict='$v1', expected 'execute'"
[[ "$i1" == "None" || -z "$i1" ]] \
  && ok "(1) THE REGRESSION FIX: intensive is empty — the unrelated HARD-lane disk-io item does not stamp the routine dispatch" \
  || bad "(1) REGRESSION: intensive='$i1' but the only [INTENSIVE] item is [HARD]-lane, unrelated to the open [ROUTINE] items"

# === (2) the intensive item IS [ROUTINE] itself -> intensive STILL stamped (no over-suppress) ==
b2="$TMP/b2"; printf '%s\n' \
  '- [ ] [ROUTINE] fix widget A <!-- id:2a2a -->' \
  '- [ ] [ROUTINE] run the gpu sweep [INTENSIVE — gpu-bench] <!-- id:2b2b -->' > "$b2"
r2="$(mkrepo repo2 "$b2")"
out2="$(classify repo2 "$r2")"
v2="$(field verdict <<<"$out2")"
i2="$(field intensive <<<"$out2")"
[[ "$v2" == "execute" ]] \
  && ok "(2) [ROUTINE]-lane [INTENSIVE] item -> verdict=execute" \
  || bad "(2) verdict='$v2', expected 'execute'"
[[ "$i2" == "gpu-bench" ]] \
  && ok "(2) intensive still stamped ('gpu-bench') when the item genuinely IS in the execute verdict's own lane" \
  || bad "(2) intensive='$i2', expected 'gpu-bench' (must not over-suppress a genuinely matching lane)"

# === (3) only [HARD] work, incl. the intensive one -> verdict=hard, intensive stamped =======
b3="$TMP/b3"; printf '%s\n' \
  '- [ ] [HARD] audit the thing [INTENSIVE — disk-io] <!-- id:3a3a -->' > "$b3"
r3="$(mkrepo repo3 "$b3")"
out3="$(classify repo3 "$r3")"
v3="$(field verdict <<<"$out3")"
i3="$(field intensive <<<"$out3")"
[[ "$v3" == "hard" ]] \
  && ok "(3) only [HARD] work, incl. the intensive item -> verdict=hard" \
  || bad "(3) verdict='$v3', expected 'hard'"
[[ "$i3" == "disk-io" ]] \
  && ok "(3) intensive stamped 'disk-io' when the top intensive item IS the hard verdict's own lane" \
  || bad "(3) intensive='$i3', expected 'disk-io'"

# === (4) human-gated [INTENSIVE] still yields "" (id:a707/id:7517 guard, both vocabularies) ==
b4="$TMP/b4"; printf '%s\n' \
  '- [ ] [ROUTINE] fix widget A <!-- id:4a4a -->' \
  '- [ ] old-vocab human item [HARD — hands] [INTENSIVE — local-llm] <!-- id:4b4b -->' \
  '- [ ] new-vocab human item [INPUT — access] [INTENSIVE — local-llm] <!-- id:4c4c -->' > "$b4"
r4="$(mkrepo repo4 "$b4")"
out4="$(classify repo4 "$r4")"
v4="$(field verdict <<<"$out4")"
i4="$(field intensive <<<"$out4")"
[[ "$v4" == "execute" ]] \
  && ok "(4) verdict=execute from the open [ROUTINE] item (human-gated items never contribute actionable work)" \
  || bad "(4) verdict='$v4', expected 'execute'"
[[ "$i4" == "None" || -z "$i4" ]] \
  && ok "(4) human-gated [INTENSIVE] items (both old- and new-vocab spellings) never stamp intensive" \
  || bad "(4) intensive='$i4' — a human-gated [INTENSIVE] item leaked into the dispatch flag (id:a707/id:7517 guard)"

echo "---"
echo "test_classify_intensive_lane_2799: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
