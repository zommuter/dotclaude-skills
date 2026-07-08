#!/usr/bin/env bash
# relay/scripts/lib-own-repos.sh — shared "confirmed own repos from relay.toml" parser
# (id:0fa0 finding e). Previously a verbatim copy of the SAME function lived in both
# discover-repos-mechanical.sh and relay-doctor.sh (id:10a6 drift risk) — a fix to the
# parser, or to its parse-guard, only ever reached whichever copy someone remembered to
# touch. This file defines ONE function; both scripts `source` it.
#
#   own_repos()
#     Reads $RELAY_TOML, honoring `classification = "own"`, the `# path:` COMMENT
#     override (tomllib drops comments, so this is recovered with a second plain-text
#     pass), and the `paused` flag. Expands `$SRC_DIR`-relative defaults. Prints
#     "<name>\t<path>" lines to stdout, one per confirmed own repo, in relay.toml's
#     `[repos.*]` iteration order.
#
#     Returns 0 with NO output if $RELAY_TOML does not exist at all — that's a valid
#     "no registry yet" state, not an error.
#
#     Returns NONZERO (propagating tomllib's own parse-failure exit code) if
#     $RELAY_TOML EXISTS but fails to parse (syntax error, duplicate key, etc.) — the
#     python3 invocation is the LAST command in the function body, so its exit status
#     IS the function's exit status.
#
#     CALLERS MUST CHECK THIS EXIT STATUS EXPLICITLY. A bare
#     `while ...; done < <(own_repos)` process-substitution DISCARDS a subshell's exit
#     status — the loop just sees EOF and finishes "successfully" with zero repos
#     enumerated, silently. This was id:0fa0 finding (a): discover-repos-mechanical.sh
#     used exactly that pattern, so a corrupt relay.toml wrote a schema-valid EMPTY
#     latest.json and beat the heartbeat GREEN. Capture to a file/variable and test
#     `$?` (or an `if ! out=$(own_repos ...); then` form) instead.
#
# Requires $RELAY_TOML and $SRC_DIR to already be set by the sourcing script (both are
# default+env-overridden identically in every caller).
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)

# Recover the `# path:` COMMENT override per repo (tomllib drops comments).
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}
