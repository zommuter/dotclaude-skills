#!/usr/bin/env bash
# roadmap:44a1 — id:3801's seam emitter (handback-followup.py) must reject a bare
# {title}-only hard-split seam at the schema boundary, and a conforming seam must
# render an Acceptance/Done-check/Context body that id:213a's roadmap-lint accepts
# WITHOUT needing a TODO.md twin. Hermetic: temp ROADMAP fixture, HANDBACK_NO_COMMIT=1
# (no git). Emitter-side twin of id:213a.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# id:6f1c/f682 worktree isolation: unlike some sibling tests, always resolve THIS repo's
# own copy (never the ~/.claude/skills install, which is a symlink to the MAIN checkout
# and would silently test stale code while this item is being worked in a worktree).
HELPER="$ROOT/relay/scripts/handback-followup.py"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

fail=0
ok()   { echo "  ok  $1"; }
bad()  { echo "  FAIL $1"; fail=1; }

STORE="$(mktemp -d)"; trap 'rm -rf "$STORE"' EXIT
RM="$STORE/ROADMAP.md"
cat > "$RM" <<'ROADMAP'
# ROADMAP

## Open
- [ ] **[HARD — strong model]** Build the whole funnel end to end <!-- id:bbbb -->
ROADMAP

run() { HANDBACK_NO_COMMIT=1 python3 "$HELPER" "$STORE" "$@"; }

echo "== a seam missing acceptance/done_check/file is REJECTED, nothing written =="
before="$(cat "$RM")"
out="$(run --parent-id bbbb --route hard-split --gate-reason "too large" \
    --split-json '[{"title":"Bare title seam"}]' 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "nonzero exit on bare-title seam"; else bad "exited 0 on a non-conforming seam"; fi
if grep -qi "acceptance" < <(echo "$out") ; then ok "error names the missing field(s)"; else bad "error doesn't name missing fields ($out)"; fi
if [ "$before" = "$(cat "$RM")" ]; then ok "ROADMAP unchanged (write-nothing on reject)"; else bad "ROADMAP was mutated despite rejection"; fi

echo "== a seam missing only 'file' is also rejected (all 3 fields required) =="
before="$(cat "$RM")"
run --parent-id bbbb --route hard-split --gate-reason "too large" \
    --split-json '[{"title":"Half-conforming seam","acceptance":"x happens","done_check":"make test"}]' >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then ok "nonzero exit on missing-file seam"; else bad "exited 0 with 'file' missing"; fi
if [ "$before" = "$(cat "$RM")" ]; then ok "ROADMAP unchanged on partial seam"; else bad "ROADMAP mutated on partial seam"; fi

echo "== a conforming seam renders Acceptance/Done-check/Context and is accepted =="
run --parent-id bbbb --route hard-split --gate-reason "too large" \
    --split-json '[{"title":"Conforming seam","tier":"ROUTINE","acceptance":"the widget loads under 200ms","done_check":"tests/run-tests.sh tests/test_widget_perf.sh","file":"src/widget.js:load()"}]' >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "conforming seam accepted (exit 0)" || bad "conforming seam rejected (exit $rc)"
seam() { grep -A3 -- 'Conforming seam' "$RM"; }
grep -qF '**Acceptance**: the widget loads under 200ms' < <(seam) && ok "acceptance rendered" || bad "acceptance not rendered"
grep -qF '**Done-check**: tests/run-tests.sh tests/test_widget_perf.sh' < <(seam) && ok "done-check rendered" || bad "done-check not rendered"
grep -qF '**Context**: src/widget.js:load()' < <(seam) && ok "file/function rendered" || bad "file/function not rendered"

echo "== the rendered seam passes id:213a's roadmap-lint WITHOUT a TODO.md twin =="
LINTOUT="$STORE/lint.out"
if [ -x "$LINT" ]; then
  if "$LINT" "$RM" >"$LINTOUT" 2>&1; then
    ok "roadmap-lint accepts the rendered seam"
  else
    bad "roadmap-lint flagged the rendered seam: $(cat "$LINTOUT")"
  fi
else
  bad "roadmap-lint.sh not found/executable at $LINT"
fi

echo
[ "$fail" -eq 0 ] && echo "test_seam_emitter_acceptance_44a1: PASS" || echo "test_seam_emitter_acceptance_44a1: FAIL"
exit "$fail"
