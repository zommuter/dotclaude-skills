#!/usr/bin/env bash
# roadmap:a707 — gather-repo-state.sh must NOT advertise a human-gated [INTENSIVE] item as
# auto-dispatchable work. [INTENSIVE] is an ORTHOGONAL resource axis (id:78ff): an item can be
# [ROUTINE]/[HARD — pool] + resource-heavy (auto-dispatch serially under --afk) OR human-gated
# ([HARD — hands]/[HARD — meeting]/[HARD — decision gate]/@manual) + resource-heavy (human-only).
# The id:ad74 INTENSIVE-EMIT backstop reads gather's top_intensive; if that field is set for a
# human-gated item, the pool force-emits an undoable unit (observed 2026-06-23: a zomni
# [HARD — hands] [INTENSIVE — local-llm] GGUF-cleanup item was dispatched and could not complete).
# Fix (id:a707): top_intensive = resource of the top open [INTENSIVE] item that is NOT human-gated;
# "" when the only open [INTENSIVE] items are human-gated. Hermetic: builds repos under mktemp.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

mkrepo() {  # mkrepo <name> <roadmap-body-file>; returns the path
  local name="$1"; local body="$2"; local r="$TMP/$name"
  mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@e; git -C "$r" config user.name t
  printf '# ROADMAP\n\n## Now\n%s\n' "$(cat "$body")" > "$r/ROADMAP.md"
  git -C "$r" add -A; git -C "$r" commit -qm init
  echo "$r"
}
gather() { RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" "$GATHER" --repo "$1" --path "$2" --runid test; }

# (1) human-gated [INTENSIVE] only → top_intensive must be "" (NOT auto-dispatchable).
b1="$TMP/b1"; printf '%s\n' \
  '- [ ] Unused GGUF model cleanup [HARD — hands] [INTENSIVE — local-llm] <!-- id:aaaa -->' \
  '- [ ] gemma reasoning decisions [HARD — decision gate] [INTENSIVE — local-llm] <!-- id:bbbb -->' > "$b1"
r1="$(mkrepo r1 "$b1")"
ti="$(field top_intensive <<<"$(gather r1 "$r1")")"
[[ "$ti" == "None" || -z "$ti" ]] \
  && ok "human-gated-only [INTENSIVE] → top_intensive empty (not force-emitted, id:a707)" \
  || bad "top_intensive='$ti' for a human-gated [HARD — hands]/[decision gate] [INTENSIVE] item — would force an undoable dispatch"

# (2) an executor-actionable [INTENSIVE] item present → top_intensive set to its resource.
b2="$TMP/b2"; printf '%s\n' \
  '- [ ] Unused GGUF model cleanup [HARD — hands] [INTENSIVE — local-llm] <!-- id:aaaa -->' \
  '- [ ] Benchmark sweep [ROUTINE] [INTENSIVE — gpu-bench] <!-- id:cccc -->' > "$b2"
r2="$(mkrepo r2 "$b2")"
ti2="$(field top_intensive <<<"$(gather r2 "$r2")")"
[[ "$ti2" == "gpu-bench" ]] \
  && ok "executor-actionable [ROUTINE] [INTENSIVE] → top_intensive='gpu-bench' (skips the human-gated one)" \
  || bad "top_intensive='$ti2', expected 'gpu-bench' (the actionable intensive item)"

# (3) @manual [INTENSIVE] is also human-gated → not advertised.
b3="$TMP/b3"; printf '%s\n' \
  '- [ ] Eyeball model outputs @manual [INTENSIVE — local-llm] <!-- id:dddd -->' > "$b3"
r3="$(mkrepo r3 "$b3")"
ti3="$(field top_intensive <<<"$(gather r3 "$r3")")"
[[ "$ti3" == "None" || -z "$ti3" ]] \
  && ok "@manual [INTENSIVE] → top_intensive empty (human-only)" \
  || bad "top_intensive='$ti3' for an @manual [INTENSIVE] item"

echo "---"
echo "test_intensive_human_gate: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
