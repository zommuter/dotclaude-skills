#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:6f62, a defect fix; it always counts.)
#
# id:6f62 — destructive-git-guard.py treated the non-pool `discovery-producer` daemon
# (fixed runId, 2100s TTL, id:54fc) as proof of an UNATTENDED relay run, so every
# INTERACTIVE session was hard-DENIED. The reproduction is pinned below verbatim:
#   CLAUDE_CODE_ENTRYPOINT=cli, RELAY_RUN_ID empty, only discovery-producer beating
#   ⇒ `git checkout -- .` must DEFER (silent) to the existing permissions.ask entry.
# Also pins: the refusal REPORTS which signal fired (not a compound assertion), it no
# longer teaches the repo-banned tree-wide `git add -A`, and the pool-run predicate is
# SHARED with relay/scripts/stop-request.sh rather than copied.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/destructive-git-guard.py"
LIB="$ROOT/relay/scripts/lib-pool-runs.py"
STOP="$ROOT/relay/scripts/stop-request.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/relay/scripts"
: > "$REPO/relay/scripts/integrate.sh"

PAYLOAD='{"session_id":"t","tool_name":"Bash","tool_input":{"command":"git checkout -- ."}}'

# beat <dir> <runId> [age_s] — write a heartbeat marker
beat() {
    mkdir -p "$1"
    python3 -c "import json,sys,time; open(sys.argv[1],'w').write(json.dumps({'runId':sys.argv[2],'heartbeat_ts':time.time()-float(sys.argv[3])}))" \
        "$1/$2.json" "$2" "${3:-0}"
}

# guard <heartbeat-base> <payload> [ENV=VAL ...] — run the hook, print stdout
guard() {
    local hb="$1" payload="$2"; shift 2
    ( cd "$REPO" \
      && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK -u CLAUDE_UNATTENDED \
             -u DESTRUCTIVE_GIT_GUARD_CONTEXT -u CLAUDE_CODE_ENTRYPOINT \
             HEARTBEAT_BASE="$hb" "$@" python3 "$GUARD" <<< "$payload" )
}

is_deny() { grep -q '"permissionDecision": *"deny"' <<< "$1"; }

# ── (1) THE REPRODUCTION (acceptance clause 2) ────────────────────────────────
HB_PRODUCER="$TMP/hb-producer"
beat "$HB_PRODUCER" discovery-producer
out="$(guard "$HB_PRODUCER" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
[[ -z "$out" ]] \
    && pass "cli + only discovery-producer beating ⇒ DEFERS to permissions.ask (id:6f62)" \
    || fail "REPRODUCTION: cli + discovery-producer should DEFER, got: $out"

# ── (2) real unattended signals still BLOCK (clause 3) ────────────────────────
out="$(guard "$HB_PRODUCER" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli RELAY_RUN_ID=relay-20260821-000000-6f62)"
if is_deny "$out"; then pass "RELAY_RUN_ID set ⇒ still BLOCKS"; else fail "RELAY_RUN_ID did not block"; fi
grep -q 'RELAY_RUN_ID=relay-20260821-000000-6f62' <<< "$out" \
    && pass "refusal NAMES the RELAY_RUN_ID trigger (clause 5)" \
    || fail "refusal does not name the RELAY_RUN_ID trigger"

HB_POOL="$TMP/hb-pool"
beat "$HB_POOL" relay-20260821-121212-4242
out="$(guard "$HB_POOL" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
if is_deny "$out"; then pass "live REAL pool heartbeat ⇒ still BLOCKS"; else fail "real pool heartbeat did not block"; fi
grep -q 'live pool heartbeat: relay-20260821-121212-4242' <<< "$out" \
    && pass "refusal NAMES the live pool runId (clause 5)" \
    || fail "refusal does not name the live pool runId"

# A real pool BESIDE the producer must still be seen.
beat "$HB_POOL" discovery-producer
out="$(guard "$HB_POOL" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
is_deny "$out" && pass "producer + real pool ⇒ BLOCKS (producer does not mask a pool)" \
    || fail "a real pool alongside the producer was missed"

