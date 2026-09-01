#!/usr/bin/env bash
# roadmap:2065 — S9 archive carve-out for the old-vocab lane-tag ratchet.
#
# Spec (TODO/ROADMAP id:2065, owner-ratified 2026-09-01, option (a)): the S9 em-dash
# delimiter migration must rewrite old-vocab lane tags inside ROADMAP.archive.md /
# TODO.archive.md — closed [x] entries only, never dispatchable — but
# hooks/pre-commit-lane-vocab.sh's ratchet blocked those rewrites because the rewritten
# lines are ADDED lines still carrying old-vocab vocabulary. Carve-out: any staged file
# whose basename matches `*.archive.md` is skipped by the ratchet, and the skip is
# announced on stdout (never silent — mechanize-first / no-silent-no-op rule).
#
# Requirements pinned here:
#   - a staged *.archive.md with an ADDED old-vocab lane tag is ALLOWED (exit 0).
#   - a staged NON-archive file (ROADMAP.md) with the SAME added old-vocab lane tag is
#     still BLOCKED (exit nonzero) — the carve-out must not disarm the ratchet generally.
#   - the skip is visible: hook stdout names the skipped archive file.
#
# Hermetic: throwaway git repo under mktemp, fixture relay.toml, no ~/.claude, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SRC_DIR/tests/lib/hermetic-git-env.sh"
HOOK="$SRC_DIR/hooks/pre-commit-lane-vocab.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$HOOK" ]] || { echo "FAIL: pre-commit-lane-vocab.sh not found at $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'clean base line\n' > "$REPO/ROADMAP.md"
printf 'clean base line\n' > "$REPO/ROADMAP.archive.md"
git -C "$REPO" add ROADMAP.md ROADMAP.archive.md
git -C "$REPO" commit -q -m base

# fixture relay.toml marking $REPO as an own (relay-onboarded) repo, so the hook fires.
RELAYTOML="$TMP/relay.toml"
printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$REPO" > "$RELAYTOML"
export LANE_VOCAB_RELAY_TOML="$RELAYTOML"

run_rc_and_out() { # <file> <content>
  printf '%s' "$2" > "$REPO/$1"
  git -C "$REPO" add "$1"
  local out rc
  out="$( ( cd "$REPO" && bash "$HOOK" ) 2>&1 )"; rc=$?
  printf '%s\x1e%s' "$rc" "$out"
}

OLD_VOCAB=$'clean base line\n- [x] [HARD — pool] archived closed item <!-- id:2065a -->\n'

# ── (1) staged *.archive.md with an added old-vocab tag → ALLOWED (exit 0) ──────────────
res="$(run_rc_and_out "ROADMAP.archive.md" "$OLD_VOCAB")"
rc="${res%%$'\x1e'*}"; out="${res#*$'\x1e'}"
[[ "$rc" -eq 0 ]] && ok "2065: staged *.archive.md with old-vocab tag is ALLOWED (exit 0)" \
                  || bad "2065: *.archive.md was blocked (rc=$rc). Output: $out"
grep -qF "ROADMAP.archive.md" <<<"$out" \
  && ok "2065: skip is announced on stdout, naming the skipped file" \
  || bad "2065: skip was silent -- output did not name ROADMAP.archive.md. Output: $out"

# reset the archive file's staged content back to base (it was never committed, only
# staged, above) so it is not part of the next diff.
printf 'clean base line\n' > "$REPO/ROADMAP.archive.md"
git -C "$REPO" add ROADMAP.archive.md

# ── (2) staged NON-archive file (ROADMAP.md) with the SAME added old-vocab tag → BLOCKED ─
res="$(run_rc_and_out "ROADMAP.md" "$OLD_VOCAB")"
rc="${res%%$'\x1e'*}"; out="${res#*$'\x1e'}"
[[ "$rc" -ne 0 ]] && ok "2065: staged ROADMAP.md with old-vocab tag is still BLOCKED (rc=$rc)" \
                  || bad "2065: carve-out disarmed the ratchet generally -- ROADMAP.md was allowed (rc=$rc)"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: S9 archive carve-out for the lane-vocab ratchet (roadmap:2065)"
