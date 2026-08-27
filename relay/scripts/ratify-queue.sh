#!/usr/bin/env bash
# ratify-queue.sh — the CONSUMER for the id:4d44 ratification queue.
#
# The producer is integrate.sh step 8b: for a SUBSTANTIVE unit the pool merges `--no-ff`,
# bumps, changelogs and ckpt-tags LOCALLY, does NOT push, and appends ONE JSON record to
# the append-only ratification queue (flock'd through relay-state-write.sh event-append).
# Nothing read that queue — this is the read/resolve side. The owner reviews the local
# merge, pushes it himself, and then marks the entry resolved HERE.
#
# Subcommands:
#   list [--repo NAME] [--all] [--json|--tsv]
#       Human-readable one line per PENDING entry (repo · ids · ckpt · merged · age).
#       --all   also show resolved entries.  --json one record per line (raw).
#       --tsv   `repo \t path \t kind \t box_summary` rows for gather-human-backlog.sh.
#   show <key>
#       Full detail for one entry, including the EXACT push command the owner needs.
#   verify <key> [--remote NAME]
#       READ-ONLY: does the remote actually carry this merge (and its ckpt tag)? Prints a
#       verdict; exit 0 = landed, 4 = NOT landed, 5 = could not verify. Writes nothing.
#   resolve <key> [--remote NAME] [--allow-missing-tag] [--note TEXT]
#       VERIFY FIRST, then mark the entry resolved. Refuses (nonzero, loud) unless the
#       remote demonstrably carries the recorded merge sha.
#   retire <key> --reason TEXT
#       Close an entry that can NEVER land, WITHOUT the remote carrying it, recording WHY.
#       `--reason` is MANDATORY. Marks status=retired (distinct from resolved) and writes
#       NO landing evidence. Refuses an entry that is not pending.
#
# <key> is the entry's ckpt tag, or its merged sha (full or a >=7-char prefix). It must
# match EXACTLY ONE entry; an ambiguous key is a loud refusal, never a guess.
#
# ── WHY `retire` IS A SEPARATE VERB, NOT `resolve --force` (id:99b7(b)) ─────────────────
# Some entries are unresolvable BY CONSTRUCTION: a pending remote that is a read-only
# third-party upstream nobody pushes to (`git://…`), or a merge commit that no longer
# exists in any object store while its ids demonstrably landed by other paths. `resolve`
# must keep refusing those — its remote check is the whole point of the queue.
#
# A `--force` on resolve would be the wrong shape: it would ALSO let a real, still-unpushed
# merge be stamped ratified, which is the single failure this queue exists to prevent. So
# the escape is a DIFFERENT verb with DIFFERENT semantics and a DIFFERENT stored status:
#   resolve = "the remote demonstrably carries this"  (evidence: verified_sha/resolved_ref)
#   retire  = "this can never land, and here is why"  (evidence: retire_reason/retired_at)
# `retire` never runs a remote check and never writes a `verified_*`/`resolved_*` field, so
# a retired entry can never be mistaken for a published one by any later reader. The reason
# is mandatory because an unexplained close is exactly what trains a reader to stop trusting
# the queue — and a queue reporting N pending when 0 are actionable is the same disease.
#
# ── WHY RESOLUTION VERIFIES THE REMOTE ITSELF (id:f5d9(a) / id:dc4f) ────────────────────
# `git-lock-push.sh` has a live defect: it can exit 0 having pushed NOTHING. So a push
# helper's exit code is NOT evidence and is never consulted here. `resolve` runs
# `git ls-remote <remote>` and requires the recorded `merged` sha to be a BRANCH tip on the
# remote (refs/heads), or an ancestor of one. Everything else — an unreachable remote, an empty
# listing, a remote that moved to some OTHER sha — is treated as NOT LANDED and REFUSED.
# Fail-closed is the safe side: a refused resolve costs one re-run; a false resolve buries
# an unpublished merge forever. There is deliberately NO "push and resolve" path — the
# owner pushes (that IS the ratification), this only records that it happened.
#
# ── NEVER SILENTLY DROP AN ENTRY ───────────────────────────────────────────────────────
# A line that is not parseable JSON, or is JSON without the fields this consumer needs, is
# printed on stderr as `MALFORMED:` with the file, line number and reason, and forces a
# NONZERO exit (3). It is never skipped, never counted as "nothing pending", and the
# rewrite performed by `resolve` preserves it BYTE-FOR-BYTE — a malformed neighbour can
# never be deleted by resolving something else.
#
# ── MARK, DON'T VANISH ─────────────────────────────────────────────────────────────────
# The cross-repo todo inbox vanishes on resolve because its durable record is the
# breadcrumb in the target repo. Here the merge is already durable in git — but WHO
# ratified it and WHEN is not, and neither is the verification evidence. So a resolved
# entry is MARKED in place (status/resolved_at/resolved_remote/resolved_ref/verified_sha)
# and kept: the queue doubles as the audit trail of local-merge → human sign-off. Growth
# is bounded by integrates; `list` shows only pending unless asked. A RETIRED entry is kept
# for the same reason and more strongly: its whole value is the recorded reason it could
# never land, so `list --all` prints that reason next to the status.
#
# Queue file: $RELAY_RATIFICATION_QUEUE, else $FABLES_CONFIG/ratification-queue.jsonl,
# else ~/.config/relay/ratification-queue.jsonl — the same resolution integrate.sh uses.
# Lock: <queue>.lock (flock fd 9, -w 30), matching decision-queue.sh.
set -euo pipefail

