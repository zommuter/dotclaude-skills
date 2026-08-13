#!/usr/bin/env bash
# roadmap:259f — classify.sh's GATE detector must be WORD-BOUNDARY anchored, not a bare
# substring match. (This IS a promoted ROADMAP item, so the header carries its id; once the
# box in ROADMAP.md is ticked, failures here count as real. While it is unticked this file
# is EXPECTED-RED — it is the spec for the open item.)
#
# DEFECT (found 2026-08-13, id:259f): the gate-text check in meeting/classify.sh is
#   grep -qiE 'gated?|gate:|reopen (gate|trigger)|condition-triggered|blocked on'
# `gated?` has no word boundary, so ANY item body containing the substring "gate" is flagged
# GATED — investigate / mitigate / aggregate / delegate / navigate are all ordinary TODO
# prose, "investigate" in particular. Such an item then gets a spurious `[GATED]` marker
# appended by SKILL.md step 3 in every /meeting bucket summary.
#
# This is deliberately NOT covered by test_classify_disposition_contract_3bf3.sh, whose
# fixtures are worded AROUND the defect (they avoid every "gate"-containing word on purpose,
# noted in that file). Pinning current behaviour there would encode the defect as intended;
# this file drives the fix instead.
#
# FIX (executor): tighten the pattern to word-boundary forms — `\bgated?\b` for the bare
# alternative, and audit the others similarly (`\bgate:` is already effectively anchored by
# the colon). The genuine gate phrases ("gated on X", "blocked on X", "reopen gate") MUST
# still yield GATED.
#
# Triangulated (id:108e): five DISTINCT false-positive words plus two DISTINCT true-positive
# phrases, so special-casing any one input cannot pass the file — the real word-boundary
# behaviour is the cheapest way to satisfy all seven.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/classify.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "classify.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/meeting-notes"

cat > "$TMP/TODO.md" <<'EOF'
# TODO

## Current

- [ ] **We should investigate the flaky retry path** before the next release. <!-- id:0001 -->
- [ ] **Mitigate the memory spike** in the batch importer. <!-- id:0002 -->
- [ ] **Aggregate the per-repo counts** into one dashboard row. <!-- id:0003 -->
- [ ] **Delegate the nightly sweep** to the mechanical daemon. <!-- id:0004 -->
- [ ] **Navigate the new onboarding flow** end to end and note friction. <!-- id:0005 -->
- [ ] **This work is gated on the upstream schema landing** first. <!-- id:0006 -->
- [ ] **Blocked on a credential** the owner has not yet provided. <!-- id:0007 -->
EOF

out="$("$SH" "$TMP")"
[[ -n "$out" ]] || fail "classify.sh produced no output for the fixture"

gate() { printf '%s\n' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $5}'; }

# --- False positives: a body that merely CONTAINS the substring "gate" must NOT be GATED ---
for pair in \
  "0001 investigate" "0002 mitigate" "0003 aggregate" "0004 delegate" "0005 navigate"; do
  id="${pair%% *}"; word="${pair##* }"
  g="$(gate "$id")"
  [[ "$g" == "" ]] || fail "'$word' contains the substring 'gate' but must yield an EMPTY gate; got '$g' (id:$id)"
  pass "'$word' → empty GATE (word-boundary, not substring)"
done

# --- True positives: genuine gate/blocked phrases must STILL be GATED ---
[[ "$(gate 0006)" == "GATED" ]] || fail "'gated on …' must still yield GATED, got '$(gate 0006)'"
pass "'gated on …' → GATED (real gate phrase preserved)"
[[ "$(gate 0007)" == "GATED" ]] || fail "'blocked on …' must still yield GATED, got '$(gate 0007)'"
pass "'blocked on …' → GATED (real gate phrase preserved)"

echo "ALL PASS: classify.sh gate detector is word-boundary anchored (id:259f)"
