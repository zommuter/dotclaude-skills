#!/usr/bin/env bash
# roadmap:71f2 — Workflow-script template-literal lint.
#
# Guards relay/scripts/lint-workflow-templates.mjs, a parser/lexer-aware check that flags
# an UNESCAPED backtick used as literal text inside a template literal in a Workflow JS
# script. `node --check` is NOT sufficient: commit 178b8db^'s relay-loop.js shipped two
# such backticks (`` `hard`` inside the shardPrompt template), `node --check` + `make test`
# both passed, yet the live Workflow parser rejected the whole script ("Unexpected token
# (763:1527)") so `/relay --afk` could not launch the pool. This suite proves the linter
# (a) FLAGS an unescaped backtick inside a template literal, naming the line, and
# (b) is SILENT on the exempt cases a naive grep would false-positive on: an escaped
# `` \` ``, a backtick inside a //  or /* */ comment, a backtick inside a '…'/"…" string,
# and a regex literal `/'/` whose quote must not desync the lexer — and that the linter
# runs CLEAN against the real tree.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-workflow-templates.mjs not found at $LINT"
node --check "$LINT" || fail "lint-workflow-templates.mjs fails node --check"
pass "linter exists and parses"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# (1) A fixture with an unescaped backtick inside a template literal → nonzero + names line.
cat > "$TMP/bad.mjs" <<'EOF'
export const meta = { name: 'bad' }
const prompt = `classify the repo and demote a `hard` verdict when gated`
EOF
if out="$(node "$LINT" "$TMP/bad.mjs" 2>&1)"; then
  fail "linter did NOT flag an unescaped backtick inside a template literal:
$out"
fi
echo "$out" | grep -qE 'bad\.mjs:2:' \
  || fail "linter flagged but did not name the offending line (expected bad.mjs:2:…):
$out"
pass "(1) unescaped backtick inside a template literal → nonzero, names the line"

# (2) A fixture whose ONLY backticks are exempt → exit zero.
#   - escaped `` \` `` inside template content
#   - a backtick inside a // line comment and a /* */ block comment
#   - a backtick inside '…' and "…" ordinary strings
#   - a regex literal containing a quote (`/'/`) that must not desync the lexer
#   - a normal ${…} interpolation
cat > "$TMP/good.mjs" <<'EOF'
export const meta = { name: 'good' }
// a `hard` backtick in a line comment is exempt
/* a `hard` backtick in a block comment is exempt */
const a = `escaped \`hard\` inline-code is fine`
const b = `with ${value} interpolation and \`esc\` is fine`
const c = 'a `hard` backtick in a single-quoted string is fine'
const d = "a `hard` backtick in a double-quoted string is fine"
const e = `${json.replace(/'/g, "'")}`
const f = `closes cleanly`
const g = `text`.trim()
const h = `text`.slice(0, 10).padEnd(3)
EOF
if ! out="$(node "$LINT" "$TMP/good.mjs" 2>&1)"; then
  fail "linter false-positived on an all-exempt fixture (should exit 0):
$out"
fi
pass "(2) escaped + comment + string + regex-quote + legit .method() close → exit zero (no false positive)"

# (2b) The `.member` tagged-template desync (the id:5bac `.timer` crash, 2026-07-07): an
#      unescaped backtick inside a template followed by a `.identifier` chain then ANOTHER
#      backtick parses as a VALID tagged template `(…).member`…`` — node --check + the
#      Workflow parser both pass, but `.member` is undefined at runtime → pool crash. This
#      is the variant the original isWordChar(next)-only rule MISSED (next was `.`, not a
#      word char), so a purpose-built guard reported the broken relay-loop.js CLEAN.
cat > "$TMP/member.mjs" <<'EOF'
export const meta = { name: 'member' }
const prompt = `fall back when the id:9d97 `.timer` is not installed, the default`
EOF
if out="$(node "$LINT" "$TMP/member.mjs" 2>&1)"; then
  fail "linter did NOT flag a `.member` tagged-template desync (the .timer crash class):
$out"
fi
echo "$out" | grep -qE 'member\.mjs:2:' \
  || fail "linter flagged the .member desync but did not name the offending line:
$out"
pass "(2b) unescaped backtick + .member chain + reopening backtick (tagged-template desync) → nonzero, names the line"

# (2c) The OPERATOR-glued inline span (the id:efaf `-c` crash, 2026-07-07): `(…) - c `…`` is
#      valid subtraction — node --check + the Workflow parser pass, but `c` is undefined at
#      runtime → "c is not defined" thrown out of integrate() → whole-pool crash. The `.member`
#      rule did NOT catch this (`-` is neither a word char nor `.`); the generalized inline-span
#      rule does. Same shape as `hard`/`.timer`: a short glued token bracketed by two backticks.
cat > "$TMP/dashc.mjs" <<'EOF'
export const meta = { name: 'dashc' }
const prompt = `the checkpoint anchor (`-c` for step 3) is decided here`
EOF
if out="$(node "$LINT" "$TMP/dashc.mjs" 2>&1)"; then
  fail "linter did NOT flag an operator-glued inline span (the -c crash class):
$out"
fi
echo "$out" | grep -qE 'dashc\.mjs:2:' \
  || fail "linter flagged the -c inline span but did not name the offending line:
$out"
pass "(2c) unescaped backtick + operator-glued token + reopening backtick (\`-c\` desync) → nonzero, names the line"

# (3) Directory scan discovers workflow scripts via the `export const meta` marker and
#     ignores a plain script with no marker.
mkdir -p "$TMP/repo/relay/scripts"
cp "$TMP/bad.mjs" "$TMP/repo/relay/scripts/wf.workflow.js"
cat > "$TMP/repo/relay/scripts/plain.mjs" <<'EOF'
// no meta marker → not a workflow script; its `bad` template `here` is not linted
const z = `a `b` c`
EOF
if node "$LINT" "$TMP/repo" >/dev/null 2>&1; then
  fail "directory scan missed the violation in wf.workflow.js"
fi
out="$(node "$LINT" "$TMP/repo" 2>&1 || true)"
echo "$out" | grep -q 'wf.workflow.js' || fail "directory scan did not report wf.workflow.js:
$out"
echo "$out" | grep -q 'plain.mjs' && fail "directory scan wrongly linted the non-workflow plain.mjs:
$out"
pass "(3) dir scan finds *.workflow.js / export-const-meta scripts, skips non-workflow files"

# (4) The real tree is CLEAN (acceptance #3 — no existing violation post-178b8db).
if ! out="$(node "$LINT" "$ROOT" 2>&1)"; then
  fail "the live tree has a template-literal violation (run the linter to see it):
$out"
fi
pass "(4) live tree lints clean"

# (5) Wired into the Makefile install manifest (id:69ef install-completeness precedent).
grep -q 'scripts/lint-workflow-templates.mjs' "$ROOT/Makefile" \
  || fail "lint-workflow-templates.mjs not in the Makefile relay manifest"
pass "(5) linter is in the Makefile install manifest"

echo "ALL PASS"
