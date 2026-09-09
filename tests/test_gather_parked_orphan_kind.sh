#!/usr/bin/env bash
# test_gather_parked_orphan_kind.sh -- gather-human-backlog.sh must surface every parked
# `relay/orphan/*` branch as a `parked_orphan` row.
#
# NO `# roadmap:` HEADER ON PURPOSE: there is no ROADMAP item for this work, so there is
# no checkbox for the runner's expected-red rule to consult. Its failures must therefore
# always count as real failures -- which is what omitting the header buys.
#
# WHAT IS UNDER TEST, and why it is not vacuous. Against the UNMODIFIED collector (the
# revision before the `parked_orphan` kind existed) the fixture's alpha repo holds a real
# `relay/orphan/*` branch with an unmerged commit, and the collector emits NOT ONE row of
# kind `parked_orphan` -- no emitter in the script ever looked at `refs/heads/relay/orphan/`.
# The false-clean guard (case 4) fails there too, and for the more damning reason: a
# configured repo path that is not a readable git repo produced no orphan output AND exit
# 0, i.e. exactly the silent "this repo has no parked orphans" that `id:4e14` names.
#
# CASE ORDER IS DELIBERATE: the headline behavioural assertion is LAST, so that against an
# unmodified ancestor it is the LAST `FAIL:` line emitted -- the one a negative-case runner
# is required to match. The cases before it pin the CONTRACTS the new emitter could break
# (the negative repo, the 4-column shape, the id:da87 review_me-is-last ordering, the
# id:4e14 loud-on-unreadable rule); several of those would pass vacuously against the
# ancestor, which is precisely why they are not the declared assertion.
#
# fails-against-rev: 8280dc2b -- relay/scripts/gather-human-backlog.sh relay/references/human.md
# fails-against-assertion: HEADLINE: a repo holding relay/orphan/
#
# Hermetic: mktemp -d for everything, HOME/SRC_DIR/RELAY_TOML overridden into the fixture,
# no network. Never touches ~/.claude, ~/.config/relay, or any real repo.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATHER="$ROOT/relay/scripts/gather-human-backlog.sh"

fails=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; fails=$((fails + 1)); }

