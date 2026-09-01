#!/usr/bin/env python3
"""Flag VACUOUS FIXTURES in tests/ (id:292b, mechanism (1) only).

The defect class: a "defect-fix" test (guards a bug rather than an open ROADMAP item) that
LOOKS behavioural but proves nothing, because nothing on record says what negative case it
must fail against. Without that record a test can go green against its own revert and no one
would notice — three live 2026-08-13 instances motivated this lint (see TODO id:292b).

What this mechanism checks
---------------------------
Every "defect-fix" test file — a `tests/test_*.sh` carrying NO `# roadmap:XXXX` header (the
harness convention, CLAUDE.md §Testing: a file WITH that header is the RED spec of an open
ROADMAP item, and its redness IS the point, so it is exempt) — MUST declare a
`# fails-against: <rev|mutation>` header naming the revision/mutation it must fail against.

  - A defect-fix test WITHOUT `# fails-against:` is FLAGGED.
  - A defect-fix test WITH `# fails-against:` PASSES.
  - A roadmap-spec test (carries `# roadmap:`) is NEVER flagged, regardless.

Deliberately OUT of scope (see ROADMAP id:292b): actually checking out/mutating the named
revision and re-running the test to confirm it fails there — that is the CI-runner half of
mechanism (1), a follow-up, not this item. This mechanism only checks that the header is
DECLARED, making the discipline conscious and on-record; it does not verify the claim.
Also out of scope: mechanism (2) reached-fixture and mechanism (3) ledger-token-shape.

  → THE RUNNER NOW EXISTS: `tests/verify-negative-cases.py` (TODO id:a73c) executes the
    declared case and checks that the assertion which fails is the one the file claims to
    pin. It is opt-in (`make verify-negatives`), not part of `tests/run-tests.sh`.

Exemptions are shared with that runner and live in ONE reviewable allowlist,
`tests/negative-case-exemptions.txt` (owner-decided) -- never scattered `n/a` comments.

Advisory by default (exit 0); non-zero only under `--strict` (mirrors the sibling lint
`tests/lint-source-grep-assertions.py`'s `--strict`/`--max N` shape).

Usage:
  tests/lint-vacuous-fixtures.py [--strict] [--max N] [tests/test_foo.sh …]
"""
import os
import re
import sys

ROADMAP_RE = re.compile(r'^\s*#\s*roadmap:\S+', re.MULTILINE)
FAILS_AGAINST_RE = re.compile(r'^\s*#\s*fails-against:\s*\S', re.MULTILINE)


def analyse(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    if ROADMAP_RE.search(text):
        return None  # roadmap-spec test — exempt, its redness is the spec
    if FAILS_AGAINST_RE.search(text):
        return None  # declared — compliant
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
        print(f"VIOLATION: {os.path.relpath(f)}  — defect-fix test missing "
              f"'# fails-against: <rev|mutation>' header")

    print()
    print(f"TOTAL: {len(violations)} defect-fix test file(s) missing '# fails-against:' "
          f"in {len(files)} file(s) scanned.")
    print("ADVISORY: declares the negative case a defect-fix test must prove it fails "
          "against — see TODO id:292b. Does not verify the claim (that is the CI-runner "
          "follow-up, out of scope here).")

    if strict and (maxn is None or len(violations) > maxn):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
