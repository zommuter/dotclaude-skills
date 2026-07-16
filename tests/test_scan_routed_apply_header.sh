#!/usr/bin/env bash
# roadmap:d515 — scan-routed.sh's APPLY-mode header must tell the truth about whether the
# run is a dry run.
#
# The defect (line ~199):
#   echo "=== routed dead-letters — APPLY mode${DRY_RUN:+' (DRY-RUN)'} ==="
# `${VAR:+...}` expands when VAR is NON-EMPTY, and the default is `DRY_RUN=0` — a non-empty
# string. So the header claims "(DRY-RUN)" on EVERY apply run, including real ones that write
# and commit. The write-gating itself is correct (it tests `-eq 1`), so this is cosmetic —
# but it makes a real apply run's output read as a no-op preview, which is exactly backwards
# for an audit trail. Observed 2026-07-16: the header said DRY-RUN while the run committed 5
# INBOUND stubs across puzzle-pwa / toesnail / zkWhale / dotclaude-skills.
#
# RED until the label is gated on the VALUE (`[[ $DRY_RUN -eq 1 ]]`) rather than emptiness.
# Hermetic: mktemp fixtures, fake SRC_DIR / relay.toml / RELAY_INBOX / CLAIM_BASE. Never
# touches ~/.claude, real repos, or the network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/scan-routed.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "scan-routed.sh not found/executable at $SH"

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; mkdir -p "$SRC"

mk_repo() { # <abs-dir>
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email z@e.st; git -C "$d" config user.name Zommuter
  printf '# TODO\n' > "$d/TODO.md"; printf '# Roadmap\n' > "$d/ROADMAP.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}
mk_repo "$SRC/myproj"

cat > "$FIX/relay.toml" <<EOF
[repos.myproj]
classification = "own"
# path: $SRC/myproj
EOF

# One class-A dead-letter so APPLY mode has something to act on and the header is printed.
cat > "$FIX/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [myproj] wire the bar pass (from meeting, note.md) <!-- routed:bbbb -->
EOF

CLAIM_BASE="$FIX/claims"; mkdir -p "$CLAIM_BASE"
run() {
  SRC_DIR="$SRC" RELAY_TOML="$FIX/relay.toml" RELAY_INBOX="$FIX/inbox.md" \
  STATE_JSON="$FIX/no-such-state.json" CLAIM_BASE="$CLAIM_BASE" \
  SCAN_ROUTED_LOG="$FIX/scan.log" "$SH" "$@"
}

# --- (1) --apply --dry-run: the header MUST advertise DRY-RUN -------------------
out_dry="$(run --apply --dry-run 2>&1)" || true
hdr_dry="$(grep -m1 'APPLY mode' <<<"$out_dry" || true)"
[[ -n "$hdr_dry" ]] || fail "(1) no 'APPLY mode' header found in --apply --dry-run output:
$out_dry"
grep -qi 'DRY-RUN' <<<"$hdr_dry" \
  || fail "(1) --dry-run header must advertise DRY-RUN; got: $hdr_dry"
pass "--apply --dry-run → header advertises DRY-RUN"

# Guard the premise: a dry run must genuinely write nothing. If this ever fails the label
# is the least of the problems.
grep -q 'routed:bbbb' "$SRC/myproj/TODO.md" \
  && fail "(1) --dry-run WROTE a stub into the target TODO — dry-run must write nothing"
pass "--apply --dry-run writes nothing (premise intact)"

# --- (2) THE POINT: a real --apply run must NOT claim DRY-RUN -------------------
out_real="$(run --apply 2>&1)" || true
hdr_real="$(grep -m1 'APPLY mode' <<<"$out_real" || true)"
[[ -n "$hdr_real" ]] || fail "(2) no 'APPLY mode' header found in real --apply output:
$out_real"
grep -qi 'DRY-RUN' <<<"$hdr_real" \
  && fail "(2) a REAL --apply run's header claims '(DRY-RUN)' — \${DRY_RUN:+...} expands on the non-empty default '0', so the audit trail reads as a no-op preview while the run actually writes and commits (id:d515); got: $hdr_real"
pass "real --apply → header does NOT claim DRY-RUN"

# Confirm the run really did write — proving (2) tested a genuinely-writing run, not a
# silently-skipped one that would make the assertion vacuous.
grep -q 'routed:bbbb' "$SRC/myproj/TODO.md" \
  || fail "(2) the real --apply run wrote no stub, so the header assertion above was vacuous:
$(cat "$SRC/myproj/TODO.md")"
pass "real --apply genuinely wrote the stub (assertion was not vacuous)"

echo "ALL PASS"
