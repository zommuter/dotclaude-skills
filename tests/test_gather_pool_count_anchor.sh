#!/usr/bin/env bash
# roadmap:fb7f — lane detection must anchor to an item's OWN tag in the two remaining
# substring-matching spots:
#   (A) gather-repo-state.sh open_hard_pool: an open item whose PROSE quotes
#       `[HARD — pool]` must NOT count (it-infra phantom `hard` verdict, 2026-06-30);
#       a 🚧-gated pool item must not count either (mirror classify-repo.sh:98's
#       conservative under-dispatch-safe exclusion).
#   (B) unpromoted-scan.sh primary_lane: an item with NO genuine lane tag whose prose
#       mentions [ROUTINE] (backtick'd OR bare) must be disposition `surface`, never
#       `promote`. LIVE EVIDENCE 2026-07-02: the leftmost-tag heuristic mislabeled
#       TODO ids 33c2/a505/7b23/b8ae as promote (b8ae's mention is BARE, so a
#       backtick-strip alone is insufficient).
#
# RED until the fix lands. Hermetic: mktemp git fixtures; RELAY_TOML /
# RELAY_WORKTREE_BASE / RELAY_DECISION_QUEUE / UNPROMOTED_SCAN_LOG all overridden.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATHER="$REPO_ROOT/relay/scripts/gather-repo-state.sh"
SCAN="$REPO_ROOT/relay/scripts/unpromoted-scan.sh"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"
export RELAY_DECISION_QUEUE="$tmpdir/decision-queue.jsonl"
export UNPROMOTED_SCAN_LOG="$tmpdir/scan.log"
touch "$RELAY_TOML"
mkdir -p "$RELAY_WORKTREE_BASE"

mkrepo() {  # mkrepo <path>
  git init -q "$1"
  git -C "$1" config user.email "t@t"
  git -C "$1" config user.name "T"
}

open_hard_pool_of() {  # open_hard_pool_of <repo-path>
  "$GATHER" --repo fixture --path "$1" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["open_hard_pool"])'
}

# ── Part A: gather-repo-state.sh open_hard_pool ───────────────────────────────
repoA="$tmpdir/repoA"
mkrepo "$repoA"
cat > "$repoA/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] A genuinely hands item whose re-lane criterion quotes `[HARD — pool]` in prose [HARD — hands] <!-- id:aaa1 -->
MD
git -C "$repoA" add ROADMAP.md
git -C "$repoA" commit -q -m "fixture"

echo "Test A1: prose-only [HARD — pool] mention → open_hard_pool==0"
got="$(open_hard_pool_of "$repoA")"
if [[ "$got" == "0" ]]; then ok "prose mention not counted"; else fail_msg "expected 0, got $got (phantom hard verdict class)"; fi

echo "Test A2: genuine pool item → open_hard_pool==1"
cat >> "$repoA/ROADMAP.md" <<'MD'
- [ ] Real pool work [HARD — pool] <!-- id:aaa2 -->
MD
git -C "$repoA" add ROADMAP.md; git -C "$repoA" commit -q -m "add pool item"
got="$(open_hard_pool_of "$repoA")"
if [[ "$got" == "1" ]]; then ok "genuine pool item counted once"; else fail_msg "expected 1, got $got"; fi

echo "Test A3: 🚧-gated pool item does not count"
cat >> "$repoA/ROADMAP.md" <<'MD'
- [ ] Gated pool work [HARD — pool] 🚧 GATED (DEP: id:aaa2) <!-- id:aaa3 -->
MD
git -C "$repoA" add ROADMAP.md; git -C "$repoA" commit -q -m "add gated pool item"
got="$(open_hard_pool_of "$repoA")"
if [[ "$got" == "1" ]]; then ok "gated pool item excluded (under-dispatch-safe)"; else fail_msg "expected 1 (gated excluded), got $got"; fi

# ── Part B: unpromoted-scan.sh primary_lane / disposition ─────────────────────
repoB="$tmpdir/repoB"
mkrepo "$repoB"
cat > "$repoB/ROADMAP.md" <<'MD'
# Roadmap

## Items

MD
cat > "$repoB/TODO.md" <<'MD'
# TODO

## Current

- [ ] **Untagged item with a backtick-quoted prose tag** — when a `[ROUTINE]` executor hits this case, defer it to the queue instead <!-- id:bbb1 -->
- [ ] **Untagged item with a bare prose tag** — the review child reports routine_open (open [ROUTINE] count after re-derivation); verify on the next pool <!-- id:bbb2 -->
- [ ] **Genuinely tagged item** [ROUTINE] — do the bounded thing; acceptance: its test goes green <!-- id:bbb3 -->
MD
git -C "$repoB" add ROADMAP.md TODO.md
git -C "$repoB" commit -q -m "fixture"

scan_out="$("$SCAN" "$repoB")"
dispo() { printf '%s\n' "$scan_out" | awk -F'\t' -v id="$1" '$2==id{print $3}'; }

echo "Test B1: backtick'd prose [ROUTINE], no genuine tag → surface"
got="$(dispo bbb1)"
if [[ "$got" == "surface" ]]; then ok "bbb1 surface"; else fail_msg "bbb1 expected surface, got '$got'"; fi

echo "Test B2: BARE prose [ROUTINE] mid-body, no genuine tag → surface"
got="$(dispo bbb2)"
if [[ "$got" == "surface" ]]; then ok "bbb2 surface (bare mention — backtick-strip alone insufficient)"; else fail_msg "bbb2 expected surface, got '$got'"; fi

echo "Test B3: genuine title-adjacent [ROUTINE] tag → promote (no regression)"
got="$(dispo bbb3)"
if [[ "$got" == "promote" ]]; then ok "bbb3 promote"; else fail_msg "bbb3 expected promote, got '$got'"; fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
