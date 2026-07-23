#!/usr/bin/env bash
# roadmap:4239 — front-door mechanical-tier preflight. mech-preflight.sh consumes the id:99a4
# discriminator (probe-mech-proxy.sh) and turns each mode into a stdout signal + a LOUD stderr
# warning:
#   mode-a  -> stdout "fallback-haiku" + warning naming the restart env (real API reachable,
#              fall the model:"bash" hops to Haiku)
#   mode-b  -> stdout "abort" + warning "proxy down / whole session degraded" (Haiku ALSO
#              unreachable through a dead proxy — never a fallback)
#   healthy -> stdout "proceed", no warning
#
# The discriminator is STUBBED via the MECH_PROBE env override (a throwaway script that prints a
# forced mode), so this test is hermetic: no real ANTHROPIC_BASE_URL / port / network dependence.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREFLIGHT="$SRC_DIR/relay/scripts/mech-preflight.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

if [[ ! -f "$PREFLIGHT" ]]; then
  echo "FAIL: relay/scripts/mech-preflight.sh does not exist yet (RED spec, roadmap:4239)"
  exit 1
fi
if [[ ! -x "$PREFLIGHT" ]]; then
  echo "FAIL: mech-preflight.sh exists but is not executable"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# make_stub <mode>: write a throwaway discriminator that prints <mode> for `discriminate`.
make_stub() {
  local mode="$1"
  local path="$TMP/probe-$mode.sh"
  cat >"$path" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == "discriminate" ]] || { echo "unexpected arg" >&2; exit 2; }
echo "$mode"
EOF
  chmod +x "$path"
  echo "$path"
}

# --- case 1: mode-a -> fallback-haiku + warning naming the restart env ---------
stub="$(make_stub mode-a)"
out="$(MECH_PROBE="$stub" "$PREFLIGHT" preflight 2>"$TMP/err_a")"
rc=$?
if [[ $rc -eq 0 && "$out" == "fallback-haiku" ]]; then
  ok "mode-a -> stdout 'fallback-haiku' (exit 0)"
else
  bad "mode-a should emit 'fallback-haiku' on stdout (got out='${out}' rc=${rc})"
fi
if grep -q "ANTHROPIC_BASE_URL=http://127.0.0.1:61843" "$TMP/err_a"; then
  ok "mode-a warning names the exact restart env"
else
  bad "mode-a warning must name the restart env ANTHROPIC_BASE_URL=http://127.0.0.1:61843 (stderr: $(cat "$TMP/err_a"))"
fi
if [[ -s "$TMP/err_a" ]]; then
  ok "mode-a emits a LOUD warning to stderr"
else
  bad "mode-a must emit a warning to stderr"
fi

# --- case 2: mode-b -> abort + a whole-session-degraded warning ----------------
stub="$(make_stub mode-b)"
out="$(MECH_PROBE="$stub" "$PREFLIGHT" preflight 2>"$TMP/err_b")"
rc=$?
if [[ $rc -eq 0 && "$out" == "abort" ]]; then
  ok "mode-b -> stdout 'abort' (exit 0)"
else
  bad "mode-b should emit 'abort' on stdout (got out='${out}' rc=${rc})"
fi
if [[ -s "$TMP/err_b" ]]; then
  ok "mode-b emits a LOUD warning to stderr"
else
  bad "mode-b must emit a warning to stderr"
fi
# mode-b must NOT masquerade as a Haiku-fallback case.
if [[ "$out" != "fallback-haiku" ]]; then
  ok "mode-b is not a Haiku-fallback case"
else
  bad "mode-b must NEVER emit 'fallback-haiku' (Haiku is unreachable through a dead proxy)"
fi

# --- case 3: healthy -> proceed, no warning ------------------------------------
stub="$(make_stub healthy)"
out="$(MECH_PROBE="$stub" "$PREFLIGHT" preflight 2>"$TMP/err_h")"
rc=$?
if [[ $rc -eq 0 && "$out" == "proceed" ]]; then
  ok "healthy -> stdout 'proceed' (exit 0)"
else
  bad "healthy should emit 'proceed' on stdout (got out='${out}' rc=${rc})"
fi
if [[ ! -s "$TMP/err_h" ]]; then
  ok "healthy emits no warning (clean stderr)"
else
  bad "healthy must not warn (stderr: $(cat "$TMP/err_h"))"
fi

echo
echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
