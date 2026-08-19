#!/usr/bin/env bash
# roadmap:5bef — author the systemd units + hardening for the two relay service users
# (authoring half of id:8e7a). Asserts the emitted unit CONTENT against a fixture: literal
# absolute paths (never %h — Amendment-2 F3), the hardening directives, the uid assertion
# guard in both entrypoint scripts, and the shared EnvironmentFile — WITHOUT ever installing
# to the real /etc/systemd/user/ or invoking sudo (hermetic, per the repo's test contract).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TOOLS="$ROOT/tools"
ENVFILE="$TOOLS/relay-service-users.env"
RO_SVC="$TOOLS/relay-ro-discover-repos-mechanical.service"
RO_TIMER="$TOOLS/relay-ro-discover-repos-mechanical.timer"
SVC_SVC="$TOOLS/relay-svc-mechanical-daemon.service"
SVC_PATH="$TOOLS/relay-svc-mechanical-daemon.path"
SVC_TIMER="$TOOLS/relay-svc-mechanical-daemon.timer"

for f in "$ENVFILE" "$RO_SVC" "$RO_TIMER" "$SVC_SVC" "$SVC_PATH" "$SVC_TIMER"; do
  [[ -f "$f" ]] || fail "expected hardened-unit file missing: $f"
done
pass "all six hardened-unit files exist under tools/"

# --- .service files: User=, no %h, the hardening directives, EnvironmentFile, uid guard ---
for pair in "relay-ro:$RO_SVC" "relay-svc:$SVC_SVC"; do
  user="${pair%%:*}"; svc="${pair#*:}"
  name="$(basename "$svc")"

  grep -qE "^User=${user}\$" "$svc" || fail "$name must set User=$user"
  pass "$name sets User=$user"

  grep -vE '^\s*#' "$svc" | grep -q '%h' && fail "$name uses %h in a directive — under $user's OWN --user manager %h resolves to /home/$user, not tobias's home (Amendment-2 F3); every path must be literal"
  pass "$name carries no %h in any directive (literal paths only)"

  grep -qE '^EnvironmentFile=/home/[^%]+/tools/relay-service-users\.env$' "$svc" \
    || fail "$name must load the shared EnvironmentFile via a literal absolute path"
  pass "$name loads the shared EnvironmentFile via a literal path"

  grep -qE "^Environment=RELAY_REQUIRE_SERVICE_USER=${user}\$" "$svc" \
    || fail "$name must set RELAY_REQUIRE_SERVICE_USER=$user so the entrypoint's uid guard fires on a mis-wired User="
  pass "$name sets RELAY_REQUIRE_SERVICE_USER=$user"

  for directive in NoNewPrivileges=true PrivateTmp=true ProtectHome=true; do
    grep -qF "$directive" "$svc" || fail "$name missing hardening directive: $directive"
  done
  pass "$name carries NoNewPrivileges/PrivateTmp/ProtectHome"

  grep -qE '^ReadOnlyPaths=' "$svc" || fail "$name missing ReadOnlyPaths= carve-out (required once ProtectHome=true masks /home/tobias)"
  grep -qE '^ReadWritePaths=' "$svc" || fail "$name missing ReadWritePaths= carve-out (required once ProtectHome=true masks /home/tobias)"
  pass "$name carries ReadOnlyPaths=/ReadWritePaths= carve-outs"

  grep -qE '^ExecStart=/home/[^%]' "$svc" || fail "$name's ExecStart= must be a literal absolute path, not %h-relative"
  pass "$name's ExecStart= is a literal absolute path"
done

# --- the EnvironmentFile: literal paths only, no $HOME/~/%h, covers every var the two
#     entrypoint scripts read via a $HOME-relative default ---
for var in RELAY_TOML SRC_DIR RELAY_DISCOVERY_QUEUE_DIR RELAY_WORKTREE_BASE RELAY_DISCOVER_MECH_LOG HEARTBEAT_BASE \
           RELAY_RECIPE_DIR RELAY_INTENSITY_FILE CLAIM_BASE CLAIM_LOG INJECT_BASE INJECT_LOG MECHANICAL_DAEMON_LOG; do
  grep -qE "^${var}=/" "$ENVFILE" || fail "relay-service-users.env missing a literal-path assignment for $var"
done
pass "relay-service-users.env assigns a literal absolute path for every \$HOME-relative override"

ENVFILE_ASSIGN_LINES="$(grep -E '^[A-Z_]+=' "$ENVFILE")"
echo "$ENVFILE_ASSIGN_LINES" | grep -q '\$HOME' && fail "relay-service-users.env must not use \$HOME in an assignment — it is loaded verbatim by systemd's EnvironmentFile= (no shell expansion)"
echo "$ENVFILE_ASSIGN_LINES" | grep -q '~' && fail "relay-service-users.env must not use ~ in an assignment — no shell expansion under EnvironmentFile="
echo "$ENVFILE_ASSIGN_LINES" | grep -q '%h' && fail "relay-service-users.env must not use %h in an assignment — %h resolves to the SERVICE user's home, not tobias's (Amendment-2 F3)"
pass "relay-service-users.env's assignments carry no \$HOME/~/%h shell-style or unit-specifier expansion"

# --- the two entrypoint scripts: the uid-assertion guard exists and is opt-in (unset by
#     default) so the existing tobias-run tools/discover-repos-mechanical.service and
#     tools/mechanical-daemon.service (and every hermetic test) are unaffected ---
DISCOVER_SH="$ROOT/relay/scripts/discover-repos-mechanical.sh"
DAEMON_SH="$ROOT/relay/scripts/mechanical-daemon.sh"

