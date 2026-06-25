#!/usr/bin/env bash
# roadmap:3441 — todo-conformance.sh: a POSITIVE grammar for TODO.md / the shared inbox
# (sibling of roadmap-lint.sh) so NO work hides in a malformed ledger line. Reports every
# non-conforming entry; `--fix` AUTO-FIXES only the unambiguously-safe class (an open
# checkbox item missing an id → mint+append) and NEVER fabricates a task from prose.
#
# RED until the script + wiring land. Hermetic: tmp fixtures, no ~/.claude, no network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "todo-conformance.sh not found at $SH"
[[ -x "$SH" ]] || fail "todo-conformance.sh not executable"
bash -n "$SH" || fail "todo-conformance.sh fails bash -n"
pass "todo-conformance.sh exists, executable, parses"

# (0) Misuse: an unknown flag exits nonzero (loud reject).
rc=0; "$SH" --definitely-not-a-flag >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "unknown flag must exit nonzero (misuse reject); got 0"
pass "unknown flag exits nonzero (misuse reject)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# (a) A clean TODO → no findings, exit 0.
cat > "$WORK/clean.md" <<'EOF'
# TODO

## Current
- [ ] a well-formed open item [ROUTINE] <!-- id:aaaa -->
- [x] a done item <!-- id:bbbb -->
  - an indented continuation line (never linted)
<!-- a bare html comment line -->

## Done
EOF
rc=0; out="$("$SH" "$WORK/clean.md" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "clean TODO must exit 0; got $rc"
[[ -z "$(grep -vE '^\s*$' <<<"$out")" ]] || fail "clean TODO must report nothing; got:
$out"
pass "(a) clean TODO → no findings, exit 0"

# (b) An open item missing an id → missing-id; --fix mints+appends → re-lint clean.
cat > "$WORK/missing.md" <<'EOF'
# TODO

## Current
- [ ] this open item has no id tag
EOF
out="$("$SH" "$WORK/missing.md" 2>/dev/null)"
grep -qP '^missing-id\t' <<<"$out" || fail "(b) open item with no id not classed missing-id:
$out"
pass "(b) open item missing id → missing-id"
"$SH" --fix "$WORK/missing.md" >/dev/null 2>&1 || fail "(b) --fix exited nonzero"
grep -qP '^- \[ \] this open item has no id tag <!-- id:[0-9a-f]{4} -->$' "$WORK/missing.md" \
  || fail "(b) --fix did not append a minted id:
$(cat "$WORK/missing.md")"
post="$("$SH" "$WORK/missing.md" 2>/dev/null)"
[[ -z "$(grep -vE '^\s*$' <<<"$post")" ]] || fail "(b) post-fix re-lint not clean:
$post"
pass "(b) --fix mints+appends an id → re-lint clean"

# (c) A bare prose line + a checkbox-less bullet → orphan; --fix MUST leave them untouched.
cat > "$WORK/orphan.md" <<'EOF'
# TODO

## Current
placeholder
- a bullet with no checkbox
- [ ] a real item [ROUTINE] <!-- id:cccc -->
EOF
before="$(cat "$WORK/orphan.md")"
out="$("$SH" "$WORK/orphan.md" 2>/dev/null)"
[[ "$(grep -cP '^orphan\t' <<<"$out")" -eq 2 ]] || fail "(c) expected 2 orphan findings; got:
$out"
"$SH" --fix "$WORK/orphan.md" >/dev/null 2>&1 || fail "(c) --fix exited nonzero"
[[ "$(cat "$WORK/orphan.md")" == "$before" ]] || fail "(c) --fix must NOT touch orphan lines (no fabricated tasks):
$(cat "$WORK/orphan.md")"
pass "(c) bare prose + checkbox-less bullet → orphan; --fix leaves them untouched"

# (d) lint-ok / ref: pointer lines are exempt (never flagged).
cat > "$WORK/exempt.md" <<'EOF'
# TODO

## Current
- a deliberate pointer, not a task <!-- ref:abcd -->
some intentional note line <!-- lint-ok: kept on purpose -->
- [ ] a real item [ROUTINE] <!-- id:dddd -->
EOF
out="$("$SH" "$WORK/exempt.md" 2>/dev/null)"
[[ -z "$(grep -vE '^\s*$' <<<"$out")" ]] || fail "(d) lint-ok/ref lines must be exempt; got:
$out"
pass "(d) lint-ok + ref: pointer lines are exempt"

