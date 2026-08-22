#!/usr/bin/env bash
# relay/scripts/reconcile-repo.sh — bounded side-effecting git reconciliation
# split out of the LLM discovery shard (flip step b, id:a0b6).
#
# Usage: reconcile-repo.sh [--dry-run] --repo <name> --path <abs> [--runid <id>]
#                          [--live-claims <comma-list>] [--main-branch <name>]
#
# Performs ONLY the bounded git ops the shard prose describes
# (relay-loop.js:854-870): SYNC-WITH-ORIGIN (id:c3f7), uv.lock cascade
# commit (id:bae5), and WORKTREE-AWARE reap/park (id:ebfb/3ac8/689c).
# NO classification (that stays classify-repo.sh / classify-verdict.sh).
#
# Architecture (id:77ce, parity oracle for relay-core ebdb-b): the body is
# split into a pure PLAN phase (read-only git observations → an actions/
# surfaced list, zero mutating git calls) and a thin APPLY phase (walks the
# planned action list and performs the mutation for each kind). `--dry-run`
# runs PLAN, emits the SAME JSON, and STOPS before APPLY — no git write
# happens. Without `--dry-run`, PLAN -> APPLY -> emit (identical observable
# behavior to the pre-split script). The `actions`/`surfaced` lists for a
# given input state are IDENTICAL with and without `--dry-run` — that
# identity is the parity oracle.
#
# Emits ONE JSON object on stdout:
#   {"repo":"<name>","actions":[{"kind":"<k>","detail":"<...>"}],"surfaced":[{"repo","reason"}]}
#   kind ∈ {ff-merge, diverged-surface, lock-commit, reap, park, suppress}
#
# Env overrides (hermetic tests):
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

repo="" path="" runid="" main_branch=""   # empty ⇒ resolve from HEAD via trunk-branch.sh
# live_claims (id:e3ad fail-closed reap guard, tri-state sum type — id:77ce): bash has
# no Option/sum type, so the three LiveClaims states are modelled as ONE sentinel-bearing
# variable instead of the previous {live_claims_provided bool, live_claims string} PAIR
# (that pair is exactly "the cost of modelling Option as a bool default", id:e3ad):
#   __UNSET__  (default)        → Unknown:   flag never passed, no caller safety context
#   ""         (--live-claims "") → Known-empty: caller checked, nothing is live
#   "a,b"      (--live-claims "a,b") → Known:  caller's live-claimed repo set
# Only the Unknown state fail-closed-refuses every destructive reap/park; the other two
# states differ only in whether $repo appears in the (possibly empty) comma-list.
live_claims="__UNSET__"
dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "reconcile-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "reconcile-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "reconcile-repo.sh: --path is required" >&2; exit 2; }

# Integration/trunk branch — the reap/park ancestry test (below) MUST compare against the
# branch children actually fork from, not a hardcoded `main`. When --main-branch is absent
# or empty, resolve it from the repo's checked-out HEAD via the single-source trunk-branch.sh
# (a repo on `claude/opusplan` with `main` frozen would otherwise mis-park every worktree).
if [[ -z "$main_branch" ]]; then
  main_branch="$("$(dirname "$0")/trunk-branch.sh" "$path")"
fi

WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"

# actions/surfaced accumulated as TSV lines, folded into JSON by python3 at the end.
actions_file="$(mktemp)"
surfaced_file="$(mktemp)"
trap 'rm -- "$actions_file" "$surfaced_file"' EXIT   # both mktemp'd just above ⇒ known to exist; no -f needed

add_action() { # <kind> <detail>
  printf '%s\t%s\n' "$1" "$2" >> "$actions_file"
}
add_surfaced() { # <reason>
  printf '%s\n' "$1" >> "$surfaced_file"
}

# --- PLAN outputs consumed by APPLY (kept minimal: what to mutate, not why) -
plan_ff_upstream=""            # non-empty ⇒ APPLY should `git merge --ff-only <upstream>`
plan_lock_paths=()             # non-empty ⇒ APPLY should add+commit these uv.lock paths
plan_reap=()                   # "<basename>:<branch>" entries ⇒ APPLY should reap
plan_park=()                   # "<basename>:<branch>" entries ⇒ APPLY should park
wtdir="$WORKTREE_BASE/$repo"

