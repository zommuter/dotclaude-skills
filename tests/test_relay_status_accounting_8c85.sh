#!/usr/bin/env bash
# roadmap:8c85 — RELAY_STATUS.md must account for EVERY own repo, every round, in exactly one
# section, with a reason. Today four non-dispatch classes vanish and the file reports a false
# clean (id:4347 no-silent-swallow, at the fleet's primary observability surface).
#
# WHAT THE CODE ACTUALLY DOES (verified in relay-loop.js at HEAD, 2026-08-10 — the TODO item's
# hypothesised mechanism "the debounced scheduleStatusWrite is never force-flushed at run end"
# is WRONG and this spec does not encode it: `await statusTail` at relay-loop.js:3020 DOES flush
# the tail before the run returns). The real mechanisms are two, and they are different bugs:
#
#   1. `snapshotState()` (relay-loop.js:~406) DROPS the two fields the renderer reads for the
#      Blocked section. `buildRelayStatus` reads `state.surfaced` and `state.handbacks`
#      (:291, :329) and `writeRelayStatus` reads them again (:375); `snapshotState` copies
#      `blocked` — a field NOTHING reads — and copies neither `surfaced` nor `handbacks`. Since
#      id:cb50 routed every write through the snapshot, EVERY status write renders
#      `## Blocked / HANDBACKs _(none)_` and `blocked=0`, no matter what happened. This single
#      bug explains three of the four reported classes at once:
#        (a) dirty-deferred — classify-verdict.sh ranks a non-lock-dirty tree `blocked`
#            (:151), discover-repo.sh routes `blocked` to `surfaced` (:135) → dropped;
#        (b) in-flight-suppressed — reconcile's repo-level classes are SUBSTITUTIVE and return
#            `surfaced` verbatim (discover-repo.sh:94-101) → dropped;
#        (d) HANDBACK — `state.handbacks` accumulates real handbacks (:2210/2233/2459/2582/
#            2605/2763) → dropped. Hence the observed `dispatched=2 / completed=1 / blocked=0`
#            with `## Blocked / HANDBACKs _(none)_` while a real dotclaude-skills handback
#            existed. It is a REGRESSION of id:1735, re-flagged by id:4f9b, recurring 2026-08-10.
#   2. `human`-verdict units are pulled out of `actionable` (relay-loop.js:~1741) and are then
#      added to NEITHER `state.queued` NOR `state.skipped`. The comment at :1823-1825 claims
#      they "surface in RELAY_STATUS skipped as 'human (surface-only: filing dispatched)'" —
#      no code does that. Class (c): zkWhale was classified `human` and has zero mentions.
#
# WHAT THIS SPEC REQUIRES:
#   • A PURE, testable accounting module `relay/scripts/status-accounting.mjs` (the house
#     pattern for logic that must be verified but lives inside the un-importable Workflow
#     module — cf. prompt-size-gate.mjs, round-plan.mjs, handback-summary.mjs).
#   • A mechanical `own_count == sum(sections)` invariant that FAILS LOUDLY and names the
#     missing repos, so a repo can never again fall out of the accounting silently.
#   • The two wiring fixes above, plus the Claims renderer printing a keyed claim's `key`.
#
# HONEST COVERAGE LIMIT (same precedent as tests/test_prompt_size_gate_4f9b.sh, id:1735/id:2ec4):
# relay-loop.js is a Workflow module that cannot be imported or executed in this harness. The
# behavioural cases below drive the PURE module through node. Section (E) is a STRUCTURAL
# check of relay-loop.js source — it pins that the fields exist and the invariant is invoked;
# it does not prove a live pool round emits a complete file end-to-end. Section (F) IS
# behavioural: relay-status-publish.sh is a plain script and runs hermetically against
# $CLAIM_BASE / $FABLES_CONFIG overrides.
#
# Hermetic: mktemp -d, HOME/CLAIM_BASE/FABLES_CONFIG overridden, node + git + jq only, no
# network, never touches ~/.claude or ~/.config/relay.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$SRC_DIR/relay/scripts/status-accounting.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
PUBLISH="$SRC_DIR/relay/scripts/relay-status-publish.sh"
CLAIM="$SRC_DIR/relay/scripts/claim.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/logs"

