#!/usr/bin/env bash
# roadmap:11a4
#
# RED SPEC for ROADMAP id:11a4, authored by relay review (run
# relay-20260909-143257-21736) and closed by this same commit.
#
# THE DEFECT. `tests/run-tests.sh`'s `item_open()` grants EXPECTED-RED to any test
# file whose `# roadmap:XXXX` header names a `- [ ]` line in ROADMAP.md, with no
# regard for WHY that line is still unticked. A `@container` / DECOMPOSED item is
# open indefinitely BY DESIGN -- its seams are the work, and the container itself
# never ticks even after every seam lands. So a spec keyed to the container's own
# token is granted expected-red status FOREVER, and a genuine regression after the
# implementing seam lands is reported "EXPECTED-RED ... red test is the spec" and
# never fails the suite. Confirmed live: `test_title_rewrite_batch_acceptance_64f9.sh`
# stayed expected-red after its seam (id:521b) landed and ticked, because it was
# keyed to the container id:64f9, not the seam.
#
# THE FIX PINNED HERE: `item_open()` now also asks whether the matched line itself
# carries a `@container` marker (bare or backticked) or the word `DECOMPOSED` in its
# gate annotation. If so, it is not "open" for expected-red purposes -- a test still
# keyed to it reports a real FAIL, forcing the header onto a landed/open seam id
# instead of silently swallowing regressions under the umbrella forever.
#
# WHAT THIS SPEC DOES NOT CLAIM: an ordinary `[INPUT - decision]`/`[HARD]` item with
# no seams yet (not decomposed) stays legitimately open and expected-red -- case (A)
# below is the regression guard for that, so the fix cannot overcorrect into treating
# every gated/undecided item as a container.
#
# Drives the REAL tests/run-tests.sh against a throwaway fixture ROADMAP + test
# files; the live repo is only read. Hermetic: everything happens under mktemp, no
# git, no network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_RUN_TESTS="$SRC_DIR/tests/run-tests.sh"
REAL_HERMETIC_ENV="$SRC_DIR/tests/lib/hermetic-git-env.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$REAL_RUN_TESTS" ]] || fail "setup: run-tests.sh not found at $REAL_RUN_TESTS"
[[ -f "$REAL_HERMETIC_ENV" ]] || fail "setup: hermetic-git-env.sh not found at $REAL_HERMETIC_ENV"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# `run-tests.sh` resolves its own ROOT (and hence ROADMAP.md) from
# `dirname "${BASH_SOURCE[0]}"/..`, not from cwd — so exercising the REAL,
# just-edited `item_open()` against a fixture ROADMAP requires copying the real
# script (byte-identical, never reimplemented) into a fixture tree next to a
# fixture ROADMAP.md, not driving the developer's own repo's ledger.
make_repo() {
  local repo="$1"
  mkdir -p "$repo/tests/lib"
  cp "$REAL_RUN_TESTS" "$repo/tests/run-tests.sh"
  cp "$REAL_HERMETIC_ENV" "$repo/tests/lib/hermetic-git-env.sh"
  chmod +x "$repo/tests/run-tests.sh"
}

RUN_TESTS_FIXTURE() {
  # $1 = repo dir, rest = test file args (already inside repo/tests)
  local repo="$1"; shift
  RUN_TESTS_DURCACHE="$TMP/durcache-$$" bash "$repo/tests/run-tests.sh" "$@"
}

# =====================================================================================
# (A) CONTROL — an ordinary open item (no @container/DECOMPOSED) is STILL granted
#     EXPECTED-RED. This is the pre-existing, correct behaviour and must not regress.
# =====================================================================================
REPO_A="$TMP/scratch-a"
make_repo "$REPO_A"
cat >"$REPO_A/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [ROUTINE] An ordinary open item with no seams <!-- id:aaaa -->
EOF
cat >"$REPO_A/tests/test_open_plain.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:aaaa
echo "FAIL: intentional fixture failure -- id:11a4 control case (A)"
exit 1
EOF
chmod +x "$REPO_A/tests/test_open_plain.sh"

rc=0
outA="$(RUN_TESTS_FIXTURE "$REPO_A" "$REPO_A/tests/test_open_plain.sh" 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(A) the runner should exit 0 for an item that is legitimately open and not a container: $outA"
grep -qE '^EXPECTED-RED +test_open_plain\.sh' <<<"$outA" || \
  fail "(A2) a plain open item's failing spec must still be reported EXPECTED-RED (the fix must not overcorrect): $outA"
