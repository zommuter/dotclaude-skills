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
#   8. git-lock-push   (--ff-only; the only network step) — SUBSTANTIVE units SKIP this
#                      (id:4d44 owner ruling (a)); see the RATIFICATION GATE block below.
#   8b. ratify-enqueue (id:4d44 — durable ratification queue; ONLY for a deferred push)
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
# ── THE RATIFICATION GATE (id:4d44 — OWNER RULING (a), 2026-08-21) ──────────────────
# MEASURED FACT, not a hypothesis: the harness safety classifier BLOCKS the integrate hop
# whenever the merge would PUBLISH substantive agent-authored work. Run
# relay-20260821-174757-32436, n=5: all three substantive integrates were refused
# `[Self-Approval]` across all three verdict modes (execute/review/hard); both integrates
# that SUCCEEDED carried `substantive: false`. The discriminator is SUBSTANTIVE-ness, not
# verdict mode. The classifier cited the owner's own CLAUDE.md delegated-verdict rule ("a
# delegated agent's verdict is a recommendation, never a self-settling decision") BY NAME.
# That is a DESIGN COLLISION between "the pool integrates unattended" and "a human ratifies
# agent-authored change", and the owner resolved it interactively:
#
#     THE POOL MERGES LOCALLY. THE HUMAN RATIFIES AND PUSHES.
#
# So for a SUBSTANTIVE unit this script runs EVERY step except the push: merge --no-ff,
# tick, bump, changelog, archive, ckpt-tag, retire and state-write all still run, the push
# does NOT, and the unit is enqueued in a DURABLE ratification queue (step 8b) for the next
# attended session. A NON-SUBSTANTIVE unit is UNCHANGED — it still pushes, exactly as before
# (those already pass the classifier and carry nothing to ratify).
#
# `--substantive` is REUSED, never re-derived: relay-loop.js already computes it
# (unitIsSubstantive) and passes it on every dispatch. UNSET defers too — deferring is the
# fail-CLOSED direction (nothing reaches the remote and the unit is still queued), so an
# ambiguous/manual invocation can never publish agent work by accident.
#
# LOCAL-AHEAD `main` IS NOW THE STEADY STATE, ACROSS RUNS. That is already tolerated by both
# gates that could have refused it, and this was CHECKED rather than assumed:
#   • sync-origin.sh (step 3) returns `diverged` ONLY when ahead>0 AND behind>0; ahead-only
#     falls through to `ok` (its step-4 "otherwise (in sync / ahead) → ok" branch).
#   • classify-verdict.sh sets `diverged = has_upstream and _ahead > 0 and _behind > 0` —
#     ahead-only is NOT the rank-0 `blocked` parity guard, so the repo keeps being dispatched.
#   • verify-isolation.sh (step 2) DID NOT tolerate it — it was the ONE gate this list
#     originally omitted, and it was the one that broke (id:8739): its base defaulted to the
#     now-FROZEN origin/main, which silently disabled the id:f682 breach detector. Fixed by
#     passing an explicit `--base <canonical HEAD sha>` at step 2; see the block there.
#   • ckpt-tag.sh / relay-state-write.sh never consult origin at all: the tag and
#     relay.toml last_ckpt are local facts, and an unpushed tag resolves locally exactly as a
#     pushed one does. discover-sig.sh DOES hash ahead/behind, so the sig changes and the
#     repo re-classifies — over-invalidation, the safe direction (id:c3a6).
# ahead>0 AND behind>0 still hands back at step 3, and that is CORRECT and deliberate: an
# origin that moved under an unpushed local queue is a real divergence needing the owner.
#
# ── FAIL-CLOSED, LOUD, DISTINCT EXITS ───────────────────────────────────────────────
# Each step maps its own failure to a DISTINCT non-zero exit code and prints a loud
# HANDBACK[<step>] line to stderr. The caller records it durably and does not re-merge.
#
# ── THE ONE RESIDUAL: the SEMVER BUMP TRIGGER (id:e647) ─────────────────────────────
# "One bump per USER-OBSERVABLE close" is a ratified REVIEWER judgement (meeting
# 2026-07-17-1541 D1). Its second half — "a refactor-only / internal-cleanup close does NOT
# bump" — was AMENDED AWAY by the owner on 2026-08-26 (verbatim: *"a refactor/internal can
# still mess up plenty and must at least bump patch"*), continuing the same reasoning that
# produced the id:65ad fleet default: a refactor-only close ASSERTS a functional identity it
# cannot actually guarantee, so minting a version is the honest signal. NO per-close path
# skips a bump on a manifest repo any more. The LEVEL is still not derivable, so this script
# never guesses it. Resolution order — the FIRST match wins:
#   1. --level minor|patch      → the caller judged it user-observable. Bump at that level.
#   2. --internal               → the caller judged it refactor-only / internal. Bump PATCH.
#                                 (`--no-bump` is a DEPRECATED ALIAS for this and warns
#                                 loudly — the name is now a lie; it no longer skips.)
#   3. no versioned manifest    → a VERSION-LESS repo (dotclaude-skills by design, id:8ef3):
#                                 there is nothing to bump. No bump; the changelog
#                                 date-buckets instead. version-bump.sh is a no-op here.
#   4. --substantive false      → the unit produced no substantive close (relay-loop.js's
#                                 unitIsSubstantive), so it cannot be a user-observable one.
#                                 No bump.
#   5. relay.toml bump_policy   → [repos.<repo>] bump_policy = never|minor|patch, a durable
#                                 per-repo standing judgement the owner records ONCE. Since
#                                 the 2026-08-26 amendment this is the ONLY surviving way to
#                                 skip a bump, and it is deliberately OWNER-recorded and
#                                 per-REPO, not a per-close agent judgement. It is where the
#                                 formally-verified carve-out (Lean — where a functional
#                                 identity CAN be mechanically established, so a no-bump is
#                                 truthful) lives. Zero repos set it today.
#   6. NO bump_policy recorded  → FLEET DEFAULT minor (id:65ad, owner-ratified 2026-08-22).
#                                 An EXPLICIT owner OVERRIDE of the 2026-07-17-1541 D1 rule,
#                                 not a convenience — see the block at the fallback site for
#                                 what it costs and why `minor`, not `patch`.
#   7. bump_policy line PRESENT → UNDETERMINABLE. HANDBACK[bump] (exit 30), LOUD, BEFORE any
#      but UNPARSED (malformed/     mutation. A line the reader could not read is NOT the
#      empty RHS, or a NEAR-MISS    absent case and never takes the default — under a fleet
#      key such as `bumppolicy`)    default that would silently bump against a recorded
#                                   `never`. See the reader block at step 3c.
#   8. bump_policy PARSED but   → FLEET DEFAULT minor, with a LOUD WARNING naming the bad
#      an UNRECOGNISED VALUE       value (id:d51f(b), owner-decided 2026-08-22). NOT a
#      (`auto`, `NEVER`, `mnior`)  handback: the primary guard is WRITER-side enum validation
#                                  in relay-state-write.sh (id:d51f(a)), which makes this
#                                  path near-unreachable defence-in-depth.
# Resolution happens pre-merge on purpose: a deferred repo is left byte-identical.
#
# Usage:
#   integrate.sh --repo <name> --path <main-checkout> --worktree <dir> --branch <branch> \
#                --summary <text> --run <runId> --label <ckpt-label> \
#                [--ids a,b] [--level minor|patch] [--internal] [--substantive true|false] \
#                [--reviewed-tip <sha>] [--verdict execute|hard|review|handoff] \
#                [--intensive <resource>] [--strong-model <id>] [--fable-recheck] \
#                [--chain-ended]
#
# Output contract (stdout, one KEY=VALUE per line — parsed by relay-loop.js integrate()):
#   merged=<sha>  ckpt=<tag>  push=<pushed|partial|deferred|no-upstream|FAILED>
#   pushRemote=<name>:<pushed|deferred|FAILED|skipped-no-ssh-key|no-push-url|undeclared>
#                                                                             (0..n lines)
#   pushPending=<comma-separated remotes that did NOT receive the merge, or empty>
#   ratification=<pending|none>
#
#   id:99b7 `undeclared` — the remote is NOT IN THIS REPO'S DO-PUBLISH ALLOWLIST
#   (`[publish] default_remotes` + `[repos.<r>] publish_remotes` in relay.toml). It is NOT a
#   publish target at all: never pushed, never counted as eligible, NEVER in `pushPending=`
#   and never in the ratification queue. It is also SURFACED LOUDLY on stderr — the mirror
#   failure (a remote the owner DID want to publish to, left undeclared) must never be
#   silent. See relay/scripts/lib-publish-remote.sh.
#   ts=<ISO>  bump=<vX.Y.Z|>  retire=<note>
#   postSig=<hex|>  openRoutine=<n>  openHard=<n>  sibling=<branch>\t<count>  (0..n lines)
#
#   id:4d44 PER-REMOTE. `push=` is the AGGREGATE; the per-remote truth is in the
#   `pushRemote=` lines. A SUBSTANTIVE unit now pushes its PRIVATE/LAN remotes automatically
#   and defers ONLY the public ones, so `push=partial` is a normal outcome. Every `pushed` is
#   VERIFIED per remote against the remote ref, never inferred from git-lock-push.sh's exit
#   code (id:f5d9(a)/id:dc4f — it exits 0 having pushed nothing); an intended push that did
#   not land is push=FAILED on stderr with a handback, never success.
#
#   `ratification=` is the OWNER-FACING key, and id:f0ad's rule survives the per-remote
#   rework UNCHANGED IN SUBSTANCE — only generalised from one remote to many:
#     pending ⇔ at least one remote still lacks the merge. THREE push classes reach it:
#               `deferred` (nothing pushed — a substantive unit whose remotes are all
#               public), `partial` (id:4d44 — some remotes got it, some were withheld), and
#               `no-upstream` (id:f0ad — nowhere to push at all). All three are the same
#               durable state for the remotes concerned: merged + tagged locally, absent
#               from those remotes. The queue entry NAMES them (`pending_remotes`).
#     none    ⇔ EVERY eligible remote carries the merge. id:f0ad's "it was published" for a
#               one-remote repo is exactly this, and the generalisation is the only reading
#               that keeps `none` meaning one thing: nothing is waiting for the owner.
#               Reporting `none` for any unit with an unpublished remote is the id:f0ad
#               defect (relay-loop counts an unpublished merge as a plain completion).
#
# Handback contract (STDOUT — mirrored to STDERR for the human tail; id:5fe2, EXIT CODE
# FLATTENED by id:2c2a):
#   PRE-LAND  handback: handback=<step>  handbackCode=<N>  handbackReason=<one line>
#                       landed=false                                    (safe to retry)
#   POST-LAND handback: handback=<step>  handbackCode=<N>  handbackReason=<one line>
#                       landed=true  partial=<step>  merged=<sha>  ckpt=<tag>
#                       push=<pushed|deferred>  ratification=<pending|none>
#                       remaining=<steps that did NOT run>  ckptRecorded=<true|false>
#   A `merged=` line NEVER appears on a pre-land handback — that is the whole discriminator.
#
#   id:2c2a — EXIT 0 WHENEVER A VERDICT WAS REACHED AND EXECUTED (owner-ratified 2026-08-26).
#   A handback IS the mechanism working: integrate.sh reached a determinate verdict ("refuse,
#   and here is exactly where and why") and executed it. Every one of the 16 per-step handback
#   codes therefore now exits 0, and the step identity that USED to ride on the exit code
#   rides — wholly — on the parsed stdout contract instead (`handback=`, plus `handbackCode=`
#   which preserves the numeric code verbatim, plus `handbackReason=`). NON-ZERO is reserved
#   for genuinely UNDETERMINABLE outcomes: EX_USAGE (the script was mis-invoked and never
#   started), and any uncaught `set -e` failure. The EX_* constants below are NOT dead — they
#   remain the step-identity numbers, emitted as `handbackCode=` and logged.
#
#   Because the block is now read off a ZERO-exit child, it goes to STDOUT: the proxy returns
#   stdout on exit 0 and DISCARDS stderr, the exact mirror of the pre-id:2c2a situation. It is
#   ALSO written to stderr so an operator tailing the terminal/log still sees it whole.
#
#   `partial=<step>` (id:2c2a) is the distinct marker for the LANDED-BUT-UNFINISHED class:
#   the merge is COMMITTED, TAGGED and (for a pushing unit) PUSHED, and only a post-land tail
#   step failed. It is emitted on exactly the same condition as `landed=true`, and never on a
#   pre-land handback or a full success — so a consumer can key case (ii) off one token.
#
#   id:4d44 RE-DERIVED THE LAND POINT (id:5fe2's discriminator was keyed on the PUSH, and a
#   substantive unit no longer has one). "LANDED" means: the merge is COMMITTED to the
#   canonical checkout AND TAGGED — i.e. the point after which re-running this script is
#   WRONG (the branch is already an ancestor of main, so a retry takes the zero-commit path
#   and mints a SECOND ckpt tag while relay.toml stays stale). That point is:
#     • a PUSHING unit      → after step 8's push is VERIFIED (unchanged from id:5fe2)
#     • a PUSH-DEFERRED unit → after step 7's ckpt-tag returns (there is no post-push class
#       for it, so keying on the push would have mis-classified EVERY substantive tail
#       failure as a safe retry — the exact wedge id:5fe2 was built to prevent).
#
# Helper resolution (all overridable for hermetic tests — the failure-injection seam):
#   INTEGRATE_CLAIM INTEGRATE_CLEAN_TREE_GATE INTEGRATE_VERIFY_ISOLATION
#   INTEGRATE_SYNC_ORIGIN INTEGRATE_VERSION_BUMP INTEGRATE_CHANGELOG_APPEND
#   INTEGRATE_CKPT_TAG INTEGRATE_GIT_LOCK_PUSH INTEGRATE_WORKTREE_RETIRE
#   INTEGRATE_STATE_WRITE INTEGRATE_ROADMAP_TICK INTEGRATE_ROADMAP_ARCHIVE
#   INTEGRATE_STRANDED_SCAN INTEGRATE_DISCOVER_SIG
set -euo pipefail

