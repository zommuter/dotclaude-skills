#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:0d7c, filed from meeting note
# `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md` (decision D2 as amended
# by that note's post-closure "Amendment session"). Failures always count.
#
# id:0d7c -- `tools/shrink-acceptance.py` is the GATE that decides whether a ledger
# line-shrink may land. It matters more than the shrinker: loderite ran a real shrink on
# 2026-09-01 that SILENTLY DROPPED FOUR IDS (89f9, a5b6, ba07, ed26) while open-item COUNTS
# were unchanged and its round-trip guard passed green. The body survived in the note file;
# the ADDRESS did not, so `md-merge update-ids` could no longer reach those items.
#
# Contract asserted here:
#   A. An UNCHANGED ledger pair passes (exit 0). A gate that cannot say "nothing broke"
#      is useless, and the head-split shrinker legitimately barely moves ROADMAP.md.
#   B. A BYTE-FIELD change alone does NOT fail. `classify-repo.sh` emits
#      roadmap_bytes/todo_bytes/review_me_bytes, which MUST change; strict verdict
#      equality fails by construction (Fable finding 4).
#   C. A DROPPED id is REFUSED (exit non-zero) -- the loderite shape: an INDENTED line
#      carrying its OWN id, relocated wholesale into the detail file. Nothing else about
#      that fixture is broken, so ONLY the id-set check can catch it. A count is not a set.
#   D. A LOST GATE MARKER is REFUSED. The item's `🚧` is destroyed rather than relocated,
#      the item silently becomes executor-dispatchable, and no detail file carries the
#      glyph -- so the gain is not attributable to a relocated spurious prose hit.
#   E. A REMOVED SPURIOUS PROSE HIT does NOT fail. Same observable movement as D (an item
#      becomes dispatchable), but the token that stopped matching is present verbatim in
#      the item's detail file, proving it was body prose. It must be reported as an
#      IMPROVEMENT, not a failure. C/D/E together are the whole directional predicate.
#   F. A drop in marker OCCURRENCE COUNT with PRESENCE preserved does NOT fail. Measured on
#      a real `--apply` of this repo's ledgers, the lane-tag token count fell 618 -> 562
#      with zero presence-loss, because a marker that appeared twice on a head line is
#      re-appended once and detectors test substring PRESENCE.
#   G. The marker-registry cross-check reports a marker a detector reads that the
#      shrinker's keep-list omits, and `--strict-markers` makes it a refusal.
#
# fails-against: the gate and this spec land in the same commit, so there is no ancestor
# tree to check out; both negative cases are mutations of the shipped tool.
# Case 1 downgrades the orphan finding from FATAL to WARN -- verbatim the loderite
# behaviour, where a dropped id produced no refusal. Fixture C is built so nothing else is
# fatal, so exactly the C assertion fires.
# Case 2 makes the attribution short-circuit to "acceptable", which is what a naive
# directional check does: it waves through every dispatch gain, including a destroyed gate
# marker. Fixture D is the only one whose verdict rests on attribution, so exactly the D
# assertion fires; fixture E stays green under the mutation by construction (it was already
# attributable), which is what makes the pair discriminating rather than a blanket kill.
# fails-against-mutation: sed -i '/id:0d7c ORPHAN-FATAL/{n;s/"FATAL"/"WARN"/}' tools/shrink-acceptance.py
# fails-against-assertion: case C: a DROPPED id must be REFUSED
# fails-against-mutation: sed -i '/id:0d7c ATTRIBUTION/a\    return True, "mutated: attribution disabled"' tools/shrink-acceptance.py
# fails-against-assertion: case D: a DESTROYED gate marker must be REFUSED
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/tools/shrink-acceptance.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

[[ -x "$GATE" ]] || report "sanity: $GATE must exist and be executable"

# run_gate <before-dir> <after-dir> [extra args...] -> rc, output in $tmp/gate.txt
run_gate() {
  local before="$1" after="$2"; shift 2
  set +e
  python3 "$GATE" --before "$before" --after "$after" "$@" > "$tmp/gate.txt" 2>&1
  local rc=$?
  set -e
  return $rc
}

# ---------------------------------------------------------------------------
# Shared BEFORE fixture. One tree, reused; each case builds its own AFTER.
#
#   bb01  a plain [ROUTINE] item, long body on the head line          (shrinkable)
#   bb02  a [ROUTINE] item gated by the 🚧 glyph                       (gate marker)
#   bb03  a [ROUTINE] item whose BODY PROSE says "blocked on"          (spurious hit)
#   bb04  a [ROUTINE] item carrying its lane tag TWICE on the line     (occurrence count)
#   bb05  an INDENTED sub-item carrying its OWN id, no lane tag        (loderite shape)
# ---------------------------------------------------------------------------
mk_before() { # <dir>
  local d="$1"
  mkdir -p "$d"
  cat > "$d/ROADMAP.md" <<'EOF'
# ROADMAP

## Current

- [ ] [ROUTINE] **Plain item** -- acceptance: make test green. Rationale prose that is long enough to be worth relocating, repeated for bulk: aaaa bbbb cccc dddd eeee ffff gggg hhhh. <!-- id:bb01 -->
- [ ] [ROUTINE] **Gated item** -- 🚧 acceptance: make test green. Rationale prose for bulk: aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj. <!-- id:bb02 -->
- [ ] [ROUTINE] **Prose-hit item** -- acceptance: make test green. History: this used to be blocked on a dependency that shipped months ago, kept for the record. <!-- id:bb03 -->
- [ ] [ROUTINE] **Repeated-tag item** -- acceptance: make test green. History note quoting its own lane: the item was filed as [ROUTINE] on purpose. <!-- id:bb04 -->
  - [ ] a sub-item note carrying its OWN id, with no lane tag of its own <!-- id:bb05 -->
EOF
  cat > "$d/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [ROUTINE] **Plain item** -- acceptance: make test green. <!-- id:bb01 -->
EOF
}

