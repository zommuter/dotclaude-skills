#!/usr/bin/env bash
# integrate.sh — standalone MECHANICAL relay integrator (seam of id:a955, id:9e50).
#
# WHY THIS EXISTS: the relay integrator was an ~11-step Sonnet AGENT prompt inside
# relay-loop.js integrate() (~2696-2909). Every step is DETERMINISTIC — release the
# lease, gate the tree, verify isolation, sync, merge --no-ff, bump, changelog, tag,
# push, retire, write state — so it belongs in a fail-closed shell script, not an LLM
# turn on the merge-to-main critical path. id:9e50 built the deterministic core; id:087b
# (owner rulings D1/D2, 2026-08-20) ported the FIVE remaining LLM-only behaviours in here
# too, so NO LLM micro-hop survives on the integration path. relay-loop.js now dispatches
# this script through the id:6176 mechanical (`relay-mech`) hop.
#
# It runs these deterministic steps, in order:
#   0. lease-release   (best-effort; the child's work is done)
#   1. clean-tree gate (id:aa93 — FAIL-CLOSED before any mutation; NEVER force-clean)
#   2. verify-isolation(id:f682/7612 — worktree really carried the work)
#   3. sync-origin     (id:c3f7 — never checkpoint on a diverged base)
#   3b. sibling-branch SURFACING (id:dd7d/15d2 — port #5). Observe-only: it never picks a
#       winner and never blocks the merge; the unit's OWN branch line is dropped and any
#       remaining line is recorded VERBATIM on stdout as `sibling=<line>`.
#   3c. BUMP-TRIGGER resolution (id:e647 — port of the one residual reviewer judgement).
#       Resolved BEFORE any mutation so an unresolvable trigger defers with main unmoved.
#   4. merge --no-ff   (conflict => abort, main unmoved). The id:8e3e/id:25aa `-c` anchor is
#      DERIVED here, not judged: HEAD unmoved ("Already up to date") => zero-commit case =>
#      anchor on the reviewed branch tip; HEAD moved => the branch carried commits => NO `-c`
#      so ckpt-tag anchors on the POST-MERGE tip that contains them.
#   4b. ROADMAP tick   (id:5b12 — port #1; execute/hard only, scoped commit)
#   5. version-bump    (SemVer, level from step 3c)
#   6. changelog-append(id:b8fa)
#   6b. roadmap-archive(id:f54d — port #2; scoped commit of ROADMAP.md + ROADMAP.archive.md)
#   7. ckpt-tag        (id:1a34 label; -c reviewed-tip for the zero-commit case)
#   8. git-lock-push   (--ff-only; the only network step)
#   9. worktree-retire (id:373e force-free; id:6e02 scope = EXACTLY this unit's pair)
#  10. state-write     (id:ebfb flock'd relay.toml single-writer)
#  10b. durable Fable-recheck keys (id:e030 — port #3). STRONG (verdict != execute) writes
#       last_strong_ckpt/strong_model/fable_rechecked; an EXECUTE (sonnet) checkpoint must
#       NEVER touch those three keys — that IS the id:e030 masking bug.
#  11. L2 push-seed inputs (id:c855 — port #4). Computed LAST, after 1-10, so postSig /
#      openRoutine / openHard reflect the settled post-integrate state.
#
# ── id:aa93 ENFORCED IN-SCRIPT, not documented ──────────────────────────────────────
# The clean-tree gate is step 1 and its non-zero exit HANDS BACK before ANY merge, tag,
# push, retire, or state write runs. This script contains NO `git stash`, `git checkout
# --`, `git reset --hard`, or `git clean` ANYWHERE — a foreign-dirty main is DEFERRED,
# never force-cleaned. The enforcement IS the ordering + the total absence of those ops,
# proven by tests/test_integrate_sh_mechanized.sh (a foreign-dirty file survives byte-for
# -byte and no merge lands), not by this comment.
#
# ── id:6e02 ENFORCED IN-SCRIPT ──────────────────────────────────────────────────────
# worktree-retire is invoked with EXACTLY the one <worktree> + <branch> passed on the
# command line — no globbing, no discovery, no "tidy other relay/*". A parallel child's
# worktree is never touched.
#
# ── SCOPED-STAGING INVARIANT (id:debf — never scoop a concurrent ledger edit) ───────
# The child's work is integrated EXCLUSIVELY by the committed-branch `git merge --no-ff` in
# step 4, which brings in ONLY the commits already on the branch and stages nothing from the
# working tree. This script therefore contains NO `git add -A`, `git add .`, `git add -u` or
# `git add --all` in any code line: every staging call is `git add -- <exact path>`. A
# `/meeting` or `/relay human` session may be writing a ledger file (TODO/ROADMAP/REVIEW_ME)
# in the main checkout concurrently — those writes are flock-protected, NOT lease-protected
# (id:c144) — and a broad `git add` would capture that uncommitted foreign edit into this
# pool checkpoint commit (the scoop window, id:3558). The step-1 clean-tree gate already
# DEFERS on a foreign-dirty tree; scoped staging closes the rest.
#
# ── FAIL-CLOSED, LOUD, DISTINCT EXITS ───────────────────────────────────────────────
# Each step maps its own failure to a DISTINCT non-zero exit code and prints a loud
# HANDBACK[<step>] line to stderr. The caller records it durably and does not re-merge.
#
# ── THE ONE RESIDUAL: the SEMVER BUMP TRIGGER (id:e647) ─────────────────────────────
# "One bump per USER-OBSERVABLE close; a refactor-only / internal-cleanup close does NOT
# bump" is a ratified REVIEWER judgement (meeting 2026-07-17-1541 D1). It is NOT derivable,
# so this script never guesses it. Resolution order — the FIRST match wins:
#   1. --level minor|patch      → the caller judged it user-observable. Bump at that level.
#   2. --no-bump                → the caller judged it refactor-only. No bump.
#   3. no versioned manifest    → a VERSION-LESS repo (dotclaude-skills by design, id:8ef3):
#                                 there is nothing to bump. No bump; the changelog
#                                 date-buckets instead. version-bump.sh is a no-op here.
#   4. --substantive false      → the unit produced no substantive close (relay-loop.js's
#                                 unitIsSubstantive), so it cannot be a user-observable one.
#                                 No bump.
#   5. relay.toml bump_policy   → [repos.<repo>] bump_policy = never|minor|patch, a durable
#                                 per-repo standing judgement the owner records ONCE.
#   6. otherwise                → UNDETERMINABLE. HANDBACK[bump] (exit 30), LOUD, BEFORE any
#                                 mutation. NEVER a silent bump; NEVER a silent skip.
# Resolution happens pre-merge on purpose: a deferred repo is left byte-identical.
#
# Usage:
#   integrate.sh --repo <name> --path <main-checkout> --worktree <dir> --branch <branch> \
#                --summary <text> --run <runId> --label <ckpt-label> \
#                [--ids a,b] [--level minor|patch] [--no-bump] [--substantive true|false] \
#                [--reviewed-tip <sha>] [--verdict execute|hard|review|handoff] \
#                [--intensive <resource>] [--strong-model <id>] [--fable-recheck] \
#                [--chain-ended]
#
# Output contract (stdout, one KEY=VALUE per line — parsed by relay-loop.js integrate()):
#   merged=<sha>  ckpt=<tag>  push=pushed  ts=<ISO>  bump=<vX.Y.Z|>  retire=<note>
#   postSig=<hex|>  openRoutine=<n>  openHard=<n>  sibling=<branch>\t<count>  (0..n lines)
#
# Handback contract (STDERR, id:5fe2 — stdout is discarded by the proxy on a non-zero exit):
#   PRE-push  exits: handback=<step>  landed=false                      (safe to retry)
#   POST-push exits: handback=<step>  landed=true  merged=<sha>  ckpt=<tag>  push=pushed
#                    remaining=<steps that did NOT run>  ckptRecorded=<true|false>
#   A `merged=` line NEVER appears on a pre-push exit — that is the whole discriminator.
#
# Helper resolution (all overridable for hermetic tests — the failure-injection seam):
#   INTEGRATE_CLAIM INTEGRATE_CLEAN_TREE_GATE INTEGRATE_VERIFY_ISOLATION
#   INTEGRATE_SYNC_ORIGIN INTEGRATE_VERSION_BUMP INTEGRATE_CHANGELOG_APPEND
#   INTEGRATE_CKPT_TAG INTEGRATE_GIT_LOCK_PUSH INTEGRATE_WORKTREE_RETIRE
#   INTEGRATE_STATE_WRITE INTEGRATE_ROADMAP_TICK INTEGRATE_ROADMAP_ARCHIVE
#   INTEGRATE_STRANDED_SCAN INTEGRATE_DISCOVER_SIG
set -euo pipefail

