#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE: TODO id:a73c lives in TODO.md only and has NO ROADMAP
# twin (`grep -n 'id:a73c' ROADMAP.md` finds nothing), so there is no checkbox for the
# harness's EXPECTED-RED rule to consult. Per CLAUDE.md §Testing a headerless file's
# failures ALWAYS count -- which is what this file wants.
#
# fails-against: tests/verify-negative-cases.py absent, or built so that it checks only the
#   EXIT STATUS of the declared negative case (the mechanism-(1)-equivalent behaviour) rather
#   than WHICH assertion fired. That is the exact blind spot id:a73c exists to close, and it
#   is the mutation declared below.
#
# fails-against-mutation: bash tests/mutations/a73c-exit-status-only.sh
# fails-against-assertion: (c) a test that dies at an EARLIER assertion
#
# REACHABILITY OF THE NEGATIVE CONTROL -- which assertions discriminate under that mutation.
# (An unreached fixture in a file that goes red LOOKS like a passing negative control and is
# not one, so this is on the record rather than assumed.) Under
# `tests/mutations/a73c-exit-status-only.sh` -- the runner reverted to "any non-zero exit is
# proof" -- assertions (a), (b), (d), (e), (f), (g), (h), (i), (j) all still PASS: the mutation
# touches only the WHICH-assertion comparison, and vacuity (rc==0), green-now, config errors
# and coverage accounting are decided elsewhere. So nothing aborts before (c), and (c) -- the
# wrong-reason case -- is the SOLE killer, which is exactly the axis this file exists to pin.
# Measured 2026-09-01; the verbatim output is in the commit message.
#
# WHAT IS BEING SPECCED -- the runner half of TODO id:a73c.
# THE RULE: it is not enough that a defect-fix test FAILS against its declared
# `# fails-against:` revision/mutation -- **the assertion that fails must be the one the file
# claims to pin.** A file that dies at an earlier assertion, is killed by a fixture-sanity
# probe, or whose fixture never reaches the guarded path is red for the WRONG REASON and is
# exactly as vacuous as one that passes (three live 2026-09-01 instances, TODO id:a73c).
#
# THIS FILE'S OWN NEGATIVE CONTROL MUST DISCRIMINATE. An unreached fixture in a file ABOUT
# unreached fixtures would be self-refuting, so the corpus below is built so that a
# mechanism-(1)-shaped runner (exit-status only) PASSES fixtures (a), (b) and (d) and FAILS
# only (c) -- and (c) additionally plants the expected substring in a NON-`FAIL:` line, so a
# runner that greps the whole output instead of the FAIL lines is caught too.
#
# Hermetic: one throwaway git fixture repo under mktemp -d; the real repo is never mutated,
# no ~/.claude, no network (revisions come from the fixture's own object database).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/lib/hermetic-git-env.sh"
RUNNER="$ROOT/tests/verify-negative-cases.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$RUNNER" ]] || fail "verify-negative-cases.py not found at $RUNNER (id:a73c not built)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/fixture"
mkdir -p "$repo/src" "$repo/tests"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
export LC_ALL=C

# --- the fixture repo: v1 is the DEFECT, v2 (working tree) is the FIX ---------------------
# v1 emits the OLD format and leaves the path UNGUARDED. Note the format change: it is what
# makes fixture (c) die early at the ancestor, reproducing id:a73c instance (a).
cat > "$repo/src/tool.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  format) echo "old-format" ;;
  guard)  echo "unguarded" ;;
esac
EOF
chmod +x "$repo/src/tool.sh"

git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" commit -qm "v1: the defect"
V1="$(git -C "$repo" rev-parse HEAD)"

cat > "$repo/src/tool.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  format) echo "new-format" ;;
  guard)  echo "guarded" ;;
esac
EOF
chmod +x "$repo/src/tool.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "v2: the fix"

mk() {  # mk <name> <<<body
  cat > "$repo/tests/$1"
  chmod +x "$repo/tests/$1"
}

# (a) GENUINELY DISCRIMINATING: red at the ancestor, at exactly the declared assertion.
mk test_good.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF

# (b) VACUOUS: asserts only what is true at BOTH revisions, so it is green against its own
#     declared negative case. Exit-status-only checking catches this one too.
mk test_vacuous.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ -x "\$R/src/tool.sh" ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF

# (c) THE ID:A73C CASE -- red at the ancestor for the WRONG REASON. Assertion (a) checks the
#     FORMAT, which the ancestor rejects outright, so the file dies there and assertion (c),
#     the one it exists to pin, is UNREACHED. An exit-status-only runner calls this fine.
#     The `echo` before (a) plants the expected substring in a NON-`FAIL:` line, so a runner
#     that greps whole output rather than FAIL lines is caught here as well.
mk test_wrong_reason.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (c) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
echo "about to check: (c) the path must be guarded"
[[ "\$(bash "\$R/src/tool.sh" format)" == new-format ]] || fail "(a) format must be new-format"
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(c) the path must be guarded"
echo "PASS: (a) (c)"
EOF

