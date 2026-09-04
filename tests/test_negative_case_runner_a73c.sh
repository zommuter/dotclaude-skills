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
# fails-against-assertion: (c) a test that dies at an EARLIER assertion than the one it declares
#
# REACHABILITY OF THE NEGATIVE CONTROL -- which assertions discriminate under that mutation.
# (An unreached fixture in a file that goes red LOOKS like a passing negative control and is
# not one, so this is on the record rather than assumed.) Under
# `tests/mutations/a73c-exit-status-only.sh` -- the runner reverted to "any non-zero exit is
# proof" -- assertions (a), (b), (d), (e), (f), (g), (h), (i), (j) all still PASS: the mutation
# touches only the WHICH-assertion comparison, and vacuity (rc==0), green-now, config errors
# and coverage accounting are decided elsewhere. So nothing aborts before (c), and (c) -- the
# wrong-reason case -- is the SOLE killer, which is exactly the axis this file exists to pin.
# Case (n2), added 2026-09-04 with id:7c82, is likewise not a discriminator for the mutation
# above: it asserts WHICH population a file lands in and that it is executed at all, and the
# mutation touches only the which-assertion comparison. (c) remains the sole killer.
# Cases (l)/(l2)/(m)/(m2)/(n)/(o)/(p)/(q), added 2026-09-01 for the six review findings, sit
# AFTER (c) and are therefore UNREACHED under this mutation. That is on the record rather than
# glossed: (m)/(m2) would also discriminate (the mutation defeats the last-FAIL-line rule
# outright), while (l)/(l2)/(o) are STATIC config-error checks the mutation does not touch and
# would still pass. Each of the eight has its own negative control, measured by running this
# file against the pre-fix runner (da37bec8): all eight went red there and green here.
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

# A BINARY tracked blob: `git show <rev>:<path>` on this used to raise UnicodeDecodeError
# inside subprocess's newline translation and abort the entire run (case (p) below).
printf '\x00\x01\xff\xfe binary payload\n' > "$repo/bin.dat"

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
#     The `printf` before (a) plants the expected substring in a NON-`FAIL:` OUTPUT line, so a
#     runner that greps whole output rather than FAIL lines is caught here as well. It is
#     ASSEMBLED from a format string rather than written literally, so that the SOURCE still
#     contains exactly one site for the declared substring -- otherwise the unique-site check
#     (case (l)) would reject this fixture before the FAIL-line-scoping axis is ever reached,
#     and the decoy axis would go untested.
mk test_wrong_reason.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (c) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
printf 'about to check: %s the path must be guarded\n' '(c)'
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

# The fixture repo needs a ROADMAP.md, because since id:7c82 the runner's roadmap carve-out
# keys on the item's CHECKBOX (`tests/run-tests.sh`'s own `item_open()`), not on the token's
# presence. Without one, EVERY fixture roadmap token resolves to "no open item" and the
# carve-out is spent before the carved-out path is ever exercised -- cases (f)/(g)/(n) would
# then be testing the EXPIRED branch while claiming to test the carve-out. Both fixture
# tokens are declared OPEN here; case (n2) ticks one, deliberately, to exercise expiry.
{
  printf -- '- [ ] [ROUTINE] **fixture roadmap-spec item.** <!-- id:9f9f -->\n'
  printf -- '- [ ] [ROUTINE] **fixture shadowed-declaration item.** <!-- id:9f9e -->\n'
} > "$repo/ROADMAP.md"

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
grep -q 'unverified:.*test_roadmap_spec.sh' <<<"$out_g" \
  && { sed 's/^/    /' <<<"$out_g"; fail "(g) a '# roadmap:' spec test must not be HELD by the runner (it must not appear in the unverified population)"; }
# ... but it must still be COUNTED and NAMED. Silently dropping the roadmap population is how
# a file with a valid declaration plus a stray roadmap token vanished from every bucket
# (finding 3 / case (n)); the carve-out is legitimate, the silence was not.
grep -qE 'COVERAGE:.*1 roadmap-spec' <<<"$out_g" \
  || { sed 's/^/    /' <<<"$out_g"; fail "(g) the roadmap-spec carve-out must be COUNTED in the coverage line, not silently dropped"; }
