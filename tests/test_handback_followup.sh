#!/usr/bin/env bash
# roadmap:3801 — durable handback follow-up (auto-gate / auto-split a handed-back item).
# Hermetic: temp ROADMAP fixture, HANDBACK_NO_COMMIT=1 (no git). Asserts gating, splitting,
# and IDEMPOTENCY (the pool re-runs handbacks — a second apply must be a no-op).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$HOME/.claude/skills/relay/scripts/handback-followup.py"
[ -f "$HELPER" ] || HELPER="$ROOT/relay/scripts/handback-followup.py"

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
- [ ] **[HARD — decision gate]** Already-gated thing — do not touch <!-- id:cccc -->
EOF

run() { HANDBACK_NO_COMMIT=1 python3 "$HELPER" "$STORE" "$@" >/dev/null 2>&1; }

echo "== decision-gate re-tags a [ROUTINE] parent + inline reason =="
run --parent-id aaaa --route decision-gate --gate-reason "blocked on a design call"
aaaa_line() { grep -- 'id:aaaa' "$RM"; }
if aaaa_line | grep -qF '[HARD — decision gate]'; then ok "aaaa now decision-gated"; else bad "aaaa not gated"; fi
if aaaa_line | grep -qF 'GATED (auto, id:3801; route:decision-gate)'; then ok "auto-gate marker + route"; else bad "no auto-gate marker"; fi
if aaaa_line | grep -qF 'blocked on a design call'; then ok "reason inlined"; else bad "reason missing"; fi
if aaaa_line | grep -qF '<!-- id:aaaa -->'; then ok "id token preserved"; else bad "id token lost"; fi

echo "== decision-gate is idempotent (second apply = no-op) =="
before="$(cat "$RM")"
run --parent-id aaaa --route decision-gate --gate-reason "different reason now"
if [ "$before" = "$(cat "$RM")" ]; then ok "re-apply changed nothing"; else bad "re-apply mutated the file"; fi

echo "== hard-split gates the parent + appends pickable seams =="
run --parent-id bbbb --route hard-split --gate-reason "6-session money path" \
    --split-json '[{"id":"1234","title":"Seam One pure hash","tier":"HARD","dep":"be4b"},{"title":"Seam Two UI wiring","tier":"ROUTINE"}]'
bbbb_line() { grep -- '<!-- id:bbbb -->' "$RM"; }
if bbbb_line | grep -qF '[HARD — decision gate]'; then ok "parent bbbb gated"; else bad "parent not gated"; fi
if bbbb_line | grep -qF 'DECOMPOSED into seams'; then ok "parent marked DECOMPOSED"; else bad "parent not marked decomposed"; fi
has "$RM" 'id:1234'               "explicit-id seam appended"
seam1() { grep -- '<!-- id:1234 -->' "$RM"; }
if seam1 | grep -qF '[HARD — strong model]'; then ok "seam-one HARD tier"; else bad "seam-one tier wrong"; fi
if seam1 | grep -qF '(after id:be4b)'; then ok "seam-one dependency noted"; else bad "seam-one dep missing"; fi
if seam1 | grep -qF 'seam of id:bbbb'; then ok "seam-one parent marker"; else bad "seam-one parent marker missing"; fi
has "$RM" 'Seam Two UI wiring'    "id-less seam appended"
seam2() { grep -- 'Seam Two UI wiring' "$RM"; }
if seam2 | grep -qF '[ROUTINE]'; then ok "seam-two ROUTINE tier"; else bad "seam-two tier wrong"; fi
if seam2 | grep -qE 'id:[0-9a-f]{4}' && ! seam2 | grep -qF 'id:1234'; then ok "seam-two got a freshly minted id"; else bad "seam-two id not minted"; fi

echo "== hard-split is idempotent (no duplicate seams on re-run) =="
run --parent-id bbbb --route hard-split --gate-reason "6-session money path" \
    --split-json '[{"id":"1234","title":"Seam One pure hash","tier":"HARD","dep":"be4b"},{"title":"Seam Two UI wiring","tier":"ROUTINE"}]'
cnt "$RM" '<!-- id:1234 -->'   1 "explicit-id seam not duplicated"
cnt "$RM" 'Seam Two UI wiring' 1 "id-less seam not re-minted (title dedup)"
cnt "$RM" 'DECOMPOSED into seams' 1 "parent not re-gated twice"

echo "== an already-gated item is left untouched (respects manual gating) =="
before="$(cat "$RM")"
run --parent-id cccc --route decision-gate --gate-reason "should be ignored"
if [ "$before" = "$(cat "$RM")" ]; then ok "already-gated cccc untouched"; else bad "cccc was mutated"; fi

echo "== route=none is a no-op =="
before="$(cat "$RM")"
run --parent-id aaaa --route none
if [ "$before" = "$(cat "$RM")" ]; then ok "route=none wrote nothing"; else bad "route=none mutated file"; fi

echo
[ "$fail" -eq 0 ] && echo "test_handback_followup: PASS" || echo "test_handback_followup: FAIL"
exit "$fail"
