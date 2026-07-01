#!/usr/bin/env bash
# roadmap:e5e9 — atomic main-write fix for the id:3801 handback follow-up (seed invalid-state i).
# handback-followup.py previously WROTE ROADMAP.md (md-merge, write-only) and THEN committed it in
# a SEPARATE git-lock-push step — a death between the two stranded a dirty ROADMAP.md on the main
# checkout (relay-doctor check 9 / invariant I1). The fix routes the write+commit through md-merge
# --commit (the id:148b atomic flock pattern) BEFORE the push, so a push death leaves a clean tree.
#
# Death simulation: stub the push script (HANDBACK_GIT_LOCK_PUSH) to exit nonzero (the push "dies").
# With the fix, the tree is still CLEAN (the commit already happened atomically); with the old
# two-step code the commit lived inside the (now-dead) push, so ROADMAP.md would be left dirty.
#
# RED until handback-followup.py commits atomically via md-merge --commit.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/handback-followup.py"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "handback-followup.py not found"
python3 -c "import ast,sys; ast.parse(open('$SH').read())" || fail "handback-followup.py is not valid python"

FIX="$(mktemp -d)"; STUB="$(mktemp)"
trap 'rm -rf "$FIX" "$STUB"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] [HARD — pool] a bounded item a strong child handed back <!-- id:aaaa -->
EOF
git -C "$FIX" add -A; git -C "$FIX" commit -qm init

# Stub push script that SIMULATES A DEATH of the push step (exits nonzero, does nothing).
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
echo "simulated push death (id:e5e9 test)" >&2
exit 1
STUBEOF
chmod +x "$STUB"

# (1) Death simulation: run the handback follow-up with the dying push stub.
HANDBACK_GIT_LOCK_PUSH="$STUB" python3 "$SH" "$FIX" \
  --parent-id aaaa --route decision-gate --gate-reason "needs a design call" >/dev/null 2>&1 || true

# KEY assertion (invariant I1): NO dirty residue on the main checkout after the push died.
resid="$(git -C "$FIX" status --porcelain)"
[[ -z "$resid" ]] || fail "(1) STRANDED residue after a simulated push death (write+commit not atomic):\n$resid"
pass "(1) push died mid-follow-up → main checkout is CLEAN (no stranded ROADMAP.md)"

# The gate WAS committed atomically (before the push) — a new commit carries it.
git -C "$FIX" log -1 --format='%s' | grep -q 'handback follow-up' \
  || fail "(2) the atomic commit did not happen (no handback-follow-up commit in HEAD)"
git -C "$FIX" show HEAD:ROADMAP.md | grep -q 'GATED' \
  || fail "(2) the committed ROADMAP.md does not carry the gate"
pass "(2) the gate is committed atomically (before the push) — the write+commit are one op"

# (3) --no-commit still writes WITHOUT committing (the deliberate dry path is preserved).
# Restore the UN-gated item first (case 1 gated it in HEAD → would be an idempotent no-op).
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] [HARD — pool] a bounded item a strong child handed back <!-- id:aaaa -->
EOF
git -C "$FIX" add -A; git -C "$FIX" commit -qm 'reset roadmap (un-gated) for no-commit case'
python3 "$SH" "$FIX" --parent-id aaaa --route decision-gate --gate-reason "dry" --no-commit >/dev/null 2>&1 || true
git -C "$FIX" diff --quiet -- ROADMAP.md && fail "(3) --no-commit should leave ROADMAP.md written-but-uncommitted (dry path)"
pass "(3) --no-commit writes without committing (dry path preserved)"

echo "ALL PASS: id:e5e9 handback follow-up atomic write+commit (no stranding window)"
