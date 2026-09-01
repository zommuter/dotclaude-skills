#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:221f and always counts.)
#
# PARITY between the two force-flag guards (id:221f).  hooks/rm-force-guard.sh was
# written to a standard hooks/destructive-git-guard.py was not:
#
#   (a) SPELLING-INSENSITIVITY — rm-force-guard.sh matches `-[A-Za-z]*f|--force`, so
#       `-f`, `-rf`, `-vf` and `--force` all reach the SAME gate.  The git guard's
#       raw-text fallback scan did not: `git clean --force` and `git checkout -f .`
#       slipped past it while `git clean -fd` and `git checkout .` did not — the same
#       operation reaching a different verdict on spelling alone.
#
#   (b) ANCHORING — rm-force-guard.sh anchors to `^` so a force flag merely MENTIONED
#       in a commit message, an echo, or a quoted argument is not matched.  The git
#       guard's patterns matched ANYWHERE in the command string, so writing ABOUT a
#       guarded command was refused.  Filing id:221f itself hit this: the item's prose
#       quoted a tree-wide discard inside a heredoc payload to md-merge.py.
#
# SCOPE IS PARITY ONLY.  Nothing may newly deny — the (b) fix makes the scan fire
# strictly LESS, and the (a) fix only aligns the raw scan with verdicts the TOKENISED
# path already reached.  The five tree-wide forms remain an UNCONDITIONAL deny
# (owner ruling 2026-08-22); this file does not touch that and must not be read as
# reopening it.
# fails-against: rev dff9a707c214 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix hooks/destructive-git-guard.py. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: dff9a707c214 -- hooks/destructive-git-guard.py
# fails-against-assertion: guard does not mention id:221f — the rationale has no anchor in the file

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/destructive-git-guard.py"
RM_GUARD="$ROOT/hooks/rm-force-guard.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -f "$GUARD" ]] || { echo "FAIL: destructive-git-guard.py not found at $GUARD"; exit 1; }
[[ -f "$RM_GUARD" ]] || { echo "FAIL: rm-force-guard.sh not found at $RM_GUARD"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Sandbox tree so os.path.isdir() has real directories to resolve against.
REPO="$TMP/repo"
mkdir -p "$REPO/hooks" "$REPO/relay/scripts"
: > "$REPO/hooks/one-file.sh"

make_payload() {
    printf '{"session_id":"t","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# run_guard <command> -> stdout of the hook (context forced ambiguous; the deny is
# unconditional so context is irrelevant to every assertion here).
run_guard() {
    ( cd "$REPO" \
      && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
             HEARTBEAT_BASE="$TMP/no-such-heartbeats" \
             DESTRUCTIVE_GIT_GUARD_CONTEXT=ambiguous \
             python3 "$GUARD" <<< "$(make_payload "$1")" )
    # stderr is deliberately NOT redirected: the guard prints its deferral diagnostics
    # there, and swallowing them would hide a silent hole in the guard.
}

is_deny() { grep -q '"permissionDecision": *"deny"' <<< "$1"; }

# The raw fallback scan is reached only when the command cannot be tokenised.  A
# heredoc is the realistic trigger AND the exact shape that produced defect (b), so
# every raw-path case below is wrapped in one rather than probed through a private
# function — the wrapper is what the hook actually receives.
#
# raw_case <command-fragment> -> a command that forces the raw scan, with the fragment
# in genuine COMMAND position (after the heredoc's terminator).
raw_case() {
    printf 'cat > /dev/null <<EOF\npayload\nEOF\n%s\n' "$1"
}

# quoted_mention <command-fragment> -> the same fragment appearing only as PAYLOAD
# inside a heredoc body — never in command position.
quoted_mention() {
    printf 'python3 md-merge.py --update-ids <<EOF\nThe guard refuses %s here.\nEOF\n' "$1"
}

# ── (a) SPELLING TABLE ────────────────────────────────────────────────────────
# Every spelling of the same destructive op must reach the same verdict on BOTH the
# tokenised path and the raw fallback path.  A row is (command, expected verdict).
#
# The DENY rows are the parity claim: no spelling of a guarded op escapes.  The ALLOW
# rows are the non-escalation claim: the spelling-insensitive matcher must not have
# swallowed the genuinely-safe near-spellings (`-n`, `--dry-run`) — that would be a
# NEW deny, which id:221f forbids.
SPELL_DENY=(
  # git clean — short clusters, long form, and mixed order
  'git clean -f'
  'git clean -d'
  'git clean -fd'
  'git clean -df'
  'git clean -fdx'
  'git clean -xdf'
  'git clean -dfx'
  'git clean --force'
  'git clean -x --force'
  'git clean -f -- hooks'
  # git checkout / restore — with and without leading flags, with and without `--`
  'git checkout .'
  'git checkout -- .'
  'git checkout -f .'
  'git checkout --force .'
  'git checkout HEAD -- .'
  'git restore .'
  'git restore -- .'
  'git restore --staged .'
  'git restore --worktree --staged .'
  # git reset --hard, with an intervening tree-ish
  'git reset --hard'
  'git reset --hard HEAD~1'
  'git reset HEAD~1 --hard'
  # git stash discard verbs
  'git stash drop'
  'git stash clear'
  # a git global option in front must not change the verdict either
  'git -C . clean -fd'
  'git --no-pager clean --force'
)
SPELL_ALLOW=(
  'git clean -n'
  'git clean --dry-run'
  'git clean -nx'
  'git checkout main'
  'git checkout -b feature/x'
  'git checkout -- hooks/one-file.sh'
  'git restore hooks/one-file.sh'
  'git restore --staged hooks/one-file.sh'
  'git reset'
  'git reset --soft HEAD~1'
  'git stash'
  'git stash pop'
  'git stash list'
)

for cmd in "${SPELL_DENY[@]}"; do
    out="$(run_guard "$cmd")"
    is_deny "$out" && pass "spelling/tokenised DENY: $cmd" \
        || fail "spelling/tokenised: '$cmd' was NOT denied (spelling-dependent verdict)"

    out="$(run_guard "$(raw_case "$cmd")")"
    is_deny "$out" && pass "spelling/raw-scan DENY: $cmd" \
        || fail "spelling/raw-scan: '$cmd' was NOT denied on the fallback path (id:221f a)"
done

for cmd in "${SPELL_ALLOW[@]}"; do
    out="$(run_guard "$cmd")"
    [[ -z "$out" ]] && pass "spelling/tokenised ALLOW: $cmd" \
        || fail "spelling/tokenised: '$cmd' newly DENIED — id:221f forbids escalation"

    out="$(run_guard "$(raw_case "$cmd")")"
    [[ -z "$out" ]] && pass "spelling/raw-scan ALLOW: $cmd" \
        || fail "spelling/raw-scan: '$cmd' newly DENIED — id:221f forbids escalation"
done

# The specific spellings that USED to be raw-scan escapes, pinned by name so a
# regression names itself.
for cmd in 'git clean --force' 'git checkout -f .' 'git restore --staged .'; do
    out="$(run_guard "$(raw_case "$cmd")")"
    is_deny "$out" && pass "raw-scan regression pin: '$cmd' is caught" \
        || fail "raw-scan regression pin: '$cmd' escaped again"
done

# rm-force-guard.sh's own spelling table, asserted here so the STANDARD this file
# holds the git guard to is itself pinned rather than assumed.
rm_guard() {
    printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$RM_GUARD"
}
for cmd in 'rm -f x' 'rm -rf x' 'rm -fr x' 'rm -vf x' 'rm --force x' 'sudo rm -f x'; do
    is_deny "$(rm_guard "$cmd")" && pass "rm guard spelling DENY: $cmd" \
        || fail "rm guard spelling: '$cmd' not denied — the parity standard itself moved"
done
for cmd in 'rm -- x' 'rm -r -- x' 'rm -i x' 'git rm x'; do
    [[ -z "$(rm_guard "$cmd")" ]] && pass "rm guard spelling ALLOW: $cmd" \
        || fail "rm guard spelling: '$cmd' denied — the parity standard itself moved"
done

# ── (b) ANCHORING — the NEGATIVE CONTROL ──────────────────────────────────────
# A guarded command that is only QUOTED — inside a heredoc payload, a commit message,
# an echo, or a --arg value — is not being RUN, and must not fire the guard.  This is
# the defect that refused the filing of id:221f itself.
MENTIONS=(
  'git reset --hard'
  'git checkout -- .'
  'git restore .'
  'git clean -fd'
  'git stash drop'
)
for verb in "${MENTIONS[@]}"; do
    out="$(run_guard "$(quoted_mention "$verb")")"
    [[ -z "$out" ]] && pass "mention in a heredoc PAYLOAD does not fire: $verb" \
        || fail "id:221f(b): guard fired on a heredoc payload that merely quotes '$verb'"
done

# The real shape from the incident: appending a TODO line whose prose quotes a guarded
# command, through md-merge.py, with a command substitution ALSO present (so the
# tokenised path is unavailable and the raw scan is what decides).
INCIDENT="$(printf 'python3 meeting/md-merge.py update-ids TODO.md --allow-new <<EOF\n- [ ] the guard denies `%s` and `%s`, so filing this item was refused <!-- id:221f -->\nEOF\n' \
    'git reset --hard' 'git clean -fd')"
out="$(run_guard "$INCIDENT")"
[[ -z "$out" ]] && pass "the id:221f filing incident no longer refuses" \
    || fail "id:221f(b): filing a TODO item that quotes a guarded command is still refused"

# A guarded command MENTIONED inside a quoted ARGUMENT, in a command that also carries
# a command substitution (raw scan path).
QUOTED_ARG=(
  'git commit -m "revert with git reset --hard if this goes wrong" -m "$(date)"'
  'echo "never run git clean -fd here" > "$(mktemp)"'
  'grep -n "git checkout -- ." "$(pwd)/TODO.md"'
)
for cmd in "${QUOTED_ARG[@]}"; do
    out="$(run_guard "$cmd")"
    [[ -z "$out" ]] && pass "mention inside a quoted ARGUMENT does not fire: $cmd" \
        || fail "id:221f(b): guard fired on a merely-quoted mention: $cmd"
done

# ANCHORING must not become a hole: the same string in genuine COMMAND position, after
# every operator that ends a simple command, still denies.
for sep in ';' '&&' '||' '|' '&'; do
    cmd="$(printf 'echo "$(pwd)" %s git reset --hard' "$sep")"
    out="$(run_guard "$cmd")"
    is_deny "$out" && pass "anchor still catches a real command after '$sep'" \
        || fail "anchoring opened a hole: 'git reset --hard' after '$sep' was allowed"
done
# ...and after a newline, inside a subshell, and after a heredoc terminator.
ANCHORED_REAL=(
  'echo "$(pwd)"
git reset --hard'
  '( cd "$(pwd)" && git clean -fd )'
  'sudo git clean -fd "$(pwd)"'
  'GIT_DIR="$(pwd)/.git" git reset --hard'
)
for cmd in "${ANCHORED_REAL[@]}"; do
    out="$(run_guard "$cmd")"
    is_deny "$out" && pass "anchor still catches: $(head -1 <<< "$cmd")" \
        || fail "anchoring opened a hole: $(head -1 <<< "$cmd")"
done
out="$(run_guard "$(raw_case 'git reset --hard')")"
is_deny "$out" && pass "anchor still catches a real command AFTER a heredoc terminator" \
    || fail "heredoc-body stripping swallowed the command that follows the terminator"

# The stripper must remove only the BODY: a heredoc whose body is harmless prose but
# whose SAME LINE carries a real destructive command still denies.
out="$(run_guard "$(printf 'cat <<EOF > "$(mktemp)"; git clean -fd\nprose\nEOF\n')")"
is_deny "$out" && pass "a real command on the heredoc's own line still denies" \
    || fail "heredoc stripping over-reached onto the delimiter line"

# ── the guard's own docstring must not be the only record ─────────────────────
grep -q 'id:221f' "$GUARD" && pass "guard records id:221f in-file" \
    || fail "guard does not mention id:221f — the rationale has no anchor in the file"

# The 2026-08-22 unconditional-deny ruling is untouched by this item.
out="$(run_guard 'git reset --hard')"
grep -q 'UNCONDITIONAL' <<< "$out" \
    && pass "the unconditional-deny ruling survives the id:221f parity work" \
    || fail "the unconditional-deny ruling was weakened — id:221f must not touch it"

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All destructive-git-guard spelling/anchoring (id:221f) tests passed."
