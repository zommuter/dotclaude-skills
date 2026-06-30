#!/usr/bin/env bash
# No roadmap header — this is a feature test for the zkm B-topology follow-up
# (meeting docs/meeting-notes/2026-06-30-1042-relay-side-zkm-b-topology.md, D2),
# not gated on a ROADMAP item. Its failures always count.
#
# Forward (and reverse) orphan-scan must be PLUGIN-AWARE: in a polyrepo whose
# plugins own their own TODO.md (each `plugins/*/`), a ROOT meeting note can cite
# an id that now lives in a plugin's ledger rather than central. Such an id must
# NOT be flagged as an orphan (it IS tracked, just in the plugin). A genuinely
# absent id must still be flagged. A plugins-less repo must behave exactly as
# before (the existence gate is off).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Repo WITH a plugin owning id:aaaa ---------------------------------------
repo="$tmp/repo"
mkdir -p "$repo/docs/meeting-notes" "$repo/plugins/p1"
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
EOF
: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.md"
# Plugin owns the relocated id
cat > "$repo/plugins/p1/TODO.md" <<'EOF'
# p1 TODO
## Current
- [ ] relocated open item <!-- id:aaaa -->
EOF
: > "$repo/plugins/p1/TODO.archive.md"
: > "$repo/plugins/p1/ROADMAP.md"
# Root note cites the plugin-local id (aaaa) and a genuinely-absent id (bbbb)
cat > "$repo/docs/meeting-notes/2026-01-01-0000-x.md" <<'EOF'
# note
## Action items
- [ ] item tracked in plugin <!-- id:aaaa -->
- [ ] item tracked nowhere <!-- id:bbbb -->
EOF

out="$(HOME="$tmp" "$ORPHAN" "$repo")"
grep -q 'id:bbbb' <<<"$out" || { echo "must flag id:bbbb (absent everywhere)"; echo "got: $out"; exit 1; }
if grep -q 'id:aaaa' <<<"$out"; then
  echo "must NOT flag id:aaaa (tracked in plugins/p1/TODO.md)"; echo "got: $out"; exit 1
fi

# --- Control: plugins-less repo — behaviour unchanged (aaaa now an orphan) ----
ctl="$tmp/ctl"
mkdir -p "$ctl/docs/meeting-notes"
cat > "$ctl/TODO.md" <<'EOF'
# TODO
## Current
EOF
: > "$ctl/TODO.archive.md"
: > "$ctl/ROADMAP.md"
cat > "$ctl/docs/meeting-notes/2026-01-01-0000-x.md" <<'EOF'
# note
## Action items
- [ ] item tracked nowhere now <!-- id:aaaa -->
EOF

ctl_out="$(HOME="$tmp" "$ORPHAN" "$ctl")"
grep -q 'id:aaaa' <<<"$ctl_out" || { echo "control: plugins-less repo must still flag id:aaaa"; echo "got: $ctl_out"; exit 1; }

echo ok
