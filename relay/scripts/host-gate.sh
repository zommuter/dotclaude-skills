#!/usr/bin/env bash
# host-gate.sh (id:43b9) — relay host-awareness gate for multi-host config monorepos.
#
# WHY (zomni meeting 2026-06-26 D7 — consolidate-device-repos-monorepo): a multi-host
# config monorepo (it-infra: hosts/<hostname>/ + shared/) holds work items some of which
# are HOST-BOUND — their definition-of-done (`make install` / tests) can only be VALIDATED
# on the matching machine (you cannot test fievel's apt path or zomni's touchscreen udev
# rule on the wrong host). EDITING a config file is host-agnostic (any host can write the
# file); only the test/make-install VERIFICATION is host-bound. This gate lets the executor
# "definition of done" and the reviewer re-derivation DEFER (the conservative default) a
# host-mismatched item rather than run install/tests on the wrong machine.
#
# A ROADMAP item may carry an OPTIONAL host tag: [host:zomni] | [host:fievel] | [host:any].
# UNTAGGED defaults to host:any (host-agnostic — verify anywhere). The tag is parsed from
# the item TEXT (the `- [ ]` line, or any text passed in). Editing is NEVER gated — only
# the host-bound verification step consults this gate.
#
# Minimal-default bias (per the meeting): defer is the dumb, safe fallback. We deliberately
# do NOT ssh to the matching host to run its tests here — that is a documented FUTURE option,
# not built now.
#
# Usage:
#   host-gate.sh '<roadmap item line / text>'      # text as $1
#   echo '<text>' | host-gate.sh                   # text on stdin
# Env:
#   RELAY_HOSTNAME   override the current hostname (default: `hostname`); for hermetic tests.
#
# Exit codes:
#   0  PROCEED — tag is host:any / absent, or matches the current hostname. Prints "proceed: ...".
#   3  DEFER   — tag names a DIFFERENT host. Prints "defer: needs host:<X> (current: <Y>)".
#   2  MISUSE  — no item text supplied.
set -euo pipefail

text="${1:-}"
# Fall back to stdin only when no arg was given AND stdin is a pipe/file (not a tty).
if [[ -z "$text" && ! -t 0 ]]; then
  text="$(cat)"
fi
[[ -n "$text" ]] || { echo "host-gate: no item text supplied (pass as \$1 or on stdin)" >&2; exit 2; }

current="${RELAY_HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"

# Extract the FIRST [host:<name>] tag (case-insensitive 'host'); name is [A-Za-z0-9_.-]+.
tag="$(printf '%s' "$text" | grep -oiE '\[host:[A-Za-z0-9_.-]+\]' | head -n1 || true)"

if [[ -z "$tag" ]]; then
  echo "proceed: no host tag (host:any default)"
  exit 0
fi

# Strip to the bare name, then lowercase both sides for a case-insensitive compare.
want="$(printf '%s' "$tag" | sed -E 's/^\[[Hh][Oo][Ss][Tt]:(.*)\]$/\1/')"
want_lc="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
current_lc="$(printf '%s' "$current" | tr '[:upper:]' '[:lower:]')"

if [[ "$want_lc" == "any" || "$want_lc" == "$current_lc" ]]; then
  echo "proceed: host:$want matches current host ($current)"
  exit 0
fi

echo "defer: needs host:$want (current: $current)"
exit 3