# ── distinct exit codes (per step) ──
EX_USAGE=2
EX_CLEAN_TREE=20
EX_ISOLATION=21
EX_SYNC=22
EX_MERGE=23
EX_VERSION=24
EX_CHANGELOG=25
EX_CKPT=26
EX_PUSH=27
EX_RETIRE=28
EX_STATE=29
# ── id:087b: one distinct code per NEWLY PORTED step ──
EX_BUMP=30          # the bump trigger could not be resolved (the one residual judgement)
EX_TICK=31          # roadmap-tick.sh failed, or its scoped commit failed
EX_ARCHIVE=32       # roadmap-archive.sh failed, or its scoped commit failed
EX_STRONG=33        # the durable Fable-recheck keys (id:e030) could not be written
EX_WIRING=34        # a required helper is missing/not executable (a wiring bug, not a
                    # scan failure — see the fail-open note on steps 3b/11 below)

LOG="${INTEGRATE_LOG:-$HOME/.claude/logs/relay-integrate.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log()  { printf '%s integrate.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }
# ── id:5fe2 — DEFERRED vs LANDED-BUT-UNFINISHED ─────────────────────────────────────
# The push at step 8 splits every handback into two classes the caller MUST tell apart:
#   • PRE-push  — the remote is untouched, so re-running the whole script is CORRECT.
#     (isolation, sync, wiring, bump, merge, tick, version, changelog, archive, ckpt —
#     AND push itself: exit 27 means the push FAILED, so the remote never moved.)
#   • POST-push — the merge is committed, TAGGED and PUSHED; only a tail step failed
#     (retire, state-write, strong-state). Re-running is WRONG: the retry fails forever
#     at merge/isolation while `relay.toml last_ckpt` stays stale and the completion
#     never reaches state.completed/CHANGELOG. Such a unit must be SURFACED for
#     completion, never re-merged.
# These three variables are the class discriminator; `pushed` is set ONLY after step 8
# returns 0, so the PRE-push half cannot accidentally advertise a landed merge.
merged_head="" ckpt_tag="" pushed=""
# The KEY=VALUE handback block goes to STDERR on purpose: mechanical-proxy.py DISCARDS a
# non-zero-exit child's stdout and returns 'MECH-ERROR exit=<n>\n<stderr>', so stdout would
# never reach parseIntegrateResult. stdout stays the SUCCESS-only contract.
# LOUD handback: name the step, print the reason to stderr, log it, exit with the step's
# distinct code. Never swallowed.
handback() { # <step-label> <exit-code> <reason...>
  local step="$1" code="$2"; shift 2
  printf 'integrate.sh: HANDBACK[%s]: %s\n' "$step" "$*" >&2
  log "HANDBACK[$step] exit=$code $*"
  if [ -n "$pushed" ]; then
    # Which tail steps did NOT run — the operator is told EXACTLY, never left to guess.
    local remaining
    case "$step" in
      worktree-retire) remaining="worktree-retire,state-write,strong-state,push-seed" ;;
      state-write)     remaining="state-write,strong-state,push-seed" ;;
      strong-state)    remaining="strong-state,push-seed" ;;
      *)               remaining="UNKNOWN post-push step '$step' — treat every tail step as unrun" ;;
    esac
    # Best-effort reconcile of the ONE piece of durable state whose staleness is the
    # observed symptom: relay.toml last_ckpt must not silently disagree with the remote,
    # which already carries $ckpt_tag. Idempotent; failure is REPORTED, never swallowed.
    local recorded=false
    if [ -n "$ckpt_tag" ] && "$STATE_WRITE" toml-set "$repo" last_ckpt "\"$ckpt_tag\"" >/dev/null 2>&1; then
      recorded=true
      log "HANDBACK[$step] id:5fe2 post-push reconcile: relay.toml last_ckpt set to $ckpt_tag"
    else
      log "HANDBACK[$step] id:5fe2 post-push reconcile FAILED — relay.toml last_ckpt may be STALE vs the pushed $ckpt_tag"
    fi
    {
      printf 'handback=%s\n'     "$step"
      printf 'landed=%s\n'       'true'
      printf 'merged=%s\n'       "$merged_head"
      printf 'ckpt=%s\n'         "$ckpt_tag"
      printf 'push=%s\n'         'pushed'
      printf 'remaining=%s\n'    "$remaining"
      printf 'ckptRecorded=%s\n' "$recorded"
    } >&2
  else
    { printf 'handback=%s\n' "$step"; printf 'landed=%s\n' 'false'; } >&2
  fi
  exit "$code"
}

