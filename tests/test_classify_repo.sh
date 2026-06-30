#!/usr/bin/env bash
# roadmap:3f0f
# Spec for relay/scripts/classify-repo.sh (id:3f0f) — the DP1 ASSEMBLY WRAPPER that makes
# classify-verdict.sh usable end-to-end on a real repo. (Productizes the 2026-06-30 dogfood
# prototype scratchpad/backtest_dogfood.py.)
#
# Contract: `classify-repo.sh --repo <name> --path <abs>` emits ONE classify-verdict JSON
# object `{verdict,reason,evidence,ambiguous}` on stdout, by assembling:
#   1. relay/scripts/gather-repo-state.sh --repo --path   (is_finished, substantive_unaudited,
#      open_hard_pool, top_intensive, …)
#   2. DERIVE from <path>/ROADMAP.md: hasRoutine (any open `- [ ]` with [ROUTINE]),
#      roadmap_open (count open `- [ ]`), roadmap_actionable_open (open items tagged
#      [ROUTINE] or [HARD — pool] AND NOT human-gated [HARD — hands|meeting|decision gate]/@manual).
#   3. FOLD relay/scripts/unpromoted-scan.sh <path> → unpromoted {promote, surface} counts.
#   4. Pipe the assembled JSON to relay/scripts/classify-verdict.sh and emit its output.
# Must be SIDE-EFFECT-FREE (reads state, runs the helpers, emits a verdict; mutates nothing).
#
# This is the INTEGRATION tier (DP3): a hermetic mktemp git repo with real ROADMAP/TODO run
# through the whole chain. RED until classify-repo.sh exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh not yet implemented (RED): $CR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Hermetic: empty relay.toml + isolated worktree base so gather-repo-state stays repo-local.
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"

mkrepo() {  # mkrepo <dir> ; caller writes ROADMAP.md/TODO.md after, then commit_repo
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e; git -C "$d" config user.name t
}
commit_repo() { git -C "$1" add -A; git -C "$1" commit -qm init; }
ckpt_head() { git -C "$1" tag -a "relay-ckpt-20260101-0000" -m ckpt; }  # mark HEAD audited

verdict_of() { "$CR" --repo "$(basename "$1")" --path "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

# --- execute: an open [ROUTINE] item wins regardless (D3 first) -----------------------------
R1="$tmp/r_execute"; mkrepo "$R1"
cat > "$R1/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:1111 -->
EOF
printf '# TODO\n## Current\n' > "$R1/TODO.md"
commit_repo "$R1"
[[ "$(verdict_of "$R1")" == "execute" ]] || { echo "execute: open [ROUTINE] must classify execute, got $(verdict_of "$R1")"; exit 1; }

# --- handoff: drained (only @manual/human-lane open) + untagged TODO backlog (surface) -------
# The case-b/h fix end-to-end: must be handoff, NOT idle/human. HEAD tagged audited so there
# are no unaudited commits (else it would be review).
R2="$tmp/r_handoff"; mkrepo "$R2"
cat > "$R2/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — hands] @manual run on device <!-- id:2222 -->
EOF
cat > "$R2/TODO.md" <<'EOF'
# TODO
## Current
- [ ] untagged design backlog item <!-- id:3333 -->
EOF
commit_repo "$R2"; ckpt_head "$R2"
[[ "$(verdict_of "$R2")" == "handoff" ]] || { echo "handoff: drained-@manual + surface backlog must be handoff, got $(verdict_of "$R2")"; exit 1; }

# --- idle: finished ROADMAP, no unpromoted backlog ------------------------------------------
R3="$tmp/r_idle"; mkrepo "$R3"
cat > "$R3/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [x] [ROUTINE] already done <!-- id:4444 -->
EOF
cat > "$R3/TODO.md" <<'EOF'
# TODO
## Current
- [x] done backlog <!-- id:5555 -->
EOF
commit_repo "$R3"; ckpt_head "$R3"
[[ "$(verdict_of "$R3")" == "idle" ]] || { echo "idle: finished + nothing unpromoted must be idle, got $(verdict_of "$R3")"; exit 1; }

# --- side-effect-free: running the wrapper leaves each fixture's git tree clean -------------
for r in "$R1" "$R2" "$R3"; do
  [[ -z "$(git -C "$r" status --porcelain)" ]] || { echo "wrapper must be side-effect-free; $r dirtied"; exit 1; }
done

echo "PASS test_classify_repo"
