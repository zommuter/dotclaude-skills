#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:3866 + id:8987, defect fixes; it always counts.)
#
# id:3866 — a PreToolUse hook that exits NON-ZERO is a *non-blocking* error: Claude Code
# surfaces stderr and RUNS the command.  So a crash in hooks/destructive-git-guard.py does
# not fail safe, it fails OPEN — the one input class that should never be trusted (a
# malformed payload) was exactly the class that bypassed the guard.  Four shapes crashed
# with exit 1 before the fix, pinned verbatim below, plus empty stdin and invalid JSON.
#
#   DISPOSITION for an unreadable payload: DEFER (exit 0, EMPTY stdout) + a one-line
#   stderr note.  A payload the hook cannot parse carries no command, so there is nothing
#   destructive to block; blocking would turn any hook-protocol change into a fleet-wide
#   outage in front of every Bash call.  The stderr note keeps it OBSERVABLE, not silent.
#
# id:8987 — a FRESH heartbeat marker whose runId is empty or non-string was silently
# ignored (is_pool_run ⇒ False ⇒ `continue`), inverting the guard's own "cannot tell ⇒
# block" doctrine.  It must now be a probe ERROR ⇒ ambiguous ⇒ BLOCK.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/destructive-git-guard.py"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"

# assert_defers <label> <payload>
#   exit 0, EMPTY stdout (nothing that could be read as a hook decision), non-empty stderr.
assert_defers() {
    local label="$1" payload="$2" rc=0
    : > "$TMP/err"
    set +e
    out="$( cd "$REPO" \
        && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
               HEARTBEAT_BASE="$TMP/no-such-heartbeats" \
               DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended \
               python3 "$GUARD" 2>"$TMP/err" <<< "$payload" )"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        fail "$label: exit $rc (a non-zero PreToolUse hook FAILS OPEN — id:3866)"
        return
    fi
    pass "$label: exit 0 (does not fail open)"
    if [[ -n "$out" ]]; then
        fail "$label: stdout should be empty, got: $out"
    else
        pass "$label: empty stdout (defers)"
    fi
    if [[ -s "$TMP/err" ]]; then
        pass "$label: observable — one-line stderr note ($(head -1 "$TMP/err"))"
    else
        fail "$label: deferral is SILENT — clause 2 requires a stderr note"
    fi
}

# ── (1) the four crashing shapes from the id:3866 report, verbatim ────────────
assert_defers "top-level JSON array"        '["a","b"]'
assert_defers "top-level JSON string"       '"just a string"'
assert_defers "tool_input is a string"      '{"tool_name":"Bash","tool_input":"notadict"}'
assert_defers "command is a number"         '{"tool_name":"Bash","tool_input":{"command":123}}'

# ── (2) the two other unreadable shapes clause 3 names ────────────────────────
assert_defers "empty stdin"                 ''
assert_defers "invalid JSON"                'not json{'

# ── (3) neighbouring malformed shapes must not crash either ───────────────────
assert_defers "command is a list"           '{"tool_name":"Bash","tool_input":{"command":["git","reset","--hard"]}}'
assert_defers "tool_input absent"           '{"tool_name":"Bash"}'
assert_defers "tool_input is a list"        '{"tool_name":"Bash","tool_input":[1,2]}'
assert_defers "whitespace-only stdin"       '   '

# ── (4) a well-formed payload is UNAFFECTED: the guard still blocks ───────────
set +e
out="$( cd "$REPO" \
    && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
           HEARTBEAT_BASE="$TMP/no-such-heartbeats" \
           DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended python3 "$GUARD" \
           <<< '{"session_id":"t","tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' )"
rc=$?
set -e
[[ $rc -eq 0 ]] && grep -q '"permissionDecision": *"deny"' <<< "$out" \
    && pass "well-formed destructive payload still DENIES (no regression)" \
    || fail "well-formed destructive payload no longer denies: rc=$rc out=$out"

# ── (5) find_violation NEVER raises, whatever it is handed (id:3866) ──────────
python3 - "$GUARD" <<'PY' && pass "find_violation never raises on hostile inputs" \
    || fail "find_violation raised"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for bad in (None, 123, 1.5, [], ["git"], {}, b"git reset --hard", object()):
    assert m.find_violation(bad) is None, f"non-str {bad!r} should be None"
# and a string that defeats tokenisation must still reach the conservative scan
assert m.find_violation("git reset --hard $(echo x)") == "git reset --hard"
PY

# ── (6) id:8987 — a FRESH marker with an unusable runId is a probe ERROR ──────
beat() {  # beat <dir> <name> <runId-json> <age_s>
    mkdir -p "$1"
    python3 -c "import json,sys,time; open(sys.argv[1],'w').write(json.dumps({'runId':json.loads(sys.argv[2]),'heartbeat_ts':time.time()-float(sys.argv[3])}))" \
        "$1/$2.json" "$3" "$4"
}
PAYLOAD='{"session_id":"t","tool_name":"Bash","tool_input":{"command":"git checkout -- ."}}'
guard() {  # guard <heartbeat-base>
    ( cd "$REPO" \
      && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
             -u DESTRUCTIVE_GIT_GUARD_CONTEXT \
             HEARTBEAT_BASE="$1" CLAUDE_CODE_ENTRYPOINT=cli python3 "$GUARD" <<< "$PAYLOAD" )
}
is_deny() { grep -q '"permissionDecision": *"deny"' <<< "$1"; }

for spec in 'empty-string:"":0' 'null:null:0' 'number:42:0' 'list:["a"]:0' 'whitespace:"   ":0'; do
    label="${spec%%:*}"; rest="${spec#*:}"; runid="${rest%:*}"; age="${rest##*:}"
    HB="$TMP/hb-$label"; beat "$HB" marker "$runid" "$age"
    out="$(guard "$HB")"
    if is_deny "$out" && grep -q 'heartbeat probe ERRORED' <<< "$out"; then
        pass "fresh marker with a $label runId ⇒ probe ERROR ⇒ BLOCK (id:8987)"
    else
        fail "fresh marker with a $label runId did not block: $out"
    fi
done

# A marker that is valid JSON but not an object is likewise unparseable ⇒ error.
HB="$TMP/hb-nonobj"; mkdir -p "$HB"; printf '[1,2]' > "$HB/marker.json"
out="$(guard "$HB")"
is_deny "$out" && pass "non-object heartbeat marker ⇒ BLOCK" \
    || fail "non-object heartbeat marker did not block: $out"

# ── (7) the STALE case is unchanged — staleness is checked BEFORE runId ───────
HB="$TMP/hb-stale-empty"; beat "$HB" marker '""' 99999
out="$(guard "$HB")"
[[ -z "$out" ]] && pass "STALE marker with an empty runId is still no signal ⇒ defer" \
    || fail "stale empty-runId marker should not block: $out"

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All destructive-git-guard malformed-payload tests passed (id:3866, id:8987)."
