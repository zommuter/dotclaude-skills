#!/usr/bin/env bash
# Defect/feature test (no roadmap item — encodes the owner-approved conversion policies as
# tooling): relay/references/todo-conversion-policies.md is the canonical P1–P4 playbook the
# conformance DETECTOR's findings are resolved by. Assert it exists, is installable (in the
# Makefile relay_FILES manifest, enforced cross-check), and is wired into the three modes +
# the detector script. Ratified 2026-06-26 from the 41-repo conversion sweep.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/relay/references/todo-conversion-policies.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$REF" ]] || fail "todo-conversion-policies.md not found at $REF"
pass "conversion-policy playbook exists"

# Encodes all four approved policy clusters + the flag-don't-guess residual rule.
for needle in 'P1' 'P2' 'P3' 'P4' 'non-canonical id' 'stale' 'relocate' 'status-as-task' 'FLAG, don'; do
  grep -qiF "$needle" "$REF" || fail "playbook missing the '$needle' policy/section"
done
pass "playbook encodes P1–P4 + flag-don't-guess"

# Installable: in the Makefile relay_FILES manifest (id:69ef refs-install also enforces this).
grep -qF 'references/todo-conversion-policies.md' "$ROOT/Makefile" || fail "playbook not in Makefile relay_FILES manifest"
pass "playbook is in the install manifest"

# Wired into the three human-facing modes + named by the detector script.
for f in handoff review human; do
  grep -qF 'todo-conversion-policies.md' "$ROOT/relay/references/$f.md" \
    || fail "relay/references/$f.md does not point at the conversion-policy playbook"
done
pass "handoff/review/human all point at the playbook"
grep -qF 'todo-conversion-policies.md' "$ROOT/relay/scripts/todo-conformance.sh" \
  || fail "todo-conformance.sh (the detector) does not point at the resolver playbook"
pass "the detector script points at the resolver playbook"

echo "ALL PASS: TODO conversion-policy playbook encoded + wired"
