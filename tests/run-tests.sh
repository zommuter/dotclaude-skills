#!/usr/bin/env bash
# run-tests.sh — plain-bash test runner for dotclaude-skills.
#
# Usage:
#   tests/run-tests.sh                      # full suite, parallel (jobs = nproc)
#   tests/run-tests.sh -j 4                 # explicit job count
#   JOBS=4 tests/run-tests.sh               # same, via env (an explicit -j wins)
#   tests/run-tests.sh tests/test_foo.sh …  # subset
#
# Each tests/test_*.sh is an independent bash script: exit 0 = pass, exit 3 = ERROR
# (id:735f — the check could not RUN at all, e.g. via tests/lib/check.sh's exit-2+
# branch; distinct from a false assertion and NEVER expected-red), any other nonzero =
# a failed assertion.
# Expected-red semantics (see CLAUDE.md §Testing):
#   A FAILING (non-error) test file whose `# roadmap:XXXX` item is still UNTICKED in
#   ROADMAP.md is reported EXPECTED-RED and does not fail the suite — red tests
#   are the executable spec for open roadmap items. Once the item's checkbox is
#   ticked, its failures are real failures. Passing tests always count. An ERRORED
#   test is never expected-red — redness-is-the-spec is a claim about assertions, not
#   about a check that could not execute.
# Exit code: 0 if no real failures/errors, 1 otherwise.
#
# Parallelism contract:
#   * `-j 1` reproduces the historical serial behaviour EXACTLY (same lines, same
#     order, same exit code). It is the compatibility anchor.
#   * Output NEVER interleaves: each test's stdout+stderr is buffered to its own
#     temp file and results are emitted in STABLE FILE ORDER (not completion
#     order), so a FAIL block stays contiguous under its own FAIL line.
#   * NESTED RUNS ARE SERIAL: ~10 test files invoke this runner recursively. We
#     export RUN_TESTS_NESTED=1; when set, jobs is forced to 1 regardless of
#     flag/env/nproc, so an outer pool of N cannot spawn N inner pools of N.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="$ROOT/ROADMAP.md"

# Hermeticity: tests build throwaway git fixture repos and `git commit`/`git init` into
# them. This suite must be immune to the DEVELOPER's own global git config — in
# particular a global `core.hooksPath` (e.g. this repo's own pre-commit-lane-vocab.sh /
# pre-push-privacy-gate.sh, installed via `make install-lane-ratchet` /
# `make install-privacy-gate`) must never fire inside a fixture repo just because the
# fixture's relay.toml happens to list it as "own". tests/lib/hermetic-git-env.sh is the
# single source of this override (id:4d1c) — individual fixture-building test files
# source it too, so `bash tests/test_foo.sh` run DIRECTLY is hermetic on its own and
# does not depend on being launched through this runner.
source "$ROOT/tests/lib/hermetic-git-env.sh"

jobs="${JOBS:-}"
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -j)   jobs="${2-}"; shift 2 ;;
    -j*)  jobs="${1#-j}"; shift ;;
    --)   shift; args+=("$@"); break ;;
    *)    args+=("$1"); shift ;;
  esac
done

nested=0
if [[ -n "${RUN_TESTS_NESTED:-}" ]]; then
  nested=1
  jobs=1                       # a nested run always stays serial (see contract above)
elif [[ -z "$jobs" ]]; then
  # stderr suppressed deliberately: a missing/failing nproc is a benign "unknown core
  # count", and its message would corrupt the runner's own output. Falls back to 1.
  jobs="$(nproc 2>/dev/null || echo 1)"
fi
if ! [[ "$jobs" =~ ^[0-9]+$ ]] || (( jobs < 1 )); then
  echo "run-tests.sh: invalid job count: '$jobs'" >&2
  exit 2
fi
export RUN_TESTS_NESTED=1

