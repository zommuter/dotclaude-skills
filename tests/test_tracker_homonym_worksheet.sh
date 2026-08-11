#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:e977, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count.)
#
# id:e977 — the cross-repo homonym ADJUDICATION worksheet.
#
# What is pinned here:
#   (1) READ-ONLY over the fleet (purity, via tests/lib/assert-repo-unchanged.sh, id:758e)
#   (2) it NEVER adjudicates: tracker/homonym-allowlist.txt is untouched, and the emitted
#       DRAFT contains no bare token — pasted verbatim it still parses as STRICT
#   (3) the evidence is actually rendered: titles, (repo,id), and the cross-reference
#       signal that separates a real cross-repo link from a birthday collision
#   (4) a cross-referencing pair is triaged "needs a look", an unrelated pair is not
#   (5) the PRIVACY guard: it refuses to drop private-repo titles inside a git worktree
#   (6) fleet-import.sh's --emit-unvalidated downgrades NOTHING (exit code and the
#       untouched --state are unchanged; only the diagnostic --out appears)
#
# Hermetic: a synthetic 3-repo fleet under mktemp -d with its own relay.toml. No network,
# no ~/.claude, none of the real own repos.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$ROOT/tracker/homonym-worksheet.sh"
IMPORT="$ROOT/tracker/fleet-import.sh"
# shellcheck source=lib/assert-repo-unchanged.sh
source "$ROOT/tests/lib/assert-repo-unchanged.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$WS" ]] || fail "tracker/homonym-worksheet.sh is missing or not executable"

# --- synthetic fleet -------------------------------------------------------------------
FLEET="$tmp/fleet"
mkdir -p "$FLEET"
export SRC_DIR="$FLEET"
export RELAY_TOML="$tmp/relay.toml"

g() { local d="$1"; shift; git -C "$d" -c user.email=t@example.invalid -c user.name=t \
        -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }

mkrepo() {   # $1=dir  $2=TODO.md content
  mkdir -p "$1"
  git init -q "$1"
  printf '%s\n' "$2" > "$1/TODO.md"
  g "$1" add -A
  g "$1" commit -q --no-verify -m "init"
}

# aaaa: minted in repo-alpha and repo-beta. alpha's prose names repo-beta AND the two
#       titles share rare vocabulary => a genuine cross-repo link => "needs a look".
# bbbb: minted in repo-alpha and repo-gamma. Nothing in common at all => birthday
#       collision => bulk-confirmable.
mkrepo "$FLEET/repo-alpha" "# TODO

## Current

- [ ] [ROUTINE] Quokka telemetry exporter — mirrored in repo-beta <!-- id:aaaa -->
- [ ] [ROUTINE] Rewrite the sourdough hydration calculator <!-- id:bbbb -->"

mkrepo "$FLEET/repo-beta" "# TODO

## Current

- [ ] [ROUTINE] Quokka telemetry exporter for the shared bus <!-- id:aaaa -->"

mkrepo "$FLEET/repo-gamma" "# TODO

## Current

- [ ] [ROUTINE] Bicycle pannier inventory screen <!-- id:bbbb -->"

cat > "$RELAY_TOML" <<EOF
[repos.repo-alpha]
classification = "own"

[repos.repo-beta]
classification = "own"

[repos.repo-gamma]
classification = "own"
EOF

OUTDIR="$tmp/out"
SHEET="$OUTDIR/homonym-worksheet.md"
DRAFT="$OUTDIR/homonym-allowlist.draft.txt"

# --- 0. purity: a read-only decision aid must not mutate any scanned repo --------------
for r in repo-alpha repo-beta repo-gamma; do
  repo_state_snapshot "$FLEET/$r" > "$tmp/snap.$r"
done
live_allow_before="$(cksum < "$ROOT/tracker/homonym-allowlist.txt")"

"$WS" --outdir "$OUTDIR" > "$tmp/ws.out" 2> "$tmp/ws.err" \
  || fail "worksheet run failed: $(cat "$tmp/ws.err")"

for r in repo-alpha repo-beta repo-gamma; do
  assert_repo_unchanged "$FLEET/$r" "$tmp/snap.$r" || fail "homonym-worksheet.sh MUTATED $r"
done

# --- 1. it NEVER adjudicates ----------------------------------------------------------
[[ "$(cksum < "$ROOT/tracker/homonym-allowlist.txt")" == "$live_allow_before" ]] \
  || fail "the live homonym-allowlist.txt was MODIFIED — this tool must never adjudicate"

[[ -s "$DRAFT" ]] || fail "no draft allow-list emitted"
# The decisive property: strip comments the way fleet-import.sh does, and NOTHING is left.
if grep -vE '^\s*(#|$)' "$DRAFT" | grep -qE '^[0-9a-f]{4}$'; then
  fail "the DRAFT carries an ACCEPTED bare token — a draft must parse as STRICT"
fi
grep -q 'UNCONFIRMED aaaa' "$DRAFT" || fail "draft does not carry token aaaa behind the UNCONFIRMED marker"
grep -q 'UNCONFIRMED bbbb' "$DRAFT" || fail "draft does not carry token bbbb behind the UNCONFIRMED marker"

