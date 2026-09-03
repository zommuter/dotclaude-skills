#!/usr/bin/env bash
# No roadmap header -- defect-fix / new-rule spec for TODO id:30fe. Failures always count.
#
# The structural SHAPE check. The owner's bar (2026-09-02): an item line carries only a
# lane tag, gate markers, its `id:` anchor, a short title and a detail pointer -- NO PROSE.
# The id:0d7c D4 length ratchet cannot express that: length is one number, and a 237-char
# line can be fully conforming or entirely prose.
#
# Also pins the SELF-CONFIGURING notes-directory rule, which is not cosmetic. The first cut
# of the id:e95b pointer-follow compared a pointer string built from a hardcoded
# `docs/ledger-notes` default, so it was measured INERT in loderite (pointers there say
# `docs/roadmap-notes`) while still reporting 19 findings that looked entirely real. A
# symlink cannot fix it -- the comparison is on the string, not the filesystem -- and a bare
# config parameter only moves the failure from "wrong default" to "unset everywhere", which
# is indistinguishable in the output. So the directory is DERIVED from the pointer the line
# already carries. Cases (e)/(f) are that rule.
#
# fails-against: the rule and this spec land in the same commit, so both negative cases are
# mutations of the shipped predicates rather than an ancestor checkout.
# fails-against-mutation: python3 -c "import io,sys; p='relay/scripts/todo-conformance.sh'; s=io.open(p,encoding='utf-8').read(); s=s.replace('  (( \${#r} > 8 )) || return 0','  return 0',1); io.open(p,'w',encoding='utf-8').write(s)"
# fails-against-assertion: (a) a prose-carrying line must be reported
# fails-against-mutation: sed -i 's|\[A-Za-z0-9_.-\]+(?:/\[A-Za-z0-9_.-\]+)\*/\${idtok}|docs/ledger-notes/${idtok}|' relay/scripts/roadmap-lint.sh
# fails-against-assertion: (f) a FOREIGN notes directory must still resolve
#
# Hermetic: temp ledgers + temp notes dirs; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/relay/scripts/todo-conformance.sh"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONF" && -x "$LINT" ]] || fail "sanity: both scripts must exist and be executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# HERMETICITY (id:2d17): todo-conformance.sh defaults BOTH ratchet baselines to committed
# files, and this test's fixture ledgers use the real basenames, so without these overrides
# the live repo's baseline decides this test's verdict. Latent since the length ratchet
# landed -- masked only because its budget is 500 chars and these fixtures are short. The
# shape ratchet fires at 8 chars of residue and unmasked it immediately. Pointing both at
# absent paths keeps the ratchets INERT, which is the state this file's assertions describe.
export SHAPE_BASELINE="$tmp/no-shape-baseline.txt"
export LENGTH_BASELINE="$tmp/no-length-baseline.txt"

T="$tmp/TODO.md"
cat >"$T" <<'MD'
# TODO

## Current

- [ ] [ROUTINE] **A fully conforming item** -- detail: `docs/ledger-notes/aa01.md` <!-- gated-on:aa09 --> <!-- id:aa01 -->
- [ ] [ROUTINE] **A titled item** that then keeps a whole sentence of explanatory prose on the line, which is exactly what the bar forbids. <!-- id:aa02 -->
- [ ] [HARD] **A conforming item with several markers** 🚧 `@manual` <!-- children:aa01,aa03 --> <!-- id:aa03 -->
- [ ] [ROUTINE] **Second bold run is prose wearing emphasis** **RED SPEC LANDED 2026-08-13** <!-- id:aa04 -->
- [x] [ROUTINE] A closed item is checked too. This second sentence is prose and must be reported. <!-- id:aa05 -->
- [ ] [ROUTINE] A bold-less single-clause title with no sentence boundary at all <!-- id:aa06 -->
MD

# Capture ONCE into a variable and match with here-strings. `cmd | grep -q` pipes into an
# early-exiting consumer under pipefail, which is the id:81d5 shape this repo lints against;
# a here-string is not a pipe, so nothing upstream can take SIGPIPE.
CONF_OUT="$("$CONF" "$T" 2>/dev/null || true)"

# --- (a) a prose-carrying line is reported ------------------------------------------
grep -q '^shape-prose.*	.*id:aa02' <<<"$CONF_OUT" \
  || fail "(a) a prose-carrying line must be reported (got: $(cut -f1 <<<"$CONF_OUT" | sort -u | tr '\n' ' '))"

