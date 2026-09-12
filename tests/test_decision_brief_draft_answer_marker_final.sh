#!/usr/bin/env bash
# Defect-fix spec for `decision-brief/docket.sh draft-answer` (id:6fda's one write path).
# Found by the id:401c strong-model audit, Run 73 (2026-09-12). No `# roadmap:` header:
# this pins a DEFECT, not a roadmap item, so its failures always count.
#
# THE DEFECT
#   `cmd_draft_answer` builds its proposed line with
#       proposed="${existing%%<!-- id:$item_id -->}"
#   which strips a SUFFIX. On a line whose anchored marker is NOT line-final the strip
#   silently no-ops, and the tool then APPENDS a second `<!-- id:XXXX -->`. The resulting
#   line carries TWO anchored markers, which `meeting/md-merge.py` and
#   `relay/scripts/lib-typed-edges.sh` both REFUSE outright (id:6059) -- so the item
#   becomes unaddressable by every anchored-id writer, and `typed_edges_own_id_of_line`
#   resolves it to nothing. Silent ledger damage, produced by the one write path in a
#   skill whose whole contract is "never write without owner confirmation".
#
#   Reachable, and not a corner: measured 2026-09-12 on this repo, 14 open `TODO.md` items
#   and 22 open `ROADMAP.md` items carry a non-line-final anchored marker. `ROADMAP.md`'s
#   `id:32c3` is one of them AND is an `[INPUT - decision]` item, i.e. exactly the kind of
#   row the docket offers the owner and `draft-answer` is then pointed at.
#
# THE FIX PINNED HERE: REFUSE (exit 7), do not guess. Inserting the marker "somewhere
#   before the trailing run" is the guess this repo's sibling tool refuses for the same
#   stated reason (review-box-tick.py, id:6d7e): a physical ledger line is not a
#   semantically complete unit, so there is no safe place to splice. The remedy is at the
#   source line.
#
# CONTROLS: case (a) is the POSITIVE control -- a line-final marker must still be accepted
#   and must still produce exactly one marker. Without it, a tool that refused everything
#   would pass case (b) and be exactly as broken.
#
# HERMETIC: fixture ledgers under `mktemp -d`; the tool is invoked with --repo-path into
#   that temp tree and WITHOUT `--apply`, so nothing is written anywhere at any point.
#
# fails-against-rev: a0ebb5110e874a51deb712be1d701620e64f516e -- decision-brief/docket.sh
# fails-against-assertion: anchored id markers -- md-merge.py
#   NOTE: at the parent revision case (b) fires TWO FAIL lines from a non-exiting
#   accumulator (the exit-code check, then the duplicate-marker check). Per the repo rule
#   this declaration names the LAST one. Case (a) is reachable and PASSES at the parent --
#   that is what makes (b)'s failure the specific one this file claims.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/decision-brief/docket.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -r "$SCRIPT" ]] || { echo "FAIL: docket.sh not found at $SCRIPT"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
{
  printf -- '- [ ] [INPUT - decision] Marker is line-final <!-- id:aaaa -->\n'
  printf -- '- [ ] [INPUT - decision] Marker has prose after it <!-- id:bbbb --> -- GATED (auto): note\n'
} > "$repo/TODO.md"

run_draft() {
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  bash "$SCRIPT" draft-answer --repo-path "$repo" --id "$1" \
      --answer 'option (a)' --answer-src 'docs/meeting-notes/x.md' --date 2026-09-12 2>&1
}

# --- (a) POSITIVE CONTROL: a line-final marker is accepted, exactly one marker out ------
out_a="$(run_draft aaaa)"; rc_a=$?
n_a="$(printf '%s\n' "$out_a" | grep '^propose:' | grep -o -- '<!-- id:aaaa -->' | grep -c . || true)"
if [[ $rc_a -eq 0 && "$n_a" == "1" ]]; then
  pass "(a) line-final marker accepted, proposal carries exactly one anchored marker"
else
  fail "(a) positive control broke: rc=$rc_a markers=$n_a -- the fixture never reached the tool"
fi

# --- (b) THE DEFECT: a non-line-final marker must be REFUSED, never duplicated ----------
out_b="$(run_draft bbbb)"; rc_b=$?
n_b="$(printf '%s\n' "$out_b" | grep '^propose:' | grep -o -- '<!-- id:bbbb -->' | grep -c . || true)"

if [[ $rc_b -eq 7 ]]; then
  pass "(b) non-line-final marker refused with the dedicated exit 7"
else
  fail "(b) expected exit 7 for a non-line-final anchored marker, got rc=$rc_b"
fi

# --- (c) the refusal is LOUD and names the condition, not a bare status -----------------
# Herestring, not a pipe: `grep -q` exits on its first match, and an early-exiting pipe
# consumer under `pipefail` is the id:81d5 shape this repo lints for.
if grep -qi 'not line-final' <<<"$out_b"; then
  pass "(c) the refusal names the actual condition on stderr"
else
  fail "(c) the refusal printed no message naming the non-line-final marker"
fi

# Ordered LAST among the assertions that fail at the parent revision, so the file's
# `# fails-against-assertion:` declaration names the final FAIL line (repo rule).
if [[ "$n_b" -le 1 ]]; then
  pass "(b) no duplicated anchored marker was proposed"
else
  fail "(b) the proposed line carries $n_b anchored id markers -- md-merge.py and lib-typed-edges.sh both REFUSE such a line (id:6059), so the item would become unaddressable"
fi

# --- (d) nothing was written: the fixture ledger is byte-identical ----------------------
if grep -qF -- '- [ ] [INPUT - decision] Marker has prose after it <!-- id:bbbb --> -- GATED (auto): note' "$repo/TODO.md" \
   && [[ "$(grep -c . "$repo/TODO.md")" == "2" ]]; then
  pass "(d) the fixture ledger is untouched"
else
  fail "(d) the fixture ledger changed -- draft-answer wrote without --apply"
fi

if [[ $fails -eq 0 ]]; then
  echo "OK: draft-answer refuses a non-line-final anchored marker instead of duplicating it"
  exit 0
fi
echo "FAILED: $fails assertion(s)"
exit 1
