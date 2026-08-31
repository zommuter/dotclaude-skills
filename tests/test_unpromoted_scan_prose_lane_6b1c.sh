#!/usr/bin/env bash
# roadmap:6b1c — unpromoted-scan.sh's `primary_lane` path 3 must be HEAD-ANCHORED for
# non-bold items, exactly as paths 1 and 2 already are.
#
# The defect (relay/scripts/unpromoted-scan.sh:116-125): after the tag-before-bold-title
# anchor (path 1) and the strict post-bold-title anchor (path 2, id:fb7f), a non-bold item
# falls through to a leftmost-tag-ANYWHERE scan over the WHOLE line. Its stated justification
# — "TODO.md's non-bold prose-summary items carry no genuine tag either way" — is false for
# the `- [ ] [INBOUND routed:XXXX from Y] …` class, which is non-bold, prose-heavy, and
# routinely QUOTES lane tags precisely because such items are bug reports ABOUT lanes.
#
# Two failure directions, and they differ in severity:
#   * a prose `[ROUTINE]` / `[HARD - pool]` makes an UNLANED item read `promote` — a
#     design/decision item offered to the executor queue. This directly violates the
#     script's own acceptance #3 ("NEVER auto-promotes an untagged item with a guessed
#     lane"). Demonstrated live on id:3e14, whose `[ROUTINE]` sat at byte offset 296 inside
#     "while even ONE executor-actionable [ROUTINE] item stays open".
#   * a prose `[INPUT - …]` makes an UNLANED item read `laned`, i.e. "lane already decided,
#     verdict-neutral" — so it never reaches lane-triage at all. This one is SILENT, and it
#     is the one that actually bit: id:be40 picked `[INPUT - access]` from ~offset 132 of the
#     parenthetical "while [INPUT - access] items exist".
#
# Head-anchored `meeting/classify.sh` reads the same lines correctly — the two readers
# disagreeing is the tell.
#
# RED until path 3 accepts a lane tag ONLY in the leading position: immediately after
# `- [ ] `, optionally preceded by one `[INBOUND …]` / `[<target-repo>]` prefix bracket.
# Anything deeper returns empty → disposition `surface`, the conservative default.
#
# NOTE this does NOT overlap tests/test_unpromoted_scan_anchoring.sh (roadmap:1312), which
# guards a different defect entirely — the twin check's `grep -qF "id:$token"`.
#
# Hermetic: one fixture repo under mktemp -d; no network, no ~/.claude, no real registry.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/unpromoted-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "unpromoted-scan.sh not found/executable at $SH"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st
git -C "$FIX" config user.name t

# ROADMAP carries no twins at all, so every TODO item below reaches the disposition logic.
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
EOF

# Six non-bold items. The first three have NO genuine lane (the bracket tokens are prose);
# the last three DO (leading position, with and without an INBOUND prefix).
# aa03 is emitted with printf, not inside the heredoc: its leftmost lane bracket is an
# old-vocab `[HARD - pool]` (deliberately, that is the case under test), and
# hooks/pre-commit-lane-vocab.sh blocks any ADDED source line that begins with a
# checkbox and carries one -- fixture or not.
{
  printf '# TODO\n\n## Current\n'
  cat <<'EOF'
- [ ] [INBOUND routed:1111 from elsewhere] a report about lane grammar — it notes that a repo stalls while even ONE executor-actionable [ROUTINE] item stays open, which is the starvation shape <!-- id:aa01 -->
- [ ] [INBOUND routed:2222 from elsewhere] add a floor to some metric (e.g. 0 sessions in 21 days while [INPUT - access] items exist ⇒ escalation), riding the existing drained-queue ping <!-- id:aa02 -->
EOF
  printf -- '- [ ] a plain non-bold prose item discussing how a %s unit is dispatched unattended by the afk pool <!-- id:aa03 -->\n' '[HARD - pool]'
  cat <<'EOF'
- [ ] [ROUTINE] a genuinely laned non-bold item whose tag leads the body <!-- id:aa04 -->
- [ ] [INPUT - meeting] [INBOUND routed:3333 from elsewhere] a genuinely laned item whose tag leads and is followed by an INBOUND prefix <!-- id:aa05 -->
- [ ] [INBOUND routed:4444 from elsewhere] [ROUTINE] a genuinely laned item whose tag sits immediately after the INBOUND prefix bracket <!-- id:aa06 -->
EOF
} > "$FIX/TODO.md"
git -C "$FIX" add -A
git -C "$FIX" commit -qm init

