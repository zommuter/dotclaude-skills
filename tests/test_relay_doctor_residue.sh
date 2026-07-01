#!/usr/bin/env bash
# roadmap:8018 — relay-doctor check 9: main-checkout residue detector (invariant I1/I7).
# Seed invalid-state (i): a gate-detection/handback path can strand an uncommitted ledger edit
# on the main checkout (loderite id:3801 residue). Check 9 reuses clean-tree-gate.sh and counts
# a NON-lock uncommitted entry as residue; a lock-only dirty tree is benign (the pool's in-place
# relock). Report-only by default; --strict exits nonzero on a finding.
#
# RED until check 9 lands in relay-doctor.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-doctor.sh not executable"
bash -n "$SH" || fail "relay-doctor.sh fails bash -n"

FIX="$(mktemp -d)"; TOML="$(mktemp)"
trap 'rm -rf "$FIX" "$TOML"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
printf '# Roadmap\n\n## Items\n' > "$FIX/ROADMAP.md"
printf '# TODO\n' > "$FIX/TODO.md"
git -C "$FIX" add -A; git -C "$FIX" commit -qm init
# hermetic: point the once-only cross-repo checks at an empty registry
printf '' > "$TOML"
export RELAY_TOML="$TOML"

# (1) clean main checkout → check 9 reports clean, doctor exits 0.
out="$("$SH" "$FIX" 2>/dev/null)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(1) report-only must exit 0 on a clean repo; got $rc"
grep -A1 'main-checkout residue' <<<"$out" | grep -q 'clean (main checkout has no uncommitted residue)' \
  || fail "(1) clean repo not reported clean by check 9:\n$out"
pass "(1) clean main checkout → check 9 clean"

# (2) a foreign-dirty TRACKED ledger edit → RESIDUE, counted as an issue.
printf '# TODO\n- [ ] stray edit\n' > "$FIX/TODO.md"   # tracked file, uncommitted
out="$("$SH" "$FIX" 2>/dev/null)"
grep -q 'RESIDUE' <<<"$out" || fail "(2) foreign-dirty tracked edit not flagged as RESIDUE:\n$out"
grep -qE 'TODO\.md' <<<"$out" || fail "(2) residue report does not name the dirty file:\n$out"
pass "(2) foreign-dirty tracked edit → RESIDUE"

# (2b) --strict exits nonzero when residue is present.
rc=0; "$SH" --strict "$FIX" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(2b) --strict must exit nonzero with residue present; got 0"
pass "(2b) --strict exits nonzero on residue"

# (3) lock-only dirty → benign, NOT residue.
git -C "$FIX" checkout -q -- TODO.md          # drop the stray edit
printf 'lock = 1\n' > "$FIX/uv.lock"; git -C "$FIX" add uv.lock; git -C "$FIX" commit -qm 'add lock'
printf 'lock = 2\n' > "$FIX/uv.lock"          # dirty ONLY the lock file
out="$("$SH" "$FIX" 2>/dev/null)"
grep -A1 'main-checkout residue' <<<"$out" | grep -q 'dirty-lock-only' \
  || fail "(3) lock-only dirty not treated as benign:\n$(grep -A2 'main-checkout residue' <<<"$out")"
grep -q 'RESIDUE' <<<"$out" && fail "(3) lock-only dirty wrongly flagged as RESIDUE:\n$out"
pass "(3) lock-only dirty → benign, not residue"

echo "ALL PASS: id:8018 relay-doctor check 9 (main-checkout residue, I1/I7)"
