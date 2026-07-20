#!/usr/bin/env bash
# roadmap:65f5
# RED spec (authored by /relay handoff 2026-07-20, apex) for the classifier
# not-executor-ready hybrid, ALL THREE classes (owner-ratified D2, meeting
# docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md,
# routed:1c08a). classify-repo.sh over-counts actionable_routine_open → verdict
# `execute` for items that are not executor-ready. Three structured signals:
#
#   (1) @owner-verify — owner-on-device-pending marker. Joins the conservative
#       is_human-style exclusion (excluded from actionable_routine_open) + a LOUD
#       why-not-ready surface on stderr (never a silent exclusion).
#   (2) typed `<!-- gated-on:XXXX -->` edge — blocks ONLY while the TARGET id's
#       checkbox is still OPEN, resolved via the id:46f6 typed-edge engine over the
#       repo's ROADMAP.md ∪ TODO.md (∪ TODO.archive.md). A done/[x] target does NOT
#       block; a dangling/unresolvable target does NOT block but is LOUD on stderr.
#       NEVER a bare substring read of "gated-on" (id:4da4/0d58 trap).
#   (3) SURFACED / no-RED-spec status (`⚠ SURFACED`) → the repo routes verdict
#       `handoff` (author the spec), never `execute`.
#
# Triangulation (id:108e): each class carries a marker-present/marker-absent control
# pair, so a hard-coded pass cannot fake the verdict flips.
#
# EXPECTED-RED while roadmap:65f5 is unticked (does not fail the suite).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
HL="$ROOT/relay/references/hard-lanes.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CR" ]] || fail "classify-repo.sh not found/executable at $CR"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$TMP/wt"

