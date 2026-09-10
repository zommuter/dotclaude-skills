#!/usr/bin/env bash
# DEFECT-FIX TEST for the nine findings of the id:0246 adversarial review (2026-09-10). No
# `# roadmap:` header on purpose: these are defect fixes, not a roadmap item, so their
# failures ALWAYS count.
#
# CONTEXT. id:0246 (one shared `inbox_line_own_token`, adopted by all three inbox sites) was
# implemented as 6d5befed, adversarially reviewed, found to carry 9 defects (2 HIGH) on a
# DESTRUCTIVE, unrecoverable write path, and REVERTED as eb2587fd before being pushed. The
# extractor and the spec were sound (`tests/test_inbox_own_token_extractor_0246.sh` covers
# those); this file pins the defects the review named, so the same commit cannot come back.
# Full prescription: `docs/ledger-notes/0246-review.md`.
#
# WHAT EACH CASE PINS:
#   (D1) HIGH -- a SYMLINKED inbox was clobbered. `mktemp` + `mv -- "$tmp" "$inbox"`
#        REPLACES a symlink with a regular file: the canonical store keeps the "resolved"
#        line, the store now exists twice and diverges, and the command exits 0. The python
#        it replaced used `write_text()`, which follows symlinks. This same file already
#        fixes this class for personas.md (routed:96da / id:00b1) and `lock_path_for`
#        canonicalises with `readlink -f` for exactly this reason (id:244f).
#   (D8) same fix -- the mode was not preserved (0664 -> mkstemp's 0600).
#   (D7) if the owning line was the ONLY line, `grep -vxF` selected nothing, exited 1, and
#        `set -e` killed the subshell before the `mv`: rc 1, line survives, stderr EMPTY,
#        and a stray `.inbox-done.XXXXXX` left in a git-tracked directory.
#   (D2) HIGH -- the add path exited 1 AFTER durably appending, so a naive retry
#        DOUBLE-FILES. `-t inbox`'s documented contract for a nonzero exit is "rejected,
#        nothing appended", and a garbage entry really does that, so a caller could not
#        tell them apart. Now a multi-marker entry is rejected at WRITE time (owner ruling:
#        such a line should not exist) and nothing is appended.
#   (D5) an INDENTED inbox line: previously drainable, then a SILENT exit-0 no-op. Owner
#        ruling 2026-09-10: REFUSE, and refuse LOUDLY.
#   (D6) a decoy multi-marker line must not block a genuine unambiguous owner elsewhere in
#        the store (it did, permanently, with a message pointing at the wrong line).
#   (D3) a FAILED drain must not be counted as `resolved`, must reach the summary, and must
#        reach the EXIT STATUS.
#   (D4) a REFUSED line must be a FINDING on stdout, never silently dropped into
#        `clean (no dead letters; nothing to drain)` -- a false clean about a question the
#        tool refused to ask.
#
# FAIL-FAST BY CONSTRUCTION: every failure exits immediately, so exactly one `FAIL:` line
# can ever fire and the declared assertion below is unambiguous (tests/verify-negative-cases.py
# matches the LAST fired FAIL line; with one line there is no last-vs-any gap to argue about).
#
# fails-against: the reverted 6d5befed implementation, whose `inbox-done` drain was a
#   `mktemp` + `grep -vxF` + `mv` pipeline -- it replaces a symlinked store with a regular
#   file (D1), drops the mode (D8), and no-ops with an empty stderr plus a stray temp file
#   when the owning line is the only line (D7); whose add path exited 1 after appending
#   (D2); and whose scan-routed counted a failed drain as resolved (D3) and dropped a
#   refusal without a finding (D4).
# fails-against-rev: 6d5befedb4c1881c00b7d9b47f441c6ef5390891 -- meeting/append.sh relay/scripts/lib-anchored-id.sh relay/scripts/scan-routed.sh
# fails-against-assertion: (D1) the SYMLINK at
#   (D1 is declared because it is the first case and this file is fail-fast, so it is both
#   the first and the last FAIL line at that revision. The later cases are pinned against
#   regression, not against that revision.)
#
# HERMETIC: HOME, RELAY_INBOX, SRC_DIR, RELAY_TOML, SCAN_ROUTED_LOG and CLAIM_BASE are all
# injected, for the reason the sibling spec spells out at length -- `inbox-done` DELETES
# lines from a local-only store that holds live items, and resolve_inbox() will MIGRATE a
# legacy path with `mv` under a real HOME. Nothing is written outside $FIX.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
SCAN="$ROOT/relay/scripts/scan-routed.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$APPEND" ]] || fail "precondition: append.sh not found at $APPEND"
[[ -x "$SCAN" ]] || fail "precondition: scan-routed.sh not found or not executable at $SCAN"
[[ $EUID -ne 0 ]] || fail "precondition: this fixture must not run as root -- case D3 makes a directory unwritable to force a failed drain, and root ignores that"

