#!/usr/bin/env bash
# roadmap:1b1a — md-merge.py update-ids silently APPENDS an unmatched id, so a typo'd
# token creates a duplicate ledger line instead of failing. The helper is the SAFE
# write path; an UPDATE that misses must fail LOUD, and appends must be opt-in.
# Contract:
#   (1) update-ids with an id NOT present in the file exits non-zero, names the
#       unmatched token(s) on stderr, and writes NOTHING (no appended duplicate line).
#   (2) update-ids --allow-new appends the new id (today's behaviour, now opt-in).
#   (3) an in-place update of an EXISTING id still works (no regression).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDMERGE="$ROOT/meeting/md-merge.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

seed() {
  cat > "$tmp/TODO.md" <<'EOF'
# TODO
- [ ] existing item <!-- id:aaaa -->
- [ ] another existing item <!-- id:bbbb -->
EOF
}

# (3) existing-id in-place update still works.
seed
echo '{"updates":[{"id":"aaaa","line":"- [x] existing item DONE <!-- id:aaaa -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md"
grep -q '^- \[x\] existing item DONE <!-- id:aaaa -->' "$tmp/TODO.md" \
  || { echo "(3) in-place update of an existing id must still work"; cat "$tmp/TODO.md"; exit 1; }

# (1) unmatched id → LOUD failure, nothing written.
seed
before="$(cat "$tmp/TODO.md")"
set +e
err="$(echo '{"updates":[{"id":"9f9f","line":"- [ ] typo target <!-- id:9f9f -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md" 2>&1 >/dev/null)"
rc=$?
set -e
[[ $rc -ne 0 ]] \
  || { echo "(1) update-ids with an unmatched id must exit non-zero, got 0"; exit 1; }
grep -q '9f9f' <<<"$err" \
  || { echo "(1) the error must name the unmatched token 9f9f (stderr: $err)"; exit 1; }
after="$(cat "$tmp/TODO.md")"
[[ "$before" == "$after" ]] \
  || { echo "(1) a failed update must write NOTHING (file changed)"; diff <(echo "$before") <(echo "$after"); exit 1; }

# (2) --allow-new opts back into the append behaviour.
seed
echo '{"updates":[{"id":"9f9f","line":"- [ ] genuinely new item <!-- id:9f9f -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md" --allow-new
grep -q '<!-- id:9f9f -->' "$tmp/TODO.md" \
  || { echo "(2) --allow-new must append the new id"; cat "$tmp/TODO.md"; exit 1; }

echo ok