if [[ -d "$path/.git" || -f "$path/.git" ]]; then

  # ============================ PLAN (pure, read-only) ======================

  # --- PLAN: SYNC (id:c3f7) --------------------------------------------------
  if git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git -C "$path" fetch origin >/dev/null 2>&1 || true
    upstream="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
    ahead="$(git -C "$path" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
    behind="$(git -C "$path" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
    porcelain="$(git -C "$path" status --porcelain)"

    if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
      add_action "diverged-surface" "local ahead $ahead / behind $behind vs origin"
      add_surfaced "diverged from origin (local $ahead / origin $behind) — needs manual reconcile (id:c3f7)"
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 && -z "$porcelain" ]]; then
      add_action "ff-merge" "fast-forwarded to $upstream"
      plan_ff_upstream="$upstream"
    fi
  fi

  # --- PLAN: LOCK (id:bae5) --------------------------------------------------
  # Plan an in-place uv.lock relock commit when EVERY dirty path is a uv.lock
  # (basename), covering the zkm cascade's nested plugins/*/uv.lock — not just
  # a root uv.lock. Any non-lock dirty path leaves the tree for classify to
  # `block`. NOTE: `ff-merge` above only plans (does not perform) the merge,
  # and only does so when the tree was already clean, so this porcelain read
  # observes the same state PLAN or APPLY would act on.
  porcelain="$(git -C "$path" status --porcelain)"
  if [[ -n "$porcelain" ]]; then
    all_lock=true
    lock_paths=()
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      p="${line:3}"                      # strip the "XY " porcelain status prefix
      if [[ "$(basename "$p")" == "uv.lock" ]]; then
        lock_paths+=("$p")
      else
        all_lock=false; break
      fi
    done <<< "$porcelain"
    if [[ "$all_lock" == true && ${#lock_paths[@]} -gt 0 ]]; then
      add_action "lock-commit" "committed uv.lock relock in place (${#lock_paths[@]} lock file(s))"
      plan_lock_paths=("${lock_paths[@]}")
    fi
  fi

  # --- PLAN: WORKTREE reap/park (id:ebfb/3ac8/689c) --------------------------
  if [[ -d "$wtdir" ]]; then
    if [[ "$live_claims" == "__UNSET__" ]]; then
      # --- FAIL-CLOSED GUARD (id:e3ad) --------------------------------------
      # No --live-claims flag was passed at all: the caller supplied NO safety
      # context, so we cannot tell live worktrees apart from stale ones. Refuse
      # every destructive reap/park in this repo and surface loudly instead —
      # this is strictly additive: the live loop (relay-loop.js -> discover-repo.sh)
      # ALWAYS passes --live-claims (even "" when nothing is live), so it never
      # hits this branch; only a caller that forgot the flag does.
      while IFS= read -r bn; do
        [[ -n "$bn" ]] || continue
        [[ -n "$runid" && "$bn" == "$runid"* ]] && continue
        msg="REFUSED reap/park of worktree $bn: --live-claims was not provided (no safety context) — fail-closed guard (id:e3ad)"
        echo "reconcile-repo.sh: WARNING: $msg" >&2
        add_surfaced "$msg"
      done < <(ls -1 "$wtdir" 2>/dev/null || true)
    else
      IFS=',' read -r -a claims_arr <<< "$live_claims"
      is_live_claimed=false
      for c in "${claims_arr[@]:-}"; do
        [[ -n "$c" && "$c" == "$repo" ]] && is_live_claimed=true
      done

      while IFS= read -r bn; do
        [[ -n "$bn" ]] || continue
        [[ -n "$runid" && "$bn" == "$runid"* ]] && continue

        if [[ "$is_live_claimed" == true ]]; then
          add_surfaced "in-flight elsewhere (worktree $bn) — claimed by another relay run (id:ebfb)"
          continue
        fi

        branch="relay/$bn"
        if git -C "$path" merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
          add_action "reap" "reaped stale empty worktree $bn"
          plan_reap+=("$bn:$branch")
        else
          add_action "park" "parked stale worktree $bn to relay/orphan/$bn"
          # id:1af1 — PLAN must not assert a COMPLETED rename. This line is emitted in the PLAN
          # phase (before APPLY runs, and at all in --dry-run), so the old wording "ref renamed
          # to relay/orphan/$bn" stated as fact something that had not happened and, if APPLY
          # failed or never ran, never would — the 2026-07-28 phantom-park incident, where the
          # surface named a ref that did not exist and idled the pool with 0 dispatched.
          # Parity (id:77ce) forbids APPLY adding to this JSON, so the fix is tense, not timing:
          # state the INTENT here; APPLY verifies the outcome on stderr/log (see the park loop).
          # id:e7e4 — CLASS MARKER prefix. This line used to start with the bare prose "stale
          # worktree …", which discover-repo.sh's class dispatcher could only read as "not
          # orphan-suppress" ⇒ SUBSTITUTIVE ⇒ units:[] — so a repo whose ONLY problem was a
          # dead run's leftover worktree was silently starved even while classifying `execute`
          # (loderite, runs relay-20260820-180056-4594 + relay-20260821-174757-32436: 6 open
          # actionable [ROUTINE] items, zero dispatched, two rounds running). A planned park IS
          # the D1 "parked orphan" (meeting 2026-07-23, id:bc49/7e87), which is ADDITIVE surface,
          # never repo-scoped suppression — the marker is what lets the dispatcher say so. The
          # item-scoped half is handled below: the suppress step now also binds PLANNED parks.
          add_surfaced "parked-orphan (planned): stale worktree $bn from a dead run — to be parked as relay/orphan/$bn for manual /relay reconcile (id:689c); verify the ref exists before acting on it"
          plan_park+=("$bn:$branch")
        fi
      done < <(ls -1 "$wtdir" 2>/dev/null || true)
    fi
  fi

  # --- PLAN: ORPHAN SUPPRESS-REDISPATCH (id:1f53, read-only, no APPLY step) --
  # Once D1 parks partial work into relay/orphan/*, do NOT re-dispatch the item's expensive
  # session. Bind each parked orphan back to its ROADMAP item via `git show --stat` on the
  # parked commit; if that item is still OPEN (or the binding is ambiguous), SURFACE a one-line
  # relay-burn cost hint (which makes discover-repo.sh skip classify → no fresh dispatch). A
  # CLOSED-item orphan does NOT suppress (stale leftover — let it classify; /relay reconcile prunes).
  # routed:42c9/8b21 ARCHIVE-BLINDNESS class: the binding must read ROADMAP.archive.md too.
  # `roadmap-archive.sh` sweeps shipped `- [x]` items out of the live file, so a DONE item
  # used to fall into the third branch below ("item not in ROADMAP — ambiguous") and its
  # stale orphan suppressed re-dispatch FOREVER — discover-repo.sh then skips classify and
  # the repo silently stalls.
  #
  # PRECEDENCE — deliberately NOT the live-first rule resolve-gates.sh uses. The greps below
  # run across BOTH files, so the semantics is OPEN-ANYWHERE-WINS: an id that is `- [x]` live
  # but `- [ ]` in the archive SUPPRESSES. That is intentional and matches this step's stated
  # bias two paragraphs up ("Ambiguous binding defaults to suppress — a glance is cheaper than
  # repeating an expensive session"): the two scripts answer different questions. resolve-gates
  # computes a TRUTH VALUE about closure, where the live ledger is current state and the
  # archive is history, so live must win. This step makes a COST-ASYMMETRIC safety call, where
  # the penalty for wrongly suppressing is one manual glance and the penalty for wrongly
  # re-dispatching is a repeated expensive session — so any sign of openness wins.
  # Membership in the archive is NOT closure either: the `- [x]` / `- [ ]` tests are unchanged,
  # so an archived parent nesting an open sub-item still suppresses.
  roadmap="$path/ROADMAP.md"
  roadmap_archive="$path/ROADMAP.archive.md"
  while IFS= read -r oref; do
    [[ -n "$oref" ]] || continue
    # BRANCH NAME first, commit message only as a FALLBACK (defect found live on loderite
    # 2026-08-22, upstream of id:a360). The ref name is the AUTHORITATIVE encoding of the item:
    # worktree-retire.sh parks as relay/orphan/$(basename <worktree-dir>) and the worktree dir is
    # relay-loop.js's `${runId}-${unitKey}` with unitKey = "<verdict>-<itemId|repo>-<attempt>",
    # so the item sits in a fixed, parseable position. The commit MESSAGE does not: a
    # commit-and-park residue commit is written by the PARKING MECHANISM, and its only `id:`
    # token is the mechanism's own — e.g. "chore(relay): WIP UNVERIFIED residue auto-commit for
    # worktree relay-20260820-180056-4594-execute-57d1-0 (id:f272 commit-and-park; …)". The
    # message-only derivation therefore bound that orphan to f272; id:57d1 never reached
    # discover-repo.sh's suppressed_item_ids, relay-loop.js's namedItemsFor (id:b09e) could not
    # subtract it, and it was selected anyway — whereupon the id:dd7d guard, which binds by
    # BRANCH NAME through stranded-branch-scan.sh and therefore DID see it, starved the repo for
    # three consecutive runs (id:a360). Both mechanisms now use the same key. Note this is
    # precisely the class where the binding matters most: a residue commit is what an executor
    # dying mid-work produces.
    # The FALLBACK is load-bearing, not defensive: a repo-scoped unit's unitKey is
    # "<verdict>-repo-<attempt>" and encodes NO item, so those refs must keep binding via the
    # message exactly as before — as must a hand-renamed orphan (dd7d trap (ii)).
    oid="$(sed -nE 's/.*-[a-z]+-([0-9a-f]{4})-[0-9]+$/\1/p' <<<"${oref##*/}")"
    [[ -n "$oid" ]] || oid="$(head -1 < <(git -C "$path" show --stat "$oref" 2>/dev/null | grep -oE 'id:[0-9a-f]{4}') | sed 's/id://' || true)"
    suppress=false; why=""
    if [[ -n "$oid" && -f "$roadmap" ]]; then
      # ROADMAP union = live ∪ archive, OPEN-ANYWHERE-WINS (see the precedence note above —
      # this is not resolve-gates.sh's live-first rule, and the difference is deliberate).
      # A missing ROADMAP.archive.md is a normal state, so it is passed only when present
      # rather than swallowed with `2>/dev/null`.
      roadmap_set=("$roadmap")
      [[ -f "$roadmap_archive" ]] && roadmap_set+=("$roadmap_archive")
      if grep -qE "^[[:space:]]*- \[ \].*id:$oid" "${roadmap_set[@]}"; then
        suppress=true; why="parked partial work for id:$oid still OPEN"
      elif grep -qE "^[[:space:]]*- \[x\].*id:$oid" "${roadmap_set[@]}"; then
        suppress=false   # closed (live OR archived) → stale orphan, do not suppress
      else
        suppress=true; why="parked partial work for id:$oid (item not in ROADMAP — ambiguous)"
      fi
    else
      suppress=true; why="parked partial work on $oref (no id binding — ambiguous)"
    fi
    if [[ "$suppress" == true ]]; then
      add_action "suppress" "$why"
      add_surfaced "suppressed re-dispatch: $why on $oref — manual /relay reconcile; cost hint: relay-burn.sh --run ${runid:-<runId>}"
    fi
  done < <( { git -C "$path" for-each-ref --format='%(refname:short)' refs/heads/relay/orphan/ 2>/dev/null || true
              # id:e7e4 — a PLANNED park (this round's plan_park) is evaluated by the SAME
              # item-binding rule as an already-parked orphan. Without this, the round in which
              # a park is planned would have no item-scoped guard at all: the park surface is
              # now ADDITIVE (see the marker above), so classify runs, and the just-parked item
              # could be re-dispatched to a second expensive session. Binding it here makes this
              # round behave exactly like the NEXT round would (when the ref lives under
              # relay/orphan/). The ref is named by its CURRENT name (relay/<bn>) — honest tense
              # per id:1af1: the rename has not happened yet and may fail.
              for __pp in "${plan_park[@]:-}"; do
                [[ -n "$__pp" ]] || continue
                printf '%s\n' "${__pp#*:}"
              done
            } )

  # ============================ APPLY (mutating) =============================
  if [[ "$dry_run" -eq 0 ]]; then
    if [[ -n "$plan_ff_upstream" ]]; then
      git -C "$path" merge --ff-only "$plan_ff_upstream" >/dev/null 2>&1
    fi
    if [[ ${#plan_lock_paths[@]} -gt 0 ]]; then
      git -C "$path" add -- "${plan_lock_paths[@]}"
      git -C "$path" commit -q -m "chore: refresh uv.lock — cascade relock (id:bae5)"
    fi
    # FORCE-FREE retirement (id:373e): all reap/park worktree+branch disposal goes through
    # worktree-retire.sh — NO `git worktree remove --force`, NO `git branch -D`. The helper
    # removes a CLEAN worktree (executor committed per contract; gitignored residue does not
    # block) and either deletes a merged branch or PARKS an unmerged one to relay/orphan/<bn>.
    # A dirty/unremovable worktree is SURFACED and LEFT on disk for a supervised reconcile —
    # never force-cleaned. The helper logs+surfaces internally; APPLY must add nothing to the
    # emitted actions/surfaced JSON (parity oracle id:77ce), so its output is discarded here.
    RETIRE="$(dirname "$0")/worktree-retire.sh"
    for entry in "${plan_reap[@]:-}"; do
      [[ -n "$entry" ]] || continue
      bn="${entry%%:*}"; branch="${entry#*:}"
      # Reap: PLAN proved the branch is an ancestor of main (merged) → --expect-merged so a
      # `branch -d` refusal surfaces as an anomaly instead of a silent park.
      "$RETIRE" "$path" "$wtdir/$bn" "$branch" --expect-merged >/dev/null 2>&1 || true  # swallow-ok: helper logs+surfaces to its own log; APPLY stays JSON-side-effect-free (id:77ce)
    done
    for entry in "${plan_park[@]:-}"; do
      [[ -n "$entry" ]] || continue
      bn="${entry%%:*}"; branch="${entry#*:}"
      # Park: PLAN found the branch unmerged → the helper removes the clean worktree then
      # renames the unmerged branch to relay/orphan/<bn> (via `branch -d`-refusal fallthrough).
      "$RETIRE" "$path" "$wtdir/$bn" "$branch" >/dev/null 2>&1 || true  # swallow-ok: see reap note (id:77ce)
      # id:1af1 — VERIFY the park actually happened. The `|| true` above is required by the
      # parity oracle (APPLY must stay JSON-side-effect-free, id:77ce), but silently swallowing
      # a failed rename is what let a PLAN-phase claim outlive the action it described: the
      # surface named relay/orphan/<bn>, the ref never existed, and the pool idled
      # `blocked-pending-human` with 0 dispatched (2026-07-28, run relay-20260728-111835-4075).
      # Verification writes ONLY to stderr + the log — never to actions/surfaced — so parity is
      # preserved while the failure stops being silent (no-silent-swallow, memory
      # `no-swallow-stderr` / id:4347).
      if ! git -C "$path" show-ref --verify --quiet "refs/heads/relay/orphan/$bn"; then
        echo "reconcile-repo: PARK VERIFY FAILED — planned relay/orphan/$bn does NOT exist after APPLY (repo=$repo, worktree=$bn). The surfaced park line names a ref that is not there; do NOT treat it as a real orphan. Investigate worktree-retire.sh for this branch. (id:1af1)" >&2
        printf '%s reconcile-repo park-verify-failed repo=%s branch=%s expected_ref=relay/orphan/%s\n' \
          "$(date -Is)" "$repo" "$branch" "$bn" >> "${RECONCILE_LOG:-$HOME/.claude/logs/relay-reconcile.log}" 2>/dev/null || true
      fi
    done
  fi
fi

ACTIONS_FILE="$actions_file" SURFACED_FILE="$surfaced_file" REPO="$repo" python3 - <<'PYEOF'
import json, os

repo = os.environ["REPO"]

actions = []
with open(os.environ["ACTIONS_FILE"]) as f:
    for ln in f:
        ln = ln.rstrip("\n")
        if not ln:
            continue
        kind, detail = ln.split("\t", 1)
        actions.append({"kind": kind, "detail": detail})

surfaced = []
with open(os.environ["SURFACED_FILE"]) as f:
    for ln in f:
        ln = ln.rstrip("\n")
        if not ln:
            continue
        surfaced.append({"repo": repo, "reason": ln})

print(json.dumps({"repo": repo, "actions": actions, "surfaced": surfaced}))
PYEOF
