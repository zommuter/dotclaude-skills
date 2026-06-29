#!/usr/bin/env bash
# roadmap:678e — scan-routed.sh SLICE 2: `--apply` (class-A idempotent INBOUND auto-write).
# Decided 2026-06-29 (`docs/meeting-notes/2026-06-29-1116-inbox-reconcile-slice2-gate-open.md`).
#
# Slice-1 (report-only) is specced in test_scan_routed.sh and SHIPPED. This file is the
# RED spec for slice-2 ONLY: a `--apply` flag that, for each class-A dead-letter (a
# conforming `routed:XXXX` whose [target] resolves to a repo ON DISK that lacks the
# token), writes a reversible additive INBOUND stub into that target repo's TODO.md and
# commits it (commit-ledger.sh, never `git add -A`). It is:
#   - idempotent on routed:XXXX (grep the target TODO for the routed token OR its minted
#     id: twin before writing — a 2nd run is a no-op),
#   - resolve-by-EXISTENCE not relay.toml membership (polyrepo `# path:` → central TODO;
#     an own repo on disk with no relay.toml block still resolves; a target matching NO
#     repo on disk stays UNRESOLVED / class-B surface-only, never written),
#   - and gated by a mandatory `--dry-run` that writes NOTHING and prints the plan/diff.
#
# RED until `--apply` lands (today scan-routed.sh rejects the unknown flag) — id:678e is
# unticked in ROADMAP.md, so a red run here is reported EXPECTED-RED by run-tests.sh.
# Assertions target the MISSING behaviour (stub written / not written), never a crash.
#
# Hermetic: mktemp fixtures, a fake SRC_DIR of git repos, a fake relay.toml (incl. a
# `# path:` polyrepo override), a fake RELAY_INBOX, and a hermetic CLAIM_BASE. Never
# touches ~/.claude, real repos, or the network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/scan-routed.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "scan-routed.sh not found at $SH"
[[ -x "$SH" ]] || fail "scan-routed.sh not executable"
bash -n "$SH" || fail "scan-routed.sh fails bash -n"
pass "scan-routed.sh exists, executable, parses"

# --- fixtures -----------------------------------------------------------------
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; mkdir -p "$SRC"

