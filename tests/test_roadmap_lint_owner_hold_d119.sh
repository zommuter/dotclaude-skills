#!/usr/bin/env bash
# roadmap:d119
# Spec for roadmap-lint.sh OWNER-HOLD recognition (id:d119), SCOPED to the linter only.
#
# id:540f / id:c179 carry an explicit OWNER hold ("does NOT land until the owner explicitly
# says so") expressed today as a `gated-on:b0b1` whose target is a TODO-only id — which the
# DEAD-GATE rule (id:49e0) reads as a FALSE dead gate. The owner rejected promoting b0b1 to
# ROADMAP (that would convert an owner hold into a technical one). The fix: an explicit
# owner-hold marker the linter understands, so a deliberately-held item is treated as
# INTENTIONAL rather than flagged DEAD-GATE — while a genuinely dead gate with no such marker
# still fires unchanged.
#
# Proposed grammar (confirm in REVIEW_ME): `<!-- owner-hold:REASON -->`.
#
# SCOPE: this guards ONLY roadmap-lint.sh (report-only). It asserts NOTHING about
# classify-repo.sh dispatch suppression or about migrating 540f/c179's real markers — those
# are a separate coordinated step (see the ROADMAP item's OUT-of-scope note).
#
# Hermetic: temp ROADMAP/TODO fixtures in mktemp -d; no ~/.claude, no network.
# Mirrors tests/test_roadmap_lint_dead_gate.sh's fixture shape.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 'dead' is a valid 4-hex token that exists NOWHERE (not ROADMAP, not TODO, not archive)
# => a genuine dead gate. Item/twin ids are all valid 4-hex (fa01/fa02).
cat >"$tmp/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:fa01 -->
- [ ] twin stub <!-- id:fa02 -->
MD

cat >"$tmp/TODO.archive.md" <<'MD'
# TODO archive
MD

cat >"$tmp/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] held item — dead gate PLUS an explicit owner-hold marker <!-- gated-on:dead --> <!-- owner-hold:remote-control-conflict --> <!-- id:fa01 -->
- [ ] [ROUTINE] plain item — the same dead gate, NO owner-hold marker <!-- gated-on:dead --> <!-- id:fa02 -->
MD

# --- default run: WARN-only, exit 0 --------------------------------------------------------
set +e
bash "$LINT" "$tmp/ROADMAP.md" >"$tmp/out" 2>"$tmp/err"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "default run must exit 0 (DEAD-GATE is WARN-only), got $rc (err: $(cat "$tmp/err"))"

# The owner-held item must NOT be flagged DEAD-GATE — the marker declares the hold intentional.
if grep -q 'id:fa01' < <(grep -E 'DEAD-GATE' "$tmp/err") ; then
  sed 's/^/    /' "$tmp/err"
  fail "an item carrying an owner-hold marker must NOT fire DEAD-GATE (id:d119 not yet built)"
fi
pass "an owner-held item with a dead gate is exempted from DEAD-GATE"

# The plain item with the same dead gate MUST still fire — the marker suppresses only itself.
grep -q 'id:fa02' < <(grep -E 'DEAD-GATE' "$tmp/err") \
  || { sed 's/^/    /' "$tmp/err"; fail "the unmarked item with a dead gate must STILL fire DEAD-GATE (the marker must not disable the rule globally)"; }
pass "an unmarked item with the same dead gate still fires DEAD-GATE"

# --- --strict still escalates the surviving finding to a non-zero exit ---------------------
set +e
bash "$LINT" --strict "$tmp/ROADMAP.md" >/dev/null 2>"$tmp/err2"; rc_s=$?
set -e
[[ $rc_s -ne 0 ]] || fail "--strict must exit non-zero while an unmarked dead gate remains"
grep -q 'id:fa02' < <(grep -E 'DEAD-GATE' "$tmp/err2") \
  || fail "--strict must still name the unmarked dead gate id:fa02 (err: $(cat "$tmp/err2"))"
if grep -q 'id:fa01' < <(grep -E 'DEAD-GATE' "$tmp/err2") ; then
  fail "--strict must NOT flag the owner-held item id:fa01 either"
fi
pass "--strict escalates the surviving unmarked dead gate, still exempts the owner-held one"

echo "ALL PASS: roadmap-lint owner-hold recognition (id:d119)"
