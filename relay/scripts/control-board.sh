#!/usr/bin/env bash
# relay/scripts/control-board.sh — the tracker pilot's CONTROL-ARM board (TODO id:8066).
#
# Usage: control-board.sh [--json] [--repo <name>]
#
# WHAT IT IS: a read-only, fleet-level board DERIVED from existing `classify-repo.sh`
# output. It is the pre-registered COMPARATOR for the 4-week tracker pilot
# (docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md,
# "Pre-registered fail condition"): without it the measurement is tracker-vs-nothing and
# reports the value of *a* dashboard rather than of *this substrate*. It therefore has to
# answer the same fleet-level questions a Plane/Vikunja board would — per-repo verdict,
# open-item counts, and what is waiting on a human — at a fraction of the cost.
#
# WHAT IT IS NOT (the id:8066 reconcile, recorded here so it is not re-litigated):
#   * NOT a second classifier. Every verdict is `classify-repo.sh --emit unit` VERBATIM;
#     the display label comes from `render-verdict.sh`, the only sanctioned emitter of the
#     word "drained" (idle → drained, design 2026-07-19-1152 D1). Nothing is re-derived.
#   * NOT `id:36f1` (the web/graph DAG visual). That renders the ITEM-level blocking DAG
#     over `~/.cache/project_manager/edges.json`, produced by `id:dc60`, and lives with
#     project_manager. This board is REPO-level, over relay classify output, and shares no
#     data source with it. Both obey the same "ONE canonical producer, N renders" steer.
#   * NOT `id:51d8` (the LLM-free human-action dashboard). That is an item-level,
#     interactive artifact over `gather-human-backlog.sh`'s tiers with precomputed steps
#     and a confirm-gated "run now" launcher. This board deliberately does NOT re-derive
#     the human backlog: its "waiting on a human" section is only the per-REPO
#     classify verdict (`human` / `blocked`). When id:51d8 is built it can consume
#     `--json` for its repo-level roll-up instead of shelling out per repo again.
#   * NOT a write path. It writes NO file, no ledger, no tracker (the pilot's ratified rule
#     is "no relay script writes to the tracker"). The board is stdout-only, so there is no
#     artifact that can go stale and nothing to review for write safety.
#   * NOT LLM-dependent: no `claude -p`, no agent(), no network. It renders offline.
#
# REPO SET: the `relay.toml` own-set is THE authority, via the SHARED own_repos() parser in
# lib-own-repos.sh (honours `classification = "own"`, the `# path:` COMMENT override, the
# `paused` flag, and $SRC_DIR-relative defaults). NEVER a `~/src/*` glob (id:7633). Its exit
# status is checked EXPLICITLY — a corrupt relay.toml aborts loudly and renders NOTHING,
# rather than silently rendering an empty board (id:0fa0 finding (a)).
#
# LOUD, NEVER SILENT (id:4347): a repo whose path is missing/not a git repo, or whose
# classify-repo.sh call fails or emits non-JSON, becomes a `producer-error` row in the board
# AND a stderr line — it is never dropped, and it never aborts the board for the other repos
# (the discover-repos-mechanical.sh id:0fa0 finding (b) precedent).
#
# BOARD COLUMNS — a pure DISPLAY grouping over the classifier's verdict enum. The raw
# verdict is ALWAYS carried alongside, so the grouping collapses nothing:
#   blocked         ← blocked                                (dirty/diverged main tree)
#   relay-poolable  ← execute, hard, review, handoff, mechanical
#                     (machine-actionable; note `mechanical` is dispatched by the host
#                      daemon, not the LLM pool — id:7616 — but needs no human either)
#   needs-feedback  ← human                                  (surface-only, no apex dispatch)
#   design-drained  ← idle                                   (rendered via render-verdict.sh)
#   unclassified    ← AMBIGUOUS, producer-error, unknown
#
# SIDE-EFFECT-FREE: reads state, prints to stdout. No git writes, no commits, no tags, no
# ledger writes, no file creation. Ships a purity test (tests/test_control_board.sh) built on
# tests/lib/assert-repo-unchanged.sh, per the executor contract's purity-test-as-contract rule.
# (Inherited declared exception, id:82c4: if a relay-core shadow binary is installed,
# classify-repo.sh appends one line to the shadow-parity log — an observability write outside
# every repo. This script adds no write of its own.)
#
# Env overrides (all forwarded to classify-repo.sh unchanged):
#   RELAY_TOML           default ~/.config/relay/relay.toml
#   SRC_DIR              default ~/src
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
#   RELAY_CORE_BIN       set to a non-executable path to disable the shadow (hermetic tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY_REPO="$SCRIPT_DIR/classify-repo.sh"
RENDER_VERDICT="$SCRIPT_DIR/render-verdict.sh"
LIB_OWN_REPOS="$SCRIPT_DIR/lib-own-repos.sh"

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
export RELAY_TOML SRC_DIR

emit_json=0
only_repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) emit_json=1; shift ;;
    --repo) only_repo="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "control-board.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

for f in "$CLASSIFY_REPO" "$RENDER_VERDICT" "$LIB_OWN_REPOS"; do
  [[ -f "$f" ]] || { echo "control-board.sh: missing dependency: $f" >&2; exit 2; }
done

# shellcheck source=lib-own-repos.sh
source "$LIB_OWN_REPOS"

# --- enumerate the own-set, checking own_repos()'s exit status EXPLICITLY (id:0fa0 (a)) ---
own_file="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"; rm -- "$own_file"' EXIT
rc=0
own_repos > "$own_file" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "control-board.sh: FAILED to parse relay.toml ($RELAY_TOML), rc=$rc — own-repo enumeration aborted; NO board rendered." >&2
  exit 3
fi

rows="$tmpdir/rows.jsonl"
: > "$rows"