# ── distinct STEP-IDENTITY codes (per step) ──
# id:2c2a — these are no longer EXIT codes. Every one of them is now reported as
# `handbackCode=<N>` on the stdout contract and the script exits 0 (a handback is a verdict
# REACHED and EXECUTED). They are kept, unrenumbered, as the durable per-step identity: the
# logs, the tests and the operator all still name a step by its number. The ONLY non-zero
# exits left are EX_USAGE (mis-invoked — no verdict was ever reached) and an uncaught
# `set -e` failure, which is the genuinely-undeterminable class the flattening reserves it for.
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
EX_RATIFY=35        # id:4d44 — the merge landed locally but could NOT be recorded in the
                    # durable ratification queue. NEVER swallowed: an unqueued deferred merge
                    # is invisible work sitting unpushed on main, which is the one failure
                    # this whole design must not have.

LOG="${INTEGRATE_LOG:-$HOME/.claude/logs/relay-integrate.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log()  { printf '%s integrate.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }
# ── id:5fe2 — DEFERRED vs LANDED-BUT-UNFINISHED (LAND POINT RE-DERIVED by id:4d44) ──
# The LAND POINT splits every handback into two classes the caller MUST tell apart:
#   • PRE-LAND  — nothing durable happened that a re-run would duplicate, so re-running the
#     whole script is CORRECT. (isolation, sync, wiring, bump, merge, tick, version,
#     changelog, archive, ckpt — AND push itself: exit 27 means the push FAILED or could not
#     be VERIFIED to have landed, so the remote never moved.)
#   • POST-LAND — the merge is committed and TAGGED (and PUSHED, for a pushing unit); only a
#     tail step failed (ratify-enqueue, retire, state-write, strong-state). Re-running is
#     WRONG: the retry takes the zero-commit path and mints a SECOND ckpt tag while
#     `relay.toml last_ckpt` stays stale and the completion never reaches
#     state.completed/CHANGELOG. Such a unit must be SURFACED for completion, never re-merged.
# id:4d44 — the land point is the CKPT TAG, not the push: a substantive unit has NO push, so
# keying on it would have re-classified every substantive tail failure as a safe retry.
# `landed` is set at exactly one place per path (verified push, or ckpt-tag on the deferred
# path), so the PRE-LAND half cannot accidentally advertise a landed merge.
merged_head="" ckpt_tag="" landed=""
# push_status/ratify_status are reported on BOTH the success and the handback path, so they
# are initialised to the pre-push truth: nothing pushed, nothing queued yet.
push_status="not-attempted" ratify_status="none"
# id:2c2a — the KEY=VALUE handback block goes to STDOUT (and is MIRRORED to stderr for the
# human tail). It used to be stderr-only because mechanical-proxy.py DISCARDS a non-zero-exit
# child's stdout and returns 'MECH-ERROR exit=<n>\n<stderr>'. Since a handback now exits 0,
# that is exactly inverted — the proxy returns stdout and drops stderr — so a stderr-only
# block would reach parseIntegrateResult as NOTHING and every handback would be misread as
# "produced no merged= line". The block therefore MOVED with the exit code, in one step:
# stdout is now the full contract (success AND handback), discriminated by `handback=`.
# LOUD handback: name the step, print the reason, log it, emit the machine block, exit 0
# (the step identity travels as `handback=`/`handbackCode=`, never as the exit status).
# Never swallowed.
handback() { # <step-label> <exit-code> <reason...>
  local step="$1" code="$2"; shift 2
  printf 'integrate.sh: HANDBACK[%s]: %s\n' "$step" "$*" >&2
  log "HANDBACK[$step] code=$code $*"
  # id:2c2a — the reason must ride on the PARSED channel too, not just the human one: with
  # exit 0 the proxy drops stderr, so a stderr-only reason would leave the operator with a
  # step name and no cause. Squashed to ONE line — every KEY=VALUE value is single-line.
  local reason_line block=""
  reason_line="$(printf '%s' "$*" | tr '\n\r' '  ')"
  if [ -n "$landed" ]; then
    # Which tail steps did NOT run — the operator is told EXACTLY, never left to guess.
    local remaining
    case "$step" in
      # id:a726(b) — `git-lock-push` became a POST-LAND step when id:4d44 moved the land
      # point to the ckpt tag, but it had no arm here, so it degraded to "UNKNOWN post-land
      # step" — precisely the message an operator does NOT want during a supervised
      # reconcile. id:5155 then moved the ratification enqueue AHEAD of this handback, so
      # `ratification-enqueue` is deliberately NOT listed as unrun: it already ran.
      git-lock-push)   remaining="push (the merge reached ${n_pushed:-?} of the intended remote(s); pending: ${pending_csv:-unknown}),worktree-retire,state-write,strong-state,push-seed" ;;
      ratify-enqueue)  remaining="ratification-enqueue,worktree-retire,state-write,strong-state,push-seed" ;;
      worktree-retire) remaining="worktree-retire,state-write,strong-state,push-seed" ;;
      state-write)     remaining="state-write,strong-state,push-seed" ;;
      strong-state)    remaining="strong-state,push-seed" ;;
      *)               remaining="UNKNOWN post-land step '$step' — treat every tail step as unrun" ;;
    esac
    # Best-effort reconcile of the ONE piece of durable state whose staleness is the
    # observed symptom: relay.toml last_ckpt must not silently disagree with the remote,
    # which already carries $ckpt_tag. Idempotent; failure is REPORTED, never swallowed.
    local recorded=false
    if [ -n "$ckpt_tag" ] && "$STATE_WRITE" toml-set "$repo" last_ckpt "\"$ckpt_tag\"" >/dev/null 2>&1; then
      recorded=true
      log "HANDBACK[$step] id:5fe2 post-land reconcile: relay.toml last_ckpt set to $ckpt_tag"
    else
      log "HANDBACK[$step] id:5fe2 post-land reconcile FAILED — relay.toml last_ckpt may be STALE vs $ckpt_tag"
    fi
    block="$(
      printf 'handback=%s\n'       "$step"
      printf 'handbackCode=%s\n'   "$code"
      printf 'handbackReason=%s\n' "$reason_line"
      printf 'landed=%s\n'         'true'
      # id:2c2a — the LANDED-BUT-UNFINISHED marker. Emitted on exactly the `landed` condition,
      # so it can never appear on a pre-land handback or on the success path.
      printf 'partial=%s\n'        "$step"
      printf 'merged=%s\n'         "$merged_head"
      printf 'ckpt=%s\n'           "$ckpt_tag"
      printf 'push=%s\n'           "$push_status"
      printf 'ratification=%s\n'   "$ratify_status"
      printf 'remaining=%s\n'      "$remaining"
      printf 'ckptRecorded=%s\n'   "$recorded"
    )"
  else
    block="$(
      printf 'handback=%s\n'       "$step"
      printf 'handbackCode=%s\n'   "$code"
      printf 'handbackReason=%s\n' "$reason_line"
      printf 'landed=%s\n'         'false'
      # id:f5d9(a) — a push that did not land is reported as such even on the PRE-LAND path,
      # so no reader can mistake "the helper exited 0" for "the remote moved".
      # An `if`, not `[ … ] && …`: a false one-liner would be the group's last command, so
      # its non-zero status would trip `set -e` and abort BEFORE the block is emitted.
      if [ "$push_status" = "FAILED" ]; then printf 'push=%s\n' 'FAILED'; fi
    )"
  fi
  # STDOUT is the parsed channel (id:2c2a); stderr keeps a verbatim mirror for the human tail.
  printf '%s\n' "$block"
  printf '%s\n' "$block" >&2
  # id:2c2a — exit 0: a handback is a REACHED-AND-EXECUTED verdict, not a failure to reach one.
  exit 0
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
# id:4d44 — THE single "is this remote a PRIVATE/LAN host?" predicate. Shared with
# hooks/pre-push-privacy-gate.sh; never re-derived here. See lib-private-remote.sh's header
# for why git-lock-push.sh's is_ssh_url() is NOT a substitute (it fails toward AUTO-PUBLISH).
LIB_PRIVATE_REMOTE="${INTEGRATE_LIB_PRIVATE_REMOTE:-$SCRIPT_DIR/lib-private-remote.sh}"
# id:99b7 — THE single "may we PUBLISH to this remote at all?" resolver (the do-publish
# ALLOWLIST). A SEPARATE predicate from lib-private-remote.sh on purpose: privacy gates the
# LEAK SCAN, this gates the PUSH, and conflating them would skip a leak scan. See that file's
# header for the third-party-upstream defect it closes.
LIB_PUBLISH_REMOTE="${INTEGRATE_LIB_PUBLISH_REMOTE:-$SCRIPT_DIR/lib-publish-remote.sh}"

