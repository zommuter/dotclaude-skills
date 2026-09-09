#!/usr/bin/env bash
# roadmap:eccb
#
# Retargeted 2026-09-09 (id:11a4) from the container `id:4839` to its landed seam
# `id:eccb` ("Pin todo-conformance.sh's length measurements to CHARACTERS
# regardless of locale"), which is exactly this file's dimension-(c) coverage.
# id:4839 is `@container DECOMPOSED into seams id:eccb, id:c655, id:aa5e, id:cb9a`
# and stays open forever by design, so keying this spec to it would have granted
# permanent EXPECTED-RED cover even though id:eccb has already landed and ticked.
# This file passes green today, so the retarget is a pure keying correction --
# id:eccb being closed now means a future regression here is a real FAIL, not
# silently swallowed under id:4839.
#
# RED SPEC for dimension (c) of id:4839: the length metric is LOCALE-DEPENDENT.
#
# todo-conformance.sh measures every length and residue with bash `${#var}` (:510, :512, :525,
# :526, :528 for the reporting classes; :814 and :876 for the two regen writers). `${#var}`
# counts CHARACTERS under a UTF-8 locale and BYTES under LC_ALL=C. Measured on one real ledger
# line: 968 under de_CH.UTF-8, 986 under LC_ALL=C -- 18 apart, from 8 non-ASCII characters.
# Re-measured on TODO.md:983 during the 2026-09-05 handoff: 365 vs 367.
#
# The baselines record no locale, so a line within ~18 chars of its ceiling flips between
# `shape-grandfathered` and `shape-regrowth` on the invoking environment alone. This is not
# exotic: the fleet is mid-em-dash-migration, so multibyte characters sit on exactly the lines
# being ratcheted.
#
# THE METRIC TO STANDARDISE ON IS CHARACTERS. tools/ledger-shrink.py's candidate gate uses
# Python len() on a str, which is characters; the shell sites must agree with it regardless of
# the invoking locale, or the tool that decides whether an item is a shrink CANDIDATE and the
# tool that decides whether it REGREW are measuring different things.
#
# Pin the metric AT THE MEASUREMENT SITE, not only in the baseline format comment: the locale
# dependence originates in every ad-hoc measurement of these ledgers; the baseline is merely
# where it persists.
#
# TRIANGULATION (id:108e): the same fixture is measured through three independent surfaces
# (the length reporter, the shape reporter, and both regen writers) under two locales, and
# cross-checked against Python len(). Hard-coding one number cannot satisfy all of them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# Pick a UTF-8 locale that actually exists on this host. Without one there is nothing to
# compare LC_ALL=C against and the file would be vacuous, so this is a hard skip-with-noise,
# not a silent pass.
UTF_LOCALE=""
for cand in de_CH.utf8 de_CH.UTF-8 en_US.utf8 en_US.UTF-8 C.utf8 C.UTF-8; do
  # `< <(...)` rather than a pipe: an early-exiting consumer under `pipefail` is the id:81d5
  # shape, and tests/test_pipefail_sigpipe_lint.sh enforces that repo-wide with no exemptions.
  if grep -qx "$cand" < <(locale -a 2>/dev/null); then UTF_LOCALE="$cand"; break; fi
done
if [[ -z "$UTF_LOCALE" ]]; then
  echo "FAIL: no UTF-8 locale available on this host -- cannot compare against LC_ALL=C, and a silent pass here would be vacuous (id:4839 dimension c)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture: an over-budget head line carrying non-ASCII characters. Multibyte characters are
# spread through the residue so BOTH the head-line length and the shape residue differ between
# the two locales -- a fix that pins only one of the two reporters still fails here.
# ---------------------------------------------------------------------------
filler() { # <n> -> 60 chars per repeat, 2 non-ASCII characters per repeat
  local i
  for ((i = 0; i < $1; i++)); do
    printf 'padding prose about ledger héad lines, segment %02d hère; ' "$i"
  done
}

TOK=ab12
FIX="$tmp/ROADMAP.md"
printf -- '- [ ] [ROUTINE] **Títle for %s** %s<!-- id:%s -->\n' "$TOK" "$(filler 12)" "$TOK" > "$FIX"

# The authority for "characters", per tools/ledger-shrink.py's candidate gate.
PY_LEN="$(python3 -c 'import sys;print(len(open(sys.argv[1],encoding="utf-8").read().splitlines()[0]))' "$FIX")"
BYTE_LEN="$(head -c -1 "$FIX" | wc -c | tr -d ' ')"
if [[ "$PY_LEN" == "$BYTE_LEN" ]]; then
  report "fixture sanity: the fixture line has no multibyte characters (chars == bytes == $PY_LEN), so every assertion below would be vacuous (id:4839 dimension c)"
fi

run_at() { # <locale> <args...> -> stdout of the linter
  local loc="$1"; shift
  LC_ALL="$loc" LANG="$loc" LENGTH_BASELINE="$tmp/absent-len.txt" SHAPE_BASELINE="$tmp/absent-shape.txt" \
    bash "$SH" "$@" 2>/dev/null || true
}

