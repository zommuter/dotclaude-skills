#!/usr/bin/env bash
# roadmap:c97c — the twin check that authorises a DESTRUCTIVE `inbox-done` must require
# the token to be the target line's OWN marker, never a bare mention in running prose.
#
# THE DEFECT (reproduced live 2026-08-14; three items destroyed: three routed tokens
# recovered by hand from `git show HEAD:todo-inbox.md`). `scan-routed.sh --apply` decides
# "this inbox item already landed, so draining it is safe" with
#     grep -qsE -- "(routed|id):$tok([^0-9a-f]|$)" TODO.md ROADMAP.md
# (via the shared primitive `token_marker_in_files` in relay/scripts/lib-anchored-id.sh).
# That anchors the `routed:`/`id:` PREFIX and a trailing non-hex boundary — but NOT the
# requirement that the token be the line's own marker. A prose cross-reference such as
#     ... the bigger gap (sibling item `routed:XXXX`) ...
# satisfies it, because the trailing backtick is a valid boundary. The inbox line is then
# deleted WITHOUT ever being filed.
#
# It is SELF-INFLICTED and INTRA-RUN: `--apply` writes item A's INBOUND stub (body and all,
# including A's prose citation of B's token) into the target TODO.md, then iterates on to B,
# re-greps the file it just wrote, finds "the token", and drains B. Order-dependent, hence
# intermittent. The `id:9fdb` refuse-without-a-twin guard in `append.sh inbox-done` is NOT
# bypassed — it is SATISFIED BY THE WRONG THING, since it asks the same question.
#
# THE CONTRACT SPECCED HERE. A token counts as present in a target ledger only in one of
# its OWNING forms:
#   * an HTML-comment marker — `<!-- routed:XXXX -->` or `<!-- id:XXXX -->`; or
#   * the ingest-stub prefix — a checkbox line whose leading bracket tags include
#     `[INBOUND routed:XXXX …]` (the exact shape `scan-routed.sh --apply` itself writes,
#     and the only marker 176 already-filed items in this repo's TODO.md carry).
# A bare `routed:XXXX` / `id:XXXX` in running prose NEVER counts.
#
# Cases: (1) the live loss — A quotes B and sorts first, B must be FILED not drained;
# (2) the SILENT direction as an explicit NEGATIVE — a prose mention alone never resolves,
# asserted both end-to-end and directly against the shared predicate; (3) every genuine
# owning form still resolves as before; (4) the fix is idempotent across runs (the intra-run
# re-read that made case 1 destructive must not become a double-write).
#
# Hermetic: mktemp fixtures, fake SRC_DIR/RELAY_TOML/RELAY_INBOX/CLAIM_BASE. Never touches
# ~/.claude, the real inbox, or the network. Fixture names are deliberately neutral and
# share no string with any assertion.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/scan-routed.sh"
LIB="$ROOT/relay/scripts/lib-anchored-id.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]]  || fail "scan-routed.sh not found/executable at $SH"
[[ -f "$LIB" ]] || fail "lib-anchored-id.sh not found at $LIB"

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
CLAIM_BASE="$FIX/claims"; mkdir -p "$CLAIM_BASE"

