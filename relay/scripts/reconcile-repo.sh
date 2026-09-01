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

# id:1171 — the orphan→item binding below resolves "an item's OWN id" through the SHARED
# id:46f6/6059 engine rather than a third private definition of it (use-existing-tools).
# Defines functions only; runs nothing.
# shellcheck source=/dev/null
source "$(dirname "$0")/lib-typed-edges.sh"

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

        # SUBMODULE-CARRYING WORKTREES (roadmap:b02f direction (c), REVERSED 2026-09-01 by
        # owner ruling on id:a290). This block USED to `continue` here on `-e .gitmodules`,
        # short-circuiting BEFORE plan_reap/plan_park were populated -- so worktree-retire.sh
        # was NEVER reached from the reap path at all. Only integrate.sh step 9 reached the
        # helper, and only for the one unit it had just integrated, which made every worktree
        # that SURVIVED integrate (handback, crash, abandoned run) permanent debris. That is
        # how 1.8 GB accumulated on yinyang-puzzle.
        #
        # THE PREMISE THE SKIP RESTED ON IS REFUTED, by fixture, twice. b02f recorded that git
        # keys its removal refusal on `.gitmodules` being IN THE TREE. It does not. A worktree
        # with `.gitmodules` present and the gitlink in its index, whose submodule was NEVER
        # INITIALISED, removes CLEANLY and FORCE-FREE (rc=0). The refusal appears only once the
        # submodule is POPULATED, and the state git actually tests is the worktree's PRIVATE
        # submodule store, `<common-git-dir>/worktrees/<name>/modules/<path>`. So the old skip
        # also excluded uninitialised-submodule worktrees that would remove force-free TODAY,
        # with no force op involved and no risk whatsoever.
        #
        # WHAT THIS DOES NOW: nothing is short-circuited. The ordinary merged/unmerged test
        # below plans a reap or a park exactly as it does for any other worktree, and
        # worktree-retire.sh -- the SINGLE place that decides what is safe to remove, which
        # already proves clean AND merged, recognises git's refusal verbatim under LC_ALL=C,
        # and FAILS CLOSED on anything it does not positively recognise -- makes the call.
        # Reconcile's job is to stop pre-empting that decision. The immediate win is the
        # UNINITIALISED case (now disposed of force-free); a POPULATED one is refused by the
        # helper and left untouched on disk, which is still strictly better than a blanket skip
        # because it produces a specific, actionable refusal. NOTE the helper's id:a290 force
        # hatch is OPT-IN (`WORKTREE_RETIRE_SUBMODULE_FORCE=1`) and NO caller here sets it --
        # deliberately, pending a separate owner decision -- so nothing is ever forced.
        #
        # THE MARKER IS PREDICTED, and the predicate is now EXACTLY git's own trigger. git
        # refuses `worktree remove` on the mere EXISTENCE of this worktree's PRIVATE submodule
        # store, `<admin dir>/modules` -- probed directly on git 2.55: an EMPTY `modules/`
        # directory, created by hand in a repo that has NO submodules at all, is refused with
        # the same `fatal: working trees containing submodules cannot be moved or removed`. So
        # `-d "$wt_admin/modules"` is the whole test, and prediction and truth coincide.
        #
        # TWO NARROWER TESTS WERE TRIED HERE AND BOTH UNDER-PREDICTED:
        #   * an outer `-e "$wtdir/$bn/.gitmodules"` gate. A worktree whose submodule WAS
        #     initialised and which was then `git reset --hard` to a commit predating the
        #     submodule keeps its private store but carries no `.gitmodules` in its tree --
        #     realistic for a crashed executor, and reproduced as a fixture. git still refuses
        #     it; the gate skipped the whole block, so nothing was predicted and nothing was
        #     reported anywhere.
        #   * a non-empty `find` on `<admin dir>/modules`. git does not care whether the
        #     directory has any content.
        # PLAN is pure and read-only, so this stays a filesystem read, never a probe.
        #
        # NOT BOUNDED IN BOTH DIRECTIONS -- an earlier version of this comment claimed it was,
        # and that wrong claim is what made the silence look acceptable. A FALSE prediction is
        # genuinely cheap (one extra surfaced line for a worktree that then disposes cleanly).
        # A MISSED prediction was NOT "one refused helper call per round": the reap path's
        # `|| true` swallowed the helper's refusal entirely, so the cost was TOTAL SILENCE.
        # APPLY therefore now also reports from the OUTCOME (the helper's exit status), which
        # is the half that actually guarantees nothing is silent -- a prediction can be wrong,
        # an outcome cannot.
        #
        # ADDITIVE by construction (id:bc49/e7e4): the marker is in discover-repo.sh's ADDITIVE
        # tuple, so it NEVER suppresses the repo. Getting that wrong is the loderite starvation
        # bug -- 6 open actionable [ROUTINE] items, zero dispatched, two rounds -- and it would
        # bite identically here, since the marker fires on EVERY round the worktree exists.
        #
        # A linked worktree's `.git` is a FILE holding `gitdir: <admin dir>`. Under
        # `worktree.useRelativePaths` git writes that path RELATIVE TO THE WORKTREE DIRECTORY
        # (`gitdir: ../../../r/.git/worktrees/<bn>`); resolving it against reconcile's CWD
        # instead yielded a path that does not exist, so every worktree in such a repo silently
        # predicted "retirable". A bare directory that is not a registered worktree has no
        # `.git` file at all -- treat that as retirable.
        wt_admin=""
        if [[ -f "$wtdir/$bn/.git" ]]; then
          wt_admin="$(sed -n '1s/^gitdir: //p' "$wtdir/$bn/.git")"
          [[ -n "$wt_admin" && "$wt_admin" != /* ]] && wt_admin="$wtdir/$bn/$wt_admin"
        fi
        wt_unretirable=false
        [[ -n "$wt_admin" && -d "$wt_admin/modules" ]] && wt_unretirable=true

        branch="relay/$bn"
        if git -C "$path" merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
          if [[ "$wt_unretirable" == true ]]; then
            add_surfaced "unretirable-submodule: worktree $bn carries a private submodule store ($wt_admin/modules), which is the state git actually refuses to remove -- NOT the mere presence of .gitmodules, which roadmap:b02f got wrong. Disposal IS attempted this round through worktree-retire.sh, force-free; the helper refuses and leaves worktree and branch untouched, and APPLY reports that refusal on stderr. Clearing it needs a supervised decision (TODO id:a290), not a cleanup pass -- there is no dirt to find."
          fi
          add_action "reap" "reaped stale empty worktree $bn"
          plan_reap+=("$bn:$branch")
        elif [[ "$wt_unretirable" == true ]]; then
          # NO PARK IS PLANNED for a worktree the helper will refuse (owner-ruled 2026-09-01,
          # id:a290). An UNMERGED worktree carrying a private submodule store -- the
          # handback/crash case this whole change exists for -- used to be planned for a park
          # that can NEVER complete: worktree-retire.sh exits 3 at the worktree step, never
          # reaching branch disposition, so `relay/orphan/$bn` never comes into existence.
          # The consequences compounded: the id:1af1 PARK VERIFY FAILED line fired every round,
          # and the orphan-suppress step bound the PLANNED park and suppressed the item's
          # re-dispatch permanently. Measured against the parent revision: discover-repo.sh
          # yielded 0 units where it had yielded 1. That is the id:e7e4 starvation class
          # arriving by the park route, item-scoped, so a single-item repo goes fully dark.
          #
          # This keys the decision on the PREDICATE rather than on an outcome, and that is a
          # deliberate, bounded choice: PLAN must be pure and the parity oracle (id:77ce)
          # forbids APPLY adding to the emitted JSON, so the park/no-park call can only be made
          # here. It is defensible only because the predicate above is now git's own trigger
          # verbatim. If it ever misses, the failure is the OLD behaviour and stays loud (a
          # park is planned, the helper refuses, PARK VERIFY FAILED fires) -- never silent.
          #
          # ACCEPTED COST, recorded rather than solved (owner's ruling): the partial work stays
          # on disk AND the item stays dispatchable, so a fresh executor may start over an
          # abandoned worktree. That is the status quo, and it was chosen over keeping the
          # suppression because a silent dispatch reduction is the worse failure. Do NOT
          # reintroduce a suppression here in some other form.
          add_surfaced "unretirable-submodule: worktree $bn is UNMERGED and carries a private submodule store ($wt_admin/modules), so worktree-retire.sh cannot complete a park -- it exits at the worktree step and never touches the branch. NO park is planned and no relay/orphan/$bn is announced (it would never exist, and announcing it suppressed this item's re-dispatch permanently -- owner-ruled 2026-09-01, id:a290). Worktree and branch relay/$bn are left exactly as they are and the item stays dispatchable; a fresh executor may therefore start over this abandoned worktree. Disposal needs a supervised decision, not a cleanup pass."
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
      # ANCHORED BINDING (id:1171). These tests used to grep a BARE `id:$oid` substring, so
      # an id merely MENTIONED in some other item's PROSE decided the branch taken. The
      # asymmetry is what made it a defect rather than noise: a false OPEN match is safe
      # (we suppress, cost = one manual glance), but a false CLOSED match silently
      # suppresses NOTHING — the starvation class id:a360 exists to prevent. Measured on
      # post-fix main: a repo-scoped orphan (`…-execute-repo-0`, no item in its ref name, so
      # the commit-message fallback is its only path) naming id:d050, with d050 occurring
      # only inside a closed `- [x]` body, produced `surfaced: []`.
      #
      # An item's OWN id is resolved by the SHARED id:46f6/6059 engine
      # (typed_edges_own_id_of_line), NOT a third private rule. That engine no longer picks
      # positionally: `<!-- id:X -->` means both "this line IS X" and "this line REFERS to
      # X", so a line carrying SEVERAL anchored markers resolves to NOTHING and says so on
      # stderr. Here that lands in the ambiguous⇒suppress branch below — the safe side.
      # (md-merge.py's _own_id_of_line raises AmbiguousOwnId for the same shape; the two
      # agree. The FIRST-vs-LAST divergence recorded under id:cc7e was closed by id:6059.)
      #
      # The grep is only a cheap CANDIDATE prefilter (checkbox line carrying the anchored
      # marker); the engine decides. Unchanged: the union is live ∪ archive with
      # OPEN-ANYWHERE-WINS (open is tested first, across both files), `- [x]` anywhere means
      # closed ⇒ do NOT suppress (the routed:42c9/8b21 archive-blindness fix), and anything
      # unresolvable defaults to suppress.
      open_hit=false; closed_hit=false
      __open_re='^[[:space:]]*- \[ \]'
      __closed_re='^[[:space:]]*- \[x\]'
      while IFS= read -r __line; do
        [[ -n "$__line" ]] || continue
        [[ "$(typed_edges_own_id_of_line "$__line")" == "$oid" ]] || continue
        if   [[ "$__line" =~ $__open_re   ]]; then open_hit=true
        elif [[ "$__line" =~ $__closed_re ]]; then closed_hit=true
        fi
      done < <(grep -hE "^[[:space:]]*- \[[ x]\].*<!-- id:$oid -->" "${roadmap_set[@]}" || true)
      if [[ "$open_hit" == true ]]; then
        suppress=true; why="parked partial work for id:$oid still OPEN"
      elif [[ "$closed_hit" == true ]]; then
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
      #
      # REPORT FROM THE OUTCOME (id:a290). This call used to end `>/dev/null 2>&1 || true`,
      # justified as "the helper logs to its own log". It does -- to a file nobody reads -- so
      # a non-zero exit here was TOTAL SILENCE, not the "one refused call per round" the PLAN
      # comment claimed. That is what let a missed prediction disappear completely. A
      # prediction can be wrong; an outcome cannot, so the helper's own exit status is the
      # thing that guarantees nothing is silent. Same discipline as the park verify below:
      # stderr + the reconcile log ONLY, never actions/surfaced, so parity (id:77ce) holds.
      retire_rc=0
      retire_out="$("$RETIRE" "$path" "$wtdir/$bn" "$branch" --expect-merged 2>&1)" || retire_rc=$?
      if (( retire_rc != 0 )); then
        echo "reconcile-repo: REAP RETIRE FAILED -- worktree-retire.sh exited $retire_rc for the planned reap of worktree $bn (repo=$repo, branch=$branch). The worktree and/or its branch were NOT disposed of and are still on disk. Helper said: ${retire_out//$'\n'/ } (id:a290)" >&2
        printf '%s reconcile-repo reap-retire-failed repo=%s branch=%s worktree=%s rc=%s\n' \
          "$(date -Is)" "$repo" "$branch" "$bn" "$retire_rc" >> "${RECONCILE_LOG:-$HOME/.claude/logs/relay-reconcile.log}" 2>/dev/null || true
      fi
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
