#!/usr/bin/env bash
# roadmap:64d3 — recipe manifest schema + drop-dir contract + recipe-validate.sh
# (slice A, meeting 2026-07-02-1924 decision 3).
#
# The mechanical-run daemon (A3, gated) consumes RELAY-AUTHORED recipes from a drop-dir.
# This RED spec pins the schema/lifecycle contract + a LOUD validator (never a silent
# coercion), never the daemon:
#   - recipe JSON {id,repo,cmd,host,est_wall,resource,acceptance_artifact}; est_wall a
#     positive-integer seconds, the rest strings.
#   - recipe-validate.sh: exit 0 silent on a well-formed recipe; exit NONZERO + LOUD
#     `ERROR:` naming the FIRST offending field on any missing/wrong-typed field or a
#     non-positive est_wall.
#   - a reference doc naming the {pending,running,done}/ drop-dir + all 7 fields +
#     "whitelisted" / "never auto-scanned".
#   - Makefile registration (script 3x, doc 1x; id:69ef install-completeness).
#
# Hermetic: temp recipe files; no ~/.config, no daemon, no network.
# RED until recipe-validate.sh + recipe-manifest.md + Makefile entries land.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/recipe-validate.sh"
DOC="$ROOT/relay/references/recipe-manifest.md"
MK="$ROOT/Makefile"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "recipe-validate.sh not found/executable at $SH (RED)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A well-formed recipe carrying all 7 fields.
write_valid() {
  cat >"$1" <<'JSON'
{
  "id": "7616",
  "repo": "ai-codebench",
  "cmd": "make bench-drain",
  "host": "zomni",
  "est_wall": 3600,
  "resource": "local-llm",
  "acceptance_artifact": "results/latest.json"
}
JSON
}

# --- (1) a complete valid recipe passes silently, exit 0 ---------------------
good="$tmp/good.json"; write_valid "$good"
"$SH" "$good" >/dev/null 2>&1 || fail "(1) a well-formed recipe must pass (exit 0)"
pass "(1) recipe-validate accepts a well-formed recipe"

# --- (2) each of the 7 fields removed in turn → nonzero + ERROR naming it -----
for f in id repo cmd host est_wall resource acceptance_artifact; do
  miss="$tmp/miss_$f.json"
  write_valid "$miss"
  python3 - "$miss" "$f" <<'PY'
import json, sys
p, f = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.pop(f, None)
json.dump(d, open(p, "w"))
PY
  if err="$("$SH" "$miss" 2>&1)"; then
    fail "(2) a recipe MISSING '$f' must be rejected (nonzero)"
  fi
  grep -qiE "ERROR.*\b$f\b" <<<"$err" \
    || fail "(2) rejection for missing '$f' must LOUDLY name the field (got: $err)"
done
pass "(2) each missing field is a LOUD nonzero rejection naming the field"

# --- (3) non-integer / zero / negative est_wall → nonzero --------------------
for badval in '"soon"' '0' '-5' '3.5'; do
  bw="$tmp/estwall.json"
  write_valid "$bw"
  python3 - "$bw" "$badval" <<'PY'
import json, sys
p = sys.argv[1]
raw = sys.argv[2]
d = json.load(open(p))
d["est_wall"] = json.loads(raw)
json.dump(d, open(p, "w"))
PY
  if "$SH" "$bw" >/dev/null 2>&1; then
    fail "(3) est_wall=$badval must be rejected (positive integer seconds only)"
  fi
done
pass "(3) a non-positive / non-integer est_wall is rejected"

# --- (4) the reference doc names the drop-dir + all 7 fields + whitelist rule --
[[ -f "$DOC" ]] || fail "(4) reference doc missing at $DOC"
grep -qF 'recipes/pending' "$DOC" || fail "(4) doc must name the pending/ drop-dir"
grep -qF 'running'         "$DOC" || fail "(4) doc must name the running/ lifecycle dir"
grep -qF 'done'            "$DOC" || fail "(4) doc must name the done/ lifecycle dir"
for f in id repo cmd host est_wall resource acceptance_artifact; do
  grep -qF "$f" "$DOC" || fail "(4) doc must document the '$f' field"
done
grep -qi 'whitelist'  "$DOC" || fail "(4) doc must state recipes are whitelisted/relay-authored"
grep -qi 'auto-scan'  "$DOC" || fail "(4) doc must state recipes are never auto-scanned from ROADMAP"
pass "(4) recipe-manifest.md documents the drop-dir, schema, and whitelist rule"

# --- (5) Makefile registration (id:69ef install-completeness) ----------------
n="$(grep -c 'scripts/recipe-validate.sh' "$MK" || true)"
[[ "$n" -ge 3 ]] || fail "(5) Makefile must register recipe-validate.sh in FILES/EXEC/ALLOW (3x); got $n"
grep -qF 'references/recipe-manifest.md' "$MK" \
  || fail "(5) Makefile must register references/recipe-manifest.md in relay_FILES"
pass "(5) Makefile registers recipe-validate.sh (3x) and recipe-manifest.md"

echo "ALL PASS: recipe manifest schema + validator (id:64d3)"