mk_repo() { # <abs-dir> <todo-content>
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email z@e.st; git -C "$d" config user.name Zommuter
  printf '%s\n' "$2" > "$d/TODO.md"
  printf '# Roadmap\n' > "$d/ROADMAP.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}

# scenario <name> <todo-seed> <inbox-body> — build a fixture, run `--apply`, and set
# SCEN_DIR / SCEN_TODO / SCEN_INBOX / SCEN_OUT (the run's stdout). Deliberately NOT called
# in a command substitution: a subshell would discard the fixture paths the assertions need.
scenario() {
  local name="$1" seed="$2" body="$3"
  SCEN_DIR="$FIX/$name"; mkdir -p "$SCEN_DIR"
  local src="$SCEN_DIR/src"; mkdir -p "$src"
  mk_repo "$src/depot" "$seed"
  cat > "$SCEN_DIR/relay.toml" <<EOF
[repos.depot]
classification = "own"
path = "$src/depot"
EOF
  printf '%s\n' "$body" > "$SCEN_DIR/inbox.md"
  SCEN_TODO="$src/depot/TODO.md"
  SCEN_INBOX="$SCEN_DIR/inbox.md"
  SCEN_SRC="$src"
  SRC_DIR="$src" RELAY_TOML="$SCEN_DIR/relay.toml" RELAY_INBOX="$SCEN_INBOX" \
    STATE_JSON="$SCEN_DIR/no-such-state.json" CLAIM_BASE="$CLAIM_BASE" \
    SCAN_ROUTED_LOG="$SCEN_DIR/scan.log" "$SH" --apply \
    >"$SCEN_DIR/out.log" 2>"$SCEN_DIR/err.log"
  SCEN_OUT="$(cat "$SCEN_DIR/out.log")"
}

# owns_token <file> <tok> — the token appears in one of its OWNING forms on some line.
owns_token() {
  grep -qE "(<!--[[:space:]]*(id|routed):$2[[:space:]]*-->)|(^- \[[ x]\] (\[[^]]*\] )*\[INBOUND routed:$2[^0-9a-f])" "$1"
}

# --- case 1: the live loss — A's body quotes B's token, A sorts FIRST -----------
# A is processed first, its stub (carrying the citation) is written into TODO.md, and the
# loop then re-greps that file for B. B must still be FILED, never drained.
scenario s1 '# TODO' '# Cross-project TODO inbox
- [ ] [depot] parent finding; the bigger gap is the sibling item `routed:b2b2` (from meeting, note.md) <!-- routed:a1a1 -->
- [ ] [depot] the quoted item, which must be filed on its own merits (from meeting, note.md) <!-- routed:b2b2 -->'

owns_token "$SCEN_TODO" a1a1 \
  || fail "(1) precondition broken: routed:a1a1 (the citing item) was not filed at all:
$SCEN_OUT
--- TODO.md ---
$(cat "$SCEN_TODO")"
grep -q 'routed:b2b2' "$SCEN_TODO" \
  || fail "(1) precondition broken: the fixture no longer reproduces the intra-run citation —
routed:b2b2 is not present anywhere in TODO.md after routed:a1a1 was filed:
$(cat "$SCEN_TODO")"
grep -qE 'RESOLVED[^-]*routed:b2b2' <<<"$SCEN_OUT" \
  && fail "(1) THE LIVE LOSS: routed:b2b2 was classified RESOLVED and drained because a
SIBLING item's body quotes its token — it was never filed:
$SCEN_OUT
--- TODO.md ---
$(cat "$SCEN_TODO")"
owns_token "$SCEN_TODO" b2b2 \
  || fail "(1) routed:b2b2 was not FILED (no owning marker in the target TODO.md):
$SCEN_OUT
--- TODO.md ---
$(cat "$SCEN_TODO")"
pass "(1) a token quoted in a sibling item's body is still FILED, not drained (the live loss)"

# --- case 2: the SILENT direction — a bare prose mention alone never resolves ----
# End-to-end: the target already contains a prose citation of the token (planted by an
# earlier, unrelated annotation) and nothing else. --apply must FILE the item.
scenario s2 '# TODO
- [ ] an unrelated item whose body cites routed:c3c3 in passing <!-- id:9999 -->' '# Cross-project TODO inbox
- [ ] [depot] must be filed despite the pre-existing prose citation (from meeting, note.md) <!-- routed:c3c3 -->'

grep -qE 'RESOLVED[^-]*routed:c3c3' <<<"$SCEN_OUT" \
  && fail "(2) a bare prose mention of routed:c3c3 satisfied the twin check — the item was
drained without ever being filed:
$SCEN_OUT
--- TODO.md ---
$(cat "$SCEN_TODO")"
owns_token "$SCEN_TODO" c3c3 \
  || fail "(2) routed:c3c3 was not filed (no owning marker written):
$SCEN_OUT
--- TODO.md ---
$(cat "$SCEN_TODO")"
pass "(2a) end-to-end: a pre-existing prose citation never counts as a landed twin"

# Directly against the shared predicate both scan-routed.sh and `append.sh inbox-done`
# consult — the negative asserted at the unit the decision is actually made in.
# shellcheck source=../relay/scripts/lib-anchored-id.sh
source "$LIB"
declare -F token_marker_in_files >/dev/null \
  || fail "(2b) token_marker_in_files is not defined in $LIB"
probe="$FIX/probe.md"
printf '%s\n' '- [ ] cross-reference only: see `routed:d4d4` and id:d4d4 for context <!-- id:1111 -->' >"$probe"
if token_marker_in_files d4d4 "$probe"; then
  fail "(2b) token_marker_in_files accepted a bare prose mention of d4d4 as a twin:
$(cat "$probe")"
fi
printf '%s\n' 'a narrative sentence naming routed:d4d4, then a hard stop.' >"$probe"
if token_marker_in_files d4d4 "$probe"; then
  fail "(2b) token_marker_in_files accepted a bare narrative mention of d4d4 as a twin"
fi
pass "(2b) the shared twin predicate rejects a bare prose mention (the silent direction)"

# --- case 3: every genuine owning form STILL resolves ---------------------------
# (a) the item's own `<!-- routed:XXXX -->` marker
scenario s3a '# TODO
- [ ] a native item carrying the token as its own marker <!-- routed:e5e5 -->' '# Cross-project TODO inbox
- [ ] [depot] already landed under a routed marker (from meeting, note.md) <!-- routed:e5e5 -->'
grep -qE 'RESOLVED[^-]*routed:e5e5' <<<"$SCEN_OUT" \
  || fail "(3a) a genuine <!-- routed:e5e5 --> twin no longer resolves:
$SCEN_OUT"
grep -q 'routed:e5e5' "$SCEN_INBOX" \
  && fail "(3a) the resolved item was not drained from the inbox:
$(cat "$SCEN_INBOX")"

# (b) the item's own `<!-- id:XXXX -->` marker (single-id-two-views: the target adopted
#     the routed token AS its id)
scenario s3b '# TODO
- [ ] the target adopted the token as its own id <!-- id:f6f6 -->' '# Cross-project TODO inbox
- [ ] [depot] already landed under an id marker (from meeting, note.md) <!-- routed:f6f6 -->'
grep -qE 'RESOLVED[^-]*routed:f6f6' <<<"$SCEN_OUT" \
  || fail "(3b) a genuine <!-- id:f6f6 --> twin no longer resolves:
$SCEN_OUT"

# (c) the INBOUND ingest-stub prefix — the exact line `--apply` itself writes, and the
#     ONLY marker most already-filed items carry (no `<!-- routed: -->` comment at all).
scenario s3c '# TODO
- [ ] [ROUTINE] [INBOUND routed:a7a7 from elsewhere] previously ingested by this very script <!-- id:2222 -->' '# Cross-project TODO inbox
- [ ] [depot] already ingested as an INBOUND stub (from meeting, note.md) <!-- routed:a7a7 -->'
grep -qE 'RESOLVED[^-]*routed:a7a7' <<<"$SCEN_OUT" \
  || fail "(3c) an INBOUND ingest stub is no longer recognised as a twin — this would make
scan-routed.sh re-file every item it has ever ingested:
$SCEN_OUT"
pass "(3) all three owning forms (routed marker, id marker, INBOUND stub) still resolve"

# --- case 4: idempotent across runs ---------------------------------------------
# The intra-run re-read of the target file is what made case 1 destructive; with the
# predicate fixed the re-read must still make a SECOND --apply a no-op.
scenario s4 '# TODO' '# Cross-project TODO inbox
- [ ] [depot] filed once, then re-scanned (from meeting, note.md) <!-- routed:b8b8 -->'
owns_token "$SCEN_TODO" b8b8 || fail "(4) first --apply did not file routed:b8b8:
$SCEN_OUT"
SRC_DIR="$SCEN_DIR/src" RELAY_TOML="$SCEN_DIR/relay.toml" RELAY_INBOX="$SCEN_INBOX" \
  STATE_JSON="$SCEN_DIR/no-such-state.json" CLAIM_BASE="$CLAIM_BASE" \
  SCAN_ROUTED_LOG="$SCEN_DIR/scan.log" "$SH" --apply >/dev/null 2>&1
n4="$(grep -c 'INBOUND routed:b8b8' "$SCEN_TODO" || true)"
[[ "$n4" -eq 1 ]] || fail "(4) idempotency broken: the stub for routed:b8b8 appears $n4 time(s), want 1:
$(cat "$SCEN_TODO")"
pass "(4) a second --apply is still a no-op (fresh per-iteration read, no double-write)"

echo "ALL PASS: id:c97c own-marker twin check (4 cases)"
