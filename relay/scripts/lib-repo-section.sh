#!/usr/bin/env bash
# relay/scripts/lib-repo-section.sh
#
# THE shared renderer for a relay.toml `[repos.<name>]` section header (id:02fe).
#
# WHY THIS EXISTS
# ---------------
# A repo name is chosen by its owner. It is not the job of a shell string-match to decide
# which names are allowed. Five separate scripts built the header by naive interpolation,
# `[repos.$repo]`, and then matched it as a fixed string:
#
#     relay-state-write.sh   grep -qxF "[repos.$repo]"        (toml-set target block)
#     ckpt-tag.sh            grep -qxF "[repos.$name]"        (managed-repo gate)
#     discover-sig.sh        awk -v want="[repos.$name]"      (signature block extract)
#     integrate.sh           awk -v want="[repos.$repo]"      (bump_policy read)
#     lib-publish-remote.sh  awk -v want="[repos.$repo]"      (publish_remotes read)
#
# That is correct only while every repo name is a TOML BARE KEY, `[A-Za-z0-9_-]+`. It was,
# for all 63 registered repos, until `zom.fi`. A dot is not a bare-key character. Written
# unquoted, `[repos.zom.fi]` is a NESTED table (`repos` then `zom` then `fi`), so tomllib
# yields a `zom` entry carrying no `classification` and lib-own-repos.sh drops the repo
# SILENTLY: the fleet reads clean with the repo invisible. Written correctly as
# `[repos."zom.fi"]`, tomllib is right but all five matchers above miss, because none quote.
#
# Both directions are wrong, and they fail differently. The unquoted form is silent, since an
# enumeration yielding nothing is indistinguishable from an empty own-set. The quoted form is
# loud at relay-state-write.sh (`block not found`) but silent at ckpt-tag.sh, whose `if` gate
# simply concludes the repo is unmanaged and skips the watermark sync.
#
# So: one renderer, sourced by all five, instead of five interpolations that each have to
# remember the quoting rule.
#
# WHAT IT GUARANTEES
# ------------------
#   repo_section_header <name>
#     The CANONICAL header, the spelling relay tooling WRITES. Bare when the name is a TOML
#     bare key, so every one of the 63 existing entries renders byte-identically to what is
#     on disk today and this library is a no-op for them. Double-quoted otherwise.
#
#   repo_section_headers <name>
#     Every ACCEPTED spelling, one per line: the spellings a matcher must RECOGNIZE. TOML
#     treats `[repos.zkm]`, `[repos."zkm"]` and the single-quoted form as the same table, so
#     a reader accepting only one of them is guessing. Writers emit the canonical form;
#     readers accept the set. A variant that cannot be rendered, because the name contains
#     the very quote character that would delimit it, is omitted rather than emitted broken.
#
# Neither function tolerates leading whitespace. That is the CALLER's business, and the five
# call sites deliberately differ on it (integrate.sh trims, ckpt-tag.sh does not). Deciding
# it here would silently widen two matchers that were narrow on purpose.
#
# Scope note (id:9220): the READER side is fixed in place rather than routed through a shared
# module. Seven copies of `sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")` recover the
# `# path:` comment override, and they sit inside inline `python3 -c` heredocs with no import
# path to hang a module on. Consolidating them is id:9220.

# repo_section_bare_ok <name>
#   Exit 0 iff <name> is a TOML bare key and therefore needs no quoting.
repo_section_bare_ok() {
  [[ "${1-}" =~ ^[A-Za-z0-9_-]+$ ]]
}

# repo_section_header <name>
#   Print the canonical `[repos.<name>]` header line.
repo_section_header() {
  local name="${1-}"
  if repo_section_bare_ok "$name"; then
    printf '[repos.%s]\n' "$name"
  else
    printf '[repos."%s"]\n' "$name"
  fi
}

# repo_section_headers <name>
#   Print every accepted spelling, one per line. Always exits 0, including for a name whose
#   content rules out one of the quoted variants.
repo_section_headers() {
  local name="${1-}"
  repo_section_bare_ok "$name" && printf '[repos.%s]\n' "$name"
  [[ "$name" != *'"'* ]] && printf '[repos."%s"]\n' "$name"
  [[ "$name" != *"'"* ]] && printf "[repos.'%s']\n" "$name"
  return 0
}

# repo_section_grep_file <name> <file>
#   Exit 0 iff <file> contains a whole line that is one of <name>'s accepted headers. The
#   fixed-string, no-leading-whitespace replacement for `grep -qxF "[repos.$name]" <file>`.
repo_section_grep_file() {
  local name="${1-}" file="${2-}" hdr
  [[ -f "$file" ]] || return 1
  while IFS= read -r hdr; do
    grep -qxF "$hdr" "$file" && return 0
  done < <(repo_section_headers "$name")
  return 1
}