FIX="$(mktemp -d)"
trap 'chmod -R u+w "$FIX" 2>/dev/null; rm -rf "$FIX"' EXIT

# --- fixture builder --------------------------------------------------------------------
# scenario <name> -- isolated HOME + a `depot` target repo whose four ledger files exist.
# Sets SC_* globals, so it must NOT be called in a command substitution.
scenario() {
  SC_DIR="$FIX/$1"
  SC_HOME="$SC_DIR/home"
  SC_SRC="$SC_DIR/src"
  SC_REPO="$SC_SRC/depot"
  SC_STORE_DIR="$SC_DIR/store"
  mkdir -p "$SC_HOME" "$SC_REPO" "$SC_DIR/claims" "$SC_STORE_DIR"
  printf '# TODO\n\n- [ ] an unrelated live item <!-- id:9901 -->\n' >"$SC_REPO/TODO.md"
  printf '# ROADMAP\n' >"$SC_REPO/ROADMAP.md"
  printf '# TODO archive\n' >"$SC_REPO/TODO.archive.md"
  printf '# ROADMAP archive\n' >"$SC_REPO/ROADMAP.archive.md"
  SC_TOML="$SC_DIR/relay.toml"
  cat >"$SC_TOML" <<EOF
[repos.depot]
classification = "own"
path = "$SC_REPO"
EOF
  # The CANONICAL store. $SC_INBOX (the path the code is handed) is set per case: for most
  # cases it IS the canonical store; for D1 it is a symlink pointing at it.
  SC_STORE="$SC_STORE_DIR/todo-inbox.md"
  : >"$SC_STORE"
  SC_INBOX="$SC_STORE"
}
twin_add() { printf '%s\n' "- [x] the landed item <!-- routed:$1 --> on 2026-09-10" >>"$SC_REPO/TODO.md"; }
store_has() { grep -qF -- "$1" "$SC_STORE"; }   # `--`: every fixture line starts with `-`

run_done() {  # run_done <token> -- append.sh inbox-done, fully injected
  DONE_RC=0
  HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    bash "$APPEND" inbox-done "$1" >"$SC_DIR/done.out" 2>"$SC_DIR/done.err" || DONE_RC=$?
  DONE_ERR="$(cat "$SC_DIR/done.err")"
}

run_scan() {  # run_scan [args...] -- scan-routed.sh, fully injected
  SCAN_RC=0
  HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    SCAN_ROUTED_LOG="$SC_DIR/scan.log" CLAIM_BASE="$SC_DIR/claims" \
    bash "$SCAN" "$@" >"$SC_DIR/scan.out" 2>"$SC_DIR/scan.err" || SCAN_RC=$?
  SCAN_OUT="$(cat "$SC_DIR/scan.out")"
  SCAN_ERR="$(cat "$SC_DIR/scan.err")"
}

