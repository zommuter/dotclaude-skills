#!/usr/bin/env bash
# roadmap:678e — scan-routed.sh (slice 1): report-only dead-letter detector for the shared
# cross-project inbox. For each conforming `- [ ] [target] … <!-- routed:XXXX -->`, a
# dead-letter is one whose target repo's TODO+ROADMAP lacks the token. Also surfaces
# non-conforming inbox entries (via todo-conformance.sh --inbox) and unresolvable targets.
# NEVER writes (slice-2 auto-file is gated). Decided 2026-06-25 (inbox-auto-reconcile note).
#
# RED until the script + wiring land. Hermetic: fixture relay.toml + fake own repos + inbox.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/scan-routed.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "scan-routed.sh not found at $SH"
[[ -x "$SH" ]] || fail "scan-routed.sh not executable"
bash -n "$SH" || fail "scan-routed.sh fails bash -n"
pass "scan-routed.sh exists, executable, parses"

# (0) Misuse: unknown flag exits nonzero.
rc=0; "$SH" --definitely-not-a-flag >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "unknown flag must exit nonzero (misuse); got 0"
pass "unknown flag exits nonzero (misuse reject)"

# --- fixture: two own repos + an inbox -----------------------------------------
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mk_repo() { # <name> <todo-content>
  local d="$FIX/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email t@e.st; git -C "$d" config user.name t
  printf '%s\n' "$2" > "$d/TODO.md"
  printf '# Roadmap\n' > "$d/ROADMAP.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}
# repoA already carries routed:1111 → that inbox item is NOT a dead letter.
mk_repo repoA '# TODO
- [ ] already filed here <!-- routed:1111 -->'
# repoB lacks routed:2222 → dead letter.
mk_repo repoB '# TODO'
# repoD: the token 1648 appears ONLY as the HHMM field of a meeting-note timestamp
# (no routed:1648 / id:1648 twin) → must STILL be a dead letter. Guards the bare-token
# substring false-match (regression 2026-06-30: routed:0928/1328 read as clean because
# their 4 chars matched meeting-note filename timestamps).
mk_repo repoD '# TODO
- [ ] see docs/meeting-notes/2026-06-30-1648-foo.md for context <!-- id:abcd -->'

cat > "$FIX/relay.toml" <<EOF
[repos.repoA]
classification = "own"
path = "$FIX/repoA"
[repos.repoB]
classification = "own"
path = "$FIX/repoB"
[repos.repoD]
classification = "own"
path = "$FIX/repoD"
EOF

cat > "$FIX/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [repoA] already filed (from src, note.md) <!-- routed:1111 -->
- [ ] [repoB] stranded dead letter (from src, note.md) <!-- routed:2222 -->
- [ ] [repoC] targets an unknown repo (from src, note.md) <!-- routed:3333 -->
- [ ] [repoD] timestamp-masked dead letter (from src, note.md) <!-- routed:1648 -->
zkm core: a token-less prose block with no checkbox and no routed token
EOF

run() { RELAY_INBOX="$FIX/inbox.md" RELAY_TOML="$FIX/relay.toml" SRC_DIR="$FIX" "$SH" "$@" 2>/dev/null; }

# (1) report-only: exit 0 even with findings.
rc=0; out="$(run)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only must exit 0 with findings; got $rc
$out"
pass "report-only (exit 0 with findings)"

# (2) routed:1111 has a twin in repoA → NOT a dead letter, but surfaced as RESOLVABLE
#     (vanish-on-resolve 2026-06-30: an already-landed item is drainable, not silent).
grep -qE 'DEAD-LETTER.*routed:1111' <<<"$out" && fail "(2) twinned routed:1111 wrongly flagged DEAD-LETTER:
$out"
grep -qE 'RESOLVABLE.*routed:1111' <<<"$out" || fail "(2) twinned routed:1111 not surfaced as RESOLVABLE:
$out"
pass "(2) twinned routed item → RESOLVABLE (not dead-letter)"

# (3) routed:2222 absent from repoB → DEAD-LETTER, with a ready-to-run/actionable hint.
grep -qi 'routed:2222' <<<"$out" || fail "(3) dead-letter routed:2222 not reported:
$out"
grep -qiE 'dead.?letter' <<<"$out" || fail "(3) no dead-letter label in output:
$out"
grep -q 'repoB' <<<"$out" || fail "(3) dead-letter line does not name the target repoB:
$out"
pass "(3) un-twinned routed item → DEAD-LETTER naming the target"

# (4) routed:3333 → target repoC is not an own repo → surfaced as unresolved (not silently dropped).
grep -qi 'routed:3333' <<<"$out" || fail "(4) unresolved-target routed:3333 not surfaced:
$out"
pass "(4) unresolvable target → surfaced, not silently dropped"

# (5) token-less prose block → non-conforming (via todo-conformance --inbox).
grep -q 'token-less prose block' <<<"$out" || fail "(5) token-less inbox prose not surfaced:
$out"
pass "(5) non-conforming inbox prose → surfaced"

# (6) --exclude repoB drops that target from the dead-letter scan.
out2="$(run --exclude repoB)"
grep -qi 'routed:2222' <<<"$out2" && fail "(6) --exclude repoB did not drop its dead letter:
$out2"
pass "(6) --exclude <repo> drops that target"

# (7) a ready-to-run command is surfaced for the dead letter (actionable, not just a log).
grep -qE 'append\.sh|md-merge|inbox-done' <<<"$out" || fail "(7) no ready-to-run command surfaced for dead letters:
$out"
pass "(7) dead-letter output includes an actionable command"

# (8) REGRESSION: routed:1648 is absent as a real twin in repoD (only as a meeting-note
#     timestamp substring) → must be flagged DEAD-LETTER, not silently swallowed as clean.
grep -qi 'routed:1648' <<<"$out" || fail "(8) timestamp-masked dead-letter routed:1648 not reported (bare-token substring false-match regression):
$out"
grep -q 'repoD' <<<"$out" || fail "(8) dead-letter routed:1648 does not name target repoD:
$out"
pass "(8) bare-token substring false-match guarded (meeting-note timestamp ≠ twin)"

# --- wiring -------------------------------------------------------------------
grep -q 'scan-routed.sh' "$ROOT/relay/scripts/relay-doctor.sh" || fail "relay-doctor.sh does not invoke scan-routed.sh"
pass "relay-doctor.sh wires in scan-routed.sh"
grep -qE 'scan-routed' "$ROOT/relay/references/human.md" || fail "human.md does not reference scan-routed"
pass "human.md references scan-routed"

echo "ALL PASS: id:678e slice-1 scan-routed.sh dead-letter detector + wiring"
