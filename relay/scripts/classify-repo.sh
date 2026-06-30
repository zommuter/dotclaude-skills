#!/usr/bin/env bash
# relay/scripts/classify-repo.sh — DP1 assembly wrapper (id:3f0f)
#
# Usage: classify-repo.sh --repo <name> --path <abs>
#
# Assembles the full classify-verdict input for a single repo by:
#   1. Running gather-repo-state.sh --repo --path   → base JSON fields
#   2. Deriving hasRoutine / roadmap_open / roadmap_actionable_open from <path>/ROADMAP.md
#   3. Running unpromoted-scan.sh <path>            → unpromoted {promote, surface} counts
#   4. Merging into one JSON object and piping to classify-verdict.sh → emit its output.
#
# SIDE-EFFECT-FREE: reads state and runs the read-only helpers; never commits, writes a
# ledger, or creates a tag.
#
# Env overrides (hermetic tests; forwarded to sub-helpers):
#   RELAY_TOML           default ~/.config/relay/relay.toml
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GATHER="$SCRIPT_DIR/gather-repo-state.sh"
SCAN="$SCRIPT_DIR/unpromoted-scan.sh"
CLASSIFY="$SCRIPT_DIR/classify-verdict.sh"

repo="" path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    *) echo "classify-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "classify-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "classify-repo.sh: --path is required" >&2; exit 2; }

# Step 1: gather base repo state (inherits RELAY_TOML / RELAY_WORKTREE_BASE from env)
base_json="$("$GATHER" --repo "$repo" --path "$path")"

# Step 2: run unpromoted-scan.sh (read-only; suppress log stderr so hermetic tests stay quiet)
scan_tsv="$("$SCAN" "$path" 2>/dev/null || true)"

# Step 3 + 4: derive ROADMAP fields, fold unpromoted counts, pipe to classifier.
# Pass the (potentially large) gather JSON + scan TSV via TEMP FILES, never env/argv: a single
# env string over MAX_ARG_STRLEN (128KB) breaks execve of python3 AND the classifier (see
# tests/test_classify_repo_large.sh — dotclaude-skills' ~130KB unpromoted-scan TSV). Paths stay tiny.
blobdir="$(mktemp -d)"
trap 'rm -rf "$blobdir"' EXIT
printf '%s' "$base_json" > "$blobdir/base.json"
printf '%s' "$scan_tsv"  > "$blobdir/scan.tsv"
export CLASSIFY_PATH="$path" BASE_FILE="$blobdir/base.json" SCAN_FILE="$blobdir/scan.tsv"
python3 - <<'PYEOF' | "$CLASSIFY"
import json, os, re, sys

HUMAN_GATES = ("[HARD — hands]", "[HARD — meeting]", "[HARD — decision gate]")

path     = os.environ["CLASSIFY_PATH"]
with open(os.environ["BASE_FILE"]) as _f: base_json = _f.read()
with open(os.environ["SCAN_FILE"]) as _f: scan_tsv  = _f.read()

# --- Step 2: derive ROADMAP fields ----------------------------------------
rm = os.path.join(path, "ROADMAP.md")
has_routine = False
roadmap_open = 0
roadmap_actionable_open = 0

if os.path.isfile(rm):
    with open(rm, errors="replace") as f:
        for ln in f:
            if not re.match(r"\s*- \[ \] ", ln):
                continue
            roadmap_open += 1
            is_routine = "[ROUTINE]" in ln
            is_pool    = "[HARD — pool]" in ln
            is_human   = any(h in ln for h in HUMAN_GATES) or "@manual" in ln
            if is_routine:
                has_routine = True
            if (is_routine or is_pool) and not is_human:
                roadmap_actionable_open += 1

# --- Step 3: fold unpromoted-scan TSV counts ------------------------------
promote = 0
surface = 0
for ln in scan_tsv.splitlines():
    cols = ln.split("\t")
    if len(cols) >= 3:
        if cols[2] == "promote":
            promote += 1
        elif cols[2] == "surface":
            surface += 1

# --- Merge into full JSON object ------------------------------------------
base = json.loads(base_json)
base["hasRoutine"]              = has_routine
base["roadmap_open"]            = roadmap_open
base["roadmap_actionable_open"] = roadmap_actionable_open
base["unpromoted"]              = {"promote": promote, "surface": surface}

print(json.dumps(base))
PYEOF
