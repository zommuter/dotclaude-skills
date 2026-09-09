#!/usr/bin/env bash
# roadmap:6446
#
# `relay/scripts/lib-roadmap-sections.sh`'s `ROADMAP_PARKED_HEADING_WORDS` was applied as
# an UNANCHORED substring search over the heading line, so a heading like
#     ## User-injected promotion 2026-08-13 (id:baf1) — archive-path stub design call
# parked every item under it ONLY because the title prose happens to contain the
# substring "archive" — verified 2026-08-14 (id:cd9c review): `classify-repo.sh` reported
# `actionable_routine_open:0` while a landed, ungated, RED-spec `[ROUTINE]` item sat
# dispatch-ready underneath, and nothing errored — the item was simply never dispatched.
#
# This is the LOAD-BEARING negative case: the fix is only correct if a genuine parking
# bucket ("## Gated / deferred", "## Done", "## Icebox") still parks — a fix that merely
# stops matching would silently un-park every deliberately-parked section in the fleet
# (id:f391's whole reason for existing as a prerequisite: `@owner-gated` protection must
# survive this exact anchoring, and that is verified separately by
# tests/test_owner_gated_first_class_f391.sh case (3), not re-proven here).
#
# fails-against-mutation: python3 -c "
# import re
# p = 'relay/scripts/lib-roadmap-sections.sh'
# s = open(p).read()
# s = s.replace(
#     \"ROADMAP_PARKED_HEADING_WORDS='(^|[^A-Za-z0-9_@-])(gated|deferred|done|icebox|archive|parked)([^A-Za-z0-9_-]|\$)'\",
#     \"ROADMAP_PARKED_HEADING_WORDS='(gated|deferred|done|icebox|archive|parked)'\",
# )
# open(p, 'w').write(s)
# "
# fails-against-assertion: classify-repo.sh actionable_routine_open=0, expected 1 (the item under a heading that merely MENTIONS a vocab word must not be parked)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/relay/scripts"
LIB="$SCRIPTS/lib-roadmap-sections.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -f "$LIB" ]] || { echo "lib-roadmap-sections.sh missing"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"; mkdir -p "$RELAY_WORKTREE_BASE"

mkrepo() {  # mkrepo <roadmap-content-file> -> repo path
  local rm_src="$1" repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"; git -C "$repo" config user.name "T"
  cp "$rm_src" "$repo/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A; git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

# ── (1) bash predicate, directly ────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$LIB"

if is_exempt_heading '## User-injected promotion 2026-08-13 (id:baf1) — archive-path stub design call'; then
  bad "(bash) a heading merely MENTIONING 'archive' in prose still parks its section — id:cd9c's exact regression"
else
  ok "(bash) a heading merely mentioning 'archive' in prose no longer parks its section"
fi

# positive controls: genuine parking buckets must still park
for h in '## Gated / deferred' '## Done' '## Icebox' '### Gated on OPEN owner decisions'; do
  if is_exempt_heading "$h"; then
    ok "(bash) genuine parking heading '$h' still parks"
  else
    bad "(bash) genuine parking heading '$h' NO LONGER parks — the fix over-broadened"
  fi
done

# negative control: an ordinary active heading must never park
if is_exempt_heading '## Items'; then
  bad "(bash) '## Items' wrongly parked — the exclusion over-broadened"
else
  ok "(bash) '## Items' is not parked"
fi

# ── (2) production readers, end to end (id:cd9c's actual shape) ────────────────
cat > "$tmpdir/cd9c.md" <<'EOF'
# Roadmap

## User-injected promotion 2026-08-13 (id:baf1) — archive-path stub design call

- [ ] [ROUTINE] landed, ungated, RED-spec item under a mention-only heading <!-- id:0001 -->
- [ ] [HARD] landed, ungated pool item under a mention-only heading <!-- id:0002 -->

## Gated / deferred

- [ ] [ROUTINE] genuinely parked <!-- id:0003 -->
- [ ] [HARD] genuinely parked <!-- id:0004 -->
EOF
repo="$(mkrepo "$tmpdir/cd9c.md")"

aro="$("$SCRIPTS/classify-repo.sh" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
[[ "$aro" == "1" ]] \
  && ok "classify-repo.sh: the mention-only heading no longer parks (actionable_routine_open=1)" \
  || bad "classify-repo.sh actionable_routine_open=$aro, expected 1 — a mention-only heading still parks live work"

ohp="$("$SCRIPTS/gather-repo-state.sh" --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))')"
[[ "$ohp" == "1" ]] \
  && ok "gather-repo-state.sh: the mention-only heading no longer parks (open_hard_pool=1)" \
  || bad "gather-repo-state.sh open_hard_pool=$ohp, expected 1 — a mention-only heading still parks live work"

# roadmap-lint's id:d35a rule flags a pool-executable lane tag SITTING under a parked
# heading (PARKED-POOL-LANE) — a separate check that fires precisely because the tagged
# item under '## Gated / deferred' (id:0003/id:0004) IS still recognized as parked, which
# is corroborating evidence for the positive control, not a defect in this fixture. What
# id:6446 must prove here is the negative: the mention-only heading's item (id:0001) must
# NOT be treated as parked, so it must never trigger that same rule.
lint_out="$("$SCRIPTS/roadmap-lint.sh" "$repo/ROADMAP.md" 2>&1 || true)"
grep -q 'PARKED-POOL-LANE.*id:0001\|id:0001.*PARKED-POOL-LANE' < <(printf '%s' "$lint_out") \
  && bad "roadmap-lint.sh treats the mention-only heading as parked (flagged id:0001 PARKED-POOL-LANE)" \
  || ok "roadmap-lint.sh does not treat the mention-only heading as parked"
grep -q 'PARKED-POOL-LANE.*id:0003\|id:0003.*PARKED-POOL-LANE' < <(printf '%s' "$lint_out") \
  && ok "roadmap-lint.sh still treats '## Gated / deferred' as parked (flagged id:0003 PARKED-POOL-LANE, corroborating)" \
  || bad "roadmap-lint.sh no longer treats '## Gated / deferred' as parked — the fix over-broadened"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
