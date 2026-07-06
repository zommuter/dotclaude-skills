#!/usr/bin/env bash
# roadmap:abbd — RED spec: relay-state-write.sh `toml-set` must emit VALID TOML for a
# bare STRING value (especially hyphenated, e.g. status=handed-off), idempotently, WITHOUT
# breaking existing callers that pass a pre-quoted string, a bare bool, or a bare int.
#
# WHY (routed:dc81 from loderite /relay handoff 2026-07-04): `toml-set` wrote the value
# VERBATIM, so `toml-set <repo> status handed-off` produced `status = handed-off` — an
# invalid TOML bareword (the hyphen) that broke the pool's relay.toml read; the handoff
# had to be re-run with explicit quotes. The tool should quote a bare string value (leaving
# a pre-quoted value, a bare bool, and a bare int untouched) so callers can't produce
# invalid TOML.
#
# AUTHORED BY THE HANDOFF (strong model), NOT the executor (anti-gaming split): the executor
# makes this GREEN by smart-quoting the value in relay-state-write.sh — it must NOT weaken
# this test. Idempotent rule the executor should implement: value already wrapped in "..." →
# verbatim; value is `true`/`false` → verbatim (bare bool); value matches ^-?[0-9]+(\.[0-9]+)?$
# → verbatim (bare number); otherwise wrap in double quotes (bare string, incl. hyphenated).
#
# Hermetic: FABLES_CONFIG → mktemp; log → /dev/null; no ~/.config, no network. RED until abbd lands.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/relay-state-write.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-state-write.sh not found/executable at $SH"
command -v python3 >/dev/null 2>&1 || fail "python3 required"
python3 -c 'import tomllib' 2>/dev/null || fail "python3 tomllib required (>=3.11)"

export FABLES_CONFIG; FABLES_CONFIG="$(mktemp -d)"
export RELAY_STATE_WRITE_LOG=/dev/null
trap 'rm -rf "$FABLES_CONFIG"' EXIT
TOML="$FABLES_CONFIG/relay.toml"

cat >"$TOML" <<'MD'
[repos.demo]
classification = "own"
status = "pending"
fable_rechecked = false
MD

# repr() of repos.demo.<field>, or raise (nonzero) if the file is not valid TOML.
getval() { python3 -c "import tomllib; d=tomllib.load(open('$TOML','rb')); print(repr(d['repos']['demo'].get('$1','<<MISSING>>')))"; }
valid()  { python3 -c "import tomllib; tomllib.load(open('$TOML','rb'))" 2>/dev/null; }

# (a) a hyphenated BARE string must be quoted → the file stays VALID TOML -------
"$SH" toml-set demo status handed-off
valid || fail "(a) after 'toml-set status handed-off' the file must remain VALID TOML (a bare hyphenated word is not)"
[[ "$(getval status)" == "'handed-off'" ]] \
  || fail "(a) status must be the string 'handed-off' (got $(getval status))"
pass "(a) a bare hyphenated string is quoted → valid TOML"

# (b) a PRE-QUOTED value must NOT be double-quoted (backward-compat / idempotent) -
"$SH" toml-set demo last_ckpt '"relay-ckpt-20260615-1200"'
valid || fail "(b) file must stay valid TOML after a pre-quoted write"
[[ "$(getval last_ckpt)" == "'relay-ckpt-20260615-1200'" ]] \
  || fail "(b) a pre-quoted value must be written verbatim, not double-quoted (got $(getval last_ckpt))"
pass "(b) an already-quoted value is written verbatim (no double-quote)"

# (c) a bare bool must stay a BARE bool (not the string \"true\") ----------------
"$SH" toml-set demo fable_rechecked true
valid || fail "(c) file must stay valid TOML after a bool write"
[[ "$(getval fable_rechecked)" == "True" ]] \
  || fail "(c) a bare bool must stay a bool, not become a quoted string (got $(getval fable_rechecked))"
pass "(c) a bare bool is preserved as a bool"

# (d) a bare integer must stay a BARE int (not the string \"5\") -----------------
"$SH" toml-set demo some_count 5
valid || fail "(d) file must stay valid TOML after an int write"
[[ "$(getval some_count)" == "5" ]] \
  || fail "(d) a bare int must stay an int, not become a quoted string (got $(getval some_count))"
pass "(d) a bare int is preserved as an int"

echo "ALL PASS: relay-state-write toml-set smart-quote (id:abbd)"