# ── args ──
repo="" path="" worktree="" branch="" summary="" run="" label=""
ids="" level="" reviewed_tip="" verdict="execute" intensive=""
internal="" substantive="" strong_model="" fable_recheck="" chain_ended=""
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
    --internal)     internal=1; shift ;;
    # DEPRECATED ALIAS (id:8d76 sibling ruling, 2026-08-26). The name is now a LIE: this
    # flag bumps PATCH, it does not skip the bump. Accepted so no caller breaks, but it
    # warns LOUDLY rather than silently doing something other than what it says.
    --no-bump)      internal=1
                    printf 'integrate.sh: WARNING — `--no-bump` is DEPRECATED and NO LONGER SKIPS THE BUMP.\n' >&2
                    printf '  Owner ruling 2026-08-26 amending meeting 2026-07-17-1541 D1: a refactor-only /\n' >&2
                    printf '  internal-cleanup close MUST still bump at least PATCH. Treating this as `--internal`\n' >&2
                    printf '  (bump level = patch). Use `--internal` explicitly; to skip a bump entirely, record\n' >&2
                    printf '  a durable `bump_policy = "never"` in relay.toml for this repo instead.\n' >&2
                    shift ;;
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
# id:76fd — `--summary -` is the opt-in stdin-payload sentinel (id:33b2/a05c option B):
# the caller's free-text summary rides the ```relay-mech-stdin fence instead of an inline
# shell argument (a markdown-backticked executor summary can no longer 404 its own
# integrate — id:2e7a). Read AFTER the required-arg check above so a call with no args at
# all (nothing to read stdin for) still fails fast at usage validation without touching
# stdin. Read as INERT DATA ONLY — never eval'd, sourced, or otherwise interpreted.
if [ "$summary" = "-" ]; then
  summary="$(cat)"
fi
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

# ── id:4d44 RATIFICATION GATE: does THIS unit push, or defer to the owner? ───────────
#    The `substantive` flag is REUSED, not re-derived — relay-loop.js's unitIsSubstantive
#    already computed it and passes it on every dispatch. Only an EXPLICIT `--substantive
#    false` pushes; `true` AND unset both defer, because deferring is the fail-closed
#    direction (nothing reaches the remote, and the unit is still durably queued).
defer_push=1
if [ "$substantive" = "false" ]; then
  defer_push=""
fi
# The durable ratification queue lives beside the relay's other durable state and is
# APPEND-ONLY JSONL, written through relay-state-write.sh's flock'd `event-append`. It is
# deliberately NOT RELAY_STATUS.md: id:4917 established that the status hop is itself blocked
# by the classifier precisely when a run goes deep, so the status file goes stale exactly when
# it would matter. $FABLES_CONFIG keeps it hermetically overridable for tests.
RATIFY_QUEUE="${RELAY_RATIFICATION_QUEUE:-${FABLES_CONFIG:-$HOME/.config/relay}/ratification-queue.jsonl}"

log "START repo=$repo path=$path branch=$branch worktree=$worktree run=$run level=${level:-none} verdict=$verdict substantive=${substantive:-unset} deferPush=${defer_push:-0}"

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
#
# ── id:8739: THE BASE IS PASSED EXPLICITLY, NEVER DEFAULTED TO origin/main ───────────
# verify-isolation.sh's default base is `origin/main` (its lines 78-80), and its whole
# main-HEAD discriminator rests on the premise (its lines 18-24) that the base ref TRACKS
# the canonical main, so that `merge-base(worktree HEAD, base)` is the DISPATCH-TIME main
# HEAD and `base` itself is main's CURRENT head. The id:4d44 ratification gate FREEZES
# `origin/main` — a substantive unit merges locally and never pushes — so that premise is
# false BY CONSTRUCTION here, and it degrades further with every deferred unit. Measured
# consequences of leaving it defaulted (REPRODUCED 2026-08-21, not inferred):
#   • (b2) NEVER FIRES AGAIN: main_head = rev-parse origin/main never advances, so
#     main_head == merge_base always and every empty worktree is waved through as a
#     "legitimate no-op review (id:8e3e)" — including the loderite/jobAI breach signature
#     this gate exists for (id:f682). The breach detector is simply OFF.
#   • (a) FIRES SPURIOUSLY: a worktree branched off a local-ahead main reports the whole
#     unratified backlog as "commits beyond base", so an EMPTY worktree reads `ok: N
#     commit(s) beyond origin/main, tree clean`.
# So the base is the CANONICAL CHECKOUT'S CURRENT HEAD — a sha, not a name. It is the exact
# commit step 4 is about to merge INTO, which is what "main" means for this integrate: no
# branch-name guess, no remote round-trip, and no dependence on a ref the ratification gate
# has frozen. It resolves inside the worktree because a linked worktree shares the object db.
# FAIL-CLOSED: if the canonical HEAD does not resolve we hand back rather than fall back to
# the defaulted (broken) base — an unverifiable isolation gate must never wave a merge
# through, and this is the merge-to-main critical path.
if ! iso_base="$(git -C "$path" rev-parse --verify -q HEAD 2>/dev/null)" || [ -z "$iso_base" ]; then
  handback verify-isolation "$EX_ISOLATION" "cannot resolve the canonical checkout's HEAD at '$path' (unborn branch or corrupt repo), so the id:8739 isolation base is UNDETERMINABLE — refusing to fall back to verify-isolation.sh's origin/main default, which id:4d44 has frozen (that fallback silently disables the id:f682 breach gate). Nothing was mutated."