if [[ ${#args[@]} -gt 0 ]]; then
  files=("${args[@]}")
else
  files=("$ROOT"/tests/test_*.sh)
fi

pass=0 fail=0 xred=0 errored=0
failed_names=()
errored_names=()

item_open() {
  # roadmap item with this token exists, is unticked, AND is not a CONTAINER.
  #
  # id:11a4: a @container / DECOMPOSED item is open indefinitely BY DESIGN -- its
  # seams are the work, not itself. Granting EXPECTED-RED to a spec keyed to the
  # container's own token would swallow a genuine regression forever, since the
  # container never ticks even after every seam lands. So a line carrying the
  # literal `@container` marker (bare or backticked) or the word `DECOMPOSED` in
  # its own gate annotation is NOT "open" for expected-red purposes: a test still
  # keyed to it is a real FAIL, forcing the header onto a landed/open seam id
  # instead. This is a claim about ONE bullet's own line, not about whether the
  # umbrella id happens to be an [INPUT - decision]/[HARD] item in general --
  # plenty of those are legitimately open with no seam yet, and stay expected-red.
  local token="$1"
  [[ -f "$ROADMAP" ]] || return 1
  grep -qE "^- \[ \] .*<!-- id:${token} -->" "$ROADMAP" || return 1
  local line
  line="$(grep -m1 -E "^- \[ \] .*<!-- id:${token} -->" "$ROADMAP")"
  if grep -qE '@container|DECOMPOSED' <<<"$line"; then
    return 1
  fi
  return 0
}

# Longest-first scheduling: durations are LEARNED from previous runs into a cache
# outside the repo (no hardcoded slow-test list — that rots). No cache => file order.
# Scheduling order never affects OUTPUT order, which is always file order. Nested runs
# neither read nor write the cache: they are serial anyway, and their throwaway fixture
# test files would poison real tests' timings via basename collisions.
DURCACHE="${RUN_TESTS_DURCACHE:-${TMPDIR:-/tmp}/dotclaude-run-tests-durations.tsv}"
(( nested )) && DURCACHE=""
mapfile -t order < <(
  printf '%s\n' "${files[@]}" | awk -v cache="$DURCACHE" '
    BEGIN { if (cache != "") while ((getline line < cache) > 0) { split(line, a, "\t"); d[a[1]] = a[2] } }
    { n = $0; sub(/.*\//, "", n); printf "%.3f\t%d\n", (n in d ? d[n] : 0), NR - 1 }
  ' | sort -t$'\t' -k1,1gr -k2,2n | cut -f2
)

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# ── id:b54b hermeticity backstop ─────────────────────────────────────────────────────
# A test fixture leaked a real `relay/ok` branch into THIS repo on 2026-08-22 (see
# TODO.md id:b54b) — a mktemp-scoped git fixture is supposed to touch only its own
# throwaway checkout, never the cwd repo run-tests.sh itself lives in. Rather than trust
# every test file to get that right, snapshot the cwd repo's relay/* branches and
# worktree list before and after the WHOLE run and fail LOUDLY on any drift. This is a
# structural backstop, not an attribution tool — under parallel jobs (`-j`>1) a leak by
# one test can't be pinned to it from this check alone; rerun the suspect file(s) alone
# (or with `-j 1`) to localize. Scoped to `.` (the runner's own cwd), which is the real
# repo root for every normal invocation and a scratch fixture repo for a nested
# self-test — never `$ROOT`, since a nested run's `$ROOT` still points at THIS repo.
snapshot_repo_state() {
  # RELAY worktree root (id:c132): the relay's own documented location for a child's
  # worktree is `$RELAY_WORKTREE_BASE/<repo>/...` (default `~/.cache/relay/worktrees`,
  # deliberately outside the repo tree per the relay SKILL.md invariant 4). Derived from
  # the same env var the relay scripts already read (never hardcoded — id:d4d3), so a
  # relocated root stays correctly excluded without a code change here.
  local relay_wt_base="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"
  # A relay child's `git worktree add -b relay/<runId>-...` mints BOTH a worktree AND
  # the branch it checks out, atomically — so excluding only the worktree line (as
  # `.claude/worktrees/` does, where the harness never creates a branch) leaves the new
  # `refs/heads/relay/*` ref behind as a spurious breach. Collect the branch(es) actually
  # checked out by a worktree under the relay root, and exclude only THOSE refs — a bare
  # `relay/*` branch with no such worktree (a genuine leak, or one leaked into the cwd
  # repo instead of the relay root) still fails unconditionally.
  local relay_wt_branches
  relay_wt_branches="$(git worktree list --porcelain 2>/dev/null | awk -v base="$relay_wt_base/" '
    /^worktree / { path = substr($0, 10); in_relay = (index(path, base) == 1) }
    /^branch /   { if (in_relay) { sub(/^branch /, ""); print } }
  ')"
  # id:b87b: the branch HEAD points at in THIS repo is expected to advance -- the
  # executor contract requires a relay child to "commit in the worktree as you go", and
  # every relay worktree branch lives inside the very `refs/heads/relay/` namespace this
  # guard watches. Exclude only that ONE ref's object-name from the comparison (replace
  # it with a fixed placeholder) rather than dropping object names generally: a fixture
  # force-moving some OTHER relay ref, or one being added/removed, must still trip the
  # guard. This is narrower than (and independent of) the id:c132 worktree-branch
  # exclusion above, which only fires when the branch is registered as a worktree under
  # $RELAY_WORKTREE_BASE -- a plain checkout on a `relay/*` branch (e.g. a hermeticity
  # fixture repo, or this repo's own root when run directly on such a branch) is not.
  local own_ref
  own_ref="$(git symbolic-ref -q HEAD 2>/dev/null || true)"
  git for-each-ref --format='%(refname) %(objectname)' refs/heads/relay/ 2>/dev/null \
    | { if [[ -n "$relay_wt_branches" ]]; then grep -vFf <(printf '%s\n' "$relay_wt_branches"); else cat; fi; } \
    | awk -v own="$own_ref" '{ if (own != "" && $1 == own) print $1, "<own-branch-head>"; else print }' \
    | sort
  echo '--worktrees--'
  # Exclude HARNESS-created agent worktrees (`.claude/worktrees/<name>`). Claude Code
  # creates one per isolated subagent and auto-removes it when the agent ends, so a
  # concurrent agent starting or finishing mid-run would otherwise trip a SPURIOUS
  # breach — this repo routinely carries ~20 of them. They are not test leaks and no
  # test creates them: fixtures work in `mktemp -d`, which is never under `.claude/`.
  # The leak signature this guard exists for (a fixture writing into the cwd repo) is
  # unaffected, since such a worktree would not live in that directory.
  #
  # Also exclude RELAY worktrees (id:c132), for the identical stated reason: a concurrent
  # `/relay` child starting or finishing mid-`make test` trips the same spurious breach.
  git worktree list --porcelain 2>/dev/null \
    | grep '^worktree ' \
    | grep -v '/\.claude/worktrees/' \
    | grep -vF "worktree $relay_wt_base/" \
    | sort
}
hermeticity_before="$(snapshot_repo_state)"

run_one() {  # $1 = index into files[]
  local i="$1" t0="$EPOCHREALTIME" rc
  bash "${files[$i]}" >"$tmp/$i.out" 2>&1
  rc=$?
  printf '%s\n' "$rc" >"$tmp/$i.rc"
  awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.3f\n", b-a}' >"$tmp/$i.dur"
}

running=0
for i in "${order[@]}"; do
  [[ -f "${files[$i]}" ]] || continue          # missing file => SKIP, emitted below
  while (( running >= jobs )); do wait -n; (( running-- )); done
  run_one "$i" &
  (( ++running ))
done
wait

hermeticity_after="$(snapshot_repo_state)"
hermeticity_breach=0
if [[ "$hermeticity_before" != "$hermeticity_after" ]]; then
  hermeticity_breach=1
  echo
  echo "HERMETICITY BREACH (id:b54b): the test run left relay/* ref or worktree drift in $(pwd) —"
  echo "a fixture reached the real repo instead of its own mktemp sandbox. This ALWAYS fails the"
  echo "suite, independent of every individual test's exit code. Diff (before -> after):"
  diff <(printf '%s\n' "$hermeticity_before") <(printf '%s\n' "$hermeticity_after") | sed 's/^/       | /' || true
  # id:b87b: name the finding precisely -- an added ref, a removed ref, and a moved ref
  # are three different things, and only the first is "left new relay/* refs".
  before_refs="$(awk '/^--worktrees--$/{exit} {print $1}' < <(printf '%s\n' "$hermeticity_before") | sort -u)"
  after_refs="$(awk '/^--worktrees--$/{exit} {print $1}' < <(printf '%s\n' "$hermeticity_after") | sort -u)"
  added_refs="$(comm -13 <(printf '%s\n' "$before_refs") <(printf '%s\n' "$after_refs") | grep -v '^$' || true)"
  removed_refs="$(comm -23 <(printf '%s\n' "$before_refs") <(printf '%s\n' "$after_refs") | grep -v '^$' || true)"
  common_refs="$(comm -12 <(printf '%s\n' "$before_refs") <(printf '%s\n' "$after_refs") | grep -v '^$' || true)"
  moved_refs=""
  if [[ -n "$common_refs" ]]; then
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      b_obj="$(awk -v r="$r" '$1==r{print $2; exit}' < <(printf '%s\n' "$hermeticity_before"))"
      a_obj="$(awk -v r="$r" '$1==r{print $2; exit}' < <(printf '%s\n' "$hermeticity_after"))"
      [[ "$b_obj" != "$a_obj" ]] && moved_refs+="$r"$'\n'
    done <<<"$common_refs"
  fi
  [[ -n "$added_refs" ]] && echo "  added ref(s):   $(printf '%s' "$added_refs" | tr '\n' ' ')"
  [[ -n "$removed_refs" ]] && echo "  removed ref(s): $(printf '%s' "$removed_refs" | tr '\n' ' ')"
  [[ -n "$moved_refs" ]] && echo "  moved ref(s):   $(printf '%s' "$moved_refs" | tr '\n' ' ')"
  echo "Rerun the suspect file(s) alone (or with -j 1) to localize which test caused this."
fi

# A harness that silently skips tests also "passes" — refuse to report at all if the
# scheduler failed to run something it should have.
for i in "${!files[@]}"; do
  [[ -f "${files[$i]}" ]] || continue
  [[ -f "$tmp/$i.rc" ]] || { echo "run-tests.sh: internal error: ${files[$i]} was never executed" >&2; exit 2; }
done

for i in "${!files[@]}"; do
  f="${files[$i]}"
  [[ -f "$f" ]] || { echo "SKIP   $f (not found)"; continue; }
  name="$(basename "$f")"
  token="$(head -1 < <(grep -oE '# roadmap:[0-9a-f]{4}' "$f") | sed 's/.*roadmap://' )" || true
  out="$(cat "$tmp/$i.out")"
  rc="$(cat "$tmp/$i.rc")"
  if [[ "$rc" == 0 ]]; then
    echo "PASS   $name"
    (( ++pass ))
  elif [[ "$rc" == 3 ]]; then
    # id:735f: exit 3 is a distinct EXECUTION ERROR (a check that could not run, e.g.
    # via tests/lib/check.sh), never a false assertion — it is NEVER granted
    # EXPECTED-RED, since redness-is-the-spec is a claim about assertions, not about a
    # check that could not execute at all.
    echo "ERROR  $name"
    printf '%s\n' "$out" | sed 's/^/       | /'
    errored_names+=("$name")
    (( ++errored ))
  else
    if [[ -n "${token:-}" ]] && item_open "$token"; then
      echo "EXPECTED-RED $name (roadmap:$token still open — red test is the spec)"
      (( ++xred ))
    else
      echo "FAIL   $name"
      printf '%s\n' "$out" | sed 's/^/       | /'
      failed_names+=("$name")
      (( ++fail ))
    fi
  fi
done

# Refresh the duration cache (last value per test name wins). Best-effort and silent:
# a broken cache only costs file-order scheduling, never correctness.
if [[ -n "$DURCACHE" ]]; then
  for i in "${!files[@]}"; do
    [[ -f "$tmp/$i.dur" ]] && printf '%s\t%s\n' "$(basename "${files[$i]}")" "$(cat "$tmp/$i.dur")"
  done >"$tmp/durs.new"
  # stderr suppressed deliberately: a first-ever run has no cache to cat, and an
  # unwritable cache is a benign loss of scheduling hints — never of test results.
  cat "$DURCACHE" "$tmp/durs.new" 2>/dev/null \
    | awk -F'\t' 'NF==2{d[$1]=$2} END{for (k in d) printf "%s\t%s\n", k, d[k]}' \
    | sort >"$tmp/durs.merged"
  [[ -s "$tmp/durs.merged" ]] && mv -- "$tmp/durs.merged" "$DURCACHE" 2>/dev/null
fi

echo
echo "summary: $pass passed, $fail failed, $errored errored, $xred expected-red (open roadmap items)"
if (( fail > 0 )); then
  printf 'failed: %s\n' "${failed_names[*]}"
fi
if (( errored > 0 )); then
  printf 'errored: %s\n' "${errored_names[*]}"
fi
if (( hermeticity_breach )); then
  echo "summary: HERMETICITY BREACH — see above (id:b54b)"
fi
if (( fail > 0 || errored > 0 || hermeticity_breach )); then
  exit 1
fi
exit 0
