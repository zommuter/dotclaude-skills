#!/usr/bin/env bash
# SPEC for id:046a — the two REMAINING ledger archivers must be WIRED.
#
# NO `# roadmap:` HEADER ON PURPOSE. id:046a is TODO-tracked and has not been promoted to
# ROADMAP.md, so this file claims no expected-red exemption: its failures always count.
#
# ── THE SHAPE THIS GUARDS ─────────────────────────────────────────────────────────────
#   Three ledger archivers exist. Verified 2026-08-27, only ONE was wired:
#     roadmap-archive.sh   ROADMAP.md      WIRED — integrate.sh step 6b (id:f54d)
#     archive-closed.sh    REVIEW_ME.md    NO CALL SITE AT ALL — its only four code
#                                          references were two comments and two remedy
#                                          STRINGS telling an operator to run it by hand
#     relay-log-archive.sh RELAY_LOG.md    NO CALL SITE — `grep -c` returned 0 in BOTH
#                                          relay-loop.js and relay/SKILL.md; the Makefile
#                                          install manifest was the only reference anywhere
#   That is the built-green-but-unreferenced class id:f54d was opened for, twice over. Its
#   sibling file (test_roadmap_archive_wired_f54d.sh) guards the one that IS wired; this file
#   guards the other two, in the same static-contract-plus-behaviour shape.
#
# ── THE SCOPE ASSERTION IS NOT GARNISH ────────────────────────────────────────────────
#   archive-closed.sh archives THREE ledgers (TODO, ROADMAP, REVIEW_ME). A bare invocation at
#   integrate would run a SECOND archiver over ROADMAP.md one step after roadmap-archive.sh
#   already rotated it — two archivers, two stub grammars, same lines (the collision id:fdc4
#   says to examine BEFORE either is wired) — and would take over TODO.md from its own
#   owner-facing path. The measured relief says only REVIEW_ME gains: REVIEW_ME 30.3–91.0%,
#   TODO 2.7–56.1%, ROADMAP −0.5% to +3.0%, NET-NEGATIVE for two repos. So `--only review_me`
#   is pinned here as part of the wiring, and a widening of it is a FAILURE, not a nicety.
#
# ── THE EXIT CONTRACT (id:2c2a) ───────────────────────────────────────────────────────
#   `EX_*` are STEP-IDENTITY codes, not exit codes: handback() prints its KEY=VALUE block to
#   STDOUT (mirrored to stderr) carrying handback=/handbackCode=/handbackReason=, and EXITS 0.
#   Non-zero is reserved for genuinely undeterminable outcomes (the EX_USAGE=2 mis-invocation
#   sites). Both new steps must therefore hand back through handback() at exit 0, with their
#   OWN distinct codes. Distinctness is asserted over EVERY EX_* in the file, not just the new
#   pair — a duplicate anywhere collapses attribution.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INTEG="$SRC_DIR/relay/scripts/integrate.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
REVIEW_ARCH="$SRC_DIR/relay/scripts/archive-closed.sh"
LOG_ARCH="$SRC_DIR/relay/scripts/relay-log-archive.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
pass() { echo "PASS: $*"; }
# NON-EXITING: this file pins two independent wirings plus an exit contract, and a
# first-failure exit would hide which of them is unmet.
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
die()  { echo "FIXTURE-ERROR: $*"; exit 2; }

[[ -x "$INTEG" ]]       || die "integrate.sh not found/executable at $INTEG"
[[ -x "$REVIEW_ARCH" ]] || die "archive-closed.sh not found/executable at $REVIEW_ARCH"
[[ -x "$LOG_ARCH" ]]    || die "relay-log-archive.sh not found/executable at $LOG_ARCH"
[[ -f "$JS" ]]          || die "relay-loop.js not found at $JS"
grep -q 'relay/scripts/integrate.sh' "$JS" \
  || fail "relay-loop.js does not dispatch integrate.sh — everything wired into it is wired to nothing"

