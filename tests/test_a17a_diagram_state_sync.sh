#!/usr/bin/env bash
# roadmap:a17a
# Drift-guard for the /relay + /meeting state-machine diagram set (a17a, meeting mtg-1726 D1/D2).
#
# The RED spec for a17a. The three Mermaid diagrams (docs/diagrams/*.mmd) must EXIST and their
# declared vocabulary must NOT drift from the machine-readable source of truth: the verdict enum
# emitted by classify-verdict.sh and the relay invocation modes in relay/SKILL.md. This is D2's
# "guard, don't hand-sync" strategy — the diagram topology is authored by the [HARD — pool]
# executor (design judgment, reconciled with the id:4da4 matrix), and THIS guard keeps the
# authored vocabulary in sync so the diagram can't silently rot.
#
# It fails RED today because docs/diagrams/ does not exist yet. The executor implementing a17a
# authors the three diagrams; this test goes green when they exist and carry the correct tokens.
# The guard DERIVES its authoritative sets from source (never hardcodes them) — an executor may
# refine the derivation, but must keep it mechanical (read from classify-verdict.sh / SKILL.md),
# never a frozen literal list.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
DIAG="$ROOT/docs/diagrams"
fail=0
note() { echo "FAIL: $*" >&2; fail=1; }

# (1) The three diagrams must exist.
for f in ledger-lifecycle relay-dispatch meeting-classification; do
  [[ -f "$DIAG/$f.mmd" ]] || note "missing diagram: docs/diagrams/$f.mmd"
done

DISPATCH="$DIAG/relay-dispatch.mmd"
if [[ -f "$DISPATCH" ]]; then
  # (2) relay-dispatch must name every verdict classify-verdict.sh can emit (derived, not hardcoded).
  verdicts="$(grep -oE '"(execute|review|hard|handoff|human|idle)"' \
    "$ROOT/relay/scripts/classify-verdict.sh" 2>/dev/null | tr -d '"' | sort -u)"
  [[ -n "$verdicts" ]] || note "could not derive verdict set from relay/scripts/classify-verdict.sh"
  while read -r v; do
    [[ -z "$v" ]] && continue
    grep -qiw "$v" "$DISPATCH" || note "relay-dispatch.mmd missing verdict '$v' (drift vs classify-verdict.sh)"
  done <<< "$verdicts"

  # (3) relay-dispatch must name every /relay invocation mode documented in SKILL.md (derived).
  modes="$(grep -oE '/relay (handoff|review|next|human|health|inject|executor|stop|reconcile)' \
    "$ROOT/relay/SKILL.md" 2>/dev/null | awk '{print $2}' | sort -u)"
  [[ -n "$modes" ]] || note "could not derive relay mode set from relay/SKILL.md"
  while read -r m; do
    [[ -z "$m" ]] && continue
    grep -qiw "$m" "$DISPATCH" || note "relay-dispatch.mmd missing relay mode '$m' (drift vs SKILL.md)"
  done <<< "$modes"

  # (4) The three execution substrates must be represented (the correction mtg-1726 turned on).
  for sub in mechanical human; do
    grep -qi "$sub" "$DISPATCH" || note "relay-dispatch.mmd missing the '$sub' substrate (mtg-1726 D1)"
  done
fi

# (5) meeting-classification must name the C1/C2/C3 classes + the broker sub-branch.
MEET="$DIAG/meeting-classification.mmd"
if [[ -f "$MEET" ]]; then
  for tok in C1 C2 C3 broker; do
    grep -qi "$tok" "$MEET" || note "meeting-classification.mmd missing '$tok'"
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "a17a diagram drift-guard: RED"
  exit 1
fi
echo "a17a diagram drift-guard: green"
exit 0
