#!/usr/bin/env bash
# roadmap:ebd0 — pre-push privacy gate (warn+LOG mode only).
#
# Spec (meeting docs/meeting-notes/2026-07-20-1241-privacy-gate-pre-push-ebd0.md, D1–D4):
#   hooks/pre-push-privacy-gate.sh is a git pre-push hook. On stdin it receives
#   `<local-ref> <local-sha> <remote-ref> <remote-sha>` lines; argv is `<remote-name>
#   <remote-url>`. It:
#     (D4) reads leak patterns + allowlist from a CONFIGURABLE PRIVATE file path
#          (env PRIVACY_GATE_PATTERNS, default under ~/.config); absent → no-op + notice.
#     (D1) classifies the remote from its URL — public forge → SCAN, private host → SKIP.
#     (D3) scans ONLY added diff lines, appends findings to a log AND prints loudly,
#          exits 0 — NEVER blocks (works for non-interactive/agent pushes).
#     (D2) best-effort `scan_pii` shell-out iff present (not exercised here — optional).
#
# Hermetic: a throwaway git repo under mktemp, synthetic fixture patterns only
# (NO real leak specifics), fixture public + private remote URLs. No ~/.claude, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$SRC_DIR/hooks/pre-push-privacy-gate.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$HOOK" ]] || { echo "FAIL: pre-push-privacy-gate.sh not found at $HOOK"; exit 1; }
[[ -x "$HOOK" ]] || bad "ebd0: hook is not executable (chmod +x)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── build a throwaway repo with two commits; the second adds a line carrying a
#    SYNTHETIC fixture leak token (never a real leak specific) ──
REPO="$TMP/repo"
mkdir -p "$REPO"
export GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'clean first line\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m base
SHA_A="$(git -C "$REPO" rev-parse HEAD)"
printf 'clean first line\nZZLEAKTOKEN-4242 seeded synthetic secret\nkey: -----BEGIN FIXTURE KEY-----\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m add-leak
SHA_B="$(git -C "$REPO" rev-parse HEAD)"
unset GIT_DIR GIT_WORK_TREE

# ── fixture PRIVATE pattern+allowlist file (synthetic only) ──
PAT="$TMP/patterns.txt"
cat > "$PAT" <<'EOF'
# synthetic fixture — no real leak specifics
ZZLEAKTOKEN-[0-9]+
-----BEGIN [A-Z ]*KEY-----
allow: ZZALLOWED-[0-9]+
private-host: fievel
EOF

LOG="$TMP/gate.log"
STDIN_LINE="refs/heads/main $SHA_B refs/heads/main $SHA_A"

run_hook() { # <remote-name> <remote-url>
  ( cd "$REPO" && printf '%s\n' "$STDIN_LINE" | \
      PRIVACY_GATE_PATTERNS="$PAT" PRIVACY_GATE_LOG="$LOG" \
      bash "$HOOK" "$1" "$2" ) 2>&1
}

# ── (1) PUBLIC remote: seeded pattern in an added line is logged + printed, exit 0 ──
: > "$LOG"
out="$(run_hook origin 'git@github.com:acme/repo.git')"; rc=$?
[[ $rc -eq 0 ]] && ok "ebd0: public-remote scan exits 0 (never blocks)" \
                || bad "ebd0: public-remote scan exited $rc — must be 0 (warn+log, never blocks)"
grep -q 'ZZLEAKTOKEN-4242' <<<"$out" \
  && ok "ebd0: finding is PRINTED loudly on a public push" \
  || bad "ebd0: seeded pattern not printed on a public push. Output: $out"
[[ -f "$LOG" ]] && grep -q 'ZZLEAKTOKEN-4242' "$LOG" \
  && ok "ebd0: finding is LOGGED (ref+finding) on a public push" \
  || bad "ebd0: seeded pattern not appended to the log on a public push"
# Regression: a leak pattern that STARTS WITH '-' (e.g. -----BEGIN … KEY-----) must be passed to
# grep via -e, else grep parses it as an option ("unrecognized option") and the pattern silently
# never matches — secret detection broken. Caught by a live push test 2026-07-20.
grep -q 'BEGIN FIXTURE KEY' <<<"$out" \
  && ok "ebd0: leading-dash pattern (-----BEGIN…KEY-----) matches (grep -e)" \
  || bad "ebd0: leading-dash pattern did NOT match — grep likely parsed it as an option. Output: $out"
grep -qiE 'unrecognized option|Usage: grep' <<<"$out" \
  && bad "ebd0: grep emitted an option-parse error — a pattern reached grep without -e. Output: $out" \
  || ok "ebd0: no grep option-parse error (all var patterns passed via -e)"

# ── (2) PRIVATE remote (matches fixture private-host): scan SKIPPED, exit 0 ──
: > "$LOG"
out="$(run_hook backup 'git@fievel:acme/repo.git')"; rc=$?
[[ $rc -eq 0 ]] && ok "ebd0: private-remote push exits 0" \
                || bad "ebd0: private-remote push exited $rc"
grep -q 'ZZLEAKTOKEN-4242' <<<"$out" \
  && bad "ebd0: private remote was SCANNED (leak printed) — must be skipped" \
  || ok "ebd0: private remote is SKIPPED (no scan)"
if [[ -s "$LOG" ]] && grep -q 'ZZLEAKTOKEN-4242' "$LOG"; then
  bad "ebd0: private remote logged a finding — must not scan"
else
  ok "ebd0: private remote wrote no finding to the log"
fi

# ── (3) ABSENT pattern file: clean no-op + notice, exit 0, nothing logged ──
: > "$LOG"
out="$( ( cd "$REPO" && printf '%s\n' "$STDIN_LINE" | \
    PRIVACY_GATE_PATTERNS="$TMP/does-not-exist.txt" PRIVACY_GATE_LOG="$LOG" \
    bash "$HOOK" origin 'git@github.com:acme/repo.git' ) 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] && ok "ebd0: absent pattern file is a clean no-op (exit 0)" \
                || bad "ebd0: absent pattern file exited $rc — must be a clean no-op"
grep -qiE 'no-?op|absent|not found|no pattern' <<<"$out" \
  && ok "ebd0: absent pattern file emits a notice (not silent)" \
  || bad "ebd0: absent pattern file gave no notice. Output: $out"

# ── (4) allowlisted token in an added line does NOT fire ──
export GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO"
printf 'clean first line\nZZLEAKTOKEN-4242 seeded synthetic secret\nZZALLOWED-77 intentional\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m add-allowed
SHA_C="$(git -C "$REPO" rev-parse HEAD)"
unset GIT_DIR GIT_WORK_TREE
: > "$LOG"
out="$( ( cd "$REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$SHA_C" "$SHA_B" | \
    PRIVACY_GATE_PATTERNS="$PAT" PRIVACY_GATE_LOG="$LOG" \
    bash "$HOOK" origin 'git@github.com:acme/repo.git' ) 2>&1 )"
grep -q 'ZZALLOWED-77' <<<"$out" \
  && bad "ebd0: allowlisted token fired — allowlist not honored" \
  || ok "ebd0: allowlisted token is suppressed"

# ── (5) make target exists (wires global core.hooksPath) ──
grep -qE '^install-privacy-gate:' "$SRC_DIR/Makefile" \
  && ok "ebd0: make install-privacy-gate target exists" \
  || bad "ebd0: no install-privacy-gate target in Makefile"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: pre-push privacy gate warn+log (roadmap:ebd0)"