# fleet-import.sh must genuinely read the draft as an EMPTY (strict) allow-list.
"$IMPORT" --dry-run --state "$tmp/throwaway.json" --allowlist-file "$DRAFT" \
  > /dev/null 2> "$tmp/strict.err" && fail "import PASSED with the draft — the draft accepted a token"
grep -q 'class A, HOMONYM' "$tmp/strict.err" \
  || fail "import with the draft did not still report the class-A homonyms"

# --- 2. the evidence is rendered ------------------------------------------------------
[[ -s "$SHEET" ]] || fail "no worksheet emitted"
grep -q 'class A (homonym, adjudicable) | \*\*2\*\*' "$SHEET" || {
  grep -n 'class A' "$SHEET"; fail "class-A count is not 2"; }
grep -q 'class B (ambiguous cross-repo edge, NEVER adjudicable) | \*\*0\*\*' "$SHEET" \
  || fail "class-B count is not 0"
grep -q 'repo-alpha/aaaa' "$SHEET" || fail "worksheet does not name the minting (repo,id)"
grep -q 'Quokka telemetry exporter' "$SHEET" || fail "worksheet does not show item TITLES"
grep -q "references sibling" "$SHEET" || fail "worksheet does not report the cross-reference signal"

# --- 3. triage: cross-referencing pair vs birthday collision --------------------------
python3 - "$SHEET" <<'PY' || fail "triage put the tokens in the wrong sections"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
a = text.split("## A. Needs a look", 1)[1].split("## B. ", 1)[0]
b = text.split("## B. ", 1)[1]
assert "aaaa" in a, "the CROSS-REFERENCING token aaaa is not in 'needs a look'"
assert "bbbb" not in a, "the unrelated token bbbb was flagged as needing a look"
assert "bbbb" in b, "the unrelated token bbbb is not in the birthday-collision table"
assert re.search(r"## A\. Needs a look \(1\)", text), "section A count wrong"
assert re.search(r"## B\. Looks like a birthday collision \(1\)", text), "section B count wrong"
PY

# --- 4. PRIVACY guard: never drop private titles inside a git working tree -------------
INREPO="$FLEET/repo-alpha/subdir"
mkdir -p "$INREPO"
if "$WS" --outdir "$INREPO" > /dev/null 2> "$tmp/guard.err"; then
  fail "PRIVACY guard did not fire for an --outdir inside a git working tree"
fi
grep -q 'REFUSING to write into a git working tree' "$tmp/guard.err" \
  || fail "privacy refusal did not explain itself: $(cat "$tmp/guard.err")"
[[ ! -e "$INREPO/homonym-worksheet.md" ]] || fail "privacy guard fired but still wrote the worksheet"
# ...and --force-in-repo is the deliberate override.
"$WS" --outdir "$INREPO" --force-in-repo > /dev/null 2>&1 \
  || fail "--force-in-repo did not override the privacy guard"
[[ -s "$INREPO/homonym-worksheet.md" ]] || fail "--force-in-repo wrote nothing"
rm -rf "$INREPO"

# --- 5. --fleet without --validate-log is refused, not guessed at ---------------------
"$WS" --outdir "$tmp/out2" --fleet "$tmp/nope.json" > /dev/null 2>&1 \
  && fail "--fleet without --validate-log was accepted"

# --- 6. --emit-unvalidated downgrades NOTHING -----------------------------------------
# Same run, with and without the flag: identical exit code, --state untouched in BOTH.
: > "$tmp/empty-allow.txt"
rc_plain=0
"$IMPORT" --state "$tmp/state-plain.json" --out "$tmp/out-plain.json" \
  --allowlist-file "$tmp/empty-allow.txt" > /dev/null 2>&1 || rc_plain=$?
rc_emit=0
"$IMPORT" --state "$tmp/state-emit.json" --out "$tmp/out-emit.json" --emit-unvalidated \
  --allowlist-file "$tmp/empty-allow.txt" > /dev/null 2> "$tmp/emit.err" || rc_emit=$?
[[ "$rc_plain" -eq 3 ]] || fail "expected the strict import to fail validate with rc=3, got $rc_plain"
[[ "$rc_emit" -eq "$rc_plain" ]] \
  || fail "--emit-unvalidated CHANGED the exit code ($rc_emit vs $rc_plain) — it must downgrade nothing"
[[ ! -e "$tmp/state-emit.json" ]] \
  || fail "--emit-unvalidated wrote the durable STATE after a failed validate"
[[ ! -e "$tmp/out-plain.json" ]] || fail "--out was written after a failed validate WITHOUT the flag"
[[ -s "$tmp/out-emit.json" ]] || fail "--emit-unvalidated did not write the diagnostic --out"
grep -q 'class A, HOMONYM' "$tmp/emit.err" \
  || fail "--emit-unvalidated silenced the collision report"
"$IMPORT" --emit-unvalidated --state "$tmp/s.json" > /dev/null 2>&1 \
  && fail "--emit-unvalidated without --out was accepted"

echo "PASS: tracker/homonym-worksheet.sh — purity, never-adjudicates, evidence, triage, privacy guard, --emit-unvalidated is a no-downgrade"
