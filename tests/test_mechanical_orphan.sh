#!/usr/bin/env bash
# roadmap:1bd1 — relay-doctor "mechanical-orphan" check: an OPEN `[MECHANICAL]` ROADMAP
# item whose recipe was never authored (or was lost) sits with a pool-inert `mechanical`
# verdict forever and silently never runs (handoff.md:77-92 names exactly this failure
# mode; nothing detects it). This is the LOUD, report-only detector id:1bd1 builds.
#
# Correlation: a recipe JSON's `id` field (recipe-manifest.md schema) names the ROADMAP
# item's `<!-- id:XXXX -->` token it executes — that is the ONLY explicit id-linkage field
# in the schema, so this check matches on it (not on filename, which is unconstrained).
# A recipe counts as "authored" if it is present in ANY of pending/running/done — a
# recipe already consumed and moved to done/ still means the item WAS fed; only "no
# recipe anywhere in the drop-dir" is the orphan.
#
# Hermetic: mktemp -d repo + mktemp -d recipe root, RELAY_RECIPE_DIR override, no
# ~/.config/relay, no network. RED until relay-doctor.sh grows the mechanical-orphan check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-doctor.sh not executable at $SH"

FIX="$(mktemp -d)"
RECIPES="$(mktemp -d)"
trap 'rm -rf "$FIX" "$RECIPES"' EXIT

mkdir -p "$RECIPES/pending" "$RECIPES/running" "$RECIPES/done"

git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st
git -C "$FIX" config user.name t

write_recipe() {
  local dir="$1" id="$2"
  cat >"$dir/recipe-$id.json" <<JSON
{
  "id": "$id",
  "repo": "fixrepo",
  "cmd": "echo hi",
  "host": "any",
  "est_wall": 60,
  "resource": "none",
  "acceptance_artifact": "/tmp/artifact-$id"
}
JSON
}

# (a) open [MECHANICAL] item with NO recipe anywhere -> reported as orphan.
# (b) open [MECHANICAL] item WITH a recipe (in done/) -> NOT reported.
# (c) CLOSED [x] [MECHANICAL] item with no recipe -> NOT reported (only open items matter).
# (d) non-[MECHANICAL] open item with no recipe -> NOT reported.
cat >"$FIX/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [MECHANICAL] orphaned mechanical item, no recipe anywhere <!-- id:a001 -->
- [ ] [MECHANICAL] fed mechanical item, recipe lives in done/ <!-- id:a002 -->
- [x] [MECHANICAL] closed mechanical item, no recipe (irrelevant, already done) <!-- id:a003 -->
- [ ] [ROUTINE] an ordinary routine item, no recipe (irrelevant, not MECHANICAL) <!-- id:a004 -->
MD
git -C "$FIX" add -A
git -C "$FIX" commit -qm init

# Only id:a002 gets an authored recipe, dropped straight into done/ (already consumed).
write_recipe "$RECIPES/done" "a002"

out="$(RELAY_RECIPE_DIR="$RECIPES" "$SH" "$FIX" 2>/dev/null)"

echo "$out" | grep -q 'mechanical-orphan' \
  || fail "relay-doctor output has no mechanical-orphan check section:\n$out"

echo "$out" | grep -q 'id:a001' \
  || fail "(a) orphaned open [MECHANICAL] item id:a001 (no recipe anywhere) must be reported:\n$out"
pass "(a) open [MECHANICAL] item with no authored recipe anywhere is reported as orphan"

echo "$out" | grep -q 'id:a002' \
  && fail "(b) id:a002 has a recipe in done/ — must NOT be reported as orphan:\n$out"
pass "(b) open [MECHANICAL] item with a recipe present (even in done/) is not reported"

echo "$out" | grep -q 'id:a003' \
  && fail "(c) id:a003 is CLOSED — must NOT be reported even though it has no recipe:\n$out"
pass "(c) closed [x] [MECHANICAL] item with no recipe is not reported"

echo "$out" | grep -q 'id:a004' \
  && fail "(d) id:a004 is not [MECHANICAL] — must NOT be reported:\n$out"
pass "(d) non-[MECHANICAL] open item with no recipe is not reported"

# report-only: relay-doctor still exits 0 despite the orphan finding.
RELAY_RECIPE_DIR="$RECIPES" "$SH" "$FIX" >/dev/null 2>&1 \
  || fail "relay-doctor must stay report-only (exit 0) even with a mechanical-orphan finding"
pass "report-only: exit 0 despite the mechanical-orphan finding"

# --strict escalates: nonzero exit when a mechanical-orphan is found.
rc=0
RELAY_RECIPE_DIR="$RECIPES" "$SH" --strict "$FIX" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "--strict must exit nonzero when a mechanical-orphan is found; got 0"
pass "--strict escalates the mechanical-orphan finding to a nonzero exit"

echo "ALL PASS: id:1bd1 relay-doctor mechanical-orphan check"
