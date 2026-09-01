#!/usr/bin/env bash
# id:d51f(a) — WRITER-side enum validation for `bump_policy` in relay-state-write.sh.
#
# NO `# roadmap:` header ON PURPOSE: id:d51f is TODO-only (TODO.md:955); it has no
# ROADMAP.md checkbox, so the harness's expected-red semantics do not apply and every
# failure in this file is a REAL failure.
#
# fails-against: mutation — delete the `if [ "$key" = "bump_policy" ]` validation block in
# relay/scripts/relay-state-write.sh (the id:d51f(a) block just above the id:abbd
# smart-quoter). Assertions (b) and (c) then go RED: `toml-set demo bump_policy auto`
# exits 0 and lands `bump_policy = "auto"` in relay.toml. Verified by mutation before
# commit — both directions observed.
#
# WHY (owner decision 2026-08-22, TODO.md:955): `toml-set` is fully generic — it
# smart-quotes any value (id:abbd) and writes it — so `toml-set <repo> bump_policy auto`
# used to land verbatim and silently. The measured failure mode is not a typo but an agent
# INVENTING a plausible-but-absent enum member (`auto`, `none`, `patch-only`, `on-feature`).
# The writer is the load-bearing guard; integrate.sh's warn-and-default (id:d51f(b)) is
# defence in depth, and a warning alone degrades silently in an unattended --afk pool.
#
# THE ENUM IS THE READER'S, VERIFIED AGAINST THE CODE, not against prose: integrate.sh's
# `case "$policy" in` recognises exactly `never` (relay/scripts/integrate.sh:573) and
# `minor|patch` (:574); everything else hits the `*)` warn-and-default branch.
#
# SCOPE CONSTRAINT this file pins (assertion (d)): the validation is KEY-SCOPED. `toml-set`
# must NOT become enum-aware in general — any other key still takes an arbitrary value.
#
# Hermetic: FABLES_CONFIG → mktemp -d; log → /dev/null; never touches ~/.config/relay,
# ~/.claude, or the network.
# fails-against-rev: 09eb27709c88 -- relay/scripts/relay-state-write.sh
# fails-against-assertion: was ACCEPTED (exit 0) — the writer guard did not fire

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="${SH_OVERRIDE:-$SRC_DIR/relay/scripts/relay-state-write.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-state-write.sh not found/executable at $SH"
command -v python3 >/dev/null 2>&1 || fail "python3 required"
python3 -c 'import tomllib' 2>/dev/null || fail "python3 tomllib required (>=3.11)"

export FABLES_CONFIG; FABLES_CONFIG="$(mktemp -d)"
export RELAY_STATE_WRITE_LOG=/dev/null
trap 'rm -rf "$FABLES_CONFIG"' EXIT
TOML="$FABLES_CONFIG/relay.toml"

reset_toml() {
  cat >"$TOML" <<'MD'
[repos.demo]
classification = "own"
status = "pending"
MD
}

# repr() of repos.demo.<field> ('<<MISSING>>' when absent); nonzero if the file is not TOML.
getval() { python3 -c "import tomllib; d=tomllib.load(open('$TOML','rb')); print(repr(d['repos']['demo'].get('$1','<<MISSING>>')))"; }

ERR="$FABLES_CONFIG/stderr.txt"
RC=0
run() { RC=0; "$SH" toml-set demo "$@" >/dev/null 2>"$ERR" || RC=$?; }

# ── (a) every VALID value is ACCEPTED and actually WRITTEN ───────────────────────────
# Both spellings a caller may pass: bare (smart-quoted by id:abbd) and pre-quoted.
for v in never minor patch; do
  reset_toml
  run bump_policy "$v"
  [[ $RC -eq 0 ]] || fail "(a) bump_policy = $v was REFUSED (exit $RC): $(cat "$ERR")"
  [[ "$(getval bump_policy)" == "'$v'" ]] \
    || fail "(a) bump_policy = $v accepted but NOT written (got $(getval bump_policy))"
