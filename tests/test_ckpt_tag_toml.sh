#!/usr/bin/env bash
# roadmap:0a3b — ckpt-tag.sh must sync [repos.<name>] last_ckpt (+ last_strong_ckpt/strong_model
# when the label records a strong model) in relay.toml via the flock'd relay-state-write.sh
# toml-set single-writer, IFF the repo has a [repos.<name>] block.
#
# Found by the 2026-07-01 fable catch-up review: tags relay-ckpt-20260701-{1948,2019,2110} were
# minted by supervised sessions via ckpt-tag.sh while relay.toml stayed at last_ckpt=...-1635 —
# only the pool integrator (relay-loop.js:1426) ever wrote relay.toml. Discovery is tag-derived
# (gather-repo-state.sh) so verdicts don't drift, but the id:e030 Fable-recheck queue misses
# out-of-pool strong checkpoints and relay-doctor check 11 (id:333c) validates a stale value.
#
# RED until ckpt-tag.sh grows the toml-sync (via FABLES_CONFIG-overridable relay-state-write.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT="$ROOT/relay/scripts/ckpt-tag.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CT" ]] || fail "ckpt-tag.sh not found/executable at $CT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # mkrepo <dir-name> -> path
  local r="$TMP/$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@e.st
  git -C "$r" config user.name t
  echo x > "$r/f"
  git -C "$r" add -A
  git -C "$r" commit -qm init
  printf '%s' "$r"
}

# Hermetic relay config root (relay-state-write.sh honors FABLES_CONFIG).
CFG="$TMP/cfg"
mkdir -p "$CFG"
cat > "$CFG/relay.toml" <<'EOF'
[repos.managed_a]
classification = "own"
last_ckpt = "relay-ckpt-00000000-0000"

[repos.managed_b]
classification = "own"
EOF
export FABLES_CONFIG="$CFG"

# (1) managed repo, ordinary (non-strong) label -> last_ckpt updated to the new tag.
RA="$(mkrepo managed_a)"
tag_a="$("$CT" "$RA" -m "test checkpoint (roadmap:0a3b case 1)" -l "reviewer (test)" )" \
  || fail "(1) ckpt-tag.sh failed on a managed repo"
[[ -n "$tag_a" ]] || fail "(1) ckpt-tag.sh printed no tag name"
grep -q "last_ckpt = \"$tag_a\"" "$CFG/relay.toml" \
  || fail "(1) relay.toml [repos.managed_a] last_ckpt not synced to $tag_a (roadmap:0a3b)"
pass "(1) managed repo: last_ckpt synced to the freshly minted tag"

# (2) strong-model label -> last_strong_ckpt + strong_model recorded too (id:e030 shape);
#     fable_rechecked is NOT touched by ckpt-tag.sh (integrator owns the consume side).
RB="$(mkrepo managed_b)"
tag_b="$("$CT" "$RB" -m "test strong checkpoint (roadmap:0a3b case 2)" -l "reviewer (claude-opus-4-8, test)" )" \
  || fail "(2) ckpt-tag.sh failed on a managed repo (strong label)"
grep -q "last_ckpt = \"$tag_b\"" "$CFG/relay.toml" \
  || fail "(2) last_ckpt not synced for managed_b"
grep -q "last_strong_ckpt = \"$tag_b\"" "$CFG/relay.toml" \
  || fail "(2) last_strong_ckpt not recorded for a strong-model label (id:e030)"
grep -q 'strong_model = "claude-opus-4-8"' "$CFG/relay.toml" \
  || fail "(2) strong_model not recorded for a strong-model label"
pass "(2) strong label: last_strong_ckpt + strong_model recorded"

# (3) UNMANAGED repo (no [repos.<name>] block) -> toml untouched, tagging still succeeds.
RC="$(mkrepo unmanaged_c)"
before="$(cat "$CFG/relay.toml")"
tag_c="$("$CT" "$RC" -m "test checkpoint (roadmap:0a3b case 3)" -l "reviewer (test)" )" \
  || fail "(3) ckpt-tag.sh must still succeed for an unmanaged repo"
git -C "$RC" rev-parse --verify -q "refs/tags/$tag_c" >/dev/null \
  || fail "(3) tag $tag_c not created on the unmanaged repo"
[[ "$(cat "$CFG/relay.toml")" == "$before" ]] \
  || fail "(3) relay.toml modified for an unmanaged repo (must never create a block)"
pass "(3) unmanaged repo: tag minted, relay.toml untouched"

# (4) relay.toml ABSENT -> logged no-op, tagging itself still succeeds.
rm -f "$CFG/relay.toml"
RD="$(mkrepo managed_a2)"
tag_d="$("$CT" "$RD" -m "test checkpoint (roadmap:0a3b case 4)" -l "reviewer (test)" )" \
  || fail "(4) ckpt-tag.sh must not fail when relay.toml is absent"
git -C "$RD" rev-parse --verify -q "refs/tags/$tag_d" >/dev/null \
  || fail "(4) tag $tag_d not created when relay.toml is absent"
pass "(4) missing relay.toml: checkpoint still succeeds (no-op sync)"

echo "ALL PASS: roadmap:0a3b ckpt-tag.sh relay.toml sync"
