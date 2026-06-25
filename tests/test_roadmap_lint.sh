#!/usr/bin/env bash
# roadmap:09a3 — roadmap-lint.sh is a GRAMMAR validator for open ROADMAP items.
#
# WHY (audit 2026-06-23, user directive): rather than detecting a fixed list of
# SPECIFIC known issues, the relay should reject ANYTHING that doesn't match the
# proper open-item syntax (415b grammar-tightening-with-loud-rejection). gather
# already LOUD-rejects an untagged `[HARD]`, but it is blind to (a) an open `- [ ]`
# item with NO class tag at all (e.g. meeting-rpg id:0951, a freshly-minted `[SEVERE]`
# item with no relay lane — invisible to BOTH the loop AND human triage), and (b)
# items carrying a malformed/unknown lane outside the `[HARD]` family. A positive
# grammar catches every deviation, not just the ones we thought to look for.
#
# The grammar (an open `- [ ]` item under an ACTIVE section must match ALL of):
#   1. a recognized class/lane tag — `[ROUTINE]` OR one of the hard-lanes.md lanes
#      (`[HARD — pool|meeting|hands|decision gate]`), optionally combined with an
#      `[INTENSIVE — <resource>]` modifier;
#   2. an `id:XXXX` (4-hex) token.
# Items under a GATED / DEFERRED / DONE / ICEBOX / ARCHIVE heading are EXEMPT
# (explicitly parked — not executor-classifiable by design).
#
# The lint reports EVERY non-conforming active open item generically (it does not
# hunt for a specific defect class) and exits nonzero when any are found; a fully
# conforming ROADMAP is a clean zero-exit no-op.
#
# Hermetic: temp ROADMAP fixtures; no network, no ~/.claude.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$SRC_DIR/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- fixture with conforming + non-conforming items --------------------------
bad="$tmp/ROADMAP.md"
cat >"$bad" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] a well-formed routine item <!-- id:aaaa -->
- [ ] [HARD — pool] a well-formed bounded apex item <!-- id:bbbb -->
- [ ] [HARD — pool] [INTENSIVE — local-llm] a well-formed intensive item <!-- id:cccc -->
- [ ] an item with NO class tag but an id <!-- id:dddd -->
- [ ] [HARD — epic] an item with an UNRECOGNIZED lane <!-- id:eeee -->
- [ ] [ROUTINE] a routine item MISSING its id token entirely
- [x] [ROUTINE] a done item is never linted <!-- id:ffff -->

## Gated / deferred (NOT executor-actionable)

- [ ] a parked feature with no tag and no id — exempt by section <!-- id:9999 -->
EOF

set +e
out="$("$LINT" "$bad" 2>&1)"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || { echo "$out"; fail "lint should exit nonzero when active open items violate the grammar"; }
pass "lint exits nonzero on a ROADMAP with grammar violations"

# Each of the THREE active violations must be reported.
grep -qF 'id:dddd' <<<"$out" || { echo "$out"; fail "missing-class item (id:dddd) not reported"; }
grep -qF 'id:eeee' <<<"$out" || { echo "$out"; fail "unrecognized-lane item (id:eeee) not reported"; }
grep -qF 'MISSING its id token' <<<"$out" || { echo "$out"; fail "missing-id item not reported"; }
pass "all three active grammar violations are reported"

# Conforming items and section-exempt / done items must NOT be flagged.
grep -qF 'id:aaaa' <<<"$out" && { echo "$out"; fail "conforming [ROUTINE] item (id:aaaa) wrongly flagged"; }
grep -qF 'id:cccc' <<<"$out" && { echo "$out"; fail "conforming [INTENSIVE] item (id:cccc) wrongly flagged"; }
grep -qF 'id:9999' <<<"$out" && { echo "$out"; fail "gated-section item (id:9999) wrongly flagged — section exemption broken"; }
grep -qF 'id:ffff' <<<"$out" && { echo "$out"; fail "done [x] item (id:ffff) wrongly flagged"; }
pass "conforming, gated-exempt, and done items are not flagged"

# --- a fully conforming ROADMAP is a clean no-op -----------------------------
good="$tmp/ROADMAP_ok.md"
cat >"$good" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] a well-formed routine item <!-- id:1111 -->
- [ ] [HARD — meeting] a well-formed meeting-lane item <!-- id:2222 -->
- [x] [ROUTINE] a done item <!-- id:3333 -->
EOF

set +e
"$LINT" "$good" >/dev/null 2>&1
rc_ok=$?
set -e
[[ "$rc_ok" -eq 0 ]] || fail "lint should exit zero on a fully conforming ROADMAP"
pass "lint is a clean zero-exit no-op on a conforming ROADMAP"

# --- c095: heading-as-item convention (collaib-shaped) -----------------------
# A `## [LANE] Title <!-- id -->` heading IS the work item; its `- [ ] Open` /
# `- [x] Done` status sub-lines are NOT separate items and must NOT be flagged.
hi="$tmp/heading_item.md"
cat > "$hi" <<'EOF'
# Roadmap

## Items

## [ROUTINE] A heading-as-item that owns its lane+id <!-- id:abcd -->
- [ ] Open
- [x] earlier status

## [HARD — pool] Another heading-item <!-- id:bcde -->
- [ ] Open
EOF
set +e
"$LINT" "$hi" >/dev/null 2>&1
rc_hi=$?
set -e
[[ "$rc_hi" -eq 0 ]] || fail "c095: heading-as-item status sub-lines must NOT be flagged (got nonzero)"
pass "c095: heading-as-item (`## [LANE] … <!-- id -->`) status sub-lines are not flagged"

# But a heading-as-item MISSING its id is still a violation (nothing hides).
hbad="$tmp/heading_item_noid.md"
cat > "$hbad" <<'EOF'
# Roadmap

## Items

## [ROUTINE] A heading-item with NO id token
- [ ] Open
EOF
set +e
out_hbad="$("$LINT" "$hbad" 2>&1)"
rc_hbad=$?
set -e
[[ "$rc_hbad" -ne 0 ]] || fail "c095: a heading-as-item missing its id must be flagged"
grep -qi 'heading-as-item MISSING its id' <<<"$out_hbad" || fail "c095: missing-id heading-item not reported with the right reason:
$out_hbad"
pass "c095: a heading-as-item missing its id IS flagged (positive grammar preserved)"

echo "ALL PASS: roadmap grammar lint (roadmap:09a3) + heading-as-item (id:c095)"
