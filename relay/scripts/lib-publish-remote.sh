#!/usr/bin/env bash
# relay/scripts/lib-publish-remote.sh — THE single "is the relay ALLOWED to push to this
# remote?" resolver (id:99b7 half (a)). ONE definition, sourced by every caller.
#
# WHY THIS FILE EXISTS — AND WHY IT IS *NOT* lib-private-remote.sh
#   id:4d44 made integrate.sh INFER the publish question from the PRIVACY question: "not
#   provably private ⇒ a public remote awaiting owner ratification". That inference fails
#   OPEN. Its live consequence: git-annex's `upstream = git://git-annex.branchable.com/` —
#   a read-only THIRD-PARTY URL this fleet only ever fetches from — was recorded as a remote
#   awaiting ratification (four unresolvable queue entries, one more per integrate), and on
#   the NON-SUBSTANTIVE path integrate.sh pushed EVERY remote, so a push to a stranger's
#   project was actually ATTEMPTED (rejected by their pre-receive hook, 2026-08-27).
#
#   The owner ratified an explicit do-publish ALLOWLIST and deliberately INVERTED the offered
#   scheme-based EXCLUSION: declare the remotes we DO publish to; everything else is not a
#   publish target at all. An allowlist fails CLOSED, which is the right failure direction
#   for a publishing decision.
#
#   THE TWO PREDICATES ARE ORTHOGONAL AND MUST STAY SO (owner ruling — do not conflate):
#     lib-private-remote.sh  answers  "is this HOST inside the fleet?"   → gates the LEAK SCAN
#     this file              answers  "may we publish HERE at all?"      → gates the PUSH
#   Widening the privacy predicate to exclude an undeclared remote would ALSO skip its leak
#   scan. Never do that. tests/test_publish_allowlist_99b7.sh (E) pins the separation.
#
# THE THREE-WAY SEMANTIC the two predicates produce together:
#     private + DECLARED   ⇒ push IMMEDIATELY                 (`origin`, the LAN host)
#     public  + DECLARED   ⇒ push GATED by owner ratification  (`github`)
#     UNDECLARED           ⇒ NEVER push, NEVER queue — SURFACED LOUDLY
#
# THE MIRROR FAILURE, WHICH IS THE DANGEROUS ONE
#   A pure allowlist silently swallows a remote the owner genuinely WANTS to publish to: add
#   a GitHub remote, forget to declare it, and nothing publishes AND nothing complains. The
#   exclusion is therefore ALWAYS paired with a LOUD line at the call site. Silence is a bug.
#
# DECLARATION SITE — `${FABLES_CONFIG:-~/.config/relay}/relay.toml`, the existing own-repo /
# policy SSOT integrate.sh already reads for `bump_policy`. No new config file.
#     [publish]
#     default_remotes = ["origin"]          # the fleet-wide floor
#
#     [repos.<name>]
#     publish_remotes = ["github"]          # per-repo ADDITIONS (union with the default)
#
# BUILT-IN FLOOR: with no `[publish] default_remotes` at all, the default is `origin`.
#   Fail-closed-to-NOTHING would stop the whole fleet pushing anywhere, including to the
#   private LAN origin — which is not publication at all. The ratified text names `origin`
#   as the global default, so that is the floor. Note the floor is deliberately the PRIVATE
#   one: an absent config can never cause a PUBLIC push.
#
# THIS IS DELIBERATELY NOT A TOML PARSER. It stays awk-shaped and auditable, matching the
# `bump_policy` reader next door. It tolerates indented headers/keys, trailing inline
# comments, TOML literal (single-quoted) strings, and an array spread over several lines.
#
# USAGE
#   . .../relay/scripts/lib-publish-remote.sh
#   set="$(publish_declared_remotes "$repo")"        # newline-separated, deduped, ordered
#   if publish_set_contains "$set" "$remote"; then ... ; fi
#
# Safe to source under `set -euo pipefail`: no bare `cmd && return` tails, no producer piped
# into an early-exiting consumer (id:81d5), and a missing relay.toml is a clean floor result.

# Path of the TOML the declaration is read from. $RELAY_PUBLISH_TOML is an escape hatch for
# hermetic tests that do not want to move the whole $FABLES_CONFIG dir.
publish_remotes_toml_file() {
  printf '%s' "${RELAY_PUBLISH_TOML:-${FABLES_CONFIG:-$HOME/.config/relay}/relay.toml}"
}

# publish_declared_remotes <repo> → one declared remote NAME per line, deduped, globals
# first then the repo's own additions. Never empty: the built-in `origin` floor applies when
# no `[publish] default_remotes` is declared (or the file is absent/unreadable).
publish_declared_remotes() {
  local repo="${1-}" f raw defaults extra
  f="$(publish_remotes_toml_file)"
  raw=""
  if [ -f "$f" ] && [ -r "$f" ]; then
    raw="$(awk -v want="[repos.$repo]" -v sq="'" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      # Emit every QUOTED token inside an array literal. Scanning for quotes (rather than
      # splitting on commas) is what makes a trailing `# comment`, a trailing comma and an
      # embedded comma-in-a-string all harmless.
      function emit(v, tag,   i, c, q, cur, inq) {
        inq = 0; cur = ""; q = ""
        for (i = 1; i <= length(v); i++) {
          c = substr(v, i, 1)
          if (inq) {
            if (c == q) { if (cur != "") print tag "\t" cur; cur = ""; inq = 0 }
            else cur = cur c
          } else if (c == "\"" || c == sq) { q = c; inq = 1; cur = "" }
        }
      }
      {
        line = $0; sub(/\r$/, "", line); t = trim(line)
        if (acc != "") {                       # continuing a multi-line array literal
          acc = acc " " t
          if (index(t, "]")) { emit(acc, acctag); acc = "" }
          next
        }
        if (t == "" || substr(t, 1, 1) == "#") next
        if (substr(t, 1, 1) == "[") { tbl = t; next }
        eq = index(t, "="); if (!eq) next
        key = trim(substr(t, 1, eq - 1)); val = trim(substr(t, eq + 1))
        if (tbl == "[publish]" && key == "default_remotes")   tag = "default"
        else if (tbl == want   && key == "publish_remotes")   tag = "repo"
        else next
        if (index(val, "]")) emit(val, tag)
        else { acc = val; acctag = tag }
      }
    ' "$f" 2>/dev/null || true)"
  fi
  defaults="$(awk -F'\t' '$1=="default" && $2!="" {print $2}' <<<"$raw")"
  extra="$(awk -F'\t' '$1=="repo" && $2!="" {print $2}' <<<"$raw")"
  # THE FLOOR. Only when NO default is declared at all — an explicitly declared, non-empty
  # list is honoured verbatim, including one that omits `origin`.
  if [ -z "$defaults" ]; then defaults="origin"; fi
  printf '%s\n%s\n' "$defaults" "$extra" | awk 'NF && !seen[$0]++'
  return 0
}

# publish_set_contains <newline-separated-set> <remote-name>
#   0 → the remote is DECLARED (we may push to it)
#   1 → UNDECLARED (never push, never queue — and the caller MUST say so loudly)
# awk, not `grep -qxF`: grep exits at the first match, and a producer piped into an
# early-exiting consumer is banned repo-wide (id:81d5).
publish_set_contains() {
  local set="${1-}" name="${2-}" hit
  if [ -z "$name" ]; then return 1; fi
  hit="$(awk -v n="$name" '$0 == n { f = 1 } END { print f + 0 }' <<<"$set")"
  if [ "$hit" = "1" ]; then return 0; fi
  return 1
}
