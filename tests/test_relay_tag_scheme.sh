#!/usr/bin/env bash
# roadmap:96a8 — de-fable checkpoint tags + durable model-tracked Fable-bonus queue.
#
# Pins three things from id:96a8 (which merges id:e030):
#   1. ckpt-tag.sh emits a relay-ckpt-* tag (hermetic run), with the model+role annotation
#      label and the RELAY_LOG.md append UNCHANGED; old fable-ckpt-* tags untouched.
#   2. relay-loop.js finds the latest checkpoint / standin by matching BOTH prefixes.
#   3. integrate() writes the durable relay.toml queue (last_strong_ckpt/strong_model/
#      fable_rechecked) on STRONG checkpoints only, and the elevation consults it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CKPT="$REPO_ROOT/relay/scripts/ckpt-tag.sh"
JS="$REPO_ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()   { echo "  PASS: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

# ── 1. ckpt-tag.sh emits relay-ckpt-* (hermetic) ──────────────────────────────
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
work="$tmpdir/work"
git init -q "$work"
git -C "$work" config user.email "test@test"
git -C "$work" config user.name "Test"
echo init > "$work/README"
git -C "$work" add README
git -C "$work" commit -q -m init

label="reviewer (claude-opus-4-8, fable-standin, relay-loop)"
tag="$("$CKPT" "$work" -m "test summary paragraph" -l "$label")"

case "$tag" in
  relay-ckpt-*) ok "ckpt-tag.sh emits a relay-ckpt-* tag ($tag)" ;;
  fable-ckpt-*) bad "ckpt-tag.sh still emits the legacy fable-ckpt-* prefix ($tag)" ;;
  *)            bad "ckpt-tag.sh emitted an unexpected tag name ($tag)" ;;
esac

# tag really exists with that name
git -C "$work" rev-parse -q --verify "refs/tags/$tag" >/dev/null \
  && ok "the relay-ckpt-* tag was actually created" \
  || bad "the printed tag does not exist in the repo"

# annotation label (model + role) is preserved verbatim in the tag message
git -C "$work" tag -l --format='%(contents)' "$tag" | grep -qF "$label" \
  && ok "tag message preserves the model+role annotation label" \
  || bad "tag message lost the model+role annotation label"

# RELAY_LOG.md append unchanged (heading carries the label + summary)
grep -qF "$label" "$work/RELAY_LOG.md" \
  && grep -qF "test summary paragraph" "$work/RELAY_LOG.md" \
  && ok "RELAY_LOG.md append (label + summary) unchanged" \
  || bad "RELAY_LOG.md append missing label or summary"

# never rewrites an existing fable-ckpt-* tag: plant one, checkpoint again, assert it survives
git -C "$work" tag -a "fable-ckpt-20200101-0000" -m "historical
reviewer (claude-fable-5, relay-loop)" HEAD
old_sha="$(git -C "$work" rev-parse 'fable-ckpt-20200101-0000^{}')"
echo more > "$work/README"; git -C "$work" add README; git -C "$work" commit -q -m more
"$CKPT" "$work" -m "second" -l "executor (sonnet, relay-loop)" >/dev/null
[[ "$(git -C "$work" rev-parse 'fable-ckpt-20200101-0000^{}')" == "$old_sha" ]] \
  && ok "existing fable-ckpt-* tag is never rewritten" \
  || bad "an existing fable-ckpt-* tag was rewritten"

# ── 2. dual-prefix matching ───────────────────────────────────────────────────
# id:11ad — the per-repo tag lookup moved into gather-repo-state.sh (it computes
# latest_ckpt from BOTH prefixes and emits it); relay-loop.js's prompt consumes
# latest_ckpt / latest_ckpt_msg and detects no-checkpoint via "latest_ckpt empty".
GATHER="$REPO_ROOT/relay/scripts/gather-repo-state.sh"
[[ -x "$GATHER" ]] || bad "gather-repo-state.sh not found"
[[ $(grep -c "tag -l 'fable-ckpt-\*' 'relay-ckpt-\*'" "$GATHER") -ge 1 ]] \
  && ok "gather-repo-state.sh matches BOTH prefixes for the latest-ckpt lookup" \
  || bad "gather-repo-state.sh does not match both tag prefixes"

