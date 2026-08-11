#!/usr/bin/env bash
# Spec for tracker/repo-entity.py — repo-level entity derivation (TODO id:c17d).
#
# NO `# roadmap:XXXX` header ON PURPOSE: id:c17d is a TODO-only item in the tracker-pilot
# cluster (children-of:2bb1) with no ROADMAP entry, so there is no checkbox to key
# EXPECTED-RED off. Failures here always count — the emitter ships green with this spec.
#
# Contract under test (the item's own wording: "for a fixture fleet, each repo's board
# status equals classify-repo.sh's verdict"):
#   (1) For a fixture fleet, every repo entity's `verdict` is BYTE-EQUAL to what
#       `classify-repo.sh --emit unit` says for that repo. No second classifier.
#   (2) The display label is render-verdict.sh's (idle -> "drained") and the board column
#       is control-board.sh's — carried ALONGSIDE the raw verdict, collapsing nothing.
#   (3) `emit` produces a document that `ledger-map.py validate` accepts, and `enrich`
#       fills the `verdict: null` hole ledger-map.py leaves without disturbing items.
#   (4) A producer-error repo becomes a `verdict: null` entity + a stderr line — never a
#       dropped repo and never an invented verdict (id:4347 no-silent-swallow).
#   (5) `validate-repos` catches the invariant violations `ledger-map.py validate` does
#       not check at all (it validates items only): a bogus column, a classified column
#       on a null verdict, a missing required key.
#   (6) The known verdict enum is a SUPERSET of every verdict classify-verdict.sh can
#       assign — an anti-drift grep, so a new classifier verdict cannot land silently.
#   (7) PURITY: deriving entities over a repo with a commit, a dirty file and a live
#       worktree leaves that repo byte-identical.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RE="$ROOT/tracker/repo-entity.py"
LM="$ROOT/tracker/ledger-map.py"
CB="$ROOT/relay/scripts/control-board.sh"
CR="$ROOT/relay/scripts/classify-repo.sh"
HELPER="$ROOT/tests/lib/assert-repo-unchanged.sh"
for f in "$RE" "$LM" "$CB" "$CR" "$HELPER"; do
  [[ -f "$f" ]] || { echo "FAIL: missing dependency: $f"; exit 1; }
done
[[ -x "$RE" ]] || { echo "FAIL: tracker/repo-entity.py is not executable"; exit 1; }
# shellcheck disable=SC1090
source "$HELPER"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt-base"
export SRC_DIR="$tmp/src"
# Hermetic: never let an installed relay-core shadow binary write to its parity log.
export RELAY_CORE_BIN=/nonexistent
mkdir -p "$SRC_DIR"

