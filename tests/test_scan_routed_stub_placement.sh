#!/usr/bin/env bash
# roadmap:14d0 — scan-routed.sh --apply must write INBOUND stubs into an ACTIVE TODO
# section, never under `## Done`. Today the write path (md-merge.py update-ids) appends
# new lines at EOF; a TODO.md ending with a `## Done` section therefore gets its stub
# misfiled as an open `- [ ]` item under Done (observed 2026-07-02: routed:1c2b and
# routed:20b2 both landed under dotclaude-skills' `## Done`; the review relocated them
# by hand). Deterministic and recurring — the stub must anchor BEFORE the first Done/
# archive-class heading; EOF append remains the fallback only when no such heading exists.
#
# RED until the insertion anchor lands. Hermetic: mktemp fixtures, fixture relay.toml/
# inbox, hermetic CLAIM_BASE. Idiom: test_scan_routed_apply.sh.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/scan-routed.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "scan-routed.sh not found at $SH"
[[ -x "$SH" ]] || fail "scan-routed.sh not executable"

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; mkdir -p "$SRC"
CLAIM_BASE="$FIX/claims"; mkdir -p "$CLAIM_BASE"

mk_repo() { # <abs-dir> <todo-content>
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email z@e.st; git -C "$d" config user.name Zommuter
  printf '%s\n' "$2" > "$d/TODO.md"
  printf '# Roadmap\n' > "$d/ROADMAP.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}

run() {
  SRC_DIR="$SRC" RELAY_TOML="$FIX/relay.toml" RELAY_INBOX="$FIX/inbox.md" \
  STATE_JSON="$FIX/no-such-state.json" CLAIM_BASE="$CLAIM_BASE" \
  SCAN_ROUTED_LOG="$FIX/scan.log" "$SH" "$@"
}

# (a) TODO ending with a `## Done` section — the misfile case.
mk_repo "$SRC/donerepo" '# TODO

## active
- [x] something finished long ago <!-- id:0000 -->

## Done
- [x] archived thing <!-- id:1111 -->'

# (b) TODO with NO Done heading — EOF fallback must still write the stub.
mk_repo "$SRC/plainrepo" '# TODO
- [x] only closed work here <!-- id:2222 -->'

cat > "$FIX/relay.toml" <<EOF
[repos.donerepo]
classification = "own"
path = "$SRC/donerepo"

[repos.plainrepo]
classification = "own"
path = "$SRC/plainrepo"
EOF

cat > "$FIX/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [donerepo] stub must land above the Done section (from review, note.md) <!-- routed:eee1 -->
- [ ] [plainrepo] stub with no Done heading uses the EOF fallback (from review, note.md) <!-- routed:eee2 -->
EOF

run --apply >/dev/null 2>&1 || true

done_todo="$SRC/donerepo/TODO.md"
plain_todo="$SRC/plainrepo/TODO.md"

# (1) stub written at all (precondition — shipped id:678e behavior).
grep -q 'routed:eee1' "$done_todo" \
  || fail "(1) --apply did not write the stub for routed:eee1 into $done_todo:
$(cat "$done_todo")"
pass "(1) stub for routed:eee1 written into the Done-terminated TODO"

# (2) the stub must sit BEFORE the `## Done` heading, not after it.
stub_line="$(grep -n 'routed:eee1' "$done_todo" | head -1 | cut -d: -f1)"
done_line="$(grep -n '^## Done' "$done_todo" | head -1 | cut -d: -f1)"
[[ -n "$stub_line" && -n "$done_line" ]] \
  || fail "(2) could not locate stub/Done lines in $done_todo"
if [[ "$stub_line" -lt "$done_line" ]]; then
  pass "(2) stub (line $stub_line) anchored BEFORE the '## Done' heading (line $done_line)"
else
  fail "(2) stub misfiled UNDER '## Done' (stub line $stub_line >= Done line $done_line) — open work hidden in a done section:
$(cat "$done_todo")"
fi

# (3) no Done heading → EOF fallback still writes the stub.
grep -q 'routed:eee2' "$plain_todo" \
  || fail "(3) EOF fallback broken: stub for routed:eee2 missing from $plain_todo:
$(cat "$plain_todo")"
pass "(3) TODO without a Done heading still receives the stub (EOF fallback)"

echo "OK: all stub-placement assertions passed"