# A STALE producer marker is still no signal.
HB_STALE="$TMP/hb-stale"
beat "$HB_STALE" discovery-producer 99999
out="$(guard "$HB_STALE" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
[[ -z "$out" ]] && pass "stale producer marker ⇒ defer" || fail "stale producer marker blocked"

# ── (3) ambiguity still resolves to BLOCK (clause 4) ──────────────────────────
out="$(guard "$HB_PRODUCER" "$PAYLOAD")"                       # no entrypoint at all
is_deny "$out" && pass "no entrypoint signal ⇒ BLOCK" || fail "no-entrypoint case did not block"
grep -q 'no CLAUDE_CODE_ENTRYPOINT signal' <<< "$out" \
    && pass "refusal names the missing-entrypoint trigger" || fail "missing-entrypoint trigger unnamed"

out="$(guard "$HB_PRODUCER" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=sdk-py)"
is_deny "$out" && pass "unrecognised entrypoint ⇒ BLOCK" || fail "unrecognised entrypoint did not block"
grep -q 'unrecognised CLAUDE_CODE_ENTRYPOINT=sdk-py' <<< "$out" \
    && pass "refusal names the unrecognised entrypoint" || fail "unrecognised entrypoint unnamed"

HB_BAD="$TMP/hb-bad"
mkdir -p "$HB_BAD"; printf 'not json' > "$HB_BAD/relay-x.json"
out="$(guard "$HB_BAD" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
is_deny "$out" && pass "heartbeat probe ERROR ⇒ BLOCK" || fail "heartbeat probe error did not block"
grep -q 'heartbeat probe ERRORED' <<< "$out" \
    && pass "refusal names the heartbeat probe error" || fail "heartbeat probe error unnamed"

out="$(guard "$TMP/no-such-dir" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
[[ -z "$out" ]] && pass "ABSENT heartbeat dir is no signal (not an error) ⇒ defer" \
    || fail "absent heartbeat dir should not be an error"

# ── (4) the refusal must not assert a compound reason (clause 5) ──────────────
out="$(guard "$HB_POOL" "$PAYLOAD" CLAUDE_CODE_ENTRYPOINT=cli)"
grep -q 'relay run id / live heartbeat detected' <<< "$out" \
    && fail "refusal still asserts the compound '(relay run id / live heartbeat detected)'" \
    || pass "refusal no longer asserts a compound reason"

# ── (5) remedy #1 must not teach the repo-banned tree-wide staging (clause 6) ─
if grep -qE 'git add +-A|git add +--all|git add +\.' <<< "$out"; then
    fail "refusal still teaches tree-wide staging (banned here, id:debf)"
else
    pass "refusal does not teach tree-wide staging"
fi
grep -q 'git add -- ' <<< "$out" && pass "refusal teaches SCOPED staging (git add -- <paths>)" \
    || fail "refusal does not show the scoped 'git add -- <paths>' form"

# ── (6) the path-scoped allow branch is UNCHANGED (clause 7) ──────────────────
set +e
out="$( cd "$REPO" && env -u RELAY_RUN_ID -u CLAUDE_RELAY_RUN_ID -u RELAY_AFK \
        -u CLAUDE_UNATTENDED -u DESTRUCTIVE_GIT_GUARD_CONTEXT HEARTBEAT_BASE="$HB_POOL" \
        python3 "$GUARD" \
        <<< '{"tool_name":"Bash","tool_input":{"command":"git checkout -- relay/scripts/integrate.sh"}}' )"
rc=$?
set -e
[[ $rc -eq 0 && -z "$out" ]] && pass "path-scoped revert: empty output, exit 0 (clause 7)" \
    || fail "path-scoped revert should be silent+0, got rc=$rc out=$out"

# ── (7) ONE shared predicate, not a second copy (clause 1) ────────────────────
[[ -f "$LIB" ]] && pass "shared predicate exists: relay/scripts/lib-pool-runs.py" \
    || fail "relay/scripts/lib-pool-runs.py is missing"
