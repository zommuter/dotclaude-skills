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
                                                       per case, read as ALTERNATIVES --
                                                       see MULTI below)

A `-rev`/`-mutation` line OPENS a case; every `-assertion:` line after it, until the next
case line, belongs to that case. A case with no assertion is a CONFIG ERROR (exit 2) -- that
is instance (c), an assertion-less fixture, refused rather than counted.

UNIQUE SITE (static, cheap, runs even under `--list`)
-----------------------------------------------------
A declared substring MUST match EXACTLY ONE line of the test file's own BODY (everything
below the leading comment block -- the header's own directive lines are excluded, and so is
nothing else). 0 sites means the declaration names an assertion the file does not contain;
2+ sites means the runner cannot tell WHICH of them fired, so a match proves nothing. Both
are CONFIG ERRORs (exit 2), not warnings.

This is not hypothetical tidiness. `CLAUDE.md` §Testing tells back-fillers to author the
ancestor case in the ANCESTOR's own spelling and to record per-ancestor reachability, so this
corpus will contain messages where an early assertion NAMES a later one, e.g.

    fail "(a) old format rejected outright, so (b) guard was never reached"
    fail "(b) guard must be present"

Declaring `(b) guard` against that file matched the (a) line by substring and was reported
OK -- id:a73c instance (a) VERBATIM, reported green. The remedy for a rejected declaration is
to NARROW it until it is unique, never to loosen the check.

MULTI -- and the false premise this paragraph used to state
-----------------------------------------------------------
This docstring previously asserted "a test exits at its FIRST failing assertion, so exactly
one FAIL line normally fires". **That is FALSE for a large minority of the corpus.** Measured
2026-09-01, counting files that define a FAIL-emitting shell function whose body contains no
`exit`/`return 1`: **75 of the 546 test files, 36 of the 161 this runner can hold.** (An
independent review counted 81/38 with a looser heuristic; either way the premise is false and
the direction is the same.) Those files use a NON-EXITING accumulator --
`note() { echo "FAIL: $*" >&2; fail=1; }`, `bad() { echo "  FAIL: $1"; fail=$((fail+1)); }` --
and exit once at the end. Accepting a hit on ANY fired FAIL line degraded the guarantee to
"any-of": a soft note could satisfy the declaration while a different assertion was the real
killer, which is close to the mechanism-(1) blind spot this runner exists to close.

So: when more than one FAIL line fires, ALL of them are reported and the declared substring
must match the **LAST** one -- the assertion the run ended on. Several `-assertion:` lines on
one case are ALTERNATIVES against that last line (e.g. two spellings of the same message
across git versions), never "any line, any of these". An accumulator whose declared assertion
genuinely is not last must narrow/re-declare to the last-firing one, split the case, or take
an exemption with a written reason -- the refusal is loud either way.
(Ordering is meaningful because the test's stdout and stderr are captured MERGED, in real
order; they used to be concatenated stdout-then-stderr, which scrambled it.)

WHY MATCH ON THE `FAIL:` LINE TEXT
----------------------------------
`fail() { echo "FAIL: $*"; exit 1; }` is this repo's dominant idiom -- measured 2026-09-01:
293 of 546 test files use that exact spelling, and 489 emit at least one line-leading
`FAIL:`. The earlier claim "292 verbatim, the rest a printf variant of the same prefix" was
WRONG: **55 of 546 emit no `FAIL:` text at all** (they use `|| { echo "…"; exit 1; }`), plus
2 that emit only a non-line-leading form. Those files can NEVER satisfy an assertion match,
so they are not silently accepted -- they belong in `tests/negative-case-exemptions.txt` with
an explicit reason, and the 12 measured today are listed there.

For the rest the failing assertion already NAMES itself in the output, in text a human wrote
to be read. Matching it needs no new marker in the 161 headerless files, no per-assertion
ids, and no rewriting of the corpus. The match is deliberately scoped to `FAIL:`-prefixed
lines only: the whole output would let a `PASS: (e) …` line satisfy an `(e)` expectation,
which is precisely the wrong-reason bug this runner exists to catch.

