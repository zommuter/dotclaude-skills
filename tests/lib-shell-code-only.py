#!/usr/bin/env python3
"""Print only the EXECUTABLE-CODE characters of a shell script (TODO id:a290, round 3).

WHY THIS EXISTS
---------------
Several tests ban a forbidden command from a script by grepping its source (`worktree remove
--force`, `branch -D`, `reset --hard`, ...). A source grep has to skip the places where those
verbs legitimately appear as PROSE -- comments, and the surfaced `msg=` / `echo` / `log` text a
human reads when the helper refuses. Every previous attempt did that by dropping whole LINES,
which turns each excluded line into a smuggling channel: a line that STARTS with `msg=` can
still execute a real force --

    msg=$(git worktree remove --force "$wt")     # executes
    msg=; git worktree remove --force "$wt"      # executes
    log "$(git worktree remove --force "$wt")"   # executes

and all six such channels (`msg=`, indented `msg=`, `why=`, `hatch_refused=`, `echo`, `log`)
were demonstrated running a real force while invisible to the ban.

The distinction the ban actually needs is not line-shaped, it is QUOTING-shaped: text inside a
quoted literal is data, text inside `$( … )` or backticks is code even when it sits inside
double quotes. So this filter blanks (a) comments and (b) quoted-literal characters, and keeps
everything else -- including the innards of a command substitution nested inside a string.
Byte offsets and line breaks are preserved, so line numbers and occurrence counts still line up
with the original file.

    ./lib-shell-code-only.py <script>        # filtered source on stdout
    ./lib-shell-code-only.py                 # or from stdin

LIMITATION, deliberately loud: here-documents are NOT parsed -- their body would be emitted as
code. Callers that care assert the target script contains no `<<` (test_worktree_retire.sh does),
so this can never silently mislead rather than merely over-report.
"""
import sys

_CODE_CTX = ("top", "cs", "bt")


def code_only(src: str) -> str:
    out = []
    n = len(src)
    i = 0
    stack = ["top"]  # top | cs (command substitution) | bt (backticks) | dq | sq

    def blank(chunk: str) -> None:
        out.append("".join("\n" if ch == "\n" else " " for ch in chunk))

    while i < n:
        c = src[i]
        ctx = stack[-1]

        if ctx == "sq":  # single quotes: everything is literal until the next '
            blank(c)
            if c == "'":
                stack.pop()
            i += 1
            continue

        if ctx == "dq":  # double quotes: literal, EXCEPT $( … ) and ` … `
            if c == "\\" and i + 1 < n:
                blank(src[i:i + 2])
                i += 2
                continue
            if c == '"':
                blank(c)
                stack.pop()
                i += 1
                continue
            if c == "$" and i + 1 < n and src[i + 1] == "(":
                blank(src[i:i + 2])
                stack.append("cs")
                i += 2
                continue
            if c == "`":
                blank(c)
                stack.append("bt")
                i += 1
                continue
            blank(c)
            i += 1
            continue

        # ---- code contexts (top / cs / bt) ----
        if c == "\\" and i + 1 < n:
            out.append(src[i:i + 2])
            i += 2
            continue
        if c == "#" and (i == 0 or src[i - 1] in " \t\n;&|("):
            j = src.find("\n", i)
            if j < 0:
                j = n
            blank(src[i:j])
            i = j
            continue
        if c == "'":
            blank(c)
            stack.append("sq")
            i += 1
            continue
        if c == '"':
            blank(c)
            stack.append("dq")
            i += 1
            continue
        if c == "$" and i + 1 < n and src[i + 1] == "(":
            out.append("$(")
            stack.append("cs")
            i += 2
            continue
        if c == "`":
            out.append(c)
            if ctx == "bt":
                stack.pop()
            else:
                stack.append("bt")
            i += 1
            continue
        if c == ")" and ctx == "cs":
            out.append(c)
            stack.pop()
            i += 1
            continue
        out.append(c)
        i += 1

    return "".join(out)


def main(argv):
    if len(argv) > 2:
        sys.stderr.write("usage: lib-shell-code-only.py [<script>]\n")
        return 2
    if len(argv) == 2:
        with open(argv[1], "r", encoding="utf-8", errors="surrogateescape") as fh:
            src = fh.read()
    else:
        src = sys.stdin.read()
    sys.stdout.write(code_only(src))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
