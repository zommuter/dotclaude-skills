#!/usr/bin/env bash
# Defect-fix test for TODO id:729c (INBOUND routed:ece6) — no `# roadmap:` header on
# purpose: there is no ROADMAP item, so a failure here is always a REAL failure.
#
# CONTRACT UNDER TEST — `append.sh` must never report success for a write that did not land.
# Today every write path is a bare `printf … >> "$dest"` inside a flock'd subshell followed
# by `exit 0` / a token echo: whatever reaches the file is never read back. If the bytes go
# nowhere (a clobbering concurrent writer — id:2be7/routed:8eb5 — a discarded redirect, a
# store that swallows writes), the caller gets exit 0 plus a routed token and the entry is
# gone with no trace anywhere: the inbox is vanish-on-resolve, so a pre-adoption loss leaves
# nothing for any scanner to find.
#
# The fixture models the loss by MUTATING a copy of append.sh so its append redirects to
# /dev/null — the write "succeeds" and stores nothing. Every append target is exercised
# (-t inbox raw form, -t inbox --route-to, -t discoveries), because they share the shape.
#
# Required behaviour: exit NON-ZERO, name the payload AND the store path on stderr, and do
# NOT print a routed token on stdout (stdout is the receipt — id:34c2 contract C).
#
# Hermetic: everything under mktemp -d. The skill root is a $TMP tree whose relay/ is a
# symlink to the repo's, so todo-conformance.sh (the id:bbb2 dependency) resolves; nothing
# outside $TMP is written and the real ~/.claude/projects/todo-inbox.md is never touched.
# fails-against: rev 6142f2329b34 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/append.sh, meeting/md-merge.py, meeting/orphan-scan.sh (+15 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 6142f2329b34 -- meeting/append.sh meeting/md-merge.py meeting/orphan-scan.sh relay/references/hard-lanes.md relay/scripts/classify-repo.sh relay/scripts/discover-sig.sh relay/scripts/gather-repo-state.sh relay/scripts/handback-guard.mjs relay/scripts/lib-anchored-id.sh relay/scripts/lib-roadmap-sections.sh relay/scripts/lib-typed-edges.sh relay/scripts/reconcile-repo.sh relay/scripts/relay-loop.js relay/scripts/resolve-gates.sh relay/scripts/roadmap-lint.sh relay/scripts/unpromoted-scan.sh tracker/SCHEMA.md tracker/ledger-map.py
# fails-against-assertion: (1) -t inbox exited 0 although the entry never reached the store — a dropped write must fail LOUDLY (stdout:

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
INBOX="$TMP/todo-inbox.md"
SRC="$TMP/src"; mkdir -p "$SRC/dotclaude-skills"
printf '# TODO — dotclaude-skills\n' > "$SRC/dotclaude-skills/TODO.md"

# Skill root: meeting/ holds the script under test, relay/ is symlinked to the real one.
mkdir -p "$TMP/skillroot/meeting"
ln -s "$ROOT/relay" "$TMP/skillroot/relay"
GOOD="$TMP/skillroot/meeting/append.sh"
cp "$SH" "$GOOD"

# The mutant: the append redirect is neutered, so the write silently stores nothing.
mkdir -p "$TMP/mutant/meeting"
ln -s "$ROOT/relay" "$TMP/mutant/relay"
BAD="$TMP/mutant/meeting/append.sh"
sed 's|>> "$dest"|>> /dev/null|g' "$SH" > "$BAD"
chmod +x "$BAD"
# Guard against a vacuous fixture: the mutation must actually have applied.
grep -q '>> /dev/null' "$BAD" || fail "setup: the append-redirect mutation did not apply — fixture is vacuous"
grep -q '>> "$dest"' "$BAD" && fail "setup: an unmutated '>> \$dest' append remains in the mutant"

fresh_inbox() {
  cat > "$INBOX" <<'EOF'
# Cross-project inbox

- [ ] [dotclaude-skills] a pre-existing conforming item (from meeting, note) <!-- routed:1234 -->
EOF
}

# --- 1. `-t inbox`, raw -e form: a dropped write must NOT report success ------------------
fresh_inbox
payload='- [ ] [dotclaude-skills] readback probe, raw form (from test, note) <!-- routed:c0de -->'
out="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$BAD" -t inbox -e "$payload" 2>"$TMP/err1")"
rc=$?
err="$(cat "$TMP/err1")"
[[ $rc -ne 0 ]] \
  || fail "(1) -t inbox exited 0 although the entry never reached the store — a dropped write must fail LOUDLY (stdout: $out)"
pass "(1) dropped inbox write exited non-zero (exit $rc)"

grep -q 'routed:c0de' <<<"$err" \
  || fail "(1) the failure must name the payload that was lost; stderr was: $err"
pass "(1) failure names the lost payload"

grep -qF "$INBOX" <<<"$err" \
  || fail "(1) the failure must name the store path it could not write; stderr was: $err"
