#!/usr/bin/env bash
# roadmap:1048
# RED SPEC for id:1048 — "Build BOUNDED auto-integrate for stranded orphans".
# Authored by /relay handoff 2026-07-23 (targeted C2). UN-DEMOTED per the --fabled A1 amendment
# (meeting docs/meeting-notes/2026-07-23-1735-relay-orphan-existence-never-blocks.md, A1): the D1
# "reconcile-first (integrate-if-safe)" rule is a NULL op while 1048 is unbuilt (the loop has no
# integrate primitive; /relay reconcile is human-only), so a single-item-only-orphan repo STALLS
# pending human reconcile — the exact original complaint. This builds the minimal auto-integrate.
#
# RATIFIED CONTRACT (A1): the relay loop auto-completes a parked orphan IFF ALL of:
#   • COMPLETE            — the child ticked its box / no open work remains for the item.
#   • clean 3-way merge   — merges onto CURRENT main with NO conflict.
#   • non-diverged        — the repo is not ahead+behind its origin.
#   • full-suite GREEN    — the ENTIRE test suite passes in a SCRATCH worktree POST-merge.
# On success it runs the standard integrate (verify → --no-ff merge → ckpt-tag → push equivalent).
# On ANY failure (partial/mid-cutoff, any conflict, any red, any divergence) it LEAVES the orphan
# PARKED and SURFACES for a human `/relay reconcile` — it NEVER force-merges or auto-resolves.
# Extends id:2370 (ledger-only auto-integrate) to CODE-BEARING orphans.
#
# SEAM: a NEW primitive `relay/scripts/auto-integrate-orphan.sh`:
#     auto-integrate-orphan.sh --repo <main-checkout-abs> --orphan-branch <relay/orphan/*>
#                              [--main-branch <name>]
#   Suite command is injectable for hermeticity via env RELAY_SUITE_CMD (default "make test"),
#   run in the scratch worktree post-merge — a red suite ⇒ NOT integrated.
#   Exit 0  = auto-integrated (main advanced --no-ff to include the orphan; orphan retired).
#   Exit !0 = left parked + surfaced (main UNCHANGED; orphan branch intact); reason on stdout/stderr.
#
# RED until id:1048's ROADMAP checkbox is ticked: the primitive does not exist yet — assertion (0)
# fails immediately.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$ROOT/relay/scripts/auto-integrate-orphan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }

# --- (0) the primitive must exist and be executable (RED: not authored yet) -------------------
[[ -x "$AI" ]] || fail "(0) auto-integrate-orphan.sh not authored yet (RED): $AI"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# helper: build a repo with an origin (so non-diverged is well-defined) + a parked orphan branch
# whose commit COMPLETES id:<item> (ticks its ROADMAP box) and adds a feature file.
build_case() {  # <dir> <item-id> <feature-content> [--main-touch <content>]
  local d="$1" item="$2" feat="$3" main_touch="${5:-}"
  mkrepo "$d"
  printf '# Roadmap\n## Items\n- [ ] [ROUTINE] the work <!-- id:%s -->\n' "$item" > "$d/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$d/TODO.md"
  printf 'shared\n' > "$d/shared.txt"
  git -C "$d" add -A; git -C "$d" commit -qm init
  local origin="$d.origin"; git -C "$d" init -q --bare "$origin" 2>/dev/null || git init -q --bare "$origin"
  git -C "$d" remote add origin "$origin"; git -C "$d" push -q -u origin main
  # parked orphan: branched from main, completes the item + adds a feature file
  git -C "$d" branch "relay/orphan/deadrun-$item" main
  git -C "$d" checkout -q "relay/orphan/deadrun-$item"
  printf '# Roadmap\n## Items\n- [x] [ROUTINE] the work <!-- id:%s -->\n' "$item" > "$d/ROADMAP.md"
  printf '%s\n' "$feat" > "$d/feature.txt"
  git -C "$d" add -A; git -C "$d" commit -qm "complete id:$item"
  git -C "$d" checkout -q main
  # optionally advance main on a shared path so the orphan CONFLICTS on merge
  if [[ -n "$main_touch" ]]; then
    printf '%s\n' "$main_touch" > "$d/feature.txt"
    git -C "$d" add -A; git -C "$d" commit -qm "main also wrote feature.txt"
    git -C "$d" push -q origin main
  fi
}

