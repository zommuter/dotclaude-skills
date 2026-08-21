#!/usr/bin/env bash
# relay/scripts/lib-private-remote.sh — THE single "is this git remote URL a PRIVATE/LAN
# host?" predicate (id:4d44). ONE definition, sourced by every caller.
#
# WHY THIS FILE EXISTS
#   The only correct classifier lived INLINE in hooks/pre-push-privacy-gate.sh. The moment a
#   second consumer appeared (integrate.sh's per-remote push narrowing — push the private
#   remotes, defer the public ones), a second, drifting definition of "is this remote public"
#   would have been born. That drift class is one this repo keeps paying for, so the predicate
#   is extracted here and BOTH callers source this one copy.
#
# WHAT MAKES IT CORRECT — AND WHY A BUILTIN-ONLY REIMPLEMENTATION CANNOT BE
#   Three sources are OR-ed, in this order:
#     1. a builtin ERE covering loopback / RFC-1918 / *.local;
#     2. $PRIVACY_GATE_PRIVATE_HOSTS — an extra ERE from the environment;
#     3. every `private-host: <ERE>` directive in the PRIVATE, never-committed pattern file
#        ($PRIVACY_GATE_PATTERNS, default ~/.config/dotclaude-skills/privacy-patterns.txt).
#   Source 3 is load-bearing: this fleet's LAN hosts are named, not numbered, so they match
#   ONLY through it. That file is deliberately absent from git and its CONTENTS ARE NEVER
#   INLINED in any committed file (public repo — no leak specifics here, mechanism only).
#   This lib READS it at runtime, exactly as the hook always has.
#
# NOT A SUBSTITUTE — git-lock-push.sh's is_ssh_url()
#   is_ssh_url() answers "does this URL need SSH AUTH", not "is this host private". It calls
#   `ssh://github.com/…` SSH — i.e. it would classify a PUBLIC remote as private and
#   AUTO-PUBLISH agent-authored work. It fails in the unsafe direction for this question.
#   Never use it here; it has its own separate job and stays where it is.
#
# FAIL DIRECTION — UNKNOWN IS PUBLIC
#   Every caller of this predicate treats "not private" as the conservative branch: the
#   privacy gate SCANS a remote it cannot prove private, and integrate.sh DEFERS a remote it
#   cannot prove private. So an absent/unreadable pattern file, an unset env var, an empty URL
#   — all yield "public". That is deliberate: never skip a leak scan, and never auto-publish,
#   on an unproven assumption.
#
# USAGE
#   source .../relay/scripts/lib-private-remote.sh
#   if is_private_remote_url "$url"; then ... ; fi
#
# The functions are safe under `set -euo pipefail`: no bare `cmd && return` tails, and a
# missing pattern file is a clean empty result, never an error.

# The builtin, PUBLIC-SAFE half of the classifier: loopback, RFC-1918, and mDNS `.local`.
# Site-specific hosts NEVER appear here — they live in the private pattern file (see above).
PRIVATE_REMOTE_BUILTIN_ERE='(^|@|//)(localhost|127\.0\.0\.1|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)|\.local($|[:/])'

# Path of the PRIVATE pattern+allowlist file this predicate reads its `private-host:`
# directives from. Same env var and same default the privacy-gate hook has always used, so
# both callers are configured by one knob (and one fixture, in hermetic tests).
private_remote_patterns_file() {
  printf '%s' "${PRIVACY_GATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/dotclaude-skills/privacy-patterns.txt}"
}

# Print one ERE per line for each `private-host:` directive in the private pattern file.
# Absent/unreadable file → no output, exit 0 (the "no site-specific hosts known" state).
# Comments (`#`) and blank lines are ignored; CRLF tolerated; surrounding space trimmed —
# byte-identical to the parse the hook did inline.
private_host_res() {
  local f line re
  f="$(private_remote_patterns_file)"
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    # Same two skips the hook applied inline, written as `if` blocks (not `[[ … ]] && continue`)
    # so this file is safe to source under `set -e`: a FALSE test at the tail of a loop body
    # is a failing command there, and would abort the caller.
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    case "$line" in
      private-host:*)
        re="$(printf '%s' "${line#private-host:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [ -n "$re" ]; then printf '%s\n' "$re"; fi
        ;;
    esac
  done < "$f"
  return 0
}

# is_private_remote_url <remote-url>
#   0 → PRIVATE/LAN (safe to skip a leak scan; safe to push without owner ratification)
#   1 → PUBLIC or UNKNOWN (scan it; defer the push)
is_private_remote_url() {
  local url="${1-}" re
  # 1. builtin ERE — guarded on a non-empty URL so an empty string can never match `(^|@|//)`
  #    on some grep implementation and silently declare "private".
  if [ -n "$url" ]; then
    if grep -Eq -e "$PRIVATE_REMOTE_BUILTIN_ERE" <<<"$url"; then return 0; fi
  fi
  # 2. environment override (an operator's extra ERE)
  if [ -n "${PRIVACY_GATE_PRIVATE_HOSTS:-}" ]; then
    if grep -Eq -e "$PRIVACY_GATE_PRIVATE_HOSTS" <<<"$url"; then return 0; fi
  fi
  # 3. the PRIVATE pattern file's `private-host:` directives
  while IFS= read -r re; do
    [ -n "$re" ] || continue
    if grep -Eq -e "$re" <<<"$url"; then return 0; fi
  done < <(private_host_res)
  return 1
}
