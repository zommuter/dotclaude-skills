#!/usr/bin/env bash
# roadmap:d0aa — em-dash delimiter migration S6: orphan-scan.sh's two real lane-tag match
# sites (--promotion's `[HARD — pool]` gate and --unbackrefed's `[* — meeting]`/
# `[INPUT — decision]` gate) must accept the hyphen-delimited spelling identically to the
# em-dash spelling. Unlike classify.sh's substring-based lane floor, these two sites are
# literal `grep -E` patterns pinned to the em-dash byte — this is the genuine, pre-fix RED
# defect this seam closes (verified below: run against the PRE-fix pattern this test would
# fail on `[HARD - pool]` / `[* - meeting]` / `[INPUT - decision]` fixtures).
#
# Hermetic: mktemp fixtures + a throwaway git repo, never touches ~/.claude or the network.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

fail() { echo "FAIL: $1"; exit 1; }

[[ -x "$ORPHAN" ]] || fail "orphan-scan.sh not executable at $ORPHAN"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"

# --- --promotion: hyphen-delimited [HARD - pool] with no ROADMAP twin ------------------
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] [HARD - pool] **Hyphen-delimited pool item, no ROADMAP twin** <!-- id:e001 -->
- [ ] [HARD — pool] **Em-dash pool item, no ROADMAP twin (control)** <!-- id:e002 -->
- [ ] [HARD - meeting] **Hyphen meeting item — not an executable lane, must NOT fire** <!-- id:e003 -->
EOF
: > "$repo/ROADMAP.md"

git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" add -A
git -C "$repo" commit -q -m fixture

out_p="$(HOME="$tmp" "$ORPHAN" --promotion "$repo" 2>&1)"

grep -q 'id:e001' <<<"$out_p" \
  || fail "[HARD - pool] (hyphen) with no ROADMAP twin must be flagged un-promoted; got: $out_p"
echo "PASS: --promotion recognizes hyphen-delimited [HARD - pool]"

grep -q 'id:e002' <<<"$out_p" \
  || fail "[HARD — pool] (em-dash control) with no ROADMAP twin must still be flagged; got: $out_p"
echo "PASS: --promotion still recognizes em-dash [HARD — pool] (no regression)"

grep -q 'id:e003' <<<"$out_p" \
  && fail "[HARD - meeting] is not an executable lane — must NOT fire in --promotion"
echo "PASS: --promotion does not fire on a non-executable hyphen lane"

# --- --unbackrefed: hyphen-delimited [* - meeting] / [INPUT - decision], no decided-in: ---
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] [INPUT - decision] **Hyphen decision item, no backref** <!-- id:e004 -->
- [ ] [INPUT — decision] **Em-dash decision item, no backref (control)** <!-- id:e005 -->
- [ ] [HARD - meeting] **Hyphen meeting-suffixed bracket, no backref** <!-- id:e006 -->
- [ ] [INPUT - decision] **Hyphen decision item WITH a backref — must NOT fire** <!-- decided-in:docs/meeting-notes/x.md --> <!-- id:e007 -->
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m fixture2

out_u="$(HOME="$tmp" "$ORPHAN" --unbackrefed "$repo" 2>&1)"

grep -q 'id:e004.*UNBACKREFED' <<<"$out_u" \
  || fail "[INPUT - decision] (hyphen), no backref, must fire UNBACKREFED; got: $out_u"
echo "PASS: --unbackrefed recognizes hyphen-delimited [INPUT - decision]"

grep -q 'id:e005.*UNBACKREFED' <<<"$out_u" \
  || fail "[INPUT — decision] (em-dash control), no backref, must still fire; got: $out_u"
echo "PASS: --unbackrefed still recognizes em-dash [INPUT — decision] (no regression)"

grep -q 'id:e006.*UNBACKREFED' <<<"$out_u" \
  || fail "[HARD - meeting] (hyphen, bracket ending 'meeting'), no backref, must fire UNBACKREFED; got: $out_u"
echo "PASS: --unbackrefed recognizes hyphen-delimited [* - meeting]"

grep -q 'id:e007' <<<"$out_u" \
  && fail "[INPUT - decision] WITH a decided-in: backref must NOT fire"
echo "PASS: --unbackrefed does not fire when a decided-in: backref is present"

echo "ALL PASS"
