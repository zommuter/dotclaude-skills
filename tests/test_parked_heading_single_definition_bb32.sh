#!/usr/bin/env bash
# DEFECT FIX — no `# roadmap:` header on purpose: id:bb32 is a defect filed by the
# 2026-08-13 relay review, not a ROADMAP item, so this file's failures always count.
#
# Defect (id:bb32): `ef43739` extracted the parked-heading predicate into
# relay/scripts/lib-roadmap-sections.sh and claimed "one definition, no second parser".
# A THIRD copy survived in the python embedded in classify-repo.sh
# (`_EXEMPT_HEADING_RE = re.compile(r"(gated|deferred|done|icebox|archive|parked)", …)`),
# and the guard in tests/test_gather_hard_pool_gated_section_4b8f.sh could not see it —
# it greps for the BASH FUNCTION NAME `is_exempt_heading()`, which a python copy never
# spells. A "one definition" test blind to the second definition is the
# loud-detection-that-checks-nothing shape (id:cbd2).
#
# The copies had ALREADY DIVERGED on the heading-LINE recognizer (verified 2026-08-13):
#   gather-repo-state.sh  `^[[:space:]]*#{1,6}[[:space:]]`   H1..H6, leading ws allowed
#   roadmap-lint.sh       `^##+[[:space:]]`                  H2+ only, no leading ws
#   classify-repo.sh      `^##+\s` (python re.match)         H2+ only, no leading ws
# so `# Gated / deferred` (H1) parked a section for the HARD counter and for nobody else.
#
# The parked-heading predicate is load-bearing for DISPATCH: id:4b8f was a counter blind
# to the heading its items sit under (an Opus HARD child dispatched every round at
# zkWhale), and id:90d6 is the splitter filing executable seams under a parked heading.
#
# This test is deliberately NOT a source grep of the predicate's behaviour: cases 2 and 3
# run the PRODUCTION scripts end-to-end. Case 3 proves single-SOURCE consumption by
# mutating only the shared lib in a verbatim copy of relay/scripts and asserting every
# reader — bash and python — follows it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# ── (1) ONE definition, LANGUAGE-AGNOSTIC ──────────────────────────────────────
# Any second copy — bash, python, node — has to retype the vocabulary alternation.
# Grepping for the alternation catches all three; grepping for `is_exempt_heading()`
# catches only bash (that is exactly how bb32 hid).
# This grep is a DRIFT tripwire, not the behavioural evidence: the behaviour is proven by
# cases (2) and (3), which run the production scripts. (id:05a2/id:3a50 note: a source grep
# is only wrong when it is the ONLY evidence for a behavioural claim; here it is not.)
copies=$(grep -rlF 'gated|deferred' "$SCRIPTS" | grep -v 'lib-roadmap-sections.sh' || true)
[[ -z "$copies" ]] \
  && ok "the parked-heading vocabulary is spelled in exactly one file" \
  || bad "parked-heading vocabulary copied outside the shared lib (drift vector): $copies"

# ── (2) the three readers AGREE on an H1 parked heading ────────────────────────
mkrepo() {  # mkrepo <roadmap-content-file>
  local rm_src="$1" repo="$tmpdir/fixture"
  rm -rf "$repo"; mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email "t@t"; git -C "$repo" config user.name "T"
  cp "$rm_src" "$repo/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A; git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

cat > "$tmpdir/h1.md" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] genuinely active routine item <!-- id:0001 -->
- [ ] [HARD] genuinely active pool item <!-- id:0002 -->

# Gated / deferred

- [ ] [ROUTINE] parked under an H1 parked heading <!-- id:0003 -->
- [ ] [HARD] parked under an H1 parked heading <!-- id:0004 -->
- [ ] an item with no lane tag at all, parked <!-- id:0005 -->
EOF
repo="$(mkrepo "$tmpdir/h1.md")"

