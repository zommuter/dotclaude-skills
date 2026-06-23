#!/usr/bin/env bash
# roadmap:365b — recurring-audit anti-spin gate (mechanism 1, shared primitive in
# gather-repo-state.sh). The recurring strong-model audit (id:401c) never closes by
# design; once a repo drains all other work it re-fires every round, auditing nothing
# but its OWN previous `relay: checkpoint` commit — "clean by vacuity" — burning the
# apex tier for zero output (TODO id:365b). gather must emit:
#   - substantive_unaudited (bool, FAIL-OPEN true): false iff every commit since the
#     audit ref (relay.toml last_strong_ckpt, else latest ckpt tag) is a checkpoint
#     commit or touches only uv.lock; true otherwise (and true when the ref can't resolve).
#   - work_sig (string): a signature STABLE across the pool's own checkpoint churn but
#     changing when an item closes or a substantive commit lands.
# Hermetic: builds git repos under mktemp, sandboxed relay.toml.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

# A repo with a recurring-audit ROADMAP item + a relay.toml block carrying last_strong_ckpt.
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
cat > "$REPO/ROADMAP.md" <<'EOF'
# Roadmap

## Items

- [ ] Strong-model audit: code review, security, and design coherence [HARD — pool] <!-- id:401c --> <!-- relay:recurring-audit -->
EOF
echo code > "$REPO/app.py"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
git -C "$REPO" tag -a relay-ckpt-20260101-0000 -m base
CKPT="relay-ckpt-20260101-0000"

# relay.toml block pointing the audit window at the base checkpoint.
TOML="$TMP/relay.toml"
cat > "$TOML" <<EOF
[repos.repo]
classification = "own"
last_strong_ckpt = "$CKPT"
EOF

g() { RELAY_TOML="$TOML" RELAY_WORKTREE_BASE="$TMP/wt" \
        "$GATHER" --repo repo --path "$REPO" --runid test; }

# (1) Baseline: no commits since last_strong_ckpt → nothing substantive to audit.
j="$(g)"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "no commits since ckpt → substantive_unaudited=false" \
  || bad "substantive_unaudited should be false with no commits since ckpt"
sig_base="$(field work_sig <<<"$j")"
[[ -n "$sig_base" && "$sig_base" != "None" ]] && ok "work_sig is non-empty" || bad "work_sig empty"

# (2) Add ONLY a `relay: checkpoint` commit (the pool's own churn) → still vacuous.
echo x >> "$REPO/.relay-state"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "relay: checkpoint 20260102-0000 (executor)"
j="$(g)"
[[ "$(field substantive_unaudited <<<"$j")" == "False" ]] \
  && ok "only a relay:checkpoint commit → substantive_unaudited stays false" \
  || bad "checkpoint-only commit wrongly flagged substantive"
sig_ckpt="$(field work_sig <<<"$j")"
[[ "$sig_ckpt" == "$sig_base" ]] \
  && ok "work_sig STABLE across a relay:checkpoint commit (anti-spin)" \
  || bad "work_sig changed on a checkpoint commit (would defeat the circuit breaker)"

# (3) Add a REAL code commit → substantive_unaudited becomes true, work_sig changes.
echo more >> "$REPO/app.py"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "feat: real change to audit"
j="$(g)"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "a real non-checkpoint commit → substantive_unaudited=true (audit has work)" \
  || bad "substantive commit not detected"
sig_real="$(field work_sig <<<"$j")"
[[ "$sig_real" != "$sig_base" ]] \
  && ok "work_sig CHANGES when a substantive commit lands" \
  || bad "work_sig did not change on a substantive commit"

# (4) Closing an open item changes work_sig (new work state, breaker resets).
sed -i 's/^- \[ \] Strong-model/- [x] Strong-model/' "$REPO/ROADMAP.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "relay: checkpoint 20260103-0000 (close item)"
j="$(g)"
sig_closed="$(field work_sig <<<"$j")"
[[ "$sig_closed" != "$sig_real" ]] \
  && ok "work_sig CHANGES when an open item closes" \
  || bad "work_sig did not change when an item closed"

# (5) FAIL-OPEN: no resolvable audit ref (no ckpt tag, empty last_strong_ckpt) → true.
REPO2="$TMP/repo2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q
git -C "$REPO2" config user.email t@t
git -C "$REPO2" config user.name t
echo code > "$REPO2/app.py"
git -C "$REPO2" add -A
git -C "$REPO2" commit -qm init
j="$(RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt2" \
      "$GATHER" --repo repo2 --path "$REPO2" --runid test)"
[[ "$(field substantive_unaudited <<<"$j")" == "True" ]] \
  && ok "unresolvable audit ref → substantive_unaudited=true (fail-open)" \
  || bad "fail-open broken: substantive_unaudited not true with no ref"

echo "test_recurring_audit_gate: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
