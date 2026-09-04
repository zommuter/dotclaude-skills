#!/usr/bin/env bash
# discover-sig.sh (id:c3a6) -- per-repo SUPERSET signature for the relay discovery cache.
#
# The autonomous pool re-ran the LLM classifier shards fresh EVERY round, re-classifying repos
# whose observable state had not changed, the bulk of the on-critical-path "status" overhead.
# This helper lets the pool skip an LLM shard for an unchanged repo: it hashes EVERY input the
# shard classifier reads into one signature; runRound reuses the cached verdict when the signature
# is unchanged round-to-round.
#
# Correctness contract (the whole point):
#   • OVER-invalidation is safe (a wasted re-classify); UNDER-invalidation is the only hazard
#     (a stale verdict). So we hash a SUPERSET and err toward changing the sig.
#   • FAIL-OPEN: any git error / non-repo path → empty ("") sentinel sig, exit 0. An empty sig
#     means "I'm not sure" → the caller MUST re-classify. The cache is never a correctness authority.
#
# I/O: reads one JSON object on stdin: {"repos":[{"repo":"name","path":"/abs","chain_ended":false}...],"liveClaims":[...]}
#      the per-repo `chain_ended` flag is OPTIONAL (default false); see the id:8123 section below
#      emits one JSON line per repo on stdout: {"repo":"name","sig":"<sha256-hex or empty>"}
#
# Env overrides (for hermetic tests; default to the live relay locations):
#   RELAY_TOML           default ~/.config/relay/relay.toml   (per-repo block: income/intensive/path)
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees      (stale/claimed-elsewhere worktree dirs)
set -euo pipefail

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
RELAY_WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"
LOG="${HOME}/.claude/logs/relay-discover-sig.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

input="$(cat)"

