#!/usr/bin/env bash
# roadmap:a505 — `@needs-auth` convention + versioned executor-contract rule (D1/D2/D3).
#
# WHY (/meeting 2026-07-14-1135, D1/D2/D3): a relay child that hits an interactive-auth /
# human-held-secret wall today STRANDS the rest of its unit — there was no convention for
# recording "this needs a human secret" and no contract rule telling a child to
# record-and-continue. This item (id:a505) fixes:
#   D1/D2 — the `@needs-auth` marker convention (broad definition, orthogonal to @manual,
#           carrier = a per-repo REVIEW_ME.md box, FOUR mandatory fields);
#   D3    — a VERSIONED executor-contract rule (record-and-continue), bumping the contract
#           marker v6 -> v7 with the CLAUDE.md pointer kept in lockstep (no version skew);
#   wiring — roadmap-lint.sh RECOGNIZES `@needs-auth` (never flags it unknown/untagged).
# The AI-free offline lister that FILTERS these boxes is a separate item (id:1750).
#
# Asserts:
#   (1) the convention doc (hard-lanes.md) defines `@needs-auth` and lists all FOUR
#       mandatory fields (what-secret / where-it-goes / exact-command / why);
#   (2) roadmap-lint.sh does NOT flag an `@needs-auth`-marked ROADMAP item (clean exit 0);
#   (3) the executor-contract marker is v7 AND the CLAUDE.md pointer matches v7 (no skew);
#   (4) the D3 record-and-continue contract rule text is present in executor-contract.md.
#
# Hermetic: only reads in-repo docs + runs roadmap-lint on a temp ROADMAP.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
VOCAB="$SRC_DIR_REPO/relay/references/hard-lanes.md"
CONTRACT="$SRC_DIR_REPO/relay/references/executor-contract.md"
CLAUDE_MD="$SRC_DIR_REPO/CLAUDE.md"
LINT="$SRC_DIR_REPO/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$VOCAB" ]]     || fail "lane vocabulary doc missing at $VOCAB"
[[ -f "$CONTRACT" ]]  || fail "executor-contract doc missing at $CONTRACT"
[[ -f "$CLAUDE_MD" ]] || fail "CLAUDE.md missing at $CLAUDE_MD"
[[ -x "$LINT" ]]      || fail "roadmap-lint.sh not found/executable at $LINT"

# --- (1) convention doc defines @needs-auth + the FOUR mandatory fields --------
grep -qF '@needs-auth' "$VOCAB" || fail "hard-lanes.md does not define the @needs-auth marker"
for field in 'what-secret' 'where-it-goes' 'exact-command'; do
  grep -qF "$field" "$VOCAB" || fail "hard-lanes.md @needs-auth convention is missing mandatory field '$field'"
done
# the fourth field is 'why' — assert it is named as a mandatory field (avoid matching the
# ubiquitous English word by requiring the four-field enumeration to be present together).
grep -qiE 'what-secret|where-it-goes|exact-command' "$VOCAB" \
  && grep -qiE '\bwhy\b' "$VOCAB" \
  || fail "hard-lanes.md @needs-auth convention does not enumerate the fourth field (why)"

# --- (2) roadmap-lint recognizes @needs-auth (no unknown/untagged flag) --------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD — hands] Provide the Signal linked-device QR @needs-auth <!-- id:1234 -->
- [ ] [HARD — pool] An ordinary pool item with no marker <!-- id:5678 -->
MD

set +e
lint_out="$(bash "$LINT" "$tmp/ROADMAP.md" 2>"$tmp/lint_err")"
lint_rc=$?
set -e
[[ $lint_rc -eq 0 ]] \
  || fail "roadmap-lint FLAGGED an @needs-auth-marked item (rc=$lint_rc, out: $lint_out, err: $(cat "$tmp/lint_err"))"
! grep -qi 'unknown\|untagged\|NO recognized' "$tmp/lint_err" \
  || fail "roadmap-lint stderr treats @needs-auth as an unknown/untagged marker (err: $(cat "$tmp/lint_err"))"

# --- (3) contract marker v7 AND CLAUDE.md pointer matches (no version skew) ----
contract_v="$(grep -oE 'relay-executor contract v[0-9]+' "$CONTRACT" | head -1 | grep -oE 'v[0-9]+')"
pointer_v="$(grep -oE 'relay-executor contract v[0-9]+' "$CLAUDE_MD"  | head -1 | grep -oE 'v[0-9]+')"
[[ "$contract_v" == "v7" ]] || fail "executor-contract marker is '$contract_v', expected v7"
[[ "$pointer_v"  == "v7" ]] || fail "CLAUDE.md pointer is '$pointer_v', expected v7"
[[ "$contract_v" == "$pointer_v" ]] || fail "version skew: contract=$contract_v vs pointer=$pointer_v"

# --- (4) the D3 record-and-continue contract rule text is present --------------
grep -qF '@needs-auth' "$CONTRACT" || fail "executor-contract.md is missing the @needs-auth (D3) rule"
grep -qi 'record-and-continue\|record.*box.*continue\|RECORDS a conforming' "$CONTRACT" \
  || fail "executor-contract.md @needs-auth rule does not state record-and-continue"

pass "@needs-auth convention (4 fields) + v7 contract rule (no skew) + roadmap-lint recognition (a505)"
