#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D4, tracked in
#  TODO.md id:15e9, not ROADMAP.md; this test always counts.)
#
# classify.sh [HARD] floor (D4): a TODO item tagged [HARD] is strong-model design work
# and must FLOOR to C3 — never C1/C2 — even when it carries a meeting-note link with a
# ## Decisions section (which would otherwise make it C1). Non-[HARD] items are
# unaffected. The relay RELAY mirror line still classifies RELAY.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFY="$ROOT/meeting/classify.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"

cat > "$fix/docs/meeting-notes/2026-01-01-0000-x.md" <<'EOF'
# x
## Decisions
- decided
EOF
cat > "$fix/TODO.md" <<'EOF'
# TODO
- [ ] **[HARD] big design** with link docs/meeting-notes/2026-01-01-0000-x.md <!-- id:aaaa -->
- [ ] [HARD — strong model] em-dash variant docs/meeting-notes/2026-01-01-0000-x.md <!-- id:dddd -->
- [ ] normal impl-ready docs/meeting-notes/2026-01-01-0000-x.md <!-- id:bbbb -->
- [ ] plain bare item with no link <!-- id:cccc -->
- [ ] Relay: 2 open ROADMAP items <!-- id:9999 -->
EOF

cls="$("$CLASSIFY" "$fix")"

class_of() { grep -P "\tid:$1\t" <<<"$cls" | cut -f1; }

[[ "$(class_of aaaa)" == "C3" ]] || { echo "[HARD] item must floor to C3, got $(class_of aaaa)"; exit 1; }
[[ "$(class_of dddd)" == "C3" ]] || { echo "[HARD — strong model] must floor to C3, got $(class_of dddd)"; exit 1; }
[[ "$(class_of bbbb)" == "C1" ]] || { echo "non-HARD link+Decisions must stay C1, got $(class_of bbbb)"; exit 1; }
[[ "$(class_of cccc)" == "C3" ]] || { echo "bare item must be C3, got $(class_of cccc)"; exit 1; }
[[ "$(class_of 9999)" == "RELAY" ]] || { echo "relay mirror line must stay RELAY, got $(class_of 9999)"; exit 1; }

# the [HARD] tag stays visible in the SUMMARY column
grep -P '\tid:aaaa\t' <<<"$cls" | grep -q '\[HARD\]' \
  || { echo "[HARD] tag must remain visible in SUMMARY"; exit 1; }

echo ok
