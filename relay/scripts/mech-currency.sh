#!/usr/bin/env bash
# mech-currency.sh — is the RUNNING mechanical-proxy current with its source? (roadmap:9e48)
#
# THE BLIND SPOT THIS CLOSES. mechanical-proxy.py binds ALLOWED_RELAY_SCRIPTS at import and
# has no reload path, so a long-running proxy keeps whatever allowlist was on disk when it
# started. On 2026-08-11 a proxy started 13:32 held a set predating the 19:22 commit that
# added provision-worktree.sh: 20 provision hops refused across 4 runs, every one fail-open
# passthrough → 404 ("issue with the selected model (bash)"), zero successes. All three
# existing guards reported healthy throughout, because none of them looks at the live process:
#   - tests/test_mech_fence_allowlist_completeness_5bbb.sh reads SOURCE
#   - probe-mech-proxy.sh is a pure TCP connect (no HTTP, no model name, no command)
#   - mech-preflight.sh maps a probe mode to a token
# This script compares what the live process PUBLISHED at startup against current source.
#
#   relay/scripts/mech-currency.sh --currency
#
# Exit 0  — current: the state file's digest equals the source digest AND its pid is alive.
# Exit 1  — STALE: digest mismatch, dead pid, unreadable/malformed state, or NO state file.
# Exit 2  — usage error.
#
# FAIL-CLOSED ON THE UNKNOWN: a MISSING state file is STALE, never healthy. The exact process
# this detects predates the state-file feature and therefore wrote none, so absence is the
# PRIMARY signal, not an excuse to pass.
#
# REPORT, DO NOT REFUSE (roadmap:9e48 scope). This script itself only makes staleness VISIBLE;
# it never blocks anything. Turning a STALE verdict into a refusal is a CALLER's decision and
# needs its own ratification — id:540f/id:c179 (the mech-preflight/relay-loop refusal pair)
# still carry an owner gate (gated-on:b0b1) and are NOT unblocked by the note below.
#
# ONE RATIFIED REFUSING CALLER (id:0384): the relay FRONT DOOR, step 0b of relay/SKILL.md, is
# authorised to treat a STALE verdict as a launch REFUSAL — matching the mode-b `abort` posture
# already in that step — and calls this check whenever the preflight probe says `proceed`. That
# carve-out is scoped to the front door's launch decision and to that step only; it does not
# license any other caller to auto-refuse, and it changes nothing in this script's behaviour.
#
# The source digest is NOT recomputed here — it is obtained by importing mechanical-proxy.py
# and calling its allowlist_digest(). One implementation of the predicate, on purpose: two
# would drift, and a drifting comparison is exactly the bug class above.
#
# Env:
#   MECH_PROXY_STATE  state file path, default ~/.config/relay/mech-proxy-state.json
#                     (must match the proxy's own default — same env var, same default)
#   MECH_PROXY_SRC    path to mechanical-proxy.py, default the sibling copy (tests override)
#
# Hermetic: reads only the state file and the proxy source; no writes, no network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_SRC="${MECH_PROXY_SRC:-$SCRIPT_DIR/mechanical-proxy.py}"
STATE_FILE="${MECH_PROXY_STATE:-$HOME/.config/relay/mech-proxy-state.json}"

usage() {
  echo "usage: mech-currency.sh --currency" >&2
  exit 2
}

case "${1:-}" in
  --currency|currency) ;;
  *) usage ;;
esac

if [[ ! -f "$PROXY_SRC" ]]; then
  echo "mech-currency: STALE (undeterminable) — no proxy source at $PROXY_SRC" >&2
  exit 1
fi

# Source digest, straight from the module's own allowlist_digest(). Importing is
# side-effect-free (the state file is written from main() only), so this cannot
# clobber the very file we are about to read.
src_digest="$(MECH_PROXY_STATE="$STATE_FILE" python3 - "$PROXY_SRC" <<'PY' 2>/dev/null || true
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mp", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
sys.stdout.write(m.allowlist_digest())
PY
)"

if [[ -z "$src_digest" ]]; then
  echo "mech-currency: STALE (undeterminable) — $PROXY_SRC exposes no usable allowlist_digest()" >&2
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  {
    echo "mech-currency: STALE — no proxy state file at $STATE_FILE."
    echo "  Either no mechanical proxy is running, or the running one PREDATES the state-file"
    echo "  feature — which is the very staleness this checks for (a pre-feature process holds"
    echo "  an in-memory ALLOWED_RELAY_SCRIPTS that may not match source, silently refusing"
    echo "  hops and falling open to a 404). Absence is not health. Restart the proxy to clear."
  } >&2
  exit 1
fi

# Parse once, emit three fields; a malformed/unreadable file yields nothing → STALE.
read -r st_pid st_digest st_started <<<"$(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        s = json.load(fh)
except Exception:
    sys.exit(0)
if not isinstance(s, dict):
    sys.exit(0)
pid = s.get("pid")
digest = s.get("allowlist_digest")
if pid is None or not digest:
    sys.exit(0)
print(pid, digest, s.get("started_at") or "unknown")
PY
)" || true

if [[ -z "${st_digest:-}" || -z "${st_pid:-}" ]]; then
  echo "mech-currency: STALE — state file $STATE_FILE is unreadable or missing pid/allowlist_digest" >&2
  exit 1
fi

if [[ "$st_digest" != "$src_digest" ]]; then
  {
    echo "mech-currency: STALE — the running proxy's allowlist does not match source."
    echo "  state file : $STATE_FILE (pid $st_pid, started $st_started)"
    echo "  in-process : $st_digest"
    echo "  on-disk    : $src_digest"
    echo "  The live process bound ALLOWED_RELAY_SCRIPTS at import and cannot reload it, so any"
    echo "  script added since it started is REFUSED — the hop falls open to the real API and"
    echo "  404s on model \"bash\". Restart mechanical-proxy.py to pick up the current allowlist."
  } >&2
  exit 1
fi

# Liveness: kill -0 fails with EPERM for a process owned by another user (the relay's
# tiered OS users), so /proc is the second, ownership-blind witness. Alive by EITHER.
if ! kill -0 "$st_pid" 2>/dev/null && [[ ! -d "/proc/$st_pid" ]]; then
  {
    echo "mech-currency: STALE — state file names pid $st_pid, which is not alive."
    echo "  state file : $STATE_FILE (started $st_started)"
    echo "  A state file outliving its process certifies nothing: the digest matches source, but"
    echo "  no proxy is holding it. Start mechanical-proxy.py (make relay-proxy-start)."
  } >&2
  exit 1
fi

echo "mech-currency: current — proxy pid $st_pid (started $st_started) holds the on-disk allowlist (${src_digest:0:12}…)"
exit 0