# --- (b) a conforming line is NOT reported ------------------------------------------
! grep -q 'id:aa01 -->' <<<"$CONF_OUT" \
  || fail "(b) a fully conforming line fired shape-prose: $(grep 'id:aa01' <<<"$CONF_OUT" | cut -c1-160)"
! grep -q 'id:aa03 -->' <<<"$CONF_OUT" \
  || fail "(b) a conforming line with lane, gate glyph, @marker and a typed edge fired shape-prose: $(grep 'id:aa03' <<<"$CONF_OUT" | cut -c1-160)"

# --- (c) a SECOND bold run is prose, not a second title ------------------------------
grep -q '^shape-prose.*id:aa04' <<<"$CONF_OUT" \
  || fail "(c) a second bold run must count as prose -- that is the exact shape that survived wave 1"

# --- (d) closed [x] items are checked too (owner ruling 2026-09-02) -------------------
grep -q '^shape-prose.*id:aa05' <<<"$CONF_OUT" \
  || fail "(d) a closed [x] item carrying prose must be reported; the owner ruled closed items are in scope"

# --- (d2) a BOLD-LESS title is a title, not prose ------------------------------------
# The owner's ratified titling rule (2026-09-02): with no bold run the title is the leading
# text up to the first sentence or clause boundary. 183 open items have no bold run, and a
# checker that calls their titles prose demands a shape the shrinker will never produce --
# the composition rule head_refusable() documents. This assertion is what keeps the two
# predicates agreeing.
! grep -q '^shape-prose.*id:aa06' <<<"$CONF_OUT" \
  || fail "(d2) a bold-less single-clause title was reported as prose: $(grep 'id:aa06' <<<"$CONF_OUT" | cut -c1-160)"

# --- (e) the rule NEVER escalates: --strict must not fail on shape alone --------------
# 460 of 840 live lines fail this today, so an ERROR would refuse every commit.
set +e
"$CONF" --strict "$T" >/dev/null 2>&1; rc_strict=$?
set -e
[[ $rc_strict -eq 0 ]] \
  || fail "(e) shape-prose must never escalate under --strict (exit $rc_strict); it is WARN until id:6546 lands"

# --- (f) a FOREIGN notes directory still resolves ------------------------------------
# The loderite shape: pointers spell a directory this repo has never heard of. A checker
# that only recognises its own spelling reports every foreign pointer as prose, and the
# pointer-follow silently does nothing while its findings still look real.
F="$tmp/foreign"; mkdir -p "$F/docs/roadmap-notes"
cat >"$F/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] a shrunk item, clause relocated -- detail: `docs/roadmap-notes/bb01.md` <!-- id:bb01 -->
MD
cat >"$F/TODO.md" <<'MD'
# TODO
MD
cat >"$F/docs/roadmap-notes/bb01.md" <<'MD'
# id:bb01

## Continuation detail (verbatim, moved from ROADMAP.md)

  - **Acceptance**: reachable only by deriving the directory from the pointer.
MD

set +e
"$LINT" "$F/ROADMAP.md" 2>"$tmp/ferr" >/dev/null
set -e
! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:bb01' "$tmp/ferr" \
  || fail "(f) a FOREIGN notes directory must still resolve -- the clause is in docs/roadmap-notes/bb01.md and the follow found nothing (err: $(cat "$tmp/ferr"))"

# And the shape check must treat a foreign pointer as a pointer, not as prose.
cat >"$tmp/foreign-todo.md" <<'MD'
# TODO

- [ ] [ROUTINE] **A conforming item pointing at a foreign notes dir** -- detail: `docs/roadmap-notes/bb02.md` <!-- id:bb02 -->
MD
FOREIGN_OUT="$("$CONF" "$tmp/foreign-todo.md" 2>/dev/null || true)"
! grep -q '^shape-prose.*id:bb02' <<<"$FOREIGN_OUT" \
  || fail "(f) a foreign-directory detail pointer was counted as prose by the shape check"

pass "structural shape check (id:30fe) reports prose outside lane/gate/id/title/pointer, treats a second bold run as prose, covers closed [x] items, never escalates under --strict, and resolves a FOREIGN notes directory in both the checker and the id:e95b pointer-follow"
