#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D2, tracked in
#  TODO.md id:38df, not ROADMAP.md; this test always counts.)
#
# orphan-scan.sh --cross-ledger / -x (single-id-two-views guard, D2): flags any
# <!-- id:XXXX --> token present in BOTH the TODO union (TODO.md + TODO.archive.md)
# AND ROADMAP.md whose checkbox state disagrees. Matching state, TODO-only, and
# ROADMAP-only tokens are NOT flagged.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"

cat > "$fix/TODO.md" <<'EOF'
# TODO
- [ ] open in todo, closed in roadmap <!-- id:1111 -->
- [ ] open in both ledgers <!-- id:2222 -->
- [x] done in both ledgers <!-- id:3333 -->
- [ ] lives only in todo <!-- id:4444 -->
- [ ] Relay: 2 open ROADMAP items <!-- id:9999 -->
EOF
cat > "$fix/TODO.archive.md" <<'EOF'
# Archive
- [x] archived, also done in roadmap <!-- id:6666 -->
EOF
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap <!-- fables-turn roadmap v1 -->
- [x] open in todo, closed in roadmap [ROUTINE] <!-- id:1111 -->
- [ ] open in both ledgers [ROUTINE] <!-- id:2222 -->
- [x] done in both ledgers [ROUTINE] <!-- id:3333 -->
- [ ] lives only in roadmap [HARD] <!-- id:5555 -->
- [x] archived, also done in roadmap [ROUTINE] <!-- id:6666 -->
EOF

out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# 1111 disagrees ([ ] in TODO, [x] in ROADMAP) → must be flagged
grep -q 'id:1111' <<<"$out" || { echo "must flag id:1111 (disagreeing state)"; echo "got: $out"; exit 1; }
# matching-state and single-ledger tokens must NOT be flagged
for tk in 2222 3333 4444 5555 6666 9999; do
  if grep -q "id:$tk" <<<"$out"; then
    echo "must NOT flag id:$tk"; echo "got: $out"; exit 1
  fi
done

# -x alias behaves identically
alias_out="$(HOME="$tmp" "$ORPHAN" -x "$fix")"
[[ "$alias_out" == "$out" ]] || { echo "-x alias must match --cross-ledger"; exit 1; }

# the flagged line names both ledger states for the human
grep -qE 'id:1111.*TODO:\[ \].*ROADMAP:\[x\]' <<<"$out" \
  || { echo "flagged line must show both checkbox states"; echo "got: $out"; exit 1; }

echo ok
