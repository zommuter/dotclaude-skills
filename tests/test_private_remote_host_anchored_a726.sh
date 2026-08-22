#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:a726(c) is a DEFECT FIX found by adversarial review,
# not a ROADMAP item, so per tests/run-tests.sh's convention these failures ALWAYS count.
#
# id:a726(c) — lib-private-remote.sh's builtin ERE false-positived in the UNSAFE direction.
#
#   Measured before the fix:
#       PRIVATE   https://github.com/o/repo.local     <-- unanchored `\.local($|[:/])`
#       PRIVATE   https://10.example.com/o/r.git      <-- `10\.` matching any host whose
#                                                         first label merely starts "10."
#   Not a regression — the ERE was inherited byte-identical from
#   hooks/pre-push-privacy-gate.sh — but the blast radius is NEW. It used to only skip a leak
#   scan; since id:4d44 it decides whether the relay AUTO-PUSHES agent-authored work without
#   owner ratification. A wrong PRIVATE verdict PUBLISHES unratified work.
#
#   The fix parses the HOST component out of the URL and anchors every builtin alternative to
#   it. This test pins BOTH directions:
#     • the two measured false positives now classify PUBLIC;
#     • `ssh://github.com/…` STAYS PUBLIC (the is_ssh_url trap — an SSH-AUTH predicate is not
#       a private-host predicate and fails toward auto-publish);
#     • NOTHING genuinely private got weaker: loopback / RFC-1918 / mDNS `.local` hosts and a
#       `private-host:`-file host all still classify PRIVATE.
#
# Hermetic: a FIXTURE pattern file only — never the real, never-committed
# ~/.config/dotclaude-skills/privacy-patterns.txt, whose CONTENTS are never inlined here.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${LIB_PRIVATE_REMOTE_OVERRIDE:-$SRC_DIR/relay/scripts/lib-private-remote.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
rc=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; rc=1; }

[[ -r "$LIB" ]] || { echo "FAIL: lib not readable at $LIB"; exit 1; }