# A repo authored by the user (no remote) → discover-repos.sh classifies it "own".
mk_repo() { # <abs-dir> <todo-content>
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email z@e.st; git -C "$d" config user.name Zommuter
  printf '%s\n' "$2" > "$d/TODO.md"
  printf '# Roadmap\n' > "$d/ROADMAP.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}

# (a) polyrepo: central zkm repo + a plugin subdir; relay.toml maps the plugin target
#     name to the CENTRAL repo path via `# path:`. The stub must land in the central
#     TODO, NOT the plugin's TODO.
mk_repo "$SRC/zkm" '# TODO'
mkdir -p "$SRC/zkm/plugins/zkm-foo"
printf '# TODO (plugin — must stay untouched)\n' > "$SRC/zkm/plugins/zkm-foo/TODO.md"
git -C "$SRC/zkm" add -A; git -C "$SRC/zkm" commit -qm plugin

# (b) non-relay-own: an own repo on disk with NO relay.toml block.
mk_repo "$SRC/myproj" '# TODO'

cat > "$FIX/relay.toml" <<EOF
[repos.zkm-foo]
classification = "own"
# path: $SRC/zkm
EOF

# Inbox: one polyrepo dead-letter, one non-relay-own dead-letter, one nonexistent target.
cat > "$FIX/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [zkm-foo] add a foo helper (from meeting, note.md) <!-- routed:aaaa -->
- [ ] [myproj] wire the bar pass (from meeting, note.md) <!-- routed:bbbb -->
- [ ] [ghostrepo] targets a repo that is not on disk (from meeting, note.md) <!-- routed:cccc -->
EOF

# Hermetic env: own-repo glob comes from SRC, relay.toml + inbox from the fixture, a
# fresh CLAIM_BASE so claim.sh peek finds no holder, and STATE_JSON pointed at nothing
# so discover-repos falls back to the $SRC glob (not a real project_manager cache).
CLAIM_BASE="$FIX/claims"; mkdir -p "$CLAIM_BASE"
run() {
  SRC_DIR="$SRC" RELAY_TOML="$FIX/relay.toml" RELAY_INBOX="$FIX/inbox.md" \
  STATE_JSON="$FIX/no-such-state.json" CLAIM_BASE="$CLAIM_BASE" \
  SCAN_ROUTED_LOG="$FIX/scan.log" "$SH" "$@"
}

zkm_todo="$SRC/zkm/TODO.md"
plugin_todo="$SRC/zkm/plugins/zkm-foo/TODO.md"
myproj_todo="$SRC/myproj/TODO.md"

# (1) --apply polyrepo: stub written into the CENTRAL zkm TODO, not the plugin's.
run --apply >/dev/null 2>&1 || true
grep -q 'routed:aaaa' "$zkm_todo" \
  || fail "(1) --apply did not write the INBOUND stub for routed:aaaa into central $zkm_todo:
$(cat "$zkm_todo")"
grep -qi 'INBOUND' "$zkm_todo" \
  || fail "(1) the written stub is not an INBOUND stub in $zkm_todo"
grep -q 'routed:aaaa' "$plugin_todo" \
  && fail "(1) stub wrongly written into the PLUGIN TODO $plugin_todo (must go to central)"
pass "(1) polyrepo target → INBOUND stub written into the central TODO, plugin untouched"

# (2) non-relay-own: target resolves by repo-existence (no relay.toml block) → its TODO.
grep -q 'routed:bbbb' "$myproj_todo" \
  || fail "(2) --apply did not write the stub for routed:bbbb into the non-relay-own repo $myproj_todo:
$(cat "$myproj_todo")"
pass "(2) own repo on disk with no relay.toml block → stub written into its TODO"

# (3) nonexistent target: never written, stays UNRESOLVED / class-B surface-only.
out="$(run --apply 2>/dev/null || true)"
grep -rq 'routed:cccc' "$SRC"/*/TODO.md "$SRC"/zkm/plugins/*/TODO.md 2>/dev/null \
  && fail "(3) routed:cccc was written somewhere, but [ghostrepo] is not on disk:
$out"
grep -qi 'UNRESOLVED' <<<"$out" \
  || fail "(3) nonexistent target routed:cccc not surfaced as UNRESOLVED:
$out"
pass "(3) nonexistent target → never written, surfaced UNRESOLVED (class-B)"

# (4) idempotent re-run: the second --apply is a no-op (stub appears exactly once).
run --apply >/dev/null 2>&1 || true   # third invocation total — still exactly one stub
n="$(grep -c 'routed:aaaa' "$zkm_todo" || true)"
[[ "$n" -eq 1 ]] || fail "(4) idempotency broken: routed:aaaa appears $n times in $zkm_todo (want 1)"
m="$(grep -c 'routed:bbbb' "$myproj_todo" || true)"
[[ "$m" -eq 1 ]] || fail "(4) idempotency broken: routed:bbbb appears $m times in $myproj_todo (want 1)"
pass "(4) re-running --apply is a no-op (each stub written exactly once)"

# (5) --apply --dry-run: writes NOTHING and prints the plan/diff.
FIX2="$(mktemp -d)"; SRC2="$FIX2/src"; mkdir -p "$SRC2"
mk_repo "$SRC2/myproj" '# TODO'
cat > "$FIX2/relay.toml" <<EOF
[repos.myproj]
classification = "own"
path = "$SRC2/myproj"
EOF
cat > "$FIX2/inbox.md" <<'EOF'
# Cross-project TODO inbox
- [ ] [myproj] dry-run must not write this (from meeting, note.md) <!-- routed:dddd -->
EOF
before="$(cat "$SRC2/myproj/TODO.md")"
dry="$(SRC_DIR="$SRC2" RELAY_TOML="$FIX2/relay.toml" RELAY_INBOX="$FIX2/inbox.md" \
       STATE_JSON="$FIX2/no-such-state.json" CLAIM_BASE="$FIX/claims" \
       SCAN_ROUTED_LOG="$FIX2/scan.log" "$SH" --apply --dry-run 2>/dev/null || true)"
after="$(cat "$SRC2/myproj/TODO.md")"
[[ "$before" == "$after" ]] \
  || fail "(5) --apply --dry-run mutated the target TODO (must write nothing):
$after"
grep -q 'routed:dddd' <<<"$dry" \
  || fail "(5) --dry-run did not print a plan/diff naming routed:dddd:
$dry"
grep -qiE 'dry.?run|would|plan|\+.*INBOUND' <<<"$dry" \
  || fail "(5) --dry-run output is not an inspectable plan/diff:
$dry"
rm -rf "$FIX2"
pass "(5) --apply --dry-run writes nothing and prints the plan/diff"

echo "ALL PASS: id:678e slice-2 scan-routed.sh --apply (5 cases)"