done
pass "(a) never/minor/patch are accepted and written"

for v in never minor patch; do
  reset_toml
  run bump_policy "\"$v\""
  [[ $RC -eq 0 ]] || fail "(a2) pre-quoted bump_policy = \"$v\" was REFUSED (exit $RC): $(cat "$ERR")"
  [[ "$(getval bump_policy)" == "'$v'" ]] \
    || fail "(a2) pre-quoted \"$v\" accepted but not written as $v (got $(getval bump_policy))"
done
pass "(a2) the same three values pre-quoted are accepted and written unchanged"

# ── (b) an INVENTED-but-plausible value is REFUSED, loudly, and writes NOTHING ───────
# `auto` is the exemplar the ratified item names; the others are its siblings.
for bad in auto none patch-only on-feature NEVER mnior; do
  reset_toml
  before="$(cat "$TOML")"
  run bump_policy "$bad"
  [[ $RC -ne 0 ]] || fail "(b) invented bump_policy = '$bad' was ACCEPTED (exit 0) — the writer guard did not fire"
  [[ "$(getval bump_policy)" == "'<<MISSING>>'" ]] \
    || fail "(b) invented bump_policy = '$bad' was WRITTEN anyway (got $(getval bump_policy))"
  [[ "$(cat "$TOML")" == "$before" ]] \
    || fail "(b) relay.toml was mutated by a REFUSED bump_policy = '$bad'"
done
pass "(b) auto/none/patch-only/on-feature/NEVER/mnior are all refused with non-zero exit, file untouched"

# ── (c) the refusal message NAMES the valid set and the offending value ──────────────
# Not a shape-grep on source: $ERR is the stderr the run above actually produced.
reset_toml
run bump_policy auto
[[ $RC -ne 0 ]] || fail "(c) precondition: 'auto' must be refused"
grep -q 'never|minor|patch' "$ERR" \
  || fail "(c) the refusal must NAME the valid set 'never|minor|patch'; got: $(cat "$ERR")"
grep -q "auto" "$ERR" \
  || fail "(c) the refusal must name the offending value 'auto'; got: $(cat "$ERR")"
pass "(c) the refusal names both the valid set and the rejected value"

# ── (d) KEY-SCOPED: any OTHER key still takes an arbitrary value ─────────────────────
# This is the owner's explicit scope constraint — toml-set must NOT become enum-aware in
# general. If a future change hoists the enum out of the `bump_policy` branch, this goes RED.
reset_toml
run status auto
[[ $RC -eq 0 ]] || fail "(d) an arbitrary value for a NON-bump_policy key was refused (exit $RC) — the validation leaked out of its key scope: $(cat "$ERR")"
[[ "$(getval status)" == "'auto'" ]] || fail "(d) status = auto was not written (got $(getval status))"

run some_policy patch-only
[[ $RC -eq 0 ]] || fail "(d2) 'some_policy' (a near-miss key name) was refused (exit $RC) — validation must key on bump_policy EXACTLY: $(cat "$ERR")"
[[ "$(getval some_policy)" == "'patch-only'" ]] || fail "(d2) some_policy = patch-only was not written (got $(getval some_policy))"
pass "(d) validation is key-scoped: other keys still accept arbitrary values"

# DELIBERATELY NOT ASSERTED HERE: writer/reader enum lockstep against integrate.sh's
# source text. A `grep -qE '^\s*minor\|patch\)' integrate.sh` would be exactly the
# SHAPE-ONLY source-grep the repo's own tests/lint-source-grep-assertions.py flags
# (id:05a2 / id:3a50) — this file never EXECUTES integrate.sh, so such a grep would prove
# nothing behavioural and would read as coverage it does not provide. The reader side is
# covered behaviourally by tests/test_bump_policy_fleet_default_65ad.sh, which drives
# integrate.sh end-to-end over all three values; the lockstep obligation is stated in the
# id:d51f(a) comment block in relay-state-write.sh.

echo "ALL PASS: $(basename "$0")"
