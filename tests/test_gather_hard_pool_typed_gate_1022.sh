#!/usr/bin/env bash
# NO `# roadmap:` header BY DESIGN: id:1022 is a DEFECT filed in TODO.md, not a ROADMAP
# item, so per tests/README conventions (see CLAUDE.md "Testing") this file carries no
# roadmap header and its failures ALWAYS count — it can never be EXPECTED-RED.
#
# SPEC for id:1022 — `gather-repo-state.sh`'s `open_hard_pool` counter must honour the
# TYPED `<!-- gated-on:XXXX -->` edge, resolved through the SHARED id:46f6 engine
# (resolve-gates.sh → lib-typed-edges.sh), exactly as the routine collector
# (`classify-repo.sh`'s `actionable_routine_open`, id:65f5) already does.
#
# The defect (gather-repo-state.sh ~:414-437 before the fix): the loop skipped a
# `[HARD - pool]` line only on the PROSE gate forms (🚧 / "BLOCKED on" / "blocked (" …)
# and NEVER consulted the typed marker. That inverts the settled id:65f5/id:46f6 rule —
# only typed edges are honoured, prose substrings never are — so a properly typed,
# genuinely gated HARD item counted as pool-dispatchable.
#
# LIVE CONSEQUENCE (run relay-20260811-141645-22545, project_manager): id:cb9e carries
# `<!-- gated-on:c56a -->` with c56a still open, yet still produced open_hard_pool=1 →
# verdict=hard → an apex child dispatched that could only hand the item straight back.
#
# TRIANGULATION: every exclusion case is paired with a DISCRIMINATING control, so a fix
# that zeroes the counter, that greps the bare substring "gated-on", or that treats a
# dangling target as a forever-block all fail here.
#
# Hermetic: real `git init` fixtures in mktemp, RELAY_TOML/RELAY_WORKTREE_BASE sandboxed,
# no network, never reads ~/.config/relay. Idiom: tests/test_container_not_hard_pool_d808.sh.
# fails-against: rev d449c4815224 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/gather-repo-state.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: d449c4815224 -- relay/scripts/gather-repo-state.sh
# fails-against-assertion: parity: collectors disagree — gather

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

# fixture_repo <roadmap-body> [<todo-body>] → path to a hermetic git repo
fixture_repo() {
  local body="$1" todo="${2:-}"
  local repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"
  git -C "$repo" config user.name "T"
  { printf '# Roadmap\n## Items\n'; printf '%s\n' "$body"; } > "$repo/ROADMAP.md"
  { printf '# TODO\n## Current\n'; [[ -n "$todo" ]] && printf '%s\n' "$todo"; } > "$repo/TODO.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

# ohp_of <roadmap-body> [<todo-body>] → gather-repo-state.sh's open_hard_pool
ohp_of() {
  local repo; repo="$(fixture_repo "$1" "${2:-}")"
  "$GATHER" --repo fixture --path "$repo" --runid test 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))'
}

# ── Case 1 (POSITIVE CONTROL): an un-gated pool leaf still counts ────────────────
# Without this, a fix that hard-codes open_hard_pool=0 would pass every other case.
got="$(ohp_of '- [ ] [HARD] A genuine un-gated pool leaf <!-- id:0001 -->')"
[[ "$got" == "1" ]] && ok "control: un-gated pool leaf counts (open_hard_pool=1)" \
                    || bad "control: un-gated pool leaf should count 1, got '$got'"

# ── Case 2: typed gated-on whose target is still OPEN must NOT count ─────────────
# The live project_manager shape: the gate target lives in the SAME ROADMAP, open.
body='- [ ] [HARD] Gated seam <!-- gated-on:0aaa --> <!-- id:0002 -->
- [ ] [ROUTINE] The gate target, still open <!-- id:0aaa -->'
got="$(ohp_of "$body")"
[[ "$got" == "0" ]] && ok "typed gated-on with an OPEN target is excluded (open_hard_pool=0)" \
                    || bad "typed gated-on with an OPEN target must be excluded (0), got '$got'"

