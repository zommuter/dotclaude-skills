#!/usr/bin/env bash
# roadmap:9078
# Spec for the BARE-ONLY narrowing of roadmap-lint.sh case-c (id:9078; owner-signed-off
# option (a)). Case-c (id:09a3) currently counts ALL lane brackets on a line, including
# backtick-quoted ones. That FALSE-POSITIVES the compliant id:0d58/fb7f/c3f5 shape — a
# genuine primary lane tag followed by a LATER backtick'd lane MENTION (prose/history) —
# because the quoted bracket is counted as a second lane.
#
# Narrowing (option a): case-c must count only lane tags OUTSIDE backticks and flag a
# conflict IFF ≥2 BARE (non-backtick'd) lane tags survive. This kills the false positive
# while still catching a genuine mechanical double-tag (two un-backtick'd lane tags). It
# deliberately RETIRES case-c's unreliable "prose disagrees with tag" intent (id:244b):
# that is mechanically undetectable, and its harmful sub-case (a prose bracket BEFORE the
# genuine tag) is already covered by the id:ad8a tag-first rule.
#
# RED until roadmap-lint.sh strips backtick spans before the lane count (reuse the
# id:1bbd/ad8a `first_lane_tag … strip=1` backtick-strip helper: sed -E 's/`[^`]*`//g').
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# The case-c conflict diagnostic is grep-separable from every other message by its
# "conflict" / "multiple lane brackets" wording (id:297b keeps it distinct from the
# id:ad8a tag-first WARN, which names ORDERING).
casec_re='conflict|multiple lane brackets'

# --- (a) compliant c3f5 shape: genuine-first + LATER backtick'd mention → NOT flagged ----
# One genuine BARE lane tag ([HARD - pool]) followed by a quoted historical lane MENTION
# (`[ROUTINE]`). Under bare-only case-c this is ONE bare lane → conforming → clean pass.
# printf (not a heredoc) so the SOURCE line does not itself begin with a checkbox
# carrying an old-vocab lane tag -- hooks/pre-commit-lane-vocab.sh blocks any such
# ADDED line, fixture or not.
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] %s real pool work — historically mislabeled, see the old note `[ROUTINE]` for the mention <!-- id:6666 -->\n' '[HARD - pool]'
} > "$tmp/roadmap_c3f5.md"
if ! "$LINT" "$tmp/roadmap_c3f5.md" >"$tmp/out_c3f5" 2>"$tmp/err_c3f5"; then
  echo "case-c bare-only: compliant c3f5 shape (genuine tag + later backtick'd mention) must PASS lint (exit 0)"
  echo "  got stdout: $(cat "$tmp/out_c3f5")"
  echo "  got stderr: $(cat "$tmp/err_c3f5")"
  exit 1
fi
if grep -qiE "$casec_re" "$tmp/err_c3f5" "$tmp/out_c3f5"; then
  echo "case-c bare-only: compliant c3f5 shape must NOT emit a case-c conflict diagnostic"
  echo "  got: $(cat "$tmp/err_c3f5" "$tmp/out_c3f5")"
  exit 1
fi

# --- (b) genuine TWO-BARE-tag conflict → STILL flagged -------------------------------------
# Two un-backtick'd lane tags on one line ([HARD - pool] [ROUTINE]) is a real mechanical
# double-tag; bare-only case-c must still catch it (loud ERROR + nonzero exit).
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] %s [ROUTINE] item carries two BARE lane tags on one line <!-- id:5555 -->\n' '[HARD - pool]'
} > "$tmp/roadmap_dbl.md"
if "$LINT" "$tmp/roadmap_dbl.md" >"$tmp/out_dbl" 2>"$tmp/err_dbl"; then
  echo "case-c bare-only: a genuine two-BARE-tag conflict must still ERROR (nonzero exit)"; exit 1
fi
grep -qiE "$casec_re" "$tmp/err_dbl" \
  || { echo "case-c bare-only: two-bare-tag conflict stderr must name the conflict (got: $(cat "$tmp/err_dbl"))"; exit 1; }

echo "PASS test_roadmap_lint_casec_backtick"
