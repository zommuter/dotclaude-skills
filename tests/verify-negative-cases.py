#!/usr/bin/env python3
"""Run the DECLARED negative case of every defect-fix test and check it dies for the RIGHT
reason (TODO id:a73c -- the CI negative-case runner half; sibling of the mechanism-(1) lint
`tests/lint-vacuous-fixtures.py`, which only checks that the header is DECLARED).

WHY THIS EXISTS
---------------
`# fails-against:` is a CLAIM. Mechanism (1) verifies the claim is on record; nothing
verified the claim itself. On 2026-09-01 three live instances shipped with the header
present and the claim false (TODO id:a73c records them):

  (a) id:9fa2's test, run against ancestor 275fec46, died at assertion (a) because that
      ancestor rejects the new file FORMAT outright -- the two assertions the file exists
      to pin were UNREACHED. Red, for the wrong reason.
  (b) id:a290's case L: the mutant was killed by a fixture-SANITY probe, not by the case
      written for it -- that case had zero demonstrated killing power.
  (c) id:8302/59c5: a RED spec whose fixture carried NO ASSERTION at all.

THE RULE THIS ENCODES, which mechanism (1) structurally cannot express:
**it is not enough that the test FAILS against the declared revision -- the assertion that
fails must be the one the file claims to pin.** A file that dies at an EARLIER assertion,
that is killed by a fixture-sanity probe, or whose fixture never reaches the guarded path
is red for the wrong reason and is exactly as vacuous as one that passes.

So each declared case is verified in BOTH directions:
  GREEN-NOW -- the test passes against the current tree (else its redness proves nothing);
  RED-THERE -- against the declared rev/mutation it fails, AND the FAIL line that fires
              contains the declared `# fails-against-assertion:` substring.

HEADER GRAMMAR (only the first token is new-and-required, and only for opted-in files)
--------------------------------------------------------------------------------------
    # fails-against: <prose>                          (mechanism (1); unchanged, still required)
    # fails-against-rev: <rev> -- <path> [<path>…]    (machine-readable case: that revision's
                                                       version of those paths, everything else
                                                       from the current tree)
    # fails-against-mutation: <shell command>         (machine-readable case: run in a scratch
                                                       copy of the tree, cwd = its root)
    # fails-against-assertion: <substring>            (which FAIL line must fire; one or more
                                                       per case, ALL must be satisfiable --
                                                       see MULTI below)

A `-rev`/`-mutation` line OPENS a case; every `-assertion:` line after it, until the next
case line, belongs to that case. A case with no assertion is a CONFIG ERROR (exit 2) -- that
is instance (c), an assertion-less fixture, refused rather than counted.

MULTI: a test exits at its FIRST failing assertion, so exactly one FAIL line normally fires.
Several `-assertion:` lines on one case are read as "any ONE of these" (alternatives, e.g.
two spellings of the same message across git versions), NOT "all". Use separate cases when
you mean separate defects.

WHY MATCH ON THE `FAIL:` LINE TEXT
----------------------------------
`fail() { echo "FAIL: $*"; exit 1; }` is this repo's universal idiom -- 292 of 546 test files
use that exact spelling, the rest a printf variant of the same `FAIL: ` prefix. The failing
assertion therefore already NAMES itself in the output, in text a human wrote to be read.
Matching it needs no new marker in the 161 headerless files, no per-assertion ids, and no
rewriting of the corpus. The match is deliberately scoped to `FAIL:`-prefixed lines only: the
whole output would let a `PASS: (e) …` line satisfy an `(e)` expectation, which is precisely
the wrong-reason bug this runner exists to catch.

COVERAGE, and why it is REPORTED rather than assumed
----------------------------------------------------
The lint (mechanism 1) is fail-closed over ALL headerless `tests/test_*.sh`. This runner can
only execute the files that carry a machine-readable case, so it reports four populations --
VERIFIED / UNVERIFIED (prose-only header) / UNDECLARED (no `# fails-against:` at all, which is
the LINT's finding, not this one) / EXEMPT (allowlist) -- and prints the counts every run.
`--strict-coverage` turns a non-empty UNVERIFIED or UNDECLARED set into exit 1. Exemptions
live in ONE reviewable allowlist, `tests/negative-case-exemptions.txt` (owner-decided,
id:a73c), shared with the lint -- never scattered `n/a` comments.

COST -- this is NOT a suite-time check. Each case copies the tracked tree and runs the test
twice (green-now + red-there). Use `make verify-negatives` (opt-in), or `--changed <base>`
in a pre-push/CI hook to verify only the defect-fix tests a branch actually touched.
`--list` is free: it reports coverage without running anything.

Hermetic + offline: scratch trees under `mktemp -d`, revisions read from the LOCAL object
database, no network, `~/.claude` never touched.

Usage:
  tests/verify-negative-cases.py [--root DIR] [--list] [--strict-coverage]
                                 [--changed [BASE]] [--timeout SEC] [tests/test_foo.sh …]
Exit: 0 ok · 1 a case failed (or --strict-coverage with gaps) · 2 config/usage error.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

CASE_RE = re.compile(r'^\s*#\s*fails-against-(rev|mutation):\s*(.+?)\s*$')
ASSERT_RE = re.compile(r'^\s*#\s*fails-against-assertion:\s*(.+?)\s*$')
PROSE_RE = re.compile(r'^\s*#\s*fails-against:\s*\S', re.MULTILINE)
ROADMAP_RE = re.compile(r'^\s*#\s*roadmap:\S+', re.MULTILINE)
FAILLINE_RE = re.compile(r'^\s*FAIL:', re.MULTILINE)

EXEMPTIONS = "tests/negative-case-exemptions.txt"


# --------------------------------------------------------------------------- exemptions
def load_exemptions(root):
    """Parse the ONE reviewable allowlist. Format: `<basename>  -- <reason>` per line.

    A reason is MANDATORY: an exemption nobody had to justify is the scattered-`n/a`
    failure mode with extra steps. Returns {basename: reason}; raises on a bad line.
    """
    path = os.path.join(root, EXEMPTIONS)
    out = {}
    if not os.path.exists(path):
        return out
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        if raw.lstrip().startswith("#"):
            continue  # whole-line comment (a reason may itself contain '#')
        line = raw.strip()
        if not line:
            continue
        if "--" not in line:
            raise ValueError(f"{EXEMPTIONS}:{n}: exemption needs a reason: "
                             f"`<test_foo.sh>  -- <why>` (got: {line!r})")
        name, reason = line.split("--", 1)
        name, reason = name.strip(), reason.strip()
        if not name or not reason:
            raise ValueError(f"{EXEMPTIONS}:{n}: empty name or reason in {line!r}")
        out[name] = reason
    return out


# ------------------------------------------------------------------------------ parsing
def header_block(text):
    """The LEADING comment block only -- shebang, blank lines and `#` comments, stopping at
    the first line of code.

    Scoped deliberately: test files build fixture scripts in heredocs, and those fixtures
    legitimately contain their own `# roadmap:` / `# fails-against-*:` lines at column 0. A
    whole-file scan reads a fixture's header as the FILE's own (measured while building this
    runner: its own spec file vanished from the plan that way).
    """
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#!") or not s or s.startswith("#"):
            out.append(line)
            continue
        break
    return "\n".join(out)


def parse_header(path):
    """-> (prose_declared: bool, cases: [dict], errors: [str])."""
    text = open(path, encoding="utf-8").read()
    head = header_block(text)
    prose = bool(PROSE_RE.search(head)) if not ROADMAP_RE.search(text) else False
    cases, errors, cur = [], [], None
    for line in head.splitlines():
        m = CASE_RE.match(line)
        if m:
            kind, arg = m.group(1), m.group(2)
            cur = {"kind": kind, "arg": arg, "assertions": [], "file": path}
            cases.append(cur)
            continue
        m = ASSERT_RE.match(line)
        if m:
            if cur is None:
                errors.append(f"{os.path.basename(path)}: `# fails-against-assertion:` with no "
                              f"preceding `# fails-against-rev:`/`-mutation:` line")
            else:
                cur["assertions"].append(m.group(1))
    for c in cases:
        if not c["assertions"]:
            errors.append(f"{os.path.basename(path)}: case `{c['kind']}: {c['arg']}` declares NO "
                          f"`# fails-against-assertion:` -- an assertion-less negative case "
                          f"cannot be verified (id:a73c instance (c))")
        if c["kind"] == "rev":
            rev, paths = split_rev_arg(c["arg"])
            if not paths:
                errors.append(f"{os.path.basename(path)}: `fails-against-rev: {c['arg']}` names no "
                              f"path -- expected `<rev> -- <path> [<path>…]`")
            c["rev"], c["paths"] = rev, paths
    return prose, cases, errors


def split_rev_arg(arg):
    toks = arg.split()
    rev = toks[0] if toks else ""
    rest = toks[1:]
    if rest and rest[0] == "--":
        rest = rest[1:]
    return rev, rest


# ------------------------------------------------------------------------ tree materialisation
def git(root, *args, **kw):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, **kw)


def init_scratch_repo(root, dest):
    """Make the scratch tree a real (single-commit) git repo.

    Not cosmetic: this repo's tests routinely run `git -C "$ROOT" status` /
    `git rev-parse --show-toplevel` against their own root, and a plain file copy makes those
    exit 128 -- which the runner would then report as a GREEN-NOW failure, i.e. a harness leak
    masquerading as a finding. History is a SINGLE synthetic commit; a test that needs the
    real commit graph is not verifiable this way and should say so in an exemption.
    """
    if git(root, "rev-parse", "--git-dir").returncode != 0:
        return
    br = git(root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip() or "main"
    cfg = ["-c", "user.name=negcase", "-c", "user.email=negcase@invalid",
           "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", "init", "-q", "-b", br, dest], capture_output=True, text=True)
    subprocess.run(["git", "-C", dest, *cfg, "add", "-A"], capture_output=True, text=True)
    subprocess.run(["git", "-C", dest, *cfg, "commit", "-qm", "negative-case scratch"],
                   capture_output=True, text=True)


def materialise(root, dest):
    """Copy the WORKING tree (tracked + untracked-not-ignored) into dest.

    The working tree, not HEAD: the point is to verify the test and the fix AS THEY STAND,
    including work that is not committed yet.
    """
    r = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    if r.returncode != 0:
        raise RuntimeError(f"git ls-files failed in {root}: {r.stderr.strip()}")
    for rel in filter(None, r.stdout.split("\0")):
        src = os.path.join(root, rel)
        if not os.path.isfile(src) or os.path.islink(src):
            continue  # submodule gitlinks / symlinks: not part of a hermetic scratch tree
        dst = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def apply_rev(root, dest, rev, paths):
    """Overwrite `paths` in dest with their content at `rev`. A path ABSENT at rev is
    DELETED in dest --"the script did not exist yet" is a legitimate negative case."""
    notes = []
    for rel in paths:
        blob = git(root, "show", f"{rev}:{rel}")
        dst = os.path.join(dest, rel)
        if blob.returncode != 0:
            if os.path.exists(dst):
                os.remove(dst)
            notes.append(f"{rel}: absent at {rev} (removed from scratch)")
            continue
        mode = "100644"
        lt = git(root, "ls-tree", rev, "--", rel)
        if lt.returncode == 0 and lt.stdout.strip():
            mode = lt.stdout.split()[0]
        os.makedirs(os.path.dirname(dst) or dest, exist_ok=True)
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(blob.stdout)
        os.chmod(dst, 0o755 if mode == "100755" else 0o644)
        notes.append(f"{rel}: @{rev}")
    return notes


def run_test(scratch, rel_test, timeout):
    env = dict(os.environ)
    env.pop("RUN_TESTS_NESTED", None)
    try:
        p = subprocess.run(["bash", rel_test], cwd=scratch, env=env, timeout=timeout,
                           capture_output=True, text=True)
        return p.returncode, (p.stdout + p.stderr)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"") + (e.stderr or b"")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return 124, out + f"\n[runner] TIMEOUT after {timeout}s"


def fail_lines(out):
    return [ln.strip() for ln in out.splitlines() if FAILLINE_RE.match(ln)]


# ----------------------------------------------------------------------------- verification
def verify_file(root, rel, cases, timeout, log):
    """-> list of problem strings (empty = all cases verified)."""
    problems = []
    base = os.path.basename(rel)

    # GREEN-NOW: the test must pass against the current tree. Skipping this would let a
    # permanently-red file look "verified" -- red everywhere proves nothing about the fix.
    with tempfile.TemporaryDirectory(prefix="negcase-now-") as scratch:
        materialise(root, scratch)
        init_scratch_repo(root, scratch)
        rc, out = run_test(scratch, rel, timeout)
    if rc != 0:
        fl = fail_lines(out) or ["(no FAIL: line -- aborted)"]
        problems.append(f"{base}: GREEN-NOW failed (rc={rc}) against the CURRENT tree; "
                        f"its redness elsewhere proves nothing. First FAIL: {fl[0]}")
        return problems
    log(f"  green-now  OK   {base}")

    for c in cases:
        label = f"{c['kind']}: {c['arg']}"
        with tempfile.TemporaryDirectory(prefix="negcase-") as scratch:
            materialise(root, scratch)
            if c["kind"] == "rev":
                r = git(root, "rev-parse", "--verify", "--quiet", c["rev"] + "^{commit}")
                if r.returncode != 0:
                    problems.append(f"{base}: revision {c['rev']!r} is not in the local object "
                                    f"database -- cannot verify `{label}`")
                    continue
                notes = apply_rev(root, scratch, c["rev"], c["paths"])
                log(f"    applied: {'; '.join(notes)}")
            else:
                m = subprocess.run(["bash", "-c", c["arg"]], cwd=scratch,
                                   capture_output=True, text=True)
                if m.returncode != 0:
                    problems.append(f"{base}: mutation command failed (rc={m.returncode}): "
                                    f"{c['arg']}\n      {m.stderr.strip()[:400]}")
                    continue
            # Commit AFTER the case is applied, so the scratch repo is CLEAN and its HEAD is
            # the world the test is being run against.
            init_scratch_repo(root, scratch)
            rc, out = run_test(scratch, rel, timeout)

        fl = fail_lines(out)
        if rc == 0:
            problems.append(f"{base}: VACUOUS -- the test PASSES against its declared negative "
                            f"case `{label}`. It demonstrates no killing power.")
            continue
        wanted = c["assertions"]
        hit = [w for w in wanted if any(w in ln for ln in fl)]
        if hit:
            log(f"  red-there  OK   {base}  [{label}]  -> {fl[0][:150]}")
            continue
        if not fl:
            tail = "\n      ".join(out.strip().splitlines()[-6:]) or "(no output)"
            problems.append(f"{base}: WRONG REASON -- died (rc={rc}) against `{label}` with NO "
                            f"`FAIL:` line at all, so no assertion fired. Expected one naming "
                            f"{wanted!r}. Tail:\n      {tail}")
        else:
            problems.append(f"{base}: WRONG REASON -- red against `{label}`, but at the WRONG "
                            f"assertion. Expected a FAIL line containing one of {wanted!r}; "
                            f"got:\n      " + "\n      ".join(fl[:4]))
    return problems


# ------------------------------------------------------------------------------------ main
def collect_files(root, argv_files, changed_base):
    tdir = os.path.join(root, "tests")
    if argv_files:
        # A named file may be given relative to --root or relative to cwd; prefer --root, so
        # `--root FIXTURE tests/test_x.sh` means the FIXTURE's file, not the caller's.
        out = []
        for f in argv_files:
            out.append(f if os.path.exists(os.path.join(root, f))
                       else os.path.relpath(os.path.abspath(f), root))
        return out
    names = sorted(f for f in os.listdir(tdir)
                   if f.startswith("test_") and f.endswith(".sh"))
    rels = [os.path.join("tests", n) for n in names]
    if changed_base is not None:
        r = git(root, "diff", "--name-only", changed_base)
        touched = set(filter(None, r.stdout.splitlines()))
        rels = [x for x in rels if x in touched]
    return rels


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", default=None)
    ap.add_argument("--list", action="store_true", help="report coverage; run nothing")
    ap.add_argument("--strict-coverage", action="store_true",
                    help="exit 1 if any non-exempt defect-fix test has no machine-readable case")
    ap.add_argument("--changed", nargs="?", const="HEAD", default=None, metavar="BASE",
                    help="only defect-fix tests changed vs BASE (default HEAD)")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args(argv)

    root = a.root or subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                    capture_output=True, text=True).stdout.strip()
    if not root or not os.path.isdir(os.path.join(root, "tests")):
        print("verify-negative-cases: cannot locate repo root (pass --root DIR)", file=sys.stderr)
        return 2
    log = (lambda *_: None) if a.quiet else (lambda s: print(s))

    try:
        exempt = load_exemptions(root)
    except ValueError as e:
        print(f"CONFIG ERROR: {e}", file=sys.stderr)
        return 2

    verified, unverified, undeclared, skipped_exempt, config_errors = [], [], [], [], []
    plan = []
    for rel in collect_files(root, a.files, a.changed):
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            config_errors.append(f"{rel}: no such file")
            continue
        base = os.path.basename(rel)
        # WHOLE-FILE roadmap detection, deliberately: `tests/run-tests.sh` and
        # `tests/lint-vacuous-fixtures.py` both grep the whole file, and a third opinion about
        # which files are defect-fix tests would be worse than the (3 measured) files whose
        # `# roadmap:` marker sits below their leading comment block. Only the
        # `fails-against-*` DIRECTIVES are header-block-scoped -- they are the ones fixture
        # heredocs counterfeit.
        if ROADMAP_RE.search(open(path, encoding="utf-8").read()):
            continue  # roadmap-spec test: its redness IS the spec (same carve-out as the lint)
        if base in exempt:
            skipped_exempt.append(base)
            continue
        prose, cases, errors = parse_header(path)
        config_errors.extend(errors)
        if cases and not errors:
            verified.append(base)
            plan.append((rel, cases))
        elif prose:
            unverified.append(base)   # mechanism (1) satisfied, not machine-verifiable yet
        else:
            undeclared.append(base)   # mechanism (1) violation -- the LINT's finding, not this one

    if config_errors:
        for e in config_errors:
            print(f"CONFIG ERROR: {e}")
        print(f"\nTOTAL: {len(config_errors)} malformed negative-case declaration(s).")
        return 2

    problems = []
    if not a.list:
        for rel, cases in plan:
            log(f"[{os.path.basename(rel)}] {len(cases)} declared case(s)")
            problems.extend(verify_file(root, rel, cases, a.timeout, log))

    print()
    for p in problems:
        print(f"VIOLATION: {p}")
    print(f"COVERAGE: {len(verified)} verifiable · {len(unverified)} unverified "
          f"(prose-only `# fails-against:`) · {len(undeclared)} undeclared "
          f"(no `# fails-against:` at all -- that is the LINT's finding, "
          f"tests/lint-vacuous-fixtures.py) · {len(skipped_exempt)} exempt "
          f"({EXEMPTIONS}).")
    if unverified and not a.quiet:
        print("  unverified: " + ", ".join(unverified))
    if a.list:
        print("LIST mode: nothing was executed.")
        return 1 if (a.strict_coverage and unverified) else 0
    print(f"TOTAL: {len(problems)} negative case(s) that do not fail for the declared reason, "
          f"across {len(plan)} file(s) executed.")
    if problems:
        return 1
    if a.strict_coverage and (unverified or undeclared):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
