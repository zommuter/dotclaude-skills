#!/usr/bin/env bash
# roadmap:cc7e — md-merge.py update-ids resolves an item's OWN id with re.search
# (the FIRST id-comment on the line), so an item whose BODY quotes an id-comment is
# unaddressable, and a write aimed at the quoted id lands on the WRONG item.
#
# Convention (already settled — gather-human-backlog.sh fixed at d7727be): an item's
# OWN id is the LAST `<!-- id:XXXX -->` on the line, never the first; body-prose
# id-comments are quotes, not the item's identity.
#
# Contract (both directions asserted; the silent mis-route is the one that needs the
# negative case):
#   (A) LOUD/addressable — an update to BBBB (the line's own, trailing id) MUST apply,
#       even though the body quotes <!-- id:AAAA --> earlier on the same line.
#   (B) SILENT mis-route — an update to AAAA (only a quoted body id, not any line's own
#       id) MUST NOT match that line: update-ids without --allow-new must fail LOUD
#       (exit non-zero, name AAAA) and write NOTHING. Under the first-match bug it
#       instead applies AAAA's update to this line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDMERGE="$ROOT/meeting/md-merge.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The line's body quotes <!-- id:aaaa --> BEFORE its own trailing <!-- id:bbbb -->.
seed() {
  cat > "$tmp/TODO.md" <<'EOF'
# TODO
- [ ] item quoting the colliding token <!-- id:aaaa --> before its own <!-- id:bbbb -->
EOF
}

# (A) an update to the line's OWN (trailing) id bbbb must apply.
seed
echo '{"updates":[{"id":"bbbb","line":"- [x] item quoting the colliding token <!-- id:aaaa --> DONE <!-- id:bbbb -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md"
grep -q 'DONE <!-- id:bbbb -->' "$tmp/TODO.md" \
  || { echo "(A) update to the line's own trailing id bbbb must apply"; cat "$tmp/TODO.md"; exit 1; }

# (B) an update to the quoted body id aaaa must NOT match this line: loud not-found,
#     nothing written (the silent mis-route case).
seed
before="$(cat "$tmp/TODO.md")"
set +e
err="$(echo '{"updates":[{"id":"aaaa","line":"- [x] WRONGLY REWRITTEN <!-- id:aaaa -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md" 2>&1 >/dev/null)"
rc=$?
set -e
[[ $rc -ne 0 ]] \
  || { echo "(B) update to a merely-quoted body id aaaa must exit non-zero (not silently mis-route), got 0"; cat "$tmp/TODO.md"; exit 1; }
grep -q 'aaaa' <<<"$err" \
  || { echo "(B) the error must name the unmatched token aaaa (stderr: $err)"; exit 1; }
after="$(cat "$tmp/TODO.md")"
[[ "$before" == "$after" ]] \
  || { echo "(B) a mis-routed update must write NOTHING (file changed)"; diff <(echo "$before") <(echo "$after"); exit 1; }

echo ok