grep -q 'roadmap-spec (not verified by this runner): 1 file(s): test_roadmap_spec.sh' <<<"$out_g" \
  || { sed 's/^/    /' <<<"$out_g"; fail "(g) a carved-out roadmap-spec test must be NAMED, so nothing can vanish from every bucket"; }
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

# ==========================================================================================
# The six review findings of 2026-09-01. (a)-(j) above covered the `PASS:`-decoy axis and the
# coverage accounting; they did NOT cover substring collision or multi-FAIL tests, which is
# precisely why both got through. Each case below was REPRODUCED against the unfixed runner
# first (verbatim false pass), then closed.
# ==========================================================================================

# --- (l) BLOCKING 1: substring collision ACROSS assertions is a CONFIG ERROR ---------------
#     The declared `(b) guard` is a substring of assertion (a)'s own message, which NAMES the
#     later assertion ("so (b) guard was never reached"). Against the ancestor the file dies
#     at (a) and the unfixed runner reported OK -- id:a73c instance (a) verbatim, green.
#     This is not a contrived spelling: CLAUDE.md §Testing tells back-fillers to author the
#     ancestor case in the ancestor's OWN spelling and record per-ancestor reachability, so
#     messages where an early assertion names a later one are what this corpus will contain.
#     The check is STATIC -- it needs no run at all, so it also fires under --list.
mk test_collision.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (b) guard
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" format)" == new-format ]] || fail "(a) old format rejected outright, so (b) guard was never reached"
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(b) guard must be present"
echo "PASS: all"
EOF
rc=0; out_l="$(run --quiet tests/test_collision.sh)" || rc=$?
[[ $rc -eq 2 ]] || { sed 's/^/    /' <<<"$out_l"; fail "(l) a declared assertion that matches TWO assertion sites must be a CONFIG ERROR (exit 2) -- matching it proves nothing about WHICH one fired; got rc=$rc"; }
grep -q 'matches 2 lines' <<<"$out_l" \
  || { sed 's/^/    /' <<<"$out_l"; fail "(l) the config error must say how many assertion sites the declaration matched"; }
grep -q 'old format rejected outright' <<<"$out_l" \
  || { sed 's/^/    /' <<<"$out_l"; fail "(l) the config error must QUOTE the colliding lines so the author can narrow the declaration"; }
rc=0; run --list tests/test_collision.sh >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "(l) the unique-site check is static and must fire under --list too, got rc=$rc"
rm -- "$repo/tests/test_collision.sh"
pass "(l) a declared assertion matching 2+ sites in the file's body is refused as a CONFIG ERROR"

# --- (l2) ... and one matching ZERO sites is refused as well -------------------------------
mk test_nosite.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: (z) an assertion this file does not contain
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF
rc=0; out_l2="$(run --quiet tests/test_nosite.sh)" || rc=$?
[[ $rc -eq 2 ]] || { sed 's/^/    /' <<<"$out_l2"; fail "(l2) a declared assertion matching NO line of the file must be a CONFIG ERROR (exit 2), got rc=$rc"; }
grep -q 'matches NO line' <<<"$out_l2" \
  || { sed 's/^/    /' <<<"$out_l2"; fail "(l2) the config error must say the declaration matched no assertion site"; }
rm -- "$repo/tests/test_nosite.sh"
pass "(l2) a declared assertion that names nothing in the file is refused as a CONFIG ERROR"