# ── helper resolution ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # relay/scripts → repo root (dotclaude-skills)
CLAIM="${INTEGRATE_CLAIM:-$SCRIPT_DIR/claim.sh}"
CLEAN_TREE="${INTEGRATE_CLEAN_TREE_GATE:-$SCRIPT_DIR/clean-tree-gate.sh}"
VERIFY_ISO="${INTEGRATE_VERIFY_ISOLATION:-$SCRIPT_DIR/verify-isolation.sh}"
SYNC_ORIGIN="${INTEGRATE_SYNC_ORIGIN:-$SCRIPT_DIR/sync-origin.sh}"
VERSION_BUMP="${INTEGRATE_VERSION_BUMP:-$SCRIPT_DIR/version-bump.sh}"
CHANGELOG="${INTEGRATE_CHANGELOG_APPEND:-$SCRIPT_DIR/changelog-append.sh}"
CKPT_TAG="${INTEGRATE_CKPT_TAG:-$SCRIPT_DIR/ckpt-tag.sh}"
GIT_LOCK_PUSH="${INTEGRATE_GIT_LOCK_PUSH:-$REPO_ROOT/git-diary-workflow/git-lock-push.sh}"
WORKTREE_RETIRE="${INTEGRATE_WORKTREE_RETIRE:-$SCRIPT_DIR/worktree-retire.sh}"
STATE_WRITE="${INTEGRATE_STATE_WRITE:-$SCRIPT_DIR/relay-state-write.sh}"
ROADMAP_TICK="${INTEGRATE_ROADMAP_TICK:-$SCRIPT_DIR/roadmap-tick.sh}"
ROADMAP_ARCHIVE="${INTEGRATE_ROADMAP_ARCHIVE:-$SCRIPT_DIR/roadmap-archive.sh}"
STRANDED_SCAN="${INTEGRATE_STRANDED_SCAN:-$SCRIPT_DIR/stranded-branch-scan.sh}"
DISCOVER_SIG="${INTEGRATE_DISCOVER_SIG:-$SCRIPT_DIR/discover-sig.sh}"