# Extract the [repos.<name>] TOML block (until the next [section] header or EOF). Empty if absent.
toml_block() {
  local name="$1"
  [[ -f "$RELAY_TOML" ]] || return 0
  awk -v want="[repos.$name]" '
    $0 == want { inb=1; print; next }
    inb && /^[[:space:]]*\[/ { inb=0 }
    inb { print }
  ' "$RELAY_TOML" 2>/dev/null || true
}

# id:e96c: LEDGER FILES the classifier shard reads (content) and scans for detail pointers.
# classify-repo.sh applies `_ledger_note_bytes()` to ROADMAP.md / TODO.md / REVIEW_ME.md /
# RELAY_LOG.md, and resolve-gates.sh reads the archives, so all seven are shard inputs.
LEDGER_FILES=(ROADMAP.md ROADMAP.archive.md TODO.md TODO.archive.md
              REVIEW_ME.md REVIEW_ME.archive.md RELAY_LOG.md)

# ledger_notes_section <repo-path>
#
# Emits one `<relpath> <sha256|MISSING|UNREADABLE …>` line per LEDGER and per ledger-note
# DETAIL FILE the ledgers point at, sorted, for inclusion in the signature blob.
#
# WHY (id:e96c): the ratified line-shrink (id:0d7c) moves an item's prose OFF its ledger line
# into a per-id detail note, and classify-repo.sh (id:f3d2) stats every pointed-to note to
# compute roadmap_bytes/todo_bytes. Those notes are therefore SHARD INPUTS. Before this
# section they reached the blob only through `git status --porcelain`, which records THAT a
# file changed and never WHAT changed, so three substantively different UNCOMMITTED edits to
# one note collapsed to a single signature: under-invalidation, this cache's only hazard.
#
# THE NOTES DIRECTORY IS DERIVED FROM THE POINTER, never hardcoded (the id:d4d3 trap): a
# hardcoded `docs/ledger-notes` is INERT on the 45 fleet repos that name the directory
# differently (loderite uses `docs/roadmap-notes`), i.e. it would silently do nothing exactly
# where it is most needed. Same shape as meeting/orphan-scan.sh and todo-conformance.sh's
# SHAPE_POINTER_RE: read the path off the line, then treat that path's DIRECTORY as the notes
# directory and take every `<dir>/<name>.md` the ledgers mention.
#
# FAIL-OPEN, in both directions:
#   * an absent ledger or note contributes a stable MISSING line (a normal state, not an error);
#   * a ledger/note that EXISTS but cannot be read contributes a per-invocation NONCE, so the
#     sig cannot go stale behind an unreadable input; it forces a re-classify instead.
#     Over-hashing is free by this tool's contract; a confident sig over unread input is not.
ledger_notes_section() {
  local path="$1"
  local -a present=() rels=() cands=() keep=() readable=()
  local f d dre rel out dirs="" nonce=""

  for f in "${LEDGER_FILES[@]}"; do
    rels+=("$f")
    [[ -e "$path/$f" ]] && present+=("$path/$f")
  done

  if [[ ${#present[@]} -gt 0 ]]; then
    # (a) any path ending in `/<4-hex>.md`, the ratified detail-note spelling, in ANY directory.
    # (b) any `detail:` pointer target, whatever the note is named.
    mapfile -t cands < <(
      { grep -hoE '[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_.-]+)*/[0-9a-fA-F]{4}\.md' "${present[@]}" 2>/dev/null || true
        grep -hoP 'detail:[[:space:]]*`?\K[^`[:space:])]+\.md' "${present[@]}" 2>/dev/null || true
      } | sort -u
    )
    # (c) every OTHER `<dir>/<name>.md` under a directory a pointer named. classify-repo.sh's
    # own note-name regex is broader than 4-hex, so widen to the DERIVED directory. Cheap: one
    # extra grep per DISTINCT notes directory (normally exactly one).
    for f in "${cands[@]}"; do
      [[ "$f" == */* ]] || continue
      d="${f%/*}"
      case $'\n'"$dirs" in *$'\n'"$d"$'\n'*) continue ;; esac
      dirs+="$d"$'\n'
    done
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      dre="${d//./\\.}"
      mapfile -t -O "${#cands[@]}" cands < <(
        grep -hoE "$dre/[A-Za-z0-9_][A-Za-z0-9_.-]*\.md" "${present[@]}" 2>/dev/null || true
      )
    done <<< "$dirs"
    [[ ${#cands[@]} -gt 0 ]] && rels+=("${cands[@]}")
  fi

  mapfile -t keep < <(printf '%s\n' "${rels[@]}" | sort -u)
  for rel in "${keep[@]}"; do
    [[ -n "$rel" ]] || continue
    # Repo-relative paths only, and never a traversal.
    case "$rel" in /*|*..*) continue ;; esac
    if [[ ! -e "$path/$rel" ]]; then
      printf '%s MISSING\n' "$rel"
    elif [[ -f "$path/$rel" && -r "$path/$rel" ]]; then
      readable+=("$rel")
    else
      [[ -n "$nonce" ]] || nonce="$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
      printf '%s UNREADABLE %s\n' "$rel" "$nonce"
    fi
  done

  # ONE sha256sum over the whole readable set. Per-file invocations were MEASURED at ~4 s per
  # repo per discovery round on this repo's 746 pointed-to notes (750 forks); batched it is
  # ~0.1 s. Output is `<hash>  <relpath>` in ARGUMENT order, and the argument list is sorted,
  # so the section stays a deterministic pure function of on-disk state.
  if [[ ${#readable[@]} -gt 0 ]]; then
    if out="$( cd "$path" && sha256sum -- "${readable[@]}" )"; then
      printf '%s\n' "$out"
    else
      # A partial batch is discarded rather than trusted: a nonce forces a re-classify.
      nonce="$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
      printf 'BATCH-HASH-FAILED %s\n' "$nonce"
    fi
  fi
}

repo_sig() {
  local repo="$1" path="$2" inlive="$3" chain_ended="$4"
  # FAIL-OPEN gate: not a git work tree → empty sentinel.
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    log "fail-open: $repo ($path) is not a git repo"
    printf ''
    return 0
  fi
  local head tags latest tagmsg porcelain upstream worktrees orphans block roadmap dq ledger_notes
  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  tags="$(git -C "$path" tag -l 'fable-ckpt-*' 'relay-ckpt-*' 2>/dev/null | sort || true)"
  latest="$(printf '%s' "$tags" | tail -n1)"
  tagmsg=""
  [[ -n "$latest" ]] && tagmsg="$(git -C "$path" tag -l --format='%(contents)' "$latest" 2>/dev/null || true)"
  porcelain="$(git -C "$path" status --porcelain 2>/dev/null || true)"
  upstream="$(git -C "$path" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
  worktrees="$(ls -1 "$RELAY_WORKTREE_BASE/$repo" 2>/dev/null | sort || true)"
  orphans="$(git -C "$path" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/relay/orphan/ 2>/dev/null || true)"
  block="$(toml_block "$repo")"
  roadmap="$(cat "$path/ROADMAP.md" 2>/dev/null || true)"
  # routed:42c9/8b21: ROADMAP.archive.md is a CLASSIFIER INPUT since the archive-blindness
  # fixes: resolve-gates.sh resolves `gated-on:` targets over it, and BOTH classify-repo.sh
  # and gather-repo-state.sh call resolve-gates.sh. Archiving a gate target flips it from
  # dangling to satisfied and can change the verdict, so it MUST move the sig or the cache
  # serves a stale one. `git status --porcelain` only accidentally covered the file's
  # APPEARANCE (as an untracked entry) and never its CONTENT, and not even that once it is
  # committed. Over-hashing is free here; under-invalidation is this cache's only hazard.
  # (`2>/dev/null` on the cat: a repo with no archive is a normal state, not an error.)
  roadmap_archive="$(cat "$path/ROADMAP.archive.md" 2>/dev/null || true)"
  # id:e96c: ledger CONTENT hashes + the pointed-to ledger-note detail files. See
  # ledger_notes_section() above for the rationale and the fail-open terms. Errors are NOT
  # swallowed into an empty section (that would be a CONFIDENT sig over unread input): a
  # failure is logged and replaced by a nonce, which forces a re-classify.
  if ! ledger_notes="$(ledger_notes_section "$path")"; then
    log "fail-open: ledger_notes_section failed for $repo ($path) — nonce forces re-classify"
    ledger_notes="ERROR $(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
  fi
  # substantive_unaudited (id:e833, 2a fix): mirrors gather-repo-state.sh's id:365b
  # computation so the sig captures the AUDIT TARGET (which commit the audit ref
  # resolves to), not just the tag NAME/message. A force-retagged ckpt (same name,
  # same annotation, different target commit, e.g. the audit anchor advancing from
  # execute-state to review-state) previously left `tags`/`tagmsg` byte-identical,
  # so the sig silently missed a real state change (the execute→review sig-collision
  # gap, id:3134/e833). Recomputing the same substantive-work verdict here closes it
  # at the source: every discover-sig consumer benefits, no second policy list to
  # keep in sync with classify-verdict.sh. FAIL-OPEN default true preserved.
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
  audit_ref="$(head -n1 < <(printf '%s\n' "$block" | sed -n 's/^[[:space:]]*last_strong_ckpt[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p') )"
  [[ -z "$audit_ref" ]] && audit_ref="$latest"
  if [[ -n "$audit_ref" && -n "$newest_strong" ]] && [[ "$newest_strong" > "$audit_ref" ]]; then
    audit_ref="$newest_strong"
  fi
  substantive_unaudited=true
  if [[ -n "$audit_ref" ]] && git -C "$path" rev-parse --verify -q "$audit_ref" >/dev/null 2>&1; then
    audit_log="$(git -C "$path" log "$audit_ref"..HEAD --pretty='%H %s' 2>/dev/null || true)"
    nonckpt_shas="$(printf '%s\n' "$audit_log" | grep -v '^[[:space:]]*$' \
                     | grep -vE ' (relay|fable): checkpoint' | awk '{print $1}' | sort || true)"
    if [[ -z "$nonckpt_shas" ]]; then
      substantive_unaudited=false
    else
      has_substantive=false
      while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        files="$(git -C "$path" show --name-only --pretty=format: "$sha" 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
        nonlock="$(printf '%s\n' "$files" | grep -vx 'uv.lock' || true)"
        [[ -n "$nonlock" ]] && { has_substantive=true; break; }
      done <<< "$nonckpt_shas"
      [[ "$has_substantive" == true ]] && substantive_unaudited=true || substantive_unaudited=false
    fi
  fi
  # Decision-queue records for this repo (open AND resolved): the classifier's verdict
  # depends on them via unpromoted-scan's case-g exclusion (id:47f1) + the resolved-record
  # exclusion (2026-07-02 answer-then-re-ask fix). The queue lives OUTSIDE the repo, so no
  # git-derived section covers it. Filing or resolving an entry must invalidate the sig.
  # Fail-open: missing helper / empty queue → empty section (over-hashing is the safe side).
  dq="$("$(dirname "${BASH_SOURCE[0]}")/decision-queue.sh" list --repo "$repo" --all 2>/dev/null || true)"
  # Labeled, NUL-free sections so distinct inputs cannot collide into the same blob.
  {
    printf '== head ==\n%s\n'      "$head"
    printf '== tags ==\n%s\n'      "$tags"
    printf '== tagmsg ==\n%s\n'    "$tagmsg"
    printf '== porcelain ==\n%s\n' "$porcelain"
    printf '== upstream ==\n%s\n'  "$upstream"
    printf '== worktrees ==\n%s\n' "$worktrees"
    printf '== orphans ==\n%s\n'   "$orphans"
    printf '== toml ==\n%s\n'      "$block"
    printf '== roadmap ==\n%s\n'   "$roadmap"
    printf '== roadmap_archive ==\n%s\n' "$roadmap_archive"
    printf '== ledger_notes ==\n%s\n' "$ledger_notes"
    printf '== dq ==\n%s\n'        "$dq"
    printf '== inlive ==\n%s\n'    "$inlive"
    printf '== substantive_unaudited ==\n%s\n' "$substantive_unaudited"
    # id:8123: CHAIN-END fact. classify-verdict.sh takes `chain_ended` as a named input and
    # ranks `review` above `execute` under it, so it is a REAL classifier signal and MUST be in
    # this blob. UNDER-invalidation is this cache's only hazard: without this section a
    # chain-end verdict could be served STALE from last round's cached (execute) verdict and the
    # forced review would silently never fire, in exactly the situation the cadence fix exists
    # for. relay-loop.js's integrator step 7a passes "chain_ended":true when the repo's chain
    # just ended, so its postSig deliberately differs from the plain next-round sig (a cache
    # MISS → re-classify; over-invalidation is the safe side, per the contract at the top).
    printf '== chain_ended ==\n%s\n' "$chain_ended"
  } | sha256sum | cut -d' ' -f1 | tr -d '\n'
}

n="$(printf '%s' "$input" | jq '.repos | length' 2>/dev/null || echo 0)"
i=0
while [[ "$i" -lt "$n" ]]; do
  repo="$(printf '%s' "$input" | jq -r ".repos[$i].repo")"
  path="$(printf '%s' "$input" | jq -r ".repos[$i].path")"
  inlive="$(printf '%s' "$input" | jq -r --arg r "$repo" '((.liveClaims // []) | index($r)) != null')"
  # id:8123: optional per-repo chain-end fact (absent → false; any non-null/non-false → true).
  chain_ended="$(printf '%s' "$input" | jq -r ".repos[$i].chain_ended // false | if . == false or . == null then \"false\" else \"true\" end")"
  sig="$(repo_sig "$repo" "$path" "$inlive" "$chain_ended")"
  jq -cn --arg repo "$repo" --arg sig "$sig" '{repo:$repo,sig:$sig}'
  i=$((i+1))
done