# --- (m) BLOCKING 2: a NON-EXITING accumulator emits several FAIL lines --------------------
#     `note() { echo "FAIL: $*" >&2; bad=1; }` + one `exit` at the end. 36 of the 161 files
#     this runner can hold are shaped like this, so the docstring's "a test exits at its FIRST
#     failing assertion" was false. Accepting a hit on ANY fired FAIL line let a soft note
#     satisfy the declaration while a different assertion was the real killer.
acc_body() {  # <declared assertion substring>
  cat <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src/tool.sh
# fails-against-assertion: $1
set -uo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
bad=0
note() { echo "FAIL: \$*" >&2; bad=1; }
[[ "\$(bash "\$R/src/tool.sh" format)" == new-format ]] || note "(a) incidental format note"
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || note "(b) THE REAL KILLER, guard missing"
exit \$bad
EOF
}
acc_body '(a) incidental format note' | mk test_accum_wrong.sh
rc=0; out_m="$(run --quiet tests/test_accum_wrong.sh)" || rc=$?
[[ $rc -eq 1 ]] || { sed 's/^/    /' <<<"$out_m"; fail "(m) with 2 FAIL lines fired, a declaration naming a NON-LAST one must be rejected -- accepting any-of degrades the guarantee to exit status; got rc=$rc"; }
grep -q 'WRONG REASON' <<<"$out_m" \
  || { sed 's/^/    /' <<<"$out_m"; fail "(m) a non-last accumulator note must be reported WRONG REASON"; }
grep -q '2 FAIL lines' <<<"$out_m" \
  || { sed 's/^/    /' <<<"$out_m"; fail "(m) the report must say how many FAIL lines fired"; }
grep -q 'incidental format note' <<<"$out_m" \
  || { sed 's/^/    /' <<<"$out_m"; fail "(m) ALL fired FAIL lines must be reported, not just the last"; }
grep -q 'THE REAL KILLER' <<<"$out_m" \
  || { sed 's/^/    /' <<<"$out_m"; fail "(m) the report must show the LAST fired FAIL line, which is the one the declaration has to match"; }
rm -- "$repo/tests/test_accum_wrong.sh"
pass "(m) with several FAIL lines, a declaration matching a non-last one is rejected and all lines are reported"

# --- (m2) ... and the SAME accumulator declaring the LAST line verifies --------------------
#     The negative control for (m): the rule rejects the wrong declaration, not the shape.
acc_body '(b) THE REAL KILLER, guard missing' | mk test_accum_right.sh
rc=0; out_m2="$(run --quiet tests/test_accum_right.sh)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_m2"; fail "(m2) an accumulator declaring its LAST fired FAIL line must verify, got rc=$rc"; }
rm -- "$repo/tests/test_accum_right.sh"
pass "(m2) the same accumulator, declaring its LAST fired assertion, verifies"

# --- (o) ADVISABLE 4: a declared path that is a DIRECTORY at that rev ----------------------
#     `git show <rev>:<dir>` returns a TREE LISTING; writing it over the directory raised an
#     uncaught IsADirectoryError that aborted the WHOLE run. Across 158 declarations one typo
#     silently left every remaining file unverified.
mk test_dirpath.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- src
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF
rc=0; out_o="$(run --quiet tests/test_dirpath.sh)" || rc=$?
[[ $rc -eq 2 ]] || { sed 's/^/    /' <<<"$out_o"; fail "(o) a fails-against-rev path that is a DIRECTORY at that rev must be a CONFIG ERROR (exit 2), got rc=$rc"; }
grep -q 'not a blob' <<<"$out_o" \
  || { sed 's/^/    /' <<<"$out_o"; fail "(o) the config error must say the declared path is not a blob at that revision"; }
grep -q 'Traceback' <<<"$out_o" \
  && { sed 's/^/    /' <<<"$out_o"; fail "(o) a bad declared path must never surface as a Python traceback -- one typo would abort the whole back-fill"; }
rm -- "$repo/tests/test_dirpath.sh"
pass "(o) a directory named as a fails-against-rev path is a named config error, not a traceback"

# --- (p) ADVISABLE 4b: a declared path that is BINARY at that rev --------------------------
#     Blobs are bytes. `text=True` on `git show` raised UnicodeDecodeError, same whole-run
#     abort. A binary path is LEGITIMATE and must simply work.
mk test_binpath.sh <<EOF
#!/usr/bin/env bash
# fails-against: $V1
# fails-against-rev: $V1 -- bin.dat src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF
rc=0; out_p="$(run --quiet tests/test_binpath.sh)" || rc=$?
grep -q 'Traceback' <<<"$out_p" \
  && { sed 's/^/    /' <<<"$out_p"; fail "(p) a BINARY path at the declared rev must not raise UnicodeDecodeError -- blobs are bytes"; }
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_p"; fail "(p) a case naming a binary path alongside a source path must still verify, got rc=$rc"; }
rm -- "$repo/tests/test_binpath.sh"
pass "(p) a binary path in a fails-against-rev case is materialised byte-for-byte, not decoded"

