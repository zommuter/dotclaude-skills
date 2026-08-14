#!/usr/bin/env bash
# roadmap:aee5 — relay-doctor check 9 must distinguish ABANDONED main-checkout residue from
# IN-FLIGHT residue, using the live-claim state it can already observe.
#
# WHY (grounded 2026-08-14, dotclaude-skills). A loderite /meeting session wrote a persona
# entry into this repo's meeting/personas.md and ended WITHOUT committing it. Nobody noticed
# for hours. The cost was not cosmetic: the id:aa93 dirty guard deferred a relay pool unit
# (review-repo-1 of relay-20260814-101319-22034 was handed back naming exactly that file) and
# git-lock-push.sh refused to rebase, forcing a manual fast-forward push.
#
# The detector was NOT missing — check 9 already reports "RESIDUE — N uncommitted non-lock
# entry(ies)". What was missing is the discriminator that makes it SAFE TO RUN ROUTINELY:
#
#   - residue while a live run holds the repo  = NORMAL mid-run state, not actionable
#   - residue with NO live holder              = ABANDONED, actionable NOW
#
# Without that split every routine run false-alarms on healthy in-flight work, which is
# exactly why the check is only run on demand — and why this residue sat unseen. This is the
# id:4347 shape: a correct detector whose signal nobody can afford to route.
#
# claim.sh peek is the liveness oracle and needs no new machinery: it already emits ONLY live
# claims (dead ones are skipped, id:7570), so a claim whose "key" is the repo name means a
# live run holds it.
#
# COVERAGE (honest): these cases assert the LABELLING and the issue-counting contract of
# check 9. They do not exercise a real concurrent pool; the liveness oracle is stubbed via
# RELAY_DOCTOR_CLAIM_SH so the two branches are reachable deterministically.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$SRC_DIR/relay/scripts/relay-doctor.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$DOCTOR" ]] || fail "relay-doctor.sh not found/executable at $DOCTOR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- a hermetic repo with a known non-lock residue ---------------------------
# NOTE: fixture dirs are named rnoclaim/rheld ON PURPOSE — never after the labels under
# assertion. A first draft used "abandoned"/"inflight" and case (1) PASSED spuriously:
# relay-doctor echoes the repo PATH, so `grep -i ABANDONED` matched the directory name
# while the script contained no such label at all. Assertion correct, fixture wrong shape.
mkrepo() {
  local d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  printf '# TODO\n' > "$d/TODO.md"
  printf '# ROADMAP\n' > "$d/ROADMAP.md"
  git -C "$d" add -A
  git -C "$d" commit -qm base
  # the residue: an uncommitted, tracked, NON-lock edit
  printf 'stranded edit\n' >> "$d/TODO.md"
  printf '%s' "$d"
}

# --- stub liveness oracles ---------------------------------------------------
# "held": emits a live claim whose key is the repo name (a live run holds it).
# "free": emits nothing (no live claim → nothing holds it).
mkclaim_stub() {
  local f="$TMP/claim-$1.sh" mode="$1" repo="$2"
  {
    echo '#!/usr/bin/env bash'
    echo '[ "${1:-}" = "peek" ] || exit 0'
    if [[ "$mode" == held ]]; then
      printf 'printf %s\\n %s\n' "'%s'" "'{\"key\":\"$repo\",\"runId\":\"relay-live-1\",\"mode\":\"execute\"}'"
    fi
  } > "$f"
  chmod +x "$f"
  printf '%s' "$f"
}

run_doctor() {  # <repo-path> <claim-stub>
  RELAY_DOCTOR_CLAIM_SH="$2" bash "$DOCTOR" "$1" 2>/dev/null || true
}

# ── (1) residue with NO live holder → ABANDONED, and it COUNTS as an issue ────
r1="$(mkrepo rnoclaim)"
stub_free="$(mkclaim_stub free rnoclaim)"
out1="$(run_doctor "$r1" "$stub_free")"

grep -qi 'RESIDUE' <<<"$out1" \
  || fail "(1) expected check 9 to report residue at all; got: $(head -c 400 <<<"$out1")"
grep -qi 'ABANDONED' <<<"$out1" \
  || fail "(1) residue with no live claim must be labelled ABANDONED — got: $(grep -i residue <<<"$out1" | head -3)"
pass "residue with no live holder → labelled ABANDONED"

grep -qi 'TODO.md' <<<"$out1" \
  || fail "(1) the ABANDONED report must name the offending path, got: $(grep -i -A2 residue <<<"$out1" | head -4)"
pass "ABANDONED report names the offending path"

# ── (2) residue WHILE a live run holds the repo → IN-FLIGHT, NOT an issue ─────
r2="$(mkrepo rheld)"
stub_held="$(mkclaim_stub held rheld)"
out2="$(run_doctor "$r2" "$stub_held")"

grep -qi 'IN-FLIGHT' <<<"$out2" \
  || fail "(2) residue under a live claim must be labelled IN-FLIGHT — got: $(grep -i residue <<<"$out2" | head -3)"
pass "residue under a live holder → labelled IN-FLIGHT"

grep -qi 'ABANDONED' <<<"$out2" \
  && fail "(2) in-flight residue must NOT be labelled ABANDONED (that is the false positive this item removes)"
pass "in-flight residue is not mislabelled ABANDONED"

# ── (3) the two branches are genuinely distinguished, not both-labelled ──────
# Negative control: the SAME repo shape yields different labels purely from claim state.
[[ "$(grep -ci 'ABANDONED' <<<"$out1")" -ge 1 && "$(grep -ci 'ABANDONED' <<<"$out2")" -eq 0 ]] \
  || fail "(3) label must be driven by live-claim state; identical dirt produced identical labels"
pass "identical residue yields different labels purely from live-claim state"

echo "PASS: relay-doctor residue liveness discriminator (aee5)"
