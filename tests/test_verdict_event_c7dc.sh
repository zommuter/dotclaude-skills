#!/usr/bin/env bash
# roadmap:c7dc
# RED SPEC for id:c7dc — emit a `verdict`-kind event per repo per round.
#
# Today pushEvent (relay-loop.js:57) is called with exactly four kinds — dispatch, integrate,
# handback, backstop — ALL of which presuppose a unit exists. A round that dispatches nothing
# therefore records nothing about WHY, and the three candidate explanations (drained backlog /
# a `blocked` verdict at rank 0 / a replayed discover-sig cache verdict) are indistinguishable
# after the fact. Observed in run relay-20260730-120037-1685 round 13.
#
# The payload is NOT new derivation: classify-verdict.sh already emits verdict, priority_rank,
# reason and evidence[] ({field,value,source}). What is missing is passthrough —
# classify-repo.sh --emit unit builds its unit dict WITHOUT priority_rank/evidence.
#
# TWO HALVES, deliberately:
#   (A) BEHAVIOURAL, hermetic (style of tests/test_classify_repo_unit.sh): the --emit unit
#       output must carry priority_rank, exercised over THREE fixtures with different ranks
#       so a hard-coded constant cannot pass.
#   (B) SOURCE-SHAPE (style of tests/test_dispatch_event_sig.sh): the pushEvent('verdict',…)
#       call, its `cached` flag, and its reachability from the NO-UNIT paths. Honest
#       limitation: half (B) guards the shape of the wiring, not a live round's output — the
#       Workflow engine cannot be run hermetically.
#
# RED until the passthrough + the event land. roadmap:c7dc unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -x "$CR" ]] || { echo "FAIL: classify-repo.sh not found/executable at $CR"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"
: > "$RELAY_TOML"

mkrepo() {  # mkrepo <dir> <roadmap-body>
  local d="$1"; shift
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  { echo '# Roadmap'; echo '## Items'; printf '%s\n' "$@"; } > "$d/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$d/TODO.md"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  git -C "$d" tag -a "relay-ckpt-20260101-0000" -m "review: work"
}

emit_unit() {  # emit_unit <name> <path>
  "$CR" --emit unit --repo "$1" --path "$2"
}

getfield() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get(sys.argv[1],"<<MISSING>>"))' "$1"; }

# --- (A) BEHAVIOURAL: priority_rank passthrough over three distinct ranks ------------------
# Fixture 1: an open [ROUTINE] item -> classify-verdict D3 rank 1 (execute).
R1="$tmp/repo_routine"; mkrepo "$R1" '- [ ] [ROUTINE] do the thing <!-- id:1111 -->'
# Fixture 2: an open [HARD] item, no [ROUTINE] -> a DIFFERENT rank.
R2="$tmp/repo_hard";    mkrepo "$R2" '- [ ] [HARD] think hard <!-- id:2222 -->'
# Fixture 3: everything closed -> the terminal "no actionable work" rank.
R3="$tmp/repo_done";    mkrepo "$R3" '- [x] [ROUTINE] already done <!-- id:3333 -->'

ranks=()
for pair in "routine:$R1" "hard:$R2" "done:$R3"; do
  name="${pair%%:*}"; path="${pair#*:}"
  out="$(emit_unit "$name" "$path" 2>/dev/null || true)"
  [[ -n "$out" ]] || fail "(A) classify-repo.sh --emit unit produced no output for fixture '$name'"
  r="$(printf '%s' "$out" | getfield priority_rank)"
  [[ "$r" != "<<MISSING>>" ]] \
    || fail "(A) classify-repo.sh --emit unit drops priority_rank for fixture '$name' — classify-verdict.sh already computes it; it must be passed through (id:c7dc)"
  case "$r" in ''|*[!0-9]*) fail "(A) priority_rank for '$name' is not an integer: '$r'";; esac
  ranks+=("$r")
done
# Triangulation: the three fixtures must not all collapse to one rank (a hard-coded constant).
if [[ "${ranks[0]}" == "${ranks[1]}" && "${ranks[1]}" == "${ranks[2]}" ]]; then
  fail "(A) all three fixtures report the same priority_rank (${ranks[0]}) — the field is a constant, not the classifier's rank (id:c7dc)"
fi
pass "(A) priority_rank passes through --emit unit and varies with the classifier (${ranks[*]})"

# --- (B) SOURCE-SHAPE: the verdict event ---------------------------------------------------
# B1. The event kind exists.
grep -Eq "pushEvent\('verdict'" "$JS" \
  || fail "(B1) no pushEvent('verdict', …) in relay-loop.js — the classification decision is still unrecorded (id:c7dc)"
pass "(B1) pushEvent('verdict', …) exists"

# B2. The payload carries the required fields.
vcall="$(grep -E "pushEvent\('verdict'" "$JS" || true)"
for f in repo round verdict priority_rank reason sig cached; do
  printf '%s' "$vcall" | grep -Eq "\b$f[[:space:]]*:" \
    || fail "(B2) pushEvent('verdict', …) payload is missing the '$f' field (id:c7dc)"
done
pass "(B2) verdict-event payload carries repo/round/verdict/priority_rank/reason/sig/cached"

# B3. `cached` is genuinely a boolean distinguishing replayed from fresh verdicts — the call
#     site must reference the reuse path (reusedUnits / reusedIdle), not hard-code false.
if printf '%s' "$vcall" | grep -Eq 'cached[[:space:]]*:[[:space:]]*false[[:space:]]*[,}]'; then
  fail "(B3) the verdict event hard-codes cached:false — a replayed id:c3a6 cache verdict would be indistinguishable from a fresh one (id:c7dc)"
fi
grep -Eq 'reusedUnits|reusedIdle' "$JS" \
  || fail "(B3) relay-loop.js no longer references the reuse path — cannot tell cached from fresh (id:c7dc)"
pass "(B3) cached is derived, not hard-coded false"

# B4. The event fires for repos that produced NO unit. The surfaced/skipped arrays are the
#     no-unit carriers; the emitter must walk them, not only `units`.
grep -Eq 'for \((const|let) [A-Za-z]+ of (surfaced|skipped)\)|surfaced\.forEach|skipped\.forEach' "$JS" \
  || fail "(B4) nothing iterates surfaced/skipped to emit a verdict event — a blocked/AMBIGUOUS/substitutive repo still leaves no trace, which is the entire bug (id:c7dc)"
pass "(B4) the no-unit (surfaced/skipped) paths are iterated for verdict emission"

# B5. No new sink: the event must ride the existing pendingEvents -> event-append path.
grep -Eq 'event-append' "$JS" \
  || fail "(B5) relay-loop.js no longer references event-append — the verdict event must reuse the existing append-only sink, not a new file (id:c7dc)"
pass "(B5) the existing event-append sink is still the only sink"

# B6. Engine still parses and lints clean.
node --check "$JS" >/dev/null 2>&1 || fail "(B6) node --check failed on relay-loop.js after the c7dc edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(B6) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(B6) relay-loop.js has a template-literal violation after the c7dc edit:
$out"
fi
pass "(B6) relay-loop.js parses and lints clean"

echo "PASS test_verdict_event_c7dc"
