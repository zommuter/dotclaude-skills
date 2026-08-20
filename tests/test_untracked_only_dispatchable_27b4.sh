#!/usr/bin/env bash
# roadmap:27b4
#
# UNTRACKED-only dirt must NOT block relay dispatch or integration; TRACKED dirt still must.
#
# WHY (measured, not hypothetical): `gather-repo-state.sh` set `dirty=true` from a bare
# `git status --porcelain`, which counts untracked ("??") entries. So two stray untracked
# campaign assets made `classify-repo.sh` return verdict=blocked for yinyang-puzzle, and the
# pool never dispatched it — no checkpoint from relay-ckpt-20260731-1801 (2026-07-31) until
# the files were committed on 2026-08-20. Nineteen days, silently, over 1 MB of PNG/SVG that
# no relay child would ever have touched. Found only because a human asked why repos get
# skipped; nothing surfaced it.
#
# WHY IT IS SAFE: a relay child works in its own `git worktree add` clone and never touches
# the main checkout's untracked files, and `git merge` REFUSES any merge that would overwrite
# an untracked file — so integrate safety is enforced by git itself, not by this verdict.
#
# WHAT THIS DOES NOT CHANGE (id:aa93 stands): tracked dirt still blocks, and nothing here
# authorises cleaning a tree. Untracked files are exactly what `git clean` destroys, which is
# why the gates still SHOW them and still never remove them. `RELAY_STRICT_UNTRACKED=1`
# restores the old strict behaviour in clean-tree-gate.sh.
#
# Precedent: `dirty_lock_only` (id:bae5) already established that some dirt is dispatchable.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATHER="$ROOT/relay/scripts/gather-repo-state.sh"
GATE="$ROOT/relay/scripts/clean-tree-gate.sh"

fails=0
ok()   { printf '  ok   — %s\n' "$1"; }
bad()  { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e.st
  git -C "$d" config user.name  Test
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" -c commit.gpgsign=false commit -q -m seed
}

# ---------------------------------------------------------------- untracked only
repo="$tmp/untracked"; mkrepo "$repo"
printf 'binary-ish\n' > "$repo/stray-asset.png"

out="$("$GATHER" --repo untracked --path "$repo" 2>/dev/null || true)"
dirty=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("dirty"))' 2>/dev/null || echo ERR)
uonly=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("dirty_untracked_only"))' 2>/dev/null || echo ERR)

[ "$dirty" = "True" ] && ok "untracked file still reports dirty=true (visibility preserved)" \
                      || bad "expected dirty=true for an untracked file, got '$dirty'"
[ "$uonly" = "True" ] && ok "dirty_untracked_only=true for an untracked-only tree" \
                      || bad "expected dirty_untracked_only=true, got '$uonly'"

if "$GATE" "$repo" >/dev/null 2>&1; then
  ok "clean-tree-gate ACCEPTS an untracked-only tree (integrate not blocked)"
else
  bad "clean-tree-gate rejected an untracked-only tree — dispatch and integrate would disagree"
fi

if RELAY_STRICT_UNTRACKED=1 "$GATE" "$repo" >/dev/null 2>&1; then
  bad "RELAY_STRICT_UNTRACKED=1 should restore strict behaviour but the gate passed"
else
  ok "RELAY_STRICT_UNTRACKED=1 restores the old strict rejection (escape hatch works)"
fi

# ------------------------------------------------------------------ tracked dirt
repo2="$tmp/tracked"; mkrepo "$repo2"
printf 'modified\n' >> "$repo2/README.md"

out2="$("$GATHER" --repo tracked --path "$repo2" 2>/dev/null || true)"
uonly2=$(printf '%s' "$out2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("dirty_untracked_only"))' 2>/dev/null || echo ERR)
[ "$uonly2" = "False" ] && ok "TRACKED modification defeats dirty_untracked_only" \
                        || bad "tracked dirt must NOT be untracked-only, got '$uonly2'"

if "$GATE" "$repo2" >/dev/null 2>&1; then
  bad "clean-tree-gate ACCEPTED a tracked-dirty tree — the id:aa93 guard is broken"
else
  ok "clean-tree-gate still REJECTS tracked dirt (id:aa93 intact)"
fi

# --------------------------------------------------------------------- both kinds
repo3="$tmp/both"; mkrepo "$repo3"
printf 'modified\n' >> "$repo3/README.md"
printf 'x\n' > "$repo3/stray.png"

out3="$("$GATHER" --repo both --path "$repo3" 2>/dev/null || true)"
uonly3=$(printf '%s' "$out3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("dirty_untracked_only"))' 2>/dev/null || echo ERR)
[ "$uonly3" = "False" ] && ok "mixed tracked+untracked is NOT untracked-only (conservative)" \
                        || bad "mixed dirt must not be untracked-only, got '$uonly3'"

if "$GATE" "$repo3" >/dev/null 2>&1; then
  bad "clean-tree-gate ACCEPTED a mixed tree — tracked dirt must still block"
else
  ok "clean-tree-gate REJECTS a mixed tree on its tracked half"
fi

if [ "$fails" -ne 0 ]; then
  printf 'test_untracked_only_dispatchable_27b4: %d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'test_untracked_only_dispatchable_27b4: all checks passed\n'