# ── args ──
repo="" path="" worktree="" branch="" summary="" run="" label=""
ids="" level="" reviewed_tip="" verdict="execute" intensive=""
no_bump="" substantive="" strong_model="" fable_recheck="" chain_ended=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         repo="${2:-}"; shift 2 ;;
    --path)         path="${2:-}"; shift 2 ;;
    --worktree)     worktree="${2:-}"; shift 2 ;;
    --branch)       branch="${2:-}"; shift 2 ;;
    --summary)      summary="${2:-}"; shift 2 ;;
    --run)          run="${2:-}"; shift 2 ;;
    --label)        label="${2:-}"; shift 2 ;;
    --ids)          ids="${2:-}"; shift 2 ;;
    --level)        level="${2:-}"; shift 2 ;;
    --reviewed-tip) reviewed_tip="${2:-}"; shift 2 ;;
    --verdict)      verdict="${2:-}"; shift 2 ;;
    --intensive)    intensive="${2:-}"; shift 2 ;;
    --no-bump)      no_bump=1; shift ;;
    --substantive)  substantive="${2:-}"; shift 2 ;;
    --strong-model) strong_model="${2:-}"; shift 2 ;;
    --fable-recheck) fable_recheck=1; shift ;;
    --chain-ended)  chain_ended=1; shift ;;
    *) echo "integrate.sh: unknown arg '$1'" >&2; exit "$EX_USAGE" ;;
  esac
done
for req in repo path worktree branch summary run label; do
  eval "v=\${$req}"
  [ -n "${v:-}" ] || { echo "integrate.sh: --$req is required" >&2; exit "$EX_USAGE"; }
done
# ── TILDE EXPANSION (id:087b) ───────────────────────────────────────────────────────
# Children report their worktree as a `~/.cache/relay/worktrees/...` path, and the old LLM
# integrator got that expanded for free because the prompt spliced it into a shell command
# UNQUOTED. The mechanical caller must single-quote every argument (mechanical-proxy.py's
# command scanner is not shell-aware — see relay-loop.js's mechArg), and `'~/x'` does NOT
# expand. So the expansion happens HERE, where $HOME is real, rather than depending on the
# caller's quoting. Only a LEADING `~/` is touched; nothing else about the path is rewritten.
expand_tilde() { case "$1" in "~/"*) printf '%s' "$HOME/${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }
path="$(expand_tilde "$path")"
worktree="$(expand_tilde "$worktree")"
[ -d "$path/.git" ] || [ -f "$path/.git" ] || { echo "integrate.sh: --path '$path' is not a git checkout" >&2; exit "$EX_USAGE"; }
case "$level" in ""|minor|patch) : ;; *) echo "integrate.sh: --level must be minor|patch (got '$level')" >&2; exit "$EX_USAGE" ;; esac
case "$substantive" in ""|true|false) : ;; *) echo "integrate.sh: --substantive must be true|false (got '$substantive')" >&2; exit "$EX_USAGE" ;; esac

# id:de69 — the checkpoint message carries the worked item id(s) so the durable RELAY_LOG /
# relay-ckpt-* record can be traced back to them. id:087b restores the EXACT ` [id:a,b]`
# spelling the LLM integrator produced (id:9e50 had written ` (a,b)`), so checkpoint messages
# read the same before and after the mechanization and no downstream reader has to learn a
# second form.
idsuffix=""
[ -n "$ids" ] && idsuffix=" [id:${ids}]"
# First worked id — the item axis the id:dd7d sibling scan compares against.
first_id="${ids%%,*}"

log "START repo=$repo path=$path branch=$branch worktree=$worktree run=$run level=${level:-none} verdict=$verdict substantive=${substantive:-unset}"

# ── step 0: lease-release (best-effort; the child's work is done, so this must run
#            whether the merge below succeeds or aborts; a no-op if this run does not
#            hold it) ──
"$CLAIM" release "$repo" --run "$run" >/dev/null 2>&1 || log "step0 lease-release non-zero (best-effort, ignored) repo=$repo"
if [ -n "$intensive" ]; then
  "$CLAIM" release "resource:$intensive" --run "$run" >/dev/null 2>&1 || log "step0 resource-lease-release non-zero (best-effort) res=$intensive"
fi

# ── step 1: clean-tree gate (id:aa93) — FAIL-CLOSED before ANY mutation. On non-zero
#            we DEFER: no merge, no destructive tree op, no force-clean. ──
if ! ct_out="$("$CLEAN_TREE" "$path" 2>&1)"; then
  handback clean-tree "$EX_CLEAN_TREE" "main checkout dirty — a concurrent edit is present; deferring to avoid data loss (id:aa93). $ct_out"
fi

# ── step 2: isolation gate (id:f682/7612) — did the child actually work in its worktree? ──
if ! iso_out="$("$VERIFY_ISO" "$worktree" 2>&1)"; then
  handback verify-isolation "$EX_ISOLATION" "isolation gate failed — worktree/main-checkout isolation breach suspected; deferring (id:7612). $iso_out"
fi

# ── step 3: sync-origin (id:c3f7) — never checkpoint on a base diverged from origin. ──
sync_out="$("$SYNC_ORIGIN" "$path" 2>&1)" || true
case "$sync_out" in
  diverged*) handback sync-origin "$EX_SYNC" "base diverged from origin — manual reconcile (id:c3f7). $sync_out" ;;
esac

