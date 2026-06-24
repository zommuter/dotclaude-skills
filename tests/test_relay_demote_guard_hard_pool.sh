#!/usr/bin/env bash
# roadmap:9973 — deterministic demote-guard for a `hard` verdict on a repo with NO open
# [HARD — pool] item. Only [HARD — pool] items are pool-dispatchable (hard-lanes.md);
# [HARD — meeting]/[HARD — decision gate]/[HARD — hands] are NOT. The LLM discover-shard's
# `hard` judgment is non-deterministic and on 2026-06-24 wrongly dispatched two repos whose
# only open HARD item was [HARD — decision gate] as `hard` → pre-start size-outs (burning Opus).
# Fix (mirrors the id:000d is_finished guard): gather-repo-state.sh emits a deterministic
# `open_hard_pool` count; relay-loop.js demotes a `hard` unit whose open_hard_pool==0 to
# surfaced (DEMOTE-ONLY, injected-exempt).
#
# Two layers, both static-structural (the live Workflow is too expensive to exercise here):
#   (a) gather-repo-state.sh emits open_hard_pool and counts ONLY [HARD — pool] open items.
#   (b) relay-loop.js contains the demote-guard wiring (schema field + JS-side block).
# Hermetic: builds throwaway git repos under mktemp; never touches ~/.claude or the network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }
[[ -f "$JS" ]]     || { echo "FAIL: relay-loop.js missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

# Build a throwaway repo with a given ROADMAP body, one relay checkpoint at HEAD.
mkrepo() {  # mkrepo <dir> <roadmap-body-file>
  local r="$1" body="$2"
  mkdir -p "$r"; ( cd "$r"
    git init -q
    git config user.email t@t; git config user.name t; git config commit.gpgsign false
    cp "$body" ROADMAP.md
    git add -A; git commit -q --no-gpg-sign -m init
    git tag -a relay-ckpt-20260101-0000 -m base )
}
gather() {  # gather <dir> <repo-name>
  RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt" \
    "$GATHER" --repo "$2" --path "$1" --runid test
}

# ── (a) gather-repo-state.sh emits open_hard_pool, counting ONLY [HARD — pool] ──────────

# (1) ROADMAP with one [HARD — decision gate] + one [HARD — hands] + ZERO [HARD — pool]
#     → open_hard_pool MUST be 0 (the 2026-06-24 false-dispatch case).
cat > "$TMP/r1.md" <<'EOF'
# ROADMAP

- [ ] [HARD — decision gate] choose the storage backend <!-- id:aaaa -->
- [ ] [HARD — hands] flash the device firmware <!-- id:bbbb -->
EOF
mkrepo "$TMP/repo1" "$TMP/r1.md"
j="$(gather "$TMP/repo1" repo1)"
[[ "$(field open_hard_pool <<<"$j")" == "0" ]] \
  && ok "no [HARD — pool] item (only decision-gate + hands) → open_hard_pool=0" \
  || bad "decision-gate+hands ROADMAP must be open_hard_pool=0 (got '$(field open_hard_pool <<<"$j")')"

# (2) ROADMAP with one open [HARD — pool] item → open_hard_pool MUST be 1.
cat > "$TMP/r2.md" <<'EOF'
# ROADMAP

- [ ] [HARD — pool] refactor the parser into modules <!-- id:cccc -->
- [ ] [HARD — decision gate] choose the storage backend <!-- id:dddd -->
EOF
mkrepo "$TMP/repo2" "$TMP/r2.md"
j="$(gather "$TMP/repo2" repo2)"
[[ "$(field open_hard_pool <<<"$j")" == "1" ]] \
  && ok "one open [HARD — pool] item → open_hard_pool=1" \
  || bad "single [HARD — pool] must be open_hard_pool=1 (got '$(field open_hard_pool <<<"$j")')"

# (3) A [x]-done [HARD — pool] item must NOT count (only open '- [ ]' items).
cat > "$TMP/r3.md" <<'EOF'
# ROADMAP

- [x] [HARD — pool] already finished <!-- id:eeee -->
- [ ] [HARD — meeting] needs a design decision <!-- id:ffff -->
EOF
mkrepo "$TMP/repo3" "$TMP/r3.md"
j="$(gather "$TMP/repo3" repo3)"
[[ "$(field open_hard_pool <<<"$j")" == "0" ]] \
  && ok "a done [x] [HARD — pool] item does not count → open_hard_pool=0" \
  || bad "done [HARD — pool] must not count (got '$(field open_hard_pool <<<"$j")')"

# (4) gather emits the field at all (presence + numeric type) for a no-roadmap repo → 0.
mkdir -p "$TMP/repo4"
( cd "$TMP/repo4"; git init -q; git config user.email t@t; git config user.name t
  git config commit.gpgsign false; echo x > a; git add -A; git commit -q --no-gpg-sign -m init )
j="$(gather "$TMP/repo4" repo4)"
[[ "$(field open_hard_pool <<<"$j")" == "0" ]] \
  && ok "repo with no ROADMAP → open_hard_pool=0 (field present)" \
  || bad "no-roadmap repo must emit open_hard_pool=0 (got '$(field open_hard_pool <<<"$j")')"

# (5) A recurring-audit-marked [HARD — pool] item with NOTHING new to audit must NOT count
#     (substantive_unaudited=false; reuse the id:365b logic). Audit window = the ckpt at HEAD,
#     so no substantive commits since → it has nothing to audit → open_hard_pool=0.
cat > "$TMP/r5.md" <<'EOF'
# ROADMAP

- [ ] [HARD — pool] Strong-model audit: review + design coherence <!-- id:401c --> <!-- relay:recurring-audit -->
EOF
mkrepo "$TMP/repo5" "$TMP/r5.md"
j="$(gather "$TMP/repo5" repo5)"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "recurring-audit fixture has nothing new to audit (substantive_unaudited=false)" \
  || bad "expected substantive_unaudited=false for the recurring-audit fixture (got '$(field substantive_unaudited <<<"$j")')"
[[ "$(field open_hard_pool <<<"$j")" == "0" ]] \
  && ok "recurring-audit [HARD — pool] with nothing to audit → open_hard_pool=0" \
  || bad "vacuous recurring-audit item must not count (got '$(field open_hard_pool <<<"$j")')"

# ── (b) relay-loop.js demote-guard wiring (static-structural) ───────────────────────────

grep -q "id:9973" "$JS" \
  || bad "id:9973: no id:9973 marker in relay-loop.js (HARD-pool demote-guard rationale missing)"
grep -q "open_hard_pool: { type: 'number' }" "$JS" \
  || bad "id:9973: DISCOVER_SCHEMA does not declare unit.open_hard_pool — the JS guard's u.open_hard_pool is always undefined (dead guard)"
grep -q "open_hard_pool per repo" "$JS" \
  || bad "id:9973: shard prompt does not instruct copying open_hard_pool onto the unit — the value never reaches the JS guard"
grep -q "HARD-pool demote" "$JS" \
  || bad "id:9973: no JS-side HARD-pool demote block in relay-loop.js"
# The guard fires only on the `hard` verdict with open_hard_pool==0.
grep -qF "u.verdict === 'hard' && (u.open_hard_pool || 0) === 0" "$JS" \
  || bad "id:9973: demote condition is not (hard verdict AND open_hard_pool==0)"
# DEMOTE-ONLY + injected-exempt: the condition is guarded by !u.injected.
grep -qF "!u.injected && u.verdict === 'hard' && (u.open_hard_pool || 0) === 0" "$JS" \
  || bad "id:9973: demote guard is not injected-exempt (!u.injected) — must never demote a user-injected unit"
# The canonical surfaced reason cites the lane contract + the guard id.
grep -q "no open \[HARD — pool\] item" "$JS" \
  || bad "id:9973: surfaced reason does not name the missing [HARD — pool] lane"
grep -q "deterministic demote-guard id:9973" "$JS" \
  && ok "id:9973: surfaced reason cites the guard id (id:9973)" \
  || bad "id:9973: surfaced reason does not cite the guard id (id:9973)"

# (c) Workflow-sandbox safety: the new wiring introduced no forbidden API + JS still parses.
node --check "$JS" >/dev/null 2>&1 \
  && ok "relay-loop.js still parses (node --check)" \
  || bad "relay-loop.js fails node --check after the demote-guard edit"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: HARD-pool demote-guard (roadmap:9973)"