# --- (q) ADVISABLE 6: a mutation is CONTAINED, and its escape is reported ------------------
#     The mutation is an arbitrary `bash -c`. Two things are now true and checked here: its
#     TMPDIR and git-discovery ceiling are inside a private sandbox (so `git rev-parse
#     --show-toplevel` cannot walk UP out of the not-yet-a-repo scratch into a real one), and
#     a write that leaves the scratch tree is REPORTED rather than silently accepted.
mk test_contained.sh <<EOF
#!/usr/bin/env bash
# fails-against: a tool.sh with the guard stripped, run under containment
# fails-against-mutation: [[ "\$TMPDIR" == *negcase-* ]] || { echo "TMPDIR not sandboxed: \$TMPDIR" >&2; exit 9; }; [[ -n "\${GIT_CEILING_DIRECTORIES:-}" ]] || { echo "no git ceiling" >&2; exit 9; }; git rev-parse --show-toplevel >/dev/null 2>&1 && { echo "discovery escaped upward to a real repo" >&2; exit 9; }; sed -i 's/guarded/unguarded/' src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF
rc=0; out_q="$(run --quiet tests/test_contained.sh)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_q"; fail "(q) a mutation must run with a sandboxed TMPDIR and a git ceiling that stops discovery walking out of the scratch, got rc=$rc"; }
rm -- "$repo/tests/test_contained.sh"

