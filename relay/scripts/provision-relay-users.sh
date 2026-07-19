#!/usr/bin/env bash
# provision-relay-users.sh — id:13ae (sandbox meeting 2026-07-08-1214, D1)
#
# Idempotently provision the TWO mechanical-daemon service users the ratified
# relay sandbox splits apart (forged-recipe isolation = build-time, D1):
#
#   relay-ro   (A) read-only discovery producer   — id:9d97 (discover-repos-mechanical)
#   relay-svc  (B) recipe-exec daemon              — id:b3d0 (mechanical-daemon)
#
# These are UNPRIVILEGED service users with NO secrets and NO push credential —
# they are the mechanical tier, NOT the LLM executor/(C) `relay-pool` tier (that
# tier is id:38bf, ssh-push model, gated on af30, and is NOT provisioned here).
#
# Group/uid layout (documented per id:13ae):
#   - each user gets its OWN primary group of the same name (no shared group —
#     a flat shared group would hand relay-ro write on recipes/, reopening the
#     producer-forges-recipe hole D1 paid a uid to close; D2).
#   - uids are auto-assigned by useradd in the regular range (relay-probe took
#     1001; these follow). Home /home/<user>, shell /bin/bash, linger enabled so
#     `systemctl --user` units (id:8e7a, separate) can run without an active login.
#   - each user's gitconfig carries `safe.directory = *` so relay-ro running git
#     (discover-sig.sh) against tobias-owned repos does not trip git's dubious-
#     ownership guard and silently produce nothing (Sven's D2 gotcha).
#
# Write-isolation itself (the per-directory ACL matrix on ~/.config/relay) is a
# SEPARATE, co-shipped script: apply-relay-acls.sh (id:02c7). Unit migration onto
# these users (root-owned units in /etc/systemd/user/, hardening directives, the
# shared EnvironmentFile) is the follow-up id:8e7a — NOT done here.
#
# Privileged steps use `sudo -A` (graphical askpass per the global SUDO convention);
# export SUDO_ASKPASS=/usr/lib/ssh/ssh-askpass before running, or use `make
# install-relay-users` which the Makefile wires. Re-running is safe (idempotent).
set -euo pipefail

SERVICE_USERS=(relay-ro relay-svc)
declare -A USER_DESC=(
  [relay-ro]="relay read-only discovery producer id9d97"
  [relay-svc]="relay recipe-exec daemon id-b3d0"
)

log() { printf '  %s\n' "$*"; }

sudo_a() { SUDO_ASKPASS="${SUDO_ASKPASS:-/usr/lib/ssh/ssh-askpass}" sudo -A "$@"; }

echo "provision-relay-users (id:13ae) — creating the mechanical-daemon service users"

for u in "${SERVICE_USERS[@]}"; do
  if id -u "$u" >/dev/null 2>&1; then
    log "$u already exists (uid $(id -u "$u")) — skipping useradd"
  else
    log "creating $u"
    # --user-group → own primary group of the same name (no shared group, D2).
    # -m home, -s shell; -c comment. System-service user in the regular range.
    sudo_a useradd --create-home --user-group --shell /bin/bash \
      --comment "${USER_DESC[$u]}" "$u"
    log "  created $u (uid $(id -u "$u"), group $(id -gn "$u"))"
  fi

  # gitconfig safe.directory=* for the service user (D2 / Sven gotcha). Idempotent:
  # --get-all first so re-runs do not append duplicates.
  if sudo_a -u "$u" git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
    log "  $u gitconfig safe.directory=* already set"
  else
    sudo_a -u "$u" git config --global --add safe.directory '*'
    log "  $u gitconfig safe.directory=* set"
  fi

  # Enable linger so `systemctl --user` units (id:8e7a) run without an active login.
  if loginctl show-user "$u" 2>/dev/null | grep -qx 'Linger=yes'; then
    log "  $u linger already enabled"
  else
    sudo_a loginctl enable-linger "$u"
    log "  $u linger enabled"
  fi
done

echo "done. Provisioned: ${SERVICE_USERS[*]}"
echo "Next: apply-relay-acls.sh (id:02c7) to enforce the write matrix; id:8e7a migrates the units."
