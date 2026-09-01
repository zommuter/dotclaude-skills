#!/usr/bin/env bash
# Spec for relay/scripts/control-board.sh — the tracker pilot's CONTROL-ARM board.
#
# NO `# roadmap:XXXX` header ON PURPOSE: this item is TODO id:8066 (the tracker-pilot
# cluster under id:4a5c) and has no ROADMAP entry, so there is no roadmap checkbox to key
# EXPECTED-RED off. Failures here therefore always count — which is correct, the board ships
# green in the same commit as this spec.
#
# Contract under test:
#   (1) Repo set comes from relay.toml's own-set via the SHARED own_repos() parser: honours
#       `classification`, `paused`, an explicit `path`, and the `# path:` COMMENT override.
#       Never a ~/src glob.
#   (2) A corrupt relay.toml aborts LOUDLY (nonzero exit, no board) — never a silent empty
#       board (id:0fa0 finding (a)).
#   (3) Per-repo verdict is classify-repo.sh's, VERBATIM; the display label is
#       render-verdict.sh's (idle → drained). No second classifier.
#   (4) Board columns group the verdict enum without collapsing it (raw verdict still shown):
#       blocked / relay-poolable / needs-feedback / design-drained / unclassified.
#   (5) A missing path / non-git dir / failing classify becomes a `producer-error` row AND a
#       stderr line, and does NOT abort the board for the other repos (id:4347).
#   (6) `--json` emits a machine-readable aggregate with a summary + per-repo rows.
#   (7) PURITY (executor-contract purity-test-as-contract): running the board over a repo
#       with a commit, a dirty file and a live worktree leaves that repo byte-identical.
# fails-against: rev 8f1e25e1522b -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix Makefile, relay/SKILL.md, relay/scripts/control-board.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 8f1e25e1522b -- Makefile relay/SKILL.md relay/scripts/control-board.sh
# fails-against-assertion: control-board.sh missing/not executable:

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CB="$ROOT/relay/scripts/control-board.sh"
HELPER="$ROOT/tests/lib/assert-repo-unchanged.sh"
[[ -x "$CB" ]] || { echo "FAIL: control-board.sh missing/not executable: $CB"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: purity helper missing: $HELPER"; exit 1; }
# shellcheck disable=SC1090
source "$HELPER"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt-base"
export SRC_DIR="$tmp/src"
# Hermetic: never let an installed relay-core binary write to the shadow-parity log.
export RELAY_CORE_BIN=/nonexistent
mkdir -p "$SRC_DIR"

mkrepo() {
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}

# --- fixtures -------------------------------------------------------------------------
# A: open [ROUTINE] → verdict execute → relay-poolable
A="$tmp/repo_a"; mkrepo "$A"
cat > "$A/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:1111 -->
EOF
printf '# TODO\n## Current\n' > "$A/TODO.md"
git -C "$A" add -A; git -C "$A" commit -qm init

# B: nothing actionable, clean, audited → verdict idle → design-drained (label "drained")
B="$SRC_DIR/repo_b"; mkrepo "$B"
printf '# Roadmap\n## Items\n' > "$B/ROADMAP.md"
printf '# TODO\n## Current\n' > "$B/TODO.md"
git -C "$B" add -A; git -C "$B" commit -qm init
git -C "$B" tag -a "relay-ckpt-20260101-0000" -m "review: audited"

# C: reached ONLY via the `# path:` comment override
C="$tmp/elsewhere/repo_c"; mkrepo "$C"
printf '# Roadmap\n## Items\n' > "$C/ROADMAP.md"
printf '# TODO\n## Current\n' > "$C/TODO.md"
git -C "$C" add -A; git -C "$C" commit -qm init
git -C "$C" tag -a "relay-ckpt-20260101-0000" -m "review: audited"

# D: paused → must NOT appear
D="$tmp/repo_d"; mkrepo "$D"
printf '# Roadmap\n' > "$D/ROADMAP.md"; git -C "$D" add -A; git -C "$D" commit -qm init

# E: classification != own → must NOT appear
E="$tmp/repo_e"; mkrepo "$E"
printf '# Roadmap\n' > "$E/ROADMAP.md"; git -C "$E" add -A; git -C "$E" commit -qm init

# F: registered but its path does not exist → producer-error row, board still renders
export RELAY_TOML="$tmp/relay.toml"
cat > "$RELAY_TOML" <<EOF
[repos.repo_a]
classification = "own"
path = "$A"

[repos.repo_b]
classification = "own"

[repos.repo_c]
# path: $C
classification = "own"

[repos.repo_d]
classification = "own"
path = "$D"
paused = true

[repos.repo_e]
classification = "external"
path = "$E"

[repos.repo_f]
classification = "own"
path = "$tmp/does-not-exist"
EOF

# === (1)+(4)+(5) markdown board ========================================================
board_err="$tmp/board.err"
board="$("$CB" 2>"$board_err")" || fail "control-board.sh exited nonzero on a valid fleet"

grep -q '^| repo_a | relay-poolable | execute |' <<<"$board" \
  || fail "repo_a should render as relay-poolable/execute; got:
$board"
pass "open [ROUTINE] repo renders relay-poolable with the verbatim execute verdict"

grep -q '^| repo_b | design-drained | drained |' <<<"$board" \
  || fail "repo_b should render design-drained with render-verdict.sh's 'drained' label; got:
$board"
pass "idle repo renders design-drained via render-verdict.sh's sanctioned label"

grep -q '^| repo_c | design-drained | drained |' <<<"$board" \
  || fail "repo_c (# path: comment override) missing from the board; got:
$board"
pass "\`# path:\` comment override is honoured (own_repos parser, never a ~/src glob)"

if grep -q 'repo_d' <<<"$board"; then fail "paused repo_d must not appear on the board"; fi
pass "paused repo is excluded"

if grep -q 'repo_e' <<<"$board"; then fail "non-own repo_e must not appear on the board"; fi
pass "non-own repo is excluded"

grep -q '^| repo_f | unclassified | producer-error |' <<<"$board" \
  || fail "missing-path repo_f should render a producer-error row; got:
$board"
grep -q '^- \*\*repo_f\*\*' <<<"$board" || fail "repo_f missing from the Producer errors section"
grep -q 'producer-error \[repo_f\]' "$board_err" \
  || fail "producer error must ALSO be loud on stderr (id:4347); stderr was:
$(cat "$board_err")"
pass "producer error is a row AND a loud stderr line, and does not abort the board"

grep -q '^## Fleet summary' <<<"$board" || fail "no Fleet summary section"
grep -q '^| relay-poolable | 1 |' <<<"$board" || fail "fleet summary miscounts relay-poolable; got:
$board"
grep -q '^## Waiting on a human' <<<"$board" || fail "no 'Waiting on a human' section"
pass "board carries fleet summary + waiting-on-a-human sections"

# === (3) the verdict is classify-repo.sh's, verbatim ===================================
direct="$("$ROOT/relay/scripts/classify-repo.sh" --repo repo_a --path "$A" --emit unit 2>/dev/null \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["verdict"])')"
[[ "$direct" == "execute" ]] || fail "fixture drifted: classify-repo says '$direct', expected execute"
grep -q "| repo_a | relay-poolable | $direct |" <<<"$board" \
  || fail "board verdict is not classify-repo.sh's verbatim value ($direct)"
pass "board re-uses classify-repo.sh's verdict verbatim — no second classifier"

# === (6) --json ========================================================================
json="$("$CB" --json 2>/dev/null)" || fail "--json exited nonzero"
cat > "$tmp/assert_json.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
assert d["schema_version"] == 1, d
assert "generated_at" in d and d["generated_at"].endswith("Z"), d
by = {r["repo"]: r for r in d["repos"]}
assert set(by) == {"repo_a", "repo_b", "repo_c", "repo_f"}, sorted(by)
assert by["repo_a"]["verdict"] == "execute" and by["repo_a"]["column"] == "relay-poolable", by["repo_a"]
assert by["repo_a"]["actionable_routine_open"] == 1, by["repo_a"]
assert by["repo_b"]["verdict"] == "idle" and by["repo_b"]["label"] == "drained", by["repo_b"]
assert by["repo_f"]["producer_error"] is True and by["repo_f"]["column"] == "unclassified", by["repo_f"]
assert d["summary"]["relay-poolable"] == 1 and d["summary"]["design-drained"] == 2, d["summary"]
assert d["summary"]["unclassified"] == 1, d["summary"]
PY
python3 "$tmp/assert_json.py" <<<"$json" || fail "--json output failed its schema assertions"
pass "--json emits a schema-versioned aggregate with summary + per-repo rows"

# === (1) --repo filter =================================================================
one="$("$CB" --repo repo_a 2>/dev/null)"
grep -q '| repo_a |' <<<"$one" || fail "--repo repo_a dropped repo_a"
if grep -q '| repo_b |' <<<"$one"; then fail "--repo repo_a must not render repo_b"; fi
pass "--repo restricts the board to one repo"

# === (2) corrupt relay.toml aborts LOUDLY ==============================================
bad_toml="$tmp/bad.toml"
printf '[repos.x\nclassification = "own"\n' > "$bad_toml"
bad_err="$tmp/bad.err"
if RELAY_TOML="$bad_toml" "$CB" >"$tmp/bad.out" 2>"$bad_err"; then
  fail "a corrupt relay.toml must abort with a nonzero exit, not render a board"
fi
grep -qi 'FAILED to parse relay.toml' "$bad_err" || fail "corrupt relay.toml must be loud on stderr; got:
$(cat "$bad_err")"
[[ ! -s "$tmp/bad.out" ]] || fail "corrupt relay.toml must render NOTHING on stdout"
pass "corrupt relay.toml aborts loudly with an empty stdout (id:0fa0 finding (a))"

# === (7) PURITY ========================================================================
P="$tmp/repo_pure"; mkrepo "$P"
cat > "$P/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] pure fixture item <!-- id:2222 -->
EOF
printf '# TODO\n## Current\n- [ ] something <!-- id:3333 -->\n' > "$P/TODO.md"
git -C "$P" add -A; git -C "$P" commit -qm init
echo dirty > "$P/dirty.txt"                       # untracked churn, part of the state
git -C "$P" worktree add -q -b wt-branch "$tmp/pure-wt"

pure_toml="$tmp/pure.toml"
cat > "$pure_toml" <<EOF
[repos.repo_pure]
classification = "own"
path = "$P"
EOF

snap="$tmp/pure.snapshot"
repo_state_snapshot "$P" > "$snap"
RELAY_TOML="$pure_toml" "$CB" >/dev/null 2>&1 || fail "board failed over the purity fixture"
RELAY_TOML="$pure_toml" "$CB" --json >/dev/null 2>&1 || fail "board --json failed over the purity fixture"
assert_repo_unchanged "$P" "$snap" || fail "control-board.sh MUTATED the repo — it is documented read-only"
pass "purity: repo with commit + dirty file + live worktree is byte-identical after two runs"

echo "ALL PASS: control-board.sh (TODO id:8066)"
