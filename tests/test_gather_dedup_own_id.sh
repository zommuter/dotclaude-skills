#!/usr/bin/env bash
# Defect-fix test (no roadmap item — found and fixed during /relay human 2026-07-30).
#
# gather-human-backlog.sh's id:4e67 TODO/ROADMAP dedup must key on each row's OWN id —
# the LAST `<!-- id:XXXX -->` on the line — never the FIRST `id:` match. The first match
# is very often an id CITED in the item's prose, which broke dedup in BOTH directions:
#
#   OVER-COUNT   a TODO row keyed on a cited id never matches its own ROADMAP twin, so the
#                same item is emitted TWICE (measured on this repo before the fix: 76
#                hard_meeting rows for only 56 distinct ids — 20 ids emitted twice).
#   UNDER-COUNT  a TODO-only row whose cited first-id happens to sit in the seen set is
#                dropped outright — a SILENT under-report of real human backlog. Measured:
#                id:4a5c (the "move to a real issue tracker" substrate question), id:09a8
#                and id:df87 were invisible to /relay human.
#
# The seen set itself had the mirror bug: it was built with a bare
# `grep -oE 'id:[0-9a-f]{4}'` over the whole ROADMAP output, sweeping up every id CITED in
# any item's prose, so it was a polluted SUPERSET of the ids actually emitted.
#
# Same failure family as [[relay-human-gather-underreport]] (id:fa5c) by a different
# mechanism: /relay human quietly reporting less backlog than exists.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "gather-human-backlog.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/src/fixture"
mkdir -p "$REPO"

# A twin pair sharing id:aaaa across both ledgers (must be emitted ONCE), where the TODO
# body cites OTHER ids BEFORE its own trailing token — the shape that broke dedup.
cat > "$REPO/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [INPUT — meeting] **Twin item** — the ROADMAP view. <!-- id:aaaa -->
- [ ] [INPUT — meeting] **Citing item** — body mentions id:cccc and id:dddd early. <!-- id:bbbb -->
EOF

# id:cccc is TODO-ONLY and its body cites id:bbbb (a ROADMAP-emitted id) FIRST. Before the
# fix this row was keyed `id:bbbb`, found it in `seen`, and vanished.
cat > "$REPO/TODO.md" <<'EOF'
# TODO

- [ ] [INPUT — meeting] **Twin item** — the TODO view, relates id:9999 first. <!-- id:aaaa -->
- [ ] [INPUT — meeting] **Todo-only item** — relates id:bbbb (cited first). <!-- id:cccc -->
EOF

cat > "$TMP/relay.toml" <<EOF
[repos.fixture]
classification = "own"
confirmed = "2026-07-30"
# path: $REPO
EOF

out="$(RELAY_TOML="$TMP/relay.toml" SRC_DIR="$TMP/src" "$SH" fixture 2>/dev/null)"

# own id of a row = LAST <!-- id:XXXX --> in its box_summary
ids="$(printf '%s\n' "$out" | awk -F'\t' '$3 ~ /^hard_meeting$/ {
  s = $4; own = ""
  while (match(s, /<!-- id:[0-9a-f][0-9a-f][0-9a-f][0-9a-f] -->/)) {
    own = substr(s, RSTART + 8, 4); s = substr(s, RSTART + RLENGTH)
  }
  if (own != "") print own
}')"

count_of() { printf '%s\n' "$ids" | grep -cx "$1" || true; }

[[ -n "$ids" ]] || fail "no hard_meeting rows emitted at all; got output: $out"

# 1. The twin sharing id:aaaa is emitted exactly ONCE (dedup works: ROADMAP row wins).
n="$(count_of aaaa)"
[[ "$n" == "1" ]] || fail "id:aaaa (in BOTH ledgers) must be emitted exactly once, got $n"
pass "twin id present in both ledgers → emitted exactly once (no double-count)"

# 2. The TODO-only row is NOT dropped, even though its body cites a ROADMAP id first.
n="$(count_of cccc)"
[[ "$n" == "1" ]] || fail "id:cccc (TODO-only, cites ROADMAP id:bbbb first) must be emitted exactly once, got $n — the silent under-report"
pass "TODO-only row citing a ROADMAP id first → still emitted (no silent under-report)"

# 3. No id is emitted more than once anywhere.
dupes="$(printf '%s\n' "$ids" | sort | uniq -d | tr '\n' ' ')"
[[ -z "${dupes// /}" ]] || fail "ids emitted more than once: $dupes"
pass "no id emitted twice"

# 4. The cited ids must never be mistaken for rows of their own.
for ghost in dddd; do
  n="$(count_of "$ghost")"
  [[ "$n" == "0" ]] || fail "id:$ghost is only CITED in prose and must never be emitted as a row, got $n"
done
pass "prose-cited id never emitted as a row of its own"

echo "ALL PASS"
