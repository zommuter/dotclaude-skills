#!/usr/bin/env bash
# roadmap:70bc
# RED SPEC — em-dash delimiter migration, seam S0.
#
# WHAT IS MISSING: there is no mechanical way to answer "is this repo's migration
# complete?" or "is the fleet half-migrated?". Several readers already accept BOTH
# delimiters (relay/scripts/mechanical-orphan-scan.sh:98 `[INTENSIVE\s*[—-]\s*…]`,
# relay/scripts/gather-human-backlog.sh:403 `\[INPUT[[:space:]]*[—-]`), so a partial
# migration is SILENTLY ABSORBED and looks identical to a finished one. Without a
# detector, seam (B) — dropping the dual-vocab blindness — has no closing condition
# that can be checked rather than asserted.
#
# A naive `grep -c '—'` is NOT the answer, and this spec exists mainly to pin why:
# ledger prose legitimately QUOTES old spellings in audit trails (loderite affd
# reads "this line is `[HARD — pool]`"), and a strict global string ban would make
# it impossible to write history about this very migration. The detector must
# distinguish a LIVE lane tag from a PROSE MENTION, using the same anchoring
# roadmap-lint.sh rule 3(g) adopted in commit 7a86cdb3: the contiguous run of
# recognised lane brackets at the START of the item text, computed after
# backtick-quoted spans are masked, with `[INTENSIVE - <res>]` resource brackets
# stripped first so a resource-FIRST item does not stop the run dead.
#
# THE ARTEFACT: relay/scripts/lane-delimiter-scan.sh
#   usage: lane-delimiter-scan.sh [--live-only] <ledger-file>...
#   - prints one `<file>:<lineno>: <tag>` finding per LIVE em-dash-delimited lane tag
#   - exits 0 when there are none, nonzero when there are
#   - `--live-only` is the closing-condition mode; without it, prose mentions are
#     also listed but marked `(prose)` and do not affect the exit code
#
# Hermetic: fixtures in mktemp -d; no ~/.claude, no network, no repo writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/relay/scripts/lane-delimiter-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCAN" ]] \
  || fail "relay/scripts/lane-delimiter-scan.sh missing or not executable — the migration's closing-condition detector does not exist yet"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Fixture A: a fully MIGRATED ledger that still mentions old spellings in prose ─
cat >"$tmp/clean.md" <<'MD'
# Roadmap

## Current

- [ ] [HARD] a migrated pool item <!-- id:aaaa -->
- [ ] [INPUT - meeting] a migrated human lane <!-- id:bbbb -->
- [ ] [INTENSIVE - local-llm] [HARD] a migrated composed run <!-- id:cccc -->
- [ ] [HARD] [INTENSIVE - disk-io] the other order <!-- id:dddd -->
- [ ] [INPUT - access] audit trail: before the 2026-08-27 sweep this line read
      `[HARD — pool]`, and the em dash there is HISTORY, not a live lane <!-- id:eeee -->
- [ ] [INPUT - decision] the `[INTENSIVE — local-llm]` spelling is quoted here too <!-- id:ffff -->

Prose paragraph: the old venue-keyed vocabulary was `[HARD — pool]`,
`[HARD — meeting]`, `[HARD — hands]` and `[HARD — decision gate]`.
MD

set +e
out="$(bash "$SCAN" --live-only "$tmp/clean.md" 2>"$tmp/err")"; rc=$?
set -e
[[ $rc -eq 0 ]] \
  || fail "--live-only flagged a fully migrated ledger (rc=$rc) — backtick'd audit-trail mentions must not count (out: $out; err: $(cat "$tmp/err"))"
[[ -z "$out" ]] \
  || fail "--live-only printed findings for a fully migrated ledger: $out"
pass "a migrated ledger with old-spelling PROSE reports zero live findings"

# ── Fixture B: a HALF-migrated ledger — the rollback signal ────────────────────
cat >"$tmp/half.md" <<'MD'
# Roadmap

## Current

- [ ] [HARD] a migrated item <!-- id:1111 -->
- [ ] [INPUT — meeting] NOT migrated: live em-dash lane tag <!-- id:2222 -->
- [ ] [INTENSIVE — local-llm] [HARD] NOT migrated: live em-dash resource tag <!-- id:3333 -->
- [ ] [HARD — pool] NOT migrated: live em-dash old-vocab lane <!-- id:4444 -->
MD

set +e
out="$(bash "$SCAN" --live-only "$tmp/half.md" 2>"$tmp/err")"; rc=$?
set -e
[[ $rc -ne 0 ]] \
  || fail "--live-only exited 0 on a half-migrated ledger (out: $out) — a half-applied migration must be mechanically detectable"
for id in 2222 3333 4444; do
  grep -q ":$id\|id:$id\|$id" <<<"$out" \
    || fail "live em-dash tag on id:$id was not reported (out: $out)"
done
grep -q '1111' <<<"$out" \
  && fail "the already-migrated id:1111 was wrongly reported as a finding (out: $out)"
pass "a half-migrated ledger reports exactly its live em-dash tags"

# ── Fixture C: anchoring — a lane bracket AFTER prose is trailing, not live ────
cat >"$tmp/anchor.md" <<'MD'
# Roadmap

## Current

- [ ] [INPUT - access] primary lane is migrated; a stray [HARD — pool] appears
      mid-sentence as unquoted trailing prose <!-- id:5555 -->
MD

set +e
out="$(bash "$SCAN" --live-only "$tmp/anchor.md" 2>/dev/null)"; rc=$?
set -e
[[ $rc -eq 0 && -z "$out" ]] \
  || fail "a lane bracket appearing AFTER prose was treated as a live lane (rc=$rc, out: $out) — the detector must anchor on the LEADING lane run, the anchoring 7a86cdb3 adopted for roadmap-lint rule 3(g)"
pass "anchoring: only the leading lane run counts as live"

# ── Default mode: prose mentions are LISTED but do not fail ────────────────────
set +e
out="$(bash "$SCAN" "$tmp/clean.md" 2>/dev/null)"; rc=$?
set -e
[[ $rc -eq 0 ]] \
  || fail "default (non --live-only) mode exited nonzero on a migrated ledger (rc=$rc) — prose mentions are informational only"
grep -q 'prose' <<<"$out" \
  || fail "default mode did not mark the old-spelling prose mentions as (prose): $out"
pass "default mode lists prose mentions without failing"

pass "lane-delimiter-scan.sh distinguishes live lane tags from prose mentions in both directions"
