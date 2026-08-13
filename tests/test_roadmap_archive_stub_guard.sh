#!/usr/bin/env bash
# Defect-fix test (no roadmap item — recurrence-prevention for the routed:f833 escalation,
# loderite id:2ab3-B; filed 2026-08-13). Failures always count.
#
# DEFECT: relay/scripts/roadmap-archive.sh has NO notion of an archived STUB. Its gate at
# `if top_done_re.match(line):` classifies any `- [x]` top-level item as archivable when
# `in_prior or aged_ok`. A stub left behind by a per-repo archiver (or restored by hand) is BY
# CONSTRUCTION `- [x]` + an id, and is in the prior commit — so the generic archiver eats its
# own successor's output: it DELETES the stub from ROADMAP.md and re-appends the body to
# ROADMAP.archive.md, duplicating ids there and re-blinding `orphan-scan --cross-ledger`
# (which reads ONLY the live ROADMAP.md).
#
# REPRODUCED IN THE FLEET, commit-level: loderite id:154a restored 59 stubs at 1dc91f6 (18:41
# 2026-08-13); c9059f0 (18:53, SAME relay run) deleted 58 of them and pushed 125 lines back
# into ROADMAP.archive.md.
#
# SCOPE — this guard is deliberately LANE-INDEPENDENT and does NOT decide routed:f833's open
# (a)/(b) design call (teach the generic script to LEAVE stubs, vs delegate to a per-repo
# archiver when one exists). It only stops the generic script DESTROYING stubs that either
# branch would rely on. Both branches need it: under (a) the stubs it writes must survive the
# next run, and under (b) a per-repo archiver's stubs must survive a generic run.
#
# The stub grammar is loderite's reference implementation, tools/archive-roadmap.mjs:
#   STUB_SUFFIX  = " (archived — see ROADMAP.archive.md)"
#   STUB_LINE_RE = /^- \[x\] .*<!--\s*id:[0-9a-f]{4}\s*-->{SUFFIX}/     (NOT end-anchored)
# The missing end-anchor is load-bearing and is asserted below: real stubs carry trailing
# annotations past the suffix, and anchoring would re-archive exactly those.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "roadmap-archive.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -r -- "$tmp"' EXIT

make_repo() {
    local repo="$1" roadmap_content="$2"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name tester
    printf '%s' "$roadmap_content" > "$repo/ROADMAP.md"
    git -C "$repo" add ROADMAP.md
    git -C "$repo" commit -qm 'seed ROADMAP'
}

SUF=" (archived — see ROADMAP.archive.md)"

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: a plain archived stub is KEPT in ROADMAP.md and NOT re-archived.
# ─────────────────────────────────────────────────────────────────────────────
repo1="$tmp/repo1"
make_repo "$repo1" "# Roadmap

## Items

- [x] **Already archived thing** <!-- id:1a2b -->$SUF
- [x] **A genuinely done item still carrying its body** <!-- id:3c4d -->
  Some continuation line that belongs to it.
- [ ] **An open item** <!-- id:5e6f -->
"

"$SCRIPT" "$repo1" >/dev/null 2>&1 || true

grep -qF 'id:1a2b' "$repo1/ROADMAP.md" \
  || fail "the archived stub (id:1a2b) was REMOVED from ROADMAP.md — the generic archiver ate a stub"
pass "archived stub stays in ROADMAP.md"

if [[ -f "$repo1/ROADMAP.archive.md" ]]; then
  n="$(grep -cF 'id:1a2b' "$repo1/ROADMAP.archive.md" || true)"
  [[ "$n" == "0" ]] || fail "the stub's id was re-appended to ROADMAP.archive.md ($n occurrence(s)) — duplicate re-created"
fi
pass "archived stub is NOT re-appended to ROADMAP.archive.md"

# The non-stub done item MUST still archive — the guard must not disable archiving wholesale.
grep -qF 'id:3c4d' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "a real (non-stub) done item was NOT archived — the guard over-reached"
pass "a real done item still archives (guard is not a blanket disable)"

grep -qF 'id:5e6f' "$repo1/ROADMAP.md" \
  || fail "the open item was removed from ROADMAP.md"
pass "open items untouched"

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: THE ANCHORING CASE — a stub with a trailing annotation past the suffix
# is still a stub. loderite saw this live (bfb3/3d6c/a10c each carry a `**⚠ …`
# annotation after the suffix); an end-anchored regex would re-archive them,
# which is the very defect the guard exists for.
# ─────────────────────────────────────────────────────────────────────────────
repo2="$tmp/repo2"
make_repo "$repo2" "# Roadmap

## Items

- [x] **Stub with a trailing annotation** <!-- id:bfb3 -->$SUF **⚠ superseded by id:9999**
- [ ] **An open item** <!-- id:7a8b -->
"

"$SCRIPT" "$repo2" >/dev/null 2>&1 || true

grep -qF 'id:bfb3' "$repo2/ROADMAP.md" \
  || fail "a stub carrying a trailing annotation past the suffix was re-archived (end-anchor regression)"
pass "stub with trailing annotation past the suffix is still recognised (no end-anchor)"

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: IDEMPOTENCE ACROSS RUNS — the property that actually failed in the
# fleet. Archive once, then commit the result and archive again: the stub the
# first run produced (or that was already present) must survive run 2 unchanged,
# and the archive must not grow.
# ─────────────────────────────────────────────────────────────────────────────
repo3="$tmp/repo3"
make_repo "$repo3" "# Roadmap

## Items

- [x] **Pre-existing stub** <!-- id:c0de -->$SUF
- [ ] **Open** <!-- id:d00d -->
"

"$SCRIPT" "$repo3" >/dev/null 2>&1 || true
git -C "$repo3" add -A >/dev/null 2>&1 || true
git -C "$repo3" commit -qm 'after run 1' >/dev/null 2>&1 || true
before_live="$(cat "$repo3/ROADMAP.md")"
before_arch=""
[[ -f "$repo3/ROADMAP.archive.md" ]] && before_arch="$(cat "$repo3/ROADMAP.archive.md")"

"$SCRIPT" "$repo3" >/dev/null 2>&1 || true
after_live="$(cat "$repo3/ROADMAP.md")"
after_arch=""
[[ -f "$repo3/ROADMAP.archive.md" ]] && after_arch="$(cat "$repo3/ROADMAP.archive.md")"

[[ "$before_live" == "$after_live" ]] \
  || fail "second run mutated ROADMAP.md — the stub was consumed on a later run (the loderite recurrence)"
[[ "$before_arch" == "$after_arch" ]] \
  || fail "second run grew ROADMAP.archive.md — duplicate re-created across runs"
pass "idempotent across runs: a stub survives repeated archiving, archive does not grow"

echo "ALL PASS"