# ── FIXTURE pattern file. `zzlanbox` is a SYNTHETIC stand-in for this fleet's real named LAN
#    hosts, which live only in the private file and are never written into a committed file.
PATFILE="$TMP/patterns.txt"
cat > "$PATFILE" <<'EOF'
# fixture — synthetic only
private-host: (^|@|//)zzlanbox([:/]|$)
EOF
export PRIVACY_GATE_PATTERNS="$PATFILE"
unset PRIVACY_GATE_PRIVATE_HOSTS || true

# classify <url> → "private" | "public", in a FRESH bash under `set -euo pipefail` (the mode
# integrate.sh sources the lib in — a lib that trips -e is itself a bug).
classify() {
  bash -c '
    set -euo pipefail
    source "$1"
    if is_private_remote_url "$2"; then echo private; else echo public; fi
  ' _ "$LIB" "$1"
}
expect() { # <expected> <url> <why>
  local got; got="$(classify "$2")"
  [[ "$got" == "$1" ]] && ok "a726(c) $2 → $1 ($3)" \
                       || bad "a726(c) $2 → $got, expected $1 ($3)"
}

# ── THE TWO MEASURED FALSE POSITIVES — both must now be PUBLIC ───────────────────────
expect public 'https://github.com/o/repo.local' \
  'a PATH ending in .local is not a .local HOST; PRIVATE here would auto-publish to GitHub'
expect public 'https://10.example.com/o/r.git' \
  'a host whose first label starts "10." is not 10.0.0.0/8'

# Same two shapes in the other URL forms this fleet uses, so the anchoring is not
# scheme-specific.
expect public 'ssh://github.com/o/repo.local'   'ssh:// form of the .local path false positive'
expect public 'git@github.com:o/repo.local'     'scp-style form of the .local path false positive'
expect public 'git@10.example.com:o/r.git'      'scp-style form of the 10. host false positive'
expect public 'https://192.168.example.com/x'   '192.168.* as a DOMAIN label, not RFC-1918'
expect public 'https://172.15.0.1/x.git'        '172.15/16 is OUTSIDE the RFC-1918 172.16-31 block'
expect public 'https://mylocal/x.git'           'a host literally named "mylocal" is not *.local'

# ── THE REQUIREMENT THAT MATTERS: ssh://github.com/… STAYS PUBLIC ────────────────────
expect public 'ssh://github.com/o/r.git' \
  'the is_ssh_url TRAP — an SSH-AUTH predicate would say private and auto-publish agent work'
expect public 'https://github.com/o/r.git'  'plain public forge'
expect public 'git@github.com:o/r.git'      'scp-style public forge'

# ── NOTHING GENUINELY PRIVATE GOT WEAKER ─────────────────────────────────────────────
expect private 'https://localhost:3000/x.git'      'loopback by name, port stripped'
expect private 'https://127.0.0.1/x.git'           'loopback by address'
expect private 'ssh://git@[::1]:22/srv/x.git'      'bracketed IPv6 loopback literal'
expect private 'git@192.168.1.9:/srv/x.git'        'RFC-1918 192.168/16, scp-style'
expect private 'https://10.0.0.4/x.git'            'RFC-1918 10/8'
expect private 'https://172.20.0.1/x.git'          'RFC-1918 172.16/12'
expect private 'ssh://fixturehost.local/srv/x.git' 'mDNS .local HOST'
expect private 'https://sub.host.local:2222/x.git' 'multi-label .local host with a port'

# ── the `private-host:` FILE source is untouched and still load-bearing ──────────────
expect private 'git@zzlanbox:/srv/git/repo.git' 'private-host: directive, scp-style'
expect private 'ssh://zzlanbox/srv/git/repo.git' 'private-host: directive, ssh:// form'
nofile="$(PRIVACY_GATE_PATTERNS="$TMP/absent.txt" \
  bash -c 'set -euo pipefail; source "$1"; if is_private_remote_url "$2"; then echo private; else echo public; fi' \
  _ "$LIB" 'git@zzlanbox:/srv/git/repo.git')"
[[ "$nofile" == public ]] \
  && ok "a726(c) with the pattern file ABSENT the LAN host falls back to PUBLIC (fail direction preserved)" \
  || bad "a726(c) absent pattern file did NOT fall back to PUBLIC (got '$nofile')"

# ── ONE definition of the builtin, in ONE file ───────────────────────────────────────
# The fingerprint is the ERE's variable name plus the RFC-1918 172-block alternation, which
# no other file may re-derive (the drift class this lib exists to prevent).
# The needle is SPLIT so this test file does not match itself — that keeps tests/ IN scope,
# which matters: a test that quietly re-declared the ERE would defeat the whole point.
NEEDLE='PRIVATE_REMOTE_'"HOST_ERE="
defs="$(grep -rl "$NEEDLE" "$SRC_DIR" --exclude-dir=.git 2>/dev/null | sort)"
[[ "$defs" == "$SRC_DIR/relay/scripts/lib-private-remote.sh" ]] \
  && ok "a726(c) exactly ONE file defines the builtin host ERE" \
  || bad "a726(c) the builtin host ERE is defined in more than one place: $defs"
reimpl="$(grep -rln '172\\\.(1\[6-9\]|2\[0-9\]|3\[01\])' "$SRC_DIR" --exclude-dir=.git --exclude-dir=tests 2>/dev/null | sort)"
[[ "$reimpl" == "$SRC_DIR/relay/scripts/lib-private-remote.sh" ]] \
  && ok "a726(c) no second copy of the RFC-1918 alternation anywhere in the repo" \
  || bad "a726(c) the RFC-1918 alternation is re-derived outside the lib: $reimpl"

[[ $rc -eq 0 ]] && echo "ALL PASS: id:a726(c) — the builtin matches the HOST, not a substring of the URL"
exit $rc
