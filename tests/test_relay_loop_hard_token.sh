#!/usr/bin/env bash
# roadmap:3c0f — relay-loop.js classifier must key on the CANONICAL `[HARD — pool]`
# lane token, not the stale pre-id:78ff `[HARD — strong model]`.
#
# WHY (audit 2026-06-23): id:78ff made `[HARD — pool]` the single canonical lane token
# (hard-lanes.md, gather-human-backlog.sh, project_manager scan.py) and back-filled
# this repo's only pool-executable HARD item, id:401c, to `[HARD — pool]`. But the
# relay-loop.js classifier — the `hard` verdict, the `openHard` count, and the
# HARD-execute child's dispatch prompt — was left keyed on the OLD bare token
# `[HARD — strong model]`. Net effect: a `[HARD — pool]` item is HIDDEN from
# /relay human ("the pool runs it") yet the loop's EXECUTABLE-HARD test looks for a
# different literal, so the pool can compute openHard=0 and never emit a `hard`
# verdict → the item falls in the crack between loop and human = drained pool despite
# open work. There is also a latent landmine: gather LOUD-rejects `[HARD — strong model]`
# as untagged, so any own-repo using the loop's token would break `/relay human`.
#
# Asserts:
#   - relay-loop.js contains NO occurrence of the stale `HARD — strong model` token;
#   - relay-loop.js references the canonical `[HARD — pool]` lane in its hard logic;
#   - the canonical token relay-loop.js keys on is defined in hard-lanes.md (the SoT),
#     so the two code consumers cannot drift again.
#
# Hermetic: pure static read of the checked-in files; no network, no ~/.claude.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
VOCAB="$SRC_DIR/relay/references/hard-lanes.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]]    || fail "relay-loop.js not found at $JS"
[[ -f "$VOCAB" ]] || fail "hard-lanes.md (lane SoT) not found at $VOCAB"

# 1. The stale token must be gone everywhere in the classifier.
if grep -qF 'HARD — strong model' "$JS"; then
  echo "offending lines:" >&2
  grep -nF 'HARD — strong model' "$JS" >&2
  fail "relay-loop.js still references the stale '[HARD — strong model]' token — sync it to the canonical '[HARD — pool]' (id:78ff / hard-lanes.md)"
fi
pass "relay-loop.js carries no stale '[HARD — strong model]' token"

# 2. The canonical lane token is present in the hard logic.
grep -qF '[HARD — pool]' "$JS" \
  || fail "relay-loop.js never references the canonical '[HARD — pool]' lane token"
pass "relay-loop.js references the canonical '[HARD — pool]' token"

# 3. The token relay-loop.js keys on must be defined in the shared vocabulary (no drift).
grep -qF '[HARD — pool]' "$VOCAB" \
  || fail "hard-lanes.md does not define '[HARD — pool]' — the shared contract drifted"
pass "the loop's lane token is defined in hard-lanes.md (consumers agree)"

echo "ALL PASS: relay-loop.js hard-token canonicalization (roadmap:3c0f)"
