#!/usr/bin/env python3
"""Flag VACUOUS FIXTURES in tests/ (id:292b, mechanism (1) only).

The defect class: a "defect-fix" test (guards a bug rather than an open ROADMAP item) that
LOOKS behavioural but proves nothing, because nothing on record says what negative case it
must fail against. Without that record a test can go green against its own revert and no one
would notice — three live 2026-08-13 instances motivated this lint (see TODO id:292b).

What this mechanism checks
---------------------------
Every "defect-fix" test file — a `tests/test_*.sh` carrying NO `# roadmap:XXXX` header (the
harness convention, CLAUDE.md §Testing: a file WITH that header is the RED spec of a
ROADMAP item, and its redness IS the point, so it is exempt) MUST declare a
`# fails-against…` header naming the revision/mutation it must fail against.

  - A defect-fix test WITHOUT any declaration is FLAGGED.
  - A defect-fix test WITH one PASSES. All THREE ratified spellings count (id:7c82):
    the prose `# fails-against:` and the machine-readable `# fails-against-rev:` /
    `# fails-against-mutation:`. This lint used to match only the bare form and so flagged
    every file carrying a machine-readable case as undeclared.
  - A roadmap-spec test (carries `# roadmap:`) whose item is still OPEN is NEVER flagged --
    its redness IS the spec.
  - A roadmap-spec test whose item is CLOSED is exempt ONLY while untouched since closure
    (id:799f). If it has gained a non-comment line since the commit that closed its item --
    a case grafted into an already-landed spec, exactly the way a defect-fix case would be
    added to any other file -- it is FLAGGED like any undeclared defect-fix test. See
    "THE POST-CLOSE GRAFT CHECK" below. A closed item whose closing commit cannot be
    resolved (token absent from ROADMAP.md/ROADMAP.archive.md, e.g. TODO-only) stays exempt
    -- this lint never invents a violation it cannot ground in git history.

Deliberately OUT of scope (see ROADMAP id:292b): actually checking out/mutating the named
revision and re-running the test to confirm it fails there — that is the CI-runner half of
mechanism (1), a follow-up, not this item. This mechanism only checks that the header is
DECLARED, making the discipline conscious and on-record; it does not verify the claim.
Also out of scope: mechanism (2) reached-fixture and mechanism (3) ledger-token-shape.

  → THE RUNNER NOW EXISTS: `tests/verify-negative-cases.py` (TODO id:a73c) executes the
    declared case and checks that the assertion which fails is the one the file claims to
    pin. It is opt-in (`make verify-negatives`), not part of `tests/run-tests.sh`.

THE POST-CLOSE GRAFT CHECK (id:799f)
-------------------------------------
The file-scoped roadmap carve-out answers "does this file, AS A WHOLE, owe a declaration?"
-- and a file that is itself the red spec of an OPEN item legitimately does not. But that
same carve-out used to survive the item's closure forever, keyed only on the token's
PRESENCE (see the id:227d/64f9 incident this item's ROADMAP block cites): a defect-fix case
grafted into an already-landed roadmap-keyed file inherited the blanket exemption and was
verifiable by neither this lint nor the runner, permanently.

For a CLOSED roadmap-keyed file with no declaration, `graft_since_close()` finds the commit
that closed the item (blames the ticked line in `ROADMAP.md`, or the line in
`ROADMAP.archive.md` if the item moved there) and diffs the file's current content against
that commit. Any added, non-comment, non-blank line means the file changed after its item
closed with nothing recording what that change must fail against -- flagged, same as an
ordinary undeclared defect-fix test. An untouched landed RED spec (no diff, or only comment
churn -- a retargeted `# roadmap:` key, a clarifying note) stays exempt: this is what keeps
the population of already-landed specs from becoming 355 new violations. A token this lint
cannot resolve to a closing commit (never present in `ROADMAP.md`/`ROADMAP.archive.md`, e.g.
tracked only in `TODO.md`) also stays exempt -- the check never guesses.

Exemptions are shared with that runner and live in ONE reviewable allowlist,
`tests/negative-case-exemptions.txt` (owner-decided) -- never scattered `n/a` comments.

Advisory by default (exit 0); non-zero only under `--strict` (mirrors the sibling lint
`tests/lint-source-grep-assertions.py`'s `--strict`/`--max N` shape).

Usage:
  tests/lint-vacuous-fixtures.py [--strict] [--max N] [tests/test_foo.sh …]
"""
import functools
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from negative_case_syntax import (  # noqa: E402
    DECLARATION_RE, DECLARATION_SPELLINGS, roadmap_item_open, roadmap_token)

# NOTE (id:7c82): the two regexes that used to live here are GONE. They said
# `roadmap:\S+` and `fails-against:` (the BARE spelling only), so this lint could not see
# the ratified `# fails-against-rev:` / `# fails-against-mutation:` forms and flagged every
# file using them as undeclared -- while `tests/verify-negative-cases.py`, reading the same
# headers, accepted them. Both tools now import ONE definition from
# `tests/lib/negative_case_syntax.py` (the id:4983 defect class). Do not reintroduce a local
# copy of either pattern.
#
# The roadmap carve-out asks "is this a defect-fix test, i.e. one that owes a declaration?",
# and a roadmap-spec file is not one WHILE its item is open -- that much stays PRESENCE-based
# and matches the RUNNER's carve-out. Once the item CLOSES the presence-only reading is
# exactly the id:799f blind spot (see THE POST-CLOSE GRAFT CHECK above): `graft_since_close()`
# below is what keeps that carve-out from surviving closure forever.


