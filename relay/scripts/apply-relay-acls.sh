#!/usr/bin/env bash
# apply-relay-acls.sh — id:02c7 (sandbox meeting 2026-07-08-1214, D2 + Amendment-2 F2)
#
# Idempotently enforce the per-directory named-POSIX-ACL WRITE MATRIX on
# ~/.config/relay so the mechanical-daemon service users (provision-relay-users.sh,
# id:13ae) are write-scoped at the KERNEL, not by documentation:
#
#   discovery-queue/  →  relay-ro  rwx           (producer writes discovery units)
#   recipes/          →  relay-svc rwx           (daemon consumes/moves recipes)
#   heartbeats/       →  relay-ro + relay-svc rwx (both beat; tobias watchdog reads)
#   claims/           →  relay-svc rwx           (daemon resource claims)
#   claims.done/      →  relay-svc rwx           (retired claims)
#   .claim.lock       →  relay-svc rwx           (cross-uid flock needs write)
#   .heartbeat.lock   →  relay-ro + relay-svc rwx (cross-uid flock, same F2 rationale)
#   (tobias keeps rwx everywhere via ownership; added to default ACLs explicitly)
#
# This makes id:1cb8's "only reviewer writes pending/" DAC-ENFORCED: relay-ro
# canNOT write recipes/, relay-svc canNOT write discovery-queue/ (asserted by the
# companion test). Default ACLs + setgid give inheritance so new files under each
# dir carry the same matrix. Directories/locks NOT in the matrix (relay.toml,
# relay-events.jsonl, RELAY_STATUS.md, …) stay tobias-only — untouched here.
#
# Runs as tobias (setfacl on tobias-owned paths needs no sudo). The named-user
# ACL entries require the users to EXIST — run provision-relay-users.sh first
# (this script fail-closes loudly if a user is missing). Idempotent: setfacl -m
# is a no-op when the entry already matches.
set -euo pipefail

RELAY_CONFIG="${RELAY_CONFIG_DIR:-$HOME/.config/relay}"

log() { printf '  %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$RELAY_CONFIG" ]] || die "$RELAY_CONFIG does not exist"
for u in relay-ro relay-svc; do
  id -u "$u" >/dev/null 2>&1 || die "user '$u' does not exist — run provision-relay-users.sh (id:13ae) first"
done

# Apply the matrix to a DIRECTORY: access ACL + matching default ACL + setgid.
# args: <dir> <acl-spec>...   e.g.  acl_dir discovery-queue "u:relay-ro:rwx"
acl_dir() {
  local dir="$RELAY_CONFIG/$1"; shift
  [[ -d "$dir" ]] || { log "skip (absent dir): $dir"; return 0; }
  local spec
  for spec in "$@"; do
    setfacl -m "$spec" "$dir"          # access ACL (this dir)
    setfacl -d -m "$spec" "$dir"       # default ACL (inherited by new children)
  done
  # tobias explicit in the default ACL too (belt-and-suspenders per D2 "tobias everywhere")
  setfacl -d -m "u:$(id -un):rwx" "$dir"
  chmod g+s "$dir"                     # setgid: new files inherit the dir group (D2)
  log "dir  $dir  ← ${*}"
}

# Apply the matrix to a single FILE (no default ACL / setgid on files).
# args: <file> <acl-spec>...
acl_file() {
  local file="$RELAY_CONFIG/$1"; shift
  [[ -e "$file" ]] || { log "skip (absent file): $file"; return 0; }
  local spec
  for spec in "$@"; do setfacl -m "$spec" "$file"; done
  log "file $file  ← ${*}"
}

echo "apply-relay-acls (id:02c7) — enforcing the write matrix on $RELAY_CONFIG"

acl_dir  discovery-queue "u:relay-ro:rwx"
acl_dir  recipes         "u:relay-svc:rwx"
acl_dir  heartbeats      "u:relay-ro:rwx" "u:relay-svc:rwx"
acl_dir  claims          "u:relay-svc:rwx"
acl_dir  claims.done     "u:relay-svc:rwx"
acl_file .claim.lock     "u:relay-svc:rwx"
acl_file .heartbeat.lock "u:relay-ro:rwx" "u:relay-svc:rwx"

echo "done. Verify: getfacl $RELAY_CONFIG/discovery-queue (u:relay-ro:rwx present)."