mk test_escape.sh <<EOF
#!/usr/bin/env bash
# fails-against: a mutation that writes outside its scratch tree
# fails-against-mutation: printf 'stray\n' > ../STRAY; sed -i 's/guarded/unguarded/' src/tool.sh
# fails-against-assertion: (a) the path must be guarded
set -euo pipefail
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
fail() { echo "FAIL: \$*"; exit 1; }
[[ "\$(bash "\$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"
echo "PASS: (a)"
EOF
rc=0; out_q2="$(run --quiet tests/test_escape.sh)" || rc=$?
[[ $rc -eq 1 ]] || { sed 's/^/    /' <<<"$out_q2"; fail "(q) a mutation that writes OUTSIDE its scratch tree must be rejected, got rc=$rc"; }
grep -q 'CONTAINMENT' <<<"$out_q2" \
  || { sed 's/^/    /' <<<"$out_q2"; fail "(q) an escaping mutation must be reported as a CONTAINMENT violation, naming the stray entry"; }
rm -- "$repo/tests/test_escape.sh"
pass "(q) mutations run with a sandboxed TMPDIR + git ceiling, and an escape is reported loudly"

# --- (n) BLOCKING 3: a roadmap token BELOW the header block must never silently vanish -----
#     Roadmap detection is WHOLE-FILE (deliberately -- run-tests.sh and the lint both grep the
#     whole file, and a third opinion would be worse) while the `fails-against-*` directives
#     are header-block-scoped. A file with a valid declaration AND a roadmap token lower down
#     therefore landed in NO bucket at all: not verified, not unverified, not undeclared, not
#     exempt. It vanished. Two live files misfire this way today. Kept LAST because it adds a
#     permanent fixture to the roadmap-spec population.
#     The marker is ASSEMBLED, never written literally -- see fixture (f).
{ printf '#!/usr/bin/env bash\n'
  printf '# fails-against: %s\n' "$V1"
  printf '# fails-against-rev: %s -- src/tool.sh\n' "$V1"
  printf '# fails-against-assertion: (a) the path must be guarded\n'
  printf 'set -euo pipefail\n'
  printf 'R="$(cd "$(dirname "$0")/.." && pwd)"\n'
  printf 'fail() { echo "FAIL: $*"; exit 1; }\n'
  printf 'cat > /dev/null <<INNER\n# %s:9f9e\nINNER\n' roadmap
  printf '[[ "$(bash "$R/src/tool.sh" guard)" == guarded ]] || fail "(a) the path must be guarded"\n'
  printf 'echo "PASS: (a)"\n'
} | mk test_roadmap_shadowed.sh
out_n="$(run --list)"
grep -q 'test_roadmap_shadowed.sh' <<<"$out_n" \
  || { sed 's/^/    /' <<<"$out_n"; fail "(n) a file whose valid declaration is cancelled by a roadmap token lower down must be NAMED in the coverage report, not vanish from every bucket"; }
grep -q 'ROADMAP-SHADOWED' <<<"$out_n" \
  || { sed 's/^/    /' <<<"$out_n"; fail "(n) the shadowed-declaration population must be reported under its own loud heading"; }
grep -q 'roadmap-spec' <<<"$out_n" \
  || { sed 's/^/    /' <<<"$out_n"; fail "(n) the coverage line must carry a roadmap-spec count so the carve-out is visible"; }
out_nq="$(run --list --quiet)"
grep -q 'ROADMAP-SHADOWED' <<<"$out_nq" \
  || { sed 's/^/    /' <<<"$out_nq"; fail "(n) the shadowed-declaration report must survive --quiet: it IS the silent-skip class"; }
pass "(n) a declaration shadowed by a roadmap token lower down is reported, never silently skipped"

# --- (n2) the carve-out EXPIRES with the item's checkbox (id:7c82) -------------------------
#     Same file, same stray token, one difference: the item is now TICKED. Before id:7c82 the
#     carve-out keyed on the token's PRESENCE and so never expired -- `tests/run-tests.sh`
#     stopped granting EXPECTED-RED the moment the item closed, while this runner went on
#     cancelling that file's declaration forever, silently. Every CLOSED roadmap-spec test in
#     the repo was permanently unverifiable. The property case (n) pins is NOT dropped: it is
#     asserted above for the still-OPEN item, and the pair is the point -- shadowed while
#     open, EXECUTED once closed.
sed -i 's/^- \[ \] \(.*<!-- id:9f9e -->\)$/- [x] \1/' "$repo/ROADMAP.md"
grep -q '^- \[x\] .*id:9f9e' "$repo/ROADMAP.md" \
  || fail "(n2) fixture sanity: the ticked item was not written, so nothing below is tested"
out_n2="$(run --list)"
grep -q 'carve-out EXPIRED' <<<"$out_n2" \
  || { sed 's/^/    /' <<<"$out_n2"; fail "(n2) once the item is TICKED the carve-out must expire and be REPORTED under its own heading"; }
grep -q 'EXPIRED.*test_roadmap_shadowed.sh' <<<"$out_n2" \
  || { sed 's/^/    /' <<<"$out_n2"; fail "(n2) the file whose carve-out expired must be NAMED, not just counted"; }
if grep -q 'ROADMAP-SHADOWED' <<<"$out_n2"; then
  sed 's/^/    /' <<<"$out_n2"
  fail "(n2) a CLOSED item's declaration is not shadowed any more -- reporting it as shadowed is the pre-id:7c82 behaviour"
fi
rc=0; out_n2r="$(run --quiet tests/test_roadmap_shadowed.sh)" || rc=$?
[[ $rc -eq 0 ]] || { sed 's/^/    /' <<<"$out_n2r"; fail "(n2) the declaration of a CLOSED roadmap item must be EXECUTED and verified, got rc=$rc"; }
# rc=0 alone would also be the exit code of a run that EXECUTED NOTHING, which is precisely
# the silent skip this case exists to forbid -- so assert the file was actually executed.
# (`--quiet` suppresses the per-case `red-there` log lines; the TOTAL line is the durable
# statement of how many files ran.)
grep -q 'across 1 file(s) executed' <<<"$out_n2r" \
  || { sed 's/^/    /' <<<"$out_n2r"; fail "(n2) the expired-carve-out file must actually be EXECUTED, not skipped with a green exit"; }
rm -- "$repo/tests/test_roadmap_shadowed.sh"
pass "(n2) the roadmap carve-out expires with the checkbox: a closed item's case is executed, not shadowed"

echo "ALL PASS: negative-case runner (id:a73c)"
