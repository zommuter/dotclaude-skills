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
double quotes. So this filter blanks (a) comments and (b) PROSE quoted literals, and keeps
everything else -- including the innards of a command substitution nested inside a string, and
quoted literals that are shell WORDS rather than prose (see WORD-LIKE LITERALS below).
Line breaks are preserved, so line numbers and occurrence counts still line up with the original
file. (Byte offsets within a line no longer always do -- see WORD-LIKE LITERALS below.)

    ./lib-shell-code-only.py <script>        # filtered source on stdout
    ./lib-shell-code-only.py                 # or from stdin

WORD-LIKE LITERALS (added round 4, 2026-09-01)
----------------------------------------------
"Everything quoted is data" was too coarse and left two smuggling channels open, both of which
kept a source-grep ban green while a real force sat in the script ready to run:

    git "worktree" "remove" "--force" "$wt"     # quoted COMMAND WORDS -- executes
    git worktree remove --for""ce "$wt"         # empty literal SPLICED into a word -- executes

Neither is prose. Prose is a SENTENCE: it has whitespace in it. A quoted literal that contains
no whitespace at all is a shell WORD (or a fragment of one), and after quote removal the shell
executes it verbatim. So a quoted literal opened from a code context is emitted as CODE, with its
delimiters DROPPED, whenever it contains no whitespace and no command substitution -- which makes
`"--force"` read as `--force` and splices `--for` + `""` + `ce` back into `--force`. A literal
that DOES contain whitespace is prose and is blanked exactly as before, and one containing
`$( … )` or backticks falls through to the character-by-character path so its code innards
survive. Dropping the delimiters is what makes the concatenation case work, and it is the reason
byte offsets within such a line shift by the number of quote characters removed.

LIMITATIONS, deliberately loud -- this filter CANNOT be made complete, so do not read a green
source-grep ban as proof that a script cannot run a forbidden command:

  * `eval` is STRUCTURAL and unclosable here. `eval "git worktree remove --force $wt"` and
    `msg="git worktree remove --force $wt"` are the same shape to any quote-aware filter; only
    the command word tells them apart, and telling them apart in general needs a shell parser.
    The honest answer is a SEPARATE ban on `eval` itself, which test_worktree_retire.sh carries.
  * Here-documents are NOT parsed -- their body would be emitted as code. Callers that care
    assert the target script contains no `<<` (test_worktree_retire.sh does), so this
    over-reports rather than silently misleading.
"""
import sys

_CODE_CTX = ("top", "cs", "bt")
_WS = " \t\n"


def _scan_literal(src: str, i: int) -> "tuple[int, bool, bool] | None":
    """Scan the quoted literal whose OPENING delimiter is at src[i].

    Returns (index just past the closing delimiter, has_substitution, has_whitespace),
    or None when the literal is unterminated (caller falls back to the char-by-char path).
    """
    q = src[i]
    n = len(src)
    j = i + 1
    has_subst = False
    has_ws = False
    while j < n:
        c = src[j]
        if q == '"' and c == "\\" and j + 1 < n:
            if src[j + 1] in _WS:
                has_ws = True
            j += 2
            continue
        if c == q:
            return j + 1, has_subst, has_ws
        if q == '"' and (c == "`" or (c == "$" and j + 1 < n and src[j + 1] == "(")):
            has_subst = True
        if c in _WS:
            has_ws = True
        j += 1
    return None


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
        if c in ("'", '"'):
            scanned = _scan_literal(src, i)
            if scanned is not None:
                end, has_subst, has_ws = scanned
                if not has_subst:
                    if has_ws:
                        # Prose: a quoted sentence. Blank it whole (identical to the
                        # character-by-character path, just done in one step).
                        blank(src[i:end])
                    else:
                        # A shell WORD, not prose: after quote removal the shell executes it
                        # verbatim. Emit the content as code and DROP the delimiters, so
                        # `"--force"` reads as --force and `--for""ce` splices back together.
                        out.append(src[i + 1:end - 1])
                    i = end
                    continue
            # Unterminated, or it carries `$( … )`/backticks whose innards are code:
            # fall through to the character-by-character path.
            blank(c)
            stack.append("sq" if c == "'" else "dq")
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