rc=0
out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: unpromoted-scan.sh must exit 0 even with findings; got $rc"
pass "report-only (exit 0)"

disp_of() {
  awk -F'\t' -v t="$1" '$2 == t { print $3; found=1 } END { if (!found) print "ABSENT" }' <<<"$out"
}

# --- The defect, direction 1: prose [ROUTINE] must NOT promote ---------------------------
# This is acceptance #3 asserted directly: an item with no genuine lane is never `promote`.
d="$(disp_of aa01)"
[[ "$d" == "surface" ]] || fail "aa01 has NO genuine lane ([ROUTINE] is prose at depth) but got disposition '$d' — a lane-less item must be 'surface', never 'promote'/'laned' (acceptance #3)
--- scan output ---
$out"
pass "prose [ROUTINE] at depth does not promote an unlaned item (aa01 → surface)"

# --- The defect, direction 2: prose [INPUT - access] must NOT read as laned --------------
# The silent direction — 'laned' means "lane question already answered", so the item drops
# out of triage forever. This is the exact id:be40 shape.
d="$(disp_of aa02)"
[[ "$d" == "surface" ]] || fail "aa02 has NO genuine lane ([INPUT - access] is prose inside a parenthetical) but got disposition '$d' — it must be 'surface' so lane-triage still sees it
--- scan output ---
$out"
pass "prose [INPUT - access] at depth does not mark an unlaned item as laned (aa02 → surface)"

# --- Same defect on a plain non-bold item with no prefix bracket -------------------------
d="$(disp_of aa03)"
[[ "$d" == "surface" ]] || fail "aa03 has NO genuine lane ([HARD - pool] is prose at depth) but got disposition '$d'
--- scan output ---
$out"
pass "prose [HARD - pool] at depth does not promote a plain non-bold item (aa03 → surface)"

# --- Positive controls: a REAL leading lane must STILL be read --------------------------
# Without these the fix could pass by returning empty for every non-bold item, which would
# silently reclassify the whole non-bold backlog as 'surface'.
d="$(disp_of aa04)"
[[ "$d" == "promote" ]] || fail "aa04 carries a genuine leading [ROUTINE] tag but got disposition '$d' — anchoring must not break true-lane detection
--- scan output ---
$out"
pass "genuine leading [ROUTINE] still promotes (aa04)"

d="$(disp_of aa05)"
[[ "$d" == "laned" ]] || fail "aa05 carries a genuine leading [INPUT - meeting] tag but got disposition '$d'
--- scan output ---
$out"
pass "genuine leading [INPUT - meeting] still reads as laned (aa05)"

# The prefix-bracket allowance: `- [ ] [INBOUND …] [ROUTINE] …` is a real repo shape and
# the tag there IS the item's lane.
d="$(disp_of aa06)"
[[ "$d" == "promote" ]] || fail "aa06 carries a genuine [ROUTINE] tag immediately after its [INBOUND …] prefix bracket but got disposition '$d' — the leading position must allow one prefix bracket
--- scan output ---
$out"
pass "genuine lane immediately after an [INBOUND …] prefix bracket is read (aa06)"

# --- Paths 1 and 2 must be untouched -----------------------------------------------------
cat > "$FIX/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [ROUTINE] **bold-titled, tag before the title** — body mentions [INPUT - access] deep in prose <!-- id:bb01 -->
- [ ] **bold-titled, tag after the title** [ROUTINE] — body mentions [HARD - meeting] deep in prose <!-- id:bb02 -->
- [ ] **bold-titled, NO genuine tag** — body mentions [ROUTINE] only as prose, deep in the line <!-- id:bb03 -->
EOF
git -C "$FIX" add -A
git -C "$FIX" commit -qm bold

rc=0
out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only (bold fixture): got $rc"

d="$(disp_of bb01)"
[[ "$d" == "promote" ]] || fail "bb01 (path 1, tag before bold title) regressed to '$d'"
d="$(disp_of bb02)"
[[ "$d" == "promote" ]] || fail "bb02 (path 2, tag after bold title) regressed to '$d'"
d="$(disp_of bb03)"
[[ "$d" == "surface" ]] || fail "bb03 (path 2, id:fb7f strictness — prose-only tag) regressed to '$d'"
pass "paths 1 and 2 behaviourally unchanged (bb01/bb02/bb03)"

echo "ok"