grep -qE '^summary:.*1 expected-red' <<<"$outA" || \
  fail "(A3) the summary lost its expected-red count for the plain-open control: $outA"
pass "(A) an ordinary open (non-container) item still grants EXPECTED-RED — no overcorrection"

# =====================================================================================
# (B) THE FIX — a @container open item's failing spec is a real FAIL, not EXPECTED-RED
# =====================================================================================
REPO_B="$TMP/scratch-b"
make_repo "$REPO_B"
cat >"$REPO_B/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [INPUT - decision] A container item, open forever by design @container <!-- id:bbbb -->
EOF
cat >"$REPO_B/tests/test_open_container.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:bbbb
echo "FAIL: intentional fixture failure -- id:11a4 case (B), a genuine regression under the container's umbrella"
exit 1
EOF
chmod +x "$REPO_B/tests/test_open_container.sh"

rc=0
outB="$(RUN_TESTS_FIXTURE "$REPO_B" "$REPO_B/tests/test_open_container.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(B) the runner exited 0 with a real failure hidden under a @container umbrella: $outB"
grep -qE '^FAIL +test_open_container\.sh' <<<"$outB" || \
  fail "(B2) a spec keyed to an open @container item must be reported FAIL, not swallowed: $outB"
grep -qE '^EXPECTED-RED' <<<"$outB" && \
  fail "(B3) the @container item's spec was still granted EXPECTED-RED — the container umbrella must never do that: $outB"
grep -qE '^summary:.*1 failed' <<<"$outB" || \
  fail "(B4) the summary did not count the container-swallowed regression as a real failure: $outB"
pass "(B) a @container item never grants EXPECTED-RED — the swallowed regression surfaces as FAIL"

# =====================================================================================
# (C) DECOMPOSED gate annotation (no literal @container token) is caught the same way,
#     matching the real ROADMAP shape (e.g. id:4839's `@container DECOMPOSED into
#     seams …` annotation) and the id:64f9 shape (`DECOMPOSED into seams …` with no
#     `@container` on the SAME line in some historical annotations).
# =====================================================================================
REPO_C="$TMP/scratch-c"
make_repo "$REPO_C"
cat >"$REPO_C/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [INPUT - decision] A gated item — GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:cccd, id:ccce — pick those, not this. <!-- id:cccc -->
EOF
cat >"$REPO_C/tests/test_open_decomposed.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:cccc
echo "FAIL: intentional fixture failure -- id:11a4 case (C), DECOMPOSED without a literal @container token"
exit 1
EOF
chmod +x "$REPO_C/tests/test_open_decomposed.sh"

rc=0
outC="$(RUN_TESTS_FIXTURE "$REPO_C" "$REPO_C/tests/test_open_decomposed.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(C) the runner exited 0 for a DECOMPOSED umbrella item's swallowed regression: $outC"
grep -qE '^FAIL +test_open_decomposed\.sh' <<<"$outC" || \
  fail "(C2) a DECOMPOSED-annotated item's spec must be reported FAIL: $outC"
grep -qE '^EXPECTED-RED' <<<"$outC" && \
  fail "(C3) a DECOMPOSED-annotated item still granted EXPECTED-RED: $outC"
pass "(C) DECOMPOSED (without a bare @container token) is caught the same way"

# =====================================================================================
# (D) A BACKTICKED `@container` marker (real shape seen on id:7408) is also caught —
#     the match must not require the marker to be bare markdown.
# =====================================================================================
REPO_D="$TMP/scratch-d"
make_repo "$REPO_D"
cat >"$REPO_D/ROADMAP.md" <<'EOF'
# ROADMAP

- [ ] [INPUT - decision] A backtick-quoted container marker `@container` <!-- id:dddd -->
EOF
cat >"$REPO_D/tests/test_open_backtick_container.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:dddd
echo "FAIL: intentional fixture failure -- id:11a4 case (D), backticked @container"
exit 1
EOF
chmod +x "$REPO_D/tests/test_open_backtick_container.sh"

rc=0
outD="$(RUN_TESTS_FIXTURE "$REPO_D" "$REPO_D/tests/test_open_backtick_container.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(D) the runner exited 0 for a backtick-quoted @container's swallowed regression: $outD"
grep -qE '^FAIL +test_open_backtick_container\.sh' <<<"$outD" || \
  fail "(D2) a backtick-quoted @container item's spec must be reported FAIL: $outD"
pass "(D) a backtick-quoted \`@container\` marker is caught the same way as a bare one"

echo "ALL PASS: id:11a4 a container/DECOMPOSED item never grants a spec EXPECTED-RED"
