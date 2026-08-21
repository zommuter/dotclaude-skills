#!/usr/bin/env python3
"""lint-pipefail-sigpipe.py — ban the `pipefail` + early-exiting-pipe-consumer race.

THE SHAPE (ROADMAP id:81d5, cause of id:7518)
---------------------------------------------
Under `set -o pipefail`, a pipeline `producer | grep -q P` (or `| head -N`,
`| sed Nq`, `| awk '…exit…'`, `| grep -m N`) fails INTERMITTENTLY on a TRUE
assertion: the consumer exits on its first match while the producer is still
writing, the producer dies of SIGPIPE (141), and `pipefail` promotes 141 to the
pipeline's exit status.  Measured 8/400 on a 262-line static producer under
load; 400/400 for `git log … | grep -q <first-line-match>`.

Safe forms: `grep -q P < <(producer)`, `grep -q P <<<"$var"`, capture-then-test.
Process substitution is safe because the producer's status is DISCARDED — the
SIGPIPE never reaches the pipeline status that `pipefail` inspects.

WHAT THIS IS NOT
----------------
It is not a grep for a marker comment and it has NO exemption mechanism.  It
tokenizes each shell file, splits real (unquoted, non-`||`) pipelines, and
flags a pipeline in a `pipefail` file whose 2nd-or-later stage is a
KNOWN-early-exiting consumer.  Consumers that read to EOF (`grep` without -q/-m,
`grep -c`, `wc -l`, `tail`, `sort`, `sed` without a quit command) are NOT
flagged — they cannot SIGPIPE their producer.
"""
import os
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------- tokenizing

def strip_comment_and_quotes(line):
    """Return (code, ok).

    Replaces quoted-string bodies with same-length filler so that `|`, `#` and
    friends INSIDE quotes are invisible to the pipeline splitter, while column
    offsets stay true.  `ok` is False when the line ends inside a quote (a
    continued multi-line string) — the caller then treats it as opaque.

    A COMMAND SUBSTITUTION stays visible even inside double quotes: `x="$(a |
    head -1)"` is code, not a string, and masking it hid a whole class of live
    sites (`test_statusline_tokens.sh` was one).  The scanner therefore keeps a
    context STACK — double-quote, single-quote, and `$(`-code — rather than a
    single `quote` flag.
    """
    out = []
    stack = ["code"]          # innermost context last
    parens = [0]              # open-paren depth of each "code" context
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        top = stack[-1]

        if top == "sq":                       # single quotes: nothing expands
            out.append(c if c == "'" else "_")
            if c == "'":
                stack.pop()
            i += 1
            continue

        if top == "dq":
            if c == "\\" and i + 1 < n:
                out.append("__"); i += 2; continue
            if c == '"':
                out.append(c); stack.pop(); i += 1; continue
            if c == "$" and line[i + 1:i + 2] == "(":
                out.append("$("); stack.append("code"); parens.append(0); i += 2
                continue
            out.append("_"); i += 1
            continue

        # --- code context
        if c == "\\" and i + 1 < n:
            out.append("__"); i += 2; continue
        if c == "'":
            out.append(c); stack.append("sq"); i += 1; continue
        if c == '"':
            out.append(c); stack.append("dq"); i += 1; continue
        if c == "$" and line[i + 1:i + 2] == "(":
            out.append("$("); stack.append("code"); parens.append(0); i += 2
            continue
        if c == "(":
            parens[-1] += 1; out.append(c); i += 1; continue
        if c == ")":
            if parens[-1] == 0 and len(stack) > 1:
                out.append(c); stack.pop(); parens.pop(); i += 1; continue
            parens[-1] -= 1; out.append(c); i += 1; continue
        if c == "#" and (i == 0 or line[i - 1] in " \t;&|(") and len(stack) == 1:
            break
        out.append(c); i += 1
    return "".join(out), all(s == "code" for s in stack)


# ------------------------------------------------------- consumer classifier

_GREP = re.compile(r"^(grep|egrep|fgrep|zgrep|rg)$")


def early_exit_reason(stage, raw=None):
    """Why this pipeline stage exits before draining stdin — or None.

    `stage` is the QUOTE-MASKED text (so a `-q` inside a quoted pattern is never
    mistaken for a flag); `raw` is the original, needed for `sed`/`awk` whose
    early-exit command lives INSIDE the quoted script.
    """
    raw = stage if raw is None else raw
    words = stage.split()
    # skip leading env assignments / `!` / `command`
    k = 0
    while k < len(words) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[k])
                              or words[k] in ("!", "command", "builtin", "exec")):
        k += 1
    if k >= len(words):
        return None
    cmd = words[k].rsplit("/", 1)[-1]
    rest = words[k + 1:]

    if _GREP.match(cmd):
        for w in rest:
            if w == "--":
                break
            if not w.startswith("-"):
                break          # the PATTERN operand; later words are files, not flags
            if w.startswith("--"):
                if w in ("--quiet", "--silent") or w.startswith("--max-count"):
                    return "grep exits at first match (-q/--max-count)"
                continue
            if len(w) > 1:
                flags = w[1:]
                if "q" in flags:
                    return "grep -q exits at first match"
                if "m" in flags:
                    return "grep -m N exits after N matches"
                if "l" in flags or "L" in flags:
                    return "grep -l exits at first match"
        return None

    if cmd == "head":
        return "head exits after N lines"

    if cmd == "read":
        return "read consumes one line then exits"

    if cmd == "sed":
        # `sed Nq`, `sed -n '/x/{p;q}'`, `sed -n 3p;3q` … any `q` command quits early.
        body = " ".join(raw.split()[k + 1:])
        if re.search(r"(^|[^a-zA-Z])q($|[^a-zA-Z])", body) or re.search(r"\d+q", body):
            return "sed quits early (q command)"
        return None

    if cmd in ("awk", "gawk", "mawk"):
        if re.search(r"\bexit\b", " ".join(raw.split()[k + 1:])):
            return "awk exits early (exit statement)"
        return None

    return None


