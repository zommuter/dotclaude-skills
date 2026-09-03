#!/usr/bin/env bash
# roadmap:d667
#
# END-TO-END spec for hooks/pre-commit-ledger-grammar.sh (id:d667): the pre-commit ratchet
# that BLOCKS a commit whose staged diff ADDS a non-conforming line to TODO.md / ROADMAP.md /
# REVIEW_ME.md, grandfathering the existing corpus STRUCTURALLY (unchanged lines are never
# inspected -- no exemption list, nothing to expire).
#
# Every case drives a REAL `git commit` in a scratch repo with the hook installed the way
# `make install-ledger-grammar-ratchet` installs it (a SYMLINK inside a core.hooksPath dir).
# The symlink shape is load-bearing, not cosmetic: the hook resolves its own repo root via
# `readlink -f "$0"` to find relay/scripts/todo-conformance.sh, so a COPIED hook cannot find
# the grammar predicate at all. Testing a copy would test a configuration nobody ships.
#
# No `# fails-against-*:` declaration: this is a NEW-FEATURE spec keyed to a roadmap item
# (the header above), not a defect-fix test, so the convention in CLAUDE.md's Testing
# section does not apply to it.
#
# HERMETIC: mktemp -d for everything, its own $HOME, its own core.hooksPath, its own
# relay.toml. Never touches ~/.claude, the live ledgers, this repo's .git, or the network.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# id:4d1c hermeticity: neutralize the DEVELOPER's global core.hooksPath, so the real
# installed pre-commit-lane-vocab.sh can never fire inside these fixtures.
# shellcheck source=tests/lib/hermetic-git-env.sh
source "$REPO_ROOT/tests/lib/hermetic-git-env.sh"
# ...but this file is the one test whose whole subject IS a pre-commit hook, so the commits
# under test must run with that env override LIFTED (`git_hooked` below). They stay hermetic
# by a different route: each fixture repo sets its OWN repo-local `core.hooksPath`, which
# takes precedence over the developer's global one, and points at a dir holding exactly one
# symlink -- the hook under test. Nothing else can run.
git_hooked() { env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 "$@"; }
HOOK="$REPO_ROOT/hooks/pre-commit-ledger-grammar.sh"
CONFORMANCE="$REPO_ROOT/relay/scripts/todo-conformance.sh"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

rc=0
fail() { echo "FAIL: $*"; rc=1; }
ok()   { echo "ok: $*"; }

# ── a scratch repo with the hook armed exactly as the make target arms it ────────────────
# $1 = repo name. Echoes the repo path. The hook dir is per-repo so cases cannot leak into
# each other, and core.hooksPath is set per-repo so the DEVELOPER's global hooksPath (this
# machine has one) can never run inside the fixture.
new_repo() {
  local name="$1" r="$WORK/$1"
  mkdir -p "$r" "$WORK/$1.hooks"
  ln -sf "$HOOK" "$WORK/$1.hooks/pre-commit"
  git init -q "$r"
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name  "ledger grammar test"
  git -C "$r" config commit.gpgsign false
  git -C "$r" config core.hooksPath "$WORK/$1.hooks"
  printf '%s' "$r"
}

# do_commit <repo> <msg> [extra git args...] -> sets $res to COMMITTED/BLOCKED and $LAST_ERR to
# the hook's stderr. Deliberately NOT a command-substitution helper: a `$( )` subshell cannot
# export $LAST_ERR back to the caller, and a silently empty $LAST_ERR would make every
# "and the message named the right class" assertion pass on an empty string.
# The FIRST commit of every fixture bypasses the hook (-c core.hooksPath=/dev/null) so the
# baseline corpus can be deliberately non-conforming.
LAST_ERR=""
res=""
do_commit() {
  local r="$1" msg="$2"; shift 2
  if git_hooked env HOME="$WORK/home" LEDGER_GRAMMAR_ALL_REPOS=1 \
      git -C "$r" commit -q "$@" -m "$msg" >"$WORK/last.out" 2>"$WORK/last.err"; then
    res=COMMITTED
  else
    res=BLOCKED
  fi
  LAST_ERR="$(cat "$WORK/last.err")"
}

mkdir -p "$WORK/home/.claude/logs"

# The baseline corpus every case starts from: DELIBERATELY non-conforming in two distinct
# ways (text after the id marker; an indented continuation line). Cases (a) and (d) rest on
# this being genuinely dirty, so it is asserted below rather than assumed.
BASE_TODO='# TODO