grep -q "fable-ckpt-\*/relay-ckpt-\*" "$JS" || grep -q "fable-ckpt" "$JS" \
  && ok "relay-loop.js still references both prefixes (latest_ckpt field doc / standin)" \
  || bad "relay-loop.js dropped the both-prefix reference"

# The old LLM prompt's "no-checkpoint detection = latest_ckpt empty" was mechanized:
# gather-repo-state.sh keys the equivalent "genuine first handoff" case on the ABSENCE of a
# ROADMAP.md (no prior /relay handoff has run yet), feeding classify-verdict.sh's handoff verdict.
grep -q "genuine first handoff" "$GATHER" \
  && ok "no-checkpoint detection = no ROADMAP.md -> genuine first handoff (gather-repo-state.sh)" \
  || bad "no-checkpoint detection does not key on the absence of a ROADMAP.md (first handoff)"

# ── 3. durable model-tracked Fable-bonus queue (id:e030) ──────────────────────
# write side: the integrator prompt records the three relay.toml fields on STRONG ckpts
grep -q 'last_strong_ckpt' "$JS" \
  && grep -q 'strong_model' "$JS" \
  && grep -q 'fable_rechecked' "$JS" \
  && ok "integrate() writes last_strong_ckpt/strong_model/fable_rechecked" \
  || bad "integrate() missing one of the durable queue fields"

# the write is gated to STRONG units (isStrong = non-execute); executor never clears
grep -q "const isStrong = unit.verdict !== 'execute'" "$JS" \
  && ok "durable-queue write gated on STRONG (non-execute) units via isStrong" \
  || bad "no isStrong gate for the durable-queue write"
grep -q 'must never clear' "$JS" \
  && ok "executor (sonnet) checkpoint explicitly must not clear the queue" \
  || bad "no executor-must-not-clear guard in the integrator prompt"

# discovery schema (relay-loop.js) + the mechanical unit-assembler (classify-repo.sh, which
# derives strongRecheckPending from relay.toml's last_strong_ckpt/fable_rechecked, replacing
# the old classifier prompt's "strongRecheckPending per repo" instruction) both expose it.
grep -q "strongRecheckPending: { type: 'boolean' }" "$JS" \
  && grep -q 'strong_recheck_pending = bool(last_strong_ckpt) and not fable_rechecked' "$REPO_ROOT/relay/scripts/classify-repo.sh" \
  && ok "DISCOVER_SCHEMA + classify-repo.sh cover strongRecheckPending" \
  || bad "strongRecheckPending missing from schema or classify-repo.sh"

# consume side: elevation considers the durable signal, not only the latest tag
grep -q 'u.standin || u.strongRecheckPending' "$JS" \
  && ok "id:9821 elevation consults the durable strongRecheckPending queue" \
  || bad "elevation does not consult strongRecheckPending"

# real-Fable review marks the recheck done (idempotent consume)
grep -q 'const isFableRecheck = SESSION_IS_FABLE' "$JS" \
  && ok "real-Fable review marks fable_rechecked done" \
  || bad "no isFableRecheck branch to close the durable queue"

# ── 4. docs mention the new fields ────────────────────────────────────────────
grep -q 'last_strong_ckpt' "$REPO_ROOT/relay/SKILL.md" \
  && grep -q 'last_strong_ckpt' "$REPO_ROOT/relay/references/conventions.md" \
  && ok "relay.toml durable-queue fields documented in SKILL.md + conventions.md" \
  || bad "durable-queue fields not documented in both SKILL.md and conventions.md"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