# (a) The LENGTH reporter must report the same number under both locales.
#
# The length ratchet is INERT without a baseline, so it would report nothing at all here.
# Give it a deliberately unreachable ceiling: the class is then `length-grandfathered` under
# both locales and what is being compared is the CHAR COUNT it prints, not which class fired.
PERMISSIVE="$tmp/permissive-len.txt"
printf '%s\t%s\t%s\n' "ROADMAP.md" "$TOK" 99999 > "$PERMISSIVE"
# Capture-then-extract throughout: `producer | grep | head -1` is the id:81d5 pipefail shape
# the repo lint refuses, so every extraction below runs over a captured string.
first_count() { # <text> <class prefix> -> the first char count printed for that class family
  grep -oP "$2-[a-z-]+ \(\K[0-9]+" <<<"$1" | { read -r n || true; printf '%s' "${n:-}"; }
}
run_len_at() { # <locale> -> the char count from the length class line
  local out
  out="$(LC_ALL="$1" LANG="$1" LENGTH_BASELINE="$PERMISSIVE" SHAPE_BASELINE="$tmp/absent-shape.txt" \
    bash "$SH" "$FIX" 2>/dev/null || true)"
  first_count "$out" length
}
len_c="$(run_len_at C)"
len_u="$(run_len_at "$UTF_LOCALE")"
if [[ -z "$len_c" || -z "$len_u" ]]; then
  report "fixture sanity: no length-* class was reported under one or both locales (C='$len_c' UTF='$len_u') -- the fixture is not over budget and the locale assertions below cannot fire (id:4839 dimension c)"
elif [[ "$len_c" != "$len_u" ]]; then
  report "(a) LENGTH reporter is locale-dependent: LC_ALL=C reports $len_c chars, LC_ALL=$UTF_LOCALE reports $len_u -- \${#var} counts bytes under C (id:4839 dimension c)"
elif [[ "$len_c" != "$PY_LEN" ]]; then
  report "(a) LENGTH reporter disagrees with the standardised metric: reports $len_c, Python len() (ledger-shrink.py's candidate gate) says $PY_LEN chars (id:4839 dimension c)"
fi

# (b) The SHAPE reporter, independently. Its residue is a different substring of the same
# line, so a fix applied to only one measurement site is caught here.
sh_c="$(first_count "$(run_at C "$FIX")" shape)"
sh_u="$(first_count "$(run_at "$UTF_LOCALE" "$FIX")" shape)"
if [[ -z "$sh_c" || -z "$sh_u" ]]; then
  report "fixture sanity: no shape-* class was reported under one or both locales (C='$sh_c' UTF='$sh_u') -- assertion (b) cannot fire (id:4839 dimension c)"
elif [[ "$sh_c" != "$sh_u" ]]; then
  report "(b) SHAPE reporter is locale-dependent: LC_ALL=C reports $sh_c chars of residue, LC_ALL=$UTF_LOCALE reports $sh_u (id:4839 dimension c)"
fi

# (c) The two REGEN writers -- the sites that PERSIST the number. A baseline generated under
# one locale and consumed under another is the failure that actually bites, so a locale-pinned
# reporter with a locale-dependent writer is no fix at all.
regen_c="$(run_at C --regen-length-baseline "$FIX" | grep -F "$TOK" | awk '{print $NF}' || true)"
regen_u="$(run_at "$UTF_LOCALE" --regen-length-baseline "$FIX" | grep -F "$TOK" | awk '{print $NF}' || true)"
if [[ -z "$regen_c" || -z "$regen_u" ]]; then
  report "fixture sanity: --regen-length-baseline emitted no row for $TOK under one or both locales -- assertion (c) cannot fire (id:4839 dimension c)"
elif [[ "$regen_c" != "$regen_u" ]]; then
  report "(c) --regen-length-baseline PERSISTS a locale-dependent number: LC_ALL=C wrote $regen_c, LC_ALL=$UTF_LOCALE wrote $regen_u -- a baseline generated under one locale mis-ratchets under the other (id:4839 dimension c)"
fi

sregen_c="$(run_at C --regen-shape-baseline "$FIX" | grep -F "$TOK" | awk '{print $NF}' || true)"
sregen_u="$(run_at "$UTF_LOCALE" --regen-shape-baseline "$FIX" | grep -F "$TOK" | awk '{print $NF}' || true)"
if [[ -z "$sregen_c" || -z "$sregen_u" ]]; then
  report "fixture sanity: --regen-shape-baseline emitted no row for $TOK under one or both locales -- assertion (d) cannot fire (id:4839 dimension c)"
elif [[ "$sregen_c" != "$sregen_u" ]]; then
  report "(d) --regen-shape-baseline PERSISTS a locale-dependent number: LC_ALL=C wrote $sregen_c, LC_ALL=$UTF_LOCALE wrote $sregen_u (id:4839 dimension c)"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: length and residue are measured in CHARACTERS at every site, invariant under LC_ALL (id:4839 dimension c)"
fi
exit "$fail"
