#!/usr/bin/env bash
# roadmap:8d52 — criteria for tagging a ROADMAP item [INTENSIVE — <resource>].
# Static checks on relay/references/conventions.md: the new section documents WHAT the
# tag is (two-part resource modifier), WHEN a strong child applies it (OOM rationale +
# the local-model-load / benchmark-eval / index-rebuild criteria), the CONSEQUENCE
# (never auto-run, serial-alone, exclusive resource claim), and the per-repo relay.toml
# `intensive` default.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$SRC_DIR/relay/references/conventions.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CONV" ]] || fail "conventions.md not found"

# (1) The new section exists.
grep -q 'Tagging `\[INTENSIVE — <resource>\]`' "$CONV" \
  || fail "no '## Tagging [INTENSIVE — <resource>]' section"
pass "section heading present"

# (2) Two-part tag form is shown.
grep -q '\[INTENSIVE — local-llm\]' "$CONV" \
  || fail "two-part tag form [INTENSIVE — local-llm] not shown"
pass "two-part tag form [INTENSIVE — local-llm] shown"

# (3) Resource modifier is orthogonal to the verdict tag (not a replacement).
grep -qi 'orthogonal\|modifier' "$CONV" \
  || fail "does not state the tag is a resource modifier orthogonal to the verdict"
pass "describes resource modifier orthogonal to verdict tag"

# (4) OOM rationale is stated.
grep -qi 'OOM\|6 sessions\|Gemma' "$CONV" \
  || fail "OOM rationale (OOM / 6 sessions / Gemma) not cited"
pass "OOM rationale cited"

# (5) The criteria list: local-model-load + benchmark/eval + index-rebuild.
grep -qi 'load a local GGUF\|into RAM/VRAM\|llama-server\|ollama' "$CONV" \
  || fail "missing local-model-load criterion"
grep -qi 'benchmark\|eval' "$CONV" \
  || fail "missing benchmark/eval criterion"
grep -qi 'index rebuild\|index/rebuild\|index rebuild\|embedding/index\|index rebuild\|index rebuild' "$CONV" \
  || fail "missing index-rebuild criterion"
# specifically the embedding/index rebuild wording
grep -qi 'embedding/index rebuild\|index rebuild\|index rebuild over a corpus\|embedding\|index rebuild' "$CONV" \
  || fail "missing embedding/index rebuild criterion"
pass "lists local-model-load + benchmark/eval + index-rebuild criteria"

# (6) Consequence: never auto-run, serially-alone, exclusive resource claim.
grep -qi 'auto-run\|auto-dispatch' "$CONV" \
  || fail "does not state the unit is never auto-run/auto-dispatched"
grep -qi 'serially-alone\|serial.*alone\|run alone\|width 1' "$CONV" \
  || fail "does not state it runs serially-alone"
grep -qi 'resource:<name>\|exclusive.*resource' "$CONV" \
  || fail "does not state the exclusive resource claim"
pass "consequence (never auto-run + serial-alone + exclusive resource claim) stated"

# (7) Per-repo relay.toml `intensive` default mentioned.
grep -qi 'intensive = "local-llm"\|intensive = true\|per-repo default' "$CONV" \
  || fail "per-repo relay.toml intensive default not mentioned"
grep -qi 'relay.toml' "$CONV" \
  || fail "does not mention relay.toml for the per-repo default"
pass "per-repo relay.toml intensive default mentioned"

echo "ALL PASS"
