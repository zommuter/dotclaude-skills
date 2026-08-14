#!/usr/bin/env bash
# roadmap:f391
#
# `@owner-gated` must be a FIRST-CLASS parked-section exclusion in
# relay/scripts/lib-roadmap-sections.sh — NOT an accident of substring matching.
#
# Today (verified 2026-08-14) the string `@owner-gated` appears NOWHERE in
# lib-roadmap-sections.sh. A heading like loderite's
#     ### `@owner-gated` — an executor CANNOT discharge these
# is parked ONLY because the literal `@owner-gated` happens to CONTAIN the vocab
# word `gated`, and the vocab is applied as an UNANCHORED substring test (:65).
# Loderite has three open items (f303, d385, 6e7a) whose dispatch protection rests
# on that coincidence.
#
# id:6446 (GATED on this item) will ANCHOR that vocabulary so a heading merely
# MENTIONING a vocab word stops parking its section. Anchoring removes the
# coincidence in the same edit — an owner-gate breach. This spec is what makes the
# anchoring safe to land later.
#
# THE LOAD-BEARING PROPERTY is before-AND-after: case (3) does not merely assert
# "parked today", it copies relay/scripts verbatim, rewrites ONLY the anchorable
# word-vocabulary into an ANCHORED form (a faithful stand-in for id:6446), and
# asserts the `@owner-gated` heading is STILL parked — by the bash predicate and by
# every production reader. A fixture that passes only before is not evidence.
#
# Hermetic: everything under mktemp -d; no ~/.claude, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/relay/scripts"
LIB="$SCRIPTS/lib-roadmap-sections.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -f "$LIB" ]] || { echo "lib-roadmap-sections.sh missing"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"; mkdir -p "$RELAY_WORKTREE_BASE"

OWNER_HEADING='### `@owner-gated` — an executor CANNOT discharge these'

# ── (1) NAMED, not incidental ─────────────────────────────────────────────────
# The marker must be spelled in the shared lib. This is the tripwire for the
# "protection by coincidence" state; cases (2)/(3) are the behavioural evidence.
grep -qF '@owner-gated' "$LIB" \
  && ok "'@owner-gated' is spelled in lib-roadmap-sections.sh (first-class, not a substring accident)" \
  || bad "'@owner-gated' appears NOWHERE in lib-roadmap-sections.sh — its protection is a substring coincidence (id:f391)"

# The marker must be defined SEPARATELY from the anchorable word vocabulary, so
# anchoring the words (id:6446) cannot reach it.
grep -qE '^ROADMAP_PARKED_HEADING_MARKERS=' "$LIB" \
  && ok "an explicit ROADMAP_PARKED_HEADING_MARKERS half exists, independent of the word vocabulary" \
  || bad "no separate ROADMAP_PARKED_HEADING_MARKERS definition — the marker still rides on the word vocabulary"

# ── (2) parked TODAY (bash predicate + every production reader) ───────────────
# shellcheck source=/dev/null
source "$LIB"
if is_exempt_heading "$OWNER_HEADING"; then
  ok "(before) is_exempt_heading parks an '@owner-gated' heading"
else
  bad "(before) is_exempt_heading does NOT park an '@owner-gated' heading"
fi
# negative control: an ordinary active heading must NOT be parked
if is_exempt_heading '## Items'; then
  bad "(control) '## Items' wrongly treated as parked — the exclusion over-broadened"
else
  ok "(control) an ordinary '## Items' heading is not parked"
fi
# negative control on the MARKER half alone: `@owner-gatedness` must not satisfy the
# marker pattern. (Through is_exempt_heading it still parks TODAY via the un-anchored
# word `gated` — that is id:6446's job, not this item's — so probe the marker directly.)
if [[ "## Notes on @owner-gatedness and other topics" =~ ${ROADMAP_PARKED_HEADING_MARKERS:-@owner-gated} ]]; then
  bad "(control) the MARKER pattern matches '@owner-gatedness' — it must be a standalone token"
else
  ok "(control) the MARKER pattern rejects '@owner-gatedness' (standalone-token anchored)"
fi

