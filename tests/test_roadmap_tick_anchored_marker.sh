#!/usr/bin/env bash
# roadmap:4a12 — the tick must anchor on the item's OWN `<!-- id:XXXX -->` MARKER,
# never a bare `id:XXXX` token appearing in PROSE on another item's line.
#
# Regression origin (cartulary 2026-08-14): `roadmap-tick.sh` used
# `index($0, "id:<id>") > 0`, a containment test. The `id:3801` auto hard-split writes
# "DECOMPOSED into seams id:AAAA, id:BBBB" as prose into the @container line, and the
# container sorts EARLIER than its seams — so with "flip the FIRST open line", ticking a
# seam flipped its container instead. Four mis-ticks in one day; shipped work read OPEN
# (the pool re-dispatched it) and containers read DONE over open seams.
set -euo pipefail

# TICK_BIN override exists so this test can be run against a pre-fix copy of the script
# to demonstrate it is non-vacuous (goes RED on the old bare-token implementation).
TICK="${TICK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/relay/scripts/roadmap-tick.sh}"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail=0

check() { # check <desc> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        printf '  ok   %s\n' "$1"
    else
        printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fail=1
    fi
}

# --- case 1: the container/seam collision, verbatim in shape from cartulary ---------
cat > "$tmp/ROADMAP.md" <<'EOF'
# ROADMAP

## Current

- [ ] [HARD] **Container.** <!-- id:6ed1 --> @container — DECOMPOSED into seams id:7b09, id:80d4 — pick those, not this.
- [ ] [HARD] **The seam that was actually worked.** <!-- id:7b09 -->
EOF
"$TICK" "$tmp" 7b09 >/dev/null 2>&1 || true
container=$(grep -o '^- \[.\].*<!-- id:6ed1 -->' "$tmp/ROADMAP.md" | cut -c1-6)
seam=$(grep -o '^- \[.\].*<!-- id:7b09 -->' "$tmp/ROADMAP.md" | cut -c1-6)
check "seam id:7b09 is ticked"              "- [x] " "$seam"
check "container id:6ed1 is UNTOUCHED"      "- [ ] " "$container"

# --- case 2: a body that QUOTES another item's marker must not be matched (cc7e) -----
cat > "$tmp/R2.md" <<'EOF'
# ROADMAP

## Current

- [ ] [HARD] **Quotes another marker in its body:** supersedes <!-- id:aaaa --> per the note. <!-- id:bbbb -->
EOF
cp "$tmp/R2.md" "$tmp/ROADMAP.md"
"$TICK" "$tmp" aaaa >/dev/null 2>&1 || true
quoted=$(grep -o '^- \[.\]' "$tmp/ROADMAP.md" | head -1)
check "quoted body marker id:aaaa does NOT tick the line" "- [ ]" "$quoted"

cp "$tmp/R2.md" "$tmp/ROADMAP.md"
"$TICK" "$tmp" bbbb >/dev/null 2>&1 || true
ownid=$(grep -o '^- \[.\]' "$tmp/ROADMAP.md" | head -1)
check "the line's OWN id id:bbbb DOES tick it"            "- [x]" "$ownid"

# --- case 3: idempotent no-op on an already-ticked id --------------------------------
before=$(cat "$tmp/ROADMAP.md")
"$TICK" "$tmp" bbbb >/dev/null 2>&1 || true
check "re-ticking an already-ticked id is a clean no-op" "$before" "$(cat "$tmp/ROADMAP.md")"

exit "$fail"