## Current

- [ ] [ROUTINE] **Pre-existing item with junk after its id.** <!-- id:1111 --> and then some
  a pre-existing continuation line
- [ ] [ROUTINE] **A clean pre-existing item.** <!-- id:2222 -->
'

# ── FIXTURE SANITY (the anti-vacuity control for case (d)) ───────────────────────────────
# Case (d) claims "a pre-existing non-conforming line, untouched, does NOT block". That claim
# is worthless unless the baseline really is non-conforming: if the fixture were clean, (d)
# would pass for the wrong reason and would keep passing after grandfathering broke. So prove
# FIRST, against the predicate itself, that these lines ARE findings.
printf '%s' "$BASE_TODO" > "$WORK/sanity.md"
sanity="$(HOME="$WORK/home" bash "$CONFORMANCE" --grammar-lines "$WORK/sanity.md" 2>/dev/null)"
if grep -q '^5	grammar-item-after-id' <<<"$sanity" && grep -q '^6	grammar-continuation' <<<"$sanity"; then
  ok "fixture sanity: the baseline corpus really is non-conforming (lines 5 and 6)"
else
  fail "fixture sanity: the baseline corpus is NOT non-conforming, so case (d) would be vacuous. Got: $sanity"
fi

# ── (a) a conforming added item line COMMITS -- alongside the dirty baseline ─────────────
r="$(new_repo a)"
printf '%s' "$BASE_TODO" > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
printf -- '- [ ] [ROUTINE] **A brand new conforming item.** <!-- id:3333 -->\n' >> "$r/TODO.md"
git -C "$r" add TODO.md
do_commit "$r" 'add a conforming item'
if [[ "$res" == COMMITTED ]]; then
  ok "(a) a conforming added item line commits"
else
  fail "(a) a conforming added item line was BLOCKED: $LAST_ERR"
fi

# ── (d) GRANDFATHERING: the untouched non-conforming lines did not block (a) ─────────────
# Same commit as (a), asserted as its own case because it is the whole ratchet claim. The
# fixture-sanity check above is what stops this from being vacuous: lines 5 and 6 of the
# committed file ARE findings, they were simply never added by this commit.
if [[ "$res" == COMMITTED ]]; then
  ok "(d) pre-existing non-conforming lines, untouched, do not block a commit"
else
  fail "(d) grandfathering broke -- untouched pre-existing non-conformance blocked the commit"
fi
# ...and prove the same lines are still there, still dirty, in what was committed.
committed="$(git -C "$r" show HEAD:TODO.md)"
if grep -qF '<!-- id:1111 --> and then some' <<<"$committed" \
   && grep -qF '  a pre-existing continuation line' <<<"$committed"; then
  ok "(d) the grandfathered lines survived into the commit untouched"
else
  fail "(d) the grandfathered lines are not in the committed file -- the fixture did not exercise the claim"
fi

# ── (b) an added CONTINUATION line is BLOCKED ────────────────────────────────────────────
r="$(new_repo b)"
printf '%s' "$BASE_TODO" > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
printf '  a NEWLY ADDED continuation line\n' >> "$r/TODO.md"
git -C "$r" add TODO.md
do_commit "$r" 'add a continuation line'
if [[ "$res" == BLOCKED ]] && grep -q 'grammar-continuation' <<<"$LAST_ERR"; then
  ok "(b) an added continuation line is blocked, naming grammar-continuation"
else
  fail "(b) an added continuation line was not blocked as grammar-continuation (res=$res): $LAST_ERR"
fi
# The block must be a REFUSAL, not a silent no-op: HEAD must not have moved.
if [[ "$(git -C "$r" rev-list --count HEAD)" == 1 ]]; then
  ok "(b) the blocked commit really did not land"
else
  fail "(b) the commit landed despite the hook reporting a block"
fi

# ── (c) an added OVER-LONG TITLE only WARNS and still commits ────────────────────────────
r="$(new_repo c)"
printf '%s' "$BASE_TODO" > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
long_title="$(printf 'x%.0s' $(seq 1 260))"
printf -- '- [ ] [ROUTINE] **%s.** <!-- id:4444 -->\n' "$long_title" >> "$r/TODO.md"
git -C "$r" add TODO.md
do_commit "$r" 'add an over-long title'
if [[ "$res" == COMMITTED ]]; then
  ok "(c) an over-long title still commits"
