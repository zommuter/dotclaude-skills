#!/usr/bin/env bash
# Defect-fix test (id:fbbf — no ROADMAP item; a relay-waste bug fix): a commit whose ONLY
# changed content is the `<!-- relay-executor contract vN -->` pointer line is a pure META
# refresh and must NOT set substantive_unaudited=true — otherwise every contract version bump
# re-classifies every managed repo as "needs review" and burns a strong review turn per repo
# for zero real work (observed zkm-pdf, 2026-07-15). Mirrors the existing uv.lock-only
# exemption (id:bae5). Hermetic: builds a throwaway git repo under mktemp.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

# Build a repo with a checkpoint tag; return its path. $1 = subdir name.
mkrepo() {
  local r="$TMP/$1"
  git init -q "$r"
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  printf '# CLAUDE.md\n\n## Relay contract <!-- relay-executor contract v7 -->\n' > "$r/CLAUDE.md"
  printf 'seed\n' > "$r/code.sh"
  git -C "$r" add -A; git -C "$r" commit -qm seed
  # annotated ckpt tag so audit_ref resolves to it (latest fable-/relay-ckpt-*)
  git -C "$r" tag -a 'relay-ckpt-20260715-0001' -m $'reconcile checkpoint\nreviewer (opus)'
  echo "$r"
}

gather() { RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" "$GATHER" --repo "$1" --path "$2" --runid test; }

# (1) pointer-ONLY commit after the ckpt → NOT substantive.
r="$(mkrepo pointeronly)"
sed -i 's/contract v7/contract v8/' "$r/CLAUDE.md"
git -C "$r" commit -qam "docs: bump relay-executor contract pointer to v8"
j="$(gather pointeronly "$r")"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "pointer-only meta refresh → substantive_unaudited=false (no wasted review)" \
  || bad "pointer-only commit wrongly counted substantive: $(field substantive_unaudited <<<"$j")"

# (2) a REAL code commit after the ckpt → substantive (control: exemption isn't over-broad).
r="$(mkrepo realwork)"
printf 'real change\n' >> "$r/code.sh"
git -C "$r" commit -qam "feat: real work"
j="$(gather realwork "$r")"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "real code commit → substantive_unaudited=true (control)" \
  || bad "real commit wrongly exempted: $(field substantive_unaudited <<<"$j")"

# (3) pointer bump AND a real change in the SAME commit → substantive (mixed is not exempt).
r="$(mkrepo mixed)"
sed -i 's/contract v7/contract v8/' "$r/CLAUDE.md"
printf 'also real\n' >> "$r/code.sh"
git -C "$r" commit -qam "chore: bump pointer + tweak code"
j="$(gather mixed "$r")"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "pointer+code mixed commit → substantive_unaudited=true (control)" \
  || bad "mixed commit wrongly exempted: $(field substantive_unaudited <<<"$j")"

echo "---- $pass passed, $fail failed ----"
[[ "$fail" -eq 0 ]]