def _repo_root(path):
    """The git worktree root containing `path` (per-file, not this script's own location --
    a fixture test invokes this lint against files living in a throwaway repo elsewhere)."""
    d = os.path.dirname(os.path.abspath(path))
    try:
        out = subprocess.run(
            ["git", "-C", d, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.dirname(d)  # fallback: assume the usual <root>/tests/<file> layout


@functools.lru_cache(maxsize=None)
def _closing_commit(root, token):
    """Best-effort commit sha at which ROADMAP.md/ROADMAP.archive.md closed `token`, or
    None if it cannot be resolved (never present, or present only in TODO.md)."""
    for relpath in ("ROADMAP.md", "ROADMAP.archive.md"):
        full = os.path.join(root, relpath)
        if not os.path.exists(full):
            continue
        try:
            lines = open(full, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        pat = re.compile(r'<!-- id:%s -->' % re.escape(token))
        for i, line in enumerate(lines, start=1):
            if not pat.search(line):
                continue
            # ROADMAP.md: only a TICKED line counts as closed. ROADMAP.archive.md: every
            # line there is closed by construction (archiving only happens to `[x]` items).
            if relpath == "ROADMAP.md" and '- [x]' not in line:
                continue
            try:
                out = subprocess.run(
                    ["git", "-C", root, "blame", "-L", "%d,%d" % (i, i),
                     "--porcelain", "--", relpath],
                    capture_output=True, text=True, timeout=10)
            except (OSError, subprocess.SubprocessError):
                return None
            if out.returncode != 0 or not out.stdout:
                continue
            sha = out.stdout.splitlines()[0].split()[0]
            if sha and all(c in "0123456789abcdef" for c in sha):
                return sha
    return None


# An added line counts as a GRAFTED CASE only if it looks like it exercises an assertion --
# not any code churn. This repo's own test convention (CLAUDE.md §Testing) is a `fail()`
# helper emitting a `FAIL:` line; 569 of 625 test files already follow it. Scoping to this
# keeps a post-close reformat, comment retarget, or unrelated variable rename (real, common,
# and NOT what id:799f is about) from reading as a graft -- only a line that itself performs
# or names a check does.
_ASSERTION_LINE_RE = re.compile(r'\bfail\b|\bassert', re.IGNORECASE)


def graft_since_close(root, path, token):
    """True iff `path` gained an assertion-shaped line since the commit that closed `token`
    -- a case grafted into an already-landed roadmap-keyed spec (id:799f)."""
    sha = _closing_commit(root, token)
    if not sha:
        return False  # can't ground it in history -- never invent a violation
    relpath = os.path.relpath(os.path.abspath(path), root)
    try:
        out = subprocess.run(
            ["git", "-C", root, "diff", sha, "--", relpath],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    if out.returncode != 0:
        return False
    for line in out.stdout.splitlines():
        if not line.startswith('+') or line.startswith('+++'):
            continue
        added = line[1:].strip()
        if not added or added.startswith('#'):
            continue
        if _ASSERTION_LINE_RE.search(added):
            return True
    return False


def analyse(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    if DECLARATION_RE.search(text):
        return None  # declared (prose OR a machine-readable case): compliant
    token = roadmap_token(text)
    if token:
        root = _repo_root(path)
        if roadmap_item_open(root, token):
            return None  # roadmap-spec test, item still open — exempt, its redness is the spec
        if not graft_since_close(root, path, token):
            return None  # closed, undeclared, but untouched since closure — still exempt
        return True  # closed roadmap-spec, undeclared, gained a line since closure — violation
    return True  # defect-fix test missing the declaration — violation


def load_exempt(here):
    """Basenames excused via the ONE shared allowlist (see module docstring)."""
    path = os.path.join(here, "negative-case-exemptions.txt")
    names = set()
    if not os.path.exists(path):
        return names
    for raw in open(path, encoding="utf-8"):
        if raw.lstrip().startswith("#") or not raw.strip():
            continue
        names.add(raw.split("--", 1)[0].strip())
    return names


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

    exempt = load_exempt(here)
    violations = []
    for f in files:
        if os.path.basename(f) in exempt:
            continue
        if analyse(f):
            violations.append(f)

    for f in violations:
        print(f"VIOLATION: {os.path.relpath(f)}  -- defect-fix test missing a negative-case "
              f"header (one of: {'; '.join(DECLARATION_SPELLINGS)})")

    print()
    print(f"TOTAL: {len(violations)} defect-fix test file(s) missing a '# fails-against…' "
          f"declaration in {len(files)} file(s) scanned.")
    print("ADVISORY: declares the negative case a defect-fix test must prove it fails "
          "against — see TODO id:292b. Does not verify the claim (that is the CI-runner "
          "follow-up, out of scope here).")

    if strict and (maxn is None or len(violations) > maxn):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
