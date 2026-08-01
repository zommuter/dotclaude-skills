#!/usr/bin/env bash
# roadmap:34b7
# RED SPEC for id:34b7 — the PARENT creates and provisions the child's worktree before
# dispatch, and the child is never handed the main-checkout path.
#
# THIS IS DISSOLUTION, NOT ENFORCEMENT: it removes the child's *reason* and *means* to
# reach into the target's main checkout, instead of guarding the write after the fact.
# The enforcement sibling (id:d464, a PreToolUse deny hook) carries a standing owner
# directive "DISCUSSION ONLY — DO NOT BUILD" and is deliberately NOT specced here.
#
# THE DEFECT, verified in-code 2026-08-01:
#   relay-loop.js:1958  `You are a relay ... child for the repo ${unit.repo} (main checkout: ${unit.path}).`
#   relay-loop.js:1962  `Create your worktree first: git -C ${unit.path} worktree add ${wt} -b ${branch} HEAD`
#   relay-loop.js:1963  `Work EXCLUSIVELY in that worktree.`   <- prose, zero enforcement
#   relay-loop.js:1988  the RESUME prompt repeats the main-checkout path
#   relay-loop.js:2413  agent opts are `{ label, phase, schema }` (+ model) — across every
#                       agent() call in relay/scripts/*.js|mjs the keys are 16x label,
#                       16x model, 15x phase, 2x schema: ZERO cwd, ZERO isolation.
# Damage trail: 2026-06-30 jobAI (id:c6c8); 2026-07-14 loderite (id:f682/7612); 2026-07-30
# loderite run relay-20260730-000539-18583 wrote non-compiling TypeScript into the LIVE
# main checkout while its worktree stayed clean.
#
# ORDERING IS LOAD-BEARING (owner's objection, 2026-07-30): part (3) — dropping the path
# from the prompt — is GATED on parts (1)+(2). Removing the path before the parent both
# creates the worktree AND provisions the gitignored build artifacts would break exactly
# the repos that legitimately reuse main's node_modules/.venv/caches. Assertion 6 encodes
# that gate as a conditional, so a partial fix that drops the path without provisioning
# FAILS rather than looking done.
#
# COVERAGE HONESTY: every assertion here is SOURCE-SHAPE over relay-loop.js, not
# behavioural. relay-loop.js is Workflow-sandbox JS with no importable surface and no
# hermetic runner (it dispatches everything through agent()), so it cannot be executed in
# this suite — the same honest limitation stated in tests/test_chain_end_reask_8123.sh
# (assertions 4-6) and tests/test_rechain_depth_cc90.sh. It is stated here rather than
# dressed up as a behavioural proof.
#
# TRIANGULATION (id:108e): eight assertions over four concerns — path removal (BOTH prompt
# sites, so fixing one is not enough), the instruction removal, the parent-side creation
# actually existing as a mechanical hop, provisioning, the ordering gate, and two
# determinism controls. Deleting the two prompt lines and stopping there fails assertions
# 3-6; adding a pre-dispatch hop but leaving the prompt alone fails 1-2.
#
# Hermetic: reads source files only. No git, no network, no HOME writes, no dispatch.
#
# RED until the parent provisions the worktree pre-dispatch. roadmap:34b7 unticked
# => EXPECTED-RED.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
SKILLMD="$ROOT/relay/SKILL.md"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -f "$SKILLMD" ]] || { echo "FAIL: relay/SKILL.md not found at $SKILLMD"; exit 1; }

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

# ── 1. The child prompt must not carry the main-checkout path (part 3) ───────────
hits="$(grep -c 'main checkout: ${unit.path}' "$JS" || true)"
if [[ "$hits" == "0" ]]; then
  ok "(1) no child prompt interpolates 'main checkout: \${unit.path}'"
else
  bad "(1) $hits child prompt(s) still hand the child the main-checkout path ('main checkout: \${unit.path}') — a child that is never told the path has no means to target it (id:34b7 part 3). Sites: $(grep -n 'main checkout: ${unit.path}' "$JS" | cut -d: -f1 | tr '\n' ' ')"
fi

# ── 2. BOTH sites, not just the dispatch prompt ──────────────────────────────────
# unitPrompt (~:1958) and the RESUME prompt (~:1988) are separate template literals.
# Fixing one and leaving the other is the exact half-fix this assertion exists to catch.
resume_line="$(grep -n 'You are RESUMING an interrupted relay HANDOFF' "$JS" | head -1 | cut -d: -f1)"
if [[ -z "$resume_line" ]]; then
  bad "(2) the resume-prompt anchor 'You are RESUMING an interrupted relay HANDOFF' is gone — test anchor stale, re-derive it before trusting this file"