# ------------------------------------------------------------ file scanning

PIPE_SPLIT = re.compile(r"(?<!\|)\|(?!\|)")


HEREDOC = re.compile(r"<<-?\s*(\\?)([\"\']?)([A-Za-z_][A-Za-z0-9_]*)\2")


def code_lines(text):
    """Yield (lineno, line) for lines that are CODE in this file.

    Heredoc BODIES are data, not commands this shell runs, so they are skipped —
    that is parser correctness, not an exemption.  (Fixture scripts written from
    a heredoc are separately reported by `--heredoc`.)
    """
    term = None
    for lineno, line in enumerate(text.splitlines(), 1):
        if term is not None:
            if line.strip() == term:
                term = None
            continue
        m = HEREDOC.search(line)
        yield lineno, line
        if m:
            term = m.group(3)


def scan(path):
    """Yield (lineno, stage, reason) for every at-risk pipeline stage."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    if "pipefail" not in text:
        return  # without pipefail the producer's 141 is discarded by the shell
    for lineno, line in code_lines(text):
        code, ok = strip_comment_and_quotes(line)
        if not ok or "|" not in code:
            continue
        parts = PIPE_SPLIT.split(code)
        if len(parts) < 2:
            continue
        # Re-derive the ORIGINAL (unmasked) text of each stage by offset, so the
        # reported stage is readable; classification uses the masked text so a
        # `-q` inside a quoted pattern can never be mistaken for a flag.
        offs = []
        pos = 0
        for p in parts:
            offs.append(pos)
            pos += len(p) + 1
        for idx in range(1, len(parts)):
            masked = parts[idx].strip()
            raw_stage = line[offs[idx]:offs[idx] + len(parts[idx])].strip()
            reason = early_exit_reason(masked, raw_stage)
            if not reason:
                continue
            producer = code[:offs[idx] - 1].strip()
            # A pipeline whose producer side is empty (e.g. a continuation line
            # starting with `|`) cannot be classified from one line — report it,
            # it is still the banned shape.
            yield lineno, line.strip(), reason, producer
    return


def iter_shell_files(root):
    """Yield every `*.sh` under `root`, pruning nested checkouts (id:b818).

    A plain `root.rglob("*.sh")` walks into ANY nested git checkout under `root`
    — most concretely `.claude/worktrees/<agent>/…`, where the Agent tool's
    `isolation: worktree` places a full second checkout of a DIFFERENT branch.
    That checkout's WIP is not `root`'s tree; flagging it makes the suite's
    result depend on which sibling agents happen to be mid-edit (id:b818).

    Fix: `os.walk` with pruning. Any directory OTHER than `root` itself that is
    a git checkout root (carries a `.git`, dir-or-file, worktree-or-normal) is
    a nested repo — do not descend into it. `.git` directories are pruned
    everywhere (including at `root`) since they hold no `.sh` sources. This is
    generic (any nested checkout, not just the worktrees path) and keeps
    catching an at-risk site as long as it is in `root`'s OWN tree, however
    deep, since only a NESTED `.git` boundary prunes.
    """
    root = Path(root)
    if root.is_file():
        yield root
        return
    for dirpath, dirnames, filenames in os.walk(root):
        d = Path(dirpath)
        dirnames[:] = [dn for dn in dirnames if dn != ".git"]
        if d != root and (d / ".git").exists():
            dirnames[:] = []  # nested checkout — do not descend further
            continue
        for fn in filenames:
            if fn.endswith(".sh"):
                yield d / fn


def main(argv):
    roots = [Path(a) for a in argv[1:]] or [Path(".")]
    hits = []
    for root in roots:
        for f in sorted(iter_shell_files(root)):
            for lineno, line, reason, producer in scan(f):
                hits.append((f, lineno, line, reason))
    for f, lineno, line, reason in hits:
        print(f"{f}:{lineno}: {reason}\n    {line}")
    if hits:
        print(f"\n{len(hits)} at-risk site(s): a producer is piped into an "
              f"early-exiting consumer under `pipefail`.", file=sys.stderr)
        print("Rewrite as `consumer … < <(producer)` (or <<<\"$var\", or "
              "capture-then-test). There are NO exemptions.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