QUEUE="${RELAY_RATIFICATION_QUEUE:-${FABLES_CONFIG:-$HOME/.config/relay}/ratification-queue.jsonl}"
LOCK_FILE="${QUEUE}.lock"

EX_USAGE=2
EX_MALFORMED=3
EX_NOTLANDED=4
EX_UNVERIFIABLE=5

die()   { printf 'ERROR: %s\n' "$*" >&2; exit "$EX_USAGE"; }
loud()  { printf 'ERROR: %s\n' "$*" >&2; }

_flock_acquire() {
  mkdir -p "$(dirname "$QUEUE")"
  exec 9>"$LOCK_FILE"
  flock -x -w 30 9 || { printf 'ERROR: could not acquire ratification-queue lock after 30s (%s)\n' "$LOCK_FILE" >&2; exit 1; }
}
_flock_release() { exec 9>&-; }

# ── the shared record reader ────────────────────────────────────────────────────────────
# Emits, on stdout, one US(0x1f)-separated projection per WELL-FORMED record:
#   lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason
# `pending` (id:4d44) is the comma-separated list of remotes that did NOT receive the merge;
# EMPTY on a pre-id:4d44 record, which means "unknown" and restores the original single-remote
# verification. New columns go at the END so an older reader's positions never shift.
# and one `MALFORMED:` line per bad record on stderr. Exit 3 if any malformed was seen.
# Kept in ONE place so list/show/verify/resolve can never disagree about what is valid.
_read_records() {
  [ -f "$QUEUE" ] || return 0
  python3 - "$QUEUE" <<'PYEOF'
import json, sys

path = sys.argv[1]
bad = 0
HEX = "0123456789abcdef"

def flat(s):
    return " ".join(str(s).split())

with open(path, encoding="utf-8", errors="replace") as fh:
    for n, raw in enumerate(fh, 1):
        if not raw.strip():
            continue
        try:
            rec = json.loads(raw)
        except Exception as exc:
            print("MALFORMED: %s:%d not parseable JSON (%s): %s"
                  % (path, n, exc, flat(raw)[:200]), file=sys.stderr)
            bad = 1
            continue
        if not isinstance(rec, dict):
            print("MALFORMED: %s:%d JSON is not an object: %s"
                  % (path, n, flat(raw)[:200]), file=sys.stderr)
            bad = 1
            continue
        kind = rec.get("kind")
        if kind != "ratification-pending":
            print("MALFORMED: %s:%d unknown kind %r — this consumer only understands "
                  "'ratification-pending' (id:4d44); the entry is NOT skipped, fix it or "
                  "move it out of the queue"
                  % (path, n, kind), file=sys.stderr)
            bad = 1
            continue
        missing = [k for k in ("repo", "path", "merged", "status") if not rec.get(k)]
        if missing:
            print("MALFORMED: %s:%d ratification record missing required field(s) %s — "
                  "repo=%r merged=%r; a merge may be sitting UNPUSHED with no usable "
                  "queue entry, record it by hand"
                  % (path, n, ",".join(missing), rec.get("repo"), rec.get("merged")),
                  file=sys.stderr)
            bad = 1
            continue
        merged = str(rec["merged"])
        if len(merged) < 7 or any(c not in HEX for c in merged.lower()):
            print("MALFORMED: %s:%d merged=%r is not a git sha — cannot be verified "
                  "against any remote" % (path, n, merged), file=sys.stderr)
            bad = 1
            continue
        ids = rec.get("ids") or []
        if isinstance(ids, list):
            ids = ",".join(str(i) for i in ids)
        # id:4d44 per-remote: which remotes did NOT receive the merge. OLDER records (and any
        # hand-written one) have no such field — an EMPTY list means "unknown / all of them",
        # and the verification falls back to its original single-default-remote behaviour.
        pending = rec.get("pending_remotes") or []
        if isinstance(pending, list):
            pending = ",".join(str(r) for r in pending if r)
        cols = [
            str(n), str(rec.get("status")), str(rec["repo"]), str(rec["path"]),
            str(rec.get("branch", "")), merged, str(rec.get("ckpt", "")),
            flat(ids), str(rec.get("bump", "")), str(rec.get("run", "")),
            str(rec.get("verdict", "")), str(rec.get("ts", "")),
            flat(rec.get("summary", "")), flat(pending),
            # id:99b7(b) — the retire reason, LAST so no older reader's positions shift.
            flat(rec.get("retire_reason", "")),
        ]
        # US (0x1f), NOT tab: a TAB is an IFS-*whitespace* character, so bash's
        # `IFS=$'\t' read` COLLAPSES consecutive tabs and an empty field (bump="" on a
        # refactor-only close, or a missing ckpt) silently shifts every later column.
        # Measured: it put `run` into `bump` and the ckpt tag into `ids`, which then fed
        # the wrong tag to the remote verification. 0x1f is non-whitespace, so empty
        # fields survive.
        print("\x1f".join(flat(c) for c in cols))

sys.exit(3 if bad else 0)
PYEOF
}

