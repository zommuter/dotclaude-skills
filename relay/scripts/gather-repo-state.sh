#!/usr/bin/env bash
# gather-repo-state.sh (id:11ad) — emit ALL the per-repo state a discover-shard needs to
# classify a repo, in ONE call, as a single JSON object.
#
# WHY: the shard classifier used to run ~17 git/grep commands PER REPO inline, taking ~one
# assistant turn each → a 6-repo shard ran ~120 turns, and each turn re-read the growing
# cached context, so cache_read summed to ~1.9M tokens/shard (~46% of shard cost; the prompt
# itself is only ~0.7%). Measured 2026-06-18 — the cost driver is TURN COUNT, not prompt size
# or context size. This helper collapses the per-repo gathering into ONE Bash call so the
# shard does ~1 turn/repo instead of ~17 → ~10x fewer turns → cache_read drops proportionally.
# It gathers the SAME facts discover-sig.sh hashes (so the classifier sees identical inputs) —
# behavior-preserving; the verdict JUDGMENT stays in the shard prompt (gated by shard-canary).
#
# I/O: gather-repo-state.sh --repo <name> --path <abs> [--runid <id>]
#      emits ONE JSON object on stdout (see fields below). FAIL-OPEN: a non-git path emits
#      {"is_git": false, ...} (exit 0) so the shard surfaces it rather than crashing the round.
#
# Env overrides (hermetic tests; default to the live relay locations):
#   RELAY_TOML           default ~/.config/relay/relay.toml
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
RELAY_WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"

repo="" path="" runid=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  repo="$2"; shift 2 ;;
    --path)  path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    *) echo "gather-repo-state: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" && -n "$path" ]] || { echo "gather-repo-state: --repo and --path are required" >&2; exit 2; }

