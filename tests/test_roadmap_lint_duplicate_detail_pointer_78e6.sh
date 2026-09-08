#!/usr/bin/env bash
# roadmap-lint.sh's detail-pointer extractor must return exactly ONE path for a
# ledger line that names its own note twice (id:78e6).
#
# No `# roadmap:` header: this is a defect-fix test, not a roadmap item's spec, so
# its failures always count.
#
# Defect: `item_detail_path()`'s `grep -oP -m1 <<<"${_rl_lines[$k]}"` bounds
# matching LINES, not matches per line -- `-m1` stops after the first matching
# LINE, but a here-string is exactly one line, so `-o` still prints EVERY match on
# it. A line whose gate-annotation reason text repeats `docs/ledger-notes/<id>.md`
# (once in the item's own head pointer, once inside the reason prose quoting that
# same path) makes `hit` a two-line string. `item_has_body_clause()` then tests
# `[[ -f "$_rl_notes_root/$rel" ]]` against that two-line `rel`, which is never a
# valid path, so it returns 2 (DETAIL-POINTER-MISSING) even though the note
# genuinely exists -- and because that is an early return, the note's real
# Acceptance/Tests/Done-check clause is never consulted (NO-ACCEPTANCE-NO-TWIN
# fires as a second, wrong finding). Measured live on id:8372 this review.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so
# the negative case is the parent revision of roadmap-lint.sh alone.
# fails-against-rev: HEAD~1 -- relay/scripts/roadmap-lint.sh
# fails-against-assertion: a note named twice on its own line was reported DETAIL-POINTER-MISSING even though it exists
#
# Hermetic: temp ROADMAP + TODO + docs/ledger-notes fixtures; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/docs/ledger-notes"
R="$tmp/ROADMAP.md"

# The line names docs/ledger-notes/d072.md TWICE -- once as the item's own
# pointer, once again inside a gate-annotation reason quoting the same path
# (the real id:8372 shape). Deliberately twin-less so the twin check cannot
# exempt it for the wrong reason.
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] duplicate pointer on one line -- detail: `docs/ledger-notes/d072.md` <!-- id:d072 --> — 🚧 GATED (auto, id:3801): see docs/ledger-notes/d072.md for the recorded rationale.
MD

cat >"$tmp/TODO.md" <<'MD'
# TODO

- [ ] an unrelated design-ledger entry <!-- id:f999 -->
MD

cat >"$tmp/docs/ledger-notes/d072.md" <<'MD'
# id:d072

## From ROADMAP

  - **Acceptance**: the relocated clause, reachable only through the pointer.
MD

set +e
bash "$LINT" "$R" 2>"$tmp/err" >/dev/null; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "default run must exit 0 (report-only), got $rc (err: $(cat "$tmp/err"))"

# (a) THE DEFECT: a present note, named twice on the same line, must not be
# reported missing.
! grep -q 'DETAIL-POINTER-MISSING: open item id:d072' "$tmp/err" \
  || fail "a note named twice on its own line was reported DETAIL-POINTER-MISSING even though it exists (err: $(cat "$tmp/err"))"

# (b) Consequence of (a): the note's real Acceptance clause must actually be
# reached, so NO-ACCEPTANCE-NO-TWIN must not fire either.
! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:d072' "$tmp/err" \
  || fail "the note's Acceptance clause was never consulted because the duplicate-pointer bug short-circuited the read (err: $(cat "$tmp/err"))"

pass "roadmap-lint's item_detail_path() takes the FIRST match when a line names its own detail note twice, so a present note is neither reported missing nor skipped for its acceptance clause (id:78e6)"