# Line number of the FIRST executed (non-comment) line CONTAINING a literal substring.
# `index()`, not a regex: every needle here is shell source full of `$`, `[` and `{`, and
# escaping those into an awk ERE is how this check silently matches nothing. `awk`, not
# `grep | head`: a producer piped into an early-exiting consumer is banned repo-wide (id:81d5).
code_line() {
  awk -v needle="$2" '{ l=$0; sub(/^[ \t]+/,"",l) } substr(l,1,1) != "#" && index($0, needle) { print NR; exit }' "$1"
}
ckpt_line="$(code_line "$INTEG" '"$CKPT_TAG" "${ckpt_args[@]}"')"
[[ -n "$ckpt_line" ]] || die "integrate.sh has no ckpt-tag step to anchor against"

# ======================================================================================
# (1) archive-closed.sh — WIRED, and SCOPED to REVIEW_ME.
# ======================================================================================
rev_line="$(code_line "$INTEG" '"$REVIEW_ARCHIVE"')"
if [[ -z "$rev_line" ]]; then
  fail "(1) integrate.sh never INVOKES \$REVIEW_ARCHIVE — archive-closed.sh is still unwired (its only references fleet-wide were two comments and two remedy strings)"
else
  pass "(1) archive-closed.sh is invoked from the serialized integrator (line $rev_line)"
fi
grep -qF -- 'INTEGRATE_REVIEW_ARCHIVE:-$SCRIPT_DIR/archive-closed.sh' "$INTEG" \
  && pass "(1) \$REVIEW_ARCHIVE resolves to relay/scripts/archive-closed.sh via an INTEGRATE_* override (the hermetic failure-injection seam every other step has)" \
  || fail "(1) \$REVIEW_ARCHIVE does not resolve to relay/scripts/archive-closed.sh through an INTEGRATE_REVIEW_ARCHIVE override"
grep -qF -- '"$REVIEW_ARCHIVE" --only review_me "$path"' "$INTEG" \
  && pass "(1) invoked as '--only review_me' on the unit's repo path" \
  || fail "(1) THE SCOPE IS WRONG OR MISSING: expected '\"\$REVIEW_ARCHIVE\" --only review_me \"\$path\"'. A bare invocation runs a SECOND archiver over ROADMAP.md one step after roadmap-archive.sh already did (id:fdc4's double-archiver collision) and takes TODO.md from its own path — and the measured relief is NET-NEGATIVE on ROADMAP for two repos. Got: $(awk '/\$REVIEW_ARCHIVE/ && !/^[[:space:]]*#/ {print NR": "$0}' "$INTEG" | tr '\n' ' ')"
if [[ -n "$rev_line" ]]; then
  [[ "$rev_line" -lt "$ckpt_line" ]] \
    && pass "(1) the REVIEW_ME archive runs BEFORE ckpt-tag — the rotation is part of the checkpointed state, not left dangling into worktree-retire" \
    || fail "(1) the REVIEW_ME archive runs AFTER ckpt-tag (archive=$rev_line, ckpt=$ckpt_line)"
  step="$(awk -v a="$rev_line" -v c="$ckpt_line" 'NR>=a && NR<c' "$INTEG")"
  grep -qF -- 'add -- REVIEW_ME.md REVIEW_ME.archive.md' <<<"$step" \
    && pass "(1) scoped staging of REVIEW_ME.md + REVIEW_ME.archive.md only (id:debf — never -A/./-u)" \
    || fail "(1) the step does not scope-stage REVIEW_ME.md + REVIEW_ME.archive.md"
  grep -qF -- 'status --porcelain -- REVIEW_ME.md REVIEW_ME.archive.md' <<<"$step" \
    && pass "(1) the commit is gated on an ACTUAL change (porcelain check) — no empty commits" \
    || fail "(1) the step does not gate its commit on a porcelain check"
fi

