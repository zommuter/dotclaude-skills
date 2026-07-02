#!/usr/bin/env bash
# roadmap:4f02 — B1 SAFETY NET for the wave-2b lane-vocabulary rename
# (meeting 2026-07-02-1924 decision 2). Pins the two additive pieces that MUST land
# before any reader flips (B2):
#   (a) roadmap-lint.sh DUAL-ACCEPTS old AND new vocab (neither an ERROR during the
#       window); an item carrying an old lane AND its new rename is a case-c conflict.
#   (b) relay/scripts/lane-convert.sh AUTO-CONVERTS only the THREE unambiguous 1:1 renames
#       ([HARD — pool]→[HARD], [HARD — meeting]→[INPUT — meeting],
#        [HARD — decision gate]→[INPUT — decision]); leaves [ROUTINE]/[MECHANICAL]/
#        [INTENSIVE — res] untouched; and is idempotent.
#   (c) [HARD — hands] fragments across FOUR destinations
#       ({[MECHANICAL] | [INPUT — access] | [INPUT — decision] | [INPUT — meeting]}, per-item
#        judgment) so the converter LEAVES it UNCHANGED and FLAGS it for human judgment on
#        STDERR — it NEVER auto-defaults hands to any [INPUT — kind] or [MECHANICAL]
#        (aligns with M3 id:3ef7 + the conformance-sweep detector-surfaces/human-decides rule).
#
# Hermetic: temp ROADMAP fixtures; no ~/.claude, no network.
# RED until roadmap-lint learns the new vocab AND lane-convert.sh exists.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
CONV="$ROOT/relay/scripts/lane-convert.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- (a) roadmap-lint DUAL-ACCEPTS the new vocab ------------------------------
new="$tmp/ROADMAP_new.md"
cat >"$new" <<'MD'
# Roadmap

## Items

- [ ] [HARD] a bare-hard new-pool item <!-- id:bb01 -->
- [ ] [INPUT — meeting] a meeting-input item <!-- id:bb02 -->
- [ ] [INPUT — decision] a decision-input item <!-- id:bb03 -->
- [ ] [INPUT — access] an access-input item <!-- id:bb04 -->
- [ ] [MECHANICAL] a compute-only item <!-- id:bb05 -->
MD
"$LINT" "$new" >/dev/null 2>&1 \
  || fail "(a) roadmap-lint must DUAL-ACCEPT the new vocab ([HARD]/[INPUT — …]) ERROR-free"
pass "(a) roadmap-lint accepts the new capability vocabulary"

# Old vocab is STILL accepted during the dual-vocab window.
old="$tmp/ROADMAP_old.md"
cat >"$old" <<'MD'
# Roadmap

## Items

- [ ] [HARD — pool] a bounded apex item <!-- id:bc01 -->
- [ ] [HARD — meeting] a decision item <!-- id:bc02 -->
- [ ] [HARD — hands] an on-device item <!-- id:bc03 -->
MD
"$LINT" "$old" >/dev/null 2>&1 \
  || fail "(a) old vocab must still be accepted during the dual-vocab window"
pass "(a) roadmap-lint still accepts the old vocabulary (window open)"

# An item carrying an OLD lane AND its NEW rename simultaneously is a case-c conflict.
conflict="$tmp/ROADMAP_conflict.md"
cat >"$conflict" <<'MD'
# Roadmap

## Items

- [ ] [HARD — pool] [HARD] two capability lanes on one item <!-- id:bc04 -->
MD
if "$LINT" "$conflict" >/dev/null 2>&1; then
  fail "(a) an item with BOTH an old lane and its new rename must be a case-c conflict (nonzero)"
fi
pass "(a) roadmap-lint flags an old+new two-lane item as a conflict"

# --- (b) lane-convert.sh auto-converts the THREE unambiguous 1:1 renames ------
[[ -x "$CONV" ]] || fail "(b) lane-convert.sh not found/executable at $CONV — B1 not landed"

src="$tmp/ledger.md"
cat >"$src" <<'MD'
# Roadmap

## Items