# =========================================================================================
# D1 + D8: a SYMLINKED inbox is drained THROUGH the symlink, with its mode intact.
# =========================================================================================
scenario d1
LINE_D1='- [ ] [depot] a symlinked-store item (from meeting, n.md) <!-- routed:c1c1 -->'
printf '# Cross-project TODO inbox\n\n%s\n' "$LINE_D1" >"$SC_STORE"
chmod 664 "$SC_STORE"
mkdir -p "$SC_DIR/link"
SC_INBOX="$SC_DIR/link/inbox.md"
ln -s "$SC_STORE" "$SC_INBOX"
twin_add c1c1
run_done c1c1

[[ $DONE_RC -eq 0 ]] || fail "(D1) inbox-done exited $DONE_RC on a symlinked store (want 0)
--- stderr ---
$DONE_ERR"
[[ -L "$SC_INBOX" ]] || fail "(D1) the SYMLINK at \$RELAY_INBOX was REPLACED BY A REGULAR FILE. \`mktemp\` + \`mv\` onto the link path clobbers the link; the canonical store keeps the resolved line, the store now exists TWICE and diverges, and the command still exits 0. Use realpath + a temp file in the RESOLVED parent + os.replace, exactly as this file already does for personas.md (routed:96da / id:00b1)
--- store (canonical) ---
$(cat "$SC_STORE")"
store_has "$LINE_D1" && fail "(D1b) the CANONICAL store was never drained -- the line survives at $SC_STORE after an exit-0 inbox-done
--- store ---
$(cat "$SC_STORE")"
pass "(D1) a symlinked inbox is drained through the link; the link survives and the canonical store is the one written"

mode="$(stat -c '%a' "$SC_STORE")"
[[ "$mode" == "664" ]] || fail "(D8) the store's MODE was not preserved across the drain: $mode (want 664). mkstemp defaults to 0600 and nothing restored it; the personas path in this same file calls os.chmod for exactly this reason"
pass "(D8) the store's mode survives the drain (664)"

# =========================================================================================
# D7: the owning line is the ONLY line -- the drain must work, loudly if it cannot, and
# must leave no temp-file litter in the store's (git-tracked) directory.
# =========================================================================================
scenario d7
LINE_D7='- [ ] [depot] the only line in the store (from meeting, n.md) <!-- routed:c7c7 -->'
printf '%s\n' "$LINE_D7" >"$SC_STORE"
twin_add c7c7
run_done c7c7

[[ $DONE_RC -eq 0 ]] || fail "(D7) inbox-done exited $DONE_RC when the owning line was the ONLY line in the store (want 0). \`grep -vxF\` selects nothing here, exits 1, and \`set -e\` kills the subshell before the rename -- rc 1, line survives, stderr EMPTY
--- stderr ---
$DONE_ERR"
store_has "$LINE_D7" && fail "(D7b) the sole line was NOT drained from the store
--- store ---
$(cat "$SC_STORE")"
litter="$(find "$SC_STORE_DIR" -name '.inbox-done*' -o -name '*.tmp' | tr '\n' ' ')"
[[ -z "$litter" ]] || fail "(D7c) the drain left TEMP-FILE LITTER in the store's directory (which is git-tracked in production): $litter"
pass "(D7) a sole owning line drains cleanly, with no temp-file litter"

# =========================================================================================
# D5: an INDENTED inbox line is REFUSED, and refused LOUDLY (owner ruling 2026-09-10). The
# defect was the silent exit-0 no-op, not the strictness.
# =========================================================================================
scenario d5
LINE_D5='  - [ ] [depot] an indented entry (from meeting, n.md) <!-- routed:c5c5 -->'
printf '# Cross-project TODO inbox\n\n%s\n' "$LINE_D5" >"$SC_STORE"
twin_add c5c5
run_done c5c5