# ── (A)+(B)+(C)+(D) BEHAVIOUR of the pure accounting module. ────────────────────────────────
if [[ ! -f "$MOD" ]]; then
  bad "id:8c85: relay/scripts/status-accounting.mjs does not exist — there is no pure, testable owner of the own_count == sum(sections) invariant"
else
  cat > "$TMP/drive.mjs" <<NODE
import { accountedRepos, unaccountedRepos, doubleCountedRepos, assertStatusAccounting, ACCOUNTING_SECTIONS } from 'file://$MOD'
const out = []
const say = (k, v) => out.push(k + '=' + (v ? '1' : '0'))

// The five sections RELAY_STATUS.md renders per-repo rows into. "blocked" is the rendered
// union of state.surfaced + state.handbacks (buildRelayStatus:291) — the module must know that.
say('sections_exact', JSON.stringify([...ACCOUNTING_SECTIONS].sort()) ===
    JSON.stringify(['blocked','completed','inFlight','queued','skipped']))

// ── (A) Replay of run relay-20260810-103858-20326, with a COMPLETE state: nothing missing. ──
const own = ['dotclaude-skills','loderite','puzzle-pwa','yinyang-puzzle','zkm-stt','zkWhale','filler-a','filler-b']
const complete = {
  inFlight:  [{ repo: 'filler-a', mode: 'execute', agentId: 'unit-1' }],
  completed: [{ repo: 'filler-b', mode: 'execute', ckptTag: 't', pushStatus: 'ok' }],
  queued:    [],
  // dirty-deferred (a) + in-flight-suppressed (b) both arrive as discovery 'surfaced' entries
  surfaced:  [
    { repo: 'puzzle-pwa',     reason: 'dirty working tree (.changelog.lock)' },
    { repo: 'yinyang-puzzle', reason: 'dirty working tree (.changelog.lock)' },
    { repo: 'zkm-stt',        reason: 'dirty working tree' },
    { repo: 'loderite',       reason: 'in-flight: claimed by another live run' },
  ],
  // (d) the real HANDBACK the status file said did not exist
  handbacks: [{ repo: 'dotclaude-skills', reason: 'execute handback', worktreePath: '/w' }],
  // (c) the human verdict, surfaced with its routing reason instead of vanishing
  skipped:   [{ repo: 'zkWhale', reason: 'human (surface-only backlog: 5 surface items, 0 promotable — filing dispatched)' }],
}
say('complete_nothing_missing', unaccountedRepos(own, complete).length === 0)
say('complete_assert_ok', assertStatusAccounting(own, complete).ok === true)
say('complete_accounts_all_8', new Set(accountedRepos(complete)).size === 8)
say('complete_no_double_count', doubleCountedRepos(complete).length === 0)
// The owner's stated invariant, literally: own_count == sum of the section row counts.
const sum = complete.inFlight.length + complete.completed.length + complete.queued.length +
            complete.surfaced.length + complete.handbacks.length + complete.skipped.length
say('complete_own_eq_sum', own.length === sum)

// ── (B) The OBSERVED (buggy) state: Blocked dropped + human never filed. The invariant must
//        DETECT it and name every missing repo — loudly, never a silent pass. ──────────────
const observed = { inFlight: complete.inFlight, completed: complete.completed, queued: [],
                   surfaced: [], handbacks: [], skipped: [] }   // exactly what snapshotState produces today
const miss = unaccountedRepos(own, observed)
say('observed_detects_6', miss.length === 6)
for (const r of ['dotclaude-skills','loderite','puzzle-pwa','yinyang-puzzle','zkm-stt','zkWhale'])
  say('observed_names_' + r, miss.includes(r))
const res = assertStatusAccounting(own, observed)
say('observed_assert_not_ok', res.ok === false)
say('observed_message_names_repos', ['loderite','zkWhale','puzzle-pwa'].every(r => String(res.message).includes(r)))
say('observed_message_names_id', String(res.message).includes('8c85'))
say('observed_message_nonempty', String(res.message).trim().length > 20)