# ── step 3b: SIBLING-BRANCH SURFACING (id:dd7d, lodelore id:15d2) — port #5. ─────────
#    Does ANOTHER branch for this same item already carry committed work this merge would
#    silently ignore? This gate SURFACES; it NEVER picks a winner and NEVER blocks the
#    merge. The line naming THIS unit's own branch is dropped (it is about to be merged in
#    step 4, it is not a sibling); every remaining line is recorded VERBATIM.
#
#    FAIL-OPEN on a scan error is the id:dd7d SPEC ("must never itself become a reason no
#    repo can ever be worked") — a scan that errors logs loudly and yields no siblings. The
#    fail-CLOSED half is the WIRING case: a missing/non-executable helper is a deployment
#    bug, not a scan outcome, and gets its own loud EX_WIRING exit.
sibling_lines=""
if [ -n "$first_id" ]; then
  [ -x "$STRANDED_SCAN" ] || handback sibling-scan "$EX_WIRING" "stranded-branch-scan.sh missing or not executable at $STRANDED_SCAN (id:dd7d wiring bug — the sibling-surfacing gate cannot run)"
  sb_rc=0
  sb_out="$("$STRANDED_SCAN" "$path" --verdict "$verdict" --item "$first_id" 2>&1)" || sb_rc=$?
  if [ "$sb_rc" -ne 0 ]; then
    log "step3b id:dd7d stranded-branch-scan exit=$sb_rc (FAIL-OPEN per id:dd7d — proceeding with the merge): $sb_out"
    printf 'integrate.sh: NOTE id:dd7d sibling scan errored (fail-open, merge proceeds): %s\n' "$sb_out" >&2
  else
    # Keep only real "<branch>\t<count>" lines, and DROP this unit's own branch.
    while IFS= read -r sline; do
      case "$sline" in *"$(printf '\t')"*) : ;; *) continue ;; esac
      case "${sline%%$(printf '\t')*}" in "$branch") continue ;; esac
      sibling_lines="${sibling_lines}${sline}"$'\n'
    done <<EOF
$sb_out
EOF
  fi
  if [ -n "$sibling_lines" ]; then
    log "step3b id:dd7d SIBLING BRANCHES surfaced for $repo item $first_id (merge proceeds, human triages): $(printf '%s' "$sibling_lines" | tr '\n' ';')"
  fi
fi

# ── step 3c: BUMP-TRIGGER resolution (id:e647) — the ONE residual reviewer judgement. ──
#    Resolved BEFORE any mutation so an unresolvable trigger DEFERS with main byte-identical.
#    See the header block for the full precedence and its rationale. Never a silent bump,
#    never a silent skip: the undeterminable case is a LOUD HANDBACK[bump].
bump_level="" bump_reason=""
if [ -n "$level" ]; then
  bump_level="$level"; bump_reason="explicit --level $level (caller judged the close user-observable)"
elif [ -n "$no_bump" ]; then
  bump_reason="explicit --no-bump (caller judged the close refactor-only / internal)"
elif [ ! -f "$path/pyproject.toml" ] && [ ! -f "$path/package.json" ]; then
  bump_reason="version-less repo (no pyproject.toml/package.json) — nothing to bump by construction (id:8ef3); the changelog date-buckets instead"
elif [ "$substantive" = "false" ]; then
  bump_reason="--substantive false — the unit produced no substantive close, so it cannot be a user-observable one"