# ======================================================================================
# (2) relay-log-archive.sh — WIRED.
# ======================================================================================
log_line="$(code_line "$INTEG" '"$RELAY_LOG_ARCHIVE" "$path"')"
if [[ -z "$log_line" ]]; then
  fail "(2) integrate.sh never INVOKES \$RELAY_LOG_ARCHIVE — relay-log-archive.sh is still unwired (grep -c returned 0 in BOTH relay-loop.js and relay/SKILL.md; the Makefile manifest was its only reference anywhere). RELAY_LOG.md grows on EVERY relay round and is counted against the review dispatch budget (id:7c5f/id:502f)."
else
  pass "(2) relay-log-archive.sh is invoked on the unit's repo path (line $log_line)"
fi
grep -qF -- 'INTEGRATE_RELAY_LOG_ARCHIVE:-$SCRIPT_DIR/relay-log-archive.sh' "$INTEG" \
  && pass "(2) \$RELAY_LOG_ARCHIVE resolves to relay/scripts/relay-log-archive.sh via an INTEGRATE_* override" \
  || fail "(2) \$RELAY_LOG_ARCHIVE does not resolve through an INTEGRATE_RELAY_LOG_ARCHIVE override"
if [[ -n "$log_line" ]]; then
  [[ "$log_line" -lt "$ckpt_line" ]] \
    && pass "(2) the RELAY_LOG rotation runs BEFORE ckpt-tag" \
    || fail "(2) the RELAY_LOG rotation runs AFTER ckpt-tag (rotate=$log_line, ckpt=$ckpt_line)"
  step="$(awk -v a="$log_line" -v c="$ckpt_line" 'NR>=a && NR<c' "$INTEG")"
  grep -qF -- 'add -- RELAY_LOG.md RELAY_LOG.archive.md' <<<"$step" \
    && pass "(2) scoped staging of RELAY_LOG.md + RELAY_LOG.archive.md only" \
    || fail "(2) the step does not scope-stage RELAY_LOG.md + RELAY_LOG.archive.md"
  grep -qF -- 'status --porcelain -- RELAY_LOG.md RELAY_LOG.archive.md' <<<"$step" \
    && pass "(2) the commit is gated on an ACTUAL change (porcelain check)" \
    || fail "(2) the step does not gate its commit on a porcelain check"
fi

# ======================================================================================
# (3) THE EXIT CONTRACT (id:2c2a) — new steps hand back through handback(), never bare exits,
#     and every EX_* step-identity code in the file stays DISTINCT.
# ======================================================================================
for pair in "review-archive:EX_REVIEW_ARCHIVE" "relay-log-archive:EX_LOG_ARCHIVE"; do
  step_label="${pair%%:*}"; var="${pair##*:}"
  grep -q "handback $step_label \"\\\$$var\"" "$INTEG" \
    && pass "(3) the $step_label step routes its failure through handback() with its own \$$var" \
    || fail "(3) no 'handback $step_label \"\$$var\"' in integrate.sh — the step either swallows its failure or exits bare. Since id:2c2a a handback MUST go through handback() and inherit exit 0; a bare 'exit <code>' would be read as an UNDETERMINABLE outcome."
  grep -qE "^$var=[0-9]+" "$INTEG" \
    && pass "(3) $var is defined in the EX_* step-identity block" \
    || fail "(3) $var is not defined as a step-identity code"
done
# A wiring bug (helper missing/not executable) is its own LOUD class — EX_WIRING, exactly as
# roadmap-archive's step does it — never a silent skip that would let a ledger grow unbounded
# while the run reports success.
for step_label in review-archive relay-log-archive; do
  grep -q "handback $step_label \"\\\$EX_WIRING\"" "$INTEG" \
    && pass "(3) $step_label guards on an executable helper and hands back EX_WIRING when it is missing" \
    || fail "(3) $step_label has no EX_WIRING executable guard — a missing helper would be a silent skip, and the ledger would grow unbounded while the run reported success"
