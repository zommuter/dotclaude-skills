#!/usr/bin/env bash
# roadmap:3add — ONE shared anchored id/token extraction helper (lib-anchored-id.sh),
# modelled on scan-routed.sh's anchoring, that consolidates the 4th-instance family of
# hand-rolled anchored checks: roadmap-lint's first-match id_re, unpromoted-scan's bare
# grep, inbox-done's substring match, md-merge's fail-open append.
#
# lib-anchored-id.sh already carries the "extract an item's OWN id from a line" shape
# (own_id_of_line / has_own_id_marker, id:521f). This item adds the SECOND shape those
# callers also hand-roll: the ROUTED-token extraction variant, and the "does a SPECIFIC
# KNOWN token appear as an anchored `(id|routed):XXXX` marker" presence check that
# scan-routed.sh's twin check (its line ~244) already does correctly — anchored on the
# marker + a token boundary, NOT a bare substring that false-matches meeting-note HHMM
# timestamps or a hash containing the same 4 hex chars.
#
# RED until lib-anchored-id.sh exports: own_routed_of_line, own_token_of_line,
# token_marker_in_text, token_marker_in_files, token_own_checkbox_marker_in_text.
#
# Hermetic: temp fixtures under mktemp -d; no network, no ~/.claude, no real repos.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC_DIR/relay/scripts/lib-anchored-id.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LIB" ]] || fail "lib-anchored-id.sh not found at $LIB"
# shellcheck source=/dev/null
source "$LIB"

for fn in own_id_of_line has_own_id_marker \
          own_routed_of_line own_token_of_line \
          token_marker_in_text token_marker_in_files \
          token_own_checkbox_marker_in_text; do
  declare -F "$fn" >/dev/null || fail "helper function '$fn' is not defined by lib-anchored-id.sh"
done
pass "all expected helper functions are defined"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- own_id_of_line (regression guard for the existing id:521f behaviour) ------
got="$(own_id_of_line '- [ ] cites dep: id:1643 <!-- id:4148 -->')"
[[ "$got" == "id:4148" ]] || fail "own_id_of_line returned own id from the trailing marker; got '$got' (want id:4148)"
pass "own_id_of_line ignores prose-cited id, returns the trailing marker"

own_id_of_line '- [ ] no own marker, only prose id:1643' && fail "own_id_of_line matched a bare prose id (should return 1)"
pass "own_id_of_line rejects a bare prose id with no HTML-comment marker"

# --- own_routed_of_line: the routed-token extraction variant --------------------
got="$(own_routed_of_line '- [ ] [zkm] ingest something (from meeting) <!-- routed:4fa9 -->')"
[[ "$got" == "routed:4fa9" ]] || fail "own_routed_of_line got '$got' (want routed:4fa9)"
pass "own_routed_of_line extracts the trailing routed marker"

# A sibling item may CITE another routed token in prose while its OWN marker differs —
# extraction must return the OWN marker, never the cited one.
got="$(own_routed_of_line '- [ ] contrast with routed:1234 is the signal <!-- routed:4fa9 -->')"
[[ "$got" == "routed:4fa9" ]] || fail "own_routed_of_line matched the prose-cited routed token; got '$got' (want routed:4fa9)"
pass "own_routed_of_line ignores a prose-cited routed token"

own_routed_of_line '- [ ] no routed marker here <!-- id:4148 -->' && fail "own_routed_of_line matched an id marker (should return 1)"
pass "own_routed_of_line does not match an id: marker"

# --- own_token_of_line: id-or-routed, reporting the kind ------------------------
got="$(own_token_of_line '- [ ] item <!-- id:4148 -->')"
[[ "$got" == "id:4148" ]] || fail "own_token_of_line id case got '$got'"
got="$(own_token_of_line '- [ ] item <!-- routed:4fa9 -->')"
[[ "$got" == "routed:4fa9" ]] || fail "own_token_of_line routed case got '$got'"
own_token_of_line '- [ ] only prose id:1643 no comment marker' && fail "own_token_of_line matched bare prose"
pass "own_token_of_line reports the kind (id/routed) of the trailing marker"