aro="$("$SCRIPTS/classify-repo.sh" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
[[ "$aro" == "1" ]] \
  && ok "classify-repo.sh exempts a section opened by an H1 parked heading (aro=1)" \
  || bad "classify-repo.sh actionable_routine_open=$aro, expected 1 (the H1-parked item must not count)"

ohp="$("$SCRIPTS/gather-repo-state.sh" --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("open_hard_pool"))')"
[[ "$ohp" == "1" ]] \
  && ok "gather-repo-state.sh exempts a section opened by an H1 parked heading (ohp=1)" \
  || bad "gather-repo-state.sh open_hard_pool=$ohp, expected 1 (the H1-parked item must not count)"

# (asserted on the SPECIFIC item, not on the exit code: this fixture also trips
# unrelated advisory WARNs that are none of bb32's business)
lint_out="$("$SCRIPTS/roadmap-lint.sh" "$repo/ROADMAP.md" 2>&1 || true)"
printf '%s' "$lint_out" | grep -q '0005' \
  && bad "roadmap-lint.sh flagged the untagged item under an H1 parked heading (id:0005)" \
  || ok "roadmap-lint.sh exempts a section opened by an H1 parked heading"

# positive control: the SAME untagged item under an ACTIVE heading must still be flagged
cat > "$tmpdir/h2active.md" <<'EOF'
# Roadmap

## Items

- [ ] an item with no lane tag at all, active <!-- id:0005 -->
EOF
lint_out="$("$SCRIPTS/roadmap-lint.sh" "$tmpdir/h2active.md" 2>&1 || true)"
printf '%s' "$lint_out" | grep -q '0005' \
  && ok "roadmap-lint.sh still flags the same untagged item under an ACTIVE heading" \
  || bad "roadmap-lint.sh no longer flags an untagged ACTIVE item — the exemption over-broadened"

# ── (2b) positive control: an ACTIVE H1 heading closes the exempt section ───────
cat > "$tmpdir/h1close.md" <<'EOF'
# Roadmap

## Gated / deferred

- [ ] [ROUTINE] parked <!-- id:0006 -->

# Items

- [ ] [ROUTINE] active again after an H1 non-parked heading <!-- id:0007 -->
EOF
repo="$(mkrepo "$tmpdir/h1close.md")"
aro="$("$SCRIPTS/classify-repo.sh" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
[[ "$aro" == "1" ]] \
  && ok "an H1 ACTIVE heading closes the exempt section (aro=1) — not a blanket suppression" \
  || bad "H1 active heading must close the exempt section, aro=$aro expected 1"

# ── (3) SINGLE SOURCE, proven by mutation ──────────────────────────────────────
# Copy relay/scripts VERBATIM, change ONLY the shared lib's vocabulary, and assert every
# reader follows. A re-inlined python/bash copy cannot follow, so this fails on a
# duplicate even if the duplicate is byte-identical today.
cp -r "$SCRIPTS" "$tmpdir/scripts"
python3 - "$tmpdir/scripts/lib-roadmap-sections.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
assert s.count('gated|deferred') == 1, "expected exactly one vocabulary spelling in the lib"
open(p, 'w').write(s.replace('gated|deferred', 'quarantined|deferred'))
PY
cat > "$tmpdir/mut.md" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] active <!-- id:0008 -->

## Quarantined

- [ ] [ROUTINE] parked under a heading the MUTATED lib calls parked <!-- id:0009 -->
EOF
repo="$(mkrepo "$tmpdir/mut.md")"
aro="$("$tmpdir/scripts/classify-repo.sh" --emit unit --repo fixture --path "$repo" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actionable_routine_open"))')"
[[ "$aro" == "1" ]] \
  && ok "classify-repo.sh's python reads the SHARED lib vocabulary (mutation followed)" \
  || bad "classify-repo.sh ignored the mutated shared vocabulary (aro=$aro, expected 1) — it still owns a copy"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
