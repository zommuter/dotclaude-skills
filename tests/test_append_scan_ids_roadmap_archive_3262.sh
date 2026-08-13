#!/usr/bin/env bash
# Defect-fix test (no roadmap item — id:3262 lives in TODO.md only). Failures always count.
# fails-against: relay-ckpt-20260813-1946 (append.sh scan_ids omits ROADMAP.archive.md — token aaa4 absent from the collision set; verified red at review 2026-08-13)
#
# DEFECT: meeting/append.sh's `scan_ids` — the collision set a new mint is checked against —
# scanned `docs/meeting-notes`, `TODO.md`, `TODO.archive.md` and `ROADMAP.md`, but NOT
# `ROADMAP.archive.md`. Note the asymmetry: the TODO ledger's archive WAS included, its
# ROADMAP twin was not. So the moment an item was archived out of ROADMAP.md its id became
# invisible to the minter and could be handed out a second time.
#
# The in-file rationale is that any file class which ORIGINATES tokens must be scanned.
# ROADMAP.archive.md holds tokens originated in ROADMAP.md — archiving does not un-originate
# them — so its exclusion was an oversight, not a ruling.
#
# CONFIRMED LIVE (fleet sweep of all 51 own repos, 2026-08-13): zkm-pdf carries TWO DISTINCT
# top-level items both tagged <!-- id:1a30 --> at ROADMAP.archive.md:76 and :115.
#
# The assertions below drive `append.sh scan-ids`, which prints the collision set directly.
# That is deterministic — asserting instead that a random mint "avoids" a token would pass
# ~65535/65536 of the time even with the defect present, i.e. a vacuous test.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SH" ]] || fail "append.sh not executable at $SH"

tmp="$(mktemp -d)"
trap 'rm -r -- "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/docs/meeting-notes"

# Each ledger file carries exactly ONE distinctive token, so a miss is attributable.
printf '# TODO\n\n- [ ] live todo item <!-- id:aaa1 -->\n'                > "$repo/TODO.md"
printf '# TODO archive\n\n- [x] archived todo item <!-- id:aaa2 -->\n'    > "$repo/TODO.archive.md"
printf '# Roadmap\n\n- [ ] live roadmap item <!-- id:aaa3 -->\n'          > "$repo/ROADMAP.md"
printf '# Roadmap archive\n\n- [x] archived roadmap item <!-- id:aaa4 -->\n' > "$repo/ROADMAP.archive.md"
printf '# note\n\nMentions <!-- id:aaa5 -->\n'                            > "$repo/docs/meeting-notes/2026-01-01-0000-x.md"

out="$("$SH" scan-ids "$repo" 2>/dev/null)"
[[ -n "$out" ]] || fail "scan-ids produced no output for the fixture"

has() { printf '%s\n' "$out" | grep -qx "$1"; }

# Regression guards — the four sources that already worked must keep working.
has aaa1 || fail "TODO.md token aaa1 missing from the collision set"
pass "TODO.md is scanned"
has aaa2 || fail "TODO.archive.md token aaa2 missing from the collision set"
pass "TODO.archive.md is scanned"
has aaa3 || fail "ROADMAP.md token aaa3 missing from the collision set"
pass "ROADMAP.md is scanned"
has aaa5 || fail "docs/meeting-notes token aaa5 missing from the collision set"
pass "docs/meeting-notes is scanned"

# THE DEFECT: a token whose ONLY occurrence is in ROADMAP.archive.md must still be in the
# collision set, or the minter will re-issue it (zkm-pdf id:1a30).
has aaa4 || fail "ROADMAP.archive.md token aaa4 is NOT in the collision set — an archived id can be re-minted (id:3262)"
pass "ROADMAP.archive.md is scanned — an archived id can no longer be re-minted"

# Symmetry, stated as its own assertion so a future edit that drops one archive but keeps
# the other fails loudly rather than silently re-opening half the hole.
has aaa2 && has aaa4 || fail "TODO.archive.md and ROADMAP.archive.md must BOTH be scanned (symmetry)"
pass "both ledger archives are scanned (symmetry holds)"

# A repo missing some ledger files is normal (not every repo is relay-managed); scan-ids must
# still succeed and report what does exist, rather than erroring out.
bare="$tmp/bare"
mkdir -p "$bare"
printf '# TODO\n\n- [ ] only file here <!-- id:bbb1 -->\n' > "$bare/TODO.md"
out2="$("$SH" scan-ids "$bare" 2>/dev/null)"
printf '%s\n' "$out2" | grep -qx bbb1 || fail "scan-ids failed on a repo with only TODO.md"
pass "missing ledger files are tolerated (partial repo still scans)"

echo "ALL PASS"
