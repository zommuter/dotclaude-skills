#!/usr/bin/env bash
# roadmap:05b0
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:05b0 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY — the "you run these" list is the one tier the owner acts on directly, and it is
# polluted by a bare substring match. Two sites bucket an item as kind=manual on
# `grep -qi '@manual'`: emit_boxes() (relay/scripts/gather-human-backlog.sh:172, the
# REVIEW_ME path) and the ROADMAP scan (:539). Observed live 2026-07-29 during
# `/relay human .`: id:af48 — a DESIGN item whose title DISCUSSES the `@wire`/`@manual`
# grammar split — was collected as `manual`, i.e. presented as a scenario a human must RUN.
# Harmless that once because a human read it; but a list of things-to-run that contains
# things-not-to-run stops being trusted. Same unanchored-substring family as id:bf19
# (roadmap-lint state claims) and id:0d58/id:d259 (lane tags); same fix shape — match the
# tag in its grammatical position (a standalone marker, not inside a backtick span).
#
# TRIANGULATION — the negative and positive cases are deliberately interleaved so neither
# "always manual" nor "never manual" can pass: (1)+(2) are the two mention shapes that must
# NOT bucket, from BOTH call sites; (3)+(4) are the real markers that MUST still bucket,
# from BOTH call sites; (5) pins the un-marked REVIEW_ME default; (6) keeps the sibling
# markers out of scope. A fix applied to only one of the two grep sites fails (1)-vs-(2) or
# (3)-vs-(4).
#
# Hermetic: a temp RELAY_TOML + temp own repos under mktemp -d. RELAY_TOML/SRC_DIR/HOME are
# redirected; the real registry and the real ~/.claude are never read or written.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -x "$SCRIPT" ]] || { echo "FAIL: gather-human-backlog.sh not found/executable at $SCRIPT" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src/repoM"

# ROADMAP.md — the :539 call site.
#   id:aaaa  MENTIONS `@manual` inside a backtick span (the af48 shape)  -> must NOT be manual
#   id:bbbb  carries a REAL standalone @manual marker                    -> MUST be manual
#   id:eeee  contains the substring inside a longer word (`@manually`)     -> must NOT be manual
cat >"$tmp/src/repoM/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [INPUT — meeting] **`drained` machine-verdict + `@wire`/`@manual` grammar split** — a DESIGN item ABOUT the tag, not a scenario to run <!-- id:aaaa -->
- [ ] [ROUTINE] Verify the tunnel by hand on the device @manual <!-- id:bbbb -->
- [ ] [ROUTINE] Document that the tag is spelled @manually nowhere in the grammar <!-- id:eeee -->
MD

cat >"$tmp/src/repoM/TODO.md" <<'MD'
# TODO
MD

# REVIEW_ME.md — the emit_boxes() :172 call site, same two shapes plus the default bucket.
#   id:cccc  MENTIONS `@manual` in backticks   -> must stay the DEFAULT review_me bucket
#   id:dddd  carries a REAL @manual marker     -> MUST be manual
#   id:ffff  no marker at all                  -> review_me
#   id:9999  carries @needs-auth               -> untouched by this change
cat >"$tmp/src/repoM/REVIEW_ME.md" <<'MD'
# Review me

- [ ] Should the `@manual` grammar be split from `@wire`? A question ABOUT the marker. <!-- id:cccc -->
- [ ] Walk through the first-run wizard on the phone @manual <!-- id:dddd -->
- [ ] Is this interpretation of the spec right? <!-- id:ffff -->
- [ ] Rotate the API token @needs-auth <!-- id:9999 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoM]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" HOME="$tmp/home" bash "$SCRIPT" 2>"$tmp/err")"
rc=$?
set -e
(( rc == 0 )) || note "the fixture must collect cleanly (exit 0), got $rc; stderr: $(head -c 300 "$tmp/err")"

# kinds_of <id> — EVERY `kind` (3rd tab field) emitted for the row(s) carrying <id>, space
# separated; empty when the id was not emitted at all. It must be every row, not the first:
# one id legitimately appears twice (e.g. a lane-collector row AND a @manual row), and
# reading only the first would let the wrong bucket hide behind the right one.
kinds_of() {
  awk -F'\t' -v tok="$1" 'index($4, tok) { printf "%s ", $3 }' <<<"$out"
}
# has_kind <id> <kind>
has_kind() { grep -qw -- "$2" <<<"$(kinds_of "$1")"; }

# ── (1) ROADMAP: a backticked MENTION must NOT bucket as manual (the af48 miss) ────────
! has_kind 'id:aaaa' manual \
  || note "(1) a ROADMAP item that merely DISCUSSES \`@manual\` in its title was bucketed kind=manual — it lands on the 'you run these' checklist as a scenario a human must RUN. This is the live 2026-07-29 id:af48 miss"

# ── (2) ROADMAP: the substring inside a longer word must NOT bucket as manual ──────────
! has_kind 'id:eeee' manual \
  || note "(2) '@manually' contains '@manual' as a substring but is not a marker in any grammatical position — an unanchored grep cannot tell them apart, which is the defect"

# ── (3) ROADMAP: a REAL standalone marker MUST still bucket as manual ──────────────────
has_kind 'id:bbbb' manual \
  || note "(3) a genuine standalone @manual ROADMAP box no longer buckets as manual (see the emitted kinds above) — anchoring must narrow the match, not delete the feature"

# ── (4) REVIEW_ME: a REAL standalone marker MUST still upgrade to manual ──────────────
has_kind 'id:dddd' manual \
  || note "(4) a genuine standalone @manual REVIEW_ME box no longer upgrades to kind=manual (see the emitted kinds above) — the emit_boxes() call site must keep working"

# ── (5) REVIEW_ME: a backticked MENTION keeps the DEFAULT review_me bucket ─────────────
[[ "$(kinds_of 'id:cccc')" == "review_me " ]] \
  || note "(5) a REVIEW_ME box that merely mentions \`@manual\` must keep the default review_me bucket (see the emitted kinds above)"

[[ "$(kinds_of 'id:ffff')" == "review_me " ]] \
  || note "(5) an unmarked REVIEW_ME box must still default to review_me (see the emitted kinds above) — the default path must be untouched"

# ── (6) the sibling @needs-auth marker is out of scope and must be unaffected ──────────
[[ "$(kinds_of 'id:9999')" == "review_me " ]] \
  || note "(6) the @needs-auth box changed bucket (see the emitted kinds above) — this item re-anchors @manual ONLY; do not opportunistically re-anchor the sibling markers here"

# ── (7) BOTH call sites must be fixed by the SAME predicate, not one grep each ─────────
# Structural, and deliberately weak: it only asserts the bare unanchored `grep -qi '@manual'`
# is gone from the script. Two independently-hand-anchored greps is the id:0d58 second-reader
# class this repo has been bitten by three times already.
if grep -nE "grep -qi '@manual'" "$SCRIPT" >/dev/null; then
  note "(7) a bare unanchored \"grep -qi '@manual'\" is still present in gather-human-backlog.sh — both call sites must route through ONE shared anchored predicate"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:05b0 not built yet" >&2; exit 1; }
echo "ALL PASS: @manual is matched as an anchored marker, not a substring (id:05b0)"