for f in "$DISCOVER_SH" "$DAEMON_SH"; do
  grep -q 'RELAY_REQUIRE_SERVICE_USER' "$f" || fail "$(basename "$f") has no RELAY_REQUIRE_SERVICE_USER uid-assertion guard (id:5bef acceptance: 'a loud EUID-is-a-relay-service-user guard in the producer and daemon entrypoints')"
done
pass "both entrypoint scripts carry the RELAY_REQUIRE_SERVICE_USER guard"

# Behavioural: a MISMATCHED RELAY_REQUIRE_SERVICE_USER must fail loudly before doing any work.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BOGUS_USER="definitely-not-a-real-user-$$-xyz"

out="$(RELAY_REQUIRE_SERVICE_USER="$BOGUS_USER" RELAY_TOML="$TMP/relay.toml" SRC_DIR="$TMP/src" \
       RELAY_DISCOVERY_QUEUE_DIR="$TMP/dq" RELAY_DISCOVER_MECH_LOG="$TMP/log.txt" \
       bash "$DISCOVER_SH" 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "discover-repos-mechanical.sh must exit nonzero when RELAY_REQUIRE_SERVICE_USER ($BOGUS_USER) does not match the invoking user"
echo "$out" | grep -qi 'hardening guard' || fail "discover-repos-mechanical.sh's uid-mismatch failure must name the id:5bef hardening guard (got: $out)"
pass "discover-repos-mechanical.sh refuses to run under a mismatched RELAY_REQUIRE_SERVICE_USER"

out="$(RELAY_REQUIRE_SERVICE_USER="$BOGUS_USER" RELAY_RECIPE_DIR="$TMP/recipes" MECHANICAL_DAEMON_LOG="$TMP/log2.txt" \
       bash "$DAEMON_SH" run 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "mechanical-daemon.sh must exit nonzero when RELAY_REQUIRE_SERVICE_USER ($BOGUS_USER) does not match the invoking user"
echo "$out" | grep -qi 'hardening guard' || fail "mechanical-daemon.sh's uid-mismatch failure must name the id:5bef hardening guard (got: $out)"
pass "mechanical-daemon.sh refuses to run under a mismatched RELAY_REQUIRE_SERVICE_USER"

# Behavioural: an UNSET RELAY_REQUIRE_SERVICE_USER (the existing tobias-run units' shape)
# must never trip the guard — confirm the guard's own message never appears when it is unset.
out="$(RELAY_TOML="$TMP/relay.toml" SRC_DIR="$TMP/src" RELAY_DISCOVERY_QUEUE_DIR="$TMP/dq" \
       RELAY_DISCOVER_MECH_LOG="$TMP/log3.txt" bash "$DISCOVER_SH" 2>&1 || true)"
echo "$out" | grep -qi 'hardening guard' && fail "discover-repos-mechanical.sh must NOT invoke the id:5bef guard when RELAY_REQUIRE_SERVICE_USER is unset (would break the existing tobias-run unit)"
pass "discover-repos-mechanical.sh's guard is a no-op when RELAY_REQUIRE_SERVICE_USER is unset"

# --- Makefile: a human-run install target exists, copies all six files, targets
#     /etc/systemd/user/, and uses sudo (never run by relay itself, per the executor
#     contract — this test only asserts the TEXT, never executes the target) ---
MAKEFILE="$ROOT/Makefile"
grep -q '^install-relay-hardened-units:' "$MAKEFILE" || fail "Makefile has no install-relay-hardened-units target"
pass "Makefile declares install-relay-hardened-units"

TARGET_BODY="$(awk '/^install-relay-hardened-units:/{f=1;next} /^[a-zA-Z_.-]+:/{f=0} f' "$MAKEFILE")"
echo "$TARGET_BODY" | grep -q '/etc/systemd/user/' || fail "install-relay-hardened-units must target /etc/systemd/user/"
echo "$TARGET_BODY" | grep -qi 'sudo' || fail "install-relay-hardened-units must use sudo (root-owned unit dir)"
for f in relay-service-users.env relay-ro-discover-repos-mechanical.service relay-ro-discover-repos-mechanical.timer \
         relay-svc-mechanical-daemon.service relay-svc-mechanical-daemon.path relay-svc-mechanical-daemon.timer; do
  echo "$TARGET_BODY" | grep -q "$f" || fail "install-relay-hardened-units must reference $f"
done
pass "install-relay-hardened-units copies all six files into /etc/systemd/user/ via sudo"

# Only a REAL (non-@echo) invocation counts — the target's own @echo instructions may
# quote a sample "systemctl --user enable" command for the human to run BY HAND under
# id:8e7a; that is documentation, not this target executing it.
echo "$TARGET_BODY" | grep -vE '^\s*@echo' | grep -qE 'systemctl --user enable' \
  && fail "install-relay-hardened-units must NOT enable the units itself — per-user enable is deliberately the id:8e7a run/verify half, not authored here"
pass "install-relay-hardened-units does not itself enable any unit (id:8e7a stays the run half)"

PHONY_BLOCK="$(awk '/^\.PHONY:/{f=1} f{print; if ($0 !~ /\\$/) exit}' "$MAKEFILE")"
echo "$PHONY_BLOCK" | grep -q 'install-relay-hardened-units' || fail ".PHONY must list install-relay-hardened-units"
pass "install-relay-hardened-units is declared .PHONY"

echo "all id:5bef hardened-unit checks passed"
