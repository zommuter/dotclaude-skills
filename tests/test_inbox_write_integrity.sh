#!/usr/bin/env bash
# roadmap:34c2 — `append.sh -t inbox` must not let a caller report a token it never wrote.
#
# INCIDENT (2026-07-17): the loderite hand-run ran
#   ID=$(append.sh new-id); append.sh -t inbox -e "… <!-- routed:\$ID -->"; echo "filed routed:$ID"
# with $ID ESCAPED in the payload and UNESCAPED in the echo. Bash wrote the literal string
# `$ID` to todo-inbox.md:143 while the echo reported `acc7`. loderite/TODO.md:40 (id:0c54)
# then cited routed:acc7 — a token that existed nowhere. Root cause is not the escaping:
# `-t inbox` accepts arbitrary text, validates nothing, and prints NOTHING on success
# (append.sh:283-287), so the receipt is the caller's own invention with no causal link to
# the bytes on disk. Same class as id:1735 (self-reported summaries).
#
# Three contracts, per meeting 2026-07-17-1450 D2/D3:
#   (A) validate  — a non-conforming `-t inbox` entry is REJECTED non-zero and NOT appended
#   (B) mint-inside — `--route-to <repo> -e "<desc>"` mints + builds + writes the line itself
#   (C) echo      — stdout is the token ACTUALLY written (minted, or parsed back from the line)
# Plus the D3 fold-in: --route-to's mint collision-checks the ROUTED namespace, which
# scan_ids (append.sh:176-185) does not — it greps `id:[0-9a-f]{4}` over <root> only, and
# `routed:acc7` matches neither that pattern nor that file set.
#
# RED until id:34c2 lands. Hermetic: fixture inbox in mktemp -d, driven via RELAY_INBOX.
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

fresh_inbox() {
  cat > "$INBOX" <<'EOF'
# Cross-project inbox

- [ ] [dotclaude-skills] a pre-existing conforming item (from meeting, note) <!-- routed:1234 -->
EOF
}

# --- (A) validate on write -----------------------------------------------------------
# The exact payload shape that caused the incident: a literal `$ID` where the token belongs.
fresh_inbox
before="$(cat "$INBOX")"
out="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" -t inbox \
  -e '- [ ] [dotclaude-skills] the acc7 repro — literal $ID in the marker (from test, note) <!-- routed:$ID -->' 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  fail "(A) append.sh accepted a payload whose marker is a literal \$ID (exit 0) — the acc7 incident is still reproducible"
fi
pass "(A) rejected the literal-\$ID payload (exit $rc)"

if [[ "$(cat "$INBOX")" != "$before" ]]; then
  fail "(A) append.sh REJECTED the entry but still mutated the inbox — a rejected write must append nothing"
fi
pass "(A) rejected entry was not appended"

case "$out" in
  *routed:*|*conform*|*expect*) pass "(A) error message names the expected form" ;;
  *) fail "(A) rejection message must name the offending line and the expected form; got: $out" ;;
esac

# A conforming entry must still be accepted (the guard must not be a blanket refusal).
fresh_inbox
RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" -t inbox \
  -e '- [ ] [dotclaude-skills] a well-formed entry (from test, note) <!-- routed:beef -->' >/dev/null 2>&1 \
  || fail "(A) rejected a CONFORMING entry — the validator is over-tight"
grep -q 'routed:beef -->' "$INBOX" || fail "(A) conforming entry was not appended"
pass "(A) conforming entry still accepted and appended"

# --- (C) echo what was written, raw -e form -------------------------------------------
fresh_inbox
tok="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" -t inbox \
  -e '- [ ] [dotclaude-skills] echo contract, raw form (from test, note) <!-- routed:c0de -->' 2>/dev/null | tr -d '[:space:]')"
[[ "$tok" == "c0de" ]] \
  || fail "(C) raw -e must echo the token parsed back out of the APPENDED line; expected 'c0de', got '$tok'"