# Age of an ISO-8601 Z timestamp, as a compact human string. "?" when unusable.
_age() {
  local ts="$1" then now d
  [ -n "$ts" ] || { printf '?'; return 0; }
  then="$(date -u -d "$ts" +%s 2>/dev/null)" || { printf '?'; return 0; }
  now="$(date -u +%s)"
  d=$(( now - then ))
  (( d < 0 )) && d=0
  if   (( d < 3600 ));  then printf '%dm' $(( d / 60 ))
  elif (( d < 86400 )); then printf '%dh' $(( d / 3600 ))
  else                       printf '%dd' $(( d / 86400 ))
  fi
}

# Resolve <key> to EXACTLY ONE record's projection line. Loud on 0 or >1.
# $1 key. Echoes the projection line. Exit 2 on no/ambiguous match.
#
# PENDING entries are matched FIRST and alone: that keeps the pre-id:99b7 ambiguity
# semantics exactly as they were (a closed entry can never make a live key ambiguous).
# Only when NO pending entry matches does it fall back to closed (resolved/retired) ones —
# so `show <retired-key>` still works, and `resolve`/`retire` can say "that entry is
# already retired" instead of the misleading "no such key". Callers that MUTATE must check
# the returned status themselves; this function deliberately does not decide that.
_find_one() {
  local key="$1" recs rc=0 hits scope=pending
  recs="$(_read_records)" || rc=$?
  if (( rc == 3 )); then
    loud "the queue contains MALFORMED entries (listed above) — fix them first; refusing to act on a queue this consumer cannot fully read"
    exit "$EX_MALFORMED"
  fi
  _match() {  # $1 = "pending" to restrict to pending records, "" for any status
    printf '%s\n' "$recs" | awk -F'\037' -v k="$1" -v only="$2" '
      $1 == "" { next }
      only != "" && $2 != only { next }
      $7 == k { print; next }                                   # exact ckpt tag
      $6 == k { print; next }                                   # exact merged sha
      length(k) >= 7 && substr($6, 1, length(k)) == k { print }  # merged sha prefix
    '
  }
  hits="$(_match "$key" pending)"
  local n
  n="$(printf '%s' "$hits" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    hits="$(_match "$key" "")"
    scope=closed
    n="$(printf '%s' "$hits" | grep -c . || true)"
  fi
  if [ "$n" -eq 0 ]; then
    loud "no ratification entry matches key '$key' in $QUEUE (try: ratify-queue.sh list --all)"
    exit "$EX_USAGE"
  fi
  if [ "$n" -gt 1 ]; then
    loud "key '$key' is AMBIGUOUS — it matches $n $scope entries; name the full ckpt tag or merged sha:"
    printf '%s\n' "$hits" | awk -F'\037' '{printf "  ckpt=%s merged=%s repo=%s status=%s\n", $7, $6, $3, $2}' >&2
    exit "$EX_USAGE"
  fi
  printf '%s\n' "$hits"
}

# A mutating subcommand may only act on a PENDING entry. $1 verb, $2 status, $3 key.
_require_pending() {
  local verb="$1" status="$2" key="$3"
  [ "$status" = pending ] || {
    loud "$verb: entry '$key' is already $status — refusing. A closed entry is never re-closed (its recorded evidence would be overwritten). See: ratify-queue.sh show $key"
    exit "$EX_USAGE"
  }
}