- [ ] [HARD — pool] a bounded apex item <!-- id:cd01 -->
- [ ] [HARD — meeting] a decision item <!-- id:cd02 -->
- [ ] [HARD — decision gate] an auto-gated item <!-- id:cd03 -->
- [ ] [ROUTINE] a routine item <!-- id:cd05 -->
- [ ] [MECHANICAL] a compute-only item <!-- id:cd06 -->
- [ ] [ROUTINE] [INTENSIVE — local-llm] a routine intensive item <!-- id:cd07 -->
MD

out="$("$CONV" "$src" 2>/dev/null)"
line() { grep -F "id:$1" <<<"$out"; }

grep -qF '[HARD]'            <<<"$(line cd01)" || fail "(b) [HARD — pool] must convert to [HARD]"
grep -qF '[HARD — pool]'     <<<"$(line cd01)" && fail "(b) old [HARD — pool] must be gone after convert"
grep -qF '[INPUT — meeting]' <<<"$(line cd02)" || fail "(b) [HARD — meeting] must convert to [INPUT — meeting]"
grep -qF '[INPUT — decision]'<<<"$(line cd03)" || fail "(b) [HARD — decision gate] must convert to [INPUT — decision]"
grep -qF '[ROUTINE]'         <<<"$(line cd05)" || fail "(b) [ROUTINE] must be left untouched"
grep -qF '[MECHANICAL]'      <<<"$(line cd06)" || fail "(b) [MECHANICAL] must be left untouched"
grep -qF '[INTENSIVE — local-llm]' <<<"$(line cd07)" || fail "(b) [INTENSIVE — res] must be left untouched"
grep -qF '[ROUTINE]'         <<<"$(line cd07)" || fail "(b) the [ROUTINE] on the intensive item must survive"
pass "(b) lane-convert auto-applies the THREE unambiguous [HARD — *]→new-vocab renames"

# --- (c) [HARD — hands] is FLAGGED for judgment, NEVER auto-defaulted ---------
# hands fragments FOUR ways ({[MECHANICAL]|[INPUT — access]|[INPUT — decision]|[INPUT — meeting]});
# the converter must leave the line UNCHANGED and surface it for human/M3 judgment on STDERR.
src2="$tmp/ledger2.md"
cat >"$src2" <<'MD'
# Roadmap

## Items

- [ ] [HARD — hands] a plain on-device item needs a physical device <!-- id:ce01 -->
- [ ] [HARD — hands] [INTENSIVE — local-llm] run the benchmark battery on zomni <!-- id:ce02 -->
MD
out2="$("$CONV" "$src2" 2>"$tmp/err2")"
for hid in ce01 ce02; do
  l2="$(grep -F "id:$hid" <<<"$out2")"
  grep -qF '[HARD — hands]' <<<"$l2" \
    || fail "(c) [HARD — hands] ($hid) must be LEFT UNCHANGED (never auto-rewritten)"
  grep -qF '[INPUT'      <<<"$l2" && fail "(c) hands ($hid) must NOT be auto-converted to any [INPUT — kind]"
  grep -qF '[MECHANICAL]'<<<"$l2" && fail "(c) hands ($hid) must NOT be auto-converted to [MECHANICAL]"
  grep -qiF "$hid" "$tmp/err2" \
    || fail "(c) hands item ($hid) must be SURFACED for judgment on STDERR"
done
# The judgment flag must present the FOUR candidate destinations (the per-item menu).
for cand in '[MECHANICAL]' '[INPUT — access]' '[INPUT — decision]' '[INPUT — meeting]'; do
  grep -qF "$cand" "$tmp/err2" \
    || fail "(c) the hands judgment flag must name the candidate destination $cand"
done
pass "(c) [HARD — hands] is left unchanged + flagged with its four candidate destinations (never auto-defaulted)"

# --- (d) idempotent: a second pass over already-converted output is a no-op ---
printf '%s\n' "$out" >"$tmp/converted.md"
out_again="$("$CONV" "$tmp/converted.md" 2>/dev/null)"
diff <(printf '%s\n' "$out") <(printf '%s\n' "$out_again") >/dev/null \
  || fail "(d) lane-convert must be idempotent (a second pass is a no-op)"
pass "(d) lane-convert is idempotent on already-converted input"

echo "ALL PASS: wave-2b converter + dual-vocab lint safety net (id:4f02)"