mkrepo() {
  local d="$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}

# --- fixture fleet --------------------------------------------------------------------
# alpha: an open [ROUTINE] roadmap item -> verdict execute -> column relay-poolable
A="$tmp/repo_alpha"; mkrepo "$A"
cat > "$A/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:1111 -->
EOF
cat > "$A/TODO.md" <<'EOF'
# TODO
## Current
- [ ] [HARD] design the thing <!-- id:1111 -->
EOF
git -C "$A" add -A; git -C "$A" commit -qm init

# beta: nothing actionable, clean, audited -> verdict idle -> label "drained"
B="$tmp/repo_beta"; mkrepo "$B"
printf '# Roadmap\n## Items\n' > "$B/ROADMAP.md"
printf '# TODO\n## Current\n' > "$B/TODO.md"
git -C "$B" add -A; git -C "$B" commit -qm init
git -C "$B" tag -a "relay-ckpt-20260101-0000" -m "review: audited"

export RELAY_TOML="$tmp/relay.toml"
cat > "$RELAY_TOML" <<EOF
[repos.repo_alpha]
classification = "own"
path = "$A"

[repos.repo_beta]
classification = "own"
path = "$B"

[repos.repo_gone]
classification = "own"
path = "$tmp/does-not-exist"
EOF

board="$tmp/board.json"
"$CB" --json > "$board" 2>"$tmp/board.err" || fail "control-board.sh --json failed:
$(cat "$tmp/board.err")"

# === (1) verdict equals classify-repo.sh's, verbatim ===================================
repos_doc="$tmp/repos.json"
"$RE" emit --board "$board" > "$repos_doc" 2>"$tmp/emit.err" || fail "emit failed:
$(cat "$tmp/emit.err")"

for pair in "repo_alpha:$A" "repo_beta:$B"; do
  name="${pair%%:*}"; rpath="${pair#*:}"
  truth="$("$CR" --repo "$name" --path "$rpath" --emit unit \
            | python3 -c 'import sys,json; print(json.load(sys.stdin)["verdict"])')"
  got="$(REPO="$name" python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
by = {r["repo"]: r for r in d["repos"]}
print(by[os.environ["REPO"]]["verdict"])' "$repos_doc")"
  [[ "$truth" == "$got" ]] \
    || fail "entity verdict for $name is $got but classify-repo.sh says $truth"
done
pass "each repo entity's verdict equals classify-repo.sh --emit unit, verbatim"

# === (2) label + column carried alongside, nothing collapsed ===========================
python3 - "$repos_doc" <<'PY' || fail "board label/column not carried alongside the raw verdict"
import json, sys
d = json.load(open(sys.argv[1]))
by = {r["repo"]: r for r in d["repos"]}
a, b = by["repo_alpha"], by["repo_beta"]
assert a["verdict"] == "execute" and a["board_column"] == "relay-poolable", a
assert a["board_label"] == "execute", a
# render-verdict.sh is the ONLY sanctioned emitter of "drained": idle -> drained, and the
# raw `idle` verdict SURVIVES next to it.
assert b["verdict"] == "idle" and b["board_label"] == "drained", b
assert b["board_column"] == "design-drained", b
assert "verdict:idle" in b["labels"] and "board:design-drained" in b["labels"], b
assert a["counts"]["actionable_routine_open"] == 1, a
PY
pass "board column + render-verdict.sh label are carried ALONGSIDE the raw verdict"

# === (3) composes with ledger-map.py ===================================================
python3 "$LM" validate "$repos_doc" >/dev/null 2>&1 \
  || fail "emit output is not a document ledger-map.py validate accepts"
pass "emit produces a document ledger-map.py validate accepts"

mapped="$tmp/alpha.json"
python3 "$LM" import repo_alpha "$A" > "$mapped" 2>/dev/null \
  || fail "ledger-map.py import failed on the fixture repo"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["repos"][0]["verdict"] is None, "precondition: the mapper leaves verdict null"
' "$mapped" || fail "precondition failed: ledger-map.py no longer emits verdict null"

enriched="$tmp/alpha.enriched.json"
"$RE" enrich "$mapped" --board "$board" > "$enriched" 2>"$tmp/enrich.err" \
  || fail "enrich failed:
$(cat "$tmp/enrich.err")"
python3 - "$mapped" "$enriched" <<'PY' || fail "enrich did not fill the verdict hole cleanly"
import json, sys
before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
r = after["repos"][0]
assert r["verdict"] == "execute", r
assert r["repo"] == "repo_alpha" and r["path"] == before["repos"][0]["path"], r
# the mapper's own repo fields survive
assert r["ledger_files"] == before["repos"][0]["ledger_files"], r
# items are untouched — this step is repo-level only
assert after["items"] == before["items"], "enrich must not touch items"
assert after["unmapped"] == before["unmapped"]
PY
python3 "$LM" validate "$enriched" >/dev/null 2>&1 \
  || fail "the enriched document no longer validates"
pass "enrich fills ledger-map.py's null verdict, leaves items untouched, still validates"

# a board repo absent from the document is a WARN, never a silent add
grep -q 'repo_beta.*not in the document' "$tmp/enrich.err" \
  || fail "a board repo missing from the document must be loud on stderr; got:
$(cat "$tmp/enrich.err")"
"$RE" enrich "$mapped" --board "$board" --add-missing 2>/dev/null \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = sorted(r["repo"] for r in d["repos"])
assert names == ["repo_alpha", "repo_beta", "repo_gone"], names
' || fail "--add-missing must append board-only repos"
pass "board-only repos WARN by default and are appended only under --add-missing"

# === (4) producer error -> null verdict + stderr, never dropped ========================
python3 - "$repos_doc" <<'PY' || fail "producer-error repo mishandled"
import json, sys
d = json.load(open(sys.argv[1]))
by = {r["repo"]: r for r in d["repos"]}
g = by["repo_gone"]
assert g["verdict"] is None, g
assert g["board_column"] == "unclassified" and g["board_label"] == "producer-error", g
assert "verdict:unavailable" in g["labels"], g
assert g["verdict_reason"], "the reason must be carried, not dropped"
PY
grep -q 'producer-error \[repo_gone\]' "$tmp/emit.err" \
  || fail "a producer error must also be loud on stderr; got:
$(cat "$tmp/emit.err")"
pass "a repo the classifier could not verdict becomes a null-verdict entity + a stderr line"

# === (5) validate-repos catches what ledger-map.py validate does not ===================
"$RE" validate-repos "$enriched" >/dev/null 2>&1 \
  || fail "validate-repos rejected a good document"

bad="$tmp/bad.json"
python3 - "$enriched" "$bad" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"][0]["board_column"] = "totally-made-up"
json.dump(d, open(sys.argv[2], "w"))
PY
if "$RE" validate-repos "$bad" >/dev/null 2>&1; then
  fail "validate-repos accepted a bogus board_column"
fi
# As of schema_version 1.1.0 (id:8c7f) `ledger-map.py validate` covers the repo VALUE
# SPACES too — the gap this subcommand was written around is closed, so BOTH must now
# reject a bogus board_column. (This assertion used to require ledger-map.py to ACCEPT
# it, pinning the gap as a precondition; it is INVERTED, not dropped.)
if python3 "$LM" validate "$bad" >/dev/null 2>&1; then
  fail "ledger-map.py validate accepted a bogus board_column — the 1.1.0 repo enum check is missing"
fi

bad2="$tmp/bad2.json"
python3 - "$enriched" "$bad2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"][0]["verdict"] = None          # no verdict ...
d["repos"][0]["board_column"] = "relay-poolable"   # ... but a classified column
json.dump(d, open(sys.argv[2], "w"))
PY
if "$RE" validate-repos "$bad2" >/dev/null 2>&1; then
  fail "validate-repos accepted a classified column on a null verdict"