done
# EVERY step-identity code distinct — not just the new pair. A duplicate anywhere collapses
# attribution for BOTH steps that share it, which is the whole property id:2c2a preserved
# when it flattened the exit status.
mapfile -t EXVALS < <(awk '/^EX_[A-Z_]+=[0-9]+/ { split($0, a, "="); split(a[2], b, " "); print b[1] }' "$INTEG")
mapfile -t EXNAMES < <(awk '/^EX_[A-Z_]+=[0-9]+/ { split($0, a, "="); print a[1] }' "$INTEG")
NUNIQ="$(printf '%s\n' "${EXVALS[@]}" | sort -u | wc -l)"
if [[ "${#EXVALS[@]}" -ge 18 ]]; then
  pass "(3) integrate.sh defines ${#EXVALS[@]} step-identity codes (16 before id:046a, +2)"
else
  fail "(3) integrate.sh defines only ${#EXVALS[@]} EX_* codes — the two new archive steps did not get their own: ${EXNAMES[*]}"
fi
[[ "$NUNIQ" -eq "${#EXVALS[@]}" ]] \
  && pass "(3) all ${#EXVALS[@]} step-identity codes are DISTINCT — attribution is per-step" \
  || fail "(3) ${#EXVALS[@]} EX_* codes collapse to $NUNIQ distinct values — a step code was reused and two steps now hand back indistinguishably: $(paste -d= <(printf '%s\n' "${EXNAMES[@]}") <(printf '%s\n' "${EXVALS[@]}") | tr '\n' ' ')"

# ======================================================================================
# (4) BEHAVIOUR — both steps run UNCONDITIONALLY on every integrate, so the "safe no-op"
#     claim must actually hold. Hermetic fixtures; no network, no real repo.
# ======================================================================================
mkrepo() {
  local d="$TMP/$1"
  git init -q "$d" || die "init $d"
  git -C "$d" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init || die "commit $d"
  printf '%s' "$d"
}

# 4a. archive-closed --only review_me on a repo with NO REVIEW_ME.md at all.
R1="$(mkrepo none)"
out="$(HOME="$TMP/home" "$REVIEW_ARCH" --only review_me "$R1" 2>&1)" \
  || fail "(4a) archive-closed --only review_me exited non-zero on a repo with no REVIEW_ME.md: $out"
[[ -z "$(git -C "$R1" status --porcelain)" ]] \
  && pass "(4a) no-REVIEW_ME repo — clean exit, tree untouched" \
  || fail "(4a) archive-closed dirtied a repo that has no REVIEW_ME.md"

# 4b. THE SCOPE, BEHAVIOURALLY. A repo with closed items in ALL THREE ledgers: only
#     REVIEW_ME.md may move. This is the assertion a static grep cannot make — if `--only`
#     were accepted and ignored, every check in (1) would still pass.
R2="$(mkrepo scoped)"
printf '# TODO\n\n- [x] a closed todo <!-- id:1111 -->\n' > "$R2/TODO.md"
printf '# ROADMAP\n\n- [x] a closed roadmap item <!-- id:2222 -->\n' > "$R2/ROADMAP.md"
printf '# REVIEW_ME\n\n- [x] a closed review item <!-- id:3333 -->\n' > "$R2/REVIEW_ME.md"
git -C "$R2" add -A && git -C "$R2" -c user.email=t@e -c user.name=t commit -q -m seed \
  || die "(4b) seed"
HOME="$TMP/home" "$REVIEW_ARCH" --only review_me "$R2" >/dev/null 2>&1 \
  || fail "(4b) archive-closed --only review_me exited non-zero on the scoped fixture"
changed="$(git -C "$R2" status --porcelain | awk '{print $NF}' | sort | tr '\n' ' ')"
[[ -f "$R2/REVIEW_ME.archive.md" ]] && grep -q 'id:3333' "$R2/REVIEW_ME.archive.md" \
  && pass "(4b) the closed REVIEW_ME item WAS archived" \
  || fail "(4b) --only review_me archived nothing from REVIEW_ME.md — the scope flag disabled the wrong half. Changed: $changed"
grep -q 'id:1111' "$R2/TODO.md" && [[ ! -e "$R2/TODO.archive.md" ]] \
  && pass "(4b) TODO.md was NOT touched — it keeps its own owner-facing path" \
  || fail "(4b) --only review_me STILL ARCHIVED TODO.md. Either the flag is ignored or it is mis-scoped. Changed: $changed"
