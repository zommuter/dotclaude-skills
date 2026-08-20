#!/usr/bin/env bash
# roadmap:cc7e — asserts the id:6059 multi-marker REFUSAL is a deliberate, tested
# contract, not merely an incidental property of the current code. Supersedes
# tests/test_md_merge_own_id_last.sh, which encoded the RETIRED last-marker-wins
# spec: that spec was overtaken by the already-shipped id:6059 design, under which
# md-merge.py refuses to resolve an item's own id at all when a line carries more
# than one anchored `<!-- id:XXXX -->` marker (AmbiguousOwnId), rather than picking
# first or last. Owner ruling 2026-08-20 (`/relay human --all`): REDEFINE cc7e to
# assert that refusal instead of closing it.
#
# Contract:
#   (A) a line carrying >1 anchored id marker: an `update-ids` write aimed at EITHER
#       marker on that line MUST raise (exit non-zero, message names both ids) and
#       write NOTHING — the line is simply unaddressable, not resolved positionally.
#   (B) a line carrying exactly one anchored id marker still applies normally — the
#       refusal is specific to the ambiguous (>1 marker) case, not a general break.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDMERGE="$ROOT/meeting/md-merge.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The line's body quotes <!-- id:aaaa --> before its own trailing <!-- id:bbbb -->:
# two anchored markers on one line, so under id:6059 the line is ambiguous.
seed_ambiguous() {
  cat > "$tmp/TODO.md" <<'MD'
# TODO
- [ ] item quoting the colliding token <!-- id:aaaa --> before its own <!-- id:bbbb -->
- [ ] unrelated single-marker item <!-- id:cccc -->
MD
}

# (A1) targeting the trailing marker (bbbb) of an ambiguous line MUST raise, not apply.
seed_ambiguous
before="$(cat "$tmp/TODO.md")"
set +e
err="$(echo '{"updates":[{"id":"bbbb","line":"- [x] DONE <!-- id:bbbb -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md" 2>&1 >/dev/null)"
rc=$?
set -e
[[ $rc -ne 0 ]] \
  || { echo "(A1) update targeting bbbb on a 2-marker line must exit non-zero, got 0"; exit 1; }
grep -qi 'ambiguous' <<<"$err" \
  || { echo "(A1) error must say AMBIGUOUS (stderr: $err)"; exit 1; }
grep -q 'aaaa' <<<"$err" && grep -q 'bbbb' <<<"$err" \
  || { echo "(A1) error must name both candidate ids aaaa and bbbb (stderr: $err)"; exit 1; }
after="$(cat "$tmp/TODO.md")"
[[ "$before" == "$after" ]] \
  || { echo "(A1) an ambiguous-line refusal must write NOTHING (file changed)"; diff <(echo "$before") <(echo "$after"); exit 1; }

# (A2) targeting the quoted body marker (aaaa) of the SAME ambiguous line must also
# raise, not silently mis-route to it — the line is unaddressable from either end.
seed_ambiguous
before="$(cat "$tmp/TODO.md")"
set +e
err="$(echo '{"updates":[{"id":"aaaa","line":"- [x] WRONGLY REWRITTEN <!-- id:aaaa -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md" 2>&1 >/dev/null)"
rc=$?
set -e
[[ $rc -ne 0 ]] \
  || { echo "(A2) update targeting aaaa on a 2-marker line must exit non-zero, got 0"; exit 1; }
grep -qi 'ambiguous' <<<"$err" \
  || { echo "(A2) error must say AMBIGUOUS (stderr: $err)"; exit 1; }
after="$(cat "$tmp/TODO.md")"
[[ "$before" == "$after" ]] \
  || { echo "(A2) an ambiguous-line refusal must write NOTHING (file changed)"; diff <(echo "$before") <(echo "$after"); exit 1; }

# (B) a single-marker line (cccc, elsewhere in the SAME file) still applies normally —
# the refusal is scoped to the ambiguous line, not a whole-file break.
seed_ambiguous
echo '{"updates":[{"id":"cccc","line":"- [x] unrelated single-marker item DONE <!-- id:cccc -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmp/TODO.md"
grep -q 'DONE <!-- id:cccc -->' "$tmp/TODO.md" \
  || { echo "(B) update to a single-marker line must still apply"; cat "$tmp/TODO.md"; exit 1; }

echo ok
