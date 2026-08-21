#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:3a09 and always counts.)
# Hermetic tests for hooks/destructive-git-guard.py:
#   (1) every TREE-WIDE destructive form is refused under an unattended context
#   (2) a PATH-SCOPED revert of enumerated files is ALLOWED (the whole point)
#   (3) both context branches: unattended BLOCKS, confirmed-interactive DEFERS
#   (4) the AMBIGUOUS context resolves to the safe side (BLOCK)
#   (5) the refusal message TEACHES the alternatives (commit / scope / tar-copy)
# Also covers id:5218: rm-force-guard.sh is versioned here and in the Makefile manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/destructive-git-guard.py"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -f "$GUARD" ]] || { echo "FAIL: destructive-git-guard.py not found at $GUARD"; exit 1; }
pass "guard script exists"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A sandbox tree so os.path.isdir() sees a real directory for the <dir> forms.
REPO="$TMP/repo"
mkdir -p "$REPO/hooks" "$REPO/relay/scripts"
: > "$REPO/hooks/one-file.sh"
: > "$REPO/hooks/other-file.sh"

make_payload() {
    printf '{"session_id":"t","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# run_guard <context> <command> -> stdout of the hook
run_guard() {
    local ctx="$1" cmd="$2"
    ( cd "$REPO" \
      && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
             HEARTBEAT_BASE="$TMP/no-such-heartbeats" \
             DESTRUCTIVE_GIT_GUARD_CONTEXT="$ctx" \
             python3 "$GUARD" <<< "$(make_payload "$cmd")" )
}

is_deny() { grep -q '"permissionDecision": *"deny"' <<< "$1"; }

# ── (1) tree-wide forms are refused (unattended) ──────────────────────────────
BANNED=(
  'git checkout -- .'
  'git checkout .'
  'git checkout -- hooks'
  'git checkout -- relay/scripts/'
  'git checkout HEAD -- .'
  'git restore .'
  'git restore --staged .'
  'git restore hooks'
  'git reset --hard'
  'git reset --hard HEAD~1'
  'git clean -fd'
  'git clean -f'
  'git clean -d'
  'git clean -fdx'
  'git clean --force'
  'git stash drop'
  'git stash clear'
  'git stash drop stash@{0}'
  'git -C . checkout -- .'
  'echo hi && git checkout -- .'
)
for cmd in "${BANNED[@]}"; do
    out="$(run_guard unattended "$cmd")"
    if is_deny "$out"; then pass "blocked: $cmd"; else fail "NOT blocked (should be): $cmd"; fi
done

# ── (2) path-scoped and non-destructive forms are ALLOWED ─────────────────────
ALLOWED=(
  'git checkout -- hooks/one-file.sh'
  'git checkout -- hooks/one-file.sh hooks/other-file.sh'
  'git checkout -- ./hooks/one-file.sh'
  'git checkout HEAD -- hooks/one-file.sh'
  'git restore hooks/one-file.sh'
  'git restore --staged hooks/one-file.sh'
  'git checkout main'
  'git checkout -b feature/x'
  'git reset'
  'git reset --soft HEAD~1'
  'git reset --mixed'
  'git clean -n'
  'git clean --dry-run'
  'git stash'
  'git stash pop'
  'git stash list'
  'git status'
  'git commit -m "wip"'
)
for cmd in "${ALLOWED[@]}"; do
    out="$(run_guard unattended "$cmd")"
    if [[ -z "$out" ]]; then pass "allowed: $cmd"; else fail "BLOCKED (should be allowed): $cmd"; fi
done

# ── (3) context branches ──────────────────────────────────────────────────────
out="$(run_guard unattended 'git checkout -- .')"
is_deny "$out" && pass "unattended context BLOCKS" || fail "unattended context did not block"
grep -q 'UNATTENDED' <<< "$out" && pass "reason names the unattended context" \
    || fail "reason does not name the unattended context"

out="$(run_guard interactive 'git checkout -- .')"
[[ -z "$out" ]] && pass "interactive context DEFERS to permissions.ask (silent)" \
    || fail "interactive context should defer, got: $out"

# ── (4) ambiguity resolves to the SAFE side ───────────────────────────────────
out="$(run_guard ambiguous 'git checkout -- .')"
is_deny "$out" && pass "ambiguous context BLOCKS (safe side)" || fail "ambiguous context did not block"
grep -q 'AMBIGUOUS' <<< "$out" && pass "reason names the ambiguous context" \
    || fail "reason does not name the ambiguous context"

# Real (unforced) detection: no unattended signal AND no interactive signal ⇒ ambiguous ⇒ block.
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u CLAUDE_CODE_ENTRYPOINT -u DESTRUCTIVE_GIT_GUARD_CONTEXT \
        HEARTBEAT_BASE="$TMP/no-such-heartbeats" python3 "$GUARD" \
        <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "unforced: no signals at all ⇒ block" || fail "unforced no-signal case did not block"

# Real detection: RELAY_RUN_ID set ⇒ unattended ⇒ block.
out="$( cd "$REPO" && env -u DESTRUCTIVE_GIT_GUARD_CONTEXT RELAY_RUN_ID="relay-test-1" \
        CLAUDE_CODE_ENTRYPOINT="cli" HEARTBEAT_BASE="$TMP/no-such-heartbeats" \
        python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "unforced: RELAY_RUN_ID beats the cli entrypoint ⇒ block" \
    || fail "RELAY_RUN_ID did not force the unattended branch"

# Real detection: cli entrypoint + no unattended signal ⇒ interactive ⇒ defer.
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$TMP/no-such-heartbeats" python3 "$GUARD" \
        <<< "$(make_payload 'git checkout -- .')" )"
[[ -z "$out" ]] && pass "unforced: cli entrypoint alone ⇒ defer" || fail "cli-entrypoint case should defer"

# Real detection: a LIVE heartbeat marker ⇒ unattended ⇒ block even with cli entrypoint.
HB="$TMP/heartbeats"
mkdir -p "$HB"
python3 -c "import json,time,sys; open(sys.argv[1],'w').write(json.dumps({'runId':'relay-x','heartbeat_ts':time.time()}))" \
    "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "unforced: live heartbeat ⇒ block" || fail "live heartbeat did not force a block"

# A STALE heartbeat is not a live run ⇒ no unattended signal ⇒ cli ⇒ defer.
python3 -c "import json,time,sys; open(sys.argv[1],'w').write(json.dumps({'runId':'relay-x','heartbeat_ts':time.time()-99999}))" \
    "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
[[ -z "$out" ]] && pass "stale heartbeat is no signal ⇒ defer" || fail "stale heartbeat should not force a block"

# An UNPARSEABLE heartbeat marker ⇒ probe error ⇒ ambiguous ⇒ block.
printf 'not json' > "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "heartbeat probe error ⇒ ambiguous ⇒ block" \
    || fail "unreadable heartbeat marker should resolve to a block"

# ── (5) the refusal TEACHES ───────────────────────────────────────────────────
out="$(run_guard unattended 'git checkout -- .')"
for needle in 'COMMIT FIRST' 'SCOPE THE REVERT' 'tar' 'UNRECOVERABLE' 'id:3a09'; do
    grep -q -- "$needle" <<< "$out" && pass "refusal teaches: mentions '$needle'" \
        || fail "refusal message is missing '$needle'"
done

# Non-Bash payloads and non-git commands are ignored.
out="$( cd "$REPO" && env DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended python3 "$GUARD" \
        <<< '{"tool_name":"Edit","tool_input":{"command":"git checkout -- ."}}' )"
[[ -z "$out" ]] && pass "non-Bash tool payload ignored" || fail "non-Bash payload should be ignored"

out="$(run_guard unattended 'rm -rf /tmp/whatever')"
[[ -z "$out" ]] && pass "non-git command ignored" || fail "non-git command should be ignored"

# ── id:5218 — rm-force-guard.sh is versioned + in the Makefile manifest ───────
[[ -f "$ROOT/hooks/rm-force-guard.sh" ]] && pass "rm-force-guard.sh is versioned in hooks/" \
    || fail "hooks/rm-force-guard.sh is missing (id:5218)"
grep -q 'rm-force-guard.sh' "$ROOT/Makefile" && pass "rm-force-guard.sh is in the Makefile manifest" \
    || fail "rm-force-guard.sh is not in the Makefile manifest"
grep -q 'destructive-git-guard.py' "$ROOT/Makefile" && pass "destructive-git-guard.py is in the Makefile manifest" \
    || fail "destructive-git-guard.py is not in the Makefile manifest"
grep -q '^status-hooks:' "$ROOT/Makefile" && pass "make status-hooks target exists" \
    || fail "no status-hooks target in the Makefile"
grep -qE '^status:.*status-hooks' "$ROOT/Makefile" && pass "make status includes status-hooks" \
    || fail "make status does not include status-hooks"

# The guard must NOT have been wired into settings.json by this change (acceptance 5).
if [[ -f "$HOME/.claude/settings.json" ]]; then
    if grep -q 'destructive-git-guard' "$HOME/.claude/settings.json"; then
        fail "destructive-git-guard is wired into settings.json — that is the owner's step (acceptance 5)"
    else
        pass "destructive-git-guard is NOT wired into settings.json (owner's step)"
    fi
fi

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All destructive-git-guard tests passed."