# (e) --inbox grammar: a token-less prose block is flagged; a conforming routed line passes.
cat > "$WORK/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [dotclaude-skills] a conforming routed item (from x, y) <!-- routed:1f5e -->
zkm core: a prose block with no checkbox and no routed token
EOF
out="$("$SH" --inbox "$WORK/inbox.md" 2>/dev/null)"
grep -q 'zkm core: a prose block' <<<"$out" || fail "(e) --inbox did not flag the token-less prose block:
$out"
grep -q 'routed:1f5e' <<<"$out" && fail "(e) --inbox wrongly flagged a conforming routed line:
$out"
pass "(e) --inbox flags token-less prose, passes conforming routed lines"

# (f) report-only by default; --strict turns findings into a nonzero exit.
rc=0; "$SH" --strict "$WORK/orphan.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(f) --strict must exit nonzero when findings exist; got 0"
pass "(f) --strict exits nonzero on findings (report-only stays exit 0)"

# --- wiring: surfaced in the human-facing relay modes + relay-doctor (never blocks) ----
grep -q 'todo-conformance.sh' "$ROOT/relay/scripts/relay-doctor.sh" || fail "relay-doctor.sh does not invoke todo-conformance.sh"
pass "relay-doctor.sh wires in todo-conformance.sh"
for ref in review human handoff; do
  grep -qiE 'conformance|non-conforming' "$ROOT/relay/references/$ref.md" \
    || fail "relay/references/$ref.md does not mention the conformance check"
done
pass "review/human/handoff references all surface the conformance check"

# (g) c095 heading-as-item: a `## [LANE] … <!-- id -->` heading owns the item; its
#     `- [ ] Open` / `- [x] Done` status sub-lines must NOT be flagged missing-id, and
#     --fix must NOT mint an id onto a status marker.
cat > "$WORK/heading.md" <<'EOF'
# TODO

## [ROUTINE] A heading-as-item that owns its lane+id <!-- id:9abc -->
- [ ] Open
- [x] earlier status
EOF
hbefore="$(cat "$WORK/heading.md")"
out="$("$SH" "$WORK/heading.md" 2>/dev/null)"
[[ -z "$(grep -vE '^\s*$' <<<"$out")" ]] || fail "(g) heading-as-item status sub-lines wrongly flagged:
$out"
"$SH" --fix "$WORK/heading.md" >/dev/null 2>&1 || fail "(g) --fix exited nonzero"
[[ "$(cat "$WORK/heading.md")" == "$hbefore" ]] || fail "(g) --fix wrongly minted an id onto a heading-item status sub-line:
$(cat "$WORK/heading.md")"
pass "(g) c095 heading-as-item status sub-lines not flagged / not auto-fixed"

# (h) A SECTION heading that carries an id for batch-tracking but NO lane tag
#     (`## [HUMAN] … <!-- id:1ef9 -->`) is NOT a heading-as-item — its children are REAL
#     items that must still be linted (the zomni regression: an id-bearing section
#     wrongly hid 9 real items).
cat > "$WORK/section_id.md" <<'EOF'
# TODO

## [HUMAN] — privileged steps (run as one batch) <!-- id:1ef9 -->
- [ ] a real item with no id tag
- [ ] another real item [ROUTINE] <!-- id:7777 -->
EOF
out="$("$SH" "$WORK/section_id.md" 2>/dev/null)"
grep -qP '^missing-id\t.*a real item with no id tag' <<<"$out" \
  || fail "(h) an id-bearing SECTION heading wrongly hid its real child items:
$out"
pass "(h) id-bearing section heading (no lane) does NOT hide real child items"

# (i) An item with a NON-canonical inline id (`(id:560c)`) must NOT be auto-minted a second
#     id by --fix (that would create a duplicate); --fix leaves it untouched + warns.
cat > "$WORK/inline_id.md" <<'EOF'
# TODO

## Current
- [ ] **caddy receiver (id:560c)** — deferred, needs sudo
EOF
ibefore="$(cat "$WORK/inline_id.md")"
"$SH" --fix "$WORK/inline_id.md" >/dev/null 2>&1 || fail "(i) --fix exited nonzero"
[[ "$(cat "$WORK/inline_id.md")" == "$ibefore" ]] || fail "(i) --fix double-minted an id onto an inline-id item:
$(cat "$WORK/inline_id.md")"
pass "(i) inline-id item is NOT double-minted by --fix (duplicate-id guard)"

echo "ALL PASS: id:3441 TODO/inbox conformance grammar + safe auto-fix + wiring"