fi
if ! iso_out="$("$VERIFY_ISO" "$worktree" --base "$iso_base" 2>&1)"; then
  handback verify-isolation "$EX_ISOLATION" "isolation gate failed — worktree/main-checkout isolation breach suspected; deferring (id:7612, base=$iso_base per id:8739). $iso_out"
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
elif [ -n "$internal" ]; then
  # OWNER RULING 2026-08-26 — amends meeting 2026-07-17-1541 D1's "a refactor-only /
  # internal-cleanup close does NOT bump". Owner verbatim: *"a refactor/internal can still
  # mess up plenty and must at least bump patch"*. This branch used to leave bump_level
  # EMPTY (no version, no tag); it now resolves to PATCH. There is no longer ANY per-close
  # path that skips a bump on a manifest repo — the only remaining skip is the DURABLE,
  # owner-recorded `bump_policy = "never"` (rule 5), which is where the formally-verified
  # carve-out he named in 2026-07-17-1541 lives. `patch` and not `minor` is the point of
  # the flag: under loose-0.x it signals "no new surface", while still minting a version
  # so the changed code is not silently asserted identical to the old.
  bump_level="patch"
  bump_reason="explicit --internal (caller judged the close refactor-only / internal) — PATCH, never nothing (owner ruling 2026-08-26 amending 2026-07-17-1541 D1)"
elif [ ! -f "$path/pyproject.toml" ] && [ ! -f "$path/package.json" ]; then
  bump_reason="version-less repo (no pyproject.toml/package.json) — nothing to bump by construction (id:8ef3); the changelog date-buckets instead"
elif [ "$substantive" = "false" ]; then
  bump_reason="--substantive false — the unit produced no substantive close, so it cannot be a user-observable one"
else
  # Durable per-repo standing judgement, if the owner recorded one.
  #
  # ── THE READER HAS THREE STATES, NEVER TWO (id:65ad hardening) ────────────────────
  # With a FLEET DEFAULT in place, "absent" now MEANS "bump". A line this reader fails to
  # parse must therefore NEVER be conflated with a line that is not there: that converts a
  # fail-LOUD into a SILENT bump against an owner's recorded `never` — a fail-silent in the
  # UNSAFE direction, and it makes the config unfalsifiable. The reader this replaces was a
  # bare `$1 == "bump_policy" { print $3 }` three-field split, which read the perfectly
  # VALID TOML `bump_policy="never"` (no spaces) as ABSENT and minted a version — on exactly
  # the hand-editing path the HANDBACK[bump] text tells a human to take.
  #
  # This is deliberately NOT a TOML parser. It stays awk-shaped and auditable, and emits
  # exactly one of three things:
  #   (nothing)          ABSENT                 => FLEET DEFAULT minor (below)
  #   value<TAB><v>      a parsed RHS           => enum-matched below
  #   unparsed<TAB><l>   PRESENT but unreadable => LOUD HANDBACK[bump], NEVER defaulted
  #
  # PRESENT-BUT-UNPARSED covers a malformed/empty RHS *and* a NEAR-MISS KEY. The near-miss
  # test, pinned by tests/test_bump_policy_fleet_default_65ad.sh (5d/5e): the key —
  # lowercased, with `_`/`-`/whitespace stripped — CONTAINS `bump`. So `bumppolicy`,
  # `bump-policy`, `BUMP_POLICY` and `bump_polcy` are all PRESENT: they sit inside this
  # repo's own block and their intent is unmistakable, so silently contradicting them is
  # worse than refusing. It keys on `bump` and NOT on `policy` ON PURPOSE — an unrelated
  # future `*_policy` key must not start false-tripping this gate. A typo that destroys the
  # `bump` stem (`ump_policy`) still reads as absent; the fuzzy set has to end somewhere,
  # and this boundary keeps the rule to one line.
  #
  # It also tolerates an INDENTED `[repos.<name>]` header and indented keys (valid TOML that
  # the old `$0 == want` / `/^\[/` anchors missed, hiding a whole block's policy), a trailing
  # inline comment, and TOML literal (single-quoted) strings.
  policy="" policy_state="absent" policy_line=""
  policy_toml="${FABLES_CONFIG:-$HOME/.config/relay}/relay.toml"
  if [ -f "$policy_toml" ]; then
    policy_read="$(awk -v want="[repos.$repo]" -v sq="'" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      {
        line = trim($0)
        if (line == "" || substr(line, 1, 1) == "#") next
        if (line == want) { inblk = 1; next }
        if (substr(line, 1, 1) == "[") { if (inblk) exit; next }
        if (!inblk) next
        eq  = index(line, "=")
        key = (eq ? trim(substr(line, 1, eq - 1)) : line)
        if (key == "bump_policy") {
          val = (eq ? trim(substr(line, eq + 1)) : "")
          q = substr(val, 1, 1)
          if (q == "\"" || q == sq) {                 # quoted: up to the closing quote
            rest = substr(val, 2); p = index(rest, q)
            val = (p ? substr(rest, 1, p - 1) : "")   # unterminated => unparsed, not absent
          } else {                                    # bare: drop inline comment + comma
            h = index(val, "#"); if (h) val = trim(substr(val, 1, h - 1))
            sub(/,$/, "", val); val = trim(val)
          }
          if (val == "") print "unparsed\t" line; else print "value\t" val
          done = 1; exit
        }
        nk = tolower(key); gsub(/[-_ \t]/, "", nk)
        if (fuzzy == "" && index(nk, "bump")) fuzzy = line
      }
      END { if (!done && fuzzy != "") print "unparsed\t" fuzzy }
    ' "$policy_toml" 2>/dev/null || true)"
    if [ -n "$policy_read" ]; then
      policy_state="${policy_read%%$'\t'*}"
      policy_line="${policy_read#*$'\t'}"
      if [ "$policy_state" = "value" ]; then policy="$policy_line"; fi
    fi
  fi
  if [ "$policy_state" = "unparsed" ]; then
    handback bump "$EX_BUMP" \
      "SEMVER BUMP TRIGGER UNRESOLVABLE for [$repo] (id:e647 / id:65ad): [repos.$repo] in $policy_toml carries a line about bump_policy that this reader could NOT parse into a value — \`$policy_line\`. PRESENT-BUT-UNPARSED is NOT the absent case and is NEVER given the fleet default: defaulting here would silently BUMP against a policy you may have recorded as 'never', which is the unsafe direction. NOTHING was mutated — main is byte-identical and the worktree is on disk. Resolve by writing the key EXACTLY as bump_policy = \"never|minor|patch\" in [repos.$repo] of $policy_toml, or by re-running with --level minor|patch or --internal (which bumps PATCH — since the 2026-08-26 amendment there is no per-close flag that skips a bump)."
  fi
  case "$policy" in
    never)         bump_reason="relay.toml [repos.$repo] bump_policy = never" ;;
    minor|patch)   bump_level="$policy"; bump_reason="relay.toml [repos.$repo] bump_policy = $policy" ;;
    # ── FLEET DEFAULT (id:65ad) — READ THIS BEFORE "TIDYING" IT AWAY ────────────────
    # No explicit bump_policy for this repo => default to `minor`. This is a DELIBERATE,
    # OWNER-RATIFIED OVERRIDE (2026-08-22, meeting D12) of a ratified decision — NOT an
    # accidental config default, and not a convenience.
    #
    # WHAT IT OVERRIDES, stated plainly: meeting 2026-07-17-1541 D1 ratified "one bump per
    # USER-OBSERVABLE close; a refactor-only / internal-cleanup close does NOT bump".
    # There is NO no-bump branch under any LEVEL policy here — a level bumps on EVERY
    # integrate — so under this default a refactor-only close WILL mint a version,
    # contrary to that rule. The owner accepted that cost knowingly: the trigger it
    # replaces was handing back three repos in a single pool run (puzzle-pwa, csgebra,
    # leAIrn2learn), and it also permanently silences the per-repo escalation the gate
    # existed to force. Whether to add a genuine no-bump branch so D1 can survive under a
    # level policy was SURFACED IN id:65ad and has since been DECIDED — in the opposite
    # direction. On 2026-08-26 the owner amended D1's no-bump half away entirely (*"a
    # refactor/internal can still mess up plenty and must at least bump patch"*), so a
    # refactor-only close minting a version is no longer a "cost accepted knowingly" but
    # the INTENDED behaviour. Do not build a no-bump branch here; `bump_policy = "never"`
    # is the one surviving skip and it is owner-recorded per repo.
    #
    # WHY `minor` AND NOT `patch`: under the loose-0.x rule, `patch` means bugfix-ONLY, so
    # it is the harmful UNDER-signal for a defaulted feature close (it tells a consumer
    # "nothing new here" when something new landed). `minor` is the harmless OVER-signal.
    #
    # SCOPE: manifest repos only — a version-less repo (this one, id:8ef3) resolved several
    # branches above and never reaches here. An EXPLICIT bump_policy, --level, --internal,
    # and --substantive false ALL still outrank this default; it is the last resort.
    "")            bump_level="minor"
                   bump_reason="FLEET DEFAULT bump_policy = minor (id:65ad, owner-ratified 2026-08-22) — no explicit [repos.$repo] bump_policy in $policy_toml" ;;
    # ── PARSED BUT UNRECOGNISED VALUE => WARN AND DEFAULT (id:d51f(b)) ──────────────
    # NOT a handback. Owner decision, 2026-08-22, and a deliberate REVERSAL of id:65ad's
    # first implementation (which handed back on a bad value, reasoning that a silent
    # default makes the config unfalsifiable — sound, but answered better below).
    #
    # WHY THE REVERSAL: the load-bearing guard is WRITER-side, not here. id:d51f(a) makes
    # `relay-state-write.sh toml-set` refuse any bump_policy outside never|minor|patch at
    # the moment an agent writes it, while that agent can still fix it — dissolving the
    # problem at its origin. This reader branch is then near-unreachable DEFENCE IN DEPTH,
    # and a handback here would defer a whole repo over a fault the writer already refuses.
    # (Measured basis for the real failure mode: not a typo, but an agent inventing a
    # plausible-but-absent enum member — `auto`, `none`, `patch-only`.)
    #
    # THE WARNING IS NOT OPTIONAL AND MUST NAME THE VALUE: an unattended --afk pool is
    # precisely where a nameless warning degrades silently. It goes to stderr AND the log.
    #
    # KEEP THE DISTINCTION FROM THE UNPARSED CASE ABOVE: a line that did not PARSE (or a
    # near-miss key) stays a LOUD HANDBACK, because there the reader does not know what the
    # owner wrote. Here it does know, and knows it is not a policy — so it says so and takes
    # the documented default. Do not merge the two branches.
    *)
      bump_level="minor"
      printf 'integrate.sh: WARNING[bump]: [repos.%s] in %s sets bump_policy = "%s", which is not one of never|minor|patch. Falling through to the FLEET DEFAULT minor (id:65ad) and bumping anyway, per id:d51f(b). The primary guard for this is writer-side enum validation in relay-state-write.sh (id:d51f(a)) — if this fired, that guard is missing or was bypassed. FIX THE VALUE in %s.\n' \
        "$repo" "$policy_toml" "$policy" "$policy_toml" >&2
      log "step3c bump-trigger WARNING id:d51f(b): unrecognised bump_policy '$policy' for [$repo] — defaulting to minor"
      bump_reason="FLEET DEFAULT bump_policy = minor after an UNRECOGNISED [repos.$repo] bump_policy = '$policy' (warned; id:d51f(b), owner-decided 2026-08-22)" ;;
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
      # Commit ROADMAP.md **and TODO.md** ONLY if they actually changed (scoped staging,
      # id:debf — never -A/./-u). roadmap-tick.sh also ticks the TODO TWIN of every worked
      # id (single-id-two-views), so the tick can dirty EITHER ledger. Staging only
      # ROADMAP.md left TODO.md modified-but-uncommitted in the CANONICAL checkout: the run
      # reported clean, step 8's `git-lock-push --ff-only` never reaches the id:aa93
      # tracked-dirty guard (that guard lives in the rebase branch), and one round later the
      # repo classified `dirty_block` with every later integrate.sh handing back at step-1
      # EX_CLEAN_TREE **permanently** — the tick is idempotent, so a retry cleared nothing
      # (id:e82e). An id with no TODO twin leaves TODO.md untouched, so the porcelain check
      # simply narrows to ROADMAP.md and no empty commit is made.
      # Each ledger is named ONLY if it exists on disk: `git add -- <missing>` is a fatal
      # pathspec error (exit 128), and a repo with no TODO.md is perfectly normal.
      tick_paths=()
      [ -e "$path/ROADMAP.md" ] && tick_paths+=(ROADMAP.md)
      [ -e "$path/TODO.md" ] && tick_paths+=(TODO.md)
      if [ "${#tick_paths[@]}" -gt 0 ] && [ -n "$(git -C "$path" status --porcelain -- "${tick_paths[@]}" 2>/dev/null)" ]; then
        git -C "$path" add -- "${tick_paths[@]}"
        git -C "$path" commit -q -m "chore(roadmap): tick worked items + TODO twins [id:$ids]" \
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

