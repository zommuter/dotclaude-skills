#!/usr/bin/env bash
#
# Defect-fix test (no `# roadmap:` header by design: this pins a DEFECT under the id:37ea
# dissolve ruling, and no ROADMAP item was minted for it -- so its failures always count).
#
# THE DEFECT: `relay/scripts/mechanical-orphan-scan.sh` read `[host: ...]` and
# `[INTENSIVE - <res>]` off the ROADMAP item LINE only. Neither token is in
# `tools/ledger-shrink.py`'s `MUST_KEEP_PATTERNS`, and by ratified design neither will be --
# that file states `[INTENSIVE]` is "deliberately excluded ... a consumer that anchors on it
# is a defect". So when the shrink relocates an item's body into `docs/ledger-notes/<id>.md`,
# both tokens go with it and the surfaced row's host/resource silently degrades to "-": the
# reviewer then authors a recipe with no host binding. id:d35a silent-no-op class.
#
# THE FIX (id:37ea): union-anchor the CONSUMER, not the keep-set. The scanner now reads the
# item line UNION the first non-blank line under the note's `## From ROADMAP` heading -- that
# single line IS the pre-shrink tail, so the verdict is byte-identical to pre-shrink. The note
# path is read OFF the line, anchored to the item's own id (the id:1608 / `item_detail_path`
# shape); hardcoding a notes directory is id:d4d3.
#
# The cases below deliberately include the OVER-MATCH controls, because re-anchoring a
# detector wrongly IS the silent-blindness class: a later `###` subsection and a sibling
# `## From TODO` section both carry a decoy host that must NOT be read.
#
# fails-against-mutation: sed -i 's|tail = relocated_tail(path, line, oid)|tail = ""|' relay/scripts/mechanical-orphan-scan.sh
# fails-against-assertion: positive control: shrunk item must recover
#
# Hermetic: mktemp -d only; RELAY_RECIPE_DIR/RELAY_TOML/SRC_DIR are redirected into it, so
# neither ~/.claude nor ~/.config/relay nor the network is touched.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/relay/scripts/mechanical-orphan-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SCAN" ]] || fail "mechanical-orphan-scan.sh not found at $SCAN"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/rc/pending" "$tmp/rc/running" "$tmp/rc/done" "$tmp/rc/drafts"
mkdir -p "$tmp/repo/docs/ledger-notes"
: > "$tmp/relay.toml"

# --- fixture ------------------------------------------------------------------------------
# Note the notes directory is NOT the fleet default in one case: `alt-notes/` proves the
# pointer is read off the line rather than assumed (the id:d4d3 hardcoded-path regression).
mkdir -p "$tmp/repo/alt-notes"

cat > "$tmp/repo/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [MECHANICAL] **Shrunk item, tags relocated** -- detail: `docs/ledger-notes/aaaa.md` <!-- id:aaaa -->
- [ ] [MECHANICAL] **Shrunk item, no tags anywhere** -- detail: `docs/ledger-notes/bbbb.md` <!-- id:bbbb -->
- [ ] [MECHANICAL] **Unshrunk, tags on the line** [host: zomni] [INTENSIVE - gpu] <!-- id:cccc -->
- [ ] [MECHANICAL] **Pointer that does not resolve** -- detail: `docs/ledger-notes/dddd.md` <!-- id:dddd -->
- [ ] [MECHANICAL] **Decoy in a sibling TODO section** -- detail: `docs/ledger-notes/eeee.md` <!-- id:eeee -->
- [ ] [MECHANICAL] **Non-default notes directory** -- detail: `alt-notes/ffff.md` <!-- id:ffff -->
EOF

cat > "$tmp/repo/docs/ledger-notes/aaaa.md" <<'EOF'
# id:aaaa

## From ROADMAP

relocated body prose [host: fievel] [INTENSIVE - ram] and then more words.

### A later subsection accumulated afterwards

it mentions [host: decoy-sub] and [INTENSIVE - decoy-sub] purely in passing.
EOF

cat > "$tmp/repo/docs/ledger-notes/bbbb.md" <<'EOF'
# id:bbbb

## From ROADMAP

relocated body prose carrying no tags at all.
EOF

cat > "$tmp/repo/docs/ledger-notes/eeee.md" <<'EOF'
# id:eeee

## From TODO

todo-side prose [host: decoy-todo] [INTENSIVE - decoy-todo]

## From ROADMAP

roadmap-side prose, deliberately tagless.
EOF

cat > "$tmp/repo/alt-notes/ffff.md" <<'EOF'
# id:ffff

## From ROADMAP

relocated body prose [host: cartmanjaro] [INTENSIVE - disk].
EOF

# --- run ----------------------------------------------------------------------------------
out="$tmp/out.tsv"; err="$tmp/err.txt"
RELAY_RECIPE_DIR="$tmp/rc" RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/nosrc" \
  bash "$SCAN" "t=$tmp/repo" >"$out" 2>"$err" \
  || fail "scanner exited non-zero; stderr: $(cat "$err")"

row() { awk -F'\t' -v id="$1" '$2 == id { print $4 "|" $5 }' "$out"; }

# --- must-not-flag controls FIRST: these hold both before and after the fix, so a failure
#     here is a genuinely new regression rather than the defect this file pins. ------------
[[ "$(row bbbb)" == "-|-" ]] \
  || fail "must-not-flag: tagless relocated body must stay '-|-', got '$(row bbbb)'"
pass "must-not-flag: a tagless relocated body yields no host/resource"

[[ "$(row cccc)" == "zomni|gpu" ]] \
  || fail "must-not-flag: unshrunk on-line tags must be unchanged, got '$(row cccc)'"
pass "must-not-flag: an unshrunk item's on-line tags are read exactly as before"

[[ "$(row dddd)" == "-|-" ]] \
  || fail "must-not-flag: unresolvable pointer must yield '-|-', got '$(row dddd)'"
pass "must-not-flag: an unresolvable pointer still yields '-'"

[[ "$(row eeee)" == "-|-" ]] \
  || fail "must-not-flag: a sibling '## From TODO' decoy must not leak into a ROADMAP read, got '$(row eeee)'"
pass "must-not-flag: a sibling '## From TODO' section is not read for a ROADMAP item"

if grep -q 'decoy-sub' "$out"; then
  fail "must-not-flag: a later '###' subsection of the note must not be read"
fi
pass "must-not-flag: only the section's first non-blank line is read, not the whole note"

# --- positive controls: these are the assertions the defect breaks. -----------------------
# ORDER MATTERS. The declared `# fails-against-assertion:` above names the aaaa line, so aaaa
# must be the FIRST assertion the mutation can reach -- `fail` exits, and a red arriving at
# some earlier assertion is red for the wrong reason (the id:a73c rule).
[[ "$(row aaaa)" == "fievel|ram" ]] \
  || fail "positive control: shrunk item must recover [host:]/[INTENSIVE] from its note, got '$(row aaaa)'"
pass "positive control: a shrunk item recovers host+resource from its relocated body"

[[ "$(row ffff)" == "cartmanjaro|disk" ]] \
  || fail "positive control (second): a non-default notes directory must be read OFF the line (id:d4d3), got '$(row ffff)'"
pass "positive control: the notes directory is read off the line, never hardcoded"

grep -q "id:dddd points at" "$err" \
  || fail "positive control (third): an unresolvable pointer must warn LOUDLY on stderr (id:4347)"
pass "positive control: an unresolvable pointer is reported, never silently read as 'no tag'"

echo "ALL PASS: mechanical-orphan-scan union-anchors host/resource across the ledger and its notes (id:37ea)"
