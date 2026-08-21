#!/usr/bin/env bash
# roadmap:3801 — durable handback follow-up (auto-gate / auto-split a handed-back item).
# Hermetic: temp ROADMAP fixture, HANDBACK_NO_COMMIT=1 (no git). Asserts gating, splitting,
# and IDEMPOTENCY (the pool re-runs handbacks — a second apply must be a no-op).
#
# id:4b64 — the EMITTED tags are the canonical capability-keyed spelling: `[INPUT — decision]`
# for the gate (was `[HARD — decision gate]`, which relay's own pre-commit lane-vocab ratchet
# BLOCKS) and `[HARD]` for a HARD seam (was the pre-id:78ff `[HARD — strong model]`, which is
# in no lane vocabulary at all). An OLD-vocab gate already on a line is still recognized as
# gated (migration window) — the last case below pins that.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# id:6f1c/f682 worktree isolation: always resolve THIS repo's own copy (never the
# ~/.claude/skills install, a symlink to the MAIN checkout — testing that would
# silently exercise stale code while this file is edited in a worktree, id:44a1).
HELPER="$ROOT/relay/scripts/handback-followup.py"

fail=0
ok()   { echo "  ok  $1"; }
bad()  { echo "  FAIL $1"; fail=1; }
has()  { if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
cnt()  { local n; n=$(grep -cF -- "$2" "$1"); if [ "$n" = "$3" ]; then ok "$4 (==$3)"; else bad "$4 (got $n want $3)"; fi; }

STORE="$(mktemp -d)"; trap 'rm -rf "$STORE"' EXIT
RM="$STORE/ROADMAP.md"
cat > "$RM" <<'EOF'
# ROADMAP

## Open
- [ ] **[ROUTINE]** Add the widget loader <!-- id:aaaa -->
- [ ] **[HARD — strong model]** Build the whole funnel end to end <!-- id:bbbb -->
- [ ] **[HARD — decision gate]** Already-gated thing (OLD vocab, migration window) — do not touch <!-- id:cccc -->
- [ ] **[INPUT — decision]** Already-gated thing (NEW vocab) — do not touch <!-- id:dddd -->
EOF

run() { HANDBACK_NO_COMMIT=1 python3 "$HELPER" "$STORE" "$@" >/dev/null 2>&1; }

echo "== decision-gate re-tags a [ROUTINE] parent + inline reason =="
run --parent-id aaaa --route decision-gate --gate-reason "blocked on a design call"
aaaa_line() { grep -- 'id:aaaa' "$RM"; }
if grep -qF '[INPUT — decision]' < <(aaaa_line) ; then ok "aaaa now decision-gated (canonical [INPUT — decision])"; else bad "aaaa not gated with the canonical [INPUT — decision] tag"; fi
if grep -qF '[HARD — decision gate]' < <(aaaa_line) ; then bad "aaaa gated with the OLD-vocab tag (the pre-commit ratchet blocks it, id:4b64)"; else ok "no old-vocab tag emitted"; fi
if grep -qF 'GATED (auto, id:3801; route:decision-gate)' < <(aaaa_line) ; then ok "auto-gate marker + route"; else bad "no auto-gate marker"; fi
if grep -qF 'blocked on a design call' < <(aaaa_line) ; then ok "reason inlined"; else bad "reason missing"; fi
if grep -qF '<!-- id:aaaa -->' < <(aaaa_line) ; then ok "id token preserved"; else bad "id token lost"; fi

echo "== decision-gate is idempotent (second apply = no-op) =="
before="$(cat "$RM")"
run --parent-id aaaa --route decision-gate --gate-reason "different reason now"
if [ "$before" = "$(cat "$RM")" ]; then ok "re-apply changed nothing"; else bad "re-apply mutated the file"; fi

SPLIT_JSON='[{"id":"1234","title":"Seam One pure hash","tier":"HARD","dep":"be4b","acceptance":"the hash helper is pure and unit-tested","done_check":"tests/run-tests.sh tests/test_seam_one.sh","file":"src/hash.js:pureHash()"},{"title":"Seam Two UI wiring","tier":"ROUTINE","acceptance":"the widget calls the hash helper on submit","done_check":"tests/run-tests.sh tests/test_seam_two.sh","file":"src/widget.js:onSubmit()"}]'

echo "== hard-split gates the parent + appends pickable seams =="
run --parent-id bbbb --route hard-split --gate-reason "6-session money path" \
    --split-json "$SPLIT_JSON"
bbbb_line() { grep -- '<!-- id:bbbb -->' "$RM"; }
if grep -qF '[INPUT — decision]' < <(bbbb_line) ; then ok "parent bbbb gated"; else bad "parent not gated"; fi
if grep -qF 'DECOMPOSED into seams' < <(bbbb_line) ; then ok "parent marked DECOMPOSED"; else bad "parent not marked decomposed"; fi
has "$RM" 'id:1234'               "explicit-id seam appended"
seam1() { grep -A3 -- '<!-- id:1234 -->' "$RM"; }
if grep -qF '**[HARD]**' < <(seam1) ; then ok "seam-one HARD tier (canonical bare [HARD])"; else bad "seam-one tier wrong (want the canonical **[HARD]**)"; fi
if grep -qF '[HARD — strong model]' < <(seam1) ; then bad "seam-one emitted the legacy [HARD — strong model] tag, which no lane parser recognizes (id:4b64)"; else ok "no legacy strong-model tag emitted"; fi
if grep -qF '(after id:be4b)' < <(seam1) ; then ok "seam-one dependency noted"; else bad "seam-one dep missing"; fi
if grep -qF 'seam of id:bbbb' < <(seam1) ; then ok "seam-one parent marker"; else bad "seam-one parent marker missing"; fi
if grep -qF '**Acceptance**: the hash helper is pure and unit-tested' < <(seam1) ; then ok "seam-one acceptance rendered"; else bad "seam-one acceptance missing"; fi
if grep -qF '**Done-check**: tests/run-tests.sh tests/test_seam_one.sh' < <(seam1) ; then ok "seam-one done-check rendered"; else bad "seam-one done-check missing"; fi
if grep -qF '**Context**: src/hash.js:pureHash()' < <(seam1) ; then ok "seam-one file/function rendered"; else bad "seam-one file/function missing"; fi
has "$RM" 'Seam Two UI wiring'    "id-less seam appended"
seam2() { grep -A3 -- 'Seam Two UI wiring' "$RM"; }
if grep -qF '[ROUTINE]' < <(seam2) ; then ok "seam-two ROUTINE tier"; else bad "seam-two tier wrong"; fi
if grep -qE 'id:[0-9a-f]{4}' < <(seam2) && ! grep -qF 'id:1234' < <(seam2) ; then ok "seam-two got a freshly minted id"; else bad "seam-two id not minted"; fi
if grep -qF '**Done-check**: tests/run-tests.sh tests/test_seam_two.sh' < <(seam2) ; then ok "seam-two done-check rendered"; else bad "seam-two done-check missing"; fi

echo "== hard-split is idempotent (no duplicate seams on re-run) =="
run --parent-id bbbb --route hard-split --gate-reason "6-session money path" \
    --split-json "$SPLIT_JSON"
cnt "$RM" '<!-- id:1234 -->'   1 "explicit-id seam not duplicated"
cnt "$RM" 'Seam Two UI wiring' 1 "id-less seam not re-minted (title dedup)"
cnt "$RM" 'DECOMPOSED into seams' 1 "parent not re-gated twice"

echo "== an already-gated item is left untouched (respects manual gating; BOTH vocabularies) =="
before="$(cat "$RM")"
run --parent-id cccc --route decision-gate --gate-reason "should be ignored"
if [ "$before" = "$(cat "$RM")" ]; then ok "already-gated cccc (old vocab) untouched"; else bad "cccc was mutated"; fi
before="$(cat "$RM")"
run --parent-id dddd --route decision-gate --gate-reason "should be ignored"
if [ "$before" = "$(cat "$RM")" ]; then ok "already-gated dddd (new vocab) untouched"; else bad "dddd was mutated"; fi

echo "== route=none is a no-op =="
before="$(cat "$RM")"
run --parent-id aaaa --route none
if [ "$before" = "$(cat "$RM")" ]; then ok "route=none wrote nothing"; else bad "route=none mutated file"; fi

echo
[ "$fail" -eq 0 ] && echo "test_handback_followup: PASS" || echo "test_handback_followup: FAIL"
exit "$fail"
