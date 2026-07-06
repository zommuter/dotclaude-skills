#!/usr/bin/env bash
# roadmap:4b37 — RED spec for the tag-first reorder tool + tag-first WARN lint.
# d259 endgame (C), meeting docs/meeting-notes/2026-07-06-0959-machine-tag-format-endgame.md.
#
# AUTHORED BY THE HANDOFF (strong model), NOT the executor (anti-gaming split, d259 D4):
# the executor implements lane-convert.sh --reorder + the roadmap-lint tag-first WARN to
# make this GREEN — it must NOT edit this spec to pass.
#
# CONTRACT the executor implements:
#   1. `lane-convert.sh --reorder <file>` prints the ledger on stdout with, on each CHECKBOX
#      line (`- [ ]` / `- [x]`), the lane-tag CLUSTER moved to immediately after the checkbox.
#      The cluster = the anchored PRIMARY lane token (first recognized bare lane tag, ignoring
#      backtick'd MENTIONS) PLUS any adjacent orthogonal `[INTENSIVE — <res>]`, order preserved.
#      Everything else on the line is left in place: title/body prose, NON-lane `[brackets]` in
#      the body, backtick'd tag MENTIONS, and the trailing `<!-- id:XXXX -->`. Whitespace is
#      normalized to single spaces where the cluster was lifted (no double space left behind).
#      IDEMPOTENT: a line whose cluster is already first is unchanged; a second pass is a no-op.
#      Composable with --in-place: `lane-convert.sh --in-place --reorder <file>` rewrites the file.
#   2. NON-checkbox lines (Why-bodies, `  - **Why**:` sub-bullets, prose, headings) are NEVER
#      touched — even when they mention a lane tag, including a backtick'd `[HARD — pool]`.
#   3. `roadmap-lint.sh` gains a tag-first WARN: a checkbox line whose lane tag is NOT the first
#      token after the checkbox is surfaced (report-only) with the stable diagnostic code
#      `TAG-NOT-FIRST` and the offending id, but the lint still EXITS 0 during the dual-vocab
#      window (a hard ERROR would false-fire on not-yet-reordered old-vocab lines — that flip is
#      7df1's final window-close step, not here). This is DISTINCT from ad8a's raw-vs-stripped
#      split-brain WARN: it fires on tag-POSITION even when there is no backtick divergence.
#
# Hermetic: temp fixtures; no ~/.claude, no network. RED until 4b37 lands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONV="$ROOT/relay/scripts/lane-convert.sh"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONV" ]] || fail "lane-convert.sh not found/executable at $CONV"
[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- (a) simple: a trailing lane tag moves to first position ------------------
a="$tmp/a.md"
cat >"$a" <<'MD'
# Roadmap

## Items

- [ ] **build the thing** [ROUTINE] <!-- id:aa01 -->
MD
out="$("$CONV" --reorder "$a" 2>/dev/null)" \
  || fail "(a) lane-convert.sh --reorder must be a supported mode"
got="$(grep -F 'id:aa01' <<<"$out")"
want='- [ ] [ROUTINE] **build the thing** <!-- id:aa01 -->'
[[ "$got" == "$want" ]] \
  || fail "(a) trailing [ROUTINE] must move to first position.\n  want: $want\n  got:  $got"
pass "(a) reorder lifts a trailing lane tag to first position"

# --- (b) multi-tag: primary + adjacent [INTENSIVE — res] both move, order kept -
b="$tmp/b.md"
cat >"$b" <<'MD'
# Roadmap

## Items

- [ ] **run the battery** [MECHANICAL] [INTENSIVE — r5-jvm] <!-- id:aa02 -->
MD
out="$("$CONV" --reorder "$b" 2>/dev/null)" || fail "(b) --reorder failed"
got="$(grep -F 'id:aa02' <<<"$out")"
want='- [ ] [MECHANICAL] [INTENSIVE — r5-jvm] **run the battery** <!-- id:aa02 -->'
[[ "$got" == "$want" ]] \
  || fail "(b) [MECHANICAL] + adjacent [INTENSIVE — res] must both move, order preserved.\n  want: $want\n  got:  $got"
pass "(b) reorder moves the primary lane + adjacent [INTENSIVE — res] as a cluster"

# --- (c) already-first is a no-op (both [ ] and [x]); second pass is a no-op ---
c="$tmp/c.md"
cat >"$c" <<'MD'
# Roadmap

## Items

- [ ] [HARD] **already leading, open** <!-- id:aa03 -->
- [x] [ROUTINE] **already leading, done** <!-- id:aa04 -->
MD
out="$("$CONV" --reorder "$c" 2>/dev/null)" || fail "(c) --reorder failed"
diff <(cat "$c") <(printf '%s\n' "$out") >/dev/null \
  || fail "(c) an already-tag-first ledger must be unchanged (idempotent, [ ] and [x])"
printf '%s\n' "$out" >"$tmp/c2.md"
out2="$("$CONV" --reorder "$tmp/c2.md" 2>/dev/null)" || fail "(c) --reorder second pass failed"
diff <(printf '%s\n' "$out") <(printf '%s\n' "$out2") >/dev/null \
  || fail "(c) a second --reorder pass must be a no-op (idempotent)"
pass "(c) reorder is idempotent (already-first no-op; second pass no-op)"

# --- (d) a NON-lane body [bracket] stays; only the recognized lane moves -------
d="$tmp/d.md"
cat >"$d" <<'MD'
# Roadmap

## Items

- [ ] fix the [foo] handler [ROUTINE] <!-- id:aa05 -->
MD
out="$("$CONV" --reorder "$d" 2>/dev/null)" || fail "(d) --reorder failed"
got="$(grep -F 'id:aa05' <<<"$out")"
want='- [ ] [ROUTINE] fix the [foo] handler <!-- id:aa05 -->'
[[ "$got" == "$want" ]] \
  || fail "(d) only the recognized lane tag moves; a non-lane body [bracket] stays put.\n  want: $want\n  got:  $got"
pass "(d) reorder moves only the recognized lane tag, not body brackets"

# --- (e) backtick'd tag MENTION must not be treated as the lane, and a
#         NON-checkbox line mentioning a backtick'd tag must be untouched -------
e="$tmp/e.md"
cat >"$e" <<'MD'
# Roadmap

## Items

- [ ] migrate the `[HARD — pool]` items to new vocab [ROUTINE] <!-- id:aa06 -->
  - **Why**: these were re-laned to `[HARD — pool]` last week and need a pass.
MD
out="$("$CONV" --reorder "$e" 2>/dev/null)" || fail "(e) --reorder failed"
got="$(grep -F 'id:aa06' <<<"$out")"
want='- [ ] [ROUTINE] migrate the `[HARD — pool]` items to new vocab <!-- id:aa06 -->'
[[ "$got" == "$want" ]] \
  || fail "(e) the REAL [ROUTINE] must move; the backtick'd [HARD — pool] mention stays in the body.\n  want: $want\n  got:  $got"
why_in="$(grep -F '**Why**' "$e")"
why_out="$(grep -F '**Why**' <<<"$out")"
[[ "$why_in" == "$why_out" ]] \
  || fail "(e) a non-checkbox Why-body line (mentioning a backtick'd [HARD — pool]) must be UNCHANGED"
pass "(e) backtick'd tag mentions and non-checkbox lines are left untouched"

# --- (f) roadmap-lint tag-first WARN: surfaced (TAG-NOT-FIRST + id) but exit 0 -
# Fixture has NO backtick divergence (so ad8a's split-brain WARN does not fire) — the
# ONLY reason to warn is tag POSITION, isolating the new check.
notfirst="$tmp/notfirst.md"
cat >"$notfirst" <<'MD'
# Roadmap

## Items

- [ ] **title precedes the tag** [ROUTINE] <!-- id:aa10 -->
MD
if ! lint_out="$("$LINT" "$notfirst" 2>&1)"; then
  fail "(f) tag-first must be WARN-only (exit 0) during the dual-vocab window, not an ERROR"
fi
grep -qF 'TAG-NOT-FIRST' <<<"$lint_out" \
  || fail "(f) roadmap-lint must surface a TAG-NOT-FIRST warning for a tag-not-first checkbox line"
grep -qF 'aa10' <<<"$lint_out" \
  || fail "(f) the TAG-NOT-FIRST warning must name the offending id (aa10)"

# A tag-first ledger must NOT emit the TAG-NOT-FIRST warning.
firstok="$tmp/firstok.md"
cat >"$firstok" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] **tag is first here** <!-- id:aa11 -->
MD
lint_ok="$("$LINT" "$firstok" 2>&1)" || fail "(f) a tag-first ledger must lint clean (exit 0)"
grep -qF 'TAG-NOT-FIRST' <<<"$lint_ok" \
  && fail "(f) a tag-first ledger must NOT emit a TAG-NOT-FIRST warning (false positive)"
