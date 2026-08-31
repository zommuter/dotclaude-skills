#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D4, tracked in
#  TODO.md id:15e9, not ROADMAP.md; this test always counts.)
#
# classify.sh lane floor (D4): a TODO item carrying a lane bracket is strong-tier/human
# work and must NOT classify C1/C2 on the strength of a linked ## Decisions section. As of
# the lane-aware refinement (2026-07-14, id:78ff) the floor routes BY LANE; as of the
# capability-keyed vocabulary migration (2026-07-30, routed:f1e1) bare `[HARD]` IS the pool
# lane, so it floors to POOL rather than the old C3+HARD-NOLANE. Full mapping lives in
# classify.sh's header and relay/references/hard-lanes.md.
#
# These fixtures exercise the FLOOR itself — that a lane tag overrides a link+Decisions
# C1/C2 classification: bare `[HARD]` (→POOL, the new-vocab pool lane) and
# `[HARD - strong model]` (an UNRECOGNIZED lane → C3+HARD-NOLANE, the loud reject). The
# per-lane routing table is covered by test_classify_hard_lanes.sh.
# Non-lane-tagged items are unaffected. The relay RELAY mirror line still classifies RELAY.
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
- [ ] [HARD - strong model] delimited-lane variant docs/meeting-notes/2026-01-01-0000-x.md <!-- id:dddd -->
- [ ] normal impl-ready docs/meeting-notes/2026-01-01-0000-x.md <!-- id:bbbb -->
- [ ] plain bare item with no link <!-- id:cccc -->
- [ ] Relay: 2 open ROADMAP items <!-- id:9999 -->
EOF

cls="$("$CLASSIFY" "$fix")"

class_of() { grep -P "\tid:$1\t" <<<"$cls" | cut -f1; }

# Bare [HARD] is the new-vocab POOL lane (routed:f1e1) — the floor still overrides the
# link+Decisions C1 this fixture would otherwise get, it just lands on POOL not C3.
[[ "$(class_of aaaa)" == "POOL" ]] || { echo "[HARD] item must floor to POOL (new-vocab pool lane), got $(class_of aaaa)"; exit 1; }
# An UNRECOGNIZED lane ("strong model" is not in hard-lanes.md) still floors to C3 + loud reject.
[[ "$(class_of dddd)" == "C3" ]] || { echo "[HARD - strong model] must floor to C3, got $(class_of dddd)"; exit 1; }
grep -q 'HARD-NOLANE' < <(grep -P '\tid:dddd\t' <<<"$cls") \
  || { echo "[HARD - strong model] (unrecognized lane) must be flagged HARD-NOLANE"; exit 1; }
[[ "$(class_of bbbb)" == "C1" ]] || { echo "non-HARD link+Decisions must stay C1, got $(class_of bbbb)"; exit 1; }
[[ "$(class_of cccc)" == "C3" ]] || { echo "bare item must be C3, got $(class_of cccc)"; exit 1; }
[[ "$(class_of 9999)" == "RELAY" ]] || { echo "relay mirror line must stay RELAY, got $(class_of 9999)"; exit 1; }

# the [HARD] tag stays visible in the SUMMARY column
grep -q '\[HARD\]' < <(grep -P '\tid:aaaa\t' <<<"$cls") \
  || { echo "[HARD] tag must remain visible in SUMMARY"; exit 1; }

echo ok
