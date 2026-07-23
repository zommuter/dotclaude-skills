#!/usr/bin/env bash
# roadmap:ce50 — inbox-scan-repo.sh: a per-repo FILTERED inbox surface for repo-scoped
# relay commands (`/relay human .`, `/relay <repo>`, `/relay . --drain`, `/relay next`).
# Distinct from scan-routed.sh's `--all` dead-letter RECONCILE: this is a report-only
# VISIBILITY check that surfaces open `- [ ] [<repo>] …` inbox items when the relay run is
# scoped to a single repo (the gap that bit chidiai 2026-07-20 — `/relay human .` skipped
# the inbox while a `[chidiai]`-targeted item sat unrouted). Report-only, NEVER writes.
#
# RED until relay/scripts/inbox-scan-repo.sh + the SKILL.md/human.md wiring land.
# Hermetic: a fixture inbox under RELAY_INBOX; no network, no ~/.claude touch.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/inbox-scan-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "inbox-scan-repo.sh not found at $SH"
[[ -x "$SH" ]] || fail "inbox-scan-repo.sh not executable"
bash -n "$SH" || fail "inbox-scan-repo.sh fails bash -n"
pass "inbox-scan-repo.sh exists, executable, parses"

# (0) Misuse: no repo argument exits nonzero (a filtered scan needs a target).
rc=0; "$SH" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(0) missing repo arg must exit nonzero (misuse); got 0"
pass "(0) missing repo arg → nonzero (misuse reject)"

# --- fixture inbox ------------------------------------------------------------
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
cat > "$FIX/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [chidiai] open item targeting chidiai (from src, note.md) <!-- routed:4975 -->
- [ ] [chidiai] a second open chidiai item (from src, note.md) <!-- routed:aa11 -->
- [x] [chidiai] already-resolved chidiai item (from src, note.md) <!-- routed:bb22 -->
- [ ] [zkm] targets a DIFFERENT repo (from src, note.md) <!-- routed:cc33 -->
- [ ] [dotclaude-skills] mentions chidiai in its prose body but targets dotclaude (from chidiai run) <!-- routed:dd44 -->
zkm core: a token-less prose block naming chidiai but with no checkbox
EOF

run() { RELAY_INBOX="$FIX/inbox.md" "$SH" "$@" 2>/dev/null; }

# (1) report-only: exit 0 with findings.
rc=0; out="$(run chidiai)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "(1) report-only must exit 0 with findings; got $rc
$out"
pass "(1) report-only (exit 0 with findings)"

# (2) both OPEN [chidiai]-targeted items are surfaced.
grep -q 'routed:4975' <<<"$out" || fail "(2) open [chidiai] item routed:4975 not surfaced:
$out"
grep -q 'routed:aa11' <<<"$out" || fail "(2) open [chidiai] item routed:aa11 not surfaced:
$out"
pass "(2) open [<repo>]-targeted items surfaced"

# (3) a [x] DONE [chidiai] item is NOT surfaced (only open work matters).
grep -q 'routed:bb22' <<<"$out" && fail "(3) resolved [x] [chidiai] item wrongly surfaced:
$out"
pass "(3) done [x] item not surfaced"

# (4) an item targeting a DIFFERENT repo ([zkm]) is left untouched.
grep -q 'routed:cc33' <<<"$out" && fail "(4) other-repo [zkm] item wrongly surfaced under chidiai scan:
$out"
pass "(4) other-repo item not surfaced"

# (5) ANCHORING: an item whose target bracket is [dotclaude-skills] but whose PROSE mentions
#     'chidiai' must NOT match a chidiai scan — the match keys on the TARGET bracket, not a
#     repo-name substring anywhere on the line (the id:be0e/1bbd anchoring-not-substring class).
grep -q 'routed:dd44' <<<"$out" && fail "(5) prose-substring false-match: dotclaude-targeted item surfaced under chidiai scan:
$out"
pass "(5) target-bracket anchored (prose substring does not false-match)"

# (6) scanning the DIFFERENT repo returns only its own item, none of chidiai's.
out_z="$(run zkm)"
grep -q 'routed:cc33' <<<"$out_z" || fail "(6) [zkm]-targeted item not surfaced under zkm scan:
$out_z"
grep -q 'routed:4975' <<<"$out_z" && fail "(6) chidiai item leaked into zkm scan:
$out_z"
pass "(6) scan is repo-scoped (no cross-repo leak)"

# (7) missing inbox file is BENIGN — the inbox is optional; exit 0, nothing surfaced
#     (NOT a loud dead-letter error; this is a visibility surface, not a reconcile).
rc=0; out_m="$(RELAY_INBOX="$FIX/does-not-exist.md" "$SH" chidiai 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "(7) missing inbox must be benign (exit 0); got $rc"
[[ -z "$out_m" ]] || fail "(7) missing inbox must surface nothing; got:
$out_m"
pass "(7) missing inbox → benign (exit 0, empty)"

# (8) UNREADABLE inbox (present but not a regular readable file) is LOUD, never silently
#     swallowed (the no-2>/dev/null-swallow rule): nonzero exit.
rc=0; RELAY_INBOX="$FIX" "$SH" chidiai >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(8) unreadable inbox (a directory) must exit nonzero (loud), got 0"
pass "(8) unreadable inbox → loud nonzero"

# --- wiring -------------------------------------------------------------------
# The repo-scoped surfaces must actually INVOKE the new scan, else "a check nothing
# invokes isn't a check" (id:de36). SKILL.md invariant-1 currently says a non-`--all`
# run skips the inbox entirely — that carve-out must now name the per-repo filtered scan.
grep -q 'inbox-scan-repo' "$ROOT/relay/references/human.md" \
  || fail "human.md does not reference inbox-scan-repo (repo-scoped surface unwired)"
pass "(9) human.md wires in the per-repo inbox scan"
grep -q 'inbox-scan-repo' "$ROOT/relay/SKILL.md" \
  || fail "SKILL.md does not reference inbox-scan-repo (repo-scoped carve-out unwired)"
pass "(10) SKILL.md wires in the per-repo inbox scan"

echo "ALL PASS: id:ce50 per-repo filtered inbox scan + repo-scoped wiring"
