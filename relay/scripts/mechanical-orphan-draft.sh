#!/usr/bin/env bash
# mechanical-orphan-draft.sh (id:8a6b clause a) — the RESOLUTION half of the mechanical-orphan
# loop. relay-doctor check-12 (id:1bd1) only DETECTS orphans; this auto-DRAFTS a recipe skeleton
# for each so the orphan stops silently rotting (the loud-detection/silent-no-op anti-pattern).
#
# For every `orphan` reported by mechanical-orphan-scan.sh (an open [MECHANICAL] ROADMAP item
# with no recipe in pending/running/done and no existing draft), write a recipe SKELETON to
#   $RELAY_RECIPE_DIR/drafts/<id>.json
# with `id` + `repo` prefilled, `host` from the item's `[host:<name>]` tag, `resource` from its
# `[INTENSIVE — <res>]` tag, and `cmd` / `est_wall` / `acceptance_artifact` left as explicit
# `TODO:` placeholders for an Opus reviewer / human to fill in.
#
# THE WHITELIST TRUST BOUNDARY IS PRESERVED (recipe-manifest.md):
#   • A draft is written to drafts/, which the mechanical-daemon NEVER consumes — it reads ONLY
#     pending/. So auto-drafting can never cause auto-execution: an Opus/human must deliberately
#     fill the TODO placeholders and MOVE drafts/<id>.json → pending/ to make it runnable.
#   • The est_wall placeholder is a STRING ("TODO: …"), so even a curious hand that copied a
#     draft into pending/ verbatim would be hard-rejected by recipe-validate.sh (est_wall must
#     be a positive integer) — the draft is doubly non-executable.
#
# IDEMPOTENT: never overwrites an existing draft, and never drafts an id that already has a real
# recipe in pending/running/done (the scanner already excludes those). Re-running is a no-op once
# every orphan has a draft.
#
# Usage: mechanical-orphan-draft.sh [name=path ...]
#   No args → scan all relay.toml own repos. name=path pairs → scan exactly those (hermetic tests).
#
# Env overrides (mirror mechanical-orphan-scan.sh):
#   RELAY_RECIPE_DIR  recipe root, default ~/.config/relay/recipes
#   RELAY_TOML        relay.toml path, default ~/.config/relay/relay.toml
#   SRC_DIR           default repo parent, default ~/src
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$ROOT/mechanical-orphan-scan.sh"
RELAY_RECIPE_DIR="${RELAY_RECIPE_DIR:-$HOME/.config/relay/recipes}"
DRAFTS="$RELAY_RECIPE_DIR/drafts"

mkdir -p "$DRAFTS"

drafted=0 skipped=0
while IFS=$'\t' read -r kind id repo host resource detail; do
  [[ "$kind" == "orphan" ]] || continue
  [[ -n "$id" ]] || continue
  # Scanner emits "-" for an absent host/resource (empty TSV fields collapse under read); map back.
  [[ "$host" == "-" ]] && host=""
  [[ "$resource" == "-" ]] && resource=""
  target="$DRAFTS/$id.json"
  if [[ -e "$target" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  # Build the skeleton with python3/json (never fragile string munging — CLAUDE.md JSON gotcha).
  ID="$id" REPO="$repo" HOST="$host" RESOURCE="$resource" python3 - "$target" <<'PY'
import json, os, sys
target = sys.argv[1]
skeleton = {
    "id":   os.environ["ID"],
    "repo": os.environ["REPO"],
    "host": os.environ["HOST"] or "TODO: host (from the item's [host:<name>] tag)",
    "resource": os.environ["RESOURCE"] or "TODO: resource (from the item's [INTENSIVE — <res>] tag)",
    "cmd":  "TODO: author the command — use the exit=$rc marker pattern in recipe-manifest.md",
    "est_wall": "TODO: positive integer seconds (this string placeholder keeps the draft non-executable)",
    "acceptance_artifact": "TODO: path/pointer to the artifact proving completion",
    "_draft": "AUTO-DRAFTED by mechanical-orphan-draft.sh (id:8a6b). NOT executable: the daemon consumes pending/ only. Fill the TODO fields, then move this file drafts/ -> pending/ to launch.",
}
with open(target, "w", encoding="utf-8") as f:
    json.dump(skeleton, f, indent=2)
    f.write("\n")
PY
  echo "drafted: $id ($repo) → $target"
  drafted=$((drafted + 1))
done < <("$SCAN" "$@")

echo "mechanical-orphan-draft: drafted=$drafted skipped=$skipped (existing)"
