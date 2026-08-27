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
#   as the global default, so that is the floor.
#
#   id:c82a — THE FLOOR'S "origin IS PRIVATE" ASSUMPTION IS A FLEET PROPERTY, NOT AN INVARIANT.
#   The comment that used to stand here read "the floor is deliberately the PRIVATE one: an
#   absent config can never cause a PUBLIC push". That is true of THIS fleet TODAY — all 56
#   own-repo origins were verified (2026-08-27) to be the private LAN host, 0 non-private —
#   and false in general: `git clone https://github.com/foo/bar` sets `origin` to a PUBLIC
#   remote, which is the single most ordinary way a repo enters `~/src`. The floor is the ONE
#   path that never consults a declaration, so on such a repo it would publish agent-authored
#   work straight through the allowlist built to prevent exactly that, silently.
#
#   THE FLOOR IS THEREFORE A CANDIDATE, NOT A GRANT. This resolver cannot decide it: it takes
#   a repo NAME and has no checkout, so it cannot resolve `origin`'s URL — and resolving one
#   here would also drag the PRIVACY predicate into the PUBLISH resolver, which the owner
#   ruling above forbids. It instead SIGNALS the floor to the caller, as a PREDICATE:
#
#       if publish_remotes_floored "$repo"; then ...   # 0 → the set is the BUILT-IN FLOOR
#
#   A predicate, NOT an out-parameter global: every caller consumes the set through
#   `set="$(publish_declared_remotes "$repo")"`, and a command substitution is a SUBSHELL, so
#   any variable that function assigned is discarded before the caller can read it. (The first
#   cut of id:c82a did exactly that and the flag read UNSET at every call site.)
#
#   A caller that HOLDS THE CHECKOUT (integrate.sh) must, when it is floored, prove `origin`
#   private via lib-private-remote.sh's `is_private_remote_url` before treating it as a
#   publish target, and WITHHOLD it — loudly — when it cannot. Not private, no pattern file,
#   an unresolvable URL: all three fail toward NOT publishing. A caller that does not hold a
#   checkout cannot make that proof and must not push on the floor alone.
#
# THIS IS DELIBERATELY NOT A TOML PARSER. It stays awk-shaped and auditable, matching the
# `bump_policy` reader next door. It tolerates indented headers/keys, trailing inline
# comments, TOML literal (single-quoted) strings, and an array spread over several lines.
#
# USAGE
#   . .../relay/scripts/lib-publish-remote.sh
#   set="$(publish_declared_remotes "$repo")"        # newline-separated, deduped, ordered
#   if publish_set_contains "$set" "$remote"; then ... ; fi
#   if publish_remotes_floored "$repo"; then ... ; fi # id:c82a — nothing was declared
#
# Safe to source under `set -euo pipefail`: no bare `cmd && return` tails, no producer piped
# into an early-exiting consumer (id:81d5), and a missing relay.toml is a clean floor result.

# Path of the TOML the declaration is read from. $RELAY_PUBLISH_TOML is an escape hatch for
# hermetic tests that do not want to move the whole $FABLES_CONFIG dir.
publish_remotes_toml_file() {
  printf '%s' "${RELAY_PUBLISH_TOML:-${FABLES_CONFIG:-$HOME/.config/relay}/relay.toml}"
}

# _publish_raw_decls <repo> → `default<TAB><name>` / `repo<TAB><name>` for every DECLARED
# entry, nothing at all when the file is absent/unreadable. THE parse — extracted (id:c82a)
# so `publish_declared_remotes` and `publish_remotes_floored` cannot drift apart, which is the
# very class this repo keeps paying for. Internal: the leading `_` marks it private to the lib.
_publish_raw_decls() {
  local repo="${1-}" f
  f="$(publish_remotes_toml_file)"
  if [ -f "$f" ] && [ -r "$f" ]; then
    awk -v want="[repos.$repo]" -v sq="'" '
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
    ' "$f" 2>/dev/null || true
  fi
  return 0
}

# publish_declared_remotes <repo> → one declared remote NAME per line, deduped, globals
# first then the repo's own additions. Never empty: the built-in `origin` floor applies when
# no `[publish] default_remotes` is declared (or the file is absent/unreadable).
publish_declared_remotes() {
  local repo="${1-}" raw defaults extra
  raw="$(_publish_raw_decls "$repo")"
  defaults="$(awk -F'\t' '$1=="default" && $2!="" {print $2}' <<<"$raw")"
  extra="$(awk -F'\t' '$1=="repo" && $2!="" {print $2}' <<<"$raw")"
  # THE FLOOR. Only when NO default is declared at all — an explicitly declared, non-empty
  # list is honoured verbatim, including one that omits `origin`.
  if [ -z "$defaults" ]; then defaults="origin"; fi
  printf '%s\n%s\n' "$defaults" "$extra" | awk 'NF && !seen[$0]++'
  return 0
}

# publish_remotes_floored <repo>
#   0 → the set publish_declared_remotes returns rests on the BUILT-IN `origin` FLOOR: no
#       `[publish] default_remotes` is declared anywhere (absent/unreadable relay.toml, a
#       fresh install, a hermetic root).
#   1 → an explicit `[publish] default_remotes` was found and honoured.
# id:c82a — a checkout-holding caller MUST, on 0, prove `origin` private before publishing to
# it (see the BUILT-IN FLOOR note at the top). Deliberately keyed on the GLOBAL default only:
# a per-repo `publish_remotes` addition is additive and never displaces the floor, so a repo
# that declares only additions is still floored for `origin`.
publish_remotes_floored() {
  local repo="${1-}" defaults
  defaults="$(_publish_raw_decls "$repo" | awk -F'\t' '$1=="default" && $2!="" {print $2}')"
  if [ -z "$defaults" ]; then return 0; fi
  return 1
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