mkrepo() {  # mkrepo <roadmap-content-file> -> repo path
  local rm_src="$1" repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"; git -C "$repo" config user.name "T"
  cp "$rm_src" "$repo/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A; git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

cat > "$tmpdir/owner.md" <<EOF
# Roadmap

## Items

- [ ] [ROUTINE] genuinely active routine item <!-- id:0001 -->
- [ ] [HARD] genuinely active pool item <!-- id:0002 -->

$OWNER_HEADING

- [ ] [ROUTINE] owner-gated routine work <!-- id:0003 -->
- [ ] [HARD] owner-gated pool work <!-- id:0004 -->
EOF

check_readers() {  # check_readers <scripts-dir> <label>
  local sdir="$1" label="$2" repo aro ohp
  repo="$(mkrepo "$tmpdir/owner.md")"
  aro="$("$sdir/classify-repo.sh" --emit unit --repo fixture --path "$repo" \
          | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
  [[ "$aro" == "1" ]] \
    && ok "($label) classify-repo.sh parks the @owner-gated section (actionable_routine_open=1)" \
    || bad "($label) classify-repo.sh actionable_routine_open=$aro, expected 1 — owner-gated item is DISPATCHABLE"
  ohp="$("$sdir/gather-repo-state.sh" --repo fixture --path "$repo" \
          | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))')"
  [[ "$ohp" == "1" ]] \
    && ok "($label) gather-repo-state.sh parks the @owner-gated section (open_hard_pool=1)" \
    || bad "($label) gather-repo-state.sh open_hard_pool=$ohp, expected 1 — owner-gated HARD item is DISPATCHABLE"
}

check_readers "$SCRIPTS" "before"

# ── (3) STILL parked once the word vocabulary is ANCHORED (the id:6446 world) ──
# Copy relay/scripts verbatim and rewrite ONLY the anchorable word half into an
# anchored form: the vocab word must be a standalone token, so `@owner-gated`
# (where `gated` is preceded by `-`) no longer matches it. If the marker is
# first-class, this changes nothing for owner-gated headings.
cp -r "$SCRIPTS" "$tmpdir/scripts"
python3 - "$tmpdir/scripts/lib-roadmap-sections.sh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r"^ROADMAP_PARKED_HEADING_WORDS=.*$", s, re.M)
if not m:
    sys.stderr.write("no ROADMAP_PARKED_HEADING_WORDS= line to anchor — the word vocabulary is "
                     "not separable from the marker (id:f391)\n")
    sys.exit(3)
anchored = ("ROADMAP_PARKED_HEADING_WORDS='(^|[^A-Za-z0-9_@-])"
            "(gated|deferred|done|icebox|archive|parked)([^A-Za-z0-9_-]|$)'")
open(p, 'w').write(s[:m.start()] + anchored + s[m.end():])
PY
mutrc=$?
if [[ $mutrc -ne 0 ]]; then
  bad "(after) could not simulate the id:6446 anchoring — no separable ROADMAP_PARKED_HEADING_WORDS"
else
  # The mutation must be a FAITHFUL id:6446 stand-in, not a nuke: a genuine parking
  # bucket must still park under it, and a mere prose mention must not.
  (
    # shellcheck source=/dev/null
    source "$tmpdir/scripts/lib-roadmap-sections.sh"
    is_exempt_heading '## Gated / deferred' || exit 11
    is_exempt_heading '## Done'             || exit 12
    is_exempt_heading '## User-injected promotion 2026-08-13 — archive-path stub design call' && exit 13
    is_exempt_heading "$OWNER_HEADING"      || exit 14
    is_exempt_heading '## Notes on @owner-gatedness and other topics' && exit 15
    exit 0
  )
  rc=$?
  case "$rc" in
    0)  ok "(after) with the word vocab ANCHORED: '@owner-gated' still parks, real buckets still park, prose mentions do not" ;;
    11) bad "(after) the anchoring stand-in broke '## Gated / deferred' — mutation is not faithful, not evidence" ;;
    12) bad "(after) the anchoring stand-in broke '## Done' — mutation is not faithful, not evidence" ;;
    13) bad "(after) the anchoring stand-in did not actually anchor (an 'archive-path' prose mention still parks)" ;;
    14) bad "(after) '@owner-gated' STOPS parking once the word vocab is anchored — the owner-gate breach id:f391 exists to prevent" ;;
    15) bad "(after) '@owner-gatedness' still parks under an anchored vocab — the marker half is not standalone-anchored" ;;
    *)  bad "(after) unexpected rc=$rc from the anchored-vocab probe" ;;
  esac
  check_readers "$tmpdir/scripts" "after"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