before="$tmp/before"
mk_before "$before"

# Sanity: the BEFORE fixture must actually exercise the machinery, or every case below
# proves nothing (the id:a73c "unreached fixture" class).
if ! grep -q 'id:bb05' "$before/ROADMAP.md"; then
  report "sanity: the BEFORE fixture lost its indented-id line"
fi

# ---------------------------------------------------------------------------
# (A) an UNCHANGED ledger pair passes.
# ---------------------------------------------------------------------------
after_a="$tmp/after-a"; mk_before "$after_a"
rc=0; run_gate "$before" "$after_a" || rc=$?
(( rc == 0 )) \
  || report "case A: an UNCHANGED ledger pair must pass; got rc=$rc -- $(grep -c '^  FATAL' "$tmp/gate.txt") fatal finding(s): $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# (B) a byte-field change ALONE does not fail. bb01's body is relocated behind a
#     pointer; every marker stays on the line, so only the *_bytes fields move.
# ---------------------------------------------------------------------------
after_b="$tmp/after-b"; mk_before "$after_b"; mkdir -p "$after_b/docs/ledger-notes"
python3 - "$after_b" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Plain item** -- detail: `docs/ledger-notes/bb01.md` "
       "<!-- id:bb01 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Plain item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
open(os.path.join(d, "docs/ledger-notes/bb01.md"), "w").write(
    "# id:bb01\n\n## From ROADMAP\n\nacceptance: make test green. Rationale prose that is "
    "long enough to be worth relocating, repeated for bulk: aaaa bbbb cccc dddd eeee ffff "
    "gggg hhhh.\n")
PY
rc=0; run_gate "$before" "$after_b" || rc=$?
(( rc == 0 )) \
  || report "case B: a *_bytes-only change must not fail (strict verdict equality fails by construction); got rc=$rc: $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# (C) THE LODERITE SHAPE: an indented line carrying its own id is relocated, taking
#     the ADDRESS with it. Counts of open items are unchanged; only a SET diff sees it.
# ---------------------------------------------------------------------------
after_c="$tmp/after-c"; mk_before "$after_c"; mkdir -p "$after_c/docs/ledger-notes"
grep -v 'id:bb05' "$after_c/ROADMAP.md" > "$tmp/c.tmp"
mv "$tmp/c.tmp" "$after_c/ROADMAP.md"
cat > "$after_c/docs/ledger-notes/bb04.md" <<'EOF'
# id:bb04

## From ROADMAP

- [ ] a sub-item note carrying its OWN id, with no lane tag of its own <!-- id:bb05 -->
EOF
rc=0; run_gate "$before" "$after_c" || rc=$?
(( rc != 0 )) \
  || report "case C: a DROPPED id must be REFUSED (non-zero exit) -- id:bb05's body survived in the detail file but its ADDRESS left the ledger, which no count and no round trip can see"
grep -q 'ORPHANED id:bb05' "$tmp/gate.txt" \
  || report "case C: the report must NAME the orphaned id (got: $(grep -m1 '^  FATAL' "$tmp/gate.txt"))"
grep -q 'detail file is not an address' "$tmp/gate.txt" \
  || report "case C: the report must say a surviving detail file does not excuse a lost address"

# ---------------------------------------------------------------------------
# (D) a LOST GATE MARKER: bb02's 🚧 is destroyed, not relocated. The item silently
#     becomes executor-dispatchable and nothing carries the glyph any more.
# ---------------------------------------------------------------------------
after_d="$tmp/after-d"; mk_before "$after_d"; mkdir -p "$after_d/docs/ledger-notes"
python3 - "$after_d" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Gated item** -- detail: `docs/ledger-notes/bb02.md` "
       "<!-- id:bb02 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Gated item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
# The detail file deliberately does NOT carry the glyph: the marker was DESTROYED.
open(os.path.join(d, "docs/ledger-notes/bb02.md"), "w").write(
    "# id:bb02\n\n## From ROADMAP\n\nacceptance: make test green. Rationale prose for bulk: "
    "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj.\n")
PY
rc=0; run_gate "$before" "$after_d" || rc=$?
# The naming assertion runs FIRST so it is never the LAST-fired FAIL line; the runner's
# last-fired rule keys the declaration on the substantive rc assertion below.
grep -q 'bb02' "$tmp/gate.txt" \
  || report "case D: the report must name id:bb02 as the item whose gate was lost"