else
  fail "(c) an over-long title BLOCKED the commit -- title length must stay WARN (id:64f9): $LAST_ERR"
fi
if grep -q 'grammar-item-title-long' <<<"$LAST_ERR" && grep -qi 'WARN' <<<"$LAST_ERR"; then
  ok "(c) the over-long title was reported as a WARN"
else
  fail "(c) the over-long title produced no WARN -- a silent pass is not the contract: $LAST_ERR"
fi

# ── (e) --no-verify overrides the block ──────────────────────────────────────────────────
r="$(new_repo e)"
printf '%s' "$BASE_TODO" > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
printf '  another added continuation line\n' >> "$r/TODO.md"
git -C "$r" add TODO.md
do_commit "$r" 'blocked without the escape hatch'
[[ "$res" == BLOCKED ]] || fail "(e) precondition: the offending commit should have been blocked first (res=$res)"
do_commit "$r" 'escape hatch' --no-verify
if [[ "$res" == COMMITTED ]]; then
  ok "(e) --no-verify overrides the block"
else
  fail "(e) --no-verify did not override the block: $LAST_ERR"
fi

# ── (f) THE ARCHIVE-MOVE CASE (the id:7909 hazard) ───────────────────────────────────────
# id:7909 records that the lane-vocab ratchet cannot tell a MOVE from an ADDITION, so it
# blocks every archive commit in a repo carrying legacy tags. Both halves are exercised
# against a REAL archiver run, not reasoned about.
#
# (f1) todo-update/archive-done.sh -- moves [x] blocks out of TODO.md into TODO.archive.md.
#      Pure deletions on the live ledger; the additions land in *.archive.md, which is out of
#      grammar scope (id:2065). Expected and MEASURED: commits cleanly.
r="$(new_repo f1)"
{
  printf '%s' "$BASE_TODO"
  printf -- '- [x] [ROUTINE] **A closed item.** <!-- id:5555 -->\n'
  printf '  its non-conforming body line\n'
  # archive-done.sh only archives when the file has >= 50 lines.
  for i in $(seq 1 60); do printf -- '- [ ] [ROUTINE] **Filler %s.** <!-- id:b%03d -->\n' "$i" "$i"; done
} > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
( cd "$r" && HOME="$WORK/home" bash "$REPO_ROOT/todo-update/archive-done.sh" TODO.md ) >/dev/null 2>&1
if [[ -f "$r/TODO.archive.md" ]]; then
  ok "(f1) archive-done.sh actually moved something (precondition)"
else
  fail "(f1) archive-done.sh archived nothing -- the case would be vacuous"
fi
git -C "$r" add TODO.md TODO.archive.md
do_commit "$r" 'archive done items'
if [[ "$res" == COMMITTED ]]; then
  ok "(f1) a real archive-done.sh commit is NOT blocked (the id:7909 hazard misses TODO archiving)"
else
  fail "(f1) a real archive-done.sh commit was BLOCKED -- id:d667 is gated on id:7909: $LAST_ERR"
fi

# (f2) relay/scripts/roadmap-archive.sh -- the hazard USED to bite here and NO LONGER DOES.
#      `id:cd9c` made the archiver leave a STUB behind in the LIVE ROADMAP.md (the header
#      line verbatim + " (archived - see ROADMAP.archive.md)"), which was a genuine ADDED
#      line with text after the id marker, so `grammar-item-after-id` fired on a line the
#      fleet's own tooling had written. This case pinned that, and said in as many words:
#      "if roadmap-archive.sh ever emits a conforming stub, this case goes red and whoever
#      reads it should re-check whether the hook can be armed."
#
#      id:2eba (owner-ratified 2026-09-03) went further than a conforming stub: the archiver
#      emits NO stub at all, so a ROADMAP archive commit is now a PURE DELETION on the live
#      ledger with the additions landing in ROADMAP.archive.md, which is out of grammar
#      scope (id:2065) -- structurally the same shape as (f1). The case is inverted to pin
#      the new measured fact.
#
#      WHAT THIS DOES *NOT* SAY: it does not claim id:d667 can now be armed. It removes ONE
#      named blocker (this one) and says so; whether others remain is a separate reading and
#      an owner call, not something this test settles.
r="$(new_repo f2)"
{
  printf '# ROADMAP\n\n## Items\n\n'
  printf -- '- [x] [ROUTINE] **A closed roadmap item.** <!-- id:6666 -->\n'
  printf '  its body line\n'
  printf -- '- [ ] [ROUTINE] **An open roadmap item.** <!-- id:7777 -->\n'
} > "$r/ROADMAP.md"
git -C "$r" add ROADMAP.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
( cd "$r" && HOME="$WORK/home" bash "$REPO_ROOT/relay/scripts/roadmap-archive.sh" "$r" ) >/dev/null 2>&1
if [[ -f "$r/ROADMAP.archive.md" ]] && grep -q 'A closed roadmap item' "$r/ROADMAP.archive.md"; then
  ok "(f2) roadmap-archive.sh actually moved something (precondition)"
