#!/usr/bin/env bash
# roadmap:2313 — M2: the re-lane DOCTRINE must route compute-only/no-LLM work to
# [MECHANICAL] at all THREE contract sites that today mis-lane it to [HARD — hands].
#
# WHY (meeting amendment 2026-07-02, M2): now that `[MECHANICAL]` exists (A1) and a daemon
# (A3) can run it, three CONTRACT doc sites still route scriptable / no-human / no-LLM
# "run X" work to `[HARD — hands]` (the human):
#   (a) hard-lanes.md — the 5-criterion (a–e) pool-vs-hands re-lane policy needs a
#       "needs an LLM?" branch: compute-only + passes a–e ⇒ [MECHANICAL].
#   (b) handoff.md — the author-then-run split must route the daemon-runnable "run X"
#       residue to [MECHANICAL], keeping only genuinely-human runs as hands.
#   (c) human.md — the "you run these" human checklist must EXCLUDE [MECHANICAL]
#       (daemon-run, not human-run).
# `gather-human-backlog.sh` already excludes `[MECHANICAL]` from human buckets in CODE
# (slice-A A1) — M2 is the DOC/doctrine layer that keeps PRODUCERS from emitting
# `[HARD — hands]` for daemon-runnable work in the first place. ORTHOGONAL to B2 (the
# vocabulary rename): this routing must survive B2.
#
# STRUCTURAL (grep-style) test: asserts the bracketed `[MECHANICAL]` token appears in the
# relevant re-lane / author-then-run / you-run-these REGION of each doc. Section-scoped so
# a token dropped in an unrelated part of the file cannot false-green it. RED until the
# prose lands.
set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
HARD_LANES="$SRC_DIR_REPO/relay/references/hard-lanes.md"
HANDOFF="$SRC_DIR_REPO/relay/references/handoff.md"
HUMAN="$SRC_DIR_REPO/relay/references/human.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

for f in "$HARD_LANES" "$HANDOFF" "$HUMAN"; do
  [[ -f "$f" ]] || fail "missing contract doc: $f"
done

# region <file> <start_substr> <end_substr>: print lines from the first line CONTAINING
# start_substr up to (excluding) the next line CONTAINING end_substr. If end is never
# found, print to EOF. Substring (not regex) matching via index().
region() {
  awk -v s="$1" -v e="$2" '
    index($0, s) { inreg=1 }
    inreg && NR>startNR && index($0, e) && seenstart { exit }
    inreg {
      if (!seenstart) { seenstart=1; startNR=NR; print; next }
      if (index($0, e)) exit
      print
    }
  ' "$3"
}

# --- (a) hard-lanes.md 5-criterion re-lane policy routes compute-only → [MECHANICAL] ---
# The region: the "Lane criterion for an INTENSIVE item" subsection up to the next "##"
# heading ("Canonical marker set").
hl_region="$(region 'Lane criterion for an INTENSIVE item' 'Canonical marker set' "$HARD_LANES")"
[[ -n "$hl_region" ]] || fail "(a) could not locate the 5-criterion re-lane section in hard-lanes.md"
grep -qF '[MECHANICAL]' <<<"$hl_region" \
  || fail "(a) hard-lanes.md 5-criterion re-lane policy does not route compute-only/no-LLM work to [MECHANICAL] (needs an 'LLM?' branch)"
pass "(a) hard-lanes.md re-lane criterion routes compute-only work to [MECHANICAL]"

# --- (b) handoff.md author-then-run split routes daemon-runnable residue → [MECHANICAL] ---
# The region: the "Author-then-run split" paragraph up to the next checkpoint (C3).
hd_region="$(region 'Author-then-run split' 'C3 — spec-as-tests' "$HANDOFF")"
[[ -n "$hd_region" ]] || fail "(b) could not locate the author-then-run split section in handoff.md"
grep -qF '[MECHANICAL]' <<<"$hd_region" \
  || fail "(b) handoff.md author-then-run split does not route the daemon-runnable 'run X' residue to [MECHANICAL]"
pass "(b) handoff.md author-then-run split routes daemon-runnable residue to [MECHANICAL]"

# --- (c) human.md "you run these" triage EXCLUDES [MECHANICAL] -----------------------
# The region: from the three-tier classification / hard-lane routing (§3) through the
# "you run these" checklist (§4) to EOF. The exclusion doctrine must name [MECHANICAL].
hu_region="$(region '## 3. Three-tier classification' '<<<<<<< NEVER-MATCHES >>>>>>>' "$HUMAN")"
[[ -n "$hu_region" ]] || fail "(c) could not locate the §3/§4 triage region in human.md"
grep -qF '[MECHANICAL]' <<<"$hu_region" \
  || fail "(c) human.md 'you run these' triage does not EXCLUDE [MECHANICAL] (daemon-run, not human-run)"
pass "(c) human.md triage names [MECHANICAL] (excluded from the you-run-these human checklist)"

echo "ALL PASS: re-lane doctrine routes compute-only work to [MECHANICAL] at all three sites (id:2313)"