# (d) MUTATION form (no ancestor involved).
mk test_mutation.sh <<EOF
#!/usr/bin/env bash
# fails-against: a tool.sh with the guard stripped
# fails-against-mutation: sed -i 's/guarded/unguarded/' src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF

# (e) PROSE-ONLY: satisfies mechanism (1), carries no machine-readable case -> UNVERIFIED.
mk test_prose_only.sh <<'EOF'
#!/usr/bin/env bash
# fails-against: some revision, described only in prose
set -euo pipefail
echo "PASS: nothing"
EOF

# (f) ROADMAP-SPEC: exempt from the whole discipline, its redness IS the spec.
#     The marker is ASSEMBLED rather than written literally: `tests/run-tests.sh` greps the
#     WHOLE file for `# roadmap:[0-9a-f]{4}`, so a literal one in a fixture heredoc would
#     make the harness read THIS file as the red spec of a roadmap item it has nothing to do
#     with, and hand it an expected-red escape it must not have.
printf '#!/usr/bin/env bash\n# %s:9f9f\nset -euo pipefail\nexit 1\n' roadmap \
  > "$repo/tests/test_roadmap_spec.sh"

# (k) HEADER SCOPING: a file whose own header is prose-only, but which BUILDS a fixture whose
#     heredoc carries machine-readable directives. Those belong to the fixture, not to the
#     file -- reading them as the file's own is how this runner briefly lost its own spec.
mk test_heredoc_decoy.sh <<EOF
#!/usr/bin/env bash
# fails-against: prose only -- the directives below belong to the FIXTURE it writes
set -euo pipefail
cat > /dev/null <<'INNER'
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (z) not this file's assertion
INNER
echo "PASS: nothing"
EOF

git -C "$repo" add -A
git -C "$repo" commit -qm "fixture tests"

run() { python3 "$RUNNER" --root "$repo" "$@" 2>&1; }

# --- (a) a genuinely discriminating negative case VERIFIES --------------------------------
rc=0; out_a="$(run --quiet tests/test_good.sh)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_a"; fail "(a) a test that is red at exactly its declared assertion must VERIFY (exit 0), got rc=$rc"; }
grep -q 'TOTAL: 0 negative case' <<<"$out_a" \
  || { sed 's/^/    /' <<<"$out_a"; fail "(a) expected a clean TOTAL for the discriminating fixture"; }
pass "(a) a discriminating negative case verifies (green-now + red-at-the-declared-assertion)"

# --- (b) a VACUOUS fixture (green against its own negative case) is REJECTED --------------
rc=0; out_b="$(run --quiet tests/test_vacuous.sh)" || rc=$?
[[ $rc -eq 1 ]] || { sed 's/^/    /' <<<"$out_b"; fail "(b) a test that PASSES against its declared negative case must be rejected (exit 1), got rc=$rc"; }
grep -q 'VACUOUS' <<<"$out_b" \
  || { sed 's/^/    /' <<<"$out_b"; fail "(b) the vacuous fixture must be named VACUOUS in the report"; }
pass "(b) a fixture that is green against its own declared negative case is rejected"

# --- (c) THE RULE: red at an EARLIER assertion is red for the WRONG REASON -----------------
#     This is the assertion that mechanism (1) -- and any exit-status-only runner -- cannot
#     make. It is also the FAIL-line-scoping check: the fixture echoes the expected substring
#     on a non-FAIL line.
rc=0; out_c="$(run --quiet tests/test_wrong_reason.sh)" || rc=$?
[[ $rc -eq 1 ]] || { sed 's/^/    /' <<<"$out_c"; fail "(c) a test that dies at an EARLIER assertion than the one it declares must be rejected (exit 1), got rc=$rc"; }
grep -q 'WRONG REASON' <<<"$out_c" \
  || { sed 's/^/    /' <<<"$out_c"; fail "(c) a test that dies at an EARLIER assertion must be reported WRONG REASON, not accepted on exit status"; }
grep -q 'FAIL: (a) format must be new-format' <<<"$out_c" \
  || { sed 's/^/    /' <<<"$out_c"; fail "(c) the report must quote the assertion that ACTUALLY fired, so the author can see it"; }
pass "(c) a test that dies at an EARLIER assertion is rejected, and the actual FAIL line is quoted"

# --- (d) the MUTATION form works as well as the rev form ----------------------------------
rc=0; out_d="$(run --quiet tests/test_mutation.sh)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_d"; fail "(d) the mutation form must verify a discriminating case, got rc=$rc"; }
pass "(d) the mutation form verifies a discriminating case"

