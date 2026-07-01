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

repo="" path="" emit_mode=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --emit) emit_mode="$2"; shift 2 ;;
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
python3 - <<'PYEOF' > "$blobdir/assembled.json"
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

"$CLASSIFY" < "$blobdir/assembled.json" > "$blobdir/verdict.json"

if [[ "$emit_mode" != "unit" ]]; then
  # Default mode: byte-unchanged classify-verdict output (regression guard).
  cat "$blobdir/verdict.json"
  exit 0
fi

# --emit unit: build the FULL DISCOVER_SCHEMA unit (id:3d61) by merging the gather
# passthrough fields (base) + deterministic derivations from toml_block/latest_ckpt_msg +
# classify-verdict's verdict/reason/intensive. SIDE-EFFECT-FREE: reads only.
REPO_ARG="$repo" PATH_ARG="$path" \
python3 - "$blobdir/assembled.json" "$blobdir/verdict.json" <<'PYEOF'
import json, os, re, sys

with open(sys.argv[1]) as f:
    base = json.load(f)
with open(sys.argv[2]) as f:
    v = json.load(f)

toml_block = base.get("toml_block", "") or ""
ckpt_msg   = base.get("latest_ckpt_msg", "") or ""

income = bool(re.search(r'(?m)^\s*income\s*=\s*true\s*$', toml_block))
standin = "fable-standin" in ckpt_msg

m = re.search(r'(?m)^\s*last_strong_ckpt\s*=\s*"([^"]*)"\s*$', toml_block)
last_strong_ckpt = m.group(1) if m else ""
fr = re.search(r'(?m)^\s*fable_rechecked\s*=\s*(\S+)\s*$', toml_block)
fable_rechecked_val = fr.group(1).strip('"') if fr else ""
fable_rechecked = fable_rechecked_val not in ("", "false", "False")
strong_recheck_pending = bool(last_strong_ckpt) and not fable_rechecked

open_hard_pool = base.get("open_hard_pool", 0) or 0

unit = {
    "repo": os.environ["REPO_ARG"],
    "path": os.environ["PATH_ARG"],
    "verdict": v.get("verdict", ""),
    "reason": v.get("reason", ""),
    "intensive": v.get("intensive", ""),
    "lastCkpt": base.get("latest_ckpt", "") or "",
    "income": income,
    "hasRoutine": bool(base.get("hasRoutine", False)),
    "openHard": open_hard_pool,
    "standin": standin,
    "is_finished": bool(base.get("is_finished", False)),
    "top_intensive": base.get("top_intensive", "") or "",
    "substantive_unaudited": bool(base.get("substantive_unaudited", True)),
    "work_sig": base.get("work_sig", "") or "",
    "open_hard_pool": open_hard_pool,
    "strongRecheckPending": strong_recheck_pending,
}
print(json.dumps(unit))
PYEOF