# ============================================================================================
# (a) COMPLETE + clean-merge + non-diverged + GREEN suite → AUTO-INTEGRATED.
# ============================================================================================
RA="$tmp/r_ok"; build_case "$RA" 1a1a "feature body"
main_before="$(git -C "$RA" rev-parse main)"
if out_a="$(RELAY_SUITE_CMD=true "$AI" --repo "$RA" --orphan-branch "relay/orphan/deadrun-1a1a" --main-branch main 2>&1)"; then rc_a=0; else rc_a=$?; fi
[[ "$rc_a" -eq 0 ]] \
  || fail "(a) a complete+clean+green orphan must AUTO-INTEGRATE (exit 0), got exit $rc_a: $out_a"
git -C "$RA" merge-base --is-ancestor "relay/orphan/deadrun-1a1a" main \
  || fail "(a) after auto-integrate, main must CONTAIN the orphan commit (merged --no-ff): $out_a"
[[ "$(git -C "$RA" rev-parse main)" != "$main_before" ]] \
  || fail "(a) main must have ADVANCED after auto-integrate: $out_a"
pass "(a) complete + clean-merge + non-diverged + green suite → auto-integrated"

# ============================================================================================
# (b1) RED suite → NOT integrated; orphan left parked + surfaced (main UNCHANGED).
# ============================================================================================
RB="$tmp/r_red"; build_case "$RB" 2b2b "feature body"
main_before_b="$(git -C "$RB" rev-parse main)"
if out_b="$(RELAY_SUITE_CMD=false "$AI" --repo "$RB" --orphan-branch "relay/orphan/deadrun-2b2b" --main-branch main 2>&1)"; then rc_b=0; else rc_b=$?; fi
[[ "$rc_b" -ne 0 ]] \
  || fail "(b1) a RED post-merge suite must BLOCK auto-integrate (nonzero exit), got exit 0: $out_b"
[[ "$(git -C "$RB" rev-parse main)" == "$main_before_b" ]] \
  || fail "(b1) main must be UNCHANGED when the suite is red (no force-merge): $out_b"
git -C "$RB" rev-parse -q --verify "relay/orphan/deadrun-2b2b" >/dev/null \
  || fail "(b1) the orphan branch must remain PARKED (intact) when integrate is refused: $out_b"
printf '%s' "$out_b" | grep -qiE "surface|reconcile|park" \
  || fail "(b1) a refused integrate must SURFACE for human /relay reconcile: $out_b"
pass "(b1) red post-merge suite → NOT integrated; orphan left parked + surfaced"

# ============================================================================================
# (b2) CONFLICTING merge → NOT integrated; orphan left parked + surfaced (main UNCHANGED).
#      (Suite is green here — the merge conflict alone must block, never an auto-resolve.)
# ============================================================================================
RC="$tmp/r_conflict"; build_case "$RC" 3c3c "orphan body" --main-touch "main body"
main_before_c="$(git -C "$RC" rev-parse main)"
if out_c="$(RELAY_SUITE_CMD=true "$AI" --repo "$RC" --orphan-branch "relay/orphan/deadrun-3c3c" --main-branch main 2>&1)"; then rc_c=0; else rc_c=$?; fi
[[ "$rc_c" -ne 0 ]] \
  || fail "(b2) a CONFLICTING orphan must BLOCK auto-integrate (nonzero exit), got exit 0: $out_c"
[[ "$(git -C "$RC" rev-parse main)" == "$main_before_c" ]] \
  || fail "(b2) main must be UNCHANGED on a merge conflict (clean abort, never auto-resolve): $out_c"
git -C "$RC" rev-parse -q --verify "relay/orphan/deadrun-3c3c" >/dev/null \
  || fail "(b2) the orphan branch must remain PARKED on conflict: $out_c"
# tree must be left clean (conflict aborted, no dangling MERGE_HEAD)
[[ -z "$(git -C "$RC" status --porcelain)" ]] \
  || fail "(b2) working tree must be CLEAN after a conflict abort (no half-merge left behind): $out_c"
pass "(b2) conflicting orphan → NOT integrated; clean abort; orphan left parked + surfaced"

echo "ALL PASS: bounded auto-integrate completes only complete+clean+non-diverged+green orphans; everything else stays parked + surfaced (id:1048)"
