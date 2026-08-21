#!/usr/bin/env bash
# roadmap:4d44 — the SHARED private-remote predicate (relay/scripts/lib-private-remote.sh).
#
# Spec:
#   ONE definition of "is this git remote URL a PRIVATE/LAN host?", sourced by BOTH
#   hooks/pre-push-privacy-gate.sh (skip the leak scan) and relay/scripts/integrate.sh
#   (push it automatically instead of deferring to owner ratification).
#
#   (1) A host named ONLY by a `private-host:` directive in the PRIVATE, never-committed
#       pattern file classifies PRIVATE. No builtin-only reimplementation can do this —
#       that is why the file must be READ at runtime.
#   (2) Builtin loopback / RFC-1918 / *.local classify PRIVATE with no file at all.
#   (3) A public forge classifies PUBLIC — https AND ssh. Specifically
#       `ssh://github.com/…` is PUBLIC: git-lock-push.sh's is_ssh_url() calls it SSH, and
#       reusing THAT predicate here would auto-publish agent work. It must not be reused.
#   (4) $PRIVACY_GATE_PRIVATE_HOSTS is honoured (the env source).
#   (5) FAIL DIRECTION: absent pattern file, or an empty URL → PUBLIC (defer / scan).
#   (6) BOTH callers reference the ONE lib — no second copy of the predicate exists.
#
# Hermetic: a FIXTURE pattern file under mktemp (NEVER the real
# ~/.config/dotclaude-skills/privacy-patterns.txt), no repos, no network, no ~/.claude.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${LIB_PRIVATE_REMOTE_OVERRIDE:-$SRC_DIR/relay/scripts/lib-private-remote.sh}"
HOOK="${HOOK_OVERRIDE:-$SRC_DIR/hooks/pre-push-privacy-gate.sh}"
INTEGRATE="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$LIB" ]] || { echo "BAD: 4d44: shared predicate not found at $LIB"; echo "---- 0 ok, 1 bad ----"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# FIXTURE pattern file — a synthetic LAN host name, never a real one.
PATFILE="$TMP/privacy-patterns.txt"
cat > "$PATFILE" <<'EOF'
# fixture pattern file (synthetic; no real leak specifics)
ZZLEAKTOKEN-[0-9]+
allow: ZZLEAKTOKEN-0000
private-host: (^|@|//)zzlanbox([:/]|$)
EOF

# `classify <url>` → prints "private" or "public", using the lib in a FRESH bash under
# `set -euo pipefail` (the mode integrate.sh sources it in — a lib that trips -e is a bug).
classify() {
  local url="$1"
  bash -c '
    set -euo pipefail
    source "$1"
    if is_private_remote_url "$2"; then echo private; else echo public; fi
  ' _ "$LIB" "$url"
}

# ── (1) the private file is LOAD-BEARING: the LAN host matches only through it ──
export PRIVACY_GATE_PATTERNS="$PATFILE"
unset PRIVACY_GATE_PRIVATE_HOSTS || true
[[ "$(classify 'git@zzlanbox:/srv/git/repo.git')" == private ]] \
  && ok "4d44 (1) a private-host:-file host is PRIVATE (scp-style URL)" \
  || bad "4d44 (1) private-host:-file host classified PUBLIC — the runtime file read is broken"
[[ "$(classify 'ssh://zzlanbox/srv/git/repo.git')" == private ]] \
  && ok "4d44 (1) a private-host:-file host is PRIVATE (ssh:// URL)" \
  || bad "4d44 (1) private-host:-file host (ssh://) classified PUBLIC"

# ...and NOT through the builtins: with the file removed it must go PUBLIC.
nofile_verdict="$(PRIVACY_GATE_PATTERNS="$TMP/absent.txt" \
  bash -c 'set -euo pipefail; source "$1"; if is_private_remote_url "$2"; then echo private; else echo public; fi' \
  _ "$LIB" 'git@zzlanbox:/srv/git/repo.git')"
[[ "$nofile_verdict" == public ]] \
  && ok "4d44 (5) absent pattern file → the LAN host is PUBLIC (fail direction: defer/scan)" \
  || bad "4d44 (5) absent pattern file did NOT fall back to PUBLIC (got '$nofile_verdict')"

# ── (2) builtins, with the fixture file present ──
for u in 'https://localhost:3000/x.git' 'git@192.168.1.9:/srv/x.git' 'https://10.0.0.4/x.git' \
         'ssh://fixturehost.local/srv/x.git' 'https://172.20.0.1/x.git'; do
  [[ "$(classify "$u")" == private ]] \
    && ok "4d44 (2) builtin loopback/RFC-1918/.local is PRIVATE: $u" \
    || bad "4d44 (2) builtin private URL classified PUBLIC: $u"
done

# ── (3) public forges are PUBLIC — including the is_ssh_url TRAP ──
[[ "$(classify 'https://github.com/o/r.git')" == public ]] \
  && ok "4d44 (3) https://github.com/… is PUBLIC" \
  || bad "4d44 (3) https GitHub remote classified PRIVATE — agent work would auto-publish"
[[ "$(classify 'ssh://github.com/o/r.git')" == public ]] \
  && ok "4d44 (3) ssh://github.com/… is PUBLIC (is_ssh_url would have said 'ssh' → the trap)" \
  || bad "4d44 (3) ssh://github.com/… classified PRIVATE — this is the is_ssh_url trap: an SSH-AUTH predicate is NOT a private-host predicate, and it fails in the UNSAFE direction"
[[ "$(classify 'git@github.com:o/r.git')" == public ]] \
  && ok "4d44 (3) git@github.com:… is PUBLIC" \
  || bad "4d44 (3) scp-style GitHub remote classified PRIVATE"

# Guard the trap directly: is_ssh_url() must NOT be the thing answering this question.
if bash -c '
    set -euo pipefail
    # extract is_ssh_url from git-lock-push.sh and ask it the same question
    sed -n "/^is_ssh_url()/,/^}/p" "$1" > "$2/isssh.sh"
    source "$2/isssh.sh"
    if is_ssh_url "ssh://github.com/o/r.git"; then exit 0; else exit 1; fi
  ' _ "$SRC_DIR/git-diary-workflow/git-lock-push.sh" "$TMP" 2>/dev/null; then
  ok "4d44 (3) confirmed: is_ssh_url('ssh://github.com/…') is TRUE — proving it cannot serve as the private-host predicate"
else
  bad "4d44 (3) is_ssh_url no longer behaves as documented; re-derive the trap before trusting this suite"
fi

# ── (4) the env source ──
env_verdict="$(PRIVACY_GATE_PATTERNS="$TMP/absent.txt" PRIVACY_GATE_PRIVATE_HOSTS='(^|@|//)zzenvbox([:/]|$)' \
  bash -c 'set -euo pipefail; source "$1"; if is_private_remote_url "$2"; then echo private; else echo public; fi' \
  _ "$LIB" 'git@zzenvbox:/srv/x.git')"
[[ "$env_verdict" == private ]] \
  && ok "4d44 (4) PRIVACY_GATE_PRIVATE_HOSTS is honoured" \
  || bad "4d44 (4) PRIVACY_GATE_PRIVATE_HOSTS ignored (got '$env_verdict')"

# ── (5) empty URL → PUBLIC ──
[[ "$(classify '')" == public ]] \
  && ok "4d44 (5) an empty remote URL is PUBLIC (never assume private)" \
  || bad "4d44 (5) an empty remote URL classified PRIVATE"

# ── (6) EXACTLY ONE definition: both callers source the lib, neither re-derives it ──
if grep -q 'lib-private-remote.sh' "$HOOK"; then
  ok "4d44 (6) the privacy-gate hook references the shared lib"
else
  bad "4d44 (6) hooks/pre-push-privacy-gate.sh does NOT reference lib-private-remote.sh"
fi
if grep -q 'lib-private-remote.sh' "$INTEGRATE"; then
  ok "4d44 (6) integrate.sh references the shared lib"
else
  bad "4d44 (6) integrate.sh does NOT reference lib-private-remote.sh"
fi
# The builtin ERE is a fingerprint of the predicate: it must appear in the lib and NOWHERE
# else under version control (a second copy is the drift this extraction exists to prevent).
copies="$(grep -rl '192\\\.168\\\.' "$SRC_DIR/hooks" "$SRC_DIR/relay/scripts" "$SRC_DIR/git-diary-workflow" 2>/dev/null | sort || true)"
if [[ "$copies" == "$LIB" ]]; then
  ok "4d44 (6) the builtin private-host ERE exists in exactly ONE file ($(basename "$LIB"))"
else
  bad "4d44 (6) the private-host ERE appears in more than one place — a SECOND definition of 'is this remote public' has been born: $(echo "$copies" | tr '\n' ' ')"
fi

echo "---- $pass ok, $fail bad ----"
if [[ "$fail" -gt 0 ]]; then
  echo "FAIL: shared private-remote predicate (roadmap:4d44)"
  exit 1
fi
echo "ALL PASS: shared private-remote predicate (roadmap:4d44)"
