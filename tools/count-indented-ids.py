#!/usr/bin/env python3
"""count-indented-ids.py -- THE counting rule for "ledger lines that are INDENTED and
carry their own `<!-- id:XXXX -->` anchor". id:8679.

WHY THIS EXISTS. Three figures for this one population are on record and all three are
load-bearing: 11 (the 2026-09-01 ruling, owner-marked UNVERIFIED), 21 (measured the same
day) and 10 (measured 2026-09-02, after the wave-2/3 shrink). They were produced by three
different ad-hoc greps against three different trees, so the numbers were never comparable
and averaging them would have hidden that. A promote pass sized off the wrong one silently
skips real items -- which is exactly the shape loderite MEASURED when four ids (89f9, a5b6,
ba07, ed26) were orphaned: body relocated, address lost, counts unchanged, round-trip green.

So the rule below is COMMITTED, and every future count -- a promote pass, a ruling, a
review -- calls this script instead of writing its own grep. A count is only meaningful
paired with its AS-OF commit, so `--rev` reads the ledger out of git rather than the
worktree, and the report always names the revision it measured.

THE COUNTING RULE, stated so it can be argued with:

  1. INDENTED     the line matches `^[ \\t]+` and is not blank. A top-level item line is a
                  different population (`ledger-shrink.py` owns those) and is excluded.
  2. NOT FENCED   lines inside a ``` fenced block are documentation OF the grammar, not
                  instances of it. A fixture heredoc in a doc would otherwise inflate the
                  count.
  3. ANCHORED     the line contains at least one `<!-- id:XXXX -->` whose match does NOT
                  begin inside an inline-code span. A backticked marker is PROSE quoting an
                  address, not an address (id:2964's mask half, imported here rather than
                  re-derived -- `ledger-continuations.code_spans` is the CommonMark-correct
                  N-backtick implementation).
  4. ADDRESSABLE  EXACTLY ONE such anchor. This is the half every ad-hoc grep gets wrong.
                  Per id:6059 BOTH `meeting/md-merge.py` and `relay/scripts/lib-typed-edges.sh`
                  REFUSE a multi-marker line: it resolves to NOTHING, with a stderr warning.
                  So a line carrying two or more anchors does not carry "its own" id at all
                  -- no tool can address it, and a promote pass cannot move it. It is
                  counted, separately and loudly, as `unaddressable`.

`indented_anchored` = `addressable` + `unaddressable`. Report both; never collapse them into
one headline number, because the two demand different actions (promote vs. split the line
first).

  5. CHECKBOX    an addressable line is further split by whether it is `- [ ]`/`- [x]`
                 shaped. This is NOT decoration: a promote pass moves a sub-ITEM to column 0,
                 and only a checkbox line IS a sub-item. A non-checkbox indented line
                 carrying an id (a bolded sub-heading, a prose continuation) is addressable
                 but has nothing to promote. Reporting the split is what made 11-vs-21
                 resolvable at all -- see `docs/ledger-notes/8679.md`.

EXIT CODES: 0 ok; 2 `--expect` mismatch (the anti-drift gate); 1 usage/IO error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from importlib import import_module

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Reuse, never re-derive: `code_spans` is the CommonMark N-backtick span finder already
# proven in the shrink tooling, and `ID_RE` is the one anchor pattern the ecosystem uses.
_lc = import_module("ledger-continuations")
code_spans = _lc.code_spans
ID_RE = _lc.ID_RE

DEFAULT_FILES = ["TODO.md", "ROADMAP.md", "TODO.archive.md", "ROADMAP.archive.md"]

INDENT_RE = re.compile(r"^[ \t]+\S")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
CHECKBOX_RE = re.compile(r"^[ \t]+[-*] \[[ xX]\]")


def anchors(line: str):
    """Anchor matches on `line` that are NOT quoted inside an inline-code span."""
    spans = code_spans(line)
    return [m for m in ID_RE.finditer(line)
            if not any(a <= m.start() < b for a, b in spans)]


def classify(text: str):
    """-> (addressable, unaddressable) lists of (lineno, id_or_None, line)."""
    addressable, unaddressable = [], []
    fenced = False
    for n, line in enumerate(text.split("\n"), 1):
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced or not INDENT_RE.match(line):
            continue
        found = anchors(line)
        if not found:
            continue
        if len(found) == 1:
            addressable.append((n, found[0].group(1), line))
        else:
            unaddressable.append((n, [m.group(1) for m in found], line))
    return addressable, unaddressable


def read_source(root: str, rel: str, rev: str | None) -> str | None:
    if rev is None:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            return None
        return open(path, encoding="utf-8").read()
    out = subprocess.run(["git", "-C", root, "show", "{}:{}".format(rev, rel)],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return out.stdout


def resolve_rev(root: str, rev: str | None) -> str:
    ref = rev if rev else "HEAD"
    out = subprocess.run(["git", "-C", root, "rev-parse", "--short", ref],
                         capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else "(not a git tree)"


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Count ledger lines that are indented and carry their own id anchor "
                    "(id:8679). The counting rule is documented in this file's docstring.")
    ap.add_argument("--root", default=".")
    ap.add_argument("--file", action="append", dest="files",
                    help="ledger to count (repeatable); default: the four live ledgers")
    ap.add_argument("--rev", default=None,
                    help="measure the ledger AS OF this git revision instead of the worktree")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--show-lines", action="store_true",
                    help="print every counted line's number and id")
    ap.add_argument("--expect", type=int, default=None,
                    help="exit 2 unless the ADDRESSABLE total over all counted files is N")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    files = args.files if args.files else DEFAULT_FILES
    asof = resolve_rev(root, args.rev)

    report = {"as_of": asof, "rev_arg": args.rev, "files": {},
              "totals": {"indented_anchored": 0, "addressable": 0,
                         "addressable_checkbox": 0, "unaddressable": 0}}

    for rel in files:
        text = read_source(root, rel, args.rev)
        if text is None:
            report["files"][rel] = {"missing": True}
            continue
        addr, unaddr = classify(text)
        cb = [t for t in addr if CHECKBOX_RE.match(t[2])]
        report["files"][rel] = {
            "addressable": len(addr),
            "addressable_checkbox": len(cb),
            "addressable_non_checkbox": len(addr) - len(cb),
            "unaddressable": len(unaddr),
            "indented_anchored": len(addr) + len(unaddr),
            "addressable_lines": [{"line": n, "id": i,
                                   "checkbox": bool(CHECKBOX_RE.match(l))}
                                  for n, i, l in addr],
            "unaddressable_lines": [{"line": n, "ids": i} for n, i, _ in unaddr],
        }
        report["totals"]["addressable"] += len(addr)
        report["totals"]["addressable_checkbox"] += len(cb)
        report["totals"]["unaddressable"] += len(unaddr)
        report["totals"]["indented_anchored"] += len(addr) + len(unaddr)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("== indented lines carrying their own id anchor (id:8679) ==")
        print("as-of commit : {}".format(asof))
        for rel in files:
            d = report["files"][rel]
            if d.get("missing"):
                print("{:<20} : (absent at this revision)".format(rel))
                continue
            print("{:<20} : addressable {:>3} (checkbox {:>3} / other {:>3})   "
                  "unaddressable {:>3}   anchored {:>3}".format(
                      rel, d["addressable"], d["addressable_checkbox"],
                      d["addressable_non_checkbox"], d["unaddressable"],
                      d["indented_anchored"]))
            if args.show_lines:
                for e in d["addressable_lines"]:
                    print("    addressable   line {:>5}  id:{}  {}".format(
                        e["line"], e["id"], "checkbox" if e["checkbox"] else "other"))
                for e in d["unaddressable_lines"]:
                    print("    unaddressable line {:>5}  ids:{}".format(
                        e["line"], ",".join(e["ids"])))
        t = report["totals"]
        print("TOTAL                : addressable {} (checkbox {} / other {})   "
              "unaddressable {}   anchored {}".format(
                  t["addressable"], t["addressable_checkbox"],
                  t["addressable"] - t["addressable_checkbox"],
                  t["unaddressable"], t["indented_anchored"]))

    if args.expect is not None and args.expect != report["totals"]["addressable"]:
        print("DRIFT: expected addressable {}, measured {} (as-of {})".format(
            args.expect, report["totals"]["addressable"], asof), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