else
  # Durable per-repo standing judgement, if the owner recorded one.
  policy=""
  policy_toml="${FABLES_CONFIG:-$HOME/.config/relay}/relay.toml"
  if [ -f "$policy_toml" ]; then
    policy="$(awk -v want="[repos.$repo]" '
      $0 == want { inblk = 1; next }
      /^\[/      { inblk = 0 }
      inblk && $1 == "bump_policy" { gsub(/[",]/, "", $3); print $3; exit }
    ' "$policy_toml" 2>/dev/null || true)"
  fi
  case "$policy" in
    never)         bump_reason="relay.toml [repos.$repo] bump_policy = never" ;;
    minor|patch)   bump_level="$policy"; bump_reason="relay.toml [repos.$repo] bump_policy = $policy" ;;
    *)
      handback bump "$EX_BUMP" \
        "SEMVER BUMP TRIGGER UNRESOLVABLE for [$repo] (id:e647). This is a MANIFEST repo, so a bump is possible, and --substantive is '${substantive:-unset}' — which does NOT establish whether this close is USER-OBSERVABLE. That is a ratified reviewer judgement (meeting 2026-07-17-1541 D1) and is NOT derivable, so this script refuses to guess in either direction: it will neither silently bump nor silently skip. NOTHING was mutated — main is byte-identical and the worktree is on disk. Resolve by re-running with ONE of: --level minor|patch (user-observable close), --no-bump (refactor-only/internal close), or by recording a durable standing judgement as bump_policy = never|minor|patch in [repos.$repo] of $policy_toml." ;;
  esac
fi
log "step3c bump-trigger: level=${bump_level:-none} — $bump_reason"

# ── step 4: merge --no-ff. On conflict/failure: abort (main unmoved), hand back. ──
pre_head="$(git -C "$path" rev-parse HEAD)"
if ! git -C "$path" merge --no-ff "$branch" -m "merge(relay): $summary" >/dev/null 2>&1; then
  git -C "$path" merge --abort >/dev/null 2>&1 || true
  post_head="$(git -C "$path" rev-parse HEAD)"
  [ "$pre_head" = "$post_head" ] || handback merge "$EX_MERGE" "merge conflict AND abort failed to restore main (was $pre_head now $post_head) — HUMAN reconcile"
  handback merge "$EX_MERGE" "merge --no-ff $branch conflicted; aborted, main unmoved at $pre_head; worktree stays on disk"
fi
merged_head="$(git -C "$path" rev-parse HEAD)"

# ── the ckpt-tag `-c` ANCHOR is DERIVED, never judged (id:8e3e / id:25aa) ────────────
#    • HEAD UNMOVED by the merge => "Already up to date" => the ZERO-COMMIT case (id:8e3e):
#      the child audited its window and changed nothing. Anchor the tag on the commit it
#      actually audited (the branch tip), NEVER on main HEAD, which may hold post-dispatch
#      commits that were never audited.
#    • HEAD MOVED => the branch CARRIED COMMITS (id:25aa): the run's own merged commits must
#      fall INSIDE the audited window, so pass NO `-c` and let ckpt-tag anchor on the
#      POST-MERGE tip. Carrying the zero-commit `-c <reviewedTip>` here would anchor BEHIND
#      the merge and leave those commits permanently OUTSIDE the audited window, so
#      classify-repo re-dispatches a "substantive unaudited commits" review forever.
#    An explicit --reviewed-tip from the caller still wins (test/manual override).
if [ -z "$reviewed_tip" ] && [ "$pre_head" = "$merged_head" ]; then
  reviewed_tip="$(git -C "$path" rev-parse "$branch")"
  log "step4 zero-commit merge (id:8e3e) — anchoring ckpt on the reviewed branch tip $reviewed_tip"
fi

# ── step 4b: DRIVER-SIDE ROADMAP TICK (id:5b12, seam of id:ae08) — port #1. ──────────
#    execute/hard children NO LONGER tick their own ROADMAP checkbox in the worktree
#    (executor-contract v12) — the single serialized integrator ticks it in the canonical
#    checkout, which is what removes the non-union `- [ ] → - [x]` collision N parallel
#    worktrees would otherwise contend on (id:dc5b C2). review/handoff children tick inside
#    their OWN merged worktree per their contract, so they are NOT driver-ticked here.
case "$verdict" in
  execute|hard)
    if [ -n "$ids" ]; then
      [ -x "$ROADMAP_TICK" ] || handback roadmap-tick "$EX_WIRING" "roadmap-tick.sh missing or not executable at $ROADMAP_TICK (id:5b12 wiring bug — worked items would silently stay open and be re-dispatched forever)"
      if ! tick_out="$("$ROADMAP_TICK" "$path" "$ids" 2>&1)"; then
        handback roadmap-tick "$EX_TICK" "roadmap-tick failed for ids '$ids' (merge landed; main is at $merged_head, NOT tagged/pushed): $tick_out"
      fi
      # Commit ROADMAP.md ONLY if it actually changed (scoped staging, id:debf — never -A).
      if [ -n "$(git -C "$path" status --porcelain -- ROADMAP.md 2>/dev/null)" ]; then
        git -C "$path" add -- ROADMAP.md
        git -C "$path" commit -q -m "chore(roadmap): tick worked items [id:$ids]" \
          || handback roadmap-tick "$EX_TICK" "roadmap tick commit failed for ids '$ids'"
      fi
    fi
    ;;
esac

# ── step 5: version-bump (SemVer). Level comes from the step-3c trigger resolution. ──
bump_version=""
if [ -n "$bump_level" ]; then
  if ! bump_version="$("$VERSION_BUMP" "$path" --level "$bump_level" 2>&1)"; then
    handback version-bump "$EX_VERSION" "version-bump --level $bump_level failed: $bump_version"
  fi
  # strip anything that is not a leading vX.Y.Z (the helper prints the tag or nothing)
  bump_version="$(printf '%s' "$bump_version" | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

# ── step 6: changelog-append (id:b8fa). No-op unless the repo already has a CHANGELOG.md
#            (or a real bump just created one via --version). ──
cl_args=("$path" --summary "$summary")
[ -n "$ids" ] && cl_args+=(--ids "$ids")
[ -n "$bump_version" ] && cl_args+=(--version "$bump_version")
if ! cl_out="$("$CHANGELOG" "${cl_args[@]}" 2>&1)"; then
  handback changelog-append "$EX_CHANGELOG" "changelog-append failed: $cl_out"
fi
# Commit CHANGELOG.md ONLY if it actually changed (scoped staging, id:debf — never -A).
if [ -n "$(git -C "$path" status --porcelain -- CHANGELOG.md 2>/dev/null)" ]; then
  git -C "$path" add -- CHANGELOG.md
  git -C "$path" commit -q -m "docs(changelog): $summary" || handback changelog-append "$EX_CHANGELOG" "changelog commit failed"
fi

