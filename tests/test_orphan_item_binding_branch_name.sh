#!/usr/bin/env bash
# fails-against: HEAD before the branch-name binding fix — reconcile-repo.sh's
#   oid="$(git show --stat "$oref" | grep -oE 'id:[0-9a-f]{4}' | head -1)"
#   derives f272 (the commit-and-park MECHANISM id) for the branch
#   relay/orphan/relay-20260820-180056-4594-execute-57d1-0, so id:57d1 never reaches
#   suppressed_item_ids and the pool selects it anyway.
#
# THE DEFECT (found live on loderite 2026-08-22, upstream of id:a360). Two mechanisms bind a
# parked orphan back to its ROADMAP item BY DIFFERENT KEYS, and they disagree for exactly the
# commit-and-park residue class — the class produced when an executor dies mid-work, i.e. when
# the binding matters most:
#
#   reconcile-repo.sh       binds by COMMIT MESSAGE  (first `id:XXXX` token)
#   stranded-branch-scan.sh binds by BRANCH NAME     (the `-<verdict>-<item>-` segment)
#
# The residue commit's message is written by the commit-and-park mechanism and reads
#   "chore(relay): WIP UNVERIFIED residue auto-commit for worktree
#    relay-20260820-180056-4594-execute-57d1-0 (id:f272 commit-and-park; do not treat as
#    reviewed)"
# — its only `id:` token is f272, the PARKING MECHANISM's id. The item id 57d1 appears only in
# the branch name. Measured against the real loderite repo:
#   relay/orphan/…-execute-57d1-0  → commit-message derivation = f272   WRONG
#   relay/orphan/…-execute-repo-0  → commit-message derivation = d050   correct
# So suppressed_item_ids came out {f272,d050}, id:57d1 survived namedItemsFor's subtraction
# (relay-loop.js:2582, id:b09e), was picked as actionable_routine_ids[0], and the id:dd7d guard
# — which binds by branch name and DOES see it — then zeroed the repo (id:a360).
#
# THE CONTRACT
#   1. A branch whose name encodes an item (`…-<verdict>-<item>-<attempt>`) binds to the
#      BRANCH-NAME item, even when its commit message names a different `id:`.
#   2. A repo-scoped branch (`…-<verdict>-repo-<attempt>`) encodes NO item, so it keeps binding
#      via the commit message exactly as it does today.
#   3. The binding agrees with stranded-branch-scan.sh's key — the two are cross-checked here
#      against the same fixture, so they cannot drift apart again silently.
#
# The fixtures use the real observed branch names, the real residue commit message and the real
# item ids — this is recorded data, not invented structure.
#
# Hermetic: mktemp -d git fixtures only; no ~/.claude, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RC="$ROOT/relay/scripts/reconcile-repo.sh"
SCAN="$ROOT/relay/scripts/stranded-branch-scan.sh"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
pass() { echo "PASS: $*"; }

[[ -x "$RC" ]]   || { echo "FAIL: reconcile-repo.sh not found/executable at $RC" >&2; exit 1; }
[[ -x "$SCAN" ]] || { echo "FAIL: stranded-branch-scan.sh not found/executable at $SCAN" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"; mkdir -p "$RELAY_WORKTREE_BASE"

repo="$tmp/loderite"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@e
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false

# ROADMAP: 57d1 is OPEN; f272 and d050 are NOT in it at all (f272 is the parking mechanism's
# own id, which lives in dotclaude-skills, not in loderite's ledger).
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] [ROUTINE] editor-core work <!-- id:57d1 -->\n'
  printf -- '- [ ] [ROUTINE] next actionable item <!-- id:6612 -->\n'
} > "$repo/ROADMAP.md"
printf '# TODO\n## Current\n' > "$repo/TODO.md"
git -C "$repo" add -A
git -C "$repo" commit -qm init

# (fixture 1) the commit-and-park RESIDUE orphan for item 57d1 — verbatim message shape.
git -C "$repo" checkout -q -b "relay/orphan/relay-20260820-180056-4594-execute-57d1-0"
echo residue > "$repo/src-editor-core.ts"
git -C "$repo" add -A
git -C "$repo" commit -qm "chore(relay): WIP UNVERIFIED residue auto-commit for worktree relay-20260820-180056-4594-execute-57d1-0 (id:f272 commit-and-park; do not treat as reviewed)"

# (fixture 2) the REPO-SCOPED orphan — no item in the branch name; its message names id:d050.
git -C "$repo" checkout -q main
git -C "$repo" checkout -q -b "relay/orphan/relay-20260820-180056-4594-execute-repo-0"
echo driver > "$repo/tools-driver.ts"
git -C "$repo" add -A
git -C "$repo" commit -qm "feat(tools): headless-Chromium PWABuilder report-card driver (id:d050)"

