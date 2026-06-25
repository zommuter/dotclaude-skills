#!/usr/bin/env bash
# roadmap:2dea — unpromoted-scan.sh: list OPEN TODO.md ids with NO ROADMAP twin,
# LANE-TAG-AGNOSTIC (the gap that stranded truncocraft's untagged backlog while the
# repo read as "drained"). Second instance of id:78ff. Report-only TSV; the disposition
# column distinguishes promote (executable lane) from surface (untagged/meeting → triage).
#
# RED until the scanner + wiring land. Hermetic: a fixture repo with
#   (a) closed ROADMAP + an open UNTAGGED TODO id with no twin → reported (surface)
#   (b) an open TODO id WITH a ROADMAP twin → clean (not reported)
#   (c) a meeting-lane / blocked TODO with no twin → reported as surface (not auto-promote)
#   (d) an open [ROUTINE] TODO id with no twin → reported as promote
# plus: a bad flag is a loud nonzero reject (misuse), and a clean repo exits 0.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/unpromoted-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "unpromoted-scan.sh not found at $SH"
[[ -x "$SH" ]] || fail "unpromoted-scan.sh not executable"
bash -n "$SH" || fail "unpromoted-scan.sh fails bash -n"
pass "unpromoted-scan.sh exists, executable, parses"

# (0) Misuse: an unknown flag exits nonzero (loud reject, not report-only).
rc=0; "$SH" --definitely-not-a-flag >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "an unknown flag must exit nonzero (misuse reject); got 0"
pass "unknown flag exits nonzero (misuse reject)"

# --- fixture repo --------------------------------------------------------------
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t

# ROADMAP fully [x]-closed (the "drained"-looking state) — only bbbb has a twin here.
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [x] [ROUTINE] a long-done routine item <!-- id:bbbb -->
EOF

# TODO holds open backlog with no ROADMAP twin (except bbbb).
cat > "$FIX/TODO.md" <<'EOF'
# TODO

## Current
- [ ] (a) untagged raw backlog the pool can't see <!-- id:aaaa -->
- [ ] (b) already promoted — has a ROADMAP twin [ROUTINE] <!-- id:bbbb -->
- [ ] (c) needs a design meeting first [HARD — meeting] <!-- id:cccc -->
- [ ] (d) plain routine, never promoted [ROUTINE] <!-- id:dddd -->
- [x] (e) closed in TODO — not open, must be ignored <!-- id:eeee -->
- [ ] (f) favicon-class: an open checkbox item with NO id token at all
EOF
git -C "$FIX" add -A; git -C "$FIX" commit -qm init

# (1) Report-only: a repo with un-promoted backlog still exits 0.
rc=0; out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: must exit 0 even with findings; got $rc"
pass "report-only (exit 0 with findings)"

# (a) untagged, no twin → reported, disposition surface.
grep -qP '\taaaa\tsurface\t' <<<"$out" || fail "(a) untagged un-twinned id aaaa not reported as surface:
$out"
pass "(a) untagged TODO with no ROADMAP twin → reported (surface)"

# (b) has a ROADMAP twin → NOT reported.
grep -qP '\tbbbb\t' <<<"$out" && fail "(b) id bbbb has a ROADMAP twin but was reported:
$out"
pass "(b) TODO id WITH a ROADMAP twin → clean (not reported)"

# (c) meeting-lane, no twin → reported as surface (NOT promote).
grep -qP '\tcccc\tsurface\t' <<<"$out" || fail "(c) meeting-lane id cccc not reported as surface (must not auto-promote):
$out"
grep -qP '\tcccc\tpromote\t' <<<"$out" && fail "(c) meeting-lane id cccc must NOT be promote (no guessed-lane auto-promote)"
pass "(c) meeting-lane/blocked TODO → reported as surface, not auto-promote"

# (d) executable [ROUTINE] lane, no twin → reported as promote.
grep -qP '\tdddd\tpromote\t' <<<"$out" || fail "(d) [ROUTINE] id dddd not reported as promote:
$out"
pass "(d) executable-lane un-twinned TODO → reported (promote)"

# (e) closed [x] TODO line → never reported (only OPEN items are backlog).
grep -qP '\teeee\t' <<<"$out" && fail "(e) closed TODO id eeee must not be reported (not open backlog)"
pass "(e) closed [x] TODO line ignored"

# (f) open checkbox with NO id token → reported as untracked, id column ----
#     (the favicon-class blind spot from the truncocraft evidence).
grep -qP '\t----\tuntracked\t.*favicon-class' <<<"$out" || fail "(f) id-less open checkbox not reported as untracked:
$out"
pass "(f) open checkbox with no id token → reported (untracked, id column ----)"

# (2) TSV shape: <repo>\t<id>\t<disposition>\t<title>, repo column is the fixture name.
fixbase="$(basename "$FIX")"
grep -qP "^${fixbase}\taaaa\tsurface\t" <<<"$out" || fail "TSV repo column / shape wrong (expected ^$fixbase\\taaaa\\tsurface\\t...):
$out"
pass "TSV shape <repo>\\t<id>\\t<disposition>\\t<title>"

# (3) A truly clean repo (every open TODO id twinned) reports nothing, exits 0.
CLEAN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$CLEAN"' EXIT
git -C "$CLEAN" init -q
git -C "$CLEAN" config user.email t@e.st; git -C "$CLEAN" config user.name t
printf '# Roadmap\n\n- [ ] [ROUTINE] open + twinned <!-- id:abcd -->\n' > "$CLEAN/ROADMAP.md"
printf '# TODO\n\n## Current\n- [ ] open + twinned [ROUTINE] <!-- id:abcd -->\n' > "$CLEAN/TODO.md"
git -C "$CLEAN" add -A; git -C "$CLEAN" commit -qm init
rc=0; cout="$("$SH" "$CLEAN" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "clean repo must exit 0; got $rc"
[[ -z "$(grep -vE '^\s*$' <<<"$cout")" ]] || fail "clean repo must report nothing; got:
$cout"
pass "clean repo (all ids twinned) reports nothing, exits 0"

# --- wiring: relay-doctor surfaces the un-promoted count -------------------------
DOC="$ROOT/relay/scripts/relay-doctor.sh"
grep -q 'unpromoted-scan.sh' "$DOC" || fail "relay-doctor.sh does not invoke unpromoted-scan.sh (wiring missing)"
pass "relay-doctor.sh wires in unpromoted-scan.sh"

# --- wiring: /relay next route ladder gains the un-promoted pre-check ------------
SKILL="$ROOT/relay/SKILL.md"
grep -qiE 'un-?promoted' "$SKILL" || fail "relay/SKILL.md Next-mode ladder does not mention the un-promoted pre-check"
pass "relay SKILL.md Next-mode ladder references the un-promoted pre-check"

echo "ALL PASS: id:2dea un-promoted TODO backlog scan (lane-tag-agnostic) + wiring"