COVERAGE, and why it is REPORTED rather than assumed
----------------------------------------------------
The lint (mechanism 1) is fail-closed over ALL headerless `tests/test_*.sh`. This runner can
only execute the files that carry a machine-readable case, so it reports FIVE populations --
VERIFIED / UNVERIFIED (prose-only header) / UNDECLARED (no `# fails-against:` at all, which is
the LINT's finding, not this one) / EXEMPT (allowlist) / ROADMAP-SPEC (carved out) -- and
prints the counts every run. The roadmap-spec bucket is REPORTED, not just skipped: roadmap
detection is WHOLE-FILE (deliberately, to agree with `tests/run-tests.sh` and the lint) while
the `fails-against-*` directives are header-block-scoped, so a file with a valid declaration
AND a `# roadmap:` token lower down -- in a fixture heredoc, say -- used to appear in NO
bucket at all and vanish from verification silently. Two live files did exactly that
(`test_orphan_scan_shipped.sh`, `test_orphan_scan_language_dispatch_15f3.sh`). Now they are
counted and named. `--strict-coverage` turns a non-empty UNVERIFIED or UNDECLARED set into
exit 1. Exemptions live in ONE reviewable allowlist,
`tests/negative-case-exemptions.txt` (owner-decided, id:a73c), shared with the lint -- never
scattered `n/a` comments.

COST -- this is NOT a suite-time check. Each case copies the tracked tree and runs the test
twice (green-now + red-there). Use `make verify-negatives` (opt-in), or `--changed <base>`
in a pre-push/CI hook to verify only the defect-fix tests a branch actually touched.
`--list` is free: it reports coverage and runs the static checks without executing anything.

CONTAINMENT -- read this before writing a `-mutation:` case
-----------------------------------------------------------
The runner's OWN actions are hermetic and offline: scratch trees under `mktemp -d`, revisions
read from the LOCAL object database, no network, `~/.claude` never touched. The docstring
used to stop there and claim "the real tree is untouched" flatly. **That claim was too broad
and is corrected here**: a `# fails-against-mutation:` line is an ARBITRARY `bash -c` command,
and an arbitrary command is not contained by choosing its cwd. A mutation writing to an
ABSOLUTE path outside the scratch was confirmed to clobber a file in the real tree.

What is now done about it:
  * each case gets a private SANDBOX directory holding the scratch tree plus its own TMPDIR,
    and the mutation runs with `TMPDIR`/`TMP`/`TEMP` and `GIT_CEILING_DIRECTORIES` pointed at
    that sandbox -- so a mutation's temp files stay inside it, and `git rev-parse
    --show-toplevel` cannot walk UPWARD out of the scratch into a real repo. (That walk is
    reachable because `init_scratch_repo` runs AFTER the mutation: at mutation time the
    scratch is not yet a git repo at all.)
  * after the mutation, the sandbox is checked for stray entries and the failure is loud.

RESIDUAL FOOT-GUN, stated plainly: none of this is a sandbox. `bash -c` can still write any
absolute path the invoking user can write, delete files, or call the network. A mutation
command is REVIEWED CODE in a tracked test header -- treat it exactly like any other script
in this repo, and never copy one from an untrusted source. Real containment would need an OS
mechanism (user/namespace/bwrap), which this runner deliberately does not attempt.

Usage:
  tests/verify-negative-cases.py [--root DIR] [--list] [--strict-coverage]
                                 [--changed [BASE]] [--timeout SEC] [tests/test_foo.sh …]
Exit: 0 ok · 1 a case failed (or --strict-coverage with gaps) · 2 config/usage error.
"""
import argparse
import contextlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

CASE_RE = re.compile(r'^\s*#\s*fails-against-(rev|mutation):\s*(.+?)\s*$')
ASSERT_RE = re.compile(r'^\s*#\s*fails-against-assertion:\s*(.+?)\s*$')
PROSE_RE = re.compile(r'^\s*#\s*fails-against:\s*\S', re.MULTILINE)
# ALIGNED with `tests/run-tests.sh:170` (`grep -oE '# roadmap:[0-9a-f]{4}'`). It used to be
# `roadmap:\S+`, which is LOOSER than the harness's own rule -- a third opinion about which
# files are roadmap specs is exactly the drift this runner is supposed to make impossible.
# (Measured 2026-09-01: no file in the corpus carries a token the two regexes disagree on, so
# the alignment is a no-op today and a guard tomorrow.)
ROADMAP_RE = re.compile(r'^\s*#\s*roadmap:[0-9a-f]{4}\b', re.MULTILINE)
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


def assertion_sites(body, needle):
    """Lines of the test's BODY that contain `needle`, as [(lineno_within_body, text)].

    The unique-site check (see module docstring): a declared substring that matches 0 body
    lines names an assertion the file does not contain; one that matches 2+ leaves the runner
    unable to say WHICH fired, so a match proves nothing. Both are CONFIG ERRORs.
    """
    return [(n, ln.strip()) for n, ln in enumerate(body.splitlines(), 1) if needle in ln]


def parse_header(path):
    """-> (prose_declared: bool, cases: [dict], errors: [str])."""
    text = open(path, encoding="utf-8").read()
    head = header_block(text)
    body = text[len(head):]
    body_off = len(head.splitlines())
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
    base = os.path.basename(path)
    for c in cases:
        if not c["assertions"]:
            errors.append(f"{base}: case `{c['kind']}: {c['arg']}` declares NO "
                          f"`# fails-against-assertion:` -- an assertion-less negative case "
                          f"cannot be verified (id:a73c instance (c))")
        # UNIQUE SITE -- static, and the reason id:a73c instance (a) got reported green:
        # `(b) guard` matched the (a) line `…so (b) guard was never reached` by substring.
        for w in c["assertions"]:
            sites = assertion_sites(body, w)
            if len(sites) == 1:
                continue
            if not sites:
                errors.append(
                    f"{base}: `# fails-against-assertion: {w}` matches NO line of the file's "
                    f"body -- the declaration names an assertion this test does not contain "
                    f"(only the leading comment block is excluded from the search)")
            else:
                shown = "\n      ".join(f"line {body_off + n}: {t}" for n, t in sites[:5])
                errors.append(
                    f"{base}: `# fails-against-assertion: {w}` matches {len(sites)} lines of "
                    f"the file's body, so a hit cannot identify WHICH assertion fired -- that "
                    f"is exactly how id:a73c instance (a) was reported green. NARROW the "
                    f"declaration until it is unique; do not loosen the check.\n      {shown}")
        if c["kind"] == "rev":
            rev, paths = split_rev_arg(c["arg"])
            if not paths:
                errors.append(f"{base}: `fails-against-rev: {c['arg']}` names no "
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
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True,
                          errors="replace", **kw)