[[ $DONE_RC -ne 0 ]] || fail "(D5) inbox-done must REFUSE an indented inbox line LOUDLY, not exit 0 with an empty stderr: rc=$DONE_RC. A previously drainable shape becoming a silent no-op is the id:d35a class this item exists to kill
--- stderr ---
$DONE_ERR"
grep -qi 'indent' <<<"$DONE_ERR" || fail "(D5b) the refusal is nonzero but says nothing an operator can act on: stderr never mentions the indentation
--- stderr ---
$DONE_ERR"
store_has "$LINE_D5" || fail "(D5c) the refused line was DELETED anyway -- a refusal must change nothing
--- store ---
$(cat "$SC_STORE")"
pass "(D5) an indented inbox line is refused loudly, and nothing is deleted"

# =========================================================================================
# D6: a decoy multi-marker line must not block a genuine, unambiguous owner elsewhere.
# =========================================================================================
scenario d6
DECOY='- [ ] [depot] a decoy citing <!-- routed:c6c6 --> literally (from meeting, n.md) <!-- routed:d6d6 -->'
GENUINE='- [ ] [depot] the genuine owner (from meeting, n.md) <!-- routed:c6c6 -->'
printf '# Cross-project TODO inbox\n\n%s\n%s\n' "$DECOY" "$GENUINE" >"$SC_STORE"
twin_add c6c6
run_done c6c6

[[ $DONE_RC -eq 0 ]] || fail "(D6) a decoy multi-marker line placed BEFORE the genuine owner BLOCKED the drain (rc=$DONE_RC). The scan must be exhaustive: an unambiguous owner anywhere in the store wins over a refusal seen earlier, or a conforming item is immortal and the refusal message points at a line the operator never asked about
--- stderr ---
$DONE_ERR"
store_has "$GENUINE" && fail "(D6b) the genuine owner was not drained
--- store ---
$(cat "$SC_STORE")"
store_has "$DECOY" || fail "(D6c) the DECOY line was deleted -- only the line that OWNS the token may be touched (id:411d)
--- store ---
$(cat "$SC_STORE")"
pass "(D6) an unambiguous owner drains even when a decoy multi-marker line precedes it, and the decoy is untouched"

# Same store, no unambiguous owner left: the refusal is still the backstop the owner ruled for.
run_done d6d6
[[ $DONE_RC -ne 0 ]] || fail "(D6d) with only the multi-marker line carrying d6d6, inbox-done must still REFUSE (id:6059 backstop): rc=$DONE_RC
--- stderr ---
$DONE_ERR"
pass "(D6d) with no unambiguous owner, the id:6059 refusal still fires"

# =========================================================================================
# D2: a multi-marker entry is rejected at WRITE time -- nothing appended, so a retry cannot
# double-file. (The reverted commit appended it and THEN exited 1, which `-t inbox`
# documents as "rejected, nothing appended".)
# =========================================================================================
scenario d2
printf '# Cross-project TODO inbox\n\n' >"$SC_STORE"
BAD_ENTRY='- [ ] [depot] a two-marker entry (from meeting, n.md) <!-- routed:c2c2 --> -- supersedes `<!-- routed:d2d2 -->`'
add_bad() {
  ADD_RC=0
  ADD_OUT="$(HOME="$SC_HOME" RELAY_INBOX="$SC_INBOX" SRC_DIR="$SC_SRC" RELAY_TOML="$SC_TOML" \
    bash "$APPEND" -t inbox -e "$BAD_ENTRY" 2>"$SC_DIR/add.err")" || ADD_RC=$?
}
add_bad
[[ $ADD_RC -ne 0 ]] || fail "(D2) a multi-marker inbox entry must be REJECTED: rc=$ADD_RC"
add_bad   # the naive retry a nonzero exit invites
n="$(grep -cF -- 'a two-marker entry' "$SC_STORE" || true)"
[[ "$n" -eq 0 ]] || fail "(D2b) a rejected \`-t inbox\` entry reached the store $n time(s). Nonzero MUST mean nothing was appended, or a caller that retries DOUBLE-FILES it -- which is what two rejections just produced
--- store ---
$(cat "$SC_STORE")"
pass "(D2) a multi-marker entry is rejected at write time; two attempts leave the store empty"

