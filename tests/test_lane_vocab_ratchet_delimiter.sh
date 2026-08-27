#!/usr/bin/env bash
# RED SPEC — em-dash delimiter migration, seam S3 (TODO item, not a ROADMAP item —
# no `# roadmap:` header; this file's failures always count).
#
# THE DEFECT (verified empirically 2026-08-27, before writing this spec):
#
#   hooks/pre-commit-lane-vocab.sh recognises a candidate tag from `all_lane_tags`,
#   which it SCRAPES from hard-lanes.md — but it decides whether that tag is
#   OLD-VOCAB by looking it up in `old_vocab_replacement`, an associative array
#   whose keys are HARDCODED with em dashes (~:101-105) and are NOT derived from
#   the scrape at all. The two halves therefore disagree under any delimiter change:
#
#     SSOT still em-dash  → all_lane_tags has no `[HARD - pool]`; first_lane_tag
#                           returns "" for a hyphen-delimited line → no block.
#     SSOT flipped        → all_lane_tags HAS `[HARD - pool]`, but the
#                           old_vocab_replacement key `[HARD — pool]` misses → no block.
#
#   Either way the ratchet degrades to a SILENT no-op. Measured, in a throwaway git
#   repo with the SSOT untouched:
#
#     staged `- [ ] [HARD - pool] b <!-- id:bbbb -->`  → exit=0, no output
#     staged `- [ ] [HARD — pool] c <!-- id:cccc -->`  → exit=1, "lane-vocab: BLOCKED"
#
#   NOTE this REFUTES the hazard "the ratchet may block the migration commit".
#   It does not block it. It stops working during it, without saying so.
#
# THE CONTRACT this spec pins: old-vocab-ness is a property of the LANE NAME
# (pool / meeting / hands / decision gate), not of the delimiter byte. The ratchet
# must block a newly added old-vocab lane tag in EITHER delimiter, and its
# replacement map must be derived from the same SSOT its recognition set is.
#
# Hermetic: throwaway git repo in mktemp -d; LANE_VOCAB_ALL_REPOS=1 bypasses the
# relay own-repo scoping so the fixture repo is in scope. No ~/.claude, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/pre-commit-lane-vocab.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$HOOK" ]] || fail "pre-commit-lane-vocab.sh not found at $HOOK"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cd "$tmp" || fail "cannot enter $tmp"
git init -q .
git config user.email test@example.invalid
git config user.name test

cat >ROADMAP.md <<'MD'
# Roadmap

## Current

- [ ] [ROUTINE] a baseline item <!-- id:aaaa -->
MD
git add -A
git commit -qm base --no-verify

run_hook() {
  set +e
  LANE_VOCAB_ALL_REPOS=1 bash "$HOOK" >"$tmp/out" 2>"$tmp/err"
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# stage_line <line> — reset the index AND the worktree back to the committed
# baseline, then stage exactly one appended line. `git checkout -- <path>` alone
# leaves the INDEX holding the previous case's line, which silently makes every
# later case re-test the first one (an unreached-fixture false pass — caught while
# writing this spec, exactly the trap that a green result from a harness you wrote
# yourself is supposed to be checked for).
stage_line() {
  git reset -q --hard HEAD
  printf '%s\n' "$1" >> ROADMAP.md
  git add -A
  # Prove the fixture is what we think it is before running the hook.
  git diff --cached -U0 --no-color | grep -qF -e "$1" \
    || fail "FIXTURE BROKEN: staged diff does not contain the line under test: $1"
}

# ── Control: the EM-DASH old-vocab spelling is blocked (existing behaviour) ─────
stage_line '- [ ] [HARD — pool] em-dash old vocab <!-- id:bbbb -->'
rc="$(run_hook)"
[[ "$rc" -ne 0 ]] \
  || fail "CONTROL BROKEN: the em-dash old-vocab tag was not blocked (rc=$rc) — the fixture never reached the code under test, so a green result below would be meaningless"
pass "control: em-dash [HARD — pool] is blocked (rc=$rc)"

# ── The spec: the HYPHEN old-vocab spelling must be blocked identically ─────────
stage_line '- [ ] [HARD - pool] hyphen old vocab <!-- id:cccc -->'
rc="$(run_hook)"
[[ "$rc" -ne 0 ]] \
  || fail "hyphen-delimited [HARD - pool] was NOT blocked (rc=$rc, out='$(cat "$tmp/out")', err='$(cat "$tmp/err")') — old-vocab-ness must key on the LANE NAME, not the delimiter byte"
grep -q 'BLOCKED' "$tmp/err" \
  || fail "hyphen-delimited old vocab exited nonzero but printed no BLOCKED line (err: $(cat "$tmp/err"))"
pass "hyphen-delimited [HARD - pool] is blocked with a loud BLOCKED line"

stage_line '- [ ] [HARD - meeting] hyphen old vocab, meeting lane <!-- id:dddd -->'
rc="$(run_hook)"
[[ "$rc" -ne 0 ]] \
  || fail "hyphen-delimited [HARD - meeting] was NOT blocked (rc=$rc, err='$(cat "$tmp/err")')"
grep -q 'INPUT' "$tmp/err" \
  || fail "the replacement suggestion for [HARD - meeting] does not name an [INPUT …] target (err: $(cat "$tmp/err"))"
pass "hyphen-delimited [HARD - meeting] is blocked and names its [INPUT - meeting] replacement"

# ── Negative controls: the NEW vocabulary must stay unblocked in both delimiters ─
stage_line '- [ ] [HARD] bare north-star tag <!-- id:eeee -->'
rc="$(run_hook)"
[[ "$rc" -eq 0 ]] \
  || fail "bare [HARD] (the north-star tag) was wrongly blocked (rc=$rc, err='$(cat "$tmp/err")')"

stage_line '- [ ] [INPUT - meeting] new vocab, hyphen delimiter <!-- id:ffff -->'
rc="$(run_hook)"
[[ "$rc" -eq 0 ]] \
  || fail "[INPUT - meeting] (new vocab, target delimiter) was wrongly blocked (rc=$rc, err='$(cat "$tmp/err")')"
pass "new-vocab tags stay unblocked in the target delimiter"

# ── Carve-out: a backtick'd PROSE MENTION of old vocab is not a live lane ───────
# Ledger prose legitimately quotes old vocabulary in audit trails. Strictness
# applies to LIVE lane tags only — the tag anchored in the item's leading lane run.
stage_line '- [ ] [INPUT - access] audit trail: this line used to be `[HARD - pool]` <!-- id:a1a1 -->'
rc="$(run_hook)"
[[ "$rc" -eq 0 ]] \
  || fail "a BACKTICK'D prose mention of [HARD - pool] on an [INPUT - access] item was wrongly blocked (rc=$rc, err='$(cat "$tmp/err")') — history about this migration must remain writable"
pass "backtick'd prose mentions of old vocab are not treated as live lane tags"

pass "ratchet keys old-vocab-ness on the lane name, not the delimiter, in both spellings"
