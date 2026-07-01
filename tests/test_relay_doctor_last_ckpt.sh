#!/usr/bin/env bash
# roadmap:333c — relay-doctor check 11: last_ckpt tag existence (invariant I8) + the coverage-gap
# honesty block naming I5/I9. The integrator writes each own repo's relay.toml last_ckpt; a failed
# push / aborted tag can desync it. A dangling last_ckpt (names a tag that doesn't exist) is an
# invalid state a rev-parse --verify catches. Empty last_ckpt = not-yet-checkpointed = clean.
#
# RED until check 11 + the I5/I9 coverage-gap lines land.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-doctor.sh not executable"

FIX="$(mktemp -d)"; TOML="$(mktemp)"
trap 'rm -rf "$FIX" "$TOML"' EXIT
NAME="$(basename "$FIX")"   # relay-doctor uses basename(path) as the repo name in repo-scope
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
printf '# Roadmap\n\n## Items\n' > "$FIX/ROADMAP.md"; printf '# TODO\n' > "$FIX/TODO.md"
git -C "$FIX" add -A; git -C "$FIX" commit -qm init
git -C "$FIX" tag relay-ckpt-20260701-1200    # a real checkpoint tag
export RELAY_TOML="$TOML"

# Quote the key: a mktemp basename contains a dot, which bare TOML would read as table nesting.
write_toml() { printf '[repos."%s"]\nclassification = "own"\nlast_ckpt = "%s"\n' "$NAME" "$1" > "$TOML"; }

# (1) last_ckpt names a REAL tag → clean.
write_toml "relay-ckpt-20260701-1200"
out="$("$SH" "$FIX" 2>/dev/null)"
grep -A1 'last_ckpt tag existence' <<<"$out" | grep -q 'resolves to a tag' \
  || fail "(1) real last_ckpt tag not reported clean:\n$(grep -A2 'last_ckpt tag' <<<"$out")"
grep -q 'DANGLING' <<<"$out" && fail "(1) real tag wrongly flagged DANGLING:\n$out"
pass "(1) last_ckpt names a real tag → clean"

# (2) last_ckpt names a NON-existent tag → DANGLING, counted as an issue, --strict nonzero.
write_toml "relay-ckpt-19990101-0000"
out="$("$SH" "$FIX" 2>/dev/null)"
grep -q 'DANGLING' <<<"$out" || fail "(2) non-existent last_ckpt tag not flagged DANGLING:\n$(grep -A2 'last_ckpt tag' <<<"$out")"
rc=0; "$SH" --strict "$FIX" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(2b) --strict must exit nonzero on a dangling last_ckpt; got 0"
pass "(2) dangling last_ckpt → DANGLING + --strict nonzero"

# (3) empty last_ckpt → clean (not-yet-checkpointed).
write_toml ""
out="$("$SH" "$FIX" 2>/dev/null)"
grep -A1 'last_ckpt tag existence' <<<"$out" | grep -q 'not yet checkpointed' \
  || fail "(3) empty last_ckpt not reported clean:\n$(grep -A2 'last_ckpt tag' <<<"$out")"
grep -q 'DANGLING' <<<"$out" && fail "(3) empty last_ckpt wrongly flagged DANGLING:\n$out"
pass "(3) empty last_ckpt → clean"

# (4) coverage-gap honesty block names invariants I5 and I9 (not-yet-wired, by design).
out="$("$SH" "$FIX" 2>/dev/null)"
grep -qE 'invariant I5' <<<"$out" || fail "(4) coverage-gap block does not name invariant I5:\n$out"
grep -qE 'invariant I9' <<<"$out" || fail "(4) coverage-gap block does not name invariant I9:\n$out"
pass "(4) coverage-gap block names the gated invariants I5 + I9"

echo "ALL PASS: id:333c relay-doctor check 11 (last_ckpt tag existence, I8) + coverage-gap I5/I9"