# =========================================================================================
# D4: a REFUSED line is a FINDING, never a silent drop into `clean`.
# =========================================================================================
scenario d4
printf '# Cross-project TODO inbox\n\n%s\n' \
  '- [ ] [depot] refusable (from meeting, n.md) <!-- routed:c4c4 --> cites <!-- routed:d4d4 -->' >"$SC_STORE"
run_scan
grep -q 'clean (no dead letters; nothing to drain)' <<<"$SCAN_OUT" \
  && fail "(D4) scan-routed reported the dead-letter pass CLEAN while REFUSING to attribute the only line in the store -- a false clean about a question the tool declined to ask (id:4347)
--- report ---
$SCAN_OUT"
grep -qE 'AMBIGUOUS' <<<"$SCAN_OUT" \
  || fail "(D4b) the refused line produced no finding on stdout: a \`log; continue\` with no findings++ makes it invisible to every reader of the report
--- report ---
$SCAN_OUT"
pass "(D4) a refused inbox line is reported as a finding, not swallowed into a clean run"

# =========================================================================================
# D3: a FAILED drain is not counted as resolved, reaches the summary, and reaches the exit
# status. The failure is FORCED by making the store's directory unwritable; `inbox-done`
# then dies while taking its flock (the lock file lives beside the resolved store), which
# is one real way the drain fails. The assertion is about scan-routed's REPORTING of a
# nonzero drain, not about which layer inside `inbox-done` refused -- what must never
# happen is a failure reported as a resolution.
# =========================================================================================
scenario d3
LINE_D3='- [ ] [depot] a twinned item whose drain will fail (from meeting, n.md) <!-- routed:c3c3 -->'
printf '# Cross-project TODO inbox\n\n%s\n' "$LINE_D3" >"$SC_STORE"
twin_add c3c3
chmod 555 "$SC_STORE_DIR"
# Fixture sanity: the failure this case needs must actually be forced, or the case proves
# nothing (a green here would be "the drain succeeded", not "a failed drain is reported").
if ( : >"$SC_STORE_DIR/.probe" ) 2>/dev/null; then
  rm -f -- "$SC_STORE_DIR/.probe"; chmod 755 "$SC_STORE_DIR"
  fail "(D3) FIXTURE BROKEN -- the store directory is still writable after chmod 555, so no drain failure can be forced and this case would pass vacuously"
fi
run_scan --apply
chmod 755 "$SC_STORE_DIR"

grep -q 'RESOLVED routed:c3c3' <<<"$SCAN_OUT" \
  && fail "(D3) scan-routed printed RESOLVED for a drain that FAILED
--- report ---
$SCAN_OUT"
grep -q '1 already-landed item(s) drained' <<<"$SCAN_OUT" \
  && fail "(D3b) the failed drain was COUNTED AS RESOLVED in the summary. Withholding the RESOLVED line but still incrementing the counter defeats the fix one level up: stdout said the item was drained while stderr said it was not
--- report ---
$SCAN_OUT"
[[ $SCAN_RC -ne 0 ]] \
  || fail "(D3c) --apply exited 0 after a drain it asked for did NOT happen. A failed state change must be visible in the exit status, not only in prose
--- report ---
$SCAN_OUT"
grep -q 'FAILED' <<<"$SCAN_OUT" \
  || fail "(D3d) the summary never mentions the failed drain
--- report ---
$SCAN_OUT"
pass "(D3) a failed drain is not counted as resolved, is named in the summary, and is nonzero in the exit status"

echo "ALL PASS: id:0246 -- the nine review defects on the destructive inbox write path"