# ── THE LAND POINT — id:5fe2, re-derived by id:4d44, GENERALISED by id:a726(a). ──────
#    The merge is committed AND now TAGGED, so from this line on a re-run is WRONG for EVERY
#    unit, substantive or not: it takes the zero-commit path and tries to mint a SECOND ckpt
#    tag. `landed` used to be set only on the deferred / no-upstream / verified-push paths, so
#    a unit whose push FAILED handed back with `landed` still empty; relay-loop.js then read
#    that as `deferred:true` — documented "Retry is correct." — for a merge that was already
#    on main and already tagged. The retry does not double-tag (id:8739's isolation gate stops
#    it at exit 21), but it reports a FALSE main-checkout breach for a unit that is really
#    "already merged and tagged, push failed". The marker belongs at the tag, unconditionally.
landed=1

# ── step 8: PER-REMOTE push narrowing (id:4d44) ──────────────────────────────────────
#
#    A SUBSTANTIVE unit no longer defers its push WHOLESALE. It pushes the PRIVATE/LAN
#    remotes automatically (those are not publication — nothing leaves the fleet) and defers
#    ONLY the non-local/public ones, which are the ones owner ratification exists to gate.
#    A NON-SUBSTANTIVE unit is UNCHANGED: every remote is pushed, as before.
#
#    THE PREDICATE IS NOT DEFINED HERE. relay/scripts/lib-private-remote.sh is the ONE copy,
#    shared with hooks/pre-push-privacy-gate.sh. It reads the PRIVATE, never-committed
#    pattern file at runtime, which is the only way this fleet's named LAN hosts classify at
#    all. git-lock-push.sh's is_ssh_url() is NOT a substitute — it answers "needs SSH auth",
#    so it calls ssh://github.com/... private and would AUTO-PUBLISH agent work.
#
#    FAIL DIRECTION — UNPROVEN IS PUBLIC. An unreadable lib, an unreadable pattern file, an
#    unresolvable remote URL: all yield "public" ⇒ DEFER. Never auto-publish on a guess.
#
#    Selection happens inside git-lock-push.sh via its `--remote` flag (id:4d44 piece A), NOT
#    by pushing per-remote from here: the flock IS that helper (id:aa93), and the two
#    rejected alternatives (bare per-remote `git push`; a temporary
#    `remote.<name>.pushurl=no_push`) drop the lock and mutate shared repo config
#    respectively.
#
# ── step 8 PART ZERO (id:99b7): THE DO-PUBLISH ALLOWLIST RUNS *BEFORE* THE PRIVACY QUESTION ─
#
#    id:4d44 (above) INFERRED the publish question from the privacy one — "not provably
#    private ⇒ a public remote awaiting owner ratification". That inference fails OPEN, and
#    for a PUBLISHING decision that is the wrong way round. Observed: git-annex's `upstream`
#    is `git://git-annex.branchable.com/`, a third-party project this repo forks and only ever
#    FETCHES from. It was recorded as awaiting ratification (four entries that can NEVER
#    resolve, one more per integrate) and — because the NON-SUBSTANTIVE path below pushed
#    EVERY remote — a push to a stranger's repository was actually ATTEMPTED on 2026-08-27.
#
#    The owner ratified an explicit do-publish ALLOWLIST, INVERTING the offered scheme-based
#    exclusion: declare the remotes we DO publish to, and everything else is not a publish
#    target at all. An allowlist fails CLOSED. The result is a THREE-WAY semantic the old
#    private/public split could not express:
#
#      private + DECLARED  ⇒ push IMMEDIATELY                (unchanged, id:4d44)
#      public  + DECLARED  ⇒ push GATED by ratification      (unchanged, id:4d44)
#      UNDECLARED          ⇒ NEVER pushed, NEVER queued, and SURFACED LOUDLY
#
#    UNDECLARED IS UNCONDITIONAL. It is decided BEFORE `$defer_push` is consulted, so the
#    NON-SUBSTANTIVE path can no longer "push everything": "never push, never track" carries
#    no substantive-ness qualifier. This NARROWS id:4d44 case 4 — flagged for the owner.
#
#    AND IT IS NEVER SILENT. The mirror failure is the dangerous one: add a real GitHub
#    remote, forget to declare it, and a pure allowlist publishes nothing AND says nothing.
#    Every exclusion therefore emits a LOUD stderr line naming the remote. Do not "tidy" that
#    line away, and do not downgrade it to log() — the log is not read.
push_pushed=""      # newline-separated: remotes VERIFIED to carry HEAD
push_deferred=""    # newline-separated: remotes deliberately NOT pushed (public/unproven)
push_unreached=""   # newline-separated: intended but did NOT arrive for a benign reason
push_undeclared=""  # newline-separated: id:99b7 — not in the publish set; never a push target
push_lines=""       # `pushRemote=<name>:<status>` stdout lines, in `git remote` order

