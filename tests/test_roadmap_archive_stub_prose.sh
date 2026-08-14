#!/usr/bin/env bash
# roadmap:4a12 — an archived STUB must stay recognised as a stub when the item line
# carries PROSE between its own `<!-- id:XXXX -->` marker and the stub suffix.
#
# DEFECT (cartulary 2026-08-14): `stub_line_re` was
#     r'^- \[x\] .*<!--\s*id:[0-9a-f]{4}\s*-->' + re.escape(STUB_SUFFIX)
# with NO `.*` between the marker and the suffix — so the suffix had to follow the marker
# IMMEDIATELY. Ledger write-backs from `/relay human` and `/meeting` routinely append
# rationale after the marker, so those stubs read as un-stubbed and were re-archived AND
# re-stubbed EVERY round. Observed: up to 9 duplicate bodies per id in ROADMAP.archive.md,
# and one ROADMAP.md line carrying the stub suffix 3x. That also violates the host repo's
# own id-uniqueness requirement, and re-blinds `orphan-scan --cross-ledger`.
#
# The regex stays deliberately NOT end-anchored (real stubs carry trailing annotations
# past the suffix) — this test pins both directions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ARCHIVE_BIN:-$ROOT/relay/scripts/roadmap-archive.sh}"
[[ -x "$SCRIPT" ]] || { echo "roadmap-archive.sh not executable at $SCRIPT" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
fail=0
SUF=" (archived — see ROADMAP.archive.md)"

make_repo() {
    local repo="$1" content="$2"
    mkdir -p "$repo"; git -C "$repo" init -q
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name tester
    printf '%s' "$content" > "$repo/ROADMAP.md"
    git -C "$repo" add ROADMAP.md; git -C "$repo" commit -qm seed
}

check() {
    if [[ "$2" == "$3" ]]; then printf '  ok   %s\n' "$1"
    else printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

repo="$tmp/repo"
make_repo "$repo" "# Roadmap

## Items

- [x] **Stub with PROSE after its marker** <!-- id:1a2b --> — Owner call 2026-08-14: rationale appended here by a ledger write-back.$SUF
- [x] **Stub with a trailing annotation past the suffix** <!-- id:3c4d -->$SUF **⚠ see note**
- [ ] **An open item** <!-- id:5e6f -->
"

# Run the archiver TWICE — the defect only compounds on the second pass.
"$SCRIPT" "$repo" >/dev/null 2>&1 || true
"$SCRIPT" "$repo" >/dev/null 2>&1 || true

rm_line="$(grep -c -- '<!-- id:1a2b -->' "$repo/ROADMAP.md" || true)"
suf_count="$(grep -o -- "$SUF" "$repo/ROADMAP.md" | grep -c . || true)"
arch_1a2b=0
[[ -f "$repo/ROADMAP.archive.md" ]] && arch_1a2b="$(grep -c -- '<!-- id:1a2b -->' "$repo/ROADMAP.archive.md" || true)"
arch_3c4d=0
[[ -f "$repo/ROADMAP.archive.md" ]] && arch_3c4d="$(grep -c -- '<!-- id:3c4d -->' "$repo/ROADMAP.archive.md" || true)"

check "prose-after-marker stub stays in ROADMAP.md exactly once" "1" "$rm_line"
check "its suffix is NOT duplicated (2 stubs => exactly 2 suffixes)" "2" "$suf_count"
check "prose-after-marker stub is NOT copied into the archive"   "0" "$arch_1a2b"
check "trailing-annotation stub is NOT copied into the archive"  "0" "$arch_3c4d"

exit "$fail"
