#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:3a09 and always counts.)
# Hermetic tests for hooks/destructive-git-guard.py:
#   (1) every TREE-WIDE destructive form is refused
#   (2) a PATH-SCOPED revert of enumerated files is ALLOWED (the whole point)
#   (3) the deny is UNCONDITIONAL — every context, including a forced `interactive`
#   (4) the context is REPORTED but never decisive
#   (5) the refusal message TEACHES the alternatives (commit / scope / tar-copy)
#   (6) the guard IS wired into settings.json
# Also covers id:5218: rm-force-guard.sh is versioned here and in the Makefile manifest.
#
# RE-SPECIFIED 2026-08-22 (owner ruling).  This file used to assert the opposite of (3)
# and (6): that a confirmed-interactive context DEFERS, and that the guard is NOT wired
# into settings.json.  Both are now wrong.  The owner wired it (settings.json), and after
# it deferred on a delegated agent's `git reset --hard` at ~02:00 — firing a
# permissions.ask prompt nobody was awake to answer — he ruled all five guarded ops
# UNCONDITIONAL DENY.  The hook governs the AGENT's Bash tool, not the human's terminal,
# so denying costs the human nothing.  The forced-`interactive` cases below are the exact
# regression that would reintroduce that incident; they must DENY.
# fails-against: rev a508a9f06373 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix Makefile, hooks/destructive-git-guard.py, hooks/rm-force-guard.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: a508a9f06373 -- Makefile hooks/destructive-git-guard.py hooks/rm-force-guard.sh
# fails-against-assertion: destructive-git-guard.py not found at

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

# ── (3) the deny is UNCONDITIONAL across every context ────────────────────────
# The five guarded ops, one canonical spelling each.
FIVE=(
  'git reset --hard'
  'git checkout -- .'
  'git restore .'
  'git clean -fd'
  'git stash drop'
)
for ctx in unattended ambiguous interactive; do
    for cmd in "${FIVE[@]}"; do
        out="$(run_guard "$ctx" "$cmd")"
        is_deny "$out" && pass "DENIED with context=$ctx: $cmd" \
            || fail "NOT denied with context=$ctx (must be unconditional): $cmd"
    done
done

# THE REGRESSION GUARD: a forced `interactive` is the exact configuration that produced
# the 2026-08-22 incident. It must decide NOTHING — no defer, no approval path.
for cmd in "${FIVE[@]}"; do
    out="$(run_guard interactive "$cmd")"
    is_deny "$out" \
        && pass "forced DESTRUCTIVE_GIT_GUARD_CONTEXT=interactive still DENIES: $cmd" \
        || fail "forced interactive context reintroduced the defer branch: $cmd"
done

# Also unconditional with a REAL cli entrypoint (how the incident session was started).
for cmd in "${FIVE[@]}"; do
    out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
            -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
            HEARTBEAT_BASE="$TMP/no-such-heartbeats" python3 "$GUARD" \
            <<< "$(make_payload "$cmd")" )"
    is_deny "$out" && pass "cli entrypoint + no unattended signal still DENIES: $cmd" \
        || fail "cli entrypoint let '$cmd' through — the defer branch is back"
done

# The 'interactive' VERDICT is gone from detect_context() itself — not merely unused.
# Asserted behaviourally (a source grep would trip over the prose that explains the
# removal, which is required, not a regression).
python3 - "$GUARD" <<'PY' && pass "detect_context never returns an 'interactive' verdict" \
    || fail "detect_context still produces an 'interactive' verdict"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
envs = [
    {}, {"CLAUDE_CODE_ENTRYPOINT": "cli"}, {"CLAUDE_CODE_ENTRYPOINT": "sdk-py"},
    {"DESTRUCTIVE_GIT_GUARD_CONTEXT": "interactive"},
    {"DESTRUCTIVE_GIT_GUARD_CONTEXT": "interactive", "CLAUDE_CODE_ENTRYPOINT": "cli"},
    {"RELAY_RUN_ID": "relay-1"}, {"RELAY_AFK": "1"},
]
for e in envs:
    e = dict(e); e.setdefault("HEARTBEAT_BASE", "/nonexistent-heartbeats")
    ctx, trigger = m.detect_context(e)
    assert ctx in ("unattended", "ambiguous"), f"{e} -> {ctx!r}"
# A forced 'interactive' must be reported as IGNORED, not silently swallowed.
_, trig = m.detect_context({"DESTRUCTIVE_GIT_GUARD_CONTEXT": "interactive",
                            "HEARTBEAT_BASE": "/nonexistent-heartbeats"})
assert "IGNORED" in trig, trig
PY

out="$(run_guard unattended 'git checkout -- .')"
grep -q 'UNATTENDED' <<< "$out" && pass "reason names the unattended context" \
    || fail "reason does not name the unattended context"

# ── (4) the context is REPORTED, never decisive ───────────────────────────────
out="$(run_guard ambiguous 'git checkout -- .')"
is_deny "$out" && pass "ambiguous context BLOCKS (safe side)" || fail "ambiguous context did not block"
grep -q 'AMBIGUOUS' <<< "$out" && pass "reason names the ambiguous context" \
    || fail "reason does not name the ambiguous context"