# NOTE (id:a726(a)): the `if [ -n "$defer_push" ]; then landed=1; fi` that used to sit here is
# GONE — not because the deferred path stopped being landed, but because EVERY path is, from
# the ckpt tag onwards. The marker now lives immediately after step 7 (see THE LAND POINT).

# Source the shared predicate. Unreadable → every remote stays unproven ⇒ public ⇒ deferred.
priv_lib_ok=0
if [ -r "$LIB_PRIVATE_REMOTE" ]; then
  # shellcheck source=./lib-private-remote.sh
  . "$LIB_PRIVATE_REMOTE"
  priv_lib_ok=1
else
  log "step8 id:4d44 lib-private-remote.sh UNREADABLE at $LIB_PRIVATE_REMOTE — no remote can be PROVEN private, so every remote is treated as PUBLIC (fail-closed: defer, never auto-publish)"
fi

# Source the do-publish resolver and materialise THIS repo's declared set once (id:99b7).
# UNREADABLE LIB ⇒ the built-in floor `origin` alone. That is the safe direction in BOTH
# senses: it can never authorise a PUBLIC push (origin is this fleet's private LAN host in
# 41 of 46 own repos), and it does not wedge the fleet by declaring nothing at all.
publish_set=""
if [ -r "$LIB_PUBLISH_REMOTE" ]; then
  # shellcheck source=./lib-publish-remote.sh
  . "$LIB_PUBLISH_REMOTE"
  publish_set="$(publish_declared_remotes "$repo")"
else
  publish_set="origin"
  printf 'integrate.sh: WARNING[publish] (id:99b7): lib-publish-remote.sh UNREADABLE at %s — falling back to the built-in floor publish set `origin` ONLY. Any other remote of [%s] is NOT IN THE PUBLISH SET for this run: not publishing, not tracking.\n' \
    "$LIB_PUBLISH_REMOTE" "$repo" >&2
  log "step8 id:99b7 lib-publish-remote.sh UNREADABLE at $LIB_PUBLISH_REMOTE — publish set floors to 'origin'"
fi
log "step8 id:99b7 publish set for [$repo]: [$(printf '%s' "$publish_set" | tr '\n' ' ')]"

# Classify every remote. `no_push` pushurls are not remotes at all for this purpose —
# git-lock-push.sh skips them by the same rule, so they are neither pushed nor deferred.
to_push="" eligible_count=0
all_remotes="$(git -C "$path" remote 2>/dev/null || true)"
for _r in $all_remotes; do
  _rurl="$(git -C "$path" remote get-url --push "$_r" 2>/dev/null || true)"
  if [ "$_rurl" = "no_push" ]; then
    push_lines="${push_lines}pushRemote=$_r:no-push-url"$'\n'
    continue
  fi
  # ── id:99b7 — THE ALLOWLIST GATE, ahead of everything else. ────────────────────────
  # An UNDECLARED remote is not "a public remote awaiting ratification" and not "a remote we
  # failed to push": it is NOT A PUBLISH TARGET. It never enters `to_push` (so it is never
  # pushed and never verified), never enters `push_deferred` (so it never reaches
  # `pushPending=` and never mints a ratification-queue entry that no owner action could
  # ever resolve), and it is NOT counted as eligible (so it cannot degrade the aggregate
  # `push=` token — we were never going to publish there).
  #
  # THE LOUD LINE IS HALF THE FEATURE, not garnish. Without it the allowlist's own mirror
  # failure — an owner adds a GitHub remote and forgets to declare it, so nothing publishes
  # and nothing complains — is completely invisible. stderr, not log(), on purpose.
  #
  # The remote URL is deliberately NOT printed: an undeclared remote may be an internal host,
  # and this line can end up in relay status output that is committed to a PUBLIC repo. The
  # URL goes to the private log instead.
  if ! publish_set_contains "$publish_set" "$_r"; then
    push_undeclared="${push_undeclared}${_r}"$'\n'
    push_lines="${push_lines}pushRemote=$_r:undeclared"$'\n'
    printf 'integrate.sh: UNDECLARED REMOTE (id:99b7): [%s] remote %s is NOT IN THE PUBLISH SET — not publishing, not tracking. Declared for this repo: [%s]. If you DO want to publish there, add it to `publish_remotes` in [repos.%s] of %s; if you do not, this line is the expected outcome and needs no action.\n' \
      "$repo" "$_r" "$(printf '%s' "$publish_set" | tr '\n' ' ')" "$repo" "$(publish_remotes_toml_file 2>/dev/null || printf '%s' "${FABLES_CONFIG:-$HOME/.config/relay}/relay.toml")" >&2
    log "step8 id:99b7 remote '$_r' ($_rurl) is UNDECLARED — never pushed, never queued"
    continue
  fi
  eligible_count=$(( eligible_count + 1 ))
  if [ -z "$defer_push" ]; then
    to_push="${to_push}${_r}"$'\n'                       # non-substantive: push everything
  elif [ "$priv_lib_ok" = 1 ] && is_private_remote_url "$_rurl"; then
    to_push="${to_push}${_r}"$'\n'                       # substantive: private/LAN → push
  else
    push_deferred="${push_deferred}${_r}"$'\n'           # substantive: public/unproven → defer
    log "step8 id:4d44 remote '$_r' is NOT provably private — DEFERRED for owner ratification"
  fi
done

push_out=""
push_helper_failed=""   # id:5155: git-lock-push.sh exited non-zero (recorded, not yet handed back)
if [ -n "$to_push" ]; then
  # ALL eligible remotes selected AND nothing deferred → invoke git-lock-push.sh with
  # --all, so the non-substantive path still pushes every eligible remote.
  #
  # id:a73b (2026-08-26) — git-lock-push.sh's ABSENT-flag default flipped from "push ALL
  # remotes" to "push origin ONLY" (owner directive: the old default was a
  # publish-by-default footgun). This call site is the one place that deliberately
  # RELIED on the old default to mean "push everything" — it must now say so explicitly
  # via --all, or a repo with 2+ eligible private remotes would silently push only
  # origin here. --remote subset selection below (the substantive/deferred path) is
  # unaffected — it already named every remote explicitly.
  # id:99b7 — `--all` means EVERY remote of the repo, INCLUDING an undeclared one. So the
  # `--all` shortcut is now valid only when NOTHING was withheld at all: no deferred remote
  # AND no undeclared one. With an undeclared remote present we must enumerate `--remote`
  # explicitly, or the non-substantive path would push to a third party's repo through the
  # very shortcut this fix exists to close.
  push_args=(--ff-only "$path")
  if [ -n "$push_deferred" ] || [ -n "$push_undeclared" ]; then
    while IFS= read -r _r; do
      [ -n "$_r" ] || continue
      push_args+=(--remote "$_r")
    done <<< "$to_push"
  else
    push_args+=(--all)
  fi
  if ! push_out="$("$GIT_LOCK_PUSH" "${push_args[@]}" 2>&1)"; then
    # id:5155 — this used to `handback git-lock-push` RIGHT HERE, which pre-empted step 8b
    # entirely: the merge and the ckpt tag were already committed, no remote carried them,
    # and NO ratification-queue entry was ever written. The failure is now RECORDED and the
    # per-remote verification below still runs, so the queue entry can NAME the remotes that
    # did not receive the merge. The handback itself moved to AFTER the enqueue.
    push_helper_failed=1
    log "step8 id:5155 git-lock-push.sh exited non-zero — recorded, NOT handed back yet; per-remote verification + the ratification enqueue still run: $push_out"
  fi
fi

# ── id:f5d9(a) — VERIFY EACH PUSHED REMOTE; never trust the helper's exit code. ────────
#    OBSERVED 2026-08-21 (run relay-20260821-170128-5042): integrate.sh printed
#    `push=pushed` while origin stayed 10 commits behind, because git-lock-push.sh exits 0
#    having pushed NOTHING (id:dc4f). The exit code is therefore NOT evidence.
#    Verification is now PER REMOTE — a single-@{upstream} check could not see a second
#    remote silently missing the push, and under narrowing the remote that matters may not
#    be the upstream one at all.
#    Compared against HEAD, not $merged_head: bump/changelog/archive/tick commits land on
#    top of the merge, so HEAD is the sha the push actually had to carry.
pushed_sha="$(git -C "$path" rev-parse HEAD)"
push_branch="$(git -C "$path" rev-parse --abbrev-ref HEAD)"
push_failures=""
push_failed=""      # id:5155: newline-separated names of the remotes that FAILED verification
if [ -n "$to_push" ]; then
  while IFS= read -r _r; do
    [ -n "$_r" ] || continue
    # git-lock-push.sh DECLINES an SSH remote when no key is loaded in the agent, by design,
    # and says so. That is not a failed push — record it honestly as unreached rather than
    # manufacturing a handback for a documented, benign skip.
    # Substring match via `case`, NOT `… | grep -q …`: a producer piped into an
    # early-exiting consumer under `set -o pipefail` is banned repo-wide (id:81d5).
    if case "$push_out" in *"skipping remote '$_r' (SSH, no key loaded"*) true ;; *) false ;; esac; then
      push_unreached="${push_unreached}${_r}"$'\n'
      push_lines="${push_lines}pushRemote=$_r:skipped-no-ssh-key"$'\n'
      log "step8 remote '$_r' SKIPPED by git-lock-push.sh (SSH, no key in agent) — treated as UNREACHED, not as a push failure"
      continue
    fi
    remote_sha=""
    for _try in 1 2; do
      remote_sha="$(git -C "$path" ls-remote "$_r" "refs/heads/$push_branch" 2>/dev/null | awk 'NR==1{print $1}')" || remote_sha=""
      [ -n "$remote_sha" ] && break
    done
    if [ -z "$remote_sha" ]; then
      # UNVERIFIABLE is treated as NOT landed — fail closed. A silent false success is the
      # exact defect being fixed.
      push_lines="${push_lines}pushRemote=$_r:FAILED"$'\n'
      push_failed="${push_failed}${_r}"$'\n'
      push_failures="${push_failures}[$_r] 'git ls-remote $_r refs/heads/$push_branch' returned NOTHING after 2 attempts — no evidence the remote moved. "
    elif [ "$remote_sha" != "$pushed_sha" ]; then
      push_lines="${push_lines}pushRemote=$_r:FAILED"$'\n'
      push_failed="${push_failed}${_r}"$'\n'
      push_failures="${push_failures}[$_r] is at $remote_sha while the local HEAD it had to carry is $pushed_sha. "
    else
      push_pushed="${push_pushed}${_r}"$'\n'
      push_lines="${push_lines}pushRemote=$_r:pushed"$'\n'
      # id:5fe2 — the remote HAS the merge + tag: every later handback is
      # LANDED-BUT-UNFINISHED, never a retryable defer.
      landed=1
      log "step8 push VERIFIED: $_r/$push_branch == $pushed_sha"
    fi
  done <<< "$to_push"