pass "(f) roadmap-lint TAG-NOT-FIRST WARN fires on position only, report-only (exit 0)"

# --- (g) TAB whitespace at the lift/trim site must not hang (audit Run 70) ------
# Regression: reorder_rest's right-trim and roadmap-lint's after-checkbox trim both
# guarded on [[:space:]]* but stripped only a literal ' ', so a TAB satisfied the
# loop guard forever without being consumed → infinite loop. A tab-bearing line must
# process and terminate (bounded by `timeout`).
g="$tmp/g.md"
printf -- '- [ ] Title [ROUTINE]\t<!-- id:aa20 -->\n' >"$g"
gout="$(timeout 10 "$CONV" --reorder "$g" 2>/dev/null)" \
  || fail "(g) --reorder must terminate on a tab after the lane tag (no infinite loop)"
grep -qF '[ROUTINE] Title' <<<"$gout" \
  || fail "(g) reorder must still lift the tag when a tab trails it.\n  got: $gout"
gl="$tmp/gl.md"
printf -- '- [ ] \t[ROUTINE] Title <!-- id:aa21 -->\n' >"$gl"
timeout 10 "$LINT" "$gl" >/dev/null 2>&1 \
  || fail "(g) roadmap-lint must terminate on a tab after the checkbox (no infinite loop)"
pass "(g) tab whitespace at the lift/trim site terminates (no infinite loop)"

echo "ALL PASS: tag-first reorder tool + tag-first WARN lint (id:4b37)"