grep -q 'UNCONDITIONAL' <<< "$out" \
    && pass "refusal states the deny is UNCONDITIONAL (not context-dependent)" \
    || fail "refusal does not say the deny is unconditional"
# It must NOT advertise an interactive escape hatch that no longer exists.
grep -q 'DESTRUCTIVE_GIT_GUARD_CONTEXT=interactive if you are certain' <<< "$out" \
    && fail "refusal still advertises the removed interactive escape hatch" \
    || pass "refusal no longer advertises an interactive escape hatch"

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

# Real detection: cli entrypoint alone is NOT evidence a human is present — it says how
# the session STARTED. It must block, and it must say so rather than claim presence.
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$TMP/no-such-heartbeats" python3 "$GUARD" \
        <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "unforced: cli entrypoint alone ⇒ block (it is not presence)" \
    || fail "cli-entrypoint case should block"
grep -q 'NOT evidence a human is present' <<< "$out" \
    && pass "refusal does not read cli-entrypoint as human presence" \
    || fail "refusal still treats CLAUDE_CODE_ENTRYPOINT=cli as a presence signal"

# Real detection: a LIVE heartbeat marker ⇒ unattended ⇒ block even with cli entrypoint.
HB="$TMP/heartbeats"
mkdir -p "$HB"
python3 -c "import json,time,sys; open(sys.argv[1],'w').write(json.dumps({'runId':'relay-x','heartbeat_ts':time.time()}))" \
    "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "unforced: live heartbeat ⇒ block" || fail "live heartbeat did not force a block"

# A STALE heartbeat is not a live run ⇒ contributes NO unattended signal. The deny is
# unconditional either way, so what is pinned here is the ATTRIBUTION: a stale marker
# must not be reported as a live pool run.
python3 -c "import json,time,sys; open(sys.argv[1],'w').write(json.dumps({'runId':'relay-x','heartbeat_ts':time.time()-99999}))" \
    "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "stale heartbeat: still blocks (unconditional)" \
    || fail "stale-heartbeat case did not block"
grep -q 'live pool heartbeat' <<< "$out" \
    && fail "a STALE marker was reported as a live pool heartbeat" \
    || pass "stale heartbeat is not reported as a live run"

# An UNPARSEABLE heartbeat marker ⇒ probe error ⇒ ambiguous ⇒ block.
printf 'not json' > "$HB/relay-x.json"
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT CLAUDE_CODE_ENTRYPOINT="cli" \
        HEARTBEAT_BASE="$HB" python3 "$GUARD" <<< "$(make_payload 'git checkout -- .')" )"
is_deny "$out" && pass "heartbeat probe error ⇒ ambiguous ⇒ block" \
    || fail "unreadable heartbeat marker should resolve to a block"

# ── (5) the refusal TEACHES ───────────────────────────────────────────────────
# Every deny payload teaches, in every context and for every one of the five ops —
# the unconditional deny must not have become a bare refusal.
for ctx in unattended ambiguous interactive; do
    for cmd in "${FIVE[@]}"; do
        out="$(run_guard "$ctx" "$cmd")"
        missing=""
        for needle in 'COMMIT FIRST' 'SCOPE THE REVERT' 'tar' 'UNRECOVERABLE' 'id:3a09'; do
            grep -q -- "$needle" <<< "$out" || missing="$missing $needle"
        done
        [[ -z "$missing" ]] && pass "refusal teaches (context=$ctx): $cmd" \
            || fail "refusal for '$cmd' (context=$ctx) is missing:$missing"
    done
done

# Non-Bash payloads and non-git commands are ignored.
out="$( cd "$REPO" && env DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended python3 "$GUARD" \
        <<< '{"tool_name":"Edit","tool_input":{"command":"git checkout -- ."}}' )"
[[ -z "$out" ]] && pass "non-Bash tool payload ignored" || fail "non-Bash payload should be ignored"

out="$(run_guard unattended 'rm -rf /tmp/whatever')"
[[ -z "$out" ]] && pass "non-git command ignored" || fail "non-git command should be ignored"

# Non-destructive git commands stay ignored in EVERY context — the unconditional deny
# must not have widened into "block anything that says git".
for ctx in unattended ambiguous interactive; do
    for cmd in 'git reset --soft HEAD~1' 'git checkout main' 'git status'; do
        out="$(run_guard "$ctx" "$cmd")"
        [[ -z "$out" ]] && pass "still ignored with context=$ctx: $cmd" \
            || fail "non-destructive command blocked with context=$ctx: $cmd"
    done
done

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

# ── (6) the guard IS wired into settings.json ─────────────────────────────────
# RE-SPECIFIED 2026-08-22. The superseded assertion demanded the OPPOSITE ("that is the
# owner's step, acceptance 5"). The owner took that step; acceptance 5 is discharged, and
# the guard has since prevented a real destructive command. An unwired guard is now the
# regression. Read-only check — this test never writes settings.json.
if [[ -f "$HOME/.claude/settings.json" ]]; then
    if grep -q 'destructive-git-guard' "$HOME/.claude/settings.json"; then
        pass "destructive-git-guard IS wired into settings.json"
    else
        fail "destructive-git-guard is NOT wired into settings.json — the guard is inert"
    fi
else
    pass "no ~/.claude/settings.json on this machine — wiring check not applicable"
fi

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All destructive-git-guard tests passed."
