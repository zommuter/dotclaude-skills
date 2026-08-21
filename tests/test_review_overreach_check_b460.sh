#!/usr/bin/env bash
# roadmap:b460
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:b460 is unticked. Do not weaken it to pass.
#
# WHAT THIS TEST IS AND IS NOT — stated up front, because the honest limitation matters.
# id:b460 is a REFERENCE-DOC change: it adds a step to the REVIEWER's own procedure
# (relay/references/review.md). There is no code to exercise, and inventing a fake code test
# for it would be precisely the "a test that does not test" this repo bans. So this file
# asserts the STRUCTURE and CONTENT of the new step — that it exists in a checkable,
# drift-resistant form and says the load-bearing things. The REAL enforcement is the Opus
# reviewer following the contract, exactly as for tests/test_review_tier_enumeration.sh.
#
# WHY THE STEP IS NEEDED (INBOUND routed:2ae7 from it-infra) — §2b's eight judgment-residue
# checks all assume the SPEC is right and the executor might CHEAT it; §4's spec-drift audit
# reads only repo-internal ARCHITECTURE.md/README.md. Nothing catches an HONEST implementation
# that is a strict SUPERSET of what the ratified source authorized, with a fully green suite.
# Live miss 2026-07-29 (it-infra id:3177): a RED spec's test 8 covered only a repo pushing
# nothing but main; the executor reasonably generalized to "any refs/heads/* != main is a
# publication channel"; 8/8 green, review returned substantive:false. But loderite meeting D1
# had ratified exactly ONE channel (an ff-only 'stable' bookmark), and loderite's bare repo
# carries 5 live relay/exec-* branches that would each have taken a worktree + full
# `npm ci && build` on the Pi. Caught only by a human re-read; fixed in it-infra 1cf9b8b.
# Load-bearing precisely when the handoff authored the spec in the SAME relay lineage: then
# the reviewer is the ONLY independent check and "tests pass" reuses the same blind spot.
#
# WHY AN ANCHORED FENCE AND NOT A PROSE GREP — a prose-scoped guard is the vacuous-guard
# failure id:cdcf documents: reword the sentence and the scoped region silently empties, so
# the check passes having checked nothing. The anchored region makes the scope structural.
#
# Hermetic: reads repo files only. No network, no ~/.claude writes, no temp state.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$ROOT/relay/references/review.md"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$REVIEW" ]] || { echo "FAIL: missing contract doc: $REVIEW" >&2; exit 1; }

START='<!-- overreach-check:start -->'
END='<!-- overreach-check:end -->'

n_start="$(grep -cF -- "$START" "$REVIEW" || true)"
n_end="$(grep -cF -- "$END" "$REVIEW" || true)"

if [[ "$n_start" != "1" || "$n_end" != "1" ]]; then
  note "(1) review.md must carry EXACTLY ONE anchored over-reach region ($START … $END) — found $n_start start / $n_end end markers. An anchor, not prose: a prose-scoped grep silently empties on the next reword (id:cdcf), passing while checking nothing"
  region=""
else
  region="$(awk -v s="$START" -v e="$END" '
    index($0, s) { inb=1; next }
    index($0, e) { inb=0 }
    inb { print }
  ' "$REVIEW")"
  [[ -n "${region// /}" ]] \
    || note "(1) the anchored over-reach region is EMPTY — the vacuous-guard shape the anchor exists to prevent"
fi

# Every content assertion below runs against the REGION, never the whole file, so a phrase
# that happens to appear elsewhere in review.md cannot false-green the step.
if [[ -n "$region" ]]; then
  # (2) re-read the CITED RATIFIED SOURCE — the restatement is not the source.
  grep -qiE 'ratifi' <<<"$region" \
    || note "(2) the region never mentions the RATIFIED SOURCE — the step's whole content is 'go read what was actually authorized, not the ROADMAP's restatement of it' (the derived-doc-vs-ratified-source rule)"
  grep -qiE 'cite|cited|citation' <<<"$region" \
    || note "(2) the region does not tell the reviewer to locate the item's CITED source — without that instruction the step has no input"

  # (3) the cross-repo case — in the incident the source was a meeting note in ANOTHER repo.
  grep -qiE 'another repo|other repo|cross-repo|different repo' <<<"$region" \
    || note "(3) the region does not name the CROSS-REPO case — in the live miss the ratified source was a loderite meeting note while the diff was in it-infra; a reviewer who only looks in-repo finds nothing and passes"

  # (4) the SUPERSET question, stated as the question to ask.
  grep -qiE 'superset|more than .*authoriz|beyond what .*authoriz' <<<"$region" \
    || note "(4) the region does not pose the SUPERSET question ('is the diff's behaviour a strict superset of what was authorized?') — that question IS the check"

  # (5) the consequence: FLAG and REOPEN, even with a green suite.
  grep -qiE 'flag' <<<"$region" \
    || note "(5) the region states no consequence — a check whose finding has no action is the 'loud detection that silently no-ops' anti-pattern"
  grep -qiE 'reopen' <<<"$region" \
    || note "(5) the region does not require REOPENING the item on a finding (the §2b consequence shape)"
  grep -qiE 'green' <<<"$region" \
    || note "(5) the region does not say the finding stands even with a fully GREEN suite — the suite passing is the condition under which this defect appears, so it must be named explicitly"

  # (6) the HONEST-implementation premise — this is not a gaming check.
  grep -qiE 'honest|not .*cheat|no cheating|good faith' <<<"$region" \
    || note "(6) the region does not state that it presumes an HONEST executor — without that, the step gets collapsed back into §2b's gaming checks on the next edit and stops covering the case it was added for"

  # (7) the no-cited-source case is itself a finding, not a pass.
  grep -qiE 'no .*(cited|ratified) source|cites no|without a .*source|absent .*source' <<<"$region" \
    || note "(7) the region does not handle the item that cites NO ratified source — silently passing that case reintroduces the silent-skip class (the id:cbd2 shape)"
fi

# (8) the step must be reachable from the document's own ordering — not an orphan block.
# It is sequenced AFTER the §2b residue checks (it presumes honesty), so a numbered heading
# must exist for it and must be positioned after §2b's heading.
hdr_line="$(head -1 < <(grep -nE '^#{2,3} .*(over-?reach)' "$REVIEW") | cut -d: -f1 || true)"
b2_line="$(head -1 < <(grep -nE '^### 2b\.' "$REVIEW") | cut -d: -f1 || true)"
if [[ -z "$hdr_line" ]]; then
  note "(8) review.md has no numbered heading for the over-reach step — an anchored region nothing points at is an orphan the reviewer never reaches"
elif [[ -n "$b2_line" ]] && (( hdr_line < b2_line )); then
  note "(8) the over-reach step is sequenced BEFORE §2b; it presumes the executor was honest, which is only established once the §2b residue checks have run"
fi

# (9) the region must sit INSIDE that step, not somewhere unrelated in the file.
if [[ -n "$hdr_line" && "$n_start" == "1" ]]; then
  start_line="$(head -1 < <(grep -nF -- "$START" "$REVIEW") | cut -d: -f1 )"
  (( start_line > hdr_line )) \
    || note "(9) the anchored region does not sit under the over-reach heading (region at line $start_line, heading at line $hdr_line)"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:b460 not built yet" >&2; exit 1; }
echo "ALL PASS: review.md carries an anchored OVER-REACH check (id:b460)"