# [repos.<name>] TOML block (until the next [section] header or EOF). Empty if absent.
toml_block() {
  [[ -f "$RELAY_TOML" ]] || return 0
  awk -v want="[repos.$repo]" '
    $0 == want { inb=1; print; next }
    inb && /^[[:space:]]*\[/ { inb=0 }
    inb { print }
  ' "$RELAY_TOML" 2>/dev/null || true
}

emit() {  # emit the JSON object from env vars (safe encoding of arbitrary multi-line content)
  IS_GIT="$1" HEAD_SHA="${2:-}" LATEST_CKPT="${3:-}" LATEST_CKPT_MSG="${4:-}" \
  COMMITS_SINCE="${5:-}" DIRTY="${6:-false}" PORCELAIN="${7:-}" UPSTREAM="${8:-}" \
  HAS_UPSTREAM="${9:-false}" WORKTREES="${10:-}" ORPHANS="${11:-}" TOML="${12:-}" \
  ROADMAP="${13:-}" LOCK_ONLY_UNAUDITED="${14:-false}" DIRTY_LOCK_ONLY="${15:-false}" \
  IS_FINISHED="${16:-false}" \
  REPO="$repo" RPATH="$path" RUNID="$runid" \
  python3 -c '
import os, json
def b(v): return v == "true"
o = {
  "repo": os.environ["REPO"], "path": os.environ["RPATH"], "runid": os.environ.get("RUNID",""),
  "is_git": b(os.environ["IS_GIT"]),
  "head": os.environ.get("HEAD_SHA",""),
  "latest_ckpt": os.environ.get("LATEST_CKPT",""),
  "latest_ckpt_msg": os.environ.get("LATEST_CKPT_MSG",""),
  "commits_since_ckpt": os.environ.get("COMMITS_SINCE",""),
  "dirty": b(os.environ.get("DIRTY","false")),
  "porcelain": os.environ.get("PORCELAIN",""),
  # id:bae5 — audit/dispatch exemptions for a mechanical uv.lock-only diff (the zkm
  # cascade): lock_only_unaudited = there ARE unaudited commits since the ckpt and
  # they touch ONLY uv.lock (→ not a real review); dirty_lock_only = the working
  # tree is dirty with ONLY uv.lock modified (→ still dispatchable; child relocks).
  "lock_only_unaudited": b(os.environ.get("LOCK_ONLY_UNAUDITED","false")),
  "dirty_lock_only": b(os.environ.get("DIRTY_LOCK_ONLY","false")),
  "upstream_ahead_behind": os.environ.get("UPSTREAM",""),
  "has_upstream": b(os.environ.get("HAS_UPSTREAM","false")),
  "worktrees": os.environ.get("WORKTREES",""),
  "orphan_refs": os.environ.get("ORPHANS",""),
  "toml_block": os.environ.get("TOML",""),
  "roadmap": os.environ.get("ROADMAP",""),
  # id:000d — deterministic finished-repo guard: true iff the roadmap is present/non-empty
  # AND has ZERO open "- [ ]" items AND commits_since_ckpt is empty AND the tree is clean
  # (dirty_lock_only counts as clean — lock-only dirty is still dispatchable, id:bae5).
  # A repo with NO roadmap stays false (genuine first handoff candidate, not a finished repo).
  "is_finished": b(os.environ.get("IS_FINISHED","false")),
}
print(json.dumps(o))
'
}

# FAIL-OPEN: not a git work tree → is_git=false, the shard surfaces it.
if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
  emit false
  exit 0
fi

# Best-effort sync so upstream ahead/behind reflects origin (ignore offline/no-remote errors).
git -C "$path" fetch origin -q 2>/dev/null || true

head_sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
tags="$(git -C "$path" tag -l 'fable-ckpt-*' 'relay-ckpt-*' 2>/dev/null | sort || true)"
latest="$(printf '%s' "$tags" | tail -n1)"
latest_msg=""
[[ -n "$latest" ]] && latest_msg="$(git -C "$path" tag -l --format='%(contents)' "$latest" 2>/dev/null || true)"
# commits the shard audits for the "review" verdict: log since the latest ckpt (or full if none).
if [[ -n "$latest" ]]; then
  commits_since="$(git -C "$path" log "$latest"..HEAD --oneline 2>/dev/null || true)"
else
  commits_since="$(git -C "$path" log --oneline -n 50 2>/dev/null || true)"
fi
porcelain="$(git -C "$path" status --porcelain 2>/dev/null || true)"
[[ -n "$porcelain" ]] && dirty=true || dirty=false

# id:bae5 — uv.lock-only exemptions (the zkm cascade). Conservative: only the
# unambiguous root "uv.lock" path is exempt; any other changed/dirty path defeats it.
# lock_only_unaudited: there ARE unaudited commits since the ckpt AND every file they
# touch is uv.lock (a mechanical cascade relock — audit-exempt, not a real review).
lock_only_unaudited=false
if [[ -n "$latest" && -n "$commits_since" ]]; then
  unaudited_files="$(git -C "$path" diff --name-only "$latest"..HEAD 2>/dev/null || true)"
  unaudited_nonlock="$(printf '%s\n' "$unaudited_files" | grep -v '^[[:space:]]*$' | grep -vx 'uv.lock' || true)"
  [[ -n "$unaudited_files" && -z "$unaudited_nonlock" ]] && lock_only_unaudited=true
fi
# dirty_lock_only: the working tree is dirty with ONLY uv.lock modified (still
# dispatchable — the executor child regenerates+commits it in its worktree).
dirty_lock_only=false
if [[ "$dirty" == true ]]; then
  dirty_nonlock="$(printf '%s\n' "$porcelain" | grep -v '^[[:space:]]*$' | awk '{print $NF}' | grep -vx 'uv.lock' || true)"
  [[ -z "$dirty_nonlock" ]] && dirty_lock_only=true
fi
# upstream ahead/behind (tab-separated "ahead<TAB>behind"); has_upstream=false when none.
if git -C "$path" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  has_upstream=true
  upstream="$(git -C "$path" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
else
  has_upstream=false; upstream=""
fi
worktrees="$(ls -1 "$RELAY_WORKTREE_BASE/$repo" 2>/dev/null | sort || true)"
orphans="$(git -C "$path" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/relay/orphan/ 2>/dev/null || true)"
block="$(toml_block)"
# roadmap: emit OPEN items + structure ONLY (id:93cc) — drop done [x] item-blocks so a large
# ROADMAP's done-item history doesn't bloat the discovery shard's context (id:11ad) or overflow
# a child. The shard classifies from open items + section headers (the EXECUTABLE-HARD test needs
# section context); done prose is dead weight. discover-sig.sh still hashes the FULL ROADMAP — a
# safe SUPERSET (over-hash = a harmless re-classify; never under-invalidates).
# FAIL-OPEN: if the trimmer ever errors, fall back to the FULL ROADMAP (cat) rather than empty
# — an empty roadmap would silently misclassify the repo as handoff (line ~630 "roadmap missing")
# and re-do expensive C1/C2. A bloated-but-correct roadmap beats a silent empty one
# (feedback-mechanize-no-swallow-stderr).
roadmap="$(ROADMAP_PATH="$path/ROADMAP.md" python3 -c '
import os, re, sys
try:
    lines = open(os.environ["ROADMAP_PATH"], encoding="utf-8").read().splitlines(keepends=True)
except OSError:
    sys.exit(0)
item = re.compile(r"^- \[([ xX])\] ")
out, dropped, i, n = [], 0, 0, len(lines)
while i < n:
    m = item.match(lines[i])
    if m:
        blk = [lines[i]]; j = i + 1
        while j < n and not item.match(lines[j]) and not lines[j].startswith("## "):
            blk.append(lines[j]); j += 1
        if m.group(1).lower() == "x":
            dropped += 1
        else:
            out.extend(blk)
        i = j
    else:
        out.append(lines[i]); i += 1
s = "".join(out)
if dropped:
    if s and not s.endswith("\n"): s += "\n"
    s += "<!-- relay-discovery-view: %d done [x] item(s) omitted; full history in ROADMAP.md -->\n" % dropped
sys.stdout.write(s)
' 2>/dev/null || cat "$path/ROADMAP.md" 2>/dev/null || true)"

# id:000d — deterministic is_finished guard: true iff roadmap is present/non-empty AND has
# ZERO open "- [ ]" items AND no unaudited commits AND tree is clean (lock-only dirty exempt).
# A repo with no ROADMAP.md stays false (genuine first handoff, not a finished repo).
is_finished=false
if [[ -f "$path/ROADMAP.md" && -n "$roadmap" ]]; then
  open_items="$(printf '%s\n' "$roadmap" | grep -cP '^- \[ \] ' 2>/dev/null || true)"
  # clean = not dirty, OR lock-only dirty (lock-only dirty is still dispatchable, id:bae5)
  clean_for_finished=false
  [[ "$dirty" == false ]] && clean_for_finished=true
  [[ "$dirty_lock_only" == true ]] && clean_for_finished=true
  if [[ "$open_items" -eq 0 && -z "$commits_since" && "$clean_for_finished" == true ]]; then
    is_finished=true
  fi
fi

emit true "$head_sha" "$latest" "$latest_msg" "$commits_since" "$dirty" "$porcelain" \
     "$upstream" "$has_upstream" "$worktrees" "$orphans" "$block" "$roadmap" \
     "$lock_only_unaudited" "$dirty_lock_only" "$is_finished"