else
  fail "(f2) roadmap-archive.sh archived nothing -- the case would be vacuous"
fi
if grep -q 'archived — see' "$r/ROADMAP.md"; then
  fail "(f2) roadmap-archive.sh still writes an archive stub into the live ledger -- id:2eba says it must not"
else
  ok "(f2) roadmap-archive.sh leaves no stub in the live ledger (id:2eba)"
fi
git -C "$r" add ROADMAP.md
[[ -f "$r/ROADMAP.archive.md" ]] && git -C "$r" add ROADMAP.archive.md
do_commit "$r" 'archive roadmap items'
if [[ "$res" == COMMITTED ]]; then
  ok "(f2) MEASURED: a roadmap-archive.sh commit is NOT blocked any more -- id:2eba removed the archive-stub blocker that gated arming id:d667 (one blocker, not a clearance)"
else
  fail "(f2) a roadmap-archive.sh commit is STILL blocked (res=$res): $LAST_ERR"
fi

# ── (g) a repo NOT in the relay.toml own-set is unaffected ───────────────────────────────
# LEDGER_GRAMMAR_ALL_REPOS is deliberately NOT set here; a fixture relay.toml lists some
# OTHER path as the only own repo, so the self-gate must no-op.
r="$(new_repo g)"
cat > "$WORK/relay.toml" <<TOML
[repos.somewhere-else]
classification = "own"
# path: $WORK/not-this-repo
TOML
printf '%s' "$BASE_TODO" > "$r/TODO.md"
git -C "$r" add TODO.md
git -C "$r" -c core.hooksPath=/dev/null commit -q -m base
printf '  a continuation line that WOULD be blocked in an own repo\n' >> "$r/TODO.md"
git -C "$r" add TODO.md
errf="$WORK/err.g"
if git_hooked env HOME="$WORK/home" LEDGER_GRAMMAR_RELAY_TOML="$WORK/relay.toml" SRC_DIR="$WORK" \
    git -C "$r" commit -q -m 'unowned repo' >/dev/null 2>"$errf"; then
  res=COMMITTED
else
  res=BLOCKED
fi
LAST_ERR="$(cat "$errf")"
if [[ "$res" == COMMITTED ]] && grep -q 'not in the relay own-repo set' <<<"$LAST_ERR"; then
  ok "(g) a repo outside the relay own-repo set is a no-op"
else
  fail "(g) the hook did not no-op outside the own-repo set (res=$res): $LAST_ERR"
fi

# ── the predicate is not duplicated: the hook must ask todo-conformance.sh ───────────────
# A structural check, cheap and worth having: if someone re-implements the grammar inside the
# hook, this is the assertion that notices.
if grep -q -- '--grammar-lines' "$HOOK" && grep -q 'todo-conformance.sh' "$HOOK"; then
  ok "the hook delegates the grammar to todo-conformance.sh --grammar-lines"
else
  fail "the hook no longer delegates to todo-conformance.sh --grammar-lines -- two copies of a grammar drift silently"
fi

# ── the hook ships DISABLED: no make target may wire it as a side effect of install ───────
if grep -q 'install-ledger-grammar-ratchet' "$REPO_ROOT/Makefile"; then
  ok "an explicit arming target exists (install-ledger-grammar-ratchet)"
else
  fail "no install-ledger-grammar-ratchet target in the Makefile"
fi
general_install_block="$(grep -E '^(install|install-hooks):' -A4 "$REPO_ROOT/Makefile")"
if grep -qE '^(install|install-hooks):.*' "$REPO_ROOT/Makefile" \
   && ! grep -q 'install-ledger-grammar-ratchet' <<<"$general_install_block"; then
  ok "neither 'install' nor 'install-hooks' arms the ratchet (it ships DISABLED)"
else
  fail "the ledger-grammar ratchet is armed by a general install target -- it must ship DISABLED"
fi

exit $rc