elif sed -n "${resume_line}p" "$JS" | grep -q 'unit.path'; then
  bad "(2) the RESUME prompt (relay-loop.js:$resume_line) still interpolates unit.path — the auto-resume child is dispatched by the same mechanism and must be covered too (id:34b7 part 3)"
else
  ok "(2) the resume prompt no longer interpolates the main-checkout path"
fi

# ── 3. The child must no longer be told to create its own worktree (part 1) ──────
if grep -q 'Create your worktree first' "$JS"; then
  bad "(3) the child prompt still says 'Create your worktree first: git -C \${unit.path} worktree add …' — that instruction IS the reason the child holds the main-checkout path (id:34b7 part 1)"
else
  ok "(3) the child prompt no longer instructs the child to run 'git worktree add'"
fi

# ── 4. The worktree creation must have MOVED to the parent, not vanished ─────────
# relay-loop.js runs shell only through a mechanical agent() hop (model: MECH_MODEL /
# 'bash'), so a parent-side `worktree add` must appear near such a dispatch. Asserting
# only "the child no longer creates it" would be satisfied by deleting the step entirely
# and leaving every child without a worktree at all.
wt_lines="$(grep -n 'worktree add' "$JS" | cut -d: -f1 || true)"
if [[ -z "$wt_lines" ]]; then
  bad "(4) 'worktree add' has disappeared from relay-loop.js entirely — the step must MOVE to a pre-dispatch parent hop, not be deleted (id:34b7 part 1)"
else
  near_mech=0
  for ln in $wt_lines; do
    lo=$(( ln > 12 ? ln - 12 : 1 )); hi=$(( ln + 12 ))
    if sed -n "${lo},${hi}p" "$JS" | grep -qE "MECH_MODEL|model: *'bash'"; then near_mech=1; break; fi
  done
  if [[ "$near_mech" == "1" ]]; then
    ok "(4) a 'worktree add' occurrence sits in a mechanical (MECH_MODEL/bash) parent hop"
  else
    bad "(4) every 'worktree add' occurrence in relay-loop.js (lines: $(echo $wt_lines | tr '\n' ' ')) is still prose in a child prompt — none is dispatched by the parent as a mechanical hop before the child runs (id:34b7 part 1)"
  fi
fi

# ── 5. Provisioning of gitignored build artifacts (part 2) ───────────────────────
# Children already do this by hand (loderite RELAY_LOG.md:2681, with :3022/:3422/:3486
# showing them removing the symlink before commit). Part 2 absorbs that manual step;
# without it, a child with no node_modules has a real reason to go to main.
if grep -qE 'node_modules' "$JS"; then
  ok "(5) relay-loop.js provisions/negotiates gitignored build artifacts (node_modules named)"
else
  bad "(5) relay-loop.js never mentions node_modules — the child's OTHER reason to reach into main (missing gitignored build artifacts) is unaddressed (id:34b7 part 2)"
fi

# ── 6. THE ORDERING GATE: part (3) must not land before parts (1)+(2) ───────────
# Encoded as a conditional so a half-fix is a FAILURE, not a silent regression: if the
# main-checkout path has been dropped from the prompt, provisioning MUST already exist.
if [[ "$hits" == "0" ]] && ! grep -qE 'node_modules' "$JS"; then
  bad "(6) ORDERING VIOLATION — the main-checkout path was dropped from the child prompt while no artifact provisioning exists. Part (3) is gated on (1)+(2); dropping the path first breaks exactly the repos that legitimately reuse main's build artifacts (owner's objection, 2026-07-30)"
else
  ok "(6) the part-(3)-gated-on-(1)+(2) ordering constraint holds"
fi

# ── 7-8. DETERMINISM CONTROLS: the recovery path depends on stable names ─────────
# The API-error recovery path (runUnit catch / integrate null-guard) re-derives a failed
# child's worktree and branch from these helpers. Moving creation to the parent must reuse
# them, not invent a second naming scheme.
grep -q 'const worktreePathFor' "$JS" \
  && ok "(7) control: worktreePathFor() still exists (deterministic worktree naming preserved)" \
  || bad "(7) worktreePathFor() is gone — the API-error recovery path re-derives a failed child's worktree from it; the parent-side creation must REUSE it"
grep -q 'const branchFor' "$JS" \
  && ok "(8) control: branchFor() still exists (deterministic branch naming preserved)" \
  || bad "(8) branchFor() is gone — same deterministic-naming contract as worktreePathFor()"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