# ── Case 3: the gate target resolving in TODO.md (cross-ledger) also blocks ──────
# resolve-gates.sh's map spans ROADMAP ∪ TODO ∪ TODO.archive; the counter must inherit
# that scope rather than a ROADMAP-only re-implementation.
got="$(ohp_of '- [ ] [HARD] Gated seam <!-- gated-on:0bbb --> <!-- id:0003 -->' \
              '- [ ] design work, still open <!-- id:0bbb -->')"
[[ "$got" == "0" ]] && ok "gate target resolved in TODO.md blocks too (0)" \
                    || bad "gate target resolved in TODO.md should block (0), got '$got'"

# ── Case 4 (DISCRIMINATING CONTROL): a CLOSED gate target must NOT suppress ──────
# A fix that skips any line containing "gated-on" fails here.
body='- [ ] [HARD] Gated seam whose gate has LANDED <!-- gated-on:0ccc --> <!-- id:0004 -->
- [x] [ROUTINE] The gate target, closed <!-- id:0ccc -->'
got="$(ohp_of "$body")"
[[ "$got" == "1" ]] && ok "typed gated-on with a CLOSED target still counts (1)" \
                    || bad "closed gate target must not suppress the item; expected 1, got '$got'"

# ── Case 5 (DISCRIMINATING CONTROL): a DANGLING target is LOUD, never a block ────
# resolve-gates.sh/classify-repo.sh semantics: an unresolvable token is surfaced but
# never silently forever-blocks. The counter must not invent a stricter rule.
got="$(ohp_of '- [ ] [HARD] Gated on a token that resolves nowhere <!-- gated-on:0fff --> <!-- id:0005 -->')"
[[ "$got" == "1" ]] && ok "dangling gate target does NOT block (1) — loud, not silent-block" \
                    || bad "dangling gate target must not block; expected 1, got '$got'"

# ── Case 6 (DISCRIMINATING CONTROL): PROSE `gated-on:` is NOT an edge ────────────
# The id:4da4/0d58 bare-substring trap: only the comment-anchored form is an edge.
body='- [ ] [HARD] Seam that merely mentions gated-on:0ddd in prose <!-- id:0006 -->
- [ ] [ROUTINE] The would-be target, open <!-- id:0ddd -->'
got="$(ohp_of "$body")"
[[ "$got" == "1" ]] && ok "bare prose 'gated-on:XXXX' is not an edge — item still counts (1)" \
                    || bad "prose 'gated-on:' must not block (typed edges only); expected 1, got '$got'"

# ── Case 7: exclusion is PER-LINE, not a whole-file bail-out ─────────────────────
body='- [ ] [HARD] Gated seam <!-- gated-on:0eee --> <!-- id:0007 -->
- [ ] [HARD] A real un-gated sibling <!-- id:0008 -->
- [ ] [ROUTINE] The gate target, still open <!-- id:0eee -->'
got="$(ohp_of "$body")"
[[ "$got" == "1" ]] && ok "gated exclusion is per-LINE: the un-gated sibling still counts (1)" \
                    || bad "expected 1 (only the un-gated sibling), got '$got'"

# ── Case 8 (PARITY, behavioural on both sides): the two collectors must agree ────
# classify-repo.sh's actionable_routine_open ALREADY excludes a typed-gated item
# (id:65f5). The defect IS that disagreement, so assert it directly.
repo="$(fixture_repo '- [ ] [HARD] Gated seam <!-- gated-on:0abc --> <!-- id:0009 -->
- [ ] [ROUTINE] The gate target, still open <!-- id:0abc -->')"
aro="$("$CLASSIFY" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("actionable_routine_open"))')"
ohp="$("$GATHER" --repo fixture --path "$repo" --runid test 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))')"
# The ROUTINE gate target itself is actionable, so aro counts it (1) while the GATED
# HARD item must be excluded on both sides — pin gather at 0 and classify at exactly
# the target-only count.
if [[ "$ohp" == "0" && "$aro" == "1" ]]; then
  ok "parity: gather excludes the typed-gated HARD line (0) while classify counts only the un-gated target (1)"
else
  bad "parity: collectors disagree — gather open_hard_pool='$ohp' (want 0), classify aro='$aro' (want 1)"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