# ── step 6b: ARCHIVE done ROADMAP items (id:f54d) — port #2. ─────────────────────────
#    The ROOT-CAUSE fix for the recurring `Prompt is too long` child deaths (id:93cc): an
#    unarchived ROADMAP grows without bound and the executor must read it to find its work.
#    IDEMPOTENT, flock-guarded, a clean no-op on a repo with no ROADMAP.md or nothing
#    archivable — so it runs unconditionally on EVERY integrate. It NEVER touches open
#    `- [ ]` items. Nothing here re-words or hand-edits what the archiver moved.
[ -x "$ROADMAP_ARCHIVE" ] || handback roadmap-archive "$EX_WIRING" "roadmap-archive.sh missing or not executable at $ROADMAP_ARCHIVE (id:f54d wiring bug — the ledger would grow unbounded until child prompts overflow)"
if ! arch_out="$("$ROADMAP_ARCHIVE" "$path" 2>&1)"; then
  handback roadmap-archive "$EX_ARCHIVE" "roadmap-archive failed (merge landed; main is at $merged_head, NOT tagged/pushed): $arch_out"
fi
# Commit ONLY those two exact paths (scoped staging, id:debf). The porcelain check also
# catches a newly-created, still-untracked ROADMAP.archive.md.
if [ -n "$(git -C "$path" status --porcelain -- ROADMAP.md ROADMAP.archive.md 2>/dev/null)" ]; then
  git -C "$path" add -- ROADMAP.md ROADMAP.archive.md
  git -C "$path" commit -q -m "chore(roadmap): archive done items" \
    || handback roadmap-archive "$EX_ARCHIVE" "roadmap archive commit failed"
fi

# ── step 7: ckpt-tag (id:1a34 label). -c reviewed-tip ONLY for the zero-commit case. ──
ckpt_args=("$path" -m "${summary}${idsuffix}" -l "$label")
[ -n "$reviewed_tip" ] && ckpt_args+=(-c "$reviewed_tip")
if ! ckpt_tag="$("$CKPT_TAG" "${ckpt_args[@]}" 2>&1)"; then
  handback ckpt-tag "$EX_CKPT" "ckpt-tag failed: $ckpt_tag"
fi
ckpt_tag="$(printf '%s' "$ckpt_tag" | tail -n1)"

# ── step 8: git-lock-push --ff-only (the only network step). ──
if ! push_out="$("$GIT_LOCK_PUSH" --ff-only "$path" 2>&1)"; then
  handback git-lock-push "$EX_PUSH" "push failed (merge + tag are committed locally; retry push): $push_out"
fi
# id:5fe2 — FROM HERE ON the remote HAS the merge + tag: every later handback is
# LANDED-BUT-UNFINISHED, never a retryable defer. Set immediately after the push returns 0.
pushed=1

# ── step 9: worktree-retire (id:373e force-free; id:6e02 scope = EXACTLY this pair). ──
#    No globbing, no discovery — the two artifacts named on the command line, nothing else.
retire_note=""
if ! retire_note="$("$WORKTREE_RETIRE" "$path" "$worktree" "$branch" --expect-merged 2>&1)"; then
  handback worktree-retire "$EX_RETIRE" "worktree-retire failed (branch merged+pushed; worktree left on disk for supervised reconcile): $retire_note"
fi

# ── step 10: state-write (id:ebfb flock'd relay.toml single-writer). Change ONLY this
#             repo's block. ──
if ! "$STATE_WRITE" toml-set "$repo" last_ckpt "\"$ckpt_tag\"" >/dev/null 2>&1; then
  handback state-write "$EX_STATE" "relay-state-write last_ckpt failed for [repos.$repo]"
fi
status_val="active"
case "$verdict" in handoff) status_val="handed-off" ;; esac
if ! "$STATE_WRITE" toml-set "$repo" status "\"$status_val\"" >/dev/null 2>&1; then
  handback state-write "$EX_STATE" "relay-state-write status failed for [repos.$repo]"
fi
if [ "$verdict" = "review" ]; then
  "$STATE_WRITE" toml-set "$repo" last_review "\"$(date +%F)\"" >/dev/null 2>&1 \
    || handback state-write "$EX_STATE" "relay-state-write last_review failed for [repos.$repo]"
fi
if [ "$verdict" = "handoff" ]; then
  "$STATE_WRITE" toml-set "$repo" handoff_date "\"$(date +%F)\"" >/dev/null 2>&1 \
    || handback state-write "$EX_STATE" "relay-state-write handoff_date failed for [repos.$repo]"
fi

# ── step 10b: durable Fable-bonus-recheck queue (id:e030) — port #3. ─────────────────
#    A STRONG unit (anything but the sonnet `execute` tier) checkpoints a strong-model
#    decision, so we persist a durable, model-tracked recheck entry. These three keys
#    survive a LATER executor checkpoint that overwrites last_ckpt, which is the whole
#    point: the pending optional Fable recheck stays visible even when masked.
#
#    THE TWO BRANCHES ARE PRESERVED EXACTLY:
#      • --fable-recheck (this session's strong tier is REAL Fable): the strong checkpoint
#        IS/satisfies the optional recheck, so fable_rechecked is TODAY'S ISO DATE — the
#        recheck just happened, mark it done, do NOT set false. (id:6856 — a Fable HANDOFF
#        used to fall to the else branch and record false, unlike a Fable review.)
#      • otherwise (an Opus-standin/strong checkpoint): fable_rechecked = false, a BARE
#        value — it still invites an optional Fable recheck.
#
#    AND THE EXECUTE BRANCH IS A HARD NO-OP: an execute (sonnet) checkpoint must NEVER
#    touch last_strong_ckpt / strong_model / fable_rechecked. Clearing them from an
#    executor checkpoint IS the id:e030 masking bug. There is deliberately no `else` here.
if [ "$verdict" != "execute" ]; then
  if [ -n "$fable_recheck" ]; then
    fable_val="\"$(date +%F)\""
  else
    fable_val="false"
  fi
  "$STATE_WRITE" toml-set "$repo" last_strong_ckpt "\"$ckpt_tag\"" >/dev/null 2>&1 \
    || handback strong-state "$EX_STRONG" "relay-state-write last_strong_ckpt failed for [repos.$repo] (id:e030 durable Fable-recheck queue)"
  "$STATE_WRITE" toml-set "$repo" strong_model "\"$strong_model\"" >/dev/null 2>&1 \
    || handback strong-state "$EX_STRONG" "relay-state-write strong_model failed for [repos.$repo] (id:e030)"
  "$STATE_WRITE" toml-set "$repo" fable_rechecked "$fable_val" >/dev/null 2>&1 \
    || handback strong-state "$EX_STRONG" "relay-state-write fable_rechecked failed for [repos.$repo] (id:e030)"
  log "step10b id:e030 durable strong-ckpt queue written: last_strong_ckpt=$ckpt_tag strong_model=$strong_model fable_rechecked=$fable_val"