def git_bytes(root, *args):
    """Like git(), but WITHOUT `text=True`.

    `git show <rev>:<path>` on a binary blob raised UnicodeDecodeError inside
    subprocess.run's own newline translation -- an UNCAUGHT traceback that aborted the whole
    run, leaving every remaining declaration unverified. Blobs are bytes; read them as bytes
    and write them back byte-for-byte.
    """
    return subprocess.run(["git", "-C", root, *args], capture_output=True)


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


def rev_path_type(root, rev, rel):
    """-> "blob" / "tree" / "commit" (submodule) / None (absent at rev)."""
    r = git(root, "cat-file", "-t", f"{rev}:{rel}")
    return r.stdout.strip() if r.returncode == 0 else None


def apply_rev(root, dest, rev, paths):
    """Overwrite `paths` in dest with their content at `rev`. A path ABSENT at rev is
    DELETED in dest --"the script did not exist yet" is a legitimate negative case.

    Only BLOBS are accepted; a directory/submodule path is refused as a CONFIG ERROR before
    a run starts (see `validate_rev_cases`), because `git show <rev>:<dir>` returns a tree
    LISTING and writing it over the directory raised IsADirectoryError -- an uncaught
    traceback that killed the entire run over one typo.
    """
    notes = []
    for rel in paths:
        blob = git_bytes(root, "show", f"{rev}:{rel}")
        dst = os.path.join(dest, rel)
        if blob.returncode != 0:
            if os.path.isdir(dst) and not os.path.islink(dst):
                shutil.rmtree(dst)
            elif os.path.exists(dst) or os.path.islink(dst):
                os.remove(dst)
            notes.append(f"{rel}: absent at {rev} (removed from scratch)")
            continue
        mode = "100644"
        lt = git(root, "ls-tree", rev, "--", rel)
        if lt.returncode == 0 and lt.stdout.strip():
            mode = lt.stdout.split()[0]
        os.makedirs(os.path.dirname(dst) or dest, exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(blob.stdout)
        os.chmod(dst, 0o755 if mode == "100755" else 0o644)
        notes.append(f"{rel}: @{rev}")
    return notes


def validate_rev_cases(root, plan):
    """Static pre-flight over every planned `-rev:` case -> [config error strings].

    Runs BEFORE anything executes (and under `--list`), so one bad path is a named config
    error rather than a traceback 40 minutes into a 158-declaration back-fill.
    """
    errors = []
    if git(root, "rev-parse", "--git-dir").returncode != 0:
        return errors
    for rel, cases in plan:
        base = os.path.basename(rel)
        for c in cases:
            if c["kind"] != "rev":
                continue
            if git(root, "rev-parse", "--verify", "--quiet", c["rev"] + "^{commit}").returncode:
                # NOT an error here. A revision missing from THIS object database is handled
                # per-case at run time (exit 1, one file), and `--list` must stay usable in a
                # scratch/exported copy whose history is a single synthetic commit -- which is
                # exactly the tree this runner's own spec runs its green-now check in.
                continue
            for p in c["paths"]:
                kind = rev_path_type(root, c["rev"], p)
                if kind in (None, "blob"):
                    continue  # absent-at-rev is a legitimate case; blob is the normal one
                errors.append(f"{base}: `fails-against-rev: {c['arg']}` -- path {p!r} is a "
                              f"{kind} at {c['rev']}, not a blob. Name the FILE(s) whose "
                              f"ancestor content the case needs; a directory cannot be "
                              f"materialised from `git show`.")
    return errors


@contextlib.contextmanager
def sandbox_tree(root):
    """Yield (sandbox, scratch) -- a private parent dir holding `tree/` and `tmp/` only.

    The extra level exists so the runner can CHECK containment afterwards: anything that
    appears in `sandbox` besides those two entries was written by something that escaped the
    scratch tree. It also gives the mutation a TMPDIR and a GIT_CEILING_DIRECTORIES that are
    inside the sandbox rather than in the real filesystem.
    """
    with tempfile.TemporaryDirectory(prefix="negcase-") as sandbox:
        scratch = os.path.join(sandbox, "tree")
        os.makedirs(scratch)
        os.makedirs(os.path.join(sandbox, "tmp"))
        materialise(root, scratch)
        yield sandbox, scratch


SANDBOX_ENTRIES = {"tree", "tmp"}


def contained_env(sandbox):
    env = dict(os.environ)
    env.pop("RUN_TESTS_NESTED", None)
    tmp = os.path.join(sandbox, "tmp")
    env["TMPDIR"] = env["TMP"] = env["TEMP"] = tmp
    # Stops `git rev-parse --show-toplevel` (and every other discovery walk) from climbing
    # ABOVE the sandbox into a real repository. Load-bearing for mutations specifically:
    # `init_scratch_repo` runs AFTER the mutation, so at mutation time the scratch is not a
    # git repo and discovery would otherwise walk upward.
    env["GIT_CEILING_DIRECTORIES"] = sandbox
    return env


def check_containment(sandbox, what):
    stray = sorted(set(os.listdir(sandbox)) - SANDBOX_ENTRIES)
    if not stray:
        return None
    return (f"{what} wrote OUTSIDE the scratch tree, into its sandbox: {stray}. A "
            f"`# fails-against-mutation:` command is an arbitrary `bash -c` and is NOT "
            f"sandboxed -- it must confine itself to relative paths under its cwd.")


def run_test(sandbox, scratch, rel_test, timeout):
    env = contained_env(sandbox)
    try:
        # stderr MERGED into stdout, not concatenated after it: the LAST-FAIL-line rule below
        # is meaningless unless the two streams stay in real order (accumulator tests write
        # their FAIL lines to stderr and their PASS lines to stdout).
        p = subprocess.run(["bash", rel_test], cwd=scratch, env=env, timeout=timeout,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, errors="replace")
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired as e:
        out = e.stdout or b""
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
    try:
        with sandbox_tree(root) as (sandbox, scratch):
            init_scratch_repo(root, scratch)
            rc, out = run_test(sandbox, scratch, rel, timeout)
    except Exception as e:  # noqa: BLE001 -- one bad file must never abort the whole run
        return [f"{base}: RUNNER ERROR during GREEN-NOW: {type(e).__name__}: {e}"]
    if rc != 0:
        fl = fail_lines(out) or ["(no FAIL: line -- aborted)"]
        problems.append(f"{base}: GREEN-NOW failed (rc={rc}) against the CURRENT tree; "
                        f"its redness elsewhere proves nothing. First FAIL: {fl[0]}")
        return problems
    log(f"  green-now  OK   {base}")

    for c in cases:
        label = f"{c['kind']}: {c['arg']}"
        try:
            with sandbox_tree(root) as (sandbox, scratch):
                if c["kind"] == "rev":
                    r = git(root, "rev-parse", "--verify", "--quiet", c["rev"] + "^{commit}")
                    if r.returncode != 0:
                        problems.append(f"{base}: revision {c['rev']!r} is not in the local "
                                        f"object database -- cannot verify `{label}`")
                        continue
                    notes = apply_rev(root, scratch, c["rev"], c["paths"])
                    log(f"    applied: {'; '.join(notes)}")
                else:
                    m = subprocess.run(["bash", "-c", c["arg"]], cwd=scratch,
                                       env=contained_env(sandbox),
                                       capture_output=True, text=True, errors="replace")
                    escaped = check_containment(sandbox, f"the mutation of {base}")
                    if escaped:
                        problems.append(f"{base}: CONTAINMENT -- {escaped}\n      command: "
                                        f"{c['arg']}")
                        continue
                    if m.returncode != 0:
                        problems.append(f"{base}: mutation command failed (rc={m.returncode}): "
                                        f"{c['arg']}\n      {m.stderr.strip()[:400]}")
                        continue
                # Commit AFTER the case is applied, so the scratch repo is CLEAN and its HEAD
                # is the world the test is being run against.
                init_scratch_repo(root, scratch)
                rc, out = run_test(sandbox, scratch, rel, timeout)
        except Exception as e:  # noqa: BLE001 -- one bad case must not abort the run
            problems.append(f"{base}: RUNNER ERROR on `{label}`: {type(e).__name__}: {e}")
            continue

        fl = fail_lines(out)
        if rc == 0:
            problems.append(f"{base}: VACUOUS -- the test PASSES against its declared negative "
                            f"case `{label}`. It demonstrates no killing power.")
            continue
        wanted = c["assertions"]
        # THE LAST FAIL LINE, not any of them. 36 of the 161 held files use a NON-EXITING
        # accumulator and emit several FAIL lines per run; accepting a hit on ANY of them let
        # a soft note satisfy the declaration while a different assertion was the real killer
        # -- an "any-of" guarantee, i.e. barely better than exit status. See MULTI in the
        # module docstring.
        hit = [w for w in wanted if fl and w in fl[-1]]
        if hit:
            log(f"  red-there  OK   {base}  [{label}]  -> {fl[-1][:150]}")
            if len(fl) > 1:
                log(f"    note: {len(fl)} FAIL lines fired; matched the LAST")
            continue
        if not fl:
            tail = "\n      ".join(out.strip().splitlines()[-6:]) or "(no output)"
            problems.append(f"{base}: WRONG REASON -- died (rc={rc}) against `{label}` with NO "
                            f"`FAIL:` line at all, so no assertion fired. Expected one naming "
                            f"{wanted!r}. Tail:\n      {tail}")
        elif len(fl) == 1:
            problems.append(f"{base}: WRONG REASON -- red against `{label}`, but at the WRONG "
                            f"assertion. Expected a FAIL line containing one of {wanted!r}; "
                            f"got:\n      " + fl[0])
        else:
            listed = "\n      ".join(f"[{i}] {ln}" for i, ln in enumerate(fl, 1))
            problems.append(
                f"{base}: WRONG REASON -- red against `{label}` with {len(fl)} FAIL lines "
                f"(a non-exiting accumulator). The declaration must match the LAST one, "
                f"[{len(fl)}]; expected one of {wanted!r}. ALL fired lines:\n      {listed}\n"
                f"      Re-declare against the last-firing assertion, split the case, or add "
                f"an exemption with a written reason.")
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
    roadmap_spec, roadmap_shadowed, roadmap_below_header = [], [], []
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
        text = open(path, encoding="utf-8", errors="replace").read()
        if ROADMAP_RE.search(text):
            # roadmap-spec test: its redness IS the spec (same carve-out as the lint). REPORTED,
            # never silently dropped -- a file whose `# roadmap:` token sits BELOW its header
            # block (in a fixture heredoc, typically) has a header-scoped declaration and a
            # whole-file roadmap match at the same time, and used to land in NO bucket at all.
            roadmap_spec.append(base)
            head = header_block(text)
            if PROSE_RE.search(head) or any(CASE_RE.match(ln) for ln in head.splitlines()):
                # The SPECIFIC vanishing shape: a real `# fails-against*` declaration in the
                # file's own header, cancelled by a `# roadmap:` token found anywhere in the
                # file -- typically a fixture/prose reference, not the file's own marker.
                roadmap_shadowed.append(base)
            elif not ROADMAP_RE.search(head):
                # The token is NOT in this file's own header block, so it is very likely a
                # fixture heredoc or a prose reference rather than the file's own marker. The
                # carve-out still applies (whole-file detection is deliberate, and narrowing it
                # would have to change run-tests.sh, the lint and this runner TOGETHER), but it
                # is NAMED so it can never vanish unnoticed. Measured 2026-09-01:
                # test_orphan_scan_shipped.sh and test_orphan_scan_language_dispatch_15f3.sh.
                roadmap_below_header.append(base)
            continue
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

    config_errors.extend(validate_rev_cases(root, plan))

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
          f"({EXEMPTIONS}) · {len(roadmap_spec)} roadmap-spec (skipped: redness IS the spec).")
    if unverified and not a.quiet:
        print("  unverified: " + ", ".join(unverified))
    if roadmap_spec and not a.quiet:
        # Named, not just counted. Roadmap detection is WHOLE-FILE while the `fails-against-*`
        # directives are header-scoped, so this bucket is where a file with a perfectly good
        # declaration can hide behind a `# roadmap:` token in a fixture heredoc.
        print(f"  roadmap-spec (not verified by this runner): {len(roadmap_spec)} file(s)"
              + (": " + ", ".join(roadmap_spec) if len(roadmap_spec) <= 12 else ""))
    if roadmap_below_header:
        print(f"  roadmap token BELOW the header block -- {len(roadmap_below_header)} file(s) "
              f"are carved out by a `# roadmap:` token that is not in their own leading "
              f"comment block (fixture heredoc or prose reference, most likely), so they are "
              f"NOT verified here and `tests/run-tests.sh` may also read them as the RED SPEC "
              f"of an item they have nothing to do with: " + ", ".join(roadmap_below_header))
    if roadmap_shadowed:
        # Always printed, --quiet included: this is the silent-skip class itself.
        print(f"  ROADMAP-SHADOWED DECLARATION -- {len(roadmap_shadowed)} file(s) carry a "
              f"`# fails-against*` declaration in their own header AND a `# roadmap:` token "
              f"elsewhere in the file, so the roadmap carve-out cancels the declaration and "
              f"they are NOT verified: " + ", ".join(roadmap_shadowed))
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
