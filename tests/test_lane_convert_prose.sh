#!/usr/bin/env bash
# DEFECT-FIX test (no roadmap item) — lane-convert.sh default RENAME path must be
# as position/backtick-aware as the --reorder path: it may rename (and flag
# [HARD — hands]) ONLY the genuine anchored PRIMARY lane tag on a `- [ ]`/`- [x]`
# CHECKBOX line (leftmost recognized BARE lane tag, ignoring backtick'd MENTIONS).
# Before the fix the rename path was a BLIND `${line//…}` transform that rewrote
# lane names quoted in PROSE, in backticks, and on non-checkbox lines, and flagged
# [HARD — hands] on any occurrence — corrupting documentation (e.g. dotclaude-skills
# ROADMAP.md prose `f599 = [HARD — pool]` and backtick'd fixture docs).
#
# Hermetic: temp fixtures in mktemp; no ~/.claude, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONV="$ROOT/relay/scripts/lane-convert.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONV" ]] || fail "lane-convert.sh not found/executable at $CONV"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

src="$tmp/ledger.md"
cat >"$src" <<'MD'
# Roadmap

## Items

- [ ] **do a thing** [HARD — pool] a genuine bounded apex item <!-- id:1111 -->
  the f599 = [HARD — pool] measure-then-decide (prose, not a checkbox)
- [ ] **meeting item** [HARD — meeting] see the `[HARD — pool]` alias note <!-- id:3333 -->
- [ ] **on-device** [HARD — hands] needs a physical device <!-- id:4444 -->
  a `[HARD — hands]` prose mention should never be flagged (non-checkbox line)
MD

out="$("$CONV" "$src" 2>"$tmp/err")"
line() { grep -F "id:$1" <<<"$out"; }

# 1. genuine primary [HARD — pool] on a checkbox line → renamed to [HARD].
grep -qF '[HARD]'        <<<"$(line 1111)" || fail "(1) genuine [HARD — pool] must convert to [HARD]"
grep -qF '[HARD — pool]' <<<"$(line 1111)" && fail "(1) genuine [HARD — pool] must be gone after convert"
pass "(1) genuine primary [HARD — pool] on a checkbox line is renamed"

# 2. a PROSE (non-checkbox) line mentioning [HARD — pool] is left UNCHANGED.
grep -qF 'the f599 = [HARD — pool] measure-then-decide' <<<"$out" \
  || fail "(2) a non-checkbox prose line must be left byte-for-byte unchanged (found rename)"
pass "(2) prose (non-checkbox) [HARD — pool] mention untouched"

# 3. genuine primary [HARD — meeting] renamed; the backtick'd `[HARD — pool]` AFTER
#    it is a MENTION and must be preserved verbatim.
l3="$(line 3333)"
grep -qF '[INPUT — meeting]' <<<"$l3" || fail "(3) genuine primary [HARD — meeting] must convert to [INPUT — meeting]"
grep -qF '`[HARD — pool]`'   <<<"$l3" || fail "(3) the backtick'd [HARD — pool] mention must be preserved verbatim"
grep -qF '[HARD]'            <<<"$l3" && fail "(3) the backtick'd mention must NOT be rewritten to [HARD]"
pass "(3) only the genuine primary tag renamed; backtick'd secondary mention preserved"

# 4. genuine primary [HARD — hands] → FLAGGED on stderr, text unchanged.
grep -qF '[HARD — hands]' <<<"$(line 4444)" || fail "(4) genuine [HARD — hands] must be left unchanged"
grep -qiF '4444' "$tmp/err" || fail "(4) genuine primary [HARD — hands] must be flagged on stderr"
pass "(4) genuine primary [HARD — hands] flagged + left unchanged"

# 5. a PROSE line mentioning [HARD — hands] must NOT be flagged.
grep -qF 'a `[HARD — hands]` prose mention should never be flagged' <<<"$out" \
  || fail "(5) the prose [HARD — hands] mention line must be left unchanged"
# The only id on a genuine hands checkbox line is 4444; the prose mention has no id
# and no checkbox, so the stderr must NOT carry the prose-line text.
grep -qF 'a `[HARD — hands]` prose mention should never be flagged' "$tmp/err" \
  && fail "(5) a non-checkbox [HARD — hands] prose mention must NOT be flagged on stderr"
pass "(5) non-checkbox [HARD — hands] prose mention not flagged"

# 6. idempotent: a second pass over already-converted output is a no-op on stdout.
printf '%s\n' "$out" >"$tmp/converted.md"
out2="$("$CONV" "$tmp/converted.md" 2>/dev/null)"
diff <(printf '%s\n' "$out") <(printf '%s\n' "$out2") >/dev/null \
  || fail "(6) lane-convert rename path must be idempotent (second pass a no-op)"
pass "(6) rename path is idempotent on already-converted input"

echo "ALL PASS: lane-convert rename path renames/flags only genuine anchored primary lane tags"