# --- (e) GREEN-NOW: a test that is red against the CURRENT tree proves nothing -------------
mk test_always_red.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
fail() { echo "FAIL: \$*"; exit 1; }
fail "(a) the path must be guarded"
EOF
rc=0; out_e="$(run --quiet tests/test_always_red.sh)" || rc=$?
[[ $rc -eq 1 ]] || { sed 's/^/    /' <<<"$out_e"; fail "(e) a test that is ALSO red against the current tree must be rejected, got rc=$rc"; }
grep -q 'GREEN-NOW' <<<"$out_e" \
  || { sed 's/^/    /' <<<"$out_e"; fail "(e) an always-red test must be reported as a GREEN-NOW failure"; }
rm -- "$repo/tests/test_always_red.sh"
pass "(e) a test that is red against the current tree too is rejected (its redness proves nothing)"

# --- (f) an ASSERTION-LESS case is a loud CONFIG ERROR (id:a73c instance (c)) -------------
mk test_no_assertion.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
set -euo pipefail
echo "PASS: nothing asserted"
EOF
rc=0; out_f="$(run --quiet tests/test_no_assertion.sh)" || rc=$?
[[ $rc -eq 2 ]] || { sed 's/^/    /' <<<"$out_f"; fail "(f) a case with no '# fails-against-assertion:' must exit 2 (config error), got rc=$rc"; }
grep -q 'CONFIG ERROR' <<<"$out_f" \
  || { sed 's/^/    /' <<<"$out_f"; fail "(f) an assertion-less negative case must be a loud CONFIG ERROR"; }
rm -- "$repo/tests/test_no_assertion.sh"
pass "(f) an assertion-less negative case is refused loudly, never silently counted"

# --- (g) coverage accounting: prose-only = UNVERIFIED, roadmap-spec = not held -------------
out_g="$(run --list)"
grep -q 'test_heredoc_decoy.sh' <<<"$out_g" \
  || { sed 's/^/    /' <<<"$out_g"; fail "(g) directives inside a FIXTURE heredoc must not be read as the file's own header -- the decoy must stay UNVERIFIED"; }
grep -q 'test_prose_only.sh' <<<"$out_g" \
  || { sed 's/^/    /' <<<"$out_g"; fail "(g) a prose-only '# fails-against:' file must be reported UNVERIFIED, not silently ignored"; }
grep -q 'test_roadmap_spec.sh' <<<"$out_g" \
  && { sed 's/^/    /' <<<"$out_g"; fail "(g) a '# roadmap:' spec test must not be held by the runner"; }
rc=0; run --list --strict-coverage >/dev/null || rc=$?
[[ $rc -eq 1 ]] || fail "(g) --strict-coverage must exit 1 while an unverified defect-fix test remains, got rc=$rc"
pass "(g) coverage is reported (prose-only = UNVERIFIED), roadmap specs are carved out, --strict-coverage bites"

# --- (h) exemptions come from ONE reviewable allowlist, with a MANDATORY reason ------------
printf '# fixture allowlist\ntest_prose_only.sh  -- harness-shape fixture, no defect to pin\ntest_heredoc_decoy.sh  -- harness-shape fixture, no defect to pin\n' \
  > "$repo/tests/negative-case-exemptions.txt"
out_h="$(run --list)"
grep -q '2 exempt' <<<"$out_h" \
  || { sed 's/^/    /' <<<"$out_h"; fail "(h) an allowlisted file must be counted EXEMPT"; }
rc=0; run --list --strict-coverage >/dev/null || rc=$?
[[ $rc -eq 0 ]] || { fail "(h) with the only unverified file exempted, --strict-coverage must pass, got rc=$rc"; }
printf 'test_prose_only.sh\n' > "$repo/tests/negative-case-exemptions.txt"
rc=0; out_h2="$(run --list)" || rc=$?
[[ $rc -eq 2 ]] || { sed 's/^/    /' <<<"$out_h2"; fail "(h) an exemption with NO reason must be a config error (exit 2), got rc=$rc"; }
rm -- "$repo/tests/negative-case-exemptions.txt"
pass "(h) exemptions live in ONE allowlist file and each needs a written reason"

# --- (i) the real repo's own allowlist parses, and the real corpus is at least LISTABLE ----
rc=0; out_i="$(python3 "$RUNNER" --root "$ROOT" --list 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_i"; fail "(i) --list over the real repo must succeed (allowlist + headers parse), got rc=$rc"; }
grep -q '^COVERAGE:' <<<"$out_i" \
  || { sed 's/^/    /' <<<"$out_i"; fail "(i) --list must print a COVERAGE line for the real repo"; }
pass "(i) the real repo's allowlist and negative-case headers parse; coverage is reported"

# --- (j) the real repo is not mutated by a run --------------------------------------------
before="$(git -C "$ROOT" status --porcelain)"
python3 "$RUNNER" --root "$repo" --quiet tests/test_good.sh >/dev/null
[[ "$(git -C "$ROOT" status --porcelain)" == "$before" ]] \
  || fail "(j) running the verifier must not touch the working tree of the repo under test"
pass "(j) verification happens in scratch copies; the real tree is untouched"

echo "ALL PASS: negative-case runner (id:a73c)"