pass "(C) raw -e echoed the token actually written (c0de)"

# --- (B) mint-inside + (C) echo -------------------------------------------------------
fresh_inbox
tok="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" -t inbox --route-to dotclaude-skills \
  -e 'mint-inside contract (from test, note)' 2>/dev/null | tr -d '[:space:]')"
[[ "$tok" =~ ^[0-9a-f]{4}$ ]] \
  || fail "(B) --route-to must print the minted 4-hex token on stdout; got '$tok'"
pass "(B) --route-to printed a 4-hex token ($tok)"

# The echoed token MUST be the one on disk. This is the whole point: reported == written.
grep -q "<!-- routed:$tok -->" "$INBOX" \
  || fail "(C) --route-to echoed '$tok' but no line in the inbox carries that marker — reported token != written token, the acc7 bug"
pass "(C) echoed token '$tok' is the token actually on disk"

# The line it built must itself be conforming (checkbox + [target] + trailing marker).
grep -qE "^- \[ \] \[dotclaude-skills\] .*<!-- routed:$tok -->$" "$INBOX" \
  || fail "(B) --route-to built a non-conforming line; got: $(grep "routed:$tok" "$INBOX")"
pass "(B) --route-to built a conforming line"

# The caller passed only a description — no marker text may leak into the body.
if grep -q "routed:$tok.*routed:$tok" "$INBOX"; then
  fail "(B) --route-to emitted the marker twice"
fi
pass "(B) marker appears exactly once on the built line"

# --- (D3) routed-namespace collision-check --------------------------------------------
# The mint draws from secrets.token_hex(2), so "drive --route-to N times and assert it never
# picks the seeded token" would pass ~99.995% of the time WHETHER OR NOT the check exists —
# a test that cannot fail is worse than no test. So the collision SET is what gets asserted,
# via a `scan-routed-tokens` verb mirroring the existing `scan-ids` precedent
# (append.sh:187-192). That is deterministic. Whether the mint then consults it is pinned by
# the set being correct + the mint reusing it; see the coverage limit in ROADMAP id:34c2.
fresh_inbox
printf -- '- [ ] [INBOUND routed:dead from somewhere] a target-side citation <!-- id:aaaa -->\n' \
  >> "$SRC/dotclaude-skills/TODO.md"

set_out="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" scan-routed-tokens dotclaude-skills 2>&1)" \
  || fail "(D3) 'append.sh scan-routed-tokens <target>' verb missing or non-zero; got: $set_out"

# The inbox's own-marker (1234) must be in the set.
grep -qx '1234' <<<"$set_out" \
  || fail "(D3) routed collision set omits '1234', an existing inbox own-marker; got: $(tr '\n' ' ' <<<"$set_out")"
pass "(D3) collision set includes the inbox own-marker (1234)"

# A token the TARGET repo merely cites (dead) must also be in the set — that is the case
# scan_ids structurally cannot see: it greps `id:[0-9a-f]{4}` over <root> only, so
# `routed:dead` matches neither its pattern nor its file set.
grep -qx 'dead' <<<"$set_out" \
  || fail "(D3) routed collision set omits 'dead', which the target repo cites as routed:dead — target-side citations must be in the set; got: $(tr '\n' ' ' <<<"$set_out")"
pass "(D3) collision set includes a token cited by the target repo (dead)"

# The set must be bare 4-hex, one per line, sorted unique — same output contract as scan-ids.
if grep -qvE '^[0-9a-f]{4}$' <<<"$set_out"; then
  fail "(D3) scan-routed-tokens must emit bare 4-hex tokens one per line (scan-ids output contract); got: $(tr '\n' ' ' <<<"$set_out")"
fi
pass "(D3) collision set matches the scan-ids output contract (bare 4-hex, one per line)"

