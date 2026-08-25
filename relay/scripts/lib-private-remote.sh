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
#
# id:a726(c) — IT MATCHES THE *HOST COMPONENT*, NOT A SUBSTRING OF THE WHOLE URL.
#   The previous ERE was `(^|@|//)(localhost|127\.0\.0\.1|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)|\.local($|[:/])`
#   applied to the entire URL string, and it false-positived in the UNSAFE direction:
#       https://github.com/o/repo.local   → PRIVATE   (`\.local($|[:/])` was unanchored, so a
#                                                      PATH ending in `.local` matched)
#       https://10.example.com/o/r.git    → PRIVATE   (`10\.` matched any host whose first
#                                                      label merely starts "10.")
#   Inherited byte-identical from hooks/pre-push-privacy-gate.sh, so not a regression — but
#   the blast radius changed when id:4d44 made this predicate decide whether the relay
#   AUTO-PUSHES agent-authored work. A wrong PRIVATE verdict PUBLISHES unratified work.
#   The fix is to parse the host out first (private_remote_host below) and anchor every
#   alternative to it: a bare `10.` prefix is no longer enough, an IPv4 must be a whole
#   IPv4, and `.local` must be the end of the HOST, never of the path.
# NOTE the direction of every change here: each one turns a former PRIVATE into a PUBLIC,
#   i.e. from auto-push toward defer-for-ratification. Nothing that was private became
#   public-unproven, and the two non-builtin sources below are UNTOUCHED — the fleet's named
#   LAN hosts match through the private pattern file exactly as before.
PRIVATE_REMOTE_HOST_ERE='^(localhost|127(\.[0-9]{1,3}){3}|\[?::1\]?|10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[01])(\.[0-9]{1,3}){2}|([A-Za-z0-9_-]+\.)*[A-Za-z0-9_-]+\.local)$'

# private_remote_host <remote-url> → prints the HOST component, or NOTHING when the URL has
# no host at all (a bare filesystem path, `file:///…`, an empty string).
#
# THE FORMS THIS FLEET REALLY USES, in the order they are discriminated:
#   scheme://[user@]host[:port]/path   https://…, ssh://…, git://…, file:///… (no host)
#   [user@]host:path                   scp-style — `git@github.com:o/r.git`, `host:/srv/x.git`
#   /any/local/path                    no host; a colon-free relative path likewise
# `[::1]`-style bracketed IPv6 literals keep their brackets so the ERE can anchor on them.
#
# NOT A SUBSTITUTE FOR THIS EITHER — git-lock-push.sh's is_ssh_url(). It answers "does this
# need SSH AUTH", so it calls `ssh://github.com/…` ssh. Here that URL MUST come out as the
# PUBLIC host `github.com`; borrowing is_ssh_url's logic would auto-publish agent work.
#
# A no-host result is deliberately NOT treated as private: a bare path can still be matched
# by a `private-host:` directive (the fleet's local bare repos are), and inventing a
# "paths are local ⇒ private" rule would widen auto-push on a guess. Unknown stays public.
private_remote_host() {
  local url="${1-}" rest before host=""
  if [ -z "$url" ]; then printf ''; return 0; fi
  case "$url" in
    *://*)
      rest="${url#*://}"      # drop the scheme
      rest="${rest%%/*}"      # drop the path FIRST, so an `@` or `:` in it cannot confuse us
      rest="${rest%%\?*}"
      rest="${rest%%#*}"
      rest="${rest#*@}"       # drop userinfo (a no-op when there is none)
      case "$rest" in
        \[*\]*) host="${rest%%\]*}]" ;;   # bracketed IPv6 literal, port (if any) discarded
        *)      host="${rest%%:*}"   ;;   # drop :port
      esac
      ;;
    *:*)
      before="${url%%:*}"
      # A slash BEFORE the colon means this is a filesystem path that happens to contain a
      # colon, not an scp-style URL. No host.
      case "$before" in
        */*) host="" ;;
        *)   host="${before#*@}" ;;
      esac
      ;;
    *) host="" ;;             # bare local path
  esac
  printf '%s' "$host"
  return 0
}

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
        # Trim with parameter expansion, not a `sed` fork: the sole consumer now DRAINS this
        # producer to EOF (id:17ac), so the per-directive fork is paid for every line instead
        # of only up to the first match. Same trim as the old `s/^[[:space:]]*//;s/…$//`.
        re="${line#private-host:}"
        while [ "$re" != "${re#[[:space:]]}" ]; do re="${re#[[:space:]]}"; done
        while [ "$re" != "${re%[[:space:]]}" ]; do re="${re%[[:space:]]}"; done
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
  local url="${1-}" re host
  # 1. builtin ERE — matched against the parsed HOST (id:a726(c)), never the whole URL.
  #    Guarded on a non-empty host so an empty string can never match and silently declare
  #    "private": no host ⇒ unproven ⇒ fall through to sources 2 and 3, then PUBLIC.
  host="$(private_remote_host "$url")"
  if [ -n "$host" ]; then
    if grep -Eq -e "$PRIVATE_REMOTE_HOST_ERE" <<<"$host"; then return 0; fi
  fi
  # 2. environment override (an operator's extra ERE)
  if [ -n "${PRIVACY_GATE_PRIVATE_HOSTS:-}" ]; then
    if grep -Eq -e "$PRIVACY_GATE_PRIVATE_HOSTS" <<<"$url"; then return 0; fi
  fi
  # 3. the PRIVATE pattern file's `private-host:` directives.
  #    DRAIN the producer to EOF into an array BEFORE matching (id:17ac). Looping directly
  #    over `< <(private_host_res)` and `return 0`-ing on the first match closes the process
  #    substitution's read end while the producer is still mid-loop, so its next
  #    `printf '%s\n'` takes SIGPIPE. In a terminal that kills the subshell silently; under
  #    `git push` it is LOUD — git ignores SIGPIPE and hooks inherit that disposition, so the
  #    write returns EPIPE instead and bash prints `printf: write error: Broken pipe` into the
  #    push transcript. That stream is the privacy gate's ONLY evidence channel (id:293f: a
  #    clean public scan prints nothing), so noise in it degrades the one signal.
  local -a res_list=()
  mapfile -t res_list < <(private_host_res)
  for re in ${res_list[@]+"${res_list[@]}"}; do
    [ -n "$re" ] || continue
    if grep -Eq -e "$re" <<<"$url"; then return 0; fi
  done
  return 1
}
