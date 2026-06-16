#!/usr/bin/env bash
# roadmap:3313 — D2: scripted, human-invoked `/relay reconcile` mode (meeting 2026-06-16-0938).
# After D1 parks orphans into relay/orphan/*, a human runs `/relay reconcile` to dispose them:
# per parked branch, choose {integrate | discard | leave}. Integration MUST reuse the existing
# verify→`git merge --no-ff`→`ckpt-tag.sh`→`git-lock-push.sh --ff-only` path (so a human can't
# skip the checkpoint tag or race the live pool's push); discard is `git branch -D`. The mode is
# NEVER auto-triggered by the pool. CAS-plumbing merges are forbidden — must be --no-ff (preserves
# 3-way conflict surfacing). Static-structural checks on the reconcile entrypoint.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# The reconcile mode is routed through the relay skill. It may land as a dedicated script
# (relay/scripts/relay-reconcile.sh) or as a documented mode in relay/SKILL.md / references.
# Accept either, but the integrate recipe and the orphan-namespace enumeration must be present.
SKILL="$SRC_DIR/relay/SKILL.md"
REF_DIR="$SRC_DIR/relay/references"
SCRIPT="$SRC_DIR/relay/scripts/relay-reconcile.sh"

# (1) a reconcile entrypoint exists (script or documented mode) carrying the D2 marker.
HAVE=""
for f in "$SCRIPT" "$SKILL" "$REF_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  if grep -q "id:3313" "$f"; then HAVE="$f"; break; fi
done
[[ -n "$HAVE" ]] || fail "no reconcile entrypoint carries the id:3313 (D2) marker"

# (2) it enumerates the relay/orphan/* namespace that D1 parks into.
grep -Eq "relay/orphan/" "$HAVE" \
  || fail "reconcile mode ($HAVE) does not enumerate the relay/orphan/* namespace"

# (3) integration reuses --no-ff merge + ckpt-tag + --ff-only push (no CAS plumbing, no skipped tag).
grep -Eq "merge --no-ff" "$HAVE" \
  || fail "reconcile integrate path does not use 'git merge --no-ff' (CAS plumbing loses conflicts)"
grep -Eq "ckpt-tag" "$HAVE" \
  || fail "reconcile integrate path does not reuse ckpt-tag.sh (human could skip the checkpoint tag)"
grep -Eq "git-lock-push.*--ff-only|--ff-only" "$HAVE" \
  || fail "reconcile integrate path does not push via --ff-only (race with the live pool)"

# (4) discard + leave are offered (it is a per-branch human decision, not auto-integrate).
grep -Eqi "branch -D|discard" "$HAVE" \
  || fail "reconcile mode offers no discard path"

pass "/relay reconcile enumerates relay/orphan/*, integrates via --no-ff+ckpt-tag+--ff-only, offers discard (3313)"
