#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose: this is the fourth instance of
# the routed:42c9 / routed:8b21 ARCHIVE-BLINDNESS class found by surveying every ledger
# scanner, and it has no ROADMAP item of its own. Failures here always count.
#
# `reconcile-repo.sh`'s ORPHAN SUPPRESS-REDISPATCH plan step (id:1f53) binds each parked
# `relay/orphan/*` branch back to its ROADMAP item and decides three ways against the LIVE
# ROADMAP.md alone:
#     `- [ ] … id:X`  → suppress ("still OPEN")
#     `- [x] … id:X`  → do NOT suppress (stale leftover, let it classify)
#     absent          → suppress ("item not in ROADMAP — ambiguous")
# An item that shipped and was archived falls into the THIRD branch, so a DONE item's stale
# orphan permanently suppresses re-dispatch and discover-repo.sh skips classify for the
# repo — a false-MISSING that silently stalls the repo. `- [x]` in ROADMAP.archive.md must
# read exactly like `- [x]` in ROADMAP.md.
#
# `--dry-run` is used throughout: PLAN emits the same actions/surfaced JSON with zero
# mutating git calls (the id:77ce parity oracle), so this test never writes to a repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILE="$ROOT/relay/scripts/reconcile-repo.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"

fail() { echo "FAIL: $*"; echo "--- reconcile JSON ---"; echo "$out"; exit 1; }

# build_repo <dir> <roadmap-body> [<archive-body>] — a repo with ONE parked orphan branch
# whose tip commit message carries id:ba01.
build_repo() {
  local d="$1" roadmap="$2" archive="${3:-}"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  printf '%s' "$roadmap" > "$d/ROADMAP.md"
  [[ -n "$archive" ]] && printf '%s' "$archive" > "$d/ROADMAP.archive.md"
  printf '# TODO\n' > "$d/TODO.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m "base"
  # the parked orphan: an unmerged branch under relay/orphan/ whose tip names the item
  git -C "$d" checkout -q -b relay/orphan/exec-ba01
  printf 'partial work\n' > "$d/partial.txt"
  git -C "$d" add -A
  git -C "$d" commit -q -m "wip on id:ba01 — parked partial work"
  git -C "$d" checkout -q main
}

run_reconcile() {
  "$RECONCILE" --dry-run --repo "$(basename "$1")" --path "$1" --live-claims "" --main-branch main
}

# --- Case 1 — THE DEFECT: ba01 shipped and was archived out of the live ROADMAP.
repoA="$tmp/archived"
build_repo "$repoA" \
  '# Roadmap
## Items
- [ ] [ROUTINE] some other open item <!-- id:ba09 -->
' \
  '# Roadmap archive
- [x] [ROUTINE] the shipped item this orphan belongs to <!-- id:ba01 -->
'
out="$(run_reconcile "$repoA")"
grep -qE '"kind": *"suppress"' <<<"$out" \
  && fail "a CLOSED item archived into ROADMAP.archive.md still suppressed re-dispatch — the orphan binding is archive-blind and fell into the \"item not in ROADMAP — ambiguous\" branch"
echo "PASS: a [x] item in ROADMAP.archive.md does not suppress (same as [x] in ROADMAP.md)"

# --- Case 2 — negative control: a genuinely OPEN item must STILL suppress.
repoB="$tmp/open"
build_repo "$repoB" \
  '# Roadmap
## Items
- [ ] [ROUTINE] the item this orphan belongs to, still open <!-- id:ba01 -->
'
out="$(run_reconcile "$repoB")"
grep -qE '"kind": *"suppress"' <<<"$out" \
  || fail "a still-OPEN item with parked partial work did not suppress — the archive widening broke id:1f53's core case"
echo "PASS: a still-open item still suppresses re-dispatch"

# --- Case 3 — negative control: an id present NOWHERE stays ambiguous → suppress.
repoC="$tmp/absent"
build_repo "$repoC" \
  '# Roadmap
## Items
- [ ] [ROUTINE] an unrelated open item <!-- id:ba09 -->
'
out="$(run_reconcile "$repoC")"
grep -qE '"kind": *"suppress"' <<<"$out" \
  || fail "an orphan bound to an id present in NO ledger stopped suppressing — the ambiguous-defaults-to-suppress rule regressed"
echo "PASS: an unresolvable binding still defaults to suppress"

# --- Case 4 — an OPEN item in ROADMAP.archive.md (an archived parent nesting open work)
# must still suppress: only `- [x]` means done.
repoD="$tmp/openinarchive"
build_repo "$repoD" \
  '# Roadmap
## Items
- [ ] [ROUTINE] an unrelated open item <!-- id:ba09 -->
' \
  '# Roadmap archive
- [ ] [ROUTINE] archived block, but THIS line is still open <!-- id:ba01 -->
'
out="$(run_reconcile "$repoD")"
grep -qE '"kind": *"suppress"' <<<"$out" \
  || fail "an OPEN line inside ROADMAP.archive.md stopped suppressing — archive MEMBERSHIP was treated as closure"
echo "PASS: membership in the archive is not closure; only [x] is"

# --- Case 5 — PRECEDENCE, pinned rather than left accidental. When an id disagrees across
# the two files (live `- [x]`, archive `- [ ]`), this step is OPEN-ANYWHERE-WINS and
# SUPPRESSES — deliberately NOT resolve-gates.sh's live-first rule.
#
# The two scripts answer different questions. resolve-gates computes a TRUTH VALUE about
# closure, so the live ledger (current state) must beat the archive (history). This step
# makes a COST-ASYMMETRIC safety call: wrongly suppressing costs one manual glance, wrongly
# re-dispatching costs a repeated expensive session — so any sign of openness wins. That
# matches the step's own documented default ("Ambiguous binding defaults to suppress").
#
# This case exists because the first version of the fix shipped a comment claiming
# "live first", which the `grep -q`-across-both-files implementation does not do. The
# behaviour was right and the claim about it was wrong; this pins the behaviour so the
# next reader gets it from a test rather than from prose.
repoE="$tmp/mixed"
build_repo "$repoE" \
  '# Roadmap
## Items
- [x] [ROUTINE] the item, closed in the LIVE queue <!-- id:ba01 -->
' \
  '# Roadmap archive
- [ ] [ROUTINE] an OLD still-open line recycling ba01 <!-- id:ba01 -->
'
out="$(run_reconcile "$repoE")"
grep -qE '"kind": *"suppress"' <<<"$out" \
  || fail "a live-[x] / archive-[ ] disagreement did not suppress — this step is OPEN-ANYWHERE-WINS by design (cost-asymmetric), not live-first"
grep -qE 'still OPEN' <<<"$out" \
  || fail "suppressed for the wrong reason — expected the still-OPEN branch, not the ambiguous fallback"
echo "PASS: live-[x] vs archive-[ ] suppresses (open-anywhere-wins, deliberately unlike resolve-gates.sh)"

echo "OK: test_reconcile_orphan_roadmap_archive.sh"