git -C "$repo" checkout -q main

out="$("$RC" --dry-run --repo loderite --path "$repo" --runid myrun123 --live-claims "" --main-branch main 2>"$tmp/err")" \
  || note "reconcile-repo.sh exited non-zero: $(cat "$tmp/err")"

surf() { python3 -c 'import sys,json; print("\n".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))' <<<"$out"; }
supp_ids() { surf | grep -oE 'id:[0-9a-f]{4}' | sed 's/id://' | sort -u | tr '\n' ' '; }

# ── (1) the residue orphan binds to the BRANCH-NAME item, not the message's mechanism id ──
line57="$(surf | grep 'execute-57d1-0' || true)"
if [[ -z "$line57" ]]; then
  note "(1) no surfaced line at all for relay/orphan/…-execute-57d1-0 — the orphan was not evaluated: $out"
else
  grep -q 'id:57d1' <<<"$line57" \
    || note "(1) the residue orphan bound to the WRONG item — its surfaced line must name id:57d1 (the branch-name item), got: $line57"
  grep -q 'id:f272' <<<"$line57" \
    && note "(1) the residue orphan bound to id:f272, the commit-and-park MECHANISM id from the commit message — that id is not a loderite ROADMAP item: $line57"
  grep -q 'still OPEN' <<<"$line57" \
    || note "(1) id:57d1 is OPEN in the fixture ROADMAP, so the suppress reason must say so (an 'ambiguous' reason means the binding still missed): $line57"
  grep -q '^suppressed re-dispatch:' <<<"$line57" \
    || note "(1) the line lacks the 'suppressed re-dispatch:' class marker discover-repo.sh dispatches on: $line57"
fi

# ── (2) the repo-scoped orphan keeps binding via the COMMIT MESSAGE (unchanged) ───────────
linerepo="$(surf | grep 'execute-repo-0' || true)"
if [[ -z "$linerepo" ]]; then
  note "(2) no surfaced line for the repo-scoped orphan — it must still be evaluated: $out"
else
  grep -q 'id:d050' <<<"$linerepo" \
    || note "(2) the repo-scoped orphan lost its commit-message binding to id:d050 — 'repo' is not an item id, so the message fallback must still run: $linerepo"
  grep -qE '\-(execute|review|handoff)-repo-' <<<"$linerepo" \
    || note "(2) the repo-scoped orphan's ref name is missing from its surfaced line: $linerepo"
fi

# ── (3) the two ids that reach discover-repo.sh's suppressed set ──────────────────────────
ids="$(supp_ids)"
[[ "$ids" == *"57d1"* ]] \
  || note "(3) id:57d1 never reaches suppressed_item_ids, so relay-loop.js's namedItemsFor cannot subtract it and the pool selects it anyway (the a360 starvation). Extracted ids: [$ids]"
[[ "$ids" == *"f272"* ]] \
  && note "(3) id:f272 leaked into the suppressed set — a mechanism id is not a ledger item and would suppress nothing real. Extracted ids: [$ids]"

# ── (4) CROSS-CHECK: reconcile's key must agree with stranded-branch-scan.sh's key ────────
# The whole defect is these two disagreeing. Same fixture, same question, same answer required.
scan57="$("$SCAN" "$repo" --verdict execute --item 57d1 --base main 2>"$tmp/scanerr")" \
  || note "(4) stranded-branch-scan.sh errored: $(cat "$tmp/scanerr")"
grep -q 'execute-57d1-0' <<<"$scan57" \
  || note "(4) stranded-branch-scan.sh does not see the 57d1 orphan; the fixture no longer reproduces the disagreement: [$scan57]"
if grep -q 'execute-57d1-0' <<<"$scan57" && ! grep -q 'id:57d1' <<<"$line57"; then
  note "(4) THE DISAGREEMENT IS STILL LIVE: stranded-branch-scan.sh binds relay/orphan/…-execute-57d1-0 to item 57d1 (by branch name) while reconcile-repo.sh binds it to something else (by commit message). These two must agree or dd7d fires on an item b09e never suppressed."
fi
# and the repo-scoped branch must NOT be item-matched by the scanner either (trap i)
scanrepo="$("$SCAN" "$repo" --verdict execute --item d050 --base main 2>/dev/null || true)"
grep -q 'execute-repo-0' <<<"$scanrepo" \
  && note "(4) stranded-branch-scan.sh item-matched the repo-scoped branch for item d050 — 'repo' must never match a real item id"

[[ $fail -eq 0 ]] || exit 1
pass "orphan→item binding reads the BRANCH NAME (authoritative), falls back to the commit message for repo-scoped refs, and agrees with stranded-branch-scan.sh"
echo "ALL PASS: reconcile-repo.sh binds a commit-and-park residue orphan to its real ROADMAP item"
