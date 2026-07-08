#!/usr/bin/env bash
# roadmap:356f — classify-repo.sh must EXEMPT whole gated/deferred ROADMAP sections
# from `actionable_routine_open`, mirroring roadmap-lint.sh's `is_exempt_heading`
# whole-section gating (roadmap-lint.sh:158-211).
#
# Bug (routed:dfc1, llm-from-scratch review 2026-07-02): the routine-counting loop in
# classify-repo.sh:88-132 walks each open `- [ ] ` line independently and excludes only
# LINE-SCOPED gates (🚧 / "BLOCKED on"). It has no section-level gating, so a [ROUTINE]
# item parked under a `## Gated / deferred` heading (no inline marker) still counts toward
# actionable_routine_open — which gates the `execute` verdict (classify-verdict.sh:91) —
# and mis-fires an execute dispatch (empty-handback no-op, the id:4da4 failure class).
# roadmap-lint.sh already treats such an item as exempt.
#
# RED until the section-gate lands. Hermetic: mktemp git repo + `--emit unit`; no
# ~/.config touch. Idiom: test_classify_repo_standin_gate.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFY="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CLASSIFY" ]] || { echo "classify-repo.sh missing: $CLASSIFY"; exit 1; }

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmpdir/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

# aro_of <roadmap-file>: build a hermetic repo carrying that ROADMAP.md and emit
# actionable_routine_open from `classify-repo.sh --emit unit`.
aro_of() {
  local rm_src="$1"
  local repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"
  git -C "$repo" config user.name "T"
  cp "$rm_src" "$repo/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  "$CLASSIFY" --emit unit --repo fixture --path "$repo" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))'
}

# ── Case 1: a [ROUTINE] item under a normal `## Items` heading → counts (== 1) ──
# (the positive control — proves the gate is section-scoped, not a blanket suppression)
cat > "$tmpdir/normal.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] active item, not gated <!-- id:0001 -->
EOF
got="$(aro_of "$tmpdir/normal.md")"
[[ "$got" == "1" ]] && ok "normal-section [ROUTINE] counts (aro=1)" \
                     || bad "normal-section [ROUTINE] should count 1, got '$got'"

# ── Case 2: SAME item under each exempt heading → NOT counted (== 0) ────────────
for heading in "Gated / deferred" "Deferred" "Icebox" "Archive" "Parked"; do
  cat > "$tmpdir/gated.md" <<EOF
# Roadmap
## Items
## $heading
- [ ] [ROUTINE] parked item under an exempt heading, no inline marker <!-- id:0002 -->
EOF
  got="$(aro_of "$tmpdir/gated.md")"
  [[ "$got" == "0" ]] && ok "[ROUTINE] under '## $heading' is exempt (aro=0)" \
                      || bad "[ROUTINE] under '## $heading' should be exempt (aro=0), got '$got'"
done

# ── Case 3: an exempt section does NOT suppress a later normal-section item ─────
# (the gate must CLOSE when a non-exempt heading follows)
cat > "$tmpdir/mixed.md" <<'EOF'
# Roadmap
## Gated / deferred
- [ ] [ROUTINE] parked, must not count <!-- id:0003 -->
## Items
- [ ] [ROUTINE] active again after the gate closed <!-- id:0004 -->
EOF
got="$(aro_of "$tmpdir/mixed.md")"
[[ "$got" == "1" ]] && ok "exempt section closes; later ## Items item counts (aro=1)" \
                    || bad "exempt section should close on next non-exempt heading, aro should be 1, got '$got'"

# ── Case 4: existing line-scoped gate still works under a NORMAL heading (regression) ──
cat > "$tmpdir/lineblock.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] 🚧 blocked item, line-scoped marker <!-- id:0005 -->
EOF
got="$(aro_of "$tmpdir/lineblock.md")"
[[ "$got" == "0" ]] && ok "line-scoped 🚧 gate still excludes under normal heading (aro=0)" \
                    || bad "line-scoped 🚧 should still exclude, aro=0, got '$got'"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
