#!/usr/bin/env python3
"""
PreToolUse hook: dropped-file / pathspec guard for 'git commit'.

Intercepts Bash tool calls that invoke 'git commit' with explicit file-path
arguments, then blocks the call when at least one of those arguments does NOT
match any currently staged file.  This catches pathspec typos (e.g. running
'git commit foo.p' instead of 'git commit foo.py' while foo.py is staged) while
remaining completely silent on ordinary partial-staging commits — diary-style
commits that name every file they intend to commit will see all their path args
matched in the staged set and will not be blocked.

Non-noise guarantee
-------------------
The hook only fires when BOTH conditions hold simultaneously:
  1. The git commit command contains at least one explicit file-path argument.
  2. At least one of those explicit paths does NOT match any staged file.

Consequently:
  • 'git commit -m "msg"' (no path args)        → never blocked
  • 'git commit -m "msg" file.py' (file.py staged) → never blocked
  • 'git commit -m "msg" -- file.py' (file.py staged) → never blocked
  • 'git commit -m "msg" fle.py' (typo, not staged)  → BLOCKED

A command containing a command substitution, heredoc, or process substitution is
never blocked: shlex cannot tokenize those bodies faithfully, so the guard cannot
tell a pathspec from a fragment of a commit message.  This deliberately exempts
the 'git commit -m "$(cat <<EOF ...)"' diary pattern from the guard rather than
risk rejecting a valid commit (routed:b213).

Tracks TODO id:b67e.

Output
------
Outputs a JSON object to stdout:
  {"decision": "block", "reason": "..."} to block the commit, or nothing (exit 0)
  to let it proceed.
"""
import json
import re
import shlex
import subprocess
import sys
from typing import Optional

# Shell constructs whose bodies shlex cannot tokenize faithfully: it treats quotes
# *inside* a command substitution or heredoc body as shell quotes, so a single
# literal quote in a commit message silently re-brackets the rest of the command
# and the message tail is mis-read as pathspec arguments.  Presence of any of
# these means "cannot reliably parse" — extract_path_args returns None and the
# caller does not block.  Over-broad by design: a false bail merely disables the
# guard for that command, whereas a false block rejects a legitimate commit.
_UNPARSEABLE_CONSTRUCT = re.compile(
    r"""
      \$\(        # command substitution  $( ... )
    | `           # legacy command substitution
    | <<          # heredoc / herestring
    | <\(         # process substitution
    """,
    re.VERBOSE,
)

# git commit options (short or long form) that consume the NEXT token as their value.
# Long-form '--opt=value' tokens are handled by the '=' check and never reach this set.
_OPTION_WITH_VALUE: frozenset[str] = frozenset({
    "-m", "--message",
    "-C", "--reuse-message",
    "-c", "--reedit-message",
    "-F", "--file",
    "-t", "--template",
    "--trailer",
})


def extract_path_args(command: str) -> Optional[list[str]]:
    """
    Parse a shell command string and return the explicit file-path arguments
    for the 'git commit' invocation, or None if the command cannot be reliably
    parsed (in which case the caller MUST NOT block — conservative by default).

    Returns an empty list when the commit has no explicit path args.
    """
    if _UNPARSEABLE_CONSTRUCT.search(command):
        return None  # Command substitution / heredoc — don't block

    try:
        tokens = shlex.split(command)
    except ValueError:
        return None  # Un-parseable shell syntax — don't block

    # Locate 'git' and then 'commit' in the token stream, skipping git global options.
    i = 0
    while i < len(tokens) and tokens[i] != "git":
        i += 1
    if i >= len(tokens):
        return None  # No 'git' found
    i += 1  # past 'git'

    # Skip git global options (-C <dir>, --no-pager, -c key=val, etc.)
    while i < len(tokens) and tokens[i] != "commit":
        tok = tokens[i]
        if tok in ("-C", "--git-dir", "--work-tree", "-c", "--exec-path"):
            i += 2  # option + its value
        else:
            i += 1

    if i >= len(tokens) or tokens[i] != "commit":
        return None  # Not a 'git commit' call
    i += 1  # past 'commit'

    paths: list[str] = []
    after_dashdash = False

    while i < len(tokens):
        tok = tokens[i]

        if after_dashdash:
            # Everything after '--' is a pathspec
            paths.append(tok)
            i += 1
            continue

        if tok == "--":
            after_dashdash = True
            i += 1
            continue

        # '--opt=value' form: the '=' is already embedded; skip just this token
        if tok.startswith("--") and "=" in tok:
            i += 1
            continue

        # Short/long option that takes a separate value token
        if tok in _OPTION_WITH_VALUE:
            i += 2  # skip option + its value token
            continue

        # Any remaining '-…' token is treated as a boolean flag; skip it.
        # (Unknown options with a value would cause their value to appear as a
        #  path arg, which might yield a false positive.  Practically all common
        #  git-commit flags are boolean, so this risk is negligible.)
        if tok.startswith("-"):
            i += 1
            continue

        # Non-flag, non-option-value: it's a path argument
        paths.append(tok)
        i += 1

    return paths


def get_staged_files() -> set[str]:
    """
    Return the set of file paths currently in the git index (staged), relative
    to the repository root.  Returns empty set on any error so the caller can
    decide conservatively.
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return set()
        return {line.strip() for line in result.stdout.splitlines() if line.strip()}
    except Exception:
        return set()


def path_matches_staged(path_arg: str, staged: set[str]) -> bool:
    """
    Return True if path_arg matches at least one staged file.

    Handles:
      - Exact match         : "foo/bar.py"      matches staged "foo/bar.py"
      - Directory prefix    : "foo"  or "foo/"  matches staged "foo/bar.py"
    """
    norm = path_arg.rstrip("/")
    for sp in staged:
        if sp == norm:
            return True
        if sp.startswith(norm + "/"):
            return True
    return False


def main() -> None:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw)
    except Exception:
        return  # Can't parse payload — don't block

    if payload.get("tool_name") != "Bash":
        return

    command: str = (payload.get("tool_input") or {}).get("command", "")
    if not command:
        return

    # Quick pre-filter: must contain both 'git' and 'commit'
    if "git" not in command or "commit" not in command:
        return

    path_args = extract_path_args(command)
    if path_args is None:
        return  # Unparseable — don't block (conservative)
    if not path_args:
        return  # No explicit path args — ordinary staged-only commit, don't block

    staged = get_staged_files()
    if not staged:
        # Nothing staged or couldn't determine — let git report its own error
        return

    unmatched = [p for p in path_args if not path_matches_staged(p, staged)]
    if not unmatched:
        return  # All named paths are staged — diary-style commit, allow

    # At least one explicit path arg has no staged counterpart: likely a typo or
    # a forgotten 'git add'.  Block with a diagnostic message.
    staged_sample = sorted(staged)[:10]
    extra = f" (+{len(staged) - 10} more)" if len(staged) > 10 else ""
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"Pathspec drop guard (id:b67e): the following path(s) in your "
            f"'git commit' command do not match any staged file: {unmatched}. "
            f"Currently staged: {staged_sample}{extra}. "
            f"Check for a typo in the path argument, or run 'git add <file>' first. "
            f"To commit a subset of staged files intentionally, ensure all "
            f"explicitly named paths are already staged."
        ),
    }))


main()
