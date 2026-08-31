#!/usr/bin/env bash
# roadmap:d0aa — em-dash delimiter migration S6: classify.sh's lane floor must route a
# hyphen-delimited lane tag (`[HARD - pool]`, `[INPUT - meeting]`, …) IDENTICALLY to its
# em-dash twin (`[HARD — pool]`, `[INPUT — meeting]`, …). classify.sh's lane extraction
# (meeting/classify.sh:144, `grep -oE '\[(HARD|INPUT|ROUTINE|MECHANICAL)[^]]*\]'`) captures
# the whole bracket regardless of delimiter, and the routing `case` (:151-204) matches by
# SUBSTRING on the lane word (`*pool*`, `*meeting*`, …), not on the delimiter byte — so this
# test pins that the already-delimiter-agnostic behaviour holds, one fixture per lane.
#
# Hermetic: mktemp fixtures only, never touches ~/.claude or the network.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/classify.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "classify.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [HARD - pool] **Pool item, hyphen-delimited** — executor work. <!-- id:d001 -->
- [ ] [HARD - hands] **Hands item, hyphen-delimited** — human runs it. <!-- id:d002 -->
- [ ] [HARD - meeting] **Meeting item, hyphen-delimited** — needs a design session. <!-- id:d003 -->
- [ ] [HARD - decision gate] **Auto-gate alias, hyphen-delimited**. <!-- id:d004 -->
- [ ] [INPUT - meeting] **Meeting item, hyphen new-vocab**. <!-- id:d005 -->
- [ ] [INPUT - decision] **Decision item, hyphen new-vocab**. <!-- id:d006 -->
- [ ] [INPUT - access] **Access item, hyphen new-vocab**. <!-- id:d007 -->
- [ ] [INPUT - author] **Author item, hyphen new-vocab**. <!-- id:d008 -->
- [ ] [INPUT - nonsense] **Unrecognized hyphen lane** — must still LOUD-reject. <!-- id:d009 -->
EOF

out="$("$SH" "$TMP")"

cls()  { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $1}'; }
gate() { printf '%s' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $5}'; }

[[ "$(cls d001)" == "POOL"  ]] || fail "[HARD - pool] must be POOL, got '$(cls d001)'"
pass "[HARD - pool] → POOL (matches em-dash twin)"

[[ "$(cls d002)" == "HANDS" ]] || fail "[HARD - hands] must be HANDS, got '$(cls d002)'"
pass "[HARD - hands] → HANDS (matches em-dash twin)"

[[ "$(cls d003)" == "C3" ]] || fail "[HARD - meeting] must be C3, got '$(cls d003)'"
pass "[HARD - meeting] → C3 (matches em-dash twin)"

[[ "$(cls d004)" == "C3" ]] || fail "[HARD - decision gate] must be C3, got '$(cls d004)'"
[[ "$(gate d004)" != *HARD-NOLANE* ]] || fail "[HARD - decision gate] must not be HARD-NOLANE"
pass "[HARD - decision gate] → C3 (matches em-dash twin)"

[[ "$(cls d005)" == "C3" ]] || fail "[INPUT - meeting] must be C3, got '$(cls d005)'"
pass "[INPUT - meeting] → C3 (matches em-dash twin)"

[[ "$(cls d006)" == "HUMAN" ]] || fail "[INPUT - decision] must be HUMAN, got '$(cls d006)'"
pass "[INPUT - decision] → HUMAN (matches em-dash twin)"

[[ "$(cls d007)" == "HANDS" ]] || fail "[INPUT - access] must be HANDS, got '$(cls d007)'"
pass "[INPUT - access] → HANDS (matches em-dash twin)"

[[ "$(cls d008)" == "HANDS" ]] || fail "[INPUT - author] must be HANDS, got '$(cls d008)'"
pass "[INPUT - author] → HANDS (matches em-dash twin)"

[[ "$(cls d009)" == "C3" ]] || fail "unrecognized hyphen lane must be C3, got '$(cls d009)'"
[[ "$(gate d009)" == *HARD-NOLANE* ]] || fail "unrecognized hyphen lane must be HARD-NOLANE, got '$(gate d009)'"
pass "[INPUT - nonsense] → C3 + HARD-NOLANE (loud reject holds for hyphen too)"

echo "ALL PASS"