fi

bad3="$tmp/bad3.json"
python3 - "$enriched" "$bad3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
del d["repos"][0]["labels"]
json.dump(d, open(sys.argv[2], "w"))
PY
if "$RE" validate-repos "$bad3" >/dev/null 2>&1; then
  fail "validate-repos accepted a repo entity missing a required key"
fi
pass "validate-repos rejects bogus column, unclassifiable column, missing required key"

# === (6) anti-drift: the enum is a superset of classify-verdict.sh's verdicts ==========
python3 - "$ROOT/relay/scripts/classify-verdict.sh" "$RE" <<'PY' \
  || fail "classify-verdict.sh can emit a verdict repo-entity.py does not know"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
found = set(re.findall(r'(?m)^\s*verdict\s*=\s*"([a-zA-Z]+)"\s*$', src))
assert found, "no verdict assignments found — the grep anchor broke, not the enum"
emitter = open(sys.argv[2], encoding="utf-8").read()
known = set(re.findall(r'"([a-zA-Z]+)"',
                       emitter.split("VERDICT_ENUM = [")[1].split("]")[0]))
missing = found - known
assert not missing, "classify-verdict.sh emits %r which VERDICT_ENUM lacks" % sorted(missing)
PY
pass "VERDICT_ENUM covers every verdict classify-verdict.sh can assign (anti-drift grep)"

# === (7) PURITY =======================================================================
P="$tmp/repo_pure"; mkrepo "$P"
cat > "$P/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] pure fixture item <!-- id:2222 -->
EOF
printf '# TODO\n## Current\n- [ ] something <!-- id:3333 -->\n' > "$P/TODO.md"
git -C "$P" add -A; git -C "$P" commit -qm init
echo dirty > "$P/dirty.txt"
git -C "$P" worktree add -q -b wt-branch "$tmp/pure-wt"

pure_toml="$tmp/pure.toml"
cat > "$pure_toml" <<EOF
[repos.repo_pure]
classification = "own"
path = "$P"
EOF
pure_board="$tmp/pure-board.json"
RELAY_TOML="$pure_toml" "$CB" --json > "$pure_board" 2>/dev/null \
  || fail "board failed over the purity fixture"

snap="$tmp/pure.snapshot"
repo_state_snapshot "$P" > "$snap"
pure_doc="$tmp/pure-doc.json"
python3 "$LM" import repo_pure "$P" > "$pure_doc" 2>/dev/null || fail "import failed"
"$RE" emit --board "$pure_board" >/dev/null 2>&1 || fail "emit failed on the purity fixture"
"$RE" enrich "$pure_doc" --board "$pure_board" > "$tmp/pure-enriched.json" 2>/dev/null \
  || fail "enrich failed on the purity fixture"
"$RE" validate-repos "$tmp/pure-enriched.json" >/dev/null 2>&1 || fail "validate-repos failed"
assert_repo_unchanged "$P" "$snap" \
  || fail "repo-entity.py MUTATED the repo — it is documented read-only"
pass "purity: repo with commit + dirty file + live worktree is byte-identical afterwards"

# === -OO regression (the ledger-map.py CLI crash class) ================================
python3 -OO "$RE" emit --board "$board" >/dev/null 2>&1 \
  || fail "python3 -OO crashes the CLI (docstring-stripping regression)"
pass "python3 -OO does not break the CLI"

echo "ALL PASS: tracker/repo-entity.py (TODO id:c17d)"
