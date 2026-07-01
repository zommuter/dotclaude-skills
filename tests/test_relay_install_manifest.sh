#!/usr/bin/env bash
# roadmap:5f09 — relay install-manifest completeness + quota-stop invocation contract.
#
# Why this exists: on 2026-06-15 the default pool was non-functional yet the suite
# was green, because (1) the Makefile relay_FILES/_EXEC/_ALLOW manifest had omitted
# scripts (quota-stop.sh, relay-loop.js were never symlinked by `make install`) and
# (2) relay-loop.js called quota-stop.sh with bad positional args
# (`--tier T <agents> 0`) that the script rejects with exit 2. These two contract
# checks would have caught both failures.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MK="$SRC_DIR/Makefile"
SCRIPTS_DIR="$SRC_DIR/relay/scripts"
JS="$SCRIPTS_DIR/relay-loop.js"
QS="$SCRIPTS_DIR/quota-stop.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MK" ]] || fail "Makefile not found at $MK"
[[ -d "$SCRIPTS_DIR" ]] || fail "relay/scripts dir not found at $SCRIPTS_DIR"
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -x "$QS" ]] || fail "quota-stop.sh not found/executable at $QS"

# ── Helper: extract a line-continued Make variable block (VAR := a \ <newline> b ...).
# Reads from the line containing "<var> :=" until the first line WITHOUT a trailing
# backslash (inclusive). Prints the joined contents.
extract_var() {
  local var="$1"
  awk -v var="$var" '
    $0 ~ ("^" var "[[:space:]]*:=") { inblk=1 }
    inblk { line=$0; sub(/\\[[:space:]]*$/, "", line); printf "%s ", line;
            if ($0 !~ /\\[[:space:]]*$/) exit }
  ' "$MK"
}

FILES_BLK="$(extract_var relay_FILES)"
EXEC_BLK="$(extract_var relay_EXEC)"
ALLOW_BLK="$(extract_var relay_ALLOW)"

[[ -n "$FILES_BLK" ]] || fail "could not extract relay_FILES block from Makefile"
[[ -n "$EXEC_BLK" ]]  || fail "could not extract relay_EXEC block from Makefile"
[[ -n "$ALLOW_BLK" ]] || fail "could not extract relay_ALLOW block from Makefile"
pass "extracted relay_FILES / relay_EXEC / relay_ALLOW blocks from Makefile"

# ── (1) INSTALL-COMPLETENESS ────────────────────────────────────────────────
# Every file under relay/scripts/ must be registered as scripts/<name> in relay_FILES
# so `make install` symlinks it. Every executable *.sh must additionally appear in
# relay_EXEC AND relay_ALLOW. *.js is in FILES only (read by the Workflow tool, not run).
contains_token() {
  # word-boundary-ish match: token surrounded by whitespace or string ends.
  case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

shopt -s nullglob
checked=0
for f in "$SCRIPTS_DIR"/*; do
  name="$(basename "$f")"
  # Skip Python bytecode caches: never an install/symlink target, and they materialize
  # whenever a test or run imports a relay python module (e.g. backtest-historical.py).
  [[ "$name" == "__pycache__" || "$name" == *.pyc ]] && continue
  tok="scripts/$name"
  checked=$((checked + 1))

  contains_token "$FILES_BLK" "$tok" \
    || fail "$tok in relay_FILES (file under relay/scripts/ is not registered; make install won't symlink it)"

  if [[ "$name" == *.sh && -x "$f" ]]; then
    contains_token "$EXEC_BLK" "$tok" \
      || fail "$tok in relay_EXEC (executable *.sh must be chmod'd on install)"
    contains_token "$ALLOW_BLK" "$tok" \
      || fail "$tok in relay_ALLOW (executable *.sh must be allowlisted)"
  fi
done
shopt -u nullglob
[[ "$checked" -gt 0 ]] || fail "no files found under relay/scripts/ (glob failed?)"
pass "install-completeness: all $checked relay/scripts/* registered in relay_FILES (+ *.sh in _EXEC/_ALLOW)"

# ── (2) QUOTA-STOP INVOCATION CONTRACT ──────────────────────────────────────
# relay-loop.js must invoke quota-stop.sh using ONLY flags the script accepts.

# 2a. Derive the accepted long-flags from quota-stop.sh's arg loop, and confirm it
#     rejects unknown args (a `*) ... exit 2` default case).
for flag in --tier --agents --wall; do
  grep -qE "^[[:space:]]*$flag\)" "$QS" \
    || fail "quota-stop.sh arg loop has no '$flag)' case (accepted-flag contract changed)"
done
grep -qE '^\s*\*\)' "$QS" || fail "quota-stop.sh has no '*)' default case"
grep -qE '^\s*\*\).*exit 2' "$QS" \
  || fail "quota-stop.sh '*)' default case does not 'exit 2' on unknown arg (won't reject bad invocation)"
pass "quota-stop.sh accepts {--tier,--agents,--wall} and rejects unknown args (exit 2)"

# 2b. Find the relay-loop.js line that invokes quota-stop.sh and assert it uses the
#     three flags with no bare positional argument. The original bug was
#     '--tier ${tier} ${unitsDispatched} 0' — bare positionals after --tier that
#     quota-stop.sh rejects with exit 2 (silently disabling the gate / killing dispatch).
inv="$(grep -n 'quota-stop\.sh' "$JS" | grep -- '--tier' || true)"
[[ -n "$inv" ]] || fail "no quota-stop.sh invocation with --tier found in relay-loop.js"

# Isolate the invocation substring from 'quota-stop.sh' up to the trailing newline marker
# in the template literal (the command is on a single template-literal line).
cmd="$(printf '%s\n' "$inv" | sed -n 's/.*\(quota-stop\.sh[^\\]*\).*/\1/p' | head -1)"
[[ -n "$cmd" ]] || fail "could not isolate the quota-stop.sh command substring"

for flag in --tier --agents --wall; do
  contains_token "$cmd" "$flag" \
    || fail "quota-stop.sh invocation missing '$flag' (got: $cmd)"
done
pass "quota-stop.sh invocation passes --tier, --agents, --wall"

# Bare-positional guard: every token after 'quota-stop.sh' must be a --flag or the
# *value* immediately following a --flag. Walk the tokens and reject any non-flag token
# that is NOT preceded by a --flag (that is exactly the old '--tier ${tier} <agents> 0' bug
# where <agents> and 0 sat as positionals after --tier's single consumed value).
# Drop the leading path token, then scan.
body="${cmd#*quota-stop.sh}"
# shellcheck disable=SC2206
toks=($body)
expecting_value=0
bad=""
for t in "${toks[@]}"; do
  if [[ "$t" == --* ]]; then
    expecting_value=1          # this flag consumes the next token as its value
  elif [[ "$expecting_value" -eq 1 ]]; then
    expecting_value=0          # this token is the flag's value — fine
  else
    bad="$t"                   # a token that is neither a flag nor a flag's value
    break
  fi
done
[[ -z "$bad" ]] || fail "bare positional argument '$bad' in quota-stop.sh invocation (the old '--tier T <agents> 0' bug; quota-stop.sh rejects it with exit 2): $cmd"
pass "quota-stop.sh invocation has no bare positional args (every value follows a --flag)"

echo "ALL PASS: relay install-manifest + quota-stop invocation contract (id:5f09)"
