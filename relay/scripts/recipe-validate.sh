#!/usr/bin/env bash
# recipe-validate.sh — validate ONE relay-authored recipe JSON against the schema
# pinned in `relay/references/recipe-manifest.md` (id:64d3, meeting 2026-07-02-1924
# decision 3, slice A2 of the mechanical-run daemon).
#
# Recipes are WHITELISTED / relay-authored ONLY — this validator is the gate a
# malformed recipe must clear before the (gated, not-yet-built) daemon in A3 ever
# reads it. It NEVER scans ROADMAP.md or any other source to invent recipes; it only
# validates a JSON file handed to it explicitly. See recipe-manifest.md for the full
# drop-dir lifecycle and the "never auto-scanned" invariant.
#
# Schema: {id, repo, cmd, host, est_wall, resource, acceptance_artifact}
#   - id / repo / cmd / host / resource / acceptance_artifact: non-empty strings.
#   - est_wall: a positive integer (seconds). No floats, no zero, no negative.
#
# Usage:
#   recipe-validate.sh <recipe.json>
#     exit 0, silent, on a well-formed recipe.
#     exit 1 with a LOUD `ERROR: <field> ...` line on stderr naming the FIRST
#     offending field, on any missing key, wrong type, or non-positive est_wall.
#     No silent coercion — a malformed recipe is always rejected loudly.
#
# The recipe drop-dir itself defaults to ~/.config/relay/recipes (RELAY_RECIPE_DIR
# override, id:64d3 acceptance 3) — this script does not touch the drop-dir; it only
# validates a single file path given on argv. (The pending→running→done move is the
# daemon's job, not built here — see recipe-manifest.md.)
set -euo pipefail

usage() { sed -n '2,29p' "$0"; }

path="${1:-}"
case "$path" in
  ""|-h|--help|help) usage; exit 0 ;;
esac

if [ ! -f "$path" ]; then
  echo "ERROR: recipe file not found: $path" >&2
  exit 1
fi

# python3 stdlib json — never fragile string munging (repo gotcha). Prints the
# FIRST offending field name (or nothing) on stdout; recipe-validate.sh turns that
# into the loud ERROR: line so all failure paths share one message shape.
bad_field="$(python3 - "$path" <<'PY'
import json, sys

path = sys.argv[1]

str_fields = ["id", "repo", "cmd", "host", "resource", "acceptance_artifact"]

try:
    with open(path) as fh:
        data = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    print(f"<file>:not valid JSON ({exc})")
    sys.exit(0)

if not isinstance(data, dict):
    print("<file>:recipe JSON must be an object")
    sys.exit(0)

for f in str_fields:
    if f not in data:
        print(f"{f}:missing")
        sys.exit(0)
    if not isinstance(data[f], str) or data[f] == "":
        print(f"{f}:must be a non-empty string")
        sys.exit(0)

if "est_wall" not in data:
    print("est_wall:missing")
    sys.exit(0)

est_wall = data["est_wall"]
# bool is a subclass of int in Python — explicitly reject it too.
if isinstance(est_wall, bool) or not isinstance(est_wall, int):
    print("est_wall:must be a positive integer (seconds)")
    sys.exit(0)
if est_wall <= 0:
    print("est_wall:must be a positive integer (seconds)")
    sys.exit(0)

# well-formed
print("")
PY
)"

if [ -n "$bad_field" ]; then
  field="${bad_field%%:*}"
  reason="${bad_field#*:}"
  echo "ERROR: $field $reason ($path)" >&2
  exit 1
fi

# Advisory (non-fatal) explicit-success-marker check (id:fd37). A [MECHANICAL] recipe's
# `cmd` that redirects into its own acceptance_artifact but never appends an explicit
# terminal marker leaves an EMPTY artifact on a silent-on-clean tool (e.g. `tsc`) —
# indistinguishable from "never ran". This is advisory ONLY: it never fails the schema
# check above, it only warns on stderr so a relay reviewer can fix the recipe before it
# reaches the daemon. Deliberately conservative — we can't parse arbitrary shell, so we
# only warn when the cmd both (1) redirects into the acceptance_artifact and (2) carries
# no exit-preserving marker token (`exit=...` / `exit $?`); see recipe-manifest.md for the
# canonical safe pattern this check is nudging recipes toward.
marker_warning="$(python3 - "$path" <<'PY'
import json, re, sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)

cmd = data.get("cmd", "")
artifact = data.get("acceptance_artifact", "")

redirects_to_artifact = bool(artifact) and artifact in cmd and ">" in cmd
has_marker = bool(re.search(r'exit=\$?\{?\w*\}?|exit\s+\$\?', cmd))

if redirects_to_artifact and not has_marker:
    print("WARNING: cmd redirects into acceptance_artifact but has no explicit "
          "exit-preserving marker (e.g. 'exit=$rc') — a silent-on-clean tool "
          "would leave an ambiguous EMPTY artifact; see recipe-manifest.md")
PY
)"

if [ -n "$marker_warning" ]; then
  echo "$marker_warning" >&2
fi

exit 0