fi
while IFS= read -r _r; do
  [ -n "$_r" ] || continue
  push_lines="${push_lines}pushRemote=$_r:deferred"$'\n'
done <<< "$push_deferred"

# Count non-empty lines. `awk 'NF'` (not `grep -c .`) — grep exits 1 on no match, which under
# `set -e` inside a command substitution is a needless trap, and awk never early-exits.
_count() { printf '%s' "${1:-}" | awk 'NF{n++} END{print n+0}'; }
n_pushed="$(_count "$push_pushed")"
n_deferred="$(_count "$push_deferred")"
n_unreached="$(_count "$push_unreached")"
n_failed="$(_count "$push_failed")"
# id:5155 — a FAILED remote is a MISSING remote. It used to be counted in neither
# `n_missing` nor the step-8b gate, so a merge that reached ZERO remotes could still be
# reported `ratification=none` — the exact inverse of what that token means.
n_missing=$(( n_deferred + n_unreached + n_failed ))

# id:5155 — a non-zero helper exit is itself a failure signal even when every remote happened
# to verify. Fail CLOSED: manufacture a failure record so the unit is queued for the owner
# rather than silently reported as published on the strength of a lie we already caught once.
if [ -n "$push_helper_failed" ] && [ -z "$push_failures" ]; then
  push_failures="[git-lock-push] the helper exited NON-ZERO while every intended remote verified as carrying $pushed_sha — the two disagree, so this is treated as FAILED (fail-closed). "
fi

# ── the AGGREGATE `push=` token (see the stdout contract at the foot of this file) ──
#   pushed     every eligible remote received the merge, nothing was withheld
#   partial    at least one remote received it AND at least one did not (id:4d44 narrowing)
#   deferred   nothing reached any remote and at least one was withheld
#   no-upstream  the repo has NO eligible remote at all — nothing to push, nothing withheld
#   FAILED     at least one remote was intended, attempted, and could not be VERIFIED
# id:5155 — FAILED is computed HERE, alongside the others, and the handback that reports it
# is deferred until AFTER step 8b. Previously the handback fired from the middle of this
# block, so the enqueue below was unreachable on the one path where an unpublished land is
# most likely (an unreachable LAN origin fails EVERY substantive unit in the run).
if [ -n "$push_failures" ]; then
  push_status="FAILED"
elif [ "$n_pushed" -gt 0 ] && [ "$n_missing" -eq 0 ]; then
  push_status="pushed"
elif [ "$n_pushed" -gt 0 ]; then
  push_status="partial"
elif [ "$n_missing" -gt 0 ]; then
  push_status="deferred"
else
  push_status="no-upstream"
  # Nothing was published, but the merge + tag ARE committed locally — that is the same
  # land point as the deferred path, so the same non-retryable class applies.
  landed=1
fi
# NOTE: there is deliberately NO `defer_push`-based enqueue decision here. id:f0ad moved that
# gate onto `$push_status` at step 8b, after proving that `$defer_push` silently excluded the
# `no-upstream` class; keying it on substantive-ness again — even indirectly — would reopen
# exactly that hole. The single gate lives at step 8b and reads `$push_status` alone.
log "step8 id:4d44 substantive=${substantive:-unset} push=$push_status pushed=[$(printf '%s' "$push_pushed" | tr '\n' ' ')] deferred=[$(printf '%s' "$push_deferred" | tr '\n' ' ')] unreached=[$(printf '%s' "$push_unreached" | tr '\n' ' ')] undeclared=[$(printf '%s' "$push_undeclared" | tr '\n' ' ')]"

# ── step 8b: RATIFICATION ENQUEUE (id:4d44) — the durable surface for an UNPUBLISHED land. ──
#    Append-only JSONL through relay-state-write.sh's flock'd `event-append`, so two
#    concurrent integrates never interleave a partial line. The JSON is built by python3
#    from argv — NEVER string-concatenated — because summary/label carry arbitrary text
#    (the decision-queue.sh convention).
#
#    id:f0ad — THE GATE IS `push_status`, NOT `defer_push`. It used to be `defer_push`, which
#    silently excluded the OTHER unpublished-land class: `no-upstream` (a NON-substantive unit
#    in an upstream-less repo). Both classes are the same durable state — merge committed, tag
#    written, nothing on any remote — so both are queued and both report ratification=pending.
#    A `pushed` unit is never queued; there is nothing to ratify.
#
#    FAIL-CLOSED AND LOUD: if the queue write fails, the merge is sitting unpushed on main
#    with NOTHING telling the owner it exists. That is the one outcome this design cannot
#    have, so it is a HANDBACK, and because `landed` is already set it surfaces as
#    LANDED-BUT-UNFINISHED (surface for reconcile) rather than as a retryable defer.
#
#    id:4d44 PER-REMOTE — HOW id:f0ad's GATE GENERALISES. f0ad moved the gate off
#    `$defer_push` onto `$push_status` precisely so that EVERY unpublished-land class is
#    queued, not just the substantive one. The per-remote rework adds a THIRD such class,
#    so it joins the same case arm rather than getting a parallel gate:
#      deferred     nothing reached any remote (a substantive unit, all remotes public)
#      no-upstream  there was nowhere to push at all                            (id:f0ad)
#      partial      SOME remotes got it, some were withheld                     (id:4d44)
#    All three are the same durable state FOR THE REMOTES CONCERNED — merge committed, tag
#    written, absent from those remotes — so all three queue and all three report
#    ratification=pending. `pushed` is never queued: there is nothing left to ratify.
#    The record NAMES the outstanding remotes (`pending_remotes`) and the ones that already
#    have it (`pushed_remotes`), so a `partial` entry is actionable rather than ambiguous.
#
#    `ratification=none` therefore still means EXACTLY ONE THING, as id:f0ad established —
#    only stated per-remote: every eligible remote carries the merge. For a one-remote repo
#    that is verbatim f0ad's "it was published". For a SUBSTANTIVE unit whose remotes are all
#    private/LAN it is also true: they were pushed, nothing was withheld, nothing awaits the
#    owner. Reporting `none` while ANY remote still lacks the merge is the f0ad defect.
#
# ── id:f0ad — WHY THE ENQUEUE IS *NOT* MOVED AHEAD OF THE CKPT TAG ───────────────────
#    The residual crash window is real: `landed` is set the moment step 7's tag exists, and
#    the queue append happens a few statements later, so a hard kill in between leaves an
#    unpushed merge with no queue entry. Moving the enqueue BEFORE step 7 was considered and
#    REJECTED, because it trades a microsecond crash window for a durable CORRECTNESS defect:
#      • ckpt-tag failure (EX_CKPT, 26) is a PRE-LAND handback — "re-running is CORRECT". A
#        pre-tag enqueue would already have written a `pending` record for that unit. The
#        re-run's merge is a no-op (the branch is now an ancestor of main), so it produces the
#        SAME `merged` sha and appends a SECOND record.
#      • ratify-queue.sh keys entries by ckpt tag OR merged sha and REFUSES an ambiguous key
#        ("an ambiguous key is a loud refusal, never a guess"). Two records sharing one sha
#        are therefore permanently UNRESOLVABLE — the queue wedges on exactly the unit it was
#        supposed to protect.
#      • the pre-tag record could not carry `ckpt` at all, and that field is what
#        ratify-queue.sh's tag-parity check (`PARTIAL: … carries the merge but NOT its
#        checkpoint tag`) reads.
#    So the ordering stands. The window is NOT closed, and is not claimed to be: the honest
#    recovery is that the ckpt TAG is itself durable in git, so an orphaned land is
#    recoverable by finding a local-ahead main carrying a `relay-ckpt-*` tag with no queue
#    entry. Closing it properly needs a two-phase record (write `landing` pre-tag, promote it
#    post-tag) which changes the queue contract ratify-queue.sh consumes — an owner call, not
#    a silent widening here.
#
#    id:5155 ADDS THE FOURTH CLASS — `FAILED`. It was missing from this arm, and the
#    push-failure handback fired BEFORE this line anyway, so a landed merge that reached ZERO
#    remotes produced no queue entry at all and reported `ratification=none`. Both halves are
#    fixed: FAILED joins the arm, and the handback now fires AFTER the enqueue. A failed
#    remote is a PENDING remote — it is in `pending_remotes` exactly like a deferred one,
#    because from the owner's side the state is identical: the merge is not there.
case "$push_status" in deferred|no-upstream|partial|FAILED) ratify_enqueue=1 ;; *) ratify_enqueue="" ;; esac
if [ -n "$ratify_enqueue" ]; then
  pending_csv="$(printf '%s%s%s' "$push_deferred" "$push_unreached" "$push_failed" | awk 'NF{printf "%s%s", sep, $0; sep=","}')"
  pushed_csv="$(printf '%s' "$push_pushed" | awk 'NF{printf "%s%s", sep, $0; sep=","}')"
  ratify_line="$(python3 - "$RATIFY_QUEUE" "$repo" "$path" "$branch" "$worktree" "$merged_head" "$ckpt_tag" \
                   "$run" "$verdict" "$ids" "${bump_version:-}" "$summary" "$label" "${substantive:-unset}" \
                   "$push_status" "$pending_csv" "$pushed_csv" <<'PYEOF'