// ── (C) Exactly ONE section per repo — own_count == sum(sections) is violated by a duplicate
//        just as much as by an omission. ──────────────────────────────────────────────────
const dup = { inFlight: [{ repo: 'a' }], completed: [], queued: [{ repo: 'a', verdict: 'execute' }],
              surfaced: [], handbacks: [], skipped: [] }
say('duplicate_detected', doubleCountedRepos(dup).includes('a'))
say('duplicate_assert_not_ok', assertStatusAccounting(['a'], dup).ok === false)

// ── (D) Fail-safe on absent/empty inputs — the invariant must never throw inside the loop. ──
say('empty_own_ok', unaccountedRepos([], {}).length === 0 && assertStatusAccounting([], {}).ok === true)
say('missing_fields_no_throw', (() => { try { unaccountedRepos(['x'], {}); return true } catch { return false } })())
say('null_state_no_throw', (() => { try { assertStatusAccounting(['x'], null); return true } catch { return false } })())

console.log(out.join('\n'))
NODE
  if res=$(node "$TMP/drive.mjs" 2>&1); then
    echo "$res" | sed 's/^/    /'
    while IFS='=' read -r k v; do
      [[ -z "$k" ]] && continue
      [[ "$v" == "1" ]] && ok "accounting: $k" || bad "id:8c85: accounting case failed — $k"
    done <<< "$res"
  else
    echo "$res" | sed 's/^/    /'
    bad "id:8c85: status-accounting.mjs does not expose the required API (accountedRepos / unaccountedRepos / doubleCountedRepos / assertStatusAccounting / ACCOUNTING_SECTIONS)"
  fi
fi

# ── (E) STRUCTURAL — relay-loop.js source. Stated limit: the Workflow module cannot be
#        imported or run here, so these pin the shape, not an end-to-end round. ────────────

# (E1) The GENERIC drift check that would have caught this bug class by itself: every
#      `state.X` field the RENDERER reads must be a field the SNAPSHOT actually copies.
if python3 - "$JS" <<'PY'
import re, sys
src = open(sys.argv[1]).read()

def body(name):
    i = src.index('function %s(' % name)
    depth = 0; started = False
    for j in range(i, len(src)):
        if src[j] == '{': depth += 1; started = True
        elif src[j] == '}':
            depth -= 1
            if started and depth == 0: return src[i:j+1]
    return src[i:]

readers = body('buildRelayStatus') + body('writeRelayStatus')
snap = body('snapshotState')

# Fields read off the state object by the renderers (ignore method calls like state.foo()).
read = set()
for m in re.finditer(r'\bstate\.([A-Za-z_]\w*)', readers):
    read.add(m.group(1))
# Fields the snapshot writes into the returned literal: `key: ...` or bare shorthand `key,`.
# Keys may be packed several per line, so anchor on `{`/`,`/newline rather than line start.
# A `s.foo` read is preceded by `.` and never matches.
written = set(re.findall(r'(?<=[{,\n])\s*([A-Za-z_]\w*)\s*[:,]', snap))

missing = sorted(read - written)
if missing:
    print('renderer reads fields the snapshot never copies: ' + ', '.join(missing))
    sys.exit(1)
PY
then
  ok "relay-loop.js: every state field the renderer reads is carried by snapshotState"
else
  bad "id:8c85: snapshotState DROPS renderer-read state fields (see the line above) — every RELAY_STATUS write renders those sections empty regardless of what happened"
fi

# (E2) Named explicitly, because these two are the observed false clean.
snapbody=$(python3 - "$JS" <<'PY'
import sys
src = open(sys.argv[1]).read()
i = src.index('function snapshotState(')
d = 0; s = False
for j in range(i, len(src)):
    if src[j] == '{': d += 1; s = True
    elif src[j] == '}':
        d -= 1
        if s and d == 0: print(src[i:j+1]); break
PY
)
grep -q 'surfaced' <<<"$snapbody" \
  && ok "snapshotState carries \`surfaced\` (the dirty-deferred + in-flight-suppressed rows)" \
  || bad "id:8c85: snapshotState does not carry \`surfaced\` — classes (a) and (b) are erased before the write"
