#!/usr/bin/env python3
"""Flag SOURCE-GREP-AS-BEHAVIOURAL-ASSERTION in tests/ (id:05a2 / id:3a50 class).

The defect class: a test asserts a fix's SHAPE by grepping the implementation's source text
(`grep -q 'live-runs' "$SCRIPT"`), so it stays green through a full revert of the behaviour it
claims to guard. Two proven instances in one review window (id:05a2, id:3a50) prompted this
lint; the question it answers is whether that is two incidents or a codebase habit.

What it flags
-------------
A `grep` (or `rg`) whose TARGET operand is a variable that the same test file assigns from the
REPO SOURCE TREE ($SRC_DIR/…, $ROOT/…, $REPO_ROOT/…), i.e. the shipped implementation rather
than a fixture the test built in $tmpdir. Each hit is classified:

  SHAPE-ONLY  the test file never EXECUTES that source file (no `bash "$V"`, `node "$V"`,
              `"$V" …`, `python3 "$V"`) — every assertion about it is source text. This is the
              id:3a50 shape: nothing in the file can fail when the behaviour breaks.
  MIXED       the file does execute the source elsewhere, so the grep is a supplementary
              tripwire beside real coverage (the id:05a2 shape once its behavioural half is
              covered by a sibling test). Lower severity, but a grep next to a real test still
              reads as coverage it does not provide.

Deliberately NOT flagged: greps over `$out`/heredocs/`<<<` (assertions on OUTPUT are
behavioural), greps over fixture files built under $tmpdir, and `bash -n` / `node --check`
syntax gates.

Honest limits: this is a lexical heuristic over shell text, not a parse. It cannot tell a
legitimate source-shape assertion (a contract that genuinely IS "this string must appear in
this file" — e.g. a documentation/marker check) from an illegitimate one; that judgement is
the reader's. It is therefore ADVISORY: exit 0 always, unless --strict.

Usage:
  tests/lint-source-grep-assertions.py [--strict] [--max N] [tests/test_foo.sh …]
"""
import os
import re
import sys

REPO_ROOT_VARS = ("SRC_DIR", "ROOT", "REPO_ROOT", "SRC", "REPO")
# `VAR="$SRC_DIR/relay/scripts/x.sh"` — an assignment naming a file in the shipped tree.
ASSIGN_RE = re.compile(
    r'^\s*(?:local\s+|export\s+)?([A-Za-z_][A-Za-z0-9_]*)=\"?\$\{?(' + "|".join(REPO_ROOT_VARS) + r')\}?/([^\"\s;]+)'
)
GREP_RE = re.compile(r'(?<![\w-])(?:grep|rg)\b(?P<rest>[^\n]*)')
# grep operands of the form "$VAR" — the LAST one in the grep's own command segment is its file
TARGET_RE = re.compile(r'\"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"')


def analyse(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return []
    lines = text.split("\n")

    # 1. variables bound to a file in the shipped source tree
    src_vars = {}
    for ln in lines:
        m = ASSIGN_RE.match(ln)
        if m:
            src_vars[m.group(1)] = m.group(3)
    if not src_vars:
        return []

    # 2. does the file EXECUTE any of them? "$V" must stand in COMMAND POSITION — either as the
    #    first word of a command, or straight after an interpreter (bash/sh/node/python3/env).
    #    `[[ -f "$V" ]]`, `node --check "$V"`, `bash -n "$V"` and `node "$LINT" "$V"` (the var as
    #    an ARGUMENT to some other tool) are NOT execution: none of them runs its logic.
    SEP = re.compile(r'(?:^|\|\||&&|[|;(]|\$\(|`|\bthen\b|\bdo\b|\belse\b)')
    INTERP = {"bash", "sh", "zsh", "node", "python", "python3", "env", "exec", "command", "time"}
    executed = set()
    for v in src_vars:
        tok = re.compile(r'\"\$\{?' + re.escape(v) + r'\}?\"')
        for ln in lines:
            if ln.strip().startswith("#"):
                continue
            for m in tok.finditer(ln):
                head = ln[:m.start()]
                cut = 0
                for s in SEP.finditer(head):
                    cut = s.end()
                words = head[cut:].split()
                if not words:
                    executed.add(v)
                    break
                if words[0] in ("if", "!", "while", "until"):
                    words = words[1:]
                if not words:
                    executed.add(v)
                    break
                if words[0] in INTERP:
                    rest = words[1:]
                    if any(w in ("-n", "--check", "-c") for w in rest):
                        continue          # syntax gate, not execution
                    if all(w.startswith("-") for w in rest):
                        executed.add(v)
                        break
            if v in executed:
                break

    hits = []
    for i, ln in enumerate(lines, 1):
        stripped = ln.strip()
        if stripped.startswith("#"):
            continue
        if not GREP_RE.search(ln):
            continue
        if "<<<" in ln or "<<" in ln:
            continue          # asserting on captured OUTPUT — behavioural
        g = GREP_RE.search(ln)
        seg = ln[g.start():]
        cut = re.search(r'\|\||&&|;|\s\|\s', seg)
        if cut:
            seg = seg[:cut.start()]
        ops = TARGET_RE.findall(seg)
        if not ops:
            continue
        var = ops[-1]
        if var not in src_vars:
            continue
        target = src_vars[var]
        if target.rsplit(".", 1)[-1] in ("md", "toml", "txt", "json", "yml", "yaml"):
            # a grep over a DOC/CONFIG is a legitimate content contract, not a behavioural
            # claim about executable code — reported separately, never in the headline count
            kind = "DOC"
        else:
            kind = "MIXED" if var in executed else "SHAPE-ONLY"
        hits.append((i, kind, var, src_vars[var], stripped))
    return hits


def main(argv):
    strict = "--strict" in argv
    argv = [a for a in argv if a != "--strict"]
    maxn = None
    if "--max" in argv:
        k = argv.index("--max")
        maxn = int(argv[k + 1])
        del argv[k:k + 2]

    here = os.path.dirname(os.path.abspath(__file__))
    files = argv or sorted(
        os.path.join(here, f) for f in os.listdir(here)
        if f.startswith("test_") and f.endswith(".sh")
    )

    total = 0
    docs = 0
    shape_only_files = []
    per_file = []
    for f in files:
        hits = analyse(f)
        if not hits:
            continue
        code = [h for h in hits if h[1] != "DOC"]
        docs += len(hits) - len(code)
        if not code:
            continue
        total += len(code)
        per_file.append((f, code))
        if any(h[1] == "SHAPE-ONLY" for h in code):
            shape_only_files.append(f)

    for f, hits in per_file:
        print(f"{os.path.relpath(f)}  ({len(hits)} source-grep assertion(s))")
        for lineno, kind, var, target, src in hits:
            print(f"  {kind:10} :{lineno}  ${var} -> {target}")
            print(f"             {src}")

    print()
    print(f"TOTAL: {total} source-grep assertion(s) over EXECUTABLE code in {len(per_file)} "
          f"file(s) (+{docs} over docs/config, not counted).")
    print(f"  {len(shape_only_files)} file(s) carry at least one SHAPE-ONLY hit — a grep over a "
          f"source file the test never runs.")
    for f in shape_only_files:
        print(f"  SHAPE-ONLY FILE: {os.path.relpath(f)}")
    print("ADVISORY: a source grep is not automatically wrong — it is wrong when it is the "
          "ONLY evidence for a BEHAVIOURAL claim. Review each hit; see id:05a2 / id:3a50.")

    if strict and (maxn is None or total > maxn):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