[[ -x "$GATHER" ]] || { echo "FAIL: gather-human-backlog.sh missing/not executable: $GATHER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# fixture git repos must be immune to the developer's global hooksPath / identity
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null

git_q() { git "$@" >/dev/null 2>&1; }

# make_repo <name> -> $T/src/<name>, one commit on main, plus a REVIEW_ME box so the repo
# always produces SOME row. That is what makes "no parked_orphan row" a meaningful
# negative: an empty TSV would be ambiguous between "no orphans" and "collector broke".
make_repo() {
  local n="$1" r="$T/src/$1"
  mkdir -p "$r"
  git_q init -b main "$r"
  git_q -C "$r" config user.email fixture@example.invalid
  git_q -C "$r" config user.name fixture
  printf 'base\n' > "$r/f"
  printf '# REVIEW_ME\n\n- [ ] a real human-judgment box in %s\n' "$n" > "$r/REVIEW_ME.md"
  git_q -C "$r" add -A
  git_q -C "$r" commit -m base
  printf '%s' "$r"
}

# park_orphan <repo> <branch-basename> -- reproduce what worktree-retire.sh leaves behind:
# a commit that is NOT on main, reachable only from refs/heads/relay/orphan/<basename>.
park_orphan() {
  local r="$1" bn="$2"
  git_q -C "$r" checkout -b "relay/orphan/$bn"
  printf 'unmerged executor work\n' >> "$r/f"
  git_q -C "$r" commit -am "feat: real unmerged work parked from a dead run ($bn)"
  git_q -C "$r" checkout main
}

ORPHAN_BN='relay-20260101-000000-1234-execute-repo-0'
ALPHA="$(make_repo alpha)"   # holds a parked orphan
BETA="$(make_repo beta)"     # holds none
park_orphan "$ALPHA" "$ORPHAN_BN"

mkdir -p "$T/cfg" "$T/home"
cat > "$T/cfg/relay.toml" <<EOF
[repos.alpha]
classification = "own"
path = "$ALPHA"

[repos.beta]
classification = "own"
path = "$BETA"
EOF

# HOME is redirected into the fixture so relay-reconcile.sh's own log (~/.claude/logs/…)
# can never be written to the developer's real ~/.claude.
run_gather() {
  HOME="$T/home" SRC_DIR="$T/src" RELAY_TOML="$T/cfg/relay.toml" \
    env -u RELAY_RATIFICATION_QUEUE -u FABLES_CONFIG bash "$GATHER" "$@"
}

out="$(run_gather 2>"$T/err")"; rc=$?
alpha_rows="$(awk -F'\t' '$1=="alpha" && $3=="parked_orphan"' <<< "$out")"
n_alpha="$(printf '%s' "$alpha_rows" | grep -c . || true)"

[[ $rc -eq 0 ]] \
  && pass "gather exits 0 on a clean fixture holding a parked orphan" \
  || { fail "gather exited $rc on a clean fixture"; cat "$T/err"; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. THE NEGATIVE: a repo with NO parked orphan produces NO parked_orphan row --
#    while still producing its other rows, so an empty scan cannot masquerade as
#    a correct negative.
# ─────────────────────────────────────────────────────────────────────────────
beta_orphans="$(awk -F'\t' '$1=="beta" && $3=="parked_orphan"' <<< "$out")"
[[ -z "$beta_orphans" ]] \
  && pass "a repo with no relay/orphan/* branch emits NO parked_orphan row" \
  || fail "beta has no parked orphan but emitted:"$'\n'"$beta_orphans"
beta_any="$(awk -F'\t' '$1=="beta"' <<< "$out")"
[[ -n "$beta_any" ]] \
  && pass "beta was actually scanned (its REVIEW_ME box came through) -- the negative is not an empty scan" \
  || fail "beta produced NO rows at all; the negative above would be vacuous"

# ─────────────────────────────────────────────────────────────────────────────
# 2. COLUMN CONTRACT: still exactly 4 tab-separated columns on every row.
# ─────────────────────────────────────────────────────────────────────────────
badcols="$(awk -F'\t' 'NF!=4 {c++} END{print c+0}' <<< "$out")"
[[ "$badcols" == 0 ]] \
  && pass "every row still has exactly 4 columns (repo/path/kind/box_summary)" \
  || fail "$badcols rows have != 4 columns"

# ─────────────────────────────────────────────────────────────────────────────
# 3. ORDERING (id:da87): review_me stays the LAST bucket, so a parked_orphan row
#    must never be emitted after it for the same repo.
# ─────────────────────────────────────────────────────────────────────────────
last_rm="$(awk -F'\t' '$1=="alpha" && $3=="review_me"{n=NR} END{print n+0}' <<< "$out")"
last_po="$(awk -F'\t' '$1=="alpha" && $3=="parked_orphan"{n=NR} END{print n+0}' <<< "$out")"
if [[ "$last_rm" -gt 0 && "$last_po" -gt 0 && "$last_po" -lt "$last_rm" ]]; then
  pass "parked_orphan rows precede review_me -- the id:da87 'review_me is last' ordering holds"
else
  fail "ordering broken: last alpha review_me row=$last_rm, last alpha parked_orphan row=$last_po"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. id:4e14 FALSE-CLEAN GUARD: a configured repo path that exists but is NOT a
#    readable git repo must be SURFACED on stderr, by NAME, saying its branches
#    could not be checked -- never silently read as "this repo has no parked
#    orphans". (Loud-on-stderr-and-continue is what relay-reconcile.sh's own
#    `--all` pass does for the same case; the failure this forbids is the SILENT
#    one, and every other emitter still has real rows for such a repo.)
# ─────────────────────────────────────────────────────────────────────────────
BROKEN="$T/src/broken"; mkdir -p "$BROKEN"
printf '# REVIEW_ME\n\n- [ ] a box in the unreadable repo\n' > "$BROKEN/REVIEW_ME.md"
cat >> "$T/cfg/relay.toml" <<EOF

[repos.broken]
classification = "own"
path = "$BROKEN"
EOF
out2="$(run_gather 2>"$T/err2")"; rc2=$?
if grep -q '^NOTE: broken' "$T/err2" && grep -q 'id:4e14' "$T/err2"; then
  pass "an unreadable repo is named LOUDLY on stderr as un-checkable (never a silent clean bill)"
else
  fail "no id:4e14 stderr line naming the unreadable repo -- the false-clean shape"; cat "$T/err2"
fi
broken_orphans="$(awk -F'\t' '$1=="broken" && $3=="parked_orphan"' <<< "$out2")"
[[ -z "$broken_orphans" ]] \
  && pass "the unreadable repo contributes NO fabricated parked_orphan row" \
  || fail "the unreadable repo emitted a parked_orphan row:"$'\n'"$broken_orphans"
grep -qE $'^alpha\t.*\tparked_orphan\t' <<< "$out2" \
  && pass "alpha's parked_orphan row survives an unreadable sibling repo (id:da87 isolation)" \
  || fail "an unreadable sibling repo suppressed alpha's parked_orphan rows"

# ─────────────────────────────────────────────────────────────────────────────
# 5. HEADLINE (last on purpose -- see the header): the repo holding the parked
#    branch produces exactly one parked_orphan row, naming the branch and its
#    disposition commands.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$n_alpha" == 1 ]] \
   && grep -qF "relay/orphan/$ORPHAN_BN" <<< "$alpha_rows" \
   && grep -qF -- '--integrate' <<< "$alpha_rows" \
   && grep -qF -- '--discard' <<< "$alpha_rows"; then
  pass "a repo holding relay/orphan/* emits exactly ONE parked_orphan row naming the branch and its integrate/discard commands"
else
  fail "HEADLINE: a repo holding relay/orphan/$ORPHAN_BN did not produce exactly one parked_orphan row naming the branch and its integrate/discard commands (rows=$n_alpha):"$'\n'"${alpha_rows:-<none>}"
fi

printf '\n%s: %d failure(s)\n' "$(basename "$0")" "$fails"
[[ $fails -eq 0 ]]
