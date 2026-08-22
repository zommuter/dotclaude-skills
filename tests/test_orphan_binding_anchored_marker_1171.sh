#!/usr/bin/env bash
# test_orphan_binding_anchored_marker_1171.sh — the orphan→item binding must resolve an
# id through the item's OWN anchored `<!-- id:XXXX -->` marker, never a bare `id:XXXX`
# substring anywhere in ROADMAP.md ∪ ROADMAP.archive.md.
#
# NO `# roadmap:` HEADER ON PURPOSE. id:1171 lives in TODO.md, not ROADMAP.md, so a
# `# roadmap:1171` header would be inert today (run-tests.sh looks the checkbox up in
# ROADMAP.md) and would become a silent EXPECTED-RED mask the day 1171 were promoted
# (hazard filed as id:915b). Defect-fix test ⇒ no header ⇒ its failures always count.
#
# THE DEFECT (id:1171, residual half of id:a360). reconcile-repo.sh's suppress step greps
#   grep -qE '^[[:space:]]*- \[x\].*id:$oid'
# i.e. a BARE substring. `id:d050` mentioned as PROSE inside a DIFFERENT, closed `- [x]`
# item therefore satisfies it, and the orphan takes the *closed ⇒ stale ⇒ do NOT suppress*
# branch. The branch-name fix (5643e3f) closed this only for orphans whose branch encodes
# an item; a REPO-SCOPED orphan (`…-execute-repo-0`) encodes none, so the commit-message
# FALLBACK — which still ran the unanchored grep — was the only path available to it.
#
# ASYMMETRY that sets the severity: a false OPEN match is SAFE (the code suppresses, cost =
# one manual glance). A false CLOSED match SILENTLY SUPPRESSES NOTHING — the starvation
# class id:a360 exists to prevent.
#
# WHAT MUST NOT BREAK. The `- [x] ⇒ do NOT suppress` branch is load-bearing: it is the
# routed:42c9 / 8b21 ARCHIVE-BLINDNESS fix (roadmap-archive.sh sweeps shipped `- [x]` items
# out of the live file, so a DONE item used to fall through to "not in ROADMAP — ambiguous"
# and its stale orphan then suppressed re-dispatch FOREVER). Cases (3a)-(3c) below are the
# regression guards for it, archive variant included. OPEN-ANYWHERE-WINS across the two
# files and ambiguous-defaults-to-suppress are likewise ratified semantics, preserved here.
#
# `--dry-run` throughout: PLAN emits the same actions/surfaced JSON with zero mutating git
# calls (the id:77ce parity oracle), so this test never writes to a repo.
#
# Hermetic: mktemp -d git fixtures, HOME + RELAY_WORKTREE_BASE redirected into it; no
# ~/.claude, no real relay.toml, no real loderite checkout, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILE="$ROOT/relay/scripts/reconcile-repo.sh"
[[ -x "$RECONCILE" ]] || { echo "FAIL: reconcile-repo.sh not found/executable at $RECONCILE" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
export RELAY_WORKTREE_BASE="$tmp/wt"; mkdir -p "$RELAY_WORKTREE_BASE"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
ok()   { echo "PASS: $*"; }

# build_repo <dir> <branch> <commit-msg> <roadmap-body> [<archive-body>]
build_repo() {
  local d="$1" branch="$2" msg="$3" roadmap="$4" archive="${5:-}"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  printf '%s' "$roadmap" > "$d/ROADMAP.md"
  [[ -n "$archive" ]] && printf '%s' "$archive" > "$d/ROADMAP.archive.md"
  printf '# TODO\n' > "$d/TODO.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m base
  git -C "$d" checkout -q -b "$branch"
  printf 'partial work\n' > "$d/partial.txt"
  git -C "$d" add -A
  git -C "$d" commit -q -m "$msg"
  git -C "$d" checkout -q main
}

run_reconcile() {
  "$RECONCILE" --dry-run --repo "$(basename "$1")" --path "$1" \
    --live-claims "" --main-branch main 2>"$tmp/err.txt"
}

# suppress action details, "|"-joined ("" when none)
suppress_details() {
  python3 -c 'import sys,json
d=json.load(sys.stdin)
print("|".join(a["detail"] for a in d["actions"] if a["kind"]=="suppress"))'
}

# The repo-scoped orphan branch: its name encodes NO item ("repo" is not a hex token), so
# reconcile-repo.sh's branch-name derivation cannot fire and the commit-message fallback is
# the ONLY available path. That is exactly the shape id:1171 leaves exposed.
REPO_BRANCH='relay/orphan/relay-20260822-102233-32252-execute-repo-0'
REPO_MSG='feat(tools): headless-Chromium PWABuilder report-card driver (id:d050)'

# ═══ (1) THE DEFECT — d050 only as PROSE inside a CLOSED item ⇒ must NOT take the closed
#         branch. Pre-fix: the bare grep matches that `- [x]` line ⇒ suppress=false ⇒ the
#         orphan yields NO suppress entry at all, silently. ════════════════════════════════
repo1="$tmp/prose-closed"
build_repo "$repo1" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [ ] [ROUTINE] an unrelated open item <!-- id:ba09 -->
' \
  '# Roadmap archive

- [x] [HARD] **Wire the share URL into the app** <!-- id:0295 --> **CLOSED.** Prior partial work was parked as `relay/orphan/…-execute-0` and the driver landed under id:d050 commit-and-park.
'
out1="$(run_reconcile "$repo1")"
det1="$(suppress_details <<<"$out1")"
if [[ -z "$det1" ]]; then
  note "(1) THE DEFECT: a repo-scoped orphan whose id (d050) occurs ONLY as prose inside a DIFFERENT item's CLOSED \`- [x]\` body produced NO suppress entry — the bare-substring grep read the prose mention as that item's own marker and took the 'closed ⇒ stale ⇒ do NOT suppress' branch. A false CLOSED match suppresses nothing, silently: the starvation class. JSON: $out1"
else
  ok "(1) a prose-only mention inside a CLOSED item does not silence the binding"
fi
grep -q 'id:0295' <<<"$det1" \
  && note "(1) the suppress reason names id:0295 — the orphan was bound to the item that merely MENTIONS d050: [$det1]"

# ═══ (2) same shape, prose mention inside an OPEN item. Suppression happens either way, so
#         the REASON is the assertion — it must be the honest ambiguous one, not the
#         "still OPEN" one (which would claim parked work for a non-existent item). ═══════
repo2="$tmp/prose-open"
build_repo "$repo2" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [ ] [ROUTINE] an open item whose body merely mentions id:d050 in prose <!-- id:ba09 -->
'
out2="$(run_reconcile "$repo2")"
det2="$(suppress_details <<<"$out2")"
[[ -n "$det2" ]] \
  || note "(2) no suppress entry for an unresolvable binding — ambiguous must default to suppress: $out2"
if grep -q 'still OPEN' <<<"$det2"; then
  note "(2) the suppress reason claims 'parked partial work for id:d050 still OPEN', but NO item owns d050 — d050 appears only as prose in id:ba09's body. Suppressing is right; this reason is not. Expected the ambiguous branch: [$det2]"
elif grep -q 'ambiguous' <<<"$det2"; then
  ok "(2) a prose-only mention inside an OPEN item suppresses for the HONEST ambiguous reason"
else
  note "(2) unexpected suppress reason: [$det2]"
fi

# ═══ (3) REGRESSION GUARDS for the load-bearing branch ═══════════════════════════════════
# (3a) genuinely-anchored OPEN item ⇒ suppress, reason says still OPEN.
repo3a="$tmp/anchored-open"
build_repo "$repo3a" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [ ] [ROUTINE] the item this orphan belongs to <!-- id:d050 -->
'
det3a="$(suppress_details <<<"$(run_reconcile "$repo3a")")"
grep -q 'still OPEN' <<<"$det3a" \
  && ok "(3a) an anchored OPEN item still suppresses, with the still-OPEN reason" \
  || note "(3a) an anchored OPEN item lost its suppression (id:1f53 core case): [$det3a]"

# (3b) genuinely-anchored CLOSED item in the LIVE file ⇒ do NOT suppress (stale orphan prunes).
repo3b="$tmp/anchored-closed-live"
build_repo "$repo3b" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [x] [ROUTINE] the shipped item this stale orphan belongs to <!-- id:d050 -->
'
det3b="$(suppress_details <<<"$(run_reconcile "$repo3b")")"
[[ -z "$det3b" ]] \
  && ok "(3b) an anchored CLOSED item in ROADMAP.md still does NOT suppress — the stale orphan prunes" \
  || note "(3b) an anchored CLOSED item suppressed re-dispatch — a done item's stale orphan would stall the repo forever: [$det3b]"

# (3c) the routed:42c9 ARCHIVE-BLINDNESS case: anchored CLOSED in ROADMAP.archive.md.
repo3c="$tmp/anchored-closed-archive"
build_repo "$repo3c" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [ ] [ROUTINE] an unrelated open item <!-- id:ba09 -->
' \
  '# Roadmap archive

- [x] [ROUTINE] the shipped item this stale orphan belongs to <!-- id:d050 -->
'
det3c="$(suppress_details <<<"$(run_reconcile "$repo3c")")"
[[ -z "$det3c" ]] \
  && ok "(3c) an anchored CLOSED item swept into ROADMAP.archive.md still does NOT suppress (routed:42c9 archive-blindness fix intact)" \
  || note "(3c) ARCHIVE-BLINDNESS REGRESSED: a shipped item archived out of the live ROADMAP suppressed re-dispatch forever: [$det3c]"

# (3d) OPEN-ANYWHERE-WINS: `- [x]` live but `- [ ]` archived ⇒ suppress (ratified semantics).
repo3d="$tmp/open-anywhere"
build_repo "$repo3d" "$REPO_BRANCH" "$REPO_MSG" \
  '# Roadmap

## Items
- [x] [ROUTINE] closed in the live file <!-- id:d050 -->
' \
  '# Roadmap archive

- [ ] [ROUTINE] but an archived twin is still open <!-- id:d050 -->
'
det3d="$(suppress_details <<<"$(run_reconcile "$repo3d")")"
grep -q 'still OPEN' <<<"$det3d" \
  && ok "(3d) OPEN-ANYWHERE-WINS preserved — an open twin anywhere in the union suppresses" \
  || note "(3d) OPEN-ANYWHERE-WINS regressed: an item open in ROADMAP.archive.md but closed live no longer suppresses: [$det3d]"

# ═══ (4) the BRANCH-NAME path is unaffected: the item comes from the ref name, and the
#         commit message's own id (the parking mechanism's) never decides. ════════════════
repo4="$tmp/branch-name"
build_repo "$repo4" 'relay/orphan/relay-20260820-180056-4594-execute-57d1-0' \
  'chore(relay): WIP UNVERIFIED residue auto-commit for worktree relay-20260820-180056-4594-execute-57d1-0 (id:f272 commit-and-park; do not treat as reviewed)' \
  '# Roadmap

## Items
- [ ] [ROUTINE] editor-core share plumbing <!-- id:57d1 -->
' \
  '# Roadmap archive

- [x] [HARD] a closed item whose body mentions id:f272 commit-and-park in prose <!-- id:0295 -->
'
det4="$(suppress_details <<<"$(run_reconcile "$repo4")")"
grep -q 'id:57d1' <<<"$det4" \
  && ok "(4) the branch-name derivation is unaffected — the orphan binds to id:57d1" \
  || note "(4) the branch-name path regressed; expected a suppress reason naming id:57d1: [$det4]"
grep -q 'still OPEN' <<<"$det4" \
  || note "(4) the branch-name-derived binding did not read id:57d1 as OPEN: [$det4]"
grep -q 'id:f272' <<<"$det4" \
  && note "(4) the parking MECHANISM's id f272 leaked into the suppress reason: [$det4]"

[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: the orphan→item binding resolves ids through the anchored <!-- id:XXXX --> marker; a prose-only mention never decides a suppression, and the archive-blindness / open-anywhere-wins semantics are intact (id:1171)"