# And the mint must actually consult it: a token in the set is never returned. Deterministic
# only in the limit, so this asserts the reachable part — the minted token is in NEITHER the
# seeded set NOR a repeat of a previously minted one, across consecutive calls on one inbox.
seen="$set_out"
for i in 1 2 3; do
  t="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" -t inbox --route-to dotclaude-skills \
    -e "collision probe $i (from test, note)" 2>/dev/null | tr -d '[:space:]')"
  [[ "$t" =~ ^[0-9a-f]{4}$ ]] || fail "(D3) probe $i did not return a token; got '$t'"
  grep -qx "$t" <<<"$seen" \
    && fail "(D3) --route-to minted '$t', already in the routed namespace — the mint is not consulting the collision set"
  seen="$seen"$'\n'"$t"
done
pass "(D3) 3 consecutive mints avoided the seeded set and each other"

# --- scope guard: discoveries/personas must be UNTOUCHED by the validator --------------
# D2 explicitly scopes validation to -t inbox. A free-prose discoveries entry must still work.
# SKILL_DIR is derived from the script's own dirname (append.sh:16) and is NOT injectable, so
# run a COPY out of $TMP — otherwise this would create discoveries.md inside the real repo
# (it is a local-only file, deliberately never committed here). Hermetic: touches only $TMP.
cp "$SH" "$TMP/append.sh"
if ! RELAY_INBOX="$INBOX" "$TMP/append.sh" -t discoveries \
  -e '- [2026-07-17 test] a free-prose finding with no routed marker at all — see note.md' >/dev/null 2>&1; then
  fail "the inbox validator leaked onto -t discoveries — D2 scopes it to inbox only"
fi
grep -q 'free-prose finding' "$TMP/discoveries.md" \
  || fail "-t discoveries did not append the free-prose entry"
pass "-t discoveries still accepts free prose (validator correctly scoped to inbox)"

# --- (bbb2) dependency-absent case must fail LOUDLY, not swallow a bare exit 127 ----------
# id:34c2's validator shells out to relay/scripts/todo-conformance.sh (good reuse). When the
# meeting skill is installed WITHOUT a sibling relay/ (no todo-conformance.sh), the command
# substitution used to die exit 127 and `set -e` DISCARDED its "No such file" diagnostic — a
# silent swallow (id:bbb2). Contract: probe the dependency, fail non-zero naming it, append
# NOTHING. Hermetic: run a COPY under $TMP/meeting so conf_sh resolves to an ABSENT
# $TMP/relay/scripts/todo-conformance.sh (SKILL_DIR = the script's own dirname, append.sh:34).
mkdir -p "$TMP/meeting"
cp "$SH" "$TMP/meeting/append.sh"
[[ -e "$TMP/relay/scripts/todo-conformance.sh" ]] \
  && fail "(bbb2) test setup wrong — a todo-conformance.sh exists where absence is required"
fresh_inbox
before="$(cat "$INBOX")"
dep_out="$(RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$TMP/meeting/append.sh" -t inbox \
  -e '- [ ] [dotclaude-skills] dep-absent probe, otherwise conforming (from test, note) <!-- routed:feed -->' 2>&1)"
dep_rc=$?
[[ $dep_rc -ne 0 ]] \
  || fail "(bbb2) -t inbox exited 0 with todo-conformance.sh ABSENT — the dependency probe is missing"
pass "(bbb2) dependency-absent -t inbox failed non-zero (exit $dep_rc)"

[[ "$(cat "$INBOX")" == "$before" ]] \
  || fail "(bbb2) a dependency-absent failure still mutated the inbox — must append nothing (fail-closed)"
pass "(bbb2) nothing appended on the dependency-absent failure"

case "$dep_out" in
  *todo-conformance*|*relay*|*install*) pass "(bbb2) error names the missing relay dependency (no silent swallow)" ;;
  *) fail "(bbb2) failure must LOUDLY name the missing todo-conformance.sh/relay dependency; got: $dep_out" ;;
esac

echo "ALL PASS"