grep -q 'lib-pool-runs.py' "$GUARD" && pass "guard USES the shared predicate" \
    || fail "guard does not reference lib-pool-runs.py"
grep -q 'lib-pool-runs.py' "$STOP" && pass "stop-request.sh USES the shared predicate" \
    || fail "stop-request.sh does not reference lib-pool-runs.py"
# Neither caller may carry its own inline copy of the rule.
for f in "$GUARD" "$STOP"; do
    if grep -qE '!= *"discovery-producer"|!= *'\''discovery-producer'\''' "$f"; then
        fail "$(basename "$f") still carries an inline copy of the predicate"
    else
        pass "$(basename "$f") carries no inline copy of the predicate"
    fi
done

# id:4c14 — the assertion above pins ONE SPELLING, not the rule: a reintroduced copy
# written `== "discovery-producer": continue`, `not in ("discovery-producer",)` or
# `startswith("discovery")` would sail past it. Both callers mention the literal ONLY in
# COMMENTS today (guard: module docstring + a `#` comment + a function docstring;
# stop-request.sh: two `#` lines), so the strictly stronger assertion — ZERO NON-COMMENT
# occurrences of the literal in either caller — is available and already true. Comments
# ARE allowed (they explain why the predicate is shared); executable code is not.
python3 - "$GUARD" <<'PY' && pass "guard mentions 'discovery-producer' only in comments/docstrings (id:4c14)" \
    || fail "destructive-git-guard.py has a NON-COMMENT occurrence of 'discovery-producer'"
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
hits = []
for tok in tokenize.generate_tokens(io.StringIO(src).readline):
    if tok.type == tokenize.COMMENT:
        continue
    # Docstrings are triple-quoted; an inline predicate copy would use a plain literal,
    # so ONLY triple-quoted strings are exempt — `== "discovery-producer"` still counts.
    if tok.type == tokenize.STRING and tok.string.lstrip("rbuRBUf")[:3] in ('"""', "'''"):
        continue
    if "discovery-producer" in tok.string:
        hits.append((tok.start[0], tok.string.strip()[:60]))
if hits:
    print("NON-COMMENT occurrences:", hits)
    sys.exit(1)
PY
# stop-request.sh is shell: strip whole-line `#` comments and assert the same.
if grep -q 'discovery-producer' < <(sed 's/^[[:space:]]*#.*$//' "$STOP"); then
    fail "stop-request.sh has a NON-COMMENT occurrence of 'discovery-producer' (id:4c14)"
else
    pass "stop-request.sh mentions 'discovery-producer' only in comments (id:4c14)"
fi
grep -q 'lib-pool-runs.py' "$ROOT/Makefile" && pass "lib-pool-runs.py is in the Makefile manifest" \
    || fail "lib-pool-runs.py is not in the Makefile manifest"

# The predicate itself.
python3 - "$LIB" <<'PY' && pass "is_pool_run: producer False, real run True, empty False" \
    || fail "is_pool_run predicate is wrong"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lpr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.is_pool_run("relay-20260821-1-2") is True
assert m.is_pool_run("discovery-producer") is False
assert m.is_pool_run("") is False
assert m.is_pool_run(None) is False
PY

# stop-request.sh --list still filters the producer out.
HB_LIST="$TMP/hb-list"
beat "$HB_LIST" discovery-producer
beat "$HB_LIST" relay-20260821-999999-1
listout="$(HEARTBEAT_BASE="$HB_LIST" bash "$STOP" --list)"
grep -q 'relay-20260821-999999-1' <<< "$listout" \
    && pass "stop-request --list still reports the real pool" \
    || fail "stop-request --list lost the real pool: $listout"
grep -q 'discovery-producer' <<< "$listout" \
    && fail "stop-request --list leaked discovery-producer" \
    || pass "stop-request --list still excludes discovery-producer"

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All destructive-git-guard pool-signal tests passed (id:6f62)."
