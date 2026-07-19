#!/usr/bin/env bash
# roadmap:ac7f
# RED spec (authored by /relay handoff 2026-07-19, apex) for the af48 KEYSTONE child
# id:ac7f — the `@wire` grammar + `classify-repo` count + `drained` render-alias.
# Design: docs/meeting-notes/2026-07-19-1152-drained-verdict-wire-manual-grammar.md
# (D1 drained=render-alias-over-idle / D3 two-linked-items split / D4 @wire=orthogonal
# marker counting toward actionable_routine_open).
#
# Three deliverables, each pinned below:
#   (2) classify-repo.sh: an open item carrying `@wire` on a primary EXECUTOR lane
#       ([ROUTINE]/[HARD — pool]/[HARD]) counts toward actionable_routine_open, so the
#       classify-verdict execute gate fires → verdict=execute. `@manual` stays EXCLUDED.
#   (3) drained render-alias: a NEW relay/scripts/render-verdict.sh maps a classify-verdict
#       JSON on stdin → a display label; verdict=idle → "drained" (the ONLY sanctioned way
#       to emit the word), every other verdict verbatim. NO new classify-verdict.sh enum.
#   (1) grammar docs: `@wire` is documented in relay/references/hard-lanes.md.
#
# Consumers enumerated (id:78df discipline): actionable_routine_open is read by
# classify-verdict.sh (execute gate, :51/:131) — the routing-determining consumer this
# spec exercises end-to-end — and re-exported by classify-repo.sh --emit unit (:294) and
# relay-doctor check 10 (field passthroughs of the same integer, no separate wire logic).
#
# EXPECTED-RED while roadmap:ac7f is unticked (does not fail the suite). Ticking it makes
# any failure real.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
RV="$ROOT/relay/scripts/render-verdict.sh"
HL="$ROOT/relay/references/hard-lanes.md"
[[ -x "$CR" ]] || { echo "classify-repo.sh missing (RED): $CR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"

mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; }
commit_repo() { git -C "$1" add -A; git -C "$1" commit -qm init; }
ckpt_head() { git -C "$1" tag -a "relay-ckpt-20260101-0000" -m ckpt; }  # mark HEAD audited → not `review`
verdict_of() { "$CR" --repo "$(basename "$1")" --path "$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

# =====================================================================================
# (2a) @wire on a [HARD — pool] item COUNTS as executor-actionable → verdict=execute.
#      Control: the SAME item WITHOUT @wire is plain pool-lane hard work → verdict=hard.
#      Triangulation (id:108e): identical item, only the @wire marker differs → the
#      verdict flips execute↔hard, so a hard-coded pass can't fake it.
# =====================================================================================
RW="$tmp/r_wire"; mkrepo "$RW"
cat > "$RW/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — pool] Wire the new picker into the toolbar @wire <!-- id:aaaa -->
EOF
printf '# TODO\n## Current\n' > "$RW/TODO.md"
commit_repo "$RW"; ckpt_head "$RW"
[[ "$(verdict_of "$RW")" == "execute" ]] || { echo "FAIL (2a): [HARD — pool] @wire item must classify execute (counts toward actionable_routine_open), got $(verdict_of "$RW")"; exit 1; }

RH="$tmp/r_nowire"; mkrepo "$RH"
cat > "$RH/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — pool] Wire the new picker into the toolbar <!-- id:cccc -->
EOF
printf '# TODO\n## Current\n' > "$RH/TODO.md"
commit_repo "$RH"; ckpt_head "$RH"
[[ "$(verdict_of "$RH")" == "hard" ]] || { echo "FAIL (2-control): same item WITHOUT @wire must stay hard, got $(verdict_of "$RH")"; exit 1; }

# =====================================================================================
# (2b) @manual stays EXCLUDED — a [HARD — pool] item tagged @manual is NEVER execute
#      (the safe under-dispatch direction; must hold both before and after ac7f).
# =====================================================================================
RM="$tmp/r_manual"; mkrepo "$RM"
cat > "$RM/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — pool] Rehearse the on-device unlock flow @manual <!-- id:bbbb -->
EOF
printf '# TODO\n## Current\n' > "$RM/TODO.md"
commit_repo "$RM"; ckpt_head "$RM"
[[ "$(verdict_of "$RM")" != "execute" ]] || { echo "FAIL (2b): @manual item must NOT classify execute (stays excluded), got execute"; exit 1; }

# =====================================================================================
# (3) drained render-alias — relay/scripts/render-verdict.sh maps a classify-verdict JSON
#     on stdin to a display label. verdict=idle → "drained"; any other verdict → verbatim
#     (NEVER "drained"). This is the ONLY sanctioned emitter of the word.
# =====================================================================================
[[ -x "$RV" ]] || { echo "FAIL (3): render-verdict.sh missing (RED): $RV"; exit 1; }
out_idle="$(printf '%s' '{"verdict":"idle","reason":"x"}' | "$RV")"
[[ "$out_idle" == "drained" ]] || { echo "FAIL (3a): verdict=idle must render 'drained', got '$out_idle'"; exit 1; }
out_exec="$(printf '%s' '{"verdict":"execute","reason":"x"}' | "$RV")"
[[ "$out_exec" != "drained" && "$out_exec" == "execute" ]] || { echo "FAIL (3b): verdict=execute must render 'execute' (never 'drained'), got '$out_exec'"; exit 1; }
out_hard="$(printf '%s' '{"verdict":"hard","reason":"x"}' | "$RV")"
[[ "$out_hard" != "drained" && "$out_hard" == "hard" ]] || { echo "FAIL (3c): verdict=hard must render 'hard' (never 'drained'), got '$out_hard'"; exit 1; }

# =====================================================================================
# (1) grammar docs — `@wire` is documented in the canonical lane/grammar doc.
# =====================================================================================
[[ -f "$HL" ]] && grep -q '@wire' "$HL" || { echo "FAIL (1): @wire must be documented in relay/references/hard-lanes.md"; exit 1; }

echo "PASS: @wire grammar + classify count + drained render-alias (ac7f)"