mkrepo()      { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; }
commit_repo() { git -C "$1" add -A; git -C "$1" commit -qm init; }
ckpt_head()   { git -C "$1" tag -a "relay-ckpt-20260101-0000" -m ckpt; }  # HEAD audited → never `review`
classify()    { "$CR" --repo "$(basename "$1")" --path "$1"; }            # stdout JSON; stderr passes through
verdict_of()  { classify "$1" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

# ═══ Class 1: @owner-verify ═══════════════════════════════════════════════════

# (1a) an @owner-verify-tagged open [ROUTINE] item is EXCLUDED from
#      actionable_routine_open → nothing else actionable → verdict=idle.
R1="$TMP/r_ownerverify"; mkrepo "$R1"
cat > "$R1/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Verify the STT fix on the pixel device @owner-verify <!-- id:aaa1 -->
EOF
printf '# TODO\n## Current\n' > "$R1/TODO.md"
commit_repo "$R1"; ckpt_head "$R1"
v="$(verdict_of "$R1")"
[[ "$v" == "idle" ]] || fail "(1a) @owner-verify [ROUTINE] item must be excluded from actionable_routine_open (expected idle, got $v)"
pass "(1a) @owner-verify item excluded → idle, not execute"

# (1c) the exclusion is LOUD: classify-repo surfaces a why-not-ready line on stderr
#      naming the item id and the marker (never a silent execute-suppression).
err1="$(classify "$R1" 2>&1 >/dev/null)"
grep -q 'aaa1' <<<"$err1" || fail "(1c) no why-not-ready surface naming id aaa1 on stderr (got: ${err1:-<empty>})"
grep -qi 'owner-verify' <<<"$err1" || fail "(1c) the why-not-ready surface does not name @owner-verify (got: ${err1:-<empty>})"
pass "(1c) loud why-not-ready surface names the excluded item + marker"

# (1b) control: the SAME item WITHOUT @owner-verify is executor-actionable → execute.
R1b="$TMP/r_ownerverify_ctl"; mkrepo "$R1b"
cat > "$R1b/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Verify the STT fix on the pixel device <!-- id:aaa1 -->
EOF
printf '# TODO\n## Current\n' > "$R1b/TODO.md"
commit_repo "$R1b"; ckpt_head "$R1b"
v="$(verdict_of "$R1b")"
[[ "$v" == "execute" ]] || fail "(1b) control without @owner-verify must stay execute (got $v)"
pass "(1b) control without the marker still classifies execute"

# ═══ Class 2: typed gated-on edge, resolved against the target checkbox ═══════

# (2a) gated-on → target OPEN (in ROADMAP, human-laned) → the gated item is NOT
#      actionable → verdict=idle.
R2="$TMP/r_gated_open"; mkrepo "$R2"
cat > "$R2/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Build the exporter <!-- gated-on:bbb2 --> <!-- id:ccc3 -->
- [ ] [INPUT — meeting] Decide the exporter format — see TODO.md <!-- id:bbb2 -->
EOF
printf '# TODO\n## Current\n' > "$R2/TODO.md"
commit_repo "$R2"; ckpt_head "$R2"
v="$(verdict_of "$R2")"
[[ "$v" == "idle" ]] || fail "(2a) [ROUTINE] item gated-on an OPEN target must be blocked (expected idle, got $v)"
pass "(2a) gated-on with OPEN target blocks (idle)"

# (2b) gated-on → target DONE ([x]) → the edge does NOT block → verdict=execute.
#      (Live-ROADMAP regression class: done items still carry the edge; an
#      unconditional substring read would block forever.)
R2b="$TMP/r_gated_done"; mkrepo "$R2b"
cat > "$R2b/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Build the exporter <!-- gated-on:bbb2 --> <!-- id:ccc3 -->
- [x] [INPUT — meeting] Decide the exporter format — DECIDED 2026-07-19 <!-- id:bbb2 -->
EOF
printf '# TODO\n## Current\n' > "$R2b/TODO.md"
commit_repo "$R2b"; ckpt_head "$R2b"
v="$(verdict_of "$R2b")"
[[ "$v" == "execute" ]] || fail "(2b) gated-on a DONE ([x]) target must NOT block (expected execute, got $v)"
pass "(2b) gated-on with DONE target does not block (execute)"

# (2c) gated-on → DANGLING target (resolves nowhere) → NOT a silent block
#      (verdict=execute) AND LOUD on stderr naming the unresolvable token.
R2c="$TMP/r_gated_dangling"; mkrepo "$R2c"
cat > "$R2c/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Build the exporter <!-- gated-on:dead --> <!-- id:ccc3 -->
EOF
printf '# TODO\n## Current\n' > "$R2c/TODO.md"
commit_repo "$R2c"; ckpt_head "$R2c"
v="$(verdict_of "$R2c")"
[[ "$v" == "execute" ]] || fail "(2c) a DANGLING gated-on target must not silently block (expected execute, got $v)"
err2c="$(classify "$R2c" 2>&1 >/dev/null)"
grep -q 'dead' <<<"$err2c" || fail "(2c) dangling gated-on target 'dead' not surfaced LOUDLY on stderr (got: ${err2c:-<empty>})"
pass "(2c) dangling gated-on target: no silent block + loud stderr surface"

# (2d) a backticked PROSE mention of gated-on is NOT an edge (never a bare
#      substring read) → verdict=execute.
R2d="$TMP/r_gated_prose"; mkrepo "$R2d"
cat > "$R2d/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Fix the scanner (its old `gated-on:bbb2` note was retired) <!-- id:eee4 -->
- [ ] [INPUT — meeting] Decide the exporter format — see TODO.md <!-- id:bbb2 -->
EOF
printf '# TODO\n## Current\n' > "$R2d/TODO.md"
commit_repo "$R2d"; ckpt_head "$R2d"
v="$(verdict_of "$R2d")"
[[ "$v" == "execute" ]] || fail "(2d) a backticked prose mention of gated-on must not block (expected execute, got $v)"
pass "(2d) prose gated-on mention is not an edge (execute)"

# (2e) gated-on → target lives ONLY in TODO.md and is OPEN → still blocks (the
#      46f6 resolution map spans ROADMAP.md ∪ TODO.md). The open untagged TODO
#      twin makes unpromoted-scan report surface=1, so the blocked repo classifies
#      `human` (surface-only) — the assertion is verdict != execute.
R2e="$TMP/r_gated_todo"; mkrepo "$R2e"
cat > "$R2e/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Build the importer <!-- gated-on:fff5 --> <!-- id:abc6 -->
EOF
cat > "$R2e/TODO.md" <<'EOF'
# TODO
## Current
- [ ] Decide the importer contract (design) <!-- id:fff5 -->
EOF
commit_repo "$R2e"; ckpt_head "$R2e"
v="$(verdict_of "$R2e")"
[[ "$v" != "execute" ]] || fail "(2e) gated-on target OPEN in TODO.md must still block the [ROUTINE] item (got execute)"
pass "(2e) gated-on resolves across TODO.md too (got $v, not execute)"

# ═══ Class 3: SURFACED / no-RED-spec → handoff, not execute ═══════════════════

# (3a) an open [ROUTINE] item carrying the ⚠ SURFACED status (no RED spec exists)
#      routes the repo to verdict=handoff (author the spec), never execute.
R3="$TMP/r_surfaced"; mkrepo "$R3"
cat > "$R3/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] ⚠ SURFACED — no RED spec: wire the importer into the CLI <!-- id:a7a7 -->
EOF
printf '# TODO\n## Current\n' > "$R3/TODO.md"
commit_repo "$R3"; ckpt_head "$R3"
v="$(verdict_of "$R3")"
[[ "$v" == "handoff" ]] || fail "(3a) a SURFACED/no-RED-spec item must route to handoff, not execute (got $v)"
pass "(3a) SURFACED item routes to handoff"

# (3b) control: the SAME item WITHOUT the SURFACED status is execute.
R3b="$TMP/r_surfaced_ctl"; mkrepo "$R3b"
cat > "$R3b/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] Wire the importer into the CLI <!-- id:a7a7 -->
EOF
printf '# TODO\n## Current\n' > "$R3b/TODO.md"
commit_repo "$R3b"; ckpt_head "$R3b"
v="$(verdict_of "$R3b")"
[[ "$v" == "execute" ]] || fail "(3b) control without SURFACED must stay execute (got $v)"
pass "(3b) control without the SURFACED status still classifies execute"

# ═══ Docs: the marker vocabulary is defined side-by-side in hard-lanes.md ═════

grep -q '@owner-verify' "$HL"   || fail "(4) hard-lanes.md does not document @owner-verify"
grep -q '@owner-accepted' "$HL" || fail "(4) hard-lanes.md does not document @owner-accepted (side-by-side with @owner-verify/@manual)"
grep -q '@manual' "$HL"         || fail "(4) hard-lanes.md no longer documents @manual"
pass "(4) hard-lanes.md documents @owner-verify / @owner-accepted / @manual side-by-side"

echo "OK: all classifier-not-ready assertions passed"
