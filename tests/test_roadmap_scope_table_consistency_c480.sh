#!/usr/bin/env bash
# roadmap:c480
# RED SPEC for id:c480 — the id:6b35 scope table is STALE, and nothing notices when it
# drifts (meeting docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md).
#
# THE LIVE DEFECT: ROADMAP.md's id:6b35 block carries an
#   "**OUT of scope — the 7 NON-eligible hops MUST STAY `model:'haiku'`**"
# bullet that lists `release:`. That stopped being true when id:f7d3 split and converted
# that hop — relay-loop.js now dispatches `label: `release:…`` as `model: 'bash'`, and
# tests/test_release_hop_mechanical_f7d3.sh asserts exactly that. An implementer working
# the table faithfully would "restore" model:'haiku' and re-introduce the invariant
# violation f7d3 removed.
#
# THE DURABLE FIX is not the text edit — it is the missing CHECK. The table is a ledger
# claim about code; it drifted the moment the code changed and nothing detected it for a
# week. So this spec pins BOTH: (§1) the specific contradiction is gone, and (§2-§5) a
# consistency rule exists in relay/scripts/roadmap-lint.sh that fires on the drift.
#
# CONTRACT for the rule (implement it INSIDE roadmap-lint.sh — do not add a new one-off
# scanner; this repo's "use existing tools" rule):
#   * It runs on the DEFAULT lint invocation (`roadmap-lint.sh <roadmap.md>`), so every
#     existing caller inherits it — no opt-in flag to forget (id:de36: a check nothing
#     invokes is not a check).
#   * It locates relay-loop.js as `<dir-of-roadmap>/relay/scripts/relay-loop.js`.
#     ABSENT ⇒ skip LOUDLY (a message), never silently.
#   * Hop names are PARSED FROM THE ROADMAP ITSELF — the `| \`hop\` | … |` rows of the
#     CONVERTIBLE table, and the backticked names in the OUT-of-scope bullet. A hardcoded
#     hop list is the same drift one level down and §5 fails it.
#   * For each hop the ROADMAP claims MUST STAY `model:'haiku'`: if relay-loop.js
#     dispatches a matching `label:` with `model: 'bash'` ⇒ VIOLATION.
#     For each hop the ROADMAP lists as CONVERTIBLE (`model:'bash'`): if relay-loop.js
#     dispatches it as `model: 'haiku'` ⇒ VIOLATION. Both directions.
#   * A violation prints a line containing the token SCOPE-TABLE-DRIFT and the hop name,
#     and exits NON-ZERO (this is a factual code/ledger contradiction, not a doctrine
#     WARN — it must not need --strict).
#
# Hermetic: fixtures in mktemp -d; no ~/.claude, no network, no writes to the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
ROADMAP="$ROOT/ROADMAP.md"
LOOP="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]]  || fail "roadmap-lint.sh not found/executable at $LINT"
[[ -f "$ROADMAP" ]] || fail "ROADMAP.md not found at $ROADMAP"
[[ -f "$LOOP" ]]  || fail "relay-loop.js not found at $LOOP"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── §1 the LIVE contradiction is gone ─────────────────────────────────────────────────────
# Establish the code side first, so the assertion cannot pass by the code having changed
# in the other direction without anyone noticing.
#
# The mechanical model is no longer a literal at every hop: commit 490ac6e (id:4239)
# replaced the last hardcoded `model: 'bash'` sites — including this one — with the
# MECH_MODEL indirection (`const MECH_MODEL = MECH_FALLBACK === 'fallback-haiku' ?
# 'haiku' : 'bash'`). So "f7d3 still holds" means the release hop dispatches EITHER a
# literal `model: 'bash'` OR `model: MECH_MODEL`; what a genuine f7d3 revert would look
# like is a literal `model: 'haiku'` (or no mechanical dispatch at all), and that is
# still caught below.
loop_release_is_bash=0
release_dispatch="$(grep -E "label: *\`release:" "$LOOP" | head -1 || true)"
printf '%s\n' "$release_dispatch" | grep -qE "model: *('bash'|MECH_MODEL)" && loop_release_is_bash=1

# The ROADMAP side: the OUT-of-scope MUST-STAY-haiku bullet in the id:6b35 block.
outbullet="$(grep -F 'OUT of scope' "$ROADMAP" | grep -F "MUST STAY \`model:'haiku'\`" || true)"
[[ -n "$outbullet" ]] \
  || fail "(1) could not locate the id:6b35 \"OUT of scope … MUST STAY model:'haiku'\" bullet in ROADMAP.md — if it was renamed, this spec and the lint rule must be re-anchored, not deleted"

roadmap_says_release_haiku=0
printf '%s\n' "$outbullet" | grep -qF '`release:`' && roadmap_says_release_haiku=1

if (( loop_release_is_bash == 1 && roadmap_says_release_haiku == 1 )); then
  fail "(1) LIVE CONTRADICTION: relay-loop.js dispatches a 'release:' label mechanically (model:'bash'/MECH_MODEL, id:f7d3) while the id:6b35 OUT-of-scope bullet still lists \`release:\` as MUST STAY model:'haiku'"
fi
(( loop_release_is_bash == 1 )) \
  || fail "(1) precondition lost: the 'release:'-labelled dispatch in relay-loop.js is neither model:'bash' nor model:MECH_MODEL — id:f7d3 appears to have been reverted; fix that before touching the table. Line found: ${release_dispatch:-<none>}"
pass "(1) the id:6b35 OUT-of-scope bullet no longer contradicts relay-loop.js's release: hop"

# ── fixture builder ───────────────────────────────────────────────────────────────────────
# Builds $1 = a repo-shaped dir with ROADMAP.md + relay/scripts/relay-loop.js.
#   $2 = the OUT-of-scope (MUST STAY haiku) hop list, backticked, comma separated
#   $3 = the CONVERTIBLE table rows (already markdown)
#   $4 = the relay-loop.js dispatch lines
mkfixture() {
  local dir="$1" outhops="$2" rows="$3" dispatches="$4"
  rm -rf "$dir"; mkdir -p "$dir/relay/scripts"
  {
    echo '# ROADMAP'
    echo
    echo '## Items'
    echo
    echo '- [ ] [ROUTINE] **Fixture scope-table item** <!-- id:6b35 -->'
    echo '  - **Scope — the CONVERTIBLE hops**:'
    echo '    | Hop label | line | command | note |'
    echo '    |---|---|---|---|'
    printf '%s\n' "$rows"
    echo "  - **OUT of scope — the NON-eligible hops MUST STAY \`model:'haiku'\`**: $outhops."
    echo '  - **Done-check**: fixture.'
  } >"$dir/ROADMAP.md"
  {
    echo '// fixture relay-loop.js'
    printf '%s\n' "$dispatches"
  } >"$dir/relay/scripts/relay-loop.js"
}

CONSISTENT_ROWS='    | `file-surface:${repo}` | ~1506 | `file-surface-decisions.sh` | fire-and-forget |'

# ── §2 CONSISTENT fixture ⇒ no drift complaint, exit 0 ───────────────────────────────────
mkfixture "$TMP/ok" '`discover-prelude`' "$CONSISTENT_ROWS" \
"    agent(p, { label: 'discover-prelude', model: 'haiku' })
    agent(p, { label: \`file-surface:\${repo}\`, model: 'bash' })"
if out="$("$LINT" "$TMP/ok/ROADMAP.md" 2>&1)"; then :; else
  fail "(2) a CONSISTENT scope table must lint clean (exit 0); got:
$out"
fi
printf '%s\n' "$out" | grep -q 'SCOPE-TABLE-DRIFT' \
  && fail "(2) the rule fired on a CONSISTENT fixture (false positive):
$out"
pass "(2) a consistent scope table lints clean and emits no SCOPE-TABLE-DRIFT"

# ── §3 direction A: table says MUST-STAY-haiku, code says bash ⇒ VIOLATION ───────────────
# This is the live id:c480 defect, reproduced as a fixture so it can never silently return.
mkfixture "$TMP/badA" '`release:`' "$CONSISTENT_ROWS" \
"    agent(p, { label: \`release:\${repo}:claim\`, model: 'bash' })
    agent(p, { label: \`file-surface:\${repo}\`, model: 'bash' })"
if out="$("$LINT" "$TMP/badA/ROADMAP.md" 2>&1)"; then
  fail "(3) lint exited 0 on table-says-haiku/code-says-bash — the drift must be a hard non-zero, not a --strict WARN. Output:
$out"
fi
printf '%s\n' "$out" | grep -q 'SCOPE-TABLE-DRIFT' \
  || fail "(3) violation output does not contain the token SCOPE-TABLE-DRIFT:
$out"
printf '%s\n' "$out" | grep -q 'release:' \
  || fail "(3) violation output does not name the offending hop 'release:':
$out"
pass "(3) table-says-MUST-STAY-haiku + code-says-bash ⇒ non-zero, names the hop"

# ── §4 direction B: table says CONVERTIBLE (bash), code says haiku ⇒ VIOLATION ───────────
# Without this the rule could pass vacuously by only ever checking one direction.
mkfixture "$TMP/badB" '`discover-prelude`' "$CONSISTENT_ROWS" \
"    agent(p, { label: 'discover-prelude', model: 'haiku' })
    agent(p, { label: \`file-surface:\${repo}\`, model: 'haiku' })"
if out="$("$LINT" "$TMP/badB/ROADMAP.md" 2>&1)"; then
  fail "(4) lint exited 0 on table-says-convertible/code-says-haiku. Output:
$out"
fi
printf '%s\n' "$out" | grep -q 'SCOPE-TABLE-DRIFT' \
  || fail "(4) violation output does not contain SCOPE-TABLE-DRIFT:
$out"
printf '%s\n' "$out" | grep -q 'file-surface' \
  || fail "(4) violation output does not name the offending hop 'file-surface':
$out"
pass "(4) table-says-convertible + code-says-haiku ⇒ non-zero, names the hop"

# ── §5 the hop list is PARSED from the ROADMAP, never hardcoded ──────────────────────────
# An invented hop name no hardcoded list could know about must still be checked.
mkfixture "$TMP/parsed" '`zzz-invented-hop`' "$CONSISTENT_ROWS" \
"    agent(p, { label: 'zzz-invented-hop', model: 'bash' })
    agent(p, { label: \`file-surface:\${repo}\`, model: 'bash' })"
if out="$("$LINT" "$TMP/parsed/ROADMAP.md" 2>&1)"; then
  fail "(5) lint exited 0 on an INVENTED hop name — the hop list is hardcoded, not parsed from the ROADMAP. Output:
$out"
fi
printf '%s\n' "$out" | grep -q 'zzz-invented-hop' \
  || fail "(5) the invented hop name is absent from the violation output — hop names are not parsed from the ROADMAP:
$out"
pass "(5) hop names are parsed from the ROADMAP table, not hardcoded"

# ── §6 missing relay-loop.js ⇒ skip LOUDLY, never silently ───────────────────────────────
mkfixture "$TMP/noloop" '`release:`' "$CONSISTENT_ROWS" "// unused"
rm -- "$TMP/noloop/relay/scripts/relay-loop.js"
out="$("$LINT" "$TMP/noloop/ROADMAP.md" 2>&1)" || true
printf '%s\n' "$out" | grep -qiE 'relay-loop\.js.*(not found|missing|skip)' \
  || fail "(6) a missing relay-loop.js was skipped SILENTLY — it must say so (no-silent-swallow):
$out"
pass "(6) an absent relay-loop.js is skipped loudly, with a message"

echo "ALL PASS: id:6b35 scope-table ↔ relay-loop.js consistency (id:c480)"