grep -q 'id:2222' "$R2/ROADMAP.md" && [[ ! -e "$R2/ROADMAP.archive.md" ]] \
  && pass "(4b) ROADMAP.md was NOT touched — roadmap-archive.sh already rotated it at step 6b; a second archiver over the same lines is the id:fdc4 collision" \
  || fail "(4b) --only review_me STILL ARCHIVED ROADMAP.md — that is the double-archiver collision, one step after step 6b already ran. Changed: $changed"

# 4c. A repo whose REVIEW_ME has only OPEN items — nothing archivable.
R3="$(mkrepo openonly)"
printf '# REVIEW_ME\n\n- [ ] an open review item <!-- id:4444 -->\n' > "$R3/REVIEW_ME.md"
git -C "$R3" add -A && git -C "$R3" -c user.email=t@e -c user.name=t commit -q -m seed || die "(4c) seed"
HOME="$TMP/home" "$REVIEW_ARCH" --only review_me "$R3" >/dev/null 2>&1 \
  || fail "(4c) archive-closed exited non-zero with nothing to archive"
[[ -z "$(git -C "$R3" status --porcelain)" ]] \
  && pass "(4c) nothing-to-archive — clean no-op, tree untouched, open items never moved" \
  || fail "(4c) archive-closed dirtied a repo with only OPEN items: $(git -C "$R3" status --porcelain | tr '\n' ' ')"

# 4d. relay-log-archive on a repo with NO RELAY_LOG.md.
R4="$(mkrepo nolog)"
out="$(HOME="$TMP/home" "$LOG_ARCH" "$R4" 2>&1)" \
  || fail "(4d) relay-log-archive exited non-zero on a repo with no RELAY_LOG.md: $out"
[[ -z "$(git -C "$R4" status --porcelain)" ]] \
  && pass "(4d) no-RELAY_LOG repo — clean exit, tree untouched" \
  || fail "(4d) relay-log-archive dirtied a repo that has no RELAY_LOG.md"

# 4e. THE SIZE FLOOR, behaviourally. A SMALL RELAY_LOG.md must be a complete no-op — this is
#     what makes per-integrate invocation safe on a merge=union file: the common case never
#     mutates it at all. Entries are dated 2020 (far past the 30-day age gate), so ONLY the
#     size floor can be holding them back.
R5="$(mkrepo smalllog)"
{ printf '# Relay log\n\n'
  for i in 1 2 3; do printf '## 2020-01-0%d — entry %d\n\nsome body text\n\n' "$i" "$i"; done
} > "$R5/RELAY_LOG.md"
git -C "$R5" add -A && git -C "$R5" -c user.email=t@e -c user.name=t commit -q -m seed || die "(4e) seed"
before="$(md5sum < "$R5/RELAY_LOG.md")"
HOME="$TMP/home" "$LOG_ARCH" "$R5" >/dev/null 2>&1 \
  || fail "(4e) relay-log-archive exited non-zero on a small log"
after="$(md5sum < "$R5/RELAY_LOG.md")"
[[ "$before" == "$after" && ! -e "$R5/RELAY_LOG.archive.md" ]] \
  && pass "(4e) a SMALL RELAY_LOG.md is a byte-exact no-op — the size floor is what makes per-integrate rotation safe on a merge=union file" \
  || fail "(4e) relay-log-archive MUTATED a small RELAY_LOG.md (or created an archive). merge=union does not protect a deletion, so the common case must not touch the file at all."
[[ -z "$(git -C "$R5" status --porcelain)" ]] \
  && pass "(4e) tree left clean" \
  || fail "(4e) relay-log-archive left the tree dirty: $(git -C "$R5" status --porcelain | tr '\n' ' ')"

# ======================================================================================
if [[ $FAILS -eq 0 ]]; then
  echo "ALL PASS: archive-closed.sh + relay-log-archive.sh are wired into the integrator (id:046a)"
  exit 0
fi
echo "FAILED: $FAILS assertion(s) — id:046a"
exit 1