(( rc != 0 )) \
  || report "case D: a DESTROYED gate marker must be REFUSED -- id:bb02 became executor-dispatchable and no detail file carries the gate glyph, so the gain is not a relocated spurious hit"

# ---------------------------------------------------------------------------
# (E) a REMOVED SPURIOUS PROSE HIT: bb03's "blocked on" was history prose, relocated
#     verbatim into its detail file. Same observable movement as (D); must PASS.
# ---------------------------------------------------------------------------
after_e="$tmp/after-e"; mk_before "$after_e"; mkdir -p "$after_e/docs/ledger-notes"
python3 - "$after_e" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Prose-hit item** -- detail: `docs/ledger-notes/bb03.md` "
       "<!-- id:bb03 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Prose-hit item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
open(os.path.join(d, "docs/ledger-notes/bb03.md"), "w").write(
    "# id:bb03\n\n## From ROADMAP\n\nacceptance: make test green. History: this used to be "
    "blocked on a dependency that shipped months ago, kept for the record.\n")
PY
rc=0; run_gate "$before" "$after_e" || rc=$?
(( rc == 0 )) \
  || report "case E: a relocated SPURIOUS prose hit must NOT fail -- 'blocked on' is present verbatim in docs/ledger-notes/bb03.md, so it was body prose; got rc=$rc: $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"
grep -q 'IMPROVEMENTS' "$tmp/gate.txt" \
  || report "case E: the allowed direction must be REPORTED as an improvement, not passed silently"

# ---------------------------------------------------------------------------
# (F) marker OCCURRENCE COUNT falls, PRESENCE preserved. bb04 carried [ROUTINE]
#     twice; the relocation leaves one. Measured live at 618 -> 562 lane-tag tokens.
# ---------------------------------------------------------------------------
after_f="$tmp/after-f"; mk_before "$after_f"; mkdir -p "$after_f/docs/ledger-notes"
python3 - "$after_f" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Repeated-tag item** -- detail: `docs/ledger-notes/bb04.md` "
       "<!-- id:bb04 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Repeated-tag item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
open(os.path.join(d, "docs/ledger-notes/bb04.md"), "w").write(
    "# id:bb04\n\n## From ROADMAP\n\nacceptance: make test green. History note quoting its "
    "own lane: the item was filed as [ROUTINE] on purpose.\n")
PY
before_tags="$(grep -o '\[ROUTINE\]' "$before/ROADMAP.md" | wc -l)"
after_tags="$(grep -o '\[ROUTINE\]' "$after_f/ROADMAP.md" | wc -l)"
(( after_tags < before_tags )) \
  || report "case F: fixture sanity -- the AFTER tree must actually carry FEWER lane-tag occurrences ($before_tags -> $after_tags), or the case proves nothing"
rc=0; run_gate "$before" "$after_f" || rc=$?
(( rc == 0 )) \
  || report "case F: a drop in marker OCCURRENCE count with PRESENCE preserved must not fail; got rc=$rc: $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# (G) the marker-registry cross-check. A keep-list that omits a marker a detector
#     reads must be REPORTED, and must REFUSE under --strict-markers.
# ---------------------------------------------------------------------------
cat > "$tmp/keep-empty.txt" <<'EOF'
# a keep-list that covers nothing at all
ZZZZ-NOTHING-MATCHES-THIS
EOF
rc=0; run_gate "$before" "$after_a" --keep-list "$tmp/keep-empty.txt" || rc=$?
(( rc == 0 )) \
  || report "case G: keep-list gaps are ADVISORY by default (the fallback list is a reference); got rc=$rc"
grep -q 'KEEP-LIST GAP' "$tmp/gate.txt" \
  || report "case G: a keep-list covering nothing must report KEEP-LIST GAPs for the markers the detectors read"
grep -q "KEEP-LIST GAP: '@manual'" "$tmp/gate.txt" \
  || report "case G: the cross-check must name the specific marker, e.g. @manual, not just a count"
rc=0; run_gate "$before" "$after_a" --keep-list "$tmp/keep-empty.txt" --strict-markers || rc=$?
(( rc != 0 )) \
  || report "case G: --strict-markers must turn a keep-list gap into a refusal"

# ---------------------------------------------------------------------------
# (H) the registry and the out-of-scope declaration are IN the report. An honest
#     stated gap beats a silent one, and a gap nobody can read is silent.
# ---------------------------------------------------------------------------
rc=0; run_gate "$before" "$after_a" || rc=$?
grep -q 'DECLARED OUT OF SCOPE' "$tmp/gate.txt" \
  || report "case H: the report must DECLARE which detectors are out of scope and why"
grep -q 'classify-repo' "$tmp/gate.txt" \
  || report "case H: the report must enumerate the detector registry it actually ran"

if (( fail )); then
  exit 1
fi
echo "PASS: shrink-acceptance.py refuses a dropped id and a destroyed gate marker, accepts an unchanged ledger, a bytes-only change, a relocated spurious prose hit and an occurrence-count drop, and reports keep-list gaps (id:0d7c)"
