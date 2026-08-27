#!/usr/bin/env bash
# roadmap:71d6
# RED SPEC — em-dash delimiter migration, seam S1.
#
# THE DEFECT (verified empirically 2026-08-27, before writing this spec):
#
#   Three readers scrape the lane vocabulary out of relay/references/hard-lanes.md
#   with an EM-DASH-HARDCODED `grep -oE '\[HARD — …\]'`, and each falls back to a
#   HARDCODED EM-DASH vocabulary when the scrape yields nothing:
#
#     relay/scripts/lane-convert.sh          ~:73/81  → fallback ~:76/84   SILENT
#     relay/scripts/roadmap-lint.sh          ~:131/189 → fallback ~:135/193 warns
#     hooks/pre-commit-lane-vocab.sh         ~:81/89  → fallback ~:84/92   SILENT
#
#   Consequence: flip the SSOT doc to `[HARD - pool]` and all three keep enforcing
#   the OLD em-dash vocabulary while the doc reads new. lane-convert.sh and the
#   ratchet hook do it with ZERO output. This is the id:d35a silent-no-op class
#   inside the very tooling built to prevent it.
#
#   Observed, verbatim, with a hyphen-flipped hard-lanes.md and a ROADMAP holding
#   `- [ ] [HARD — pool] leftover old tag <!-- id:aaaa -->`:
#     lane-convert.sh --dry-run  → rc=0, stderr EMPTY, still rewrote the em-dash
#                                  tag to [HARD] from the fallback set
#     roadmap-lint.sh            → 2 × "WARNING — could not read … using built-in
#                                  fallback set", then linted normally
#
# THE CONTRACT this spec pins:
#   (1) The fallback vocabularies are DELETED. A failed/empty scrape must FAIL
#       LOUDLY (nonzero + stderr), never substitute a hardcoded guess.
#   (2) The readers' scrape regexes accept the CANONICAL delimiter that the SSOT
#       doc actually uses, so flipping the doc flips the readers with it.
#
# Hermetic: works entirely inside mktemp -d on a COPY of relay/; no ~/.claude,
# no network, no writes to the repo.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Part 1: source-level — the hardcoded em-dash fallbacks must be GONE ─────────
# A fallback that merely gets its delimiter updated is still the landmine: it lets
# a broken scrape look like a working one. The migration DELETES them.
for f in relay/scripts/lane-convert.sh relay/scripts/roadmap-lint.sh hooks/pre-commit-lane-vocab.sh; do
  # The fallback is recognisable by its literal multi-lane assignment:
  #   hard_lanes=$'[HARD — pool]\n[HARD — meeting]…'  (or the hyphen equivalent)
  if grep -qE "(hard_lanes|input_lanes)=\\\$'\[" "$ROOT/$f"; then
    # `grep | head -2` is the id:7518 / id:81d5 pipefail class the repo's own lint
    # forbids: head exits early, grep takes SIGPIPE, pipefail promotes it. Read the
    # matches into an array via process substitution and slice them without a pipe.
    mapfile -t _fb_hits < <(grep -nE "(hard_lanes|input_lanes)=\\\$'\[" "$ROOT/$f")
    fail "$f still carries a HARDCODED lane-vocabulary fallback — the migration deletes it so a failed scrape fails loudly (grep: ${_fb_hits[0]:-} ${_fb_hits[1]:-})"
  fi
done
pass "no reader carries a hardcoded lane-vocabulary fallback"

# ── Part 2: behavioural — a scrape that yields nothing must be LOUD ─────────────
# Build an isolated relay/ copy whose hard-lanes.md contains NO lane tags at all.
cp -r "$ROOT/relay" "$tmp/relay"
cat >"$tmp/relay/references/hard-lanes.md" <<'MD'
# lane vocabulary

This fixture deliberately declares NO lane tags at all, to prove the readers do not
substitute a hardcoded guess when the scrape comes back empty.
MD

cat >"$tmp/ROADMAP.md" <<'MD'
# Roadmap

## Current

- [ ] [ROUTINE] a plain item <!-- id:aaaa -->
MD

set +e
lc_out="$(bash "$tmp/relay/scripts/lane-convert.sh" --dry-run "$tmp/ROADMAP.md" 2>"$tmp/lc_err")"; lc_rc=$?
set -e
if [[ $lc_rc -eq 0 && ! -s "$tmp/lc_err" ]]; then
  fail "lane-convert.sh SILENTLY tolerated an empty lane scrape (rc=$lc_rc, stderr empty) — it must fail loudly, not fall back to a hardcoded vocabulary"
fi
pass "lane-convert.sh fails loudly on an empty lane scrape"

set +e
bash "$tmp/relay/scripts/roadmap-lint.sh" "$tmp/ROADMAP.md" >"$tmp/rl_out" 2>"$tmp/rl_err"; rl_rc=$?
set -e
grep -q 'fallback' "$tmp/rl_err" \
  && fail "roadmap-lint.sh still announces a 'built-in fallback set' — the fallback must be deleted, not warned about (err: $(head -3 "$tmp/rl_err" | tr '\n' ' '))"
[[ $rl_rc -ne 0 || -s "$tmp/rl_err" ]] \
  || fail "roadmap-lint.sh silently tolerated an empty lane scrape (rc=$rl_rc, stderr empty)"
pass "roadmap-lint.sh fails loudly on an empty lane scrape, without a fallback set"

# ── Part 3: the canonical delimiter round-trips SSOT → reader ──────────────────
# With hard-lanes.md declaring the HYPHEN spelling (the migration target), the
# converter must recognise `[HARD - pool]` as the pool lane and rename it to the
# bare `[HARD]` north-star tag. Today the scrape misses it and the em-dash fallback
# does not contain it, so the tag passes through untouched.
cat >"$tmp/relay/references/hard-lanes.md" <<'MD'
# lane vocabulary

| Lane tag | Disposition |
|---|---|
| `[HARD - pool]` | pool |
| `[HARD - meeting]` | meeting |
| `[HARD - hands]` | hands |
| `[HARD - decision gate]` | meeting |

New vocabulary: `[INPUT - meeting]`, `[INPUT - decision]`, `[INPUT - access]`,
`[INPUT - author]`. Resource axis: `[INTENSIVE - local-llm]`.
MD

cat >"$tmp/ROADMAP2.md" <<'MD'
# Roadmap

## Current

- [ ] [HARD - pool] a hyphen-delimited pool item <!-- id:bbbb -->
MD

set +e
conv="$(bash "$tmp/relay/scripts/lane-convert.sh" --dry-run "$tmp/ROADMAP2.md" 2>"$tmp/c_err")"
set -e
grep -q '^- \[ \] \[HARD\] a hyphen-delimited pool item' <<<"$conv" \
  || fail "lane-convert.sh did not recognise the SSOT's own [HARD - pool] spelling — the scrape regex is still em-dash-hardcoded (got: $(grep -m1 'hyphen-delimited' <<<"$conv"))"
pass "lane-convert.sh reads the canonical delimiter from the SSOT and renames on it"

pass "SSOT delimiter is authoritative for every reader; no silent fallback survives"
