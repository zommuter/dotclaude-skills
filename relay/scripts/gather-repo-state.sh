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

emit() {  # emit the JSON object via temp files (avoids execve overflow on large blobs, id:07be)
  # Pass field VALUES to python via a temp directory — NOT via env vars or argv. A single env
  # string over MAX_ARG_STRLEN (128KB) breaks execve with "Argument list too long" on a repo
  # with a large ROADMAP (same class as the id:3f0f fix in classify-repo.sh). Pattern: write
  # each value with printf '%s' into its own file; pass only the tmpdir path to python.
  _blobdir="$(mktemp -d)"
  # Expand $_blobdir NOW (at definition time) so the trap fires correctly when the shell
  # exits after the function has returned and the local scope is gone (set -u safe).
  # shellcheck disable=SC2064
  trap "rm -rf '$_blobdir'" EXIT
  printf '%s' "${1}"      > "$_blobdir/IS_GIT"
  printf '%s' "${2:-}"    > "$_blobdir/HEAD_SHA"
  printf '%s' "${3:-}"    > "$_blobdir/LATEST_CKPT"
  printf '%s' "${4:-}"    > "$_blobdir/LATEST_CKPT_MSG"
  printf '%s' "${5:-}"    > "$_blobdir/COMMITS_SINCE"
  printf '%s' "${6:-false}" > "$_blobdir/DIRTY"
  printf '%s' "${7:-}"    > "$_blobdir/PORCELAIN"
  printf '%s' "${8:-}"    > "$_blobdir/UPSTREAM"
  printf '%s' "${9:-false}" > "$_blobdir/HAS_UPSTREAM"
  printf '%s' "${10:-}"   > "$_blobdir/WORKTREES"
  printf '%s' "${11:-}"   > "$_blobdir/ORPHANS"
  printf '%s' "${12:-}"   > "$_blobdir/TOML"
  printf '%s' "${13:-}"   > "$_blobdir/ROADMAP"
  printf '%s' "${14:-false}" > "$_blobdir/LOCK_ONLY_UNAUDITED"
  printf '%s' "${15:-false}" > "$_blobdir/DIRTY_LOCK_ONLY"
  printf '%s' "${16:-false}" > "$_blobdir/IS_FINISHED"
  printf '%s' "${17:-}"   > "$_blobdir/TOP_INTENSIVE"
  printf '%s' "${18:-true}" > "$_blobdir/SUBSTANTIVE_UNAUDITED"
  printf '%s' "${19:-}"   > "$_blobdir/WORK_SIG"
  printf '%s' "${20:-0}"  > "$_blobdir/OPEN_HARD_POOL"
  EMIT_DIR="$_blobdir" REPO="$repo" RPATH="$path" RUNID="$runid" \
  python3 -c '
import os, json
d = os.environ["EMIT_DIR"]
def r(k):
    try:
        with open(d + "/" + k) as f: return f.read()
    except OSError:
        return ""
def b(v): return v == "true"
o = {
  "repo": os.environ["REPO"], "path": os.environ["RPATH"], "runid": os.environ.get("RUNID",""),
  "is_git": b(r("IS_GIT")),
  "head": r("HEAD_SHA"),
  "latest_ckpt": r("LATEST_CKPT"),
  "latest_ckpt_msg": r("LATEST_CKPT_MSG"),
  "commits_since_ckpt": r("COMMITS_SINCE"),
  "dirty": b(r("DIRTY")),
  "porcelain": r("PORCELAIN"),
  # id:bae5 — audit/dispatch exemptions for a mechanical uv.lock-only diff (the zkm
  # cascade): lock_only_unaudited = there ARE unaudited commits since the ckpt and
  # they touch ONLY uv.lock (→ not a real review); dirty_lock_only = the working
  # tree is dirty with ONLY uv.lock modified (→ still dispatchable; child relocks).
  "lock_only_unaudited": b(r("LOCK_ONLY_UNAUDITED")),
  "dirty_lock_only": b(r("DIRTY_LOCK_ONLY")),
  "upstream_ahead_behind": r("UPSTREAM"),
  "has_upstream": b(r("HAS_UPSTREAM")),
  "worktrees": r("WORKTREES"),
  "orphan_refs": r("ORPHANS"),
  "toml_block": r("TOML"),
  "roadmap": r("ROADMAP"),
  # id:000d — deterministic finished-repo guard: true iff the roadmap is present/non-empty
  # AND has ZERO open "- [ ]" items AND commits_since_ckpt is empty AND the tree is clean
  # (dirty_lock_only counts as clean — lock-only dirty is still dispatchable, id:bae5).
  # A repo with NO roadmap stays false (genuine first handoff candidate, not a finished repo).
  "is_finished": b(r("IS_FINISHED")),
  # id:ad74 — deterministic intensive-item field: the resource name of the top open
  # "- [ ]" item carrying an "[INTENSIVE — <resource>]" modifier, "" when none.
  # The JS-side INTENSIVE promote backstop uses this to self-correct a shard that
  # classifies a repo idle/skipped despite having an open [INTENSIVE] item.
  "top_intensive": r("TOP_INTENSIVE"),
  # id:365b — relay anti-spin primitive. substantive_unaudited (FAIL-OPEN default true):
  # false iff every commit since the audit ref (relay.toml last_strong_ckpt, else the latest
  # ckpt tag) is a `relay:/fable: checkpoint` commit or touches ONLY uv.lock — i.e. there is
  # NOTHING NEW for the recurring strong-model audit (id:401c) to review. Stays true when the
  # ref cannot be resolved (never wrongly skip a real audit). The shard recurring-audit gate
  # (mechanism 1) reads it to demote a marked recurring audit with nothing to audit.
  "substantive_unaudited": b(r("SUBSTANTIVE_UNAUDITED")),
  # work_sig: a signature STABLE across the pool OWN `relay: checkpoint` churn but changing
  # when an open item closes or a substantive commit lands. The JS-side re-dispatch circuit
  # breaker (mechanism 2) keys on it: a (repo,verdict) re-dispatched with an unchanged work_sig
  # has no new work → suppress after >3×. "" when uncomputable (the breaker treats "" as a
  # fresh signature each round = fail-open, never falsely suppresses real work).
  "work_sig": r("WORK_SIG"),
  # id:9973 — deterministic demote-guard input: the count of OPEN "- [ ]" ROADMAP items
  # whose lane tag is EXACTLY "[HARD — pool]" (the ONLY pool-dispatchable HARD lane per
  # relay/references/hard-lanes.md — [HARD — meeting]/[HARD — decision gate]/[HARD — hands]
  # are NOT). A recurring-audit-marked [HARD — pool] item with nothing new to audit
  # (substantive_unaudited == false, reusing the id:365b logic) does NOT count — it is not
  # an executable pool item this round. The JS-side demote-guard (id:9973) reads this: a
  # `hard` verdict on a repo with open_hard_pool == 0 is demoted to surfaced, since the
  # LLM shard `hard` judgment is non-deterministic and has wrongly dispatched repos whose
  # only open HARD item was [HARD — decision gate] (observed 2026-06-24).
  "open_hard_pool": int(r("OPEN_HARD_POOL") or 0),
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

# id:ad74 — deterministic top_intensive field: resource of the top open "- [ ]" item
# carrying an "[INTENSIVE — <resource>]" modifier, "" when none.
# The JS-side INTENSIVE promote backstop reads this to correct a shard that idles a repo
# despite having an open [INTENSIVE] item (the symmetric PROMOTE counterpart to id:000d).
#
# id:a707 — but [INTENSIVE] is an ORTHOGONAL resource axis (id:78ff): an item can be
# [ROUTINE]/[HARD — pool] (executor-actionable, just resource-heavy → auto-dispatch serially
# under --afk) OR human-gated ([HARD — hands]/[HARD — meeting]/[HARD — decision gate]/@manual)
# AND resource-heavy. A human-gated [INTENSIVE] item is HUMAN work that merely happens to load
# a model — it must NOT be auto-dispatched even under --afk/--allow-intensive (observed
# 2026-06-23: a zomni [HARD — hands] [INTENSIVE — local-llm] item was dispatched and could not
# complete — needs live GPU/sudo). So top_intensive is the resource of the top open [INTENSIVE]
# item that is NOT human-gated; human-gated intensive items stay "" here and surface for the
# human via the normal gated-HARD / @manual path. FAIL-SAFE: when unsure (no lane tag), the item
# is NOT treated as human-gated (it still emits — under-suppression beats wrongly hiding work).
top_intensive=""
if [[ -n "$roadmap" ]]; then
  top_intensive="$(printf '%s\n' "$roadmap" \
    | grep -P '^- \[ \].*\[INTENSIVE — ' 2>/dev/null \
    | grep -vP '\[HARD — (hands|meeting|decision gate)\]|@manual|\[MECHANICAL\]|🚧|BLOCKED on|blocked on' \
    | grep -m1 -oP '\[INTENSIVE — \K[^\]]+' 2>/dev/null || true)"
fi

# id:365b — relay anti-spin primitive (shared by both mechanisms). The recurring strong-model
# audit (id:401c) never closes by design; once a repo drains all other work it re-fires every
# round and audits only its OWN previous `relay: checkpoint` commit ("clean by vacuity"),
# burning the apex tier for zero output. Compute against the AUDIT WINDOW REF:
# relay.toml's last_strong_ckpt for this repo (the strong-audit watermark), falling back to
# the latest ckpt tag ($latest) when unset. FAIL-OPEN: stay true unless we can PROVE there is
# nothing new — a real audit must never be wrongly skipped.
audit_ref="$(printf '%s\n' "$block" | sed -n 's/^[[:space:]]*last_strong_ckpt[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' | head -n1)"
[[ -z "$audit_ref" ]] && audit_ref="$latest"
# Stale-watermark guard (2026-07-01 duplicate-dispatch incident, run relay-20260701-202806-14640):
# relay.toml's last_strong_ckpt can LAG the real newest strong checkpoint when an out-of-pool
# session mints ckpt tags without syncing relay.toml (tags 1927..2110 vs watermark 1635 → the
# pool re-dispatched duplicate strong reviews of an already-audited window every round). The
# tags themselves carry the role: ckpt-tag.sh appends the label as the LAST line of the tag
# annotation — "reviewer (...)" / "strong-execute (...)" are strong audits, "executor (...)"
# is not (an executor checkpoint must never advance the strong-audit anchor, id:e030 direction).
# Anchor on the newest strong-labeled tag when it is newer than the toml watermark (tag names
# embed date-minute, so the existing `sort` lexicographic order IS chronological order).
# FAIL-OPEN preserved: an unlabeled/legacy tag never matches → audit stays true; the unset-
# watermark $latest fallback above is unchanged (newest_strong can never sort after $latest).
newest_strong=""
if [[ -n "$tags" ]]; then
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    lbl="$(git -C "$path" tag -l --format='%(contents)' "$t" 2>/dev/null | awk 'NF{l=$0} END{print l}')"
    case "$lbl" in
      reviewer*|strong-execute*) newest_strong="$t"; break ;;
    esac
  done < <(printf '%s\n' "$tags" | tac)
fi
if [[ -n "$audit_ref" && -n "$newest_strong" ]] && [[ "$newest_strong" > "$audit_ref" ]]; then
  audit_ref="$newest_strong"
fi
substantive_unaudited=true       # FAIL-OPEN default
nonckpt_shas=""                  # sorted non-checkpoint commit shas since the audit ref (for work_sig)
if [[ -n "$audit_ref" ]] && git -C "$path" rev-parse --verify -q "$audit_ref" >/dev/null 2>&1; then
  # List commits since the ref; drop the pool's own checkpoint commits by subject.
  audit_log="$(git -C "$path" log "$audit_ref"..HEAD --pretty='%H %s' 2>/dev/null || true)"
  nonckpt_shas="$(printf '%s\n' "$audit_log" | grep -v '^[[:space:]]*$' \
                   | grep -vE ' (relay|fable): checkpoint' | awk '{print $1}' | sort || true)"
  if [[ -z "$nonckpt_shas" ]]; then
    # Only checkpoint commits (or none) since the ref → nothing substantive to audit.
    substantive_unaudited=false
  else
    # Of the non-checkpoint commits, is ANY one substantive — i.e. not a pure uv.lock-only
    # relock (id:bae5) and not a pure contract-pointer-refresh (id:373e follow-up)?
    has_substantive=false
    while IFS= read -r sha; do
      [[ -z "$sha" ]] && continue
      files="$(git -C "$path" show --name-only --pretty=format: "$sha" 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
      nonlock="$(printf '%s\n' "$files" | grep -vx 'uv.lock' || true)"
      [[ -z "$nonlock" ]] && continue    # uv.lock-only relock — not substantive (id:bae5)
      # Contract-pointer-refresh exemption: a commit whose ONLY changed content is the
      # `relay-executor contract vN` pointer line is a pure META refresh (`relay review` §4
      # bumps the marker when the executor contract version rises). A version bump must NOT,
      # by itself, re-classify every managed repo as needing a fresh strong review — that was
      # the observed waste (zkm-pdf, 2026-07-15). Detected by CONTENT, not commit subject, so
      # it holds however the reviewer titles the commit.
      content="$(git -C "$path" show --pretty=format: --unified=0 "$sha" 2>/dev/null \
                 | grep -E '^[+-]' | grep -vE '^[+-]{3} ' || true)"   # actual +/- content lines
      nonmeta="$(printf '%s\n' "$content" | grep -vE '^[[:space:]]*$' \
                 | grep -vE 'relay-executor contract v[0-9]+' || true)"
      [[ -z "$nonmeta" ]] && continue    # every changed line is the contract pointer — meta only
      has_substantive=true; break
    done <<< "$nonckpt_shas"
    [[ "$has_substantive" == true ]] && substantive_unaudited=true || substantive_unaudited=false
  fi
fi
# work_sig: STABLE across a `relay: checkpoint` commit, but changes when an item closes or a
# substantive commit lands. Hash the sorted-unique OPEN item id tokens + substantive_unaudited
# + the sorted non-checkpoint commit shas since the audit ref. (Checkpoint commits are excluded
# from nonckpt_shas, so the pool's own churn does not perturb the signature.)
open_ids="$(printf '%s\n' "$roadmap" | grep -oP '^- \[ \].*<!-- id:\K[0-9a-f]{4}' 2>/dev/null | sort -u || true)"
work_sig="$(printf '%s\n%s\n%s\n' "$open_ids" "$substantive_unaudited" "$nonckpt_shas" \
              | sha256sum | cut -c1-16)"

# id:9973 — deterministic open_hard_pool count: open "- [ ]" items whose PRIMARY lane
# (id:4da4 first-tag parse, mirroring classify-repo.sh:85) is tagged EXACTLY
# "[HARD — pool]" (the only pool-dispatchable HARD lane, per hard-lanes.md). Plain whole-line substring
# matching over-counted: an open item whose PROSE quotes `[HARD — pool]` (e.g. a
# hands/meeting item's re-lane criteria) is not a genuine pool tag (id:fb7f, it-infra
# phantom `hard` 2026-06-30). A recurring-audit-marked [HARD — pool] item (carrying
# <!-- relay:recurring-audit -->) does NOT count when substantive_unaudited is false —
# it has nothing new to audit this round and is therefore NOT an executable pool item
# (reuse the id:365b logic, same as the shard's recurring-audit gate). Also mirrors the
# conservative gate exclusion (classify-repo.sh:98): a 🚧/BLOCKED-on pool item is not
# executor-actionable this round either (under-dispatch-safe). The JS-side demote-guard
# (id:9973) reads this to demote a `hard` verdict on a repo with open_hard_pool == 0.
#
# roadmap_primary_lane <line> — leftmost recognized lane-tag by byte position, AFTER
# stripping backtick-quoted spans (id:1bbd) so a prose mention wrapped in backticks
# (e.g. "...whose re-lane criterion quotes `[HARD — pool]`...") cannot out-rank the
# item's own bare tag.
roadmap_primary_lane() {
  local line="$1" clean tag prefix pos best_pos=-1 best_tag=""
  clean="$(printf '%s' "$line" | sed -E 's/`[^`]*`//g')"
  # Dual-vocab window (id:4f02/id:8111 B2a, OPEN): the OLD venue-keyed "[HARD — <lane>]"
  # spelling and the NEW capability-keyed bare "[HARD]"/"[INPUT — <lane>]" spelling are
  # both recognized, then normalized to the same tag string below so every caller
  # (the open_hard_pool anchor) keeps comparing against one canonical value. "[HARD]"
  # is an EXACT substring match — it never false-matches inside "[HARD — pool]"/
  # "[HARD — hands]"/etc. (those contain "[HARD —", never the literal "[HARD]").
  for tag in "[ROUTINE]" "[HARD — pool]" "[HARD — hands]" "[HARD — meeting]" "[HARD — decision gate]" \
             "[HARD]" "[INPUT — access]" "[INPUT — meeting]" "[INPUT — decision]"; do
    case "$clean" in
      *"$tag"*)
        prefix="${clean%%"$tag"*}"; pos=${#prefix}
        if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
          best_pos=$pos; best_tag="$tag"
        fi ;;
    esac
  done
  case "$best_tag" in
    "[HARD]")              best_tag="[HARD — pool]" ;;
    "[INPUT — meeting]")   best_tag="[HARD — meeting]" ;;
    "[INPUT — decision]")  best_tag="[HARD — decision gate]" ;;
    "[INPUT — access]")    best_tag="[HARD — hands]" ;;
  esac
  printf '%s' "$best_tag"
}

open_hard_pool=0
if [[ -n "$roadmap" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*-\ \[\ \]\  ]] || continue
    [[ "$(roadmap_primary_lane "$line")" == "[HARD — pool]" ]] || continue
    case "$line" in
      *'🚧'*|*'BLOCKED on'*|*'blocked on'*) continue ;;
    esac
    # A recurring-audit item with nothing new to audit must NOT count.
    if printf '%s' "$line" | grep -q 'relay:recurring-audit' \
       && [[ "$substantive_unaudited" == false ]]; then
      continue
    fi
    open_hard_pool=$((open_hard_pool + 1))
  done < <(printf '%s\n' "$roadmap")
fi

emit true "$head_sha" "$latest" "$latest_msg" "$commits_since" "$dirty" "$porcelain" \
     "$upstream" "$has_upstream" "$worktrees" "$orphans" "$block" "$roadmap" \
     "$lock_only_unaudited" "$dirty_lock_only" "$is_finished" "$top_intensive" \
     "$substantive_unaudited" "$work_sig" "$open_hard_pool"