emit_error_row() {
  # $1=repo $2=path $3=reason
  REPO="$1" RPATH="$2" REASON="$3" python3 -c '
import json, os
print(json.dumps({
    "repo": os.environ["REPO"], "path": os.environ["RPATH"],
    "verdict": "", "reason": os.environ["REASON"],
    "actionable_routine_open": 0, "open_hard_pool": 0, "open_mechanical": 0,
    "producer_error": True,
}))' >> "$rows"
  echo "control-board.sh: producer-error [$1]: $3" >&2
}

while IFS=$'\t' read -r name path; do
  [[ -n "$name" ]] || continue
  [[ -z "$only_repo" || "$name" == "$only_repo" ]] || continue
  if [[ ! -d "$path" ]]; then
    emit_error_row "$name" "$path" "path does not exist: $path"
    continue
  fi
  if [[ ! -e "$path/.git" ]]; then
    emit_error_row "$name" "$path" "not a git repository: $path"
    continue
  fi
  unit=""
  crc=0
  unit="$("$CLASSIFY_REPO" --repo "$name" --path "$path" --emit unit 2>"$tmpdir/err")" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    emit_error_row "$name" "$path" "classify-repo.sh exited $crc: $(tail -n 1 "$tmpdir/err" 2>/dev/null || true)"
    continue
  fi
  if ! printf '%s' "$unit" | python3 -c 'import sys, json; json.load(sys.stdin)' 2>/dev/null; then
    emit_error_row "$name" "$path" "classify-repo.sh emitted empty/non-JSON output"
    continue
  fi
  # Display label comes from render-verdict.sh — the ONLY sanctioned "drained" emitter.
  label="$(printf '%s' "$unit" | "$RENDER_VERDICT")"
  printf '%s' "$unit" | LABEL="$label" python3 -c '
import json, os, sys
u = json.load(sys.stdin)
u["label"] = os.environ["LABEL"]
u["producer_error"] = False
print(json.dumps(u))' >> "$rows"
done < "$own_file"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ROWS_FILE="$rows" EMIT_JSON="$emit_json" GENERATED_AT="$GENERATED_AT" \
RELAY_TOML="$RELAY_TOML" python3 <<'PYEOF'
import json, os

COLUMN_OF = {
    "blocked":    "blocked",
    "execute":    "relay-poolable",
    "hard":       "relay-poolable",
    "review":     "relay-poolable",
    "handoff":    "relay-poolable",
    "mechanical": "relay-poolable",
    "human":      "needs-feedback",
    "idle":       "design-drained",
}
ORDER = ["blocked", "relay-poolable", "needs-feedback", "design-drained", "unclassified"]

rows = []
with open(os.environ["ROWS_FILE"]) as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

for r in rows:
    if r.get("producer_error"):
        r["column"] = "unclassified"
        r["label"] = "producer-error"
    else:
        r["column"] = COLUMN_OF.get(r.get("verdict", ""), "unclassified")

summary = {c: 0 for c in ORDER}
for r in rows:
    summary[r["column"]] += 1

if os.environ["EMIT_JSON"] == "1":
    print(json.dumps({
        "schema_version": 1,
        "generated_at": os.environ["GENERATED_AT"],
        "relay_toml": os.environ["RELAY_TOML"],
        "summary": summary,
        "repos": [{
            "repo": r.get("repo", ""),
            "path": r.get("path", ""),
            "column": r["column"],
            "verdict": r.get("verdict", ""),
            "label": r.get("label", ""),
            "reason": r.get("reason", ""),
            "actionable_routine_open": r.get("actionable_routine_open", 0),
            "open_hard_pool": r.get("open_hard_pool", 0),
            "open_mechanical": r.get("open_mechanical", 0),
            "producer_error": bool(r.get("producer_error")),
        } for r in rows],
    }, indent=2))
    raise SystemExit(0)

out = []
out.append("# Relay control-arm board — %s" % os.environ["GENERATED_AT"])
out.append("")
out.append("Derived read-only from `classify-repo.sh` over the `relay.toml` own-set "
           "(`%s`), %d repo(s). No file written; no LLM used." % (os.environ["RELAY_TOML"], len(rows)))
out.append("")
out.append("## Fleet summary")
out.append("")
out.append("| column | repos |")
out.append("|---|---:|")
for c in ORDER:
    out.append("| %s | %d |" % (c, summary[c]))
out.append("")
out.append("## Repos")
out.append("")
out.append("| repo | column | verdict/label | routine-open | hard-open | mech-open |")
out.append("|---|---|---|---:|---:|---:|")
for r in sorted(rows, key=lambda r: (ORDER.index(r["column"]), r.get("repo", ""))):
    out.append("| %s | %s | %s | %d | %d | %d |" % (
        r.get("repo", ""), r["column"], r.get("label", "") or "(none)",
        int(r.get("actionable_routine_open", 0) or 0),
        int(r.get("open_hard_pool", 0) or 0),
        int(r.get("open_mechanical", 0) or 0)))
out.append("")
out.append("## Waiting on a human")
out.append("")
waiting = [r for r in rows if r["column"] in ("needs-feedback", "blocked")]
if not waiting:
    out.append("_(none)_")
else:
    for r in sorted(waiting, key=lambda r: r.get("repo", "")):
        out.append("- **%s** — %s — %s" % (r.get("repo", ""), r.get("label", ""), r.get("reason", "")))
out.append("")
errs = [r for r in rows if r.get("producer_error")]
out.append("## Producer errors")
out.append("")
if not errs:
    out.append("_(none)_")
else:
    for r in sorted(errs, key=lambda r: r.get("repo", "")):
        out.append("- **%s** — %s" % (r.get("repo", ""), r.get("reason", "")))
print("\n".join(out))
PYEOF
