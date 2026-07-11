#!/usr/bin/env bash
# roadmap:2b0b — add a 5th capability lane `[INPUT — author]` (human-expert-authored
# content) to the lane contract + its in-repo consumers. Today an `[INPUT — author]`
# item falls into gather-human-backlog.sh's `else` branch → `untagged` → LOUD nonzero
# reject, and hard-lanes.md does not define the marker. Contract:
#   (1) hard-lanes.md's capability table defines the `[INPUT — author]` marker.
#   (2) gather-human-backlog.sh buckets an `[INPUT — author]` item onto an author/owner
#       bucket (NOT meeting, NOT untagged) and the run exits 0 (no loud reject).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"
VOCAB="$ROOT/relay/references/hard-lanes.md"

fail() { echo "FAIL: $*"; exit 1; }

# (1) the shared contract defines the new lane marker.
grep -qF '[INPUT — author]' "$VOCAB" \
  || fail "hard-lanes.md does not define the [INPUT — author] capability marker (id:2b0b)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src/repoAuthor"
cat > "$tmp/src/repoAuthor/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [INPUT — author] Write the Experiment-1 results section <!-- id:a111 -->
- [ ] [HARD] A pool-executable apex item for contrast <!-- id:b222 -->
MD

cat > "$tmp/relay.toml" <<'TOML'
[repos.repoAuthor]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err")"
rc=$?
set -e

# (2a) an [INPUT — author] item must NOT force the untagged LOUD nonzero reject.
[[ $rc -eq 0 ]] \
  || fail "an [INPUT — author] item must be recognized (exit 0), got $rc (stderr: $(cat "$tmp/err"))"

# (2b) it must be bucketed onto an author/owner bucket — not meeting, not untagged.
grep -q 'Write the Experiment-1 results section' <<<"$out" \
  || fail "the [INPUT — author] item was not emitted (out: $out)"
grep -iP 'author' <<<"$(grep 'Experiment-1 results section' <<<"$out")" \
  || fail "the [INPUT — author] item must bucket onto an author/owner kind (out: $out)"
if grep 'Experiment-1 results section' <<<"$out" | grep -qi 'untagged'; then
  fail "the [INPUT — author] item must NOT be bucketed as untagged (out: $out)"
fi

echo ok