else
  log "step10b id:e030 EXECUTE checkpoint — last_strong_ckpt/strong_model/fable_rechecked deliberately UNTOUCHED (never clear a pending Fable recheck)"
fi

# ── step 11: L2 push-seed inputs (id:c855) — port #4. ────────────────────────────────
#    Computed LAST, AFTER steps 1-10, so the relay.toml block, the removed worktree dir and
#    the pushed HEAD all feed the signature — i.e. these reflect the fully-SETTLED
#    post-integrate state, which is the only state next round's prelude can reproduce.
#
#    FAIL-OPEN is the id:c855 SPEC, and it is fail-open in the SAFE direction: an empty
#    postSig makes relay-loop.js DELETE the cache entry, so the repo re-classifies next
#    round. Under-invalidation (a stale 'idle' masking real work) is the one hazard refused;
#    a wasted re-classify is not. The wiring case (missing helper) is still EX_WIRING-loud.
post_sig=""
if [ -x "$DISCOVER_SIG" ]; then
  ce=""; [ -n "$chain_ended" ] && ce=',"chain_ended":true'
  sig_rc=0
  sig_out="$(printf '%s' "{\"repos\":[{\"repo\":\"$repo\",\"path\":\"$path\"$ce}],\"liveClaims\":[]}" | "$DISCOVER_SIG" 2>&1)" || sig_rc=$?
  if [ "$sig_rc" -eq 0 ]; then
    post_sig="$(printf '%s' "$sig_out" | sed -n 's/.*"sig"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]*\)".*/\1/p' | tail -n1)"
  else
    log "step11 id:c855 discover-sig exit=$sig_rc — FAIL-OPEN, postSig stays empty so the repo re-classifies: $sig_out"
  fi
else
  log "step11 id:c855 discover-sig.sh not executable at $DISCOVER_SIG — FAIL-OPEN, postSig stays empty (repo re-classifies)"
fi
# Open-work counts from the POST-integrate ROADMAP.md at HEAD. Both are plain counts, and 0
# when the file/marker is absent. openHard counts ALL [HARD items (gated or not): the
# supervisor only push-seeds 'idle' when BOTH counts are 0, so over-counting merely declines
# to cache — the safe direction.
open_routine="$(git -C "$path" grep -c -E '^- \[ \].*\[ROUTINE\]' HEAD -- ROADMAP.md 2>/dev/null | tail -n1 | sed 's/.*://' || true)"
open_hard="$(git -C "$path" grep -c -E '^- \[ \].*\[HARD' HEAD -- ROADMAP.md 2>/dev/null | tail -n1 | sed 's/.*://' || true)"
case "$open_routine" in ''|*[!0-9]*) open_routine=0 ;; esac
case "$open_hard"    in ''|*[!0-9]*) open_hard=0 ;; esac

log "DONE repo=$repo merged=$merged_head ckpt=$ckpt_tag bump=${bump_version:-none} postSig=${post_sig:-<empty>} openRoutine=$open_routine openHard=$open_hard"
# ── Machine-readable output contract: one KEY=VALUE per line (parsed by relay-loop.js's
#    parseIntegrateResult, id:087b). Values are single-line by construction.
printf 'merged=%s\n' "$merged_head"
printf 'ckpt=%s\n'   "$ckpt_tag"
printf 'push=%s\n'   "pushed"
printf 'ts=%s\n'     "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'bump=%s\n'   "${bump_version:-}"
printf 'retire=%s\n' "$(printf '%s' "${retire_note:-}" | tr '\n' ' ')"
printf 'postSig=%s\n' "${post_sig:-}"
printf 'openRoutine=%s\n' "$open_routine"
printf 'openHard=%s\n'    "$open_hard"
# 0..n sibling lines, VERBATIM from stranded-branch-scan.sh (id:dd7d) minus this unit's own
# branch. Their presence NEVER means the merge was withheld — it landed above.
if [ -n "$sibling_lines" ]; then
  printf '%s' "$sibling_lines" | while IFS= read -r sline; do
    [ -n "$sline" ] && printf 'sibling=%s\n' "$sline"
  done
fi
exit 0