# --- token_marker_in_text: KNOWN-token anchored presence (scan-routed twin) -----
# The exact false-match scan-routed.sh guards against: a meeting-note filename timestamp
# `YYYY-MM-DD-HHMM` whose HHMM field equals the token. A bare substring grep says "present";
# the anchored check must say ABSENT.
blob_ts='see docs/meeting-notes/2026-06-30-0928-foo.md for context'
if printf '%s' "$blob_ts" | token_marker_in_text 0928; then
  fail "token_marker_in_text false-matched an HHMM timestamp (0928) as a present token — that is the bare-substring bug this helper exists to prevent"
fi
pass "token_marker_in_text ignores an HHMM-timestamp substring collision"

# A real anchored marker IS found.
printf '%s' '- [ ] item <!-- id:0928 -->' | token_marker_in_text 0928 \
  || fail "token_marker_in_text missed a genuine <!-- id:0928 --> marker"
printf '%s' '- [ ] item <!-- routed:0928 -->' | token_marker_in_text 0928 \
  || fail "token_marker_in_text missed a genuine <!-- routed:0928 --> marker"
# A `children:`/`gated-on:` edge is NOT an id/routed marker → must NOT match.
if printf '%s' 'children:0928,1abc anchored citation' | token_marker_in_text 0928; then
  fail "token_marker_in_text matched a children: edge token — only id:/routed: prefixes count"
fi
pass "token_marker_in_text finds genuine id:/routed: markers and ignores children: edges"

# It must NOT match a longer hex run that merely CONTAINS the token (boundary anchor).
if printf '%s' 'id:0928abcd' | token_marker_in_text 0928; then
  fail "token_marker_in_text matched 'id:0928abcd' — the trailing-boundary anchor is missing"
fi
pass "token_marker_in_text respects the trailing token boundary"

# --- token_marker_in_files: same check over one or more files (scan-routed form) -
todo="$tmp/TODO.md"; road="$tmp/ROADMAP.md"
printf '# TODO\n- [ ] unrelated item <!-- id:aaaa -->\n' >"$todo"
printf '# ROADMAP\n- [ ] the twin lives here <!-- routed:4fa9 -->\n' >"$road"
token_marker_in_files 4fa9 "$todo" "$road" || fail "token_marker_in_files missed the twin in ROADMAP.md"
token_marker_in_files bbbb "$todo" "$road" && fail "token_marker_in_files matched an absent token"
# Missing file must not crash the check (scan-routed greps with -s).
token_marker_in_files 4fa9 "$todo" "$road" "$tmp/nope.md" || fail "token_marker_in_files broke on a missing file arg"
pass "token_marker_in_files anchors over multiple files, tolerates a missing file"

# --- token_own_checkbox_marker_in_text: unpromoted-scan's checkbox-own shape ----
# The token must be some CHECKBOX line's OWN `<!-- id:XXXX -->` marker, not a bare
# prose citation inside another item's text (id:1312 false-match class).
prose_only='- [ ] a separate seam tracked as id:2b63 in another items body <!-- id:9999 -->'
printf '%s' "$prose_only" | token_own_checkbox_marker_in_text 2b63 \
  && fail "token_own_checkbox_marker_in_text matched a bare prose citation (id:1312 bug)"
pass "token_own_checkbox_marker_in_text ignores a prose-only citation"

printf '%s' '- [ ] real open item <!-- id:2b63 -->' | token_own_checkbox_marker_in_text 2b63 \
  || fail "token_own_checkbox_marker_in_text missed an open checkbox owning the id"
printf '%s' '- [x] a done item <!-- id:2b63 -->' | token_own_checkbox_marker_in_text 2b63 \
  || fail "token_own_checkbox_marker_in_text missed a DONE checkbox owning the id"
# Trailing prose after the marker (id:798d: not end-anchored) still counts.
printf '%s' '- [ ] gated item <!-- id:2b63 --> — GATED (auto, id:3801)' | token_own_checkbox_marker_in_text 2b63 \
  || fail "token_own_checkbox_marker_in_text should tolerate trailing prose after the marker"
pass "token_own_checkbox_marker_in_text matches open/done checkbox-own markers, allows trailing prose"

# --- input validation: a non-4-hex token is a loud reject, not a silent pass ----
set +e
printf '%s' 'anything <!-- id:abcd -->' | token_marker_in_text 'zzz'
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "token_marker_in_text should return 2 on a malformed token; got $rc"
pass "token_marker_in_text loud-rejects a malformed token (rc=2)"

echo "ALL PASS"