pass "(1) failure names the store path"

[[ -z "$(tr -d '[:space:]' <<<"$out")" ]] \
  || fail "(1) stdout printed a receipt ('$out') for a write that did not land — the token echo is the caller's receipt and must stay silent on failure"
pass "(1) no token receipt printed on failure"

# --- 2. `-t inbox --route-to` (mint-inside form) ------------------------------------------
fresh_inbox
out2="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$BAD" -t inbox --route-to dotclaude-skills \
  -e 'readback probe, mint-inside form (from test, note)' 2>"$TMP/err2")"
rc2=$?
err2="$(cat "$TMP/err2")"
[[ $rc2 -ne 0 ]] \
  || fail "(2) --route-to exited 0 and echoed '$out2' although nothing reached the store — the minted token is a phantom receipt"
pass "(2) dropped --route-to write exited non-zero (exit $rc2)"

grep -qF "$INBOX" <<<"$err2" \
  || fail "(2) the failure must name the store path; stderr was: $err2"
pass "(2) failure names the store path"

[[ -z "$(tr -d '[:space:]' <<<"$out2")" ]] \
  || fail "(2) --route-to printed token '$out2' for a line that is not on disk"
pass "(2) no token receipt printed on failure"

# --- 3. `-t discoveries` shares the same append shape -------------------------------------
out3="$(RELAY_INBOX="$INBOX" "$BAD" -t discoveries \
  -e '- [2026-08-14 test] a free-prose discovery that must not vanish silently' 2>"$TMP/err3")"
rc3=$?
err3="$(cat "$TMP/err3")"
[[ $rc3 -ne 0 ]] \
  || fail "(3) -t discoveries exited 0 although the entry never reached discoveries.md — the same silent-drop shape"
pass "(3) dropped discoveries write exited non-zero (exit $rc3)"
grep -q 'free-prose discovery' <<<"$err3" \
  || fail "(3) the failure must name the lost payload; stderr was: $err3"
pass "(3) discoveries failure names the lost payload"

# --- 4. NO-REGRESSION: the unmutated script still writes, echoes, and exits 0 --------------
fresh_inbox
tok="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$GOOD" -t inbox \
  -e '- [ ] [dotclaude-skills] healthy raw append (from test, note) <!-- routed:beef -->' 2>"$TMP/err4")"
rc4=$?
[[ $rc4 -eq 0 ]] || fail "(4) a healthy -t inbox append now FAILS (exit $rc4): $(cat "$TMP/err4")"
[[ "$(tr -d '[:space:]' <<<"$tok")" == "beef" ]] \
  || fail "(4) healthy append must still echo the written token 'beef'; got '$tok'"
grep -q 'routed:beef -->' "$INBOX" || fail "(4) healthy append did not reach the store"
pass "(4) healthy raw -e append still writes, echoes 'beef', exits 0"

tok2="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$GOOD" -t inbox --route-to dotclaude-skills \
  -e 'healthy mint-inside append (from test, note)' 2>"$TMP/err5")"
rc5=$?
[[ $rc5 -eq 0 ]] || fail "(4) a healthy --route-to append now FAILS (exit $rc5): $(cat "$TMP/err5")"
[[ "$(tr -d '[:space:]' <<<"$tok2")" =~ ^[0-9a-f]{4}$ ]] \
  || fail "(4) healthy --route-to must echo the minted token; got '$tok2'"
grep -q "<!-- routed:$(tr -d '[:space:]' <<<"$tok2") -->" "$INBOX" \
  || fail "(4) healthy --route-to token '$tok2' is not on disk"
pass "(4) healthy --route-to append still writes, echoes its minted token, exits 0"

RELAY_INBOX="$INBOX" "$GOOD" -t discoveries \
  -e '- [2026-08-14 test] a healthy free-prose discovery' >/dev/null 2>"$TMP/err6" \
  || fail "(4) a healthy -t discoveries append now FAILS: $(cat "$TMP/err6")"
grep -q 'healthy free-prose discovery' "$TMP/skillroot/meeting/discoveries.md" \
  || fail "(4) healthy discoveries append did not reach discoveries.md"
pass "(4) healthy -t discoveries append still works"

# --- 5. a multi-line entry must be verified in full, not by its first line -----------------
# `-t discoveries` legitimately takes prose blocks; a partial write (first line only) is the
# clobber shape that a naive "grep the first line" read-back would call success.
RELAY_INBOX="$INBOX" "$GOOD" -t discoveries \
  -e '- [2026-08-14 test] block head
  continuation line that must also land' >/dev/null 2>"$TMP/err7" \
  || fail "(5) a healthy multi-line -t discoveries append FAILED: $(cat "$TMP/err7")"
grep -q 'continuation line that must also land' "$TMP/skillroot/meeting/discoveries.md" \
  || fail "(5) multi-line append lost its continuation line"
pass "(5) multi-line discoveries entry lands whole"

echo "ALL PASS"