grep -q 'handbacks' <<<"$snapbody" \
  && ok "snapshotState carries \`handbacks\` (class (d), the id:1735 regression)" \
  || bad "id:8c85: snapshotState does not carry \`handbacks\` — the Blocked section is structurally always _(none)_"

# (E3) human-verdict units must land in an accounting section, not be dropped. Comments are
#      stripped first: relay-loop.js already CLAIMS this in prose while doing nothing.
if python3 - "$JS" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
start = src.index('state.queued = [')
end   = src.index('state.skipped =', start)
end   = src.index('\n', src.index('\n', end) + 1)
block = re.sub(r'//.*', '', src[start:end])
sys.exit(0 if 'human' in block.lower() else 1)
PY
then
  ok "human-verdict units are folded into a rendered section (queued/skipped), not dropped"
else
  bad "id:8c85: human-verdict units reach NO section — relay-loop.js:1823-1825 claims in a COMMENT that they 'surface in RELAY_STATUS skipped', but no code does it (class (c), zkWhale)"
fi

# (E4) The invariant must actually be WIRED — a pure module nothing calls is the
#      [[relay-builtgreen-but-unreferenced]] failure mode.
grep -qF 'assertStatusAccounting' "$JS" \
  && ok "relay-loop.js invokes assertStatusAccounting (the invariant is wired, not merely built)" \
  || bad "id:8c85: relay-loop.js never calls assertStatusAccounting — an unreferenced module is not an invariant"
# The own-repo list exists TODAY only as a local inside the discovery function (:1267), out of
# scope at status-write / run-end time. The invariant needs it on the run state.
grep -qF 'state.ownRepos' "$JS" \
  && ok "the own-repo list is on the run state (in scope wherever the invariant fires)" \
  || bad "id:8c85: the own-repo list is a discovery-function local only (relay-loop.js:1267) — it is out of scope at status-write/run-end, so own_count == sum(sections) cannot be asserted there"

# ── (F) BEHAVIOURAL — the Claims renderer must name a KEYED claim by its key. A keyed claim
#        (e.g. the meeting advisory `meeting:<repo>`) has repo:"" and item:"", so the current
#        `.repo // .item` fallback renders `-   mode=handoff  run=…` with an empty subject. ─
if [[ -x "$PUBLISH" && -x "$CLAIM" ]] && command -v jq >/dev/null 2>&1; then
  export CLAIM_BASE="$TMP/relaycfg" FABLES_CONFIG="$TMP/relaycfg"
  export CLAIM_LOG="$TMP/claim.log" RELAY_STATE_WRITE_LOG="$TMP/statewrite.log"
  mkdir -p "$CLAIM_BASE"
  "$CLAIM" acquire 'meeting:loderite' --run 'relay-testrun' --mode handoff >/dev/null 2>&1 || true
  printf '# RELAY_STATUS — test\n\n## Run progress\n- round=1\n' \
    | "$PUBLISH" --path "$TMP/RELAY_STATUS.md" --run 'relay-testrun' --events-path "$TMP/events.jsonl" >/dev/null 2>&1 || true
  if [[ -f "$TMP/RELAY_STATUS.md" ]]; then
    claimline=$(sed -n '/^## Claims (live)/,/^## /p' "$TMP/RELAY_STATUS.md" | grep '^- ' | head -1 || true)
    if [[ -z "$claimline" ]]; then
      bad "id:8c85: the live keyed claim was not rendered in '## Claims (live)' at all"
    elif grep -qF 'meeting:loderite' <<<"$claimline"; then
      ok "Claims renderer names a keyed claim by its key: $claimline"
    else
      bad "id:8c85: Claims renderer printed '$claimline' — a keyed claim (repo:\"\") must fall back to \`key\`, not to an empty subject"
    fi
  else
    bad "id:8c85: relay-status-publish.sh wrote no file (hermetic run failed) — cannot verify the Claims renderer"
  fi
else
  bad "id:8c85: relay-status-publish.sh / claim.sh / jq unavailable — Claims renderer case NOT verified (not a pass)"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: RELAY_STATUS.md accounts for every own repo in exactly one section (id:8c85)"
