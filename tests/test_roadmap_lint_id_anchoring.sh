#!/usr/bin/env bash
# roadmap:521f — roadmap-lint.sh must extract an item's id from its OWN canonical trailing
# `<!-- id:XXXX -->` marker, NOT via an unanchored first-match grep over the whole line.
#
# The defect: `id_re='id:[0-9a-fA-F]{4}'` (line ~217) used with bash `=~` (lines 270/294/
# 323/434/447) matches the FIRST `id:XXXX` on the line. Prose-bearing items routinely cite
# OTHER tokens ("dep: id:1643", "supersedes id:2b63") BEFORE their own trailing marker, so:
#
#   (1) MISATTRIBUTION — an item whose prose cites another id reports its violation under
#       that CITED id, sending a human to the wrong item (confirmed: zkWhale ROADMAP id:4148
#       reports as [id:1643]).
#   (2) FALSE-NEGATIVE — clause 2 ("has an id token") is satisfied by ANY id on the line, so
#       an item with NO own marker passes clean if its prose merely cites some other token.
#       The loud-reject that is this lint's whole purpose never fires.
#
# This is the SAME unanchored-token-grep hazard class as id:1312 (unpromoted-scan's twin
# check) and the `inbox-done` substring match — scan-routed.sh and (since id:1312)
# unpromoted-scan.sh both anchor to the trailing marker; roadmap-lint never got the fix.
#
# RED until extraction is anchored to the canonical trailing `<!-- id:XXXX -->` comment
# (prefer LAST-match / comment-anchored). NOTE (id:521f): three call sites now hand-roll
# this same anchored extraction — prefer factoring ONE shared helper over a third copy.
#
# Hermetic: temp ROADMAP fixtures; no network, no ~/.claude, no real repos.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$SRC_DIR/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- (1) MISATTRIBUTION -------------------------------------------------------
# An item with a genuine violation (no class tag) whose prose cites ANOTHER id before its
# own trailing marker. The violation must be attributed to its OWN id (4148), not the
# cited one (1643).
mis="$tmp/ROADMAP_mis.md"
cat >"$mis" <<'EOF'
# Roadmap

## Items

- [ ] an item with NO class tag whose prose cites dep: id:1643 <!-- id:4148 -->
EOF

out_mis="$("$LINT" "$mis" 2>&1)"

# Assert on the REPORT HEADER line (`  - [id:XXXX] <reason>`) only — the lint also echoes
# the raw source line underneath, which necessarily contains BOTH tokens, so a whole-output
# grep would pass vacuously.
hdr="$(grep -E '^[[:space:]]*- \[id:[0-9a-fA-F]{4}\]' <<<"$out_mis" || true)"
[[ -n "$hdr" ]] || fail "(1) no '- [id:XXXX]' report header found in output:
$out_mis"

grep -qF '[id:4148]' <<<"$hdr" \
  || fail "(1) violation attributed to the CITED id instead of the item's own trailing marker (id:521f) — expected [id:4148]; got: $hdr"
pass "misattribution: violation reported under the item's own id (4148)"

grep -qF '[id:1643]' <<<"$hdr" \
  && fail "(1) report header names the prose-cited id:1643 — an unanchored first-match extraction; got: $hdr"
pass "misattribution: the prose-cited id:1643 is not used as the item's identity"

# --- (2) FALSE-NEGATIVE -------------------------------------------------------
# An item with a recognized lane tag but NO own id marker, whose prose cites another id.
# Clause 2 must still LOUD-reject it as missing an id.
fn="$tmp/ROADMAP_fn.md"
cat >"$fn" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] an item with NO own id token whose prose cites dep: id:1643
EOF

set +e
out_fn="$("$LINT" "$fn" 2>&1)"
rc_fn=$?
set -e

[[ "$rc_fn" -ne 0 ]] \
  || fail "(2) lint exited CLEAN on an item with no own id marker — its prose citation of id:1643 satisfied the unanchored id check, so the loud-reject never fired (id:521f):
$out_fn"
pass "false-negative: an item with no own id marker is still rejected"

grep -qiE 'id' <<<"$out_fn" \
  || fail "(2) missing-id item reported without naming the id clause: $out_fn"
pass "false-negative: the missing-id violation is reported"

# --- (3) CONTROL: a conforming item citing another id stays clean -------------
# Anchoring must not over-correct into false POSITIVES: a well-formed item is allowed to
# cite other tokens in its prose.
ok="$tmp/ROADMAP_ok.md"
cat >"$ok" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] a conforming item whose prose cites dep: id:1643 <!-- id:4148 -->
- [x] [ROUTINE] a done item citing id:1643 <!-- id:5555 -->
EOF

set +e
out_ok="$("$LINT" "$ok" 2>&1)"
rc_ok=$?
set -e

[[ "$rc_ok" -eq 0 ]] \
  || fail "(3) CONTROL: a conforming item that merely CITES another id was flagged — anchoring over-corrected into a false positive:
$out_ok"
pass "control: a conforming item citing another id in prose is clean"

echo "ALL PASS"