import json, sys, datetime
(_q, repo, path, branch, worktree, merged, ckpt, run, verdict, ids,
 bump, summary, label, substantive, push_status, pending_csv, pushed_csv) = sys.argv[1:18]
pending = [r for r in pending_csv.split(",") if r]
pushed = [r for r in pushed_csv.split(",") if r]
# id:f0ad — the record must say WHICH unpublished class this is, and the remediation must
# match it. A `no-upstream` repo has no remote to push to, so telling the owner to
# `git push --follow-tags` would hand him a command that cannot work.
# id:4d44 extends that principle rather than replacing it: when the remotes are KNOWN, the
# remediation names them, because a `partial` unit's bare `git push --follow-tags` would be
# just as misleading — it hides which remotes are already published and which are not.
if push_status == "no-upstream":
    action = ("this checkout has NO upstream, so the merge + tag are LOCAL-ONLY with nowhere to "
              "go: add/authorise a remote for %s and push it (git -C %s push -u <remote> HEAD "
              "--follow-tags), or record that this repo is deliberately local-only" % (repo, path))
elif pending:
    action = ("review the merge, then push the remotes that did NOT receive it: "
              + "; ".join("git -C %s push --follow-tags %s" % (path, r) for r in pending))
else:
    action = ("review the merge, then push it: git -C %s push --follow-tags" % (path,))
print(json.dumps({
    "kind": "ratification-pending",
    "id": "id:4d44",
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "pending",
    "repo": repo,
    "path": path,
    "branch": branch,
    "worktree": worktree,
    "merged": merged,
    "ckpt": ckpt,
    "run": run,
    "verdict": verdict,
    "ids": [i for i in ids.split(",") if i],
    "bump": bump,
    "substantive": substantive,
    "summary": summary,
    "label": label,
    # id:f0ad — the record carries the REAL class, not a hardcoded "deferred".
    # id:4d44 per-remote adds WHICH remotes are still pending and which already carry the
    # merge. ratify-queue.sh's `resolve` verification reads `pending_remotes` so it can never
    # resolve an entry by checking a remote that was already pushed while a genuinely pending
    # one still lacks the merge.
    "push": push_status,
    "pending_remotes": pending,
    "pushed_remotes": pushed,
    "action": action,
}, ensure_ascii=False))
PYEOF
)" || handback ratify-enqueue "$EX_RATIFY" "could not RENDER the id:4d44 ratification record for [$repo] — the merge $merged_head + tag $ckpt_tag are committed locally and UNPUSHED with no durable queue entry; record them by hand"
  if ! printf '%s\n' "$ratify_line" | "$STATE_WRITE" event-append "$RATIFY_QUEUE" >/dev/null 2>&1; then
    handback ratify-enqueue "$EX_RATIFY" "could not APPEND the id:4d44 ratification record to $RATIFY_QUEUE for [$repo] — the merge $merged_head + tag $ckpt_tag are committed locally and UNPUSHED with no durable queue entry; record them by hand. Queue line was: $ratify_line"
  fi
  ratify_status="pending"
  log "step8b id:4d44 ratification queued in $RATIFY_QUEUE: repo=$repo merged=$merged_head ckpt=$ckpt_tag push=$push_status pending=[$pending_csv] pushed=[$pushed_csv]"
else
  log "step8b id:4d44/id:f0ad NO ratification entry: push=$push_status — every eligible remote ($(printf '%s' "$push_pushed" | tr '\n' ' ')) received the merge, so nothing is waiting for the owner"
fi

# ── step 8c: the PUSH-FAILURE handback (id:f5d9(a)), MOVED here by id:5155. ──────────
#    It used to fire from the middle of step 8, which pre-empted the enqueue above entirely.
#    The unit IS landed (merge committed, ckpt tag written) and is now ALSO queued, so this
#    surfaces as LANDED-BUT-UNFINISHED with `ratification=pending` — never as a retryable
#    defer, and never as the `ratification=none` that the stdout contract defines as "every
#    eligible remote carries the merge".
if [ -n "$push_failures" ]; then
  handback git-lock-push "$EX_PUSH" "push=FAILED (id:f5d9(a)/id:5155): the push could NOT be VERIFIED for at least one remote. The exit code is not evidence (id:dc4f); the merge + tag are committed locally at $pushed_sha, $n_pushed of the intended remote(s) did receive them, and this unit IS recorded in the ratification queue (ratification=$ratify_status). Per-remote evidence: $push_failures Helper output: $push_out"
fi

# ── step 9: worktree-retire (id:373e force-free; id:6e02 scope = EXACTLY this pair). ──
#    No globbing, no discovery — the two artifacts named on the command line, nothing else.
retire_note=""
if ! retire_note="$("$WORKTREE_RETIRE" "$path" "$worktree" "$branch" --expect-merged 2>&1)"; then
  handback worktree-retire "$EX_RETIRE" "worktree-retire failed (branch merged+tagged, push=$push_status; worktree left on disk for supervised reconcile): $retire_note"
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

log "DONE repo=$repo merged=$merged_head ckpt=$ckpt_tag push=$push_status ratification=$ratify_status bump=${bump_version:-none} postSig=${post_sig:-<empty>} openRoutine=$open_routine openHard=$open_hard"
# ── Machine-readable output contract: one KEY=VALUE per line (parsed by relay-loop.js's
#    parseIntegrateResult, id:087b). Values are single-line by construction.
printf 'merged=%s\n' "$merged_head"
printf 'ckpt=%s\n'   "$ckpt_tag"
# id:f5d9(a) — every `pushed` here is a VERIFIED remote-ref match, never the helper's exit code.
#
# id:4d44 PER-REMOTE CONTRACT. `push=` is the AGGREGATE token over all eligible remotes:
#   pushed | partial | deferred | no-upstream | FAILED
# and the PER-REMOTE detail follows as 0..n `pushRemote=<name>:<status>` lines, in
# `git remote` order, with status ∈ pushed | deferred | FAILED | skipped-no-ssh-key |
# no-push-url. `pushPending=` is the comma-separated list of remotes that did NOT receive the
# merge (empty when none). `push=` stayed a single aggregate token DELIBERATELY: three
# consumers (relay-loop's RELAY_STATUS line, its landedWhere prose, and the existing
# integrate tests) read it as one word, and splitting it would have broken them silently —
# the per-remote truth is ADDED alongside, never hidden.
#
# id:99b7 — an `undeclared` remote is DELIBERATELY absent from `pushPending=`. That key means
# "did not receive the merge but was supposed to"; an undeclared remote was never a publish
# target, so listing it there would mint exactly the unresolvable owner-action entry this
# change removes. Its evidence is its own `pushRemote=<n>:undeclared` line plus a LOUD stderr
# line — never silence.
#
# `ratification=pending` ⇔ at least one remote is still missing the merge (or it reached
# none at all) and the durable queue entry NAMES them; `ratification=none` ⇔ every eligible
# remote carries it. See step 8b's header for the full definition.
# id:5155 — that ⇔ now holds on the FAILED path too. A remote whose push could not be
# VERIFIED counts as MISSING, so a landed merge that reached zero remotes is queued and
# reports `ratification=pending` (on the handback's stderr block); `ratification=none` is
# emitted ONLY when every eligible remote demonstrably carries the merge.
printf 'push=%s\n'   "$push_status"
if [ -n "$push_lines" ]; then
  printf '%s' "$push_lines"
fi
printf 'pushPending=%s\n' "$(printf '%s%s%s' "$push_deferred" "$push_unreached" "$push_failed" | awk 'NF{printf "%s%s", sep, $0; sep=","}')"
printf 'ratification=%s\n' "$ratify_status"
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
