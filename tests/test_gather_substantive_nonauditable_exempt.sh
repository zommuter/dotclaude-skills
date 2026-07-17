#!/usr/bin/env bash
# Defect-fix test (id:2630 — a relay-waste bug fix; broadens the id:bae5 uv.lock-only and
# id:fbbf contract-pointer exemptions). A "review" verdict exists to catch gamed test-integrity,
# which requires SOURCE/TEST changes. A commit that touches ONLY non-auditable paths — lockfiles,
# the ledgers (ROADMAP/TODO/REVIEW_ME/RELAY_LOG/CHANGELOG), docs/** & the root doc set — or that
# merely bumps a manifest `version` must NOT set substantive_unaudited=true, else every such churn
# re-classifies the repo as "needs review" and burns a strong (Opus) review turn for zero audit
# work. Observed 2026-07-17: zkm v0.21.0 bump, toesnail TODO +1, chidiai docs/cases, and
# mathematical-writing/zkWhale ledger+meeting-note windows each triggered a no-op Opus review.
# FAIL-OPEN: any path NOT in the exempt set is auditable (controls #5/#6). Hermetic: mktemp repo.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

# Build a repo with a checkpoint tag; seeds a source file + a manifest so bumps have a base.
mkrepo() {
  local r="$TMP/$1"
  git init -q "$r"
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  mkdir -p "$r/src" "$r/docs/cases"
  printf 'export const x = 1;\n' > "$r/src/foo.ts"
  printf '[project]\nname = "z"\nversion = "0.18.0"\n' > "$r/pyproject.toml"
  printf 'lock = 0.18.0\n' > "$r/uv.lock"
  printf '# TODO\n\n- [ ] seed <!-- id:0001 -->\n' > "$r/TODO.md"
  printf '# README\n' > "$r/README.md"
  git -C "$r" add -A; git -C "$r" commit -qm seed
  git -C "$r" tag -a 'relay-ckpt-20260715-0001' -m $'reconcile checkpoint\nreviewer (opus)'
  echo "$r"
}
gather() { RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" "$GATHER" --repo "$1" --path "$2" --runid test; }
sub() { field substantive_unaudited <<<"$1"; }

# (1) ledger-only commit (TODO.md) → NOT substantive.
r="$(mkrepo ledger)"
printf -- '- [ ] more <!-- id:0002 -->\n' >> "$r/TODO.md"
git -C "$r" commit -qam "docs(todo): file an item"
j="$(gather ledger "$r")"
[[ "$(sub "$j")" == "False" ]] && ok "ledger-only (TODO) → not substantive" \
  || bad "ledger-only wrongly substantive: $(sub "$j")"

# (2) manifest version bump (pyproject version line + uv.lock) → NOT substantive (the zkm case).
r="$(mkrepo bump)"
sed -i 's/0.18.0/0.21.0/' "$r/pyproject.toml" "$r/uv.lock"
git -C "$r" commit -qam "chore(release): v0.21.0"
j="$(gather bump "$r")"
[[ "$(sub "$j")" == "False" ]] && ok "version bump (pyproject+uv.lock) → not substantive (zkm case)" \
  || bad "version bump wrongly substantive: $(sub "$j")"

# (3) docs + README + version bump together → NOT substantive (the chidiai case: big docs body
#     must not defeat its own exemption — content check is scoped to auditable files only).
r="$(mkrepo docsheavy)"
for i in 1 2 3; do printf 'a case file with lots of prose line %s\n%s\n' "$i" "$(yes x | head -40 | tr '\n' ' ')" > "$r/docs/cases/case-$i.md"; done
printf 'more readme\n' >> "$r/README.md"
sed -i 's/0.18.0/0.21.0/' "$r/pyproject.toml" "$r/uv.lock"
git -C "$r" commit -qam "cases + readme + bump"
j="$(gather docsheavy "$r")"
[[ "$(sub "$j")" == "False" ]] && ok "docs/cases + README + version bump → not substantive (chidiai case)" \
  || bad "docs-heavy+bump wrongly substantive: $(sub "$j")"

# (4) meeting-note only (docs/**) → NOT substantive.
r="$(mkrepo meeting)"
mkdir -p "$r/docs/meeting-notes"; printf '# meeting\n\nD1 ...\n' > "$r/docs/meeting-notes/2026-07-17-x.md"
git -C "$r" add -A; git -C "$r" commit -qm "meeting: a decision"
j="$(gather meeting "$r")"
[[ "$(sub "$j")" == "False" ]] && ok "meeting-note only (docs/**) → not substantive" \
  || bad "meeting-note wrongly substantive: $(sub "$j")"

# (5) CONTROL: a real source commit → substantive (exemption is not over-broad).
r="$(mkrepo realsrc)"
printf 'export const y = 2;\n' >> "$r/src/foo.ts"
git -C "$r" commit -qam "feat: real code"
j="$(gather realsrc "$r")"
[[ "$(sub "$j")" == "True" ]] && ok "real src commit → substantive (control)" \
  || bad "real src wrongly exempted: $(sub "$j")"

# (6) CONTROL: mixed src + ledger in ONE commit → substantive (mixed is never exempt).
r="$(mkrepo mixed)"
printf 'export const z = 3;\n' >> "$r/src/foo.ts"
printf -- '- [ ] mixed <!-- id:0003 -->\n' >> "$r/TODO.md"
git -C "$r" commit -qam "feat + todo"
j="$(gather mixed "$r")"
[[ "$(sub "$j")" == "True" ]] && ok "mixed src+ledger → substantive (control)" \
  || bad "mixed wrongly exempted: $(sub "$j")"

echo "---- $pass passed, $fail failed ----"
[[ "$fail" -eq 0 ]]
