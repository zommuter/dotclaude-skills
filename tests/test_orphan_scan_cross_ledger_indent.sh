#!/usr/bin/env bash
# roadmap:34c7 — Unify orphan-scan.sh --cross-ledger on an id-keyed, indent-agnostic
# twin-check (meeting 2026-07-11-1239 D1). Today --cross-ledger anchors its TODO/ROADMAP
# scan at column 0 (`^- \[[ xX]\] `), so a drift whose TODO twin is an INDENTED sub-item
# (`  - [ ] … <!-- id -->`) is invisible and never flagged, even though the archiver's
# id-keyed check catches it. Contract: a drift whose TODO twin is indented IS flagged;
# a matching indented pair is NOT.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix"

cat > "$fix/TODO.md" <<'EOF'
# TODO
## Current
- [ ] parent umbrella
  - [ ] indented twin, still open in TODO but closed in ROADMAP <!-- id:1a1a -->
  - [x] indented twin that AGREES with ROADMAP (both done) <!-- id:2b2b -->
- [ ] a col-0 twin, still open in TODO, closed in ROADMAP <!-- id:3c3c -->
EOF
: > "$fix/TODO.archive.md"
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap <!-- relay roadmap v1 -->
- [x] indented-twin drift, closed in roadmap [ROUTINE] <!-- id:1a1a -->
- [x] agreeing twin, closed in roadmap [ROUTINE] <!-- id:2b2b -->
- [x] col-0 twin drift, closed in roadmap [ROUTINE] <!-- id:3c3c -->
EOF

out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# The INDENTED disagreeing twin must be flagged (the id:34c7 gap).
grep -q 'id:1a1a' <<<"$out" \
  || { echo "must flag id:1a1a (indented TODO [ ] vs ROADMAP [x] — the 34c7 gap)"; echo "got: $out"; exit 1; }

# The col-0 disagreeing twin is the pre-existing behaviour — still flagged.
grep -q 'id:3c3c' <<<"$out" \
  || { echo "regression: col-0 disagreeing twin id:3c3c must still be flagged"; echo "got: $out"; exit 1; }

# An indented twin whose state AGREES with ROADMAP must NOT be flagged.
if grep -q 'id:2b2b' <<<"$out"; then
  echo "must NOT flag id:2b2b (indented but agreeing [x]/[x])"; echo "got: $out"; exit 1
fi

echo ok