# ── remote verification (the safety core) ───────────────────────────────────────────────
# $1 repo path, $2 merged sha, $3 ckpt tag (may be empty), $4 remote override (may be empty)
# Prints `<verdict> <remote> <ref>` on stdout where verdict is landed|landed-ancestor.
# Exits 4 (NOT landed) or 5 (cannot verify) with a loud stderr explanation otherwise.
_verify_remote() {
  local path="$1" merged="$2" ckpt="$3" remote="$4"
  local ls_out="" remotes="" ref="" verdict=""

  if [ ! -d "$path" ]; then
    loud "repo path does not exist: $path — the recorded merge $merged cannot be verified. Do NOT resolve; find the checkout (or the record is stale/wrong)."
    exit "$EX_UNVERIFIABLE"
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    loud "$path is not a git repository — the recorded merge $merged cannot be verified."
    exit "$EX_UNVERIFIABLE"
  fi
  if [ -z "$remote" ]; then
    remotes="$(git -C "$path" remote 2>/dev/null || true)"
    if grep -qx origin <<< "$remotes"; then
      remote=origin
    elif [ "$(printf '%s\n' "$remotes" | grep -c . || true)" -eq 1 ]; then
      remote="$(printf '%s\n' "$remotes" | tr -d '[:space:]')"
    else
      loud "cannot choose a remote for $path (remotes: $(printf '%s' "$remotes" | tr '\n' ' ')) — pass --remote NAME. Refusing to resolve on a guess."
      exit "$EX_UNVERIFIABLE"
    fi
  fi
  if ! ls_out="$(git -C "$path" ls-remote --heads --tags "$remote" 2>&1)"; then
    loud "git ls-remote $remote failed in $path — the push CANNOT be verified, so this entry stays PENDING (id:f5d9(a): an unverifiable push is treated as NOT landed). Output: $(printf '%s' "$ls_out" | tr '\n' ' ')"
    exit "$EX_UNVERIFIABLE"
  fi
  if [ -z "$(printf '%s' "$ls_out" | tr -d '[:space:]')" ]; then
    loud "git ls-remote $remote returned NOTHING in $path — no evidence the remote carries anything, let alone $merged. Treated as NOT landed (id:f5d9(a))."
    exit "$EX_UNVERIFIABLE"
  fi

  # 1. the merge sha is a BRANCH tip on the remote.
  #
  #    refs/heads ONLY, deliberately. An annotated ckpt tag peels to the merge commit, so
  #    `refs/tags/<ckpt>^{}` equals `merged` the moment the TAG is pushed — even if the
  #    branch never moved. Accepting any ref here would call a tag-only push "landed" and
  #    resolve an entry whose merge is still absent from the published trunk: precisely the
  #    false-resolve this queue exists to prevent. (Found by mutation-testing this check.)
  ref="$(awk -v m="$merged" '$1 == m && $2 ~ /^refs\/heads\// { print $2; exit }' <<< "$ls_out")"
  if [ -n "$ref" ]; then
    verdict="landed"
  else
    # 2. or it is an ANCESTOR of a remote head we also have locally (the remote moved on)
    while read -r rsha rref; do
      [ -n "$rsha" ] || continue
      case "$rref" in refs/heads/*) ;; *) continue ;; esac
      git -C "$path" cat-file -e "$rsha^{commit}" 2>/dev/null || continue
      if git -C "$path" merge-base --is-ancestor "$merged" "$rsha" 2>/dev/null; then
        ref="$rref"; verdict="landed-ancestor"; break
      fi
    done <<< "$(printf '%s\n' "$ls_out")"
  fi

  if [ -z "$verdict" ]; then
    loud "NOT LANDED: $remote does not carry $merged (neither as a ref tip nor as an ancestor of any remote head this checkout knows). The merge is still LOCAL-ONLY. Push it first:"
    loud "  git -C $path push --follow-tags"
    exit "$EX_NOTLANDED"
  fi

  # the ckpt tag rides along with --follow-tags; a missing one means a half-published unit
  if [ -n "$ckpt" ] && [ "$ckpt" != "-" ]; then
    # CAPTURE-THEN-TEST, deliberately (id:81d5): a `producer | grep -q` here would take
    # SIGPIPE 141 under `pipefail` and fail INTERMITTENTLY on a TRUE match — and this test
    # decides whether it is safe to resolve an entry, so a spurious result is the last thing
    # it may do. `sed` reads to EOF, `grep -qx` consumes a here-string; no pipe SIGPIPEs.
    remote_tag_refs="$(awk '{print $2}' <<< "$ls_out" | sed 's/\^{}$//')"
    if ! grep -qx "refs/tags/$ckpt" <<< "$remote_tag_refs"; then
      if [ "${ALLOW_MISSING_TAG:-0}" = "1" ]; then
        loud "WARNING: $remote carries the merge but NOT the ckpt tag $ckpt — resolving anyway (--allow-missing-tag)."
      else
        loud "PARTIAL: $remote carries the merge $merged but NOT its checkpoint tag $ckpt — the unit is half-published and last_strong_ckpt consumers will read stale. Push the tag, then resolve:"
        loud "  git -C $path push $remote $ckpt"
        loud "  (or re-run with --allow-missing-tag if the tag is deliberately local)"
        exit "$EX_NOTLANDED"
      fi
    fi
  fi

  printf '%s %s %s\n' "$verdict" "$remote" "$ref"
}

# ── id:4d44 per-remote: verify EVERY remote that still owes this merge ───────────────────
# $1 path, $2 merged, $3 ckpt, $4 explicit --remote override (may be empty),
# $5 the record's comma-separated `pending_remotes` (may be empty on a legacy record).
# Prints one `<verdict> <remote> <ref>` line per verified remote. ANY remote that fails
# verification aborts the whole thing (each _verify_remote already exits loud + nonzero, and
# `set -e` propagates it) — so a partial pass can never look like a resolve.
#
# WHY THIS EXISTS: integrate.sh now pushes a substantive unit's PRIVATE/LAN remotes and defers
# only its public ones. If the private remote happens to be named `origin`, the ORIGINAL
# single-default-remote check would verify the remote that was ALREADY pushed and resolve the
# entry while the public remote still lacks the merge — a false resolve of exactly the kind
# this queue exists to prevent.
_verify_pending() {
  local path="$1" merged="$2" ckpt="$3" remote="$4" pending="$5"
  local targets="" t res
  if [ -n "$remote" ]; then
    # An explicit override must COVER every pending remote, else it would resolve an entry
    # on partial evidence. Refuse rather than narrow silently.
    if [ -n "$pending" ] && [ "$pending" != "$remote" ]; then
      loud "--remote '$remote' does not cover this entry's PENDING remotes ($pending) — resolving on it would mark the entry done while $pending still lack the merge. Omit --remote to verify all of them."
      exit "$EX_USAGE"
    fi
    targets="$remote"
  elif [ -n "$pending" ]; then
    targets="$(printf '%s' "$pending" | tr ',' '\n')"
  else
    # Legacy record (pre-id:4d44) — no per-remote knowledge; verify the single default
    # remote exactly as before.
    _verify_remote "$path" "$merged" "$ckpt" ""
    return 0
  fi
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    res="$(_verify_remote "$path" "$merged" "$ckpt" "$t")"
    printf '%s\n' "$res"
  done <<< "$targets"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  list)
    show_all=0; filter_repo=""; fmt=human
    while [ $# -gt 0 ]; do
      case "$1" in
        --all)  show_all=1 ;;
        --repo) shift; filter_repo="${1:-}" ;;
        --json) fmt=json ;;
        --tsv)  fmt=tsv ;;
        *) die "list: unknown flag '$1'" ;;
      esac
      shift || true
    done

    if [ "$fmt" = json ]; then
      # raw records, unprojected — but still validated, so malformed is still loud
      recs="$(_read_records)" || rc=$?
      : "${rc:=0}"
      if [ -f "$QUEUE" ]; then
        while IFS=$'\x1f' read -r lineno status _rest; do
          [ -n "${lineno:-}" ] || continue
          [ "$show_all" = 1 ] || [ "$status" = pending ] || continue
          sed -n "${lineno}p" "$QUEUE"
        done <<< "$recs"
      fi
      if [ "${rc:-0}" = 3 ]; then exit "$EX_MALFORMED"; fi
      exit 0
    fi

    rc=0
    recs="$(_read_records)" || rc=$?
    count=0
    while IFS=$'\x1f' read -r lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason; do
      [ -n "${lineno:-}" ] || continue
      [ "$show_all" = 1 ] || [ "$status" = pending ] || continue
      [ -z "$filter_repo" ] || [ "$repo" = "$filter_repo" ] || continue
      count=$(( count + 1 ))
      if [ "$fmt" = tsv ]; then
        # id:99b7(b) — the TSV feeds /relay human's backlog. A CLOSED entry (resolved or
        # retired) is not a human box any more, so it is never emitted here even under
        # --all; emitting it would put a "still needs an owner push" row in front of the
        # owner for a merge that will never be pushed.
        [ "$status" = pending ] || { count=$(( count - 1 )); continue; }
        # gather-human-backlog.sh column contract: repo \t path \t kind \t box_summary
        # id:4d44 per-remote: when the record names its pending remotes, the box must name
        # them too — "did NOT push" is false for a unit that already published to its LAN
        # remotes, and the owner needs to know which push is actually outstanding.
        if [ -n "$pending" ]; then
          rq_what="pool merged LOCALLY and pushed only the PRIVATE/LAN remote(s); [$pending] still need an owner push: $(printf '%s' "$pending" | tr ',' '\n' | sed "s|^|git -C $path push --follow-tags |" | tr '\n' ';')"
        else
          rq_what="pool merged LOCALLY and did NOT push — review then push: git -C $path push --follow-tags"
        fi
        printf '%s\t%s\t%s\t%s\n' "$repo" "$path" ratification_pending \
          "[RATIFY id:4d44] $rq_what (merged=${merged:0:12} ckpt=${ckpt:--} ids=${ids:--} bump=${bump:-none} age=$(_age "$ts")) — ${summary:-no summary}"
      else
        printf '%-28s %-22s %-12s ids=%-24s bump=%-8s age=%s\n' \
          "${ckpt:--}" "$repo" "${merged:0:12}" "${ids:--}" "${bump:-none}" "$(_age "$ts")"
        if [ "$show_all" = 1 ] && [ "$status" != pending ]; then
          # id:99b7(b) — a RETIRED entry is closed WITHOUT the remote carrying it, so the
          # status alone is not enough: print the recorded reason right beside it, or the
          # listing reads identically to a genuine, verified resolve.
          if [ -n "$reason" ]; then
            printf '%-28s   ^ status=%s — %s\n' "" "$status" "$reason"
          else
            printf '%-28s   ^ status=%s\n' "" "$status"
          fi
        fi
      fi
    done <<< "$recs"

    if [ "$fmt" = human ]; then
      if [ "$count" -eq 0 ]; then
        printf 'no %s ratification entries in %s\n' \
          "$( [ "$show_all" = 1 ] && echo "" || echo "pending" )" "$QUEUE"
      else
        printf -- '-- %d %s entr%s; `ratify-queue.sh show <ckpt|sha>` for the push command, `resolve <ckpt|sha>` AFTER pushing\n' \
          "$count" "$( [ "$show_all" = 1 ] && echo "" || echo "pending" )" \
          "$( [ "$count" -eq 1 ] && echo y || echo ies )"
      fi
    fi
    if [ "$rc" = 3 ]; then exit "$EX_MALFORMED"; fi
    exit 0
    ;;

  show)
    key="${1:-}"; [ -n "$key" ] || die "usage: ratify-queue.sh show <ckpt|merged-sha>"
    line="$(_find_one "$key")"
    IFS=$'\x1f' read -r lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason <<< "$line"
    printf 'repo      %s\n'  "$repo"
    printf 'path      %s\n'  "$path"
    printf 'merged    %s\n'  "$merged"
    printf 'ckpt      %s\n'  "${ckpt:--}"
    printf 'branch    %s\n'  "${branch:--}"
    printf 'ids       %s\n'  "${ids:--}"
    printf 'bump      %s\n'  "${bump:-none}"
    printf 'run       %s\n'  "${run:--}"
    printf 'verdict   %s\n'  "${verdict:--}"
    printf 'queued    %s (%s ago)\n' "${ts:--}" "$(_age "$ts")"
    printf 'status    %s\n'  "$status"
    printf 'summary   %s\n'  "${summary:--}"
    # id:4d44 — name the remotes that are actually outstanding. A `partial` unit already
    # published to its private/LAN remotes; a bare `git push` command would be misleading
    # about what is left (and about what is already out there).
    printf 'pending   %s\n'  "${pending:-<all/unknown>}"
    # id:99b7(b) — a RETIRED entry must never be presented as outstanding work. Its
    # `pending_remotes` is kept as evidence of what could never land, so print the
    # retirement instead of a push command nobody is ever going to run.
    if [ "$status" = retired ]; then
      printf 'retired   %s\n' "${reason:-<no reason recorded — this should be impossible>}"
      printf 'note      CLOSED WITHOUT PUBLISHING: the remote does NOT carry %s and never will.\n' "$merged"
      exit 0
    fi
    if [ -n "$pending" ]; then
      printf '%s' "$pending" | tr ',' '\n' | while IFS= read -r r; do
        [ -n "$r" ] && printf 'push      git -C %s push --follow-tags %s\n' "$path" "$r"
      done
    else
      printf 'push      git -C %s push --follow-tags\n' "$path"
    fi
    printf 'then      ratify-queue.sh resolve %s\n' "${ckpt:-$merged}"
    printf 'or        ratify-queue.sh retire %s --reason "<why it can NEVER land>"\n' "${ckpt:-$merged}"
    exit 0
    ;;

  verify)
    key="${1:-}"; [ -n "$key" ] || die "usage: ratify-queue.sh verify <ckpt|merged-sha> [--remote NAME]"
    shift || true
    remote=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --remote) shift; remote="${1:-}" ;;
        --allow-missing-tag) ALLOW_MISSING_TAG=1 ;;
        *) die "verify: unknown flag '$1'" ;;
      esac
      shift || true
    done
    line="$(_find_one "$key")"
    IFS=$'\x1f' read -r lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason <<< "$line"
    res="$(_verify_pending "$path" "$merged" "$ckpt" "$remote" "$pending")"
    while IFS=' ' read -r v_verdict v_remote v_ref; do
      [ -n "${v_verdict:-}" ] || continue
      printf 'LANDED (%s): %s/%s carries %s (%s)\n' "$v_verdict" "$repo" "$v_remote" "$merged" "$v_ref"
    done <<< "$res"
    exit 0
    ;;

  resolve)
    key="${1:-}"; [ -n "$key" ] || die "usage: ratify-queue.sh resolve <ckpt|merged-sha> [--remote NAME] [--allow-missing-tag] [--note TEXT]"
    shift || true
    remote=""; note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --remote) shift; remote="${1:-}" ;;
        --note)   shift; note="${1:-}" ;;
        --allow-missing-tag) ALLOW_MISSING_TAG=1 ;;
        *) die "resolve: unknown flag '$1'" ;;
      esac
      shift || true
    done

    line="$(_find_one "$key")"
    IFS=$'\x1f' read -r lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason <<< "$line"
    # id:99b7(b) — never re-close a closed entry. A retired entry in particular must not be
    # re-opened into "resolved": its whole record is that the remote does NOT carry it.
    _require_pending resolve "$status" "$key"

    # VERIFY BEFORE MARKING. Any non-landed outcome exits nonzero from here and the
    # queue is left untouched — the entry stays pending, which is the safe side.
    # id:4d44 — EVERY pending remote must carry the merge; a single verified remote is not
    # evidence when the record says two are outstanding.
    res="$(_verify_pending "$path" "$merged" "$ckpt" "$remote" "$pending")"
    v_verdict="" v_remote="" v_ref=""
    while IFS=' ' read -r _v _r _f; do
      [ -n "${_v:-}" ] || continue
      v_verdict="${v_verdict:+$v_verdict,}$_v"
      v_remote="${v_remote:+$v_remote,}$_r"
      v_ref="${v_ref:+$v_ref,}$_f"
    done <<< "$res"
    if [ -z "$v_remote" ]; then
      loud "verification produced no result for '${ckpt:-$merged}' — refusing to resolve on no evidence"
      exit "$EX_UNVERIFIABLE"
    fi

    _flock_acquire
    tmp="${QUEUE}.tmp.$$"
    python3 - "$QUEUE" "$tmp" "$lineno" "$v_verdict" "$v_remote" "$v_ref" "$merged" "$note" <<'PYEOF'
import json, sys, datetime

queue, tmp, lineno, verdict, remote, ref, merged, note = sys.argv[1:9]
lineno = int(lineno)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

out = []
hit = False
with open(queue, encoding="utf-8") as fh:
    for n, raw in enumerate(fh, 1):
        if n != lineno:
            # Every other line is preserved BYTE-FOR-BYTE, malformed ones included:
            # resolving one entry must never delete or rewrite a neighbour.
            out.append(raw.rstrip("\n"))
            continue
        rec = json.loads(raw)
        rec["status"] = "resolved"
        rec["push"] = "pushed"
        # id:4d44 — nothing is outstanding any more; leaving a stale pending list would make
        # a later reader think remotes still owe this merge.
        rec["pending_remotes"] = []
        rec["resolved_at"] = now
        rec["resolved_by"] = "ratify-queue.sh"
        rec["resolved_remote"] = remote
        rec["resolved_ref"] = ref
        rec["verified_sha"] = merged
        rec["verification"] = verdict
        if note:
            rec["resolved_note"] = note
        out.append(json.dumps(rec, ensure_ascii=False))
        hit = True

if not hit:
    raise SystemExit("ERROR: line %d vanished from %s while resolving — queue changed underneath; nothing written" % (lineno, queue))

with open(tmp, "w", encoding="utf-8") as fh:
    for l in out:
        fh.write(l + "\n")
PYEOF
    mv "$tmp" "$QUEUE"
    _flock_release
    printf 'RESOLVED %s (%s): %s/%s carries %s (%s)\n' "${ckpt:-$merged}" "$repo" "$v_remote" "$v_ref" "$merged" "$v_verdict"
    exit 0
    ;;

  # ── retire (id:99b7(b)) — close an entry that can NEVER land ──────────────────────────
  # Deliberately NOT `resolve --force`: see the header. This verb runs NO remote check
  # (there is nothing to check — that is the premise) and writes NO landing evidence, so a
  # retired entry can never be misread as published. The mandatory --reason is the whole
  # point: the record's value is WHY it was written off, and an unexplained close is what
  # makes a queue untrustworthy.
  retire)
    key="${1:-}"; [ -n "$key" ] || die "usage: ratify-queue.sh retire <ckpt|merged-sha> --reason TEXT"
    shift || true
    reason_arg=""; have_reason=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) shift; reason_arg="${1:-}"; have_reason=1 ;;
        *) die "retire: unknown flag '$1' (retire takes only --reason TEXT; there is deliberately no --force, no --remote and no --allow-* escape)" ;;
      esac
      shift || true
    done
    if [ "$have_reason" = 0 ]; then
      die "retire: --reason TEXT is MANDATORY. Retiring closes an entry WITHOUT the remote carrying its merge, so the recorded reason is the only thing that keeps the queue auditable. If the merge CAN be published, push it and use \`resolve\` instead."
    fi
    if [ -z "$(printf '%s' "$reason_arg" | tr -d '[:space:]')" ]; then
      die "retire: --reason is EMPTY — an empty reason is no reason. Say why this entry can never land (e.g. 'pending remote is a read-only third-party upstream we never publish to', or 'merge commit no longer exists; ids landed via <path>')."
    fi

    line="$(_find_one "$key")"
    IFS=$'\x1f' read -r lineno status repo path branch merged ckpt ids bump run verdict ts summary pending reason <<< "$line"
    _require_pending retire "$status" "$key"

    _flock_acquire
    tmp="${QUEUE}.tmp.$$"
    python3 - "$QUEUE" "$tmp" "$lineno" "$reason_arg" <<'PYEOF'
import json, sys, datetime

queue, tmp, lineno, reason = sys.argv[1:5]
lineno = int(lineno)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

out = []
hit = False
with open(queue, encoding="utf-8") as fh:
    for n, raw in enumerate(fh, 1):
        if n != lineno:
            # Byte-for-byte, malformed neighbours included — same invariant as resolve.
            out.append(raw.rstrip("\n"))
            continue
        rec = json.loads(raw)
        rec["status"] = "retired"
        rec["push"] = "never"
        rec["retired_at"] = now
        rec["retired_by"] = "ratify-queue.sh"
        rec["retire_reason"] = reason
        # `pending_remotes` is deliberately LEFT AS IT WAS. On a resolve it is cleared
        # because nothing is outstanding any more; here the remotes genuinely never got the
        # merge, and that list IS the evidence of what was written off. `status=retired`
        # already keeps the entry out of every pending view.
        #
        # No verified_sha / resolved_* / verification key is written, ever: those mean "the
        # remote demonstrably carries this", which is precisely what a retire does not claim.
        out.append(json.dumps(rec, ensure_ascii=False))
        hit = True

if not hit:
    raise SystemExit("ERROR: line %d vanished from %s while retiring — queue changed underneath; nothing written" % (lineno, queue))

with open(tmp, "w", encoding="utf-8") as fh:
    for l in out:
        fh.write(l + "\n")
PYEOF
    mv "$tmp" "$QUEUE"
    _flock_release
    printf 'RETIRED %s (%s): closed WITHOUT publishing %s — %s\n' "${ckpt:-$merged}" "$repo" "$merged" "$reason_arg"
    printf '  (the remote does NOT carry this merge; `ratify-queue.sh list --all` shows the entry and this reason)\n'
    exit 0
    ;;

  ""|-h|--help|help)
    # Print the contiguous comment header starting at line 2, however long it grows — a
    # hardcoded line range silently truncated the usage block every time the header did.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    if [ -z "$cmd" ]; then exit "$EX_USAGE"; fi
    exit 0
    ;;

  *)
    die "unknown subcommand '$cmd' (list|show|verify|resolve|retire)"
    ;;
esac
