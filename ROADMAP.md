# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

<!-- 2026-07-15 review mini-handoff (run relay-20260715-121544-12169): relay-doctor
     surfaced two INBOUND inbox dead-letters (routed:2365 + routed:8653) reporting a real
     crash in the shipped id:1750 offline @needs-auth lister. Reproduced + root-caused:
     an executor-ready [ROUTINE] one-liner with a RED spec. Fresh id b8c2 (genuinely new
     follow-up work, not tracked in TODO); both routed: tokens carried on the line below so
     scan-routed --apply drains both inbox entries once this lands. -->

- [x] [ROUTINE] `gather-human-backlog.sh --needs-auth <repo>` crashes `path: unbound variable` — split the `local` in `list_needs_auth_repo` <!-- routed:2365 --> <!-- routed:8653 --> <!-- id:b8c2 -->
  - **Why** (INBOUND routed:2365 + routed:8653; relay-doctor 2026-07-15): the offline lister's
    named-arg branch (`run_needs_auth_lister`, `for name in "$@"` → `list_needs_auth_repo "$name"
    "${PATH_OF[$name]:-$SRC_DIR/$name}"`) dies under `set -u` on EVERY explicit repo-name
    invocation: `relay/scripts/gather-human-backlog.sh: line 362: path: unbound variable`. Root
    cause: `list_needs_auth_repo` opens `local name="$1" path="$2" file="$path/REVIEW_ME.md"` —
    bash expands all RHS words of one `local` command BEFORE any assignment takes effect, so
    `$path` in the `file=` word resolves against the CALLER's scope. The default no-arg branch
    survives by accident (its `while read … path` loop leaks a `path` into scope); the named-arg
    branch (`for name in "$@"`) has no `path` in scope, so it crashes. Only the no-arg all-repos
    form works today; `--needs-auth <repo>` (the per-repo view a human would reach for) is 100%
    broken. routed:2365 additionally notes the plugin-path own-repos (e.g. zkm-signal at
    `~/src/zkm/plugins/`) whose name isn't at `$SRC_DIR/<name>` — same crash, same fix.
  - **How / Design**: split the single-line `local` so `path` is assigned before it is
    referenced — e.g. `local name="$1" path="$2"` then a separate `local file="$path/REVIEW_ME.md"`.
    That is the whole fix; do NOT touch the no-arg branch or the awk block. Verify the plugin-path
    own-repos resolve via the `PATH_OF[$name]` lookup (from `own_repos`) rather than the
    `$SRC_DIR/$name` fallback, so a repo whose name isn't a child of `$SRC_DIR` still lists.
  - **Acceptance**: `tests/test_needs_auth_lister_named_repo.sh` (`# roadmap:b8c2`, written RED by
    this review) goes green — `--needs-auth repoNA` (explicit repo-name arg) exits 0, prints the
    repo's @needs-auth box with all four field values, and stderr carries no `unbound variable`.
    Existing `tests/test_needs_auth_lister.sh` (id:1750, no-arg form) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_needs_auth_lister_named_repo.sh tests/test_needs_auth_lister.sh`
    then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/gather-human-backlog.sh` (`list_needs_auth_repo` ~L361-362,
    `run_needs_auth_lister` named-arg branch ~L417-420). Sibling: shipped id:1750 (the lister).
    INBOUND routed:2365 + routed:8653.

<!-- 2026-07-14 handoff C2 (run relay-20260714-123104-912): promoted the two `promote`-
     disposition TODO items (unpromoted-scan @ dotclaude-skills: 2 promote / 1 surface / 16
     laned). Both are the `@needs-auth` co-meet cluster RESOLVED + re-laned `[INPUT — meeting]`
     →`[HARD — pool]` by /meeting 2026-07-14-1135 (docs/meeting-notes/2026-07-14-1135-human-
     manual-task-handling.md, D1–D4). Single-id-two-views (D2): id:a505, id:1750 REUSE their
     open TODO.md twins. Both are `[HARD]` (strong-model: a505 is a VERSIONED executor-contract
     change; 1750 is judgment-laden convention wiring) — left specced for the pool `hard`
     verdict, NOT executed in C5 (contract-surface edits + cross-repo retro-tags exceed a safe
     single-turn C5). a505 is the prerequisite (defines the convention 1750 consumes) so 1750
     carries (DEP: a505). The 1 surface item (id:625a, INBOUND routed:a6be, gated on
     project_manager id:0fc7) is the mechanical `human`-verdict filer's job, NOT promoted here. -->

- [x] [HARD] `@needs-auth` convention + executor-contract rule (D1/D2/D3) <!-- id:a505 -->
  - **Done 2026-07-14** (relay HARD child, id:da26): shipped all of D1/D2/D3 in THIS repo.
    (1) **Convention doc** — new `## The @needs-auth marker` section in
    `relay/references/hard-lanes.md`: broad definition (any human-held secret / interactive
    auth), orthogonal to `@manual`, carrier = a per-repo `REVIEW_ME.md` box (D2, explicitly NO
    global auth-queue file — id:9fdb hazard), FOUR mandatory fields (what-secret · where-it-goes
    · exact-command · why). (2) **Versioned contract rule (D3)** — added rule 6 (record-and-
    continue, default clean-handback when separability uncertain) to
    `relay/references/executor-contract.md` and BUMPED the marker v6→v7; updated the
    `CLAUDE.md` `## Relay contract` pointer AND the §Versioning contract-surface table
    ("currently v7") in the same commit (no version skew). (3) **Recognition wiring** —
    `roadmap-lint.sh` + `gather-human-backlog.sh` document `@needs-auth` as a KNOWN marker
    (never flagged unknown/untagged); the AI-free lister/filter is the co-meet item id:1750
    (NOT built here). Acceptance test `tests/test_needs_auth_convention.sh` (roadmap:a505)
    green; updated `tests/test_relay_executor.sh` v6→v7 version-consistency assertion in
    lockstep. Meeting: `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`.
  - **Why** (TODO id:a505; /meeting 2026-07-14-1135, D1/D2/D3): a relay child that hits an
    interactive-auth / human-held-secret wall today STRANDS the rest of its unit mid-session
    (the a505 filing failure). There is no convention for recording "this needs a human secret"
    and no contract rule telling a child to record-and-continue. The meeting resolved this WITH
    id:1750 as one design: a single `@needs-auth` marker is BOTH the class-(i) hands-lane reason
    and the auth-queue membership predicate.
  - **How / Design** (all in THIS repo — no cross-repo edits):
    1. **Document the `@needs-auth` convention** in a reference doc — extend
       `relay/references/hard-lanes.md` (capability/marker section) and/or
       `relay/references/conventions.md`. Definition is **broad**: any human-held secret OR
       interactive-auth (sudo/askpass, polkit/pamac, ssh/login, gpg/credential, browser-OAuth,
       a decryption passphrase, a private export). It is **orthogonal to `@manual`** (an item
       may carry both — `@needs-auth` = provide a secret; `@manual` = run/verify). The carrier
       is a **per-repo `REVIEW_ME.md` box** (D2 — explicitly NO global `~/.config/relay/auth-
       queue.md` file; that repeats the id:9fdb unversioned-destructive-store hazard). The
       convention **MANDATES four fields** per box: what-secret · where-it-goes · exact-command
       · why.
    2. **Executor-contract rule (D3, VERSIONED):** add a rule to
       `relay/references/executor-contract.md` — a child hitting an interactive-auth/secret wall
       RECORDS a conforming `@needs-auth` REVIEW_ME box instead of failing the unit, then
       clean-continues the separable remainder, **defaulting to clean-handback of the gated
       remainder when separability is uncertain**. BUMP the contract marker
       `<!-- relay-executor contract v6 -->` → v7 in executor-contract.md, AND update the
       `## Relay contract <!-- relay-executor contract v6 -->` pointer in `CLAUDE.md` (line
       ~161) to v7 in the SAME commit (co-located bump discipline, CLAUDE.md §Versioning).
    3. **Recognition wiring:** `relay/scripts/gather-human-backlog.sh` and
       `relay/scripts/roadmap-lint.sh` must RECOGNIZE `@needs-auth` (not flag it as an unknown
       marker). (The lister/filter half is id:1750; here only ensure the marker is a known token.)
  - **Acceptance**: a test (e.g. extend `tests/test_hard_lane_buckets.sh`, `# roadmap:a505`)
    asserts: the `@needs-auth` convention doc lists the four mandatory fields; `roadmap-lint.sh`
    does NOT flag an `@needs-auth`-marked item as unknown/untagged; the executor-contract marker
    is v7 and the `CLAUDE.md` pointer matches v7 (no version skew). The D3 contract rule text is
    present in executor-contract.md. NOTE: this is a `[HARD]` item — write the spec as part of
    execution (no pre-written RED spec from handoff), and keep `make test` green after ticking.
  - **Done-check**: `tests/run-tests.sh tests/test_hard_lane_buckets.sh` then full `make test`
    after ticking; verify no contract-version skew (`grep -rn 'relay-executor contract v' CLAUDE.md relay/references/executor-contract.md` all agree).
  - **Context**: `relay/references/hard-lanes.md`, `relay/references/conventions.md`,
    `relay/references/executor-contract.md` (contract marker + pointer discipline ~L141),
    `CLAUDE.md` (§Relay contract pointer ~L161, §Versioning contract-surface table),
    `relay/scripts/gather-human-backlog.sh`, `relay/scripts/roadmap-lint.sh`. Meeting:
    `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`. Co-meet with id:1750.

- [x] [HARD] Offline `@needs-auth` lister (extend `gather-human-backlog.sh`) + retro-tag the class-(i) backlog (DEP: a505) <!-- id:1750 -->
  - **Done 2026-07-14** (relay HARD child, id:da26): shipped the v1 offline lister in THIS
    repo. `gather-human-backlog.sh --needs-auth [repo...]` now filters every OPEN `@needs-auth`
    REVIEW_ME box across own repos (reusing the existing `own_repos` enumeration + REVIEW_ME
    reader, NOT a new walker) and prints a PLAIN, human-readable (NON-TSV) block per box:
    `repo — title (id)` + the four mandatory fields (what-secret / where-it-goes /
    exact-command / why), a missing field printed `(MISSING)` so a non-conforming box is LOUD.
    The mode is pure bash+awk — AI-free / offline (no `claude -p`, no network), bypassing the
    TSV collector + the HARD-lane untagged-exit path (focused human view, not the classifier
    feed). Default TSV mode is UNCHANGED (a `@needs-auth` box still surfaces as an ordinary
    review_me row per the a505 contract). Acceptance test `tests/test_needs_auth_lister.sh`
    (roadmap:1750) green; existing `test_gather_human_decision.sh` / `test_hard_lane_buckets.sh`
    / `test_needs_auth_convention.sh` / `test_relay_human.sh` all stay green. **Retro-tag
    (step 2) — filed as cross-repo inbox items** (SCOPE BOUNDARY: those five boxes live in
    OTHER repos, unreachable from this worktree): zkm-signal/e588, zkm-threema/7364,
    zkm-chatgpt/ad81, bahnbetAI/c624, zkm/0b37. v2 (interactive step-through + tick-back) stays
    DEFERRED (observe-before-preventing). Meeting: `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`.
  - **Why** (TODO id:1750; /meeting 2026-07-14-1135, D4): `/relay human` surfaces
    human-gated work but costs a Claude session. The one genuine differentiator wanted here is
    an **AI-free, offline** lister of every `@needs-auth` box across own repos — a plain bash
    sweep the human runs with no network and no model. The class-(i) backlog is already real
    (zkm-signal e588, zkm-threema 7364, zkm-chatgpt ad81, bahnbetAI c624, zkm 0b37), so the
    lister earns its keep on day one once those boxes exist.
  - **How / Design** (DEP: a505 — the `@needs-auth` convention + field contract must land first):
    1. **Extend `relay/scripts/gather-human-backlog.sh`** (do NOT fork a new repo-walker —
       reuse its existing own-repo enumeration + REVIEW_ME reader) with a `@needs-auth` filter
       and a **plain, human-readable (non-TSV) output mode**: one line/block per box showing
       repo · what-secret · where · exact-command. It must run **AI-free** (pure bash, no
       `claude -p`, no network).
    2. **Retro-tag the existing class-(i) backlog** with conforming `@needs-auth` REVIEW_ME
       boxes (all four mandatory fields) so the lister has day-one content. **SCOPE BOUNDARY:**
       the five targets (zkm-signal e588, zkm-threema 7364, zkm-chatgpt ad81, bahnbetAI c624,
       zkm 0b37) live in OTHER repos — a relay child works ONE worktree, so those per-repo boxes
       are NOT written from this worktree. File them as cross-repo inbox items
       (`meeting/append.sh -t inbox`, one per target repo) during execution; only the
       `gather-human-backlog.sh` change + a hermetic fixture live in THIS repo.
    3. **v2 (interactive step-through + REVIEW_ME tick-back via flock'd `md-merge.py`) is
       DEFERRED** — gated on v1 lister usage (observe-before-preventing). Do NOT build it now.
  - **Acceptance**: a test (`tests/test_needs_auth_lister.sh`, `# roadmap:1750`) with a hermetic
    fixture repo carrying a `@needs-auth` REVIEW_ME box asserts the lister prints that box with
    ALL FOUR fields (what/where/command/why), runs with no network/AI, and the plain output mode
    is non-TSV human-readable. Existing `gather-human-backlog.sh` tests
    (`tests/test_hard_lane_buckets.sh` and any gather-human-backlog test) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_needs_auth_lister.sh tests/test_hard_lane_buckets.sh`
    then full `make test` after ticking.
  - **Context**: `relay/scripts/gather-human-backlog.sh` (own-repo enumeration + REVIEW_ME
    reader), `relay/references/human.md` (`/relay human --all` aggregation). Cross-repo retro-tag
    targets (inbox, out of this worktree's scope): zkm-signal/e588, zkm-threema/7364,
    zkm-chatgpt/ad81, bahnbetAI/c624, zkm/0b37. Meeting:
    `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`. DEP: id:a505 (convention).
    v2 tick-back deferred under this id's acceptance.

<!-- 2026-07-13 review 5b mini-handoff: qualified two ledger-neutral TODO items the human
     flow-back added (commit 0d1ac39). Both are execution-ready [ROUTINE] with RED specs,
     reusing their TODO ids (single-id-two-views D2): id:1781, id:7f30. -->

- [x] [ROUTINE] `roadmap-lint.sh`: count only the LEADING contiguous lane-bracket run, ignore lane-bracket mentions in trailing audit-trail prose <!-- id:1781 -->
  - **Why** (TODO id:1781, surfaced by leAIrn2learn id:c3f5): the case-c conflict check (`relay/scripts/roadmap-lint.sh` ~L322-350) counts EVERY non-backticked lane bracket on a line. An item whose HEAD tag is a correct single lane but whose BODY cites a prior `[HARD — …]`/`[ROUTINE]` transition in *non-backticked* audit-trail prose (e.g. "(was [HARD — pool] before, re-laned to [ROUTINE])") false-positives the "multiple lane brackets" LOUD-reject. The existing backtick-strip (~L328) only rescues brackets inside a backtick span, not bare audit prose.
  - **How / Design**: the lane tag(s) are the CONTIGUOUS run of lane brackets at the very START of the item text (immediately after `- [ ] `). A lane bracket appearing AFTER any prose word is trailing audit-trail prose and must NOT count toward the conflict. Keep the genuine-conflict path: two contiguous LEADING lane tags (e.g. `[HARD — pool] [ROUTINE] …`) must still ERROR (do not weaken case-c / `test_roadmap_lint_tagprose.sh`). Preserve the backtick-strip and every other grammar check.
  - **Acceptance**: `tests/test_roadmap_lint_trailing_lane_prose.sh` (`# roadmap:1781`, written RED by this review) goes green — a leading `[ROUTINE]` tag with a lane bracket in trailing prose PASSES; two contiguous leading tags still ERROR; a clean single-tag item still passes. Existing `tests/test_roadmap_lint_tagprose.sh`, `tests/test_roadmap_lint.sh`, `tests/test_roadmap_lint_tag_first.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_roadmap_lint_trailing_lane_prose.sh tests/test_roadmap_lint_tagprose.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/roadmap-lint.sh` (bare-lane count + case-c conflict ~L322-350, backtick-strip ~L328). TODO id:1781.

- [x] [ROUTINE] `orphan-scan.sh --shipped`: add an `<!-- xgate:TOKEN@repo -->` marker that bypasses UNMARKED-GATE for a cross-repo gate whose blocking token lives in another repo <!-- id:7f30 -->
  - **Why** (TODO id:7f30, resolving REVIEW_ME id:50c4 option a): a deliberately-unmarked CROSS-REPO gate (e.g. id:50c4 gated on 508d@relay-core) has NO local `gated-on:` edge to point at, so it re-fires UNMARKED-GATE on every `--shipped` scan. The generic `<!-- gate-prose-only -->` marker (id:8800) suppresses the re-fire but DISCARDS which external token/repo blocks it. A dedicated `xgate:TOKEN@repo` marker records that cross-repo dependency explicitly (parseable) while still shrinking the detector.
  - **How / Design**: mirror the shipped `gate-prose-only` bypass (`meeting/orphan-scan.sh` ~L252-261, L341): detect an `<!-- xgate:TOKEN@repo -->` sibling comment and have it BYPASS the UNMARKED-GATE backstop the same way (guard on the `grep -qiE '…gated on…'` branch ~L341). Like `gate-prose-only`, it must NOT set `has_typed` and must NOT suppress the typed-predicate branches (GATE-READY/GATE-BLOCKED/UMBRELLA-*) or the EXTERNAL-WAIT / GATE-STALE paths. Parse `TOKEN@repo` shape loosely (4-hex token, `@`, repo name); a malformed marker should not crash the scan. Also add the marker to id:50c4's TODO line as the first real consumer.
  - **Acceptance**: `tests/test_orphan_scan_xgate.sh` (`# roadmap:7f30`, written RED by this review) goes green — an item carrying `<!-- xgate:508d@relay-core -->` plus gate vocabulary does NOT surface as UNMARKED-GATE, while a control item with the same vocabulary and NO marker still does. Existing `tests/test_orphan_scan_gate_prose_only.sh` (id:8800), `tests/test_orphan_scan_unmarked_gate.sh` (id:4245), `tests/test_orphan_scan_shipped.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_orphan_scan_xgate.sh tests/test_orphan_scan_gate_prose_only.sh tests/test_orphan_scan_unmarked_gate.sh` then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`gate_prose_only` ~L252-261, UNMARKED-GATE backstop ~L332-344). TODO id:7f30; consumer TODO id:50c4.

<!-- 2026-07-12 handoff C2 (focused inbox ingestion): promoted two inbox-routed items from
     today's it-infra zomni KVM/dock RCA (it-infra hosts/zomni/system/kvm-dock/INCIDENTS.md
     2026-07-12). Both are executor-ready [ROUTINE] with RED specs and are INBOUND stubs in
     TODO.md (single-id-two-views): id:3273 carries routed:8a55, id:1b18 carries routed:5434.
     Both harden the same git-diary-workflow push/replay machinery the flap starved. -->

- [x] [ROUTINE] `git-lock-push.sh` push path: bound a stalled ESTABLISHED ssh with a hard `timeout` + ServerAliveInterval/CountMax (not just ConnectTimeout) <!-- routed:8a55 --> <!-- id:3273 -->
  - **Why** (INBOUND routed:8a55 from it-infra, zomni KVM/dock RCA 2026-07-12): the push loop runs `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" git push …` (git-lock-push.sh ~L244/246). `ConnectTimeout` bounds ONLY the TCP connect — an ESTABLISHED ssh whose network dies mid-transfer hangs indefinitely. Observed live: a dock-ethernet flap at 08:55:14 left a `git push` hung 40+ min while it HELD the per-repo flock (`.git-lock-push.lock`), starving every other lock user (quota-sample commits, diary-append) fleet-wide. it-infra's `sessions-backup.sh` was hardened the SAME day (it-infra `~/.claude` commit 9950390f) — mirror that fix here.
  - **How / Design**: two complementary bounds on the push. (a) Add `-o ServerAliveInterval=<N> -o ServerAliveCountMax=<M>` to the push `GIT_SSH_COMMAND` so ssh itself tears down a dead ESTABLISHED connection after ~N·M s of silence (mirror the sessions-backup.sh values). (b) Wrap the `git push` invocation in a hard `timeout` as a belt to ServerAlive's suspenders — read a `GIT_LOCK_PUSH_TIMEOUT` env seam (default a sane production value, e.g. 120) so the timeout is tunable and hermetically testable. On a push that times out, print a LOUD stderr WARNING and follow the script's existing non-fatal contract (work stays committed locally; retries next run — same disposition as the flock-timeout / ff-only-divergence branches), and RELEASE the flock (do not leak fd 8). Apply to BOTH push invocations (existing-branch and `--set-upstream` first-push).
  - **Acceptance**: `tests/test_git_lock_push_stall_timeout.sh` (`# roadmap:3273`, written RED by this handoff) goes green — with a fake ssh that serves upload-pack locally but SLEEPS on receive-pack (an ESTABLISHED-then-dead push), the script SELF-TERMINATES within the `GIT_LOCK_PUSH_TIMEOUT` bound instead of hanging, and the built push ssh command carries `ServerAliveInterval` + `ServerAliveCountMax`. Existing git-lock-push tests (dirty-guard, ff-only, merge-branch, slash-branch) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_git_lock_push_stall_timeout.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/git-lock-push.sh` (the push loop ~L235-248; the flock at ~L115-121; the existing non-fatal WARNING+exit-0 branches to mirror). Cross-repo mirror source: it-infra `sessions-backup.sh` (commit 9950390f wording). INBOUND routed:8a55.

- [x] [ROUTINE] `diary-append.sh`: pull BEFORE replaying quarantined entries so a dirty-tree pull failure can't strand replayed text (deadlock) <!-- routed:5434 --> <!-- id:1b18 -->
  - **Why** (INBOUND routed:5434 from it-infra, zomni RCA 2026-07-12): the replay loop (diary-append.sh ~L153-158) appends every `.diary-pending-*` / `.failed/entry-*` file into DIARY.md and `rm`s it BEFORE `git pull --rebase` (~L166). That append DIRTIES the tree, so the pull refuses ("cannot pull with rebase: You have unstaged changes") and `on_failure` quarantines only the CURRENT entry — the already-appended-and-unlinked replayed text strands as an uncommitted DIARY.md change. The tree stays dirty, so EVERY subsequent run's pull refuses too → deadlock until a human commits by hand. Observed live 2026-07-12 09:51 across two parallel sessions plus a stranded quota-sample line. (Sibling of the shipped id:f8df entry-survival fix — same script, the ordering half.)
  - **How / Design**: reorder so the replay CANNOT dirty the tree before a pull. Preferred: `git pull --rebase origin <branch>` FIRST (on the clean tree), THEN replay the quarantined files + append the current entry into DIARY.md, then a single `git commit` + `git push` — the replayed content rides the same commit. (Acceptable alternative: commit the replayed entries as their OWN commit before the pull.) Preserve BOTH invariants: exactly-once (a replayed entry is appended once and its quarantine file removed only AFTER the commit succeeds) and no-entry-loss (a failure still quarantines to `.failed/` with a loud path — never silent unlink; id:4347 class). Keep the flock + the `DIARY_SKIP_SSH` test seam intact.
  - **Acceptance**: `tests/test_diary_append_replay_before_pull.sh` (`# roadmap:1b18`, written RED by this handoff) goes green — given a pre-existing `.failed/entry-*` quarantine plus fresh entries across two runs, all entries land in COMMITTED+PUSHED history exactly once, the working tree ends CLEAN, and no `.failed/`/`.diary-pending-*` files linger. Existing `tests/test_diary_append_entry_survival.sh` (id:f8df) MUST stay green (the failure-quarantine path is unchanged).
  - **Done-check**: `tests/run-tests.sh tests/test_diary_append_replay_before_pull.sh tests/test_diary_append_entry_survival.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/diary-append.sh` (replay loop ~L153-158, the pull ~L166, `on_failure` ~L141-151). Sibling: id:f8df (entry-survival, shipped). INBOUND routed:5434.

<!-- 2026-07-12 review reverse-handoff (run relay-20260712-210033-21590): the two INBOUND
     inbox items ingested this window (routed:1cda id:8800 from zkm; routed:8b23 id:0f7a from
     it-infra) landed in TODO.md ledger-neutral (no lane, no acceptance). Both are concrete,
     testable ROUTINE fixes with a clear observable done-state, so they are mini-handed-off
     here (§5b) — RED spec written, id REUSED (single-id-two-views, D2). -->

- [x] [ROUTINE] `orphan-scan.sh`: add a `<!-- gate-prose-only -->` marker that bypasses the UNMARKED-GATE backstop for confirmed external-prose gates <!-- routed:1cda --> <!-- id:8800 -->
  - **Why** (INBOUND routed:1cda from zkm): the UNMARKED-GATE backstop (meeting/orphan-scan.sh ~L321-333) surfaces any unmarked line bearing structured gate vocabulary (`gated on`, `blocked until/on`, `Gate:`, `🚧 GATED …`). Its intended resolution is "add a typed `gated-on:` edge OR confirm the gate" — but when the gate's blocking condition is an EXTERNAL prose condition (an upstream vendor shipping an API, a human decision) rather than a local TODO-id dependency, there is NO local id to point a `gated-on:` edge at. The item therefore re-fires UNMARKED-GATE on every `--shipped` scan with no non-hacky resolution, re-litigating the same confirmed gate forever.
  - **How / Design**: add a durable `<!-- gate-prose-only -->` marker that records "this prose gate is confirmed; it intentionally has no typed edge". Detect it alongside the typed-edge markers (`children:`/`gated-on:`, the `has_typed` block ~L248-250) and have it BYPASS the UNMARKED-GATE backstop the same way `has_typed` does (`continue` at ~L313-318, or a guard on the `grep -qiE '…gated on…'` branch at ~L330) — so a confirmed prose-only gate SHRINKS the detector instead of re-firing. The marker must NOT suppress the typed-predicate branches (GATE-READY/GATE-BLOCKED) — it only silences the UNMARKED-GATE advisory. Keep the EXTERNAL-WAIT (`wait_re`) and GATE-STALE (`completion_re`) paths unchanged. (Mirror the `has_typed` "marked, not because a regex got smarter" doctrine in the in-file comment.)
  - **Acceptance**: `tests/test_orphan_scan_gate_prose_only.sh` (`# roadmap:8800`, written RED by this review) goes green — an item carrying `<!-- gate-prose-only -->` plus gate vocabulary does NOT surface as UNMARKED-GATE, while a control item with the same vocabulary and NO marker still does. Existing `tests/test_orphan_scan_unmarked_gate.sh` (id:4245) and `tests/test_orphan_scan_shipped.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_orphan_scan_gate_prose_only.sh tests/test_orphan_scan_unmarked_gate.sh` then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`has_typed` ~L248-250, the typed-marker bypass ~L313-318, the UNMARKED-GATE backstop ~L321-333). INBOUND routed:1cda.

- [x] [ROUTINE] `archive-done.sh`: count nested `###` subsection task lines before pruning a `##` section as empty <!-- routed:8b23 --> <!-- id:0f7a -->
  - **Why** (INBOUND routed:8b23 from it-infra): the empty-section pruner (todo-update/archive-done.sh ~L151-180) splits TODO.md into segments on ANY heading of level ≥2 (`##` AND `###`), so a `### subsection` starts its OWN segment. A `## section` whose tasks all live under a following `### subsection` is then left with an empty body and pruned, orphaning the tasks under it. Recurred twice on it-infra's `## Backup & storage strategy` (2026-07-11), each run re-orphaning the items under the preceding section.
  - **How / Design**: a `## section` is NOT empty when a nested subsection belonging to it carries task lines. Preferred: when computing `has_content` for a level-2 section, INCLUDE the content of following deeper (`###`+) headings until the next same-or-higher-level (`##`) heading — i.e. treat subsections as body of their parent for the empty-check, not as independent prunable segments. (Acceptable alternative: only ever treat level-2 `##` as prune-segment boundaries and keep `###`+ as body of their parent.) Preserve the existing invariants: protected labels (`Done`/`Current`) are never pruned, a genuinely empty `##` (no body, no task-bearing subsection) IS still pruned, and the H1/preamble stays untouched. Keep the prior-commit + aged-date archive gates unchanged.
  - **Acceptance**: `tests/test_archive_done_nested_subsection.sh` (`# roadmap:0f7a`, written RED by this review) goes green — a `## section` whose only tasks live under a `### subsection` survives the prune, and the subsection + its tasks survive with it. Existing `tests/test_roadmap_archive.sh`, `tests/test_archive_done_multiline.sh`, `tests/test_archive_closed.sh` MUST stay green (a truly-empty non-protected section is still pruned).
  - **Done-check**: `tests/run-tests.sh tests/test_archive_done_nested_subsection.sh tests/test_archive_done_multiline.sh` then full `make test` after ticking (RED until then).
  - **Context**: `todo-update/archive-done.sh` (segment split ~L151-165, empty-check + prune ~L167-180). INBOUND routed:8b23.

<!-- 2026-07-11 handoff C2 (run relay-20260711-123559-15556): promoted the executor-ready
     `[ROUTINE]` promote-disposition TODO items (unpromoted-scan: 16 promote / 3 laned / 183
     surface). Single-id-two-views (D2): every id below REUSES its open TODO.md twin.
     Promoted the 6 genuinely executor-ready [ROUTINE] items (clear code change + testable
     acceptance). NOT promoted: the `[INPUT — meeting]`/`[INPUT — access]`-tagged "promote"
     rows (77f3/4299/b444/33c2/a505/7b23/b8ae/d0da — a lane a handoff can't decide; surface
     items are the mechanical `human`-verdict filer's job, handoff.md §surface); id:02c7
     (POSIX ACLs) is access-gated on the still-unprovisioned relay-ro/relay-svc OS users
     (id:13ae) so its "relay-ro CANNOT write" test is un-runnable — left for the access lane;
     id:2e6d parent is largely SHIPPED and its child id:7d97 (user:-prefix + emphasis
     invariants) was ALREADY SHIPPED (commit 6bc2817, test12/13 in test_memory_index.sh green)
     — so neither is promoted; 2e6d's only remainder is the [INPUT — user] settings.json
     hook install. -->

<!-- 2026-07-11 handoff (run relay-20260711-123559-15556, 2nd child): the classifier
     RE-fired `handoff` (8 promote) even though the 1637 handoff already promoted the real
     [ROUTINE] work and correctly refused the 8 `[INPUT — meeting|access]` rows. ROOT CAUSE
     found + specced below as id:719a: `unpromoted-scan.sh primary_lane()` doesn't know the
     new-vocab tags, so those 8 human-gated items are false-positive `promote`d and the
     promote count never drops → the loop re-dispatches a no-op handoff every round. This is
     the durable fix that stops the re-dispatch; nothing else was executor-promotable. -->

- [x] [ROUTINE] `unpromoted-scan.sh` `primary_lane()`: recognize the NEW capability-keyed lane vocabulary so `[INPUT — *]` items stop false-positive `promote`ing <!-- id:719a -->
  - **Why** (observed 2026-07-11, run relay-20260711-123559-15556): the dual-vocab window is still OPEN (id:7df1 gated), so live TODO items carry new-vocab tags (`[INPUT — meeting|access|decision]`, bare `[HARD]`, `[MECHANICAL]`). `primary_lane()`'s two tag lists (the bold-anchor branch and the leftmost-tag-anywhere branch) enumerate ONLY old-vocab tags (`[ROUTINE]`, `[HARD — pool|meeting|hands|decision gate]`). A new-vocab-prefixed item — `- [ ] [INPUT — meeting] **title** …` — fails the bold-title anchor (the tag sits BEFORE the `**`, not after it), falls through to the leftmost-scan, which doesn't know `[INPUT — meeting]` and so matches a `[ROUTINE]`/`[HARD — pool]` token appearing DEEP IN THE ITEM'S PROSE → returns it → disposition `promote`. Effect this run: all 8 of this repo's `[INPUT — meeting|access]` items (77f3/4299/b444/33c2/a505/7b23/b8ae/d0da) counted `promote`, so `classify-repo.sh` emitted a spurious `handoff` verdict (should be `human` per the promote==0 ∧ surface>0 case-b split, id:5eb3) and dispatched an Opus handoff child with nothing executor-promotable to do — TWICE (1637 + this run). Same anchoring-failure CLASS as existing test case (i) / id:4da4; new trigger (a new-vocab tag defeats the bold anchor). This is the id:4d8e "pin each observed discovery failure as a RED fixture" discipline.
  - **How / Design**: extend `primary_lane()` (in `relay/scripts/unpromoted-scan.sh`) to (a) add the new-vocab tags — `[INPUT — meeting]`, `[INPUT — access]`, `[INPUT — decision]`, bare `[HARD]`, `[MECHANICAL]` — to BOTH the bold-anchor tag loop and the leftmost-scan tag loop; (b) also anchor a lane tag that sits between `- [ ] ` and a bold `**title**` (the tag-before-bold-title shape `- [ ] [TAG] **title**`), so the tag wins over any prose token regardless of order. Then update the disposition mapping (lines ~258-268): executable lanes (`[ROUTINE]`, `[HARD]`, `[HARD — pool]`) → `promote`; human/compute gates (`[INPUT — *]`, `[HARD — meeting|hands|decision gate]`, `[MECHANICAL]`) → `laned` (verdict-neutral, never auto-promoted, never re-filed). Keep the fb7f bold-anchor + id:ed2e status-summary exemptions intact. NOTE: id:7df1's reader-migration (d259 decision) will eventually DELETE `primary_lane()` in favour of one fixed-offset positional read once the tag-first reorder lands cross-repo; this is the interim fix for the still-open dual-vocab window, not a competing design.
  - **Acceptance**: `tests/test_unpromoted_scan_newvocab.sh` (`# roadmap:719a`, written RED by this handoff) goes green — new-vocab-prefixed items with old-vocab prose tokens report `laned` not `promote` (cases j–n), and a genuine `[ROUTINE]` item still reports `promote` (case o). Existing `tests/test_unpromoted_scan.sh` (cases a–i, id:2dea/ed2e/4da4) MUST stay green (no regression to old-vocab anchoring or the status-summary exemption).
  - **Done-check**: `tests/run-tests.sh tests/test_unpromoted_scan_newvocab.sh tests/test_unpromoted_scan.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/unpromoted-scan.sh` (`primary_lane()` ~L85-107 + disposition mapping ~L258-268). Cross-refs: id:4d8e (mechanical-classifier corpus, this is a new fixture), id:7df1 (dual-vocab window close / eventual primary_lane deletion), id:5eb3 (promote==0∧surface>0 → human case-b), id:2d20 (pool re-dispatches un-doable units — this is one concrete cause).

- [x] [ROUTINE] `diary-append.sh`: keep the `-f` entry temp file until push SUCCEEDS + fix the multi-branch rebase race <!-- id:f8df -->
  - **Why** (TODO id:f8df; observed 2026-07-08): `diary-append.sh -f <entry>` raced a concurrent quota-sampler commit on the diary repo, died with `fatal: Cannot rebase onto multiple branches`, and had ALREADY consumed/deleted the `-f` temp entry file — the entry was silently lost (id:4347 silent-swallow class; recovered only because the invoking session still held the text).
  - **How / Design**: (a) delete the `-f` temp file ONLY AFTER commit+push succeeds — on any error, move it to a `.failed/` quarantine and print a LOUD stderr path (never silent unlink). (b) Find why the pull step hit "multiple branches" under concurrency (likely `git pull --rebase` with a multi-refspec fetch config or a missing explicit `origin <branch>` arg inside the flock) and pin the refspec / use explicit `origin <branch>` args. Keep the existing flock discipline.
  - **Acceptance**: a hermetic test (`tests/test_diary_append_entry_survival.sh`, `# roadmap:f8df`) that simulates a concurrent upstream commit landing between fetch and rebase, asserts the `-f` entry file SURVIVES the failed run (in `.failed/` with a loud path), and that a retry appends the entry EXACTLY once (no duplicate, no loss).
  - **Done-check**: `tests/run-tests.sh tests/test_diary_append_entry_survival.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/diary-append.sh` (the `-f` consume path + the pull/rebase step under flock), TODO id:f8df.

- [x] [ROUTINE] Unify `orphan-scan.sh --cross-ledger` on an id-keyed, indent-agnostic twin-check (shared with `archive-closed.sh`) <!-- id:34c7 -->
  - **Why** (TODO id:34c7; meeting 2026-07-11-1239 D1): `--cross-ledger` missed 6 real drift items (ROADMAP `[x]` / TODO `[ ]`) because their TODO twin is an INDENTED sub-item, while `archive-closed.sh`'s id-keyed check caught them — the two use different anchoring.
  - **How / Design**: re-implement `--cross-ledger`'s twin match on an id-keyed, indent-agnostic basis (find the `<!-- id:XXXX -->` token anywhere on a checkbox line regardless of leading whitespace), matching `archive-closed.sh`'s approach so the two agree. Anchor on the id marker, not a column-0 `^- \[ \]` grep.
  - **Acceptance**: `tests/` (`test_orphan_scan_cross_ledger_indent.sh` or extend the cross-ledger test, `# roadmap:34c7`) — a fixture where ROADMAP has an `[x]` item whose TODO twin is an INDENTED `  - [ ]` sub-item IS flagged as cross-ledger drift; a matching non-indented case still flags; an agreeing pair (both `[x]`) is not flagged.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--cross-ledger` mode), `todo-update/archive-closed.sh` (the id-keyed check to converge on). COUPLED with id:431f (the col-0 anchor blindspot in `--shipped`) — same script family; coordinate the anchor helper if touching both.

- [x] [ROUTINE] `orphan-scan.sh --shipped`: widen the col-0 anchor so INDENTED sub-items are classified <!-- id:431f -->
  - **Why** (TODO id:431f; found 2026-07-10 by the id:46f6 executor): the `--shipped` driver greps `^- \[ \] ` anchored at column 0, so 14 of 241 open id-bearing TODO items (6%) nested under a parent are never classified — not TICK-READY, not GATE-STALE, not the typed-edge umbrella/gate classes. Concretely inert: `gated-on:` markers on id:3c4c/eb92 and the UNMARKED-GATE expected on id:7df1.
  - **How / Design**: widen the anchor to `^\s*- \[ \] ` so indented `  - [ ]` items enter all `--shipped` classes; keep the col-0 behaviour otherwise unchanged. This is report-only (nothing auto-ticks); the change pulls 14 previously-unclassified items in at once — a measured, advisory burst, acceptable.
  - **Acceptance**: `tests/` (`test_orphan_scan_shipped_indent.sh`, `# roadmap:431f`) — an INDENTED `  - [ ]` item with a `children:` marker whose children are all `[x]` is reported UMBRELLA-READY; a pre-existing col-0 case is unchanged.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--shipped` driver / anchor). Relates id:46f6 (typed edges), id:1b1a (md-merge fail-open), id:b3ee (original `--shipped` detector). COUPLED with id:34c7 (same anchor family) and id:4245 (which depends on `--shipped` seeing 7df1).

- [x] [ROUTINE] Surface the two deliberately-unmarked gate edges (`7df1`, `50c4`) as UNMARKED-GATE in `orphan-scan.sh --shipped` <!-- id:4245 -->
  - **Why** (TODO id:4245; meeting 2026-07-10-1430): the typed-edge pass wrote 8 `children:` + 10 `gated-on:` markers, but left `7df1` and `50c4` UNMARKED on purpose — their gate tokens (`b466`, `508d`) live in project_manager / relay-core and do not resolve locally. They must surface as UNMARKED-GATE (resolved via the routed:/inbox machinery, not a local `gated-on:` edge), not silently vanish.
  - **How / Design**: give `orphan-scan.sh --shipped` an UNMARKED-GATE class that flags an open item whose known cross-repo gate token is unresolved-and-unmarked-locally, reporting `7df1` and `50c4`. Keep it report-only. NOTE: `7df1`'s TODO twin is indented, so this likely DEPENDS ON id:431f's anchor widening landing first (else 7df1 is invisible to `--shipped`).
  - **Acceptance**: `tests/` (`test_orphan_scan_unmarked_gate.sh`, `# roadmap:4245`) — a fixture with an open item carrying a cross-repo gate token but NO local `gated-on:` marker is reported UNMARKED-GATE; a locally-marked `gated-on:` item is NOT.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--shipped`), `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. DEP: id:431f (indented-item anchor) — pick 431f first.

- [x] [ROUTINE] `md-merge.py update-ids`: fail LOUD on an unmatched id; gate appends behind `--allow-new` <!-- id:1b1a -->
  - **Why** (TODO id:1b1a, HIGH PRIORITY; found 2026-07-10): `md-merge.py:143-152` APPENDS an id not present in the file. Correct for NEW items, fail-OPEN for UPDATES — a caller intending to edit `id:abcd` who mistypes it gets a silent duplicate line, not an error. The whole point of routing writes through this helper is that it is the SAFE path.
  - **How / Design**: make intent explicit — `update-ids` FAILS LOUDLY (non-zero + the named unmatched tokens on stderr, writing nothing) when an id is not found; appends require an opt-in flag (`--allow-new`, or a separate `add-items` subcommand) that preserves today's behaviour. Then verify the id-comment regex (`<!--\s*id:([0-9a-f]{4})\s*-->`, `md-merge.py:135`) is not the only reader assuming the comment terminates immediately after the hex — the item names ~10 readers; at minimum fix `handback-followup.py:71`'s `$`-anchored regex which already silently no-ops on `id:78ff` (its id comment is followed by an `xledger-ok:` annotation).
  - **Acceptance**: `tests/` (`test_md_merge_update_ids_strict.sh`, `# roadmap:1b1a`) — `update-ids` with an unknown id exits non-zero and writes NOTHING; with `--allow-new` it appends as today; a companion assertion that `handback-followup` appends its note to a line whose id comment is non-terminal (`id:XXXX xledger-ok:…`).
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `tools/md-merge.py` (`update-ids`, lines ~135/143-152), `relay/scripts/handback-followup.py:71` (`$`-anchored regex bug). Relates id:46f6 (typed-edge marker), id:ee62 (visible-vs-comment annotations), `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`.

- [x] [ROUTINE] Add a 5th capability lane `[INPUT — author]` (human-expert-authored content) to the lane contract (this-repo half) <!-- id:2b0b -->
  - **Why** (TODO id:2b0b; user 2026-07-11, M3 lane-triage): the 4 capability lanes don't cover "a human expert AUTHORS content/prose" (not credential/hardware=access, not design-judgment=meeting, not a discrete decision, not compute=mechanical). Surfaced by toesnail id:e552 and linguistic-unversals id:d58f, which stay `[HARD — hands]` until this lands.
  - **How / Design**: add `[INPUT — author]` to `relay/references/hard-lanes.md` (capability table + canonical marker set), and wire its two IN-REPO consumers — `relay/scripts/gather-human-backlog.sh` (id:78ff; bucket it onto the "you run these"/owner list, NOT a meeting) and `relay/scripts/roadmap-lint.sh` (recognition, so it isn't flagged as an unknown/untagged lane). Extend `tests/test_hard_lane_buckets.sh`'s marker-set cross-check.
  - **Acceptance**: `tests/test_hard_lane_buckets.sh` (extend, `# roadmap:2b0b`) green — an `[INPUT — author]` item is bucketed onto the owner/author list (not meeting), `roadmap-lint.sh` does not flag it as untagged, and the marker set in `hard-lanes.md` includes it.
  - **Done-check**: `tests/run-tests.sh tests/test_hard_lane_buckets.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/references/hard-lanes.md` (capability table + marker set), `relay/scripts/gather-human-backlog.sh`, `relay/scripts/roadmap-lint.sh`, `tests/test_hard_lane_buckets.sh`. CROSS-REPO coupling (out of this worktree's scope): project_manager `scan.py` (id:b466) reads the same `hard-lanes.md` contract and needs the matching lane added there — already tracked in TODO id:2b0b, not a new inbox item.

<!-- 2026-07-11 relay human: filed the impl for two ratified REVIEW_ME decisions —
     id:dfe4 (refine c095 heading-as-item detection) + id:26c2 (mechanical-daemon host-gate).
     Both [ROUTINE] with RED specs; NOT reopening c095/b3d0 (their contracts hold). -->

- [x] [ROUTINE] Refine `roadmap-lint.sh` c095 heading-as-item detection — only flag a `## …[LANE]…` heading as MISSING-id when its children are BARE status markers (no own class tag + id) <!-- id:dfe4 -->
  - **Why** (REVIEW_ME decision, human 2026-07-11; audit Run 70 finding, filed 5dc3): `roadmap-lint.sh`'s c095 "heading-as-item" detector treats ANY `## …[LANE]…` heading as a work-item heading that must carry its own `<!-- id:XXXX -->`. That false-positives on descriptive relay-handoff SECTION headers (`## [MECHANICAL] lane-anchor hotfix …`, `## [MECHANICAL] recipe explicit-success-marker …`, `## [ROUTINE] case-c bare-only lane count …`, ROADMAP ~L2861/2883/2911) whose SINGLE child is an already-`[x]` item carrying its OWN `[ROUTINE]` tag + id (0d58/fd37/9078). Demanding an id on such a heading is wrong: adding one would DUPLICATE the child's id and break single-id-two-views. The genuine c095 shape is a heading that OWNS the lane+id whose child `- [ ]` lines are BARE status markers (no own tag+id) — only that shape should be flagged.
  - **How / Design**: refine the detector so a `## …[LANE]…` heading is treated as a heading-*item* (and thus required to carry an id) ONLY when its child checkbox lines are BARE status markers — i.e. none of its immediate children carry their OWN class tag (`[ROUTINE]`/`[HARD]`/…) + `<!-- id:XXXX -->`. If ANY child carries its own tag+id, the heading is a descriptive SECTION title, not a work-item, and MUST NOT be flagged for a missing id. Keep the existing genuine-c095 detection (heading owns lane+id over bare-marker children) unchanged. Anchor the child-tag/id test on the same markers the rest of the lint uses (do not bare-substring). Report-only today (relay-doctor/roadmap-lint exit 0); the refinement removes 3 false-positives without weakening real detection.
  - **Acceptance**: `tests/test_roadmap_lint_c095.sh` (`# roadmap:dfe4`) green — a fixture ROADMAP where (a) a `## [LANE]` heading whose SOLE child carries its own `[ROUTINE]` tag + `<!-- id:XXXX -->` is NOT flagged, and (b) a `## [LANE]` heading owning a lane+id over BARE-marker children (no own tag/id) IS still flagged MISSING-id.
  - **Done-check**: `tests/run-tests.sh tests/test_roadmap_lint_c095.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/roadmap-lint.sh` (the c095 heading-as-item detector), the 3 in-repo false-positive headers at ROADMAP ~L2861/2883/2911 (children 0d58/fd37/9078), REVIEW_ME.md (this decision), original c095 tension (audit Run 70 / filed 5dc3).

- [x] [ROUTINE] Add a host-gate to `mechanical-daemon.sh` — skip+defer any recipe whose `.host` != `uname -n`, never execute it <!-- id:26c2 -->
  - **Why** (REVIEW_ME decision, human 2026-07-11; wave-2a review finding on id:b3d0): the recipe schema's `host` field is REQUIRED non-empty by `recipe-validate.sh` and documented as binding the recipe to a target host, but `mechanical-daemon.sh` reads `est_wall`/`resource`/`cmd`/`artifact` and NEVER reads `.host` nor compares it to `$(uname -n)` — so it would auto-EXECUTE a shell `cmd` from a recipe bound to a DIFFERENT host. Today the drop-dir is per-host so a mismatch can only arrive by mistaken copy or a future shared-transport (de31/b444) — not a live bug — but the daemon auto-runs shell, the review contract's §2c treats a host mismatch as *unrunnable*, and no comment records "host advisory / drop-dir per-host". Defense-in-depth: gate it. NOT reopening b3d0 (its tested contract + launch-gate hold); this is a follow-on.
  - **How / Design**: add a one-line guard in the per-recipe processing loop, BEFORE the launch-gate / run, that reads the recipe's `.host` and, when it != `$(uname -n)`, SKIPS + DEFERS the recipe (leave it in `pending/`, do NOT move to `running`, do NOT run `cmd`, no artifact, no inject) — mirroring the existing check-and-defer path for a claimed resource. Log a DISTINCT line (e.g. `defer recipe=<name> reason=host-mismatch host=<recipe.host> this=<uname>`) so it is separable from a resource-gate defer. Do not delete or quarantine the recipe (a mistaken copy may be recoverable / re-routed); defer is the conservative disposition. Keep `RELAY_RECIPE_DIR` and the other env overrides intact for hermeticity.
  - **Acceptance**: `tests/test_mechanical_daemon.sh` (extend, `# roadmap:26c2`) green — a valid recipe whose `.host` is a FOREIGN name is DEFERRED (stays in `pending/`, no artifact, no inject unit), while an otherwise-identical recipe whose `.host == $(uname -n)` still runs `pending→running→done` + injects (the existing b3d0 permit case, unbroken).
  - **Done-check**: `tests/run-tests.sh tests/test_mechanical_daemon.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/mechanical-daemon.sh` (per-recipe loop, the check-and-defer path to mirror), `relay/references/recipe-manifest.md:51` (`host` field), `relay/scripts/recipe-validate.sh` (requires `host` non-empty), ROADMAP id:b3d0 (A3, the daemon contract), REVIEW_ME.md (this decision).

<!-- 2026-07-10 handoff C2 (run relay-20260710-171033-12826-handoff): promoted the sole
     `promote`-disposition TODO item (unpromoted-scan: 1 promote / 1 laned / 58 surface).
     Single-id-two-views (D2): id:77ce REUSES its open TODO.md twin ([INBOUND routed:2f0c
     from relay-core]). [ROUTINE] with RED spec tests/test_reconcile_planner.sh (# roadmap:77ce).
     Surface items are the mechanical `human`-verdict filer's job, NOT promoted here
     (handoff.md §surface); the one `laned` item (id:abe7, [HARD — meeting]) is already
     lane-tagged and awaits a /meeting, not a handoff. -->

- [ ] [INPUT — decision] echo-runner agentType for relay-loop mechanical agents — measure, then adopt or reject (id:f599) — 🚧 GATED (auto, id:3801; route:human): Needs a live instrumented probe run (per-hop subagent token cost with vs without agentType:'echo-runner' over a representative round); the mechanical agent() hops execute only in the Workflow-sandbox runtime, unreachable from a worktree, and the item bars a reasoned decision without measured data. Re-lane back to the pool lane once the measurement exists. — needs /relay human <!-- id:f599 --> — **DECIDED 2026-07-13 (relay human): BUILD THE PROBE.** Owner authorized building the instrumented in-sandbox probe run (per-hop subagent token cost with vs without `agentType:'echo-runner'` over a representative round), then decide adopt/reject on the measured delta. Next step: author the probe harness (runs only in the Workflow-sandbox runtime); keep this box open until the measurement exists.
  - **Why** (TODO id:f599): `~/.claude/agents/echo-runner.md` (haiku + Bash-only + 3-line system prompt) was verified working via Workflow `agentType` on 2026-07-02 (a probe returned verbatim stdout; the registry picks up new defs mid-session with lag). Candidate adoption: the relay-loop.js prelude + the mechanical-runner `agent()` calls gain `agentType: 'echo-runner'` so a purely-mechanical "run this command and echo stdout" hop can't be mangled by a general-purpose agent.
  - **Design / GATE (measure-then-decide, why this is [HARD] not [ROUTINE])**: GATE on a MEASURED relay-econ before/after — one probe run cost ~20.6k subagent tokens, so the harness floor may dominate and swamp any real saving. This is not a mechanical apply: the strong session must (a) measure the per-hop token cost of the current mechanical `agent()` calls vs the same calls with `agentType: 'echo-runner'` over a representative round, and (b) decide by the pre-registered criterion: **adopt only if the delta is real** (a measured, non-noise reduction). If ADOPTED: move `~/.claude/agents/echo-runner.md` INTO this repo (under a tracked path) + add a `make install`/`make install-<x>` symlink for it, and wire `agentType: 'echo-runner'` into the mechanical-runner `agent()` calls in `relay/scripts/relay-loop.js`. If REJECTED: record the measurement + the reason in RELAY_LOG.md and delete the loose `~/.claude/agents/echo-runner.md`. Either way the loose out-of-repo def must not persist unexamined.
  - **Acceptance**: a decision recorded in RELAY_LOG.md with the before/after measurement; on adopt — the agent def is in-repo + installable + wired, `lint-workflow-templates.mjs` clean, `make test` green; on reject — the loose def deleted and the rationale logged. No red test (the deliverable is a measured decision + its follow-through, not a fixed behavior).
  - **Context**: `~/.claude/agents/echo-runner.md` (the loose def), `relay/scripts/relay-loop.js` (prelude + mechanical-runner `agent()` calls), the id:d267 quota-sample / subagent-token accounting for the econ measurement, TODO id:f599.

<!-- 2026-07-08 handoff C2 (run relay-20260708-162516-22523): promoted the sole `promote`-
     disposition TODO item (unpromoted-scan: 1 promote / 58 surface / 1 laned). Single-id-two-
     views (D2): id:356f reuses its open TODO.md twin (routed:dfc1 from llm-from-scratch). -->

- [ ] [HARD — decision gate] Relay consumer of the id:2840 derived ledger index (cross-ledger / count / promotion) — ✅ DECISION RESOLVED + BUILD AUTHORIZED 2026-07-14 (relay human): id:2840 producer shipped (project_manager id:bac5 CORE + id:608c `proj graph`, edges.json contract locked) → build the relay-side consumer. Artifact confirmed live 2026-07-14 (`proj refresh` → 1288 nodes / 2791 edges, `proj graph` consumes it); wire relay review/human + the count line to read it via the stable contract (retire `orphan-scan --cross-ledger` + the d5e0 count prose, id:1de1). <!-- id:659c --> — 🚧 GATED (auto, id:3801; route:decision-gate): Premise false: shipped edges.json is a co-citation graph (no checkbox-state/count) — cannot retire orphan-scan --cross-ledger; decide project_manager index-extension vs. keep-guard + drop-count-only (id:1de1). — needs a /meeting
  - ✅ GATE RESOLVED 2026-07-14 (relay human): the project_manager derived index (id:2840, `routed:1e99`) shipped its producer + locked artifact contract (id:bac5 CORE + id:608c `proj graph`), so this re-lanes `[INPUT — decision]`→`[HARD — pool]` and is now pool-dispatchable. Build: relay `review`/`human` + the TODO count line read the artifact instead of hand-grepping; retire the per-review TODO-twin close + the `orphan-scan --cross-ledger` hand-check; DROP the d5e0 count prose (folds in TODO id:1de1). Artifact confirmed live 2026-07-14: `proj refresh` emits a real populated `~/.cache/project_manager/edges.json` (1288 nodes / 2791 edges over 39 repos) and `proj graph [--public]` consumes it — build against the live artifact. Meeting: `docs/meeting-notes/2026-06-23-0803-ledger-drift-derived-index.md`.

- [x] [HARD] Explicit `[HARD]` lane tags + bucket the human-backlog HARD surface (done 2026-06-22, relay HARD child — relay/bash half) <!-- id:78ff -->
  - **Done 2026-06-22** (relay HARD child, id:da26): shipped the relay/bash half. (1) Lane vocabulary doc `relay/references/hard-lanes.md` — the single shared contract both `gather-human-backlog.sh` (id:78ff) and project_manager `scan.py` (id:b466) read: `[HARD — pool|meeting|hands]` lanes + `[HARD — decision gate]`/`🚧 route:meeting|human|decision-gate` as meeting-lane aliases (id:3801); `[INTENSIVE]` is the orthogonal resource axis, not a lane. (2) `gather-human-backlog.sh`: replaced `emit_gated_hard` (single `gated_hard` lump) with `emit_hard_lanes` — READS the explicit lane tag → emits per-lane kind `hard_pool`/`hard_meeting`/`hard_hands`; an open `[HARD]` with NO recognized lane prints a stderr `ERROR:` and forces a NONZERO exit (id:415b grammar-tightening-with-loud-rejection, never silently default). (3) `references/human.md` §2/§3/return-summary: the three buckets are now distinct call-to-actions (pool→FYI/`--afk`, meeting→`/meeting`, hands→"you run these"), not one /meeting firehose. (4) Back-filled THIS repo's bare `[HARD — strong model]` items: de4e→meeting, 401c→pool, 3346→meeting; dba3 left as its machine-managed `[HARD — decision gate]` alias. Acceptance test `tests/test_hard_lane_buckets.sh` (roadmap:78ff) green. **Residual (not this worktree's scope):** cross-repo back-fill of OTHER confirmed-own repos' bare `[HARD — strong model]` tags — a relay child works ONE repo's worktree; the per-repo lane back-fill belongs to each repo's next handoff/review or a `/relay human` sweep (the collector now LOUD-rejects any un-back-filled untagged HARD, so the gap is self-surfacing). project_manager id:b466 (Python half) consumes this same `hard-lanes.md` contract.
  - **Design + rationale: TODO id:78ff** (single-id-two-views — the "why" lives there). DECISION 2026-06-21 (user "obviously explicit"): every open `[HARD]` ROADMAP item declares a lane in its bracket tag — `[HARD — pool]` (this `--afk` pool runs it via the `hard` verdict, id:da26), `[HARD — meeting]` (≡ `[HARD — decision gate]`/`🚧 route:…`, id:3801 → `/meeting`), `[HARD — hands]` (hardware/sudo/secret/on-device/rehearsal → "you run these"). `[INTENSIVE — <resource>]` (id:8d52) is an ORTHOGONAL resource axis, not a lane.
  - **Scope (this is the relay/bash half; `proj relay` half = project_manager id:b466):**
    1. Document the lane vocabulary ONCE in `relay/references/` (the single source both tools read).
    2. `gather-human-backlog.sh`: replace the "emit every `[HARD]` as gated_hard" lump with reading the explicit lane tag → emit a `bucket` field (pool|meeting|hands); a `[HARD]` with NO lane tag is emitted as `untagged` and the script EXITS NONZERO / prints a LOUD warning (id:415b grammar-tightening-with-loud-rejection — never silently default).
    3. `references/human.md`: present the three buckets as distinct call-to-actions (pool→"run /relay --afk", meeting→/meeting, hands→checklist), not one "/meeting" firehose.
    4. Back-fill every existing bare `[HARD — strong model]` across all confirmed `own` repos to an explicit lane (use the 2026-06-21 manual re-bucketing in the diary as the starting classification).
  - **Acceptance:** a new `tests/test_hard_lane_buckets.sh` (`# roadmap:78ff`): a ROADMAP fixture with one item per lane + one untagged asserts gather-human-backlog emits the right `bucket` per item AND exits nonzero (loud) on the untagged one; the lane vocabulary doc exists; cross-check that the marker set matches project_manager's (id:b466). RED until implemented.
  - **Coupling:** ships its vocabulary doc BEFORE or WITH project_manager id:b466 (shared contract; keep them in sync). Relates id:3801/da26/8d52/9c92/415b.

- [x] [INPUT — decision] Opus quality-degradation investigation + standing model-probe deliverable — 🚧 GATED (auto, id:3801; route:human): Closure blocked: id:23e9 seed needs the claude-probe OS user (id:d0c0, useradd/sudo — forbidden for a relay child) + real Opus/Sonnet/Haiku token runs — needs /relay human <!-- id:dba3 --> — **DECIDED 2026-07-13 (relay human): reuse the EXISTING `relay-probe` OS user** (no `useradd`/sudo needed — the id:d0c0 blocker lapses); it only needs a fresh credential copy, which the owner consented to provide. HANDS residue (surface to "you run these"): copy new credentials into the `relay-probe` user's `~/.claude`, then the probe can seed the id:23e9 pre-registered band (5 cold runs/tier across Opus/Sonnet/Haiku). Box stays open until credentials are copied + first seed lands. — **DONE 2026-07-13 (user directive):** marked complete. The standing model-probe (`tools/model-probe.sh` + versioned battery) IS the durable deliverable; the investigation was expected inconclusive by design. Related open items NOT auto-closed here — close separately if you consider them subsumed: id:23e9 (seed+close operational sub-item), id:5fc6 (load/disappointment observational umbrella), id:903a/e3c0/241c (investigation axes).
  - **Meeting held 2026-06-17** (`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`). **Investigation expected inconclusive** (n=4 anecdotes, n=1 sessions, no prior baseline — self-anchored prior). Real deliverable = the standing probe. Close this item once id:2d01+c345+040a+23e9 land and the baseline is seeded.
  - **Evidence source:** memory `opus-quality-degradation-20260616.md`; 4 incidents from session `bf9dd9e5` (1213 lines / 2.4M tokens — very long; confound). Key hypotheses: long-context fatigue vs wall-clock duration (idle-gap / KV-cache rot) vs model-serving regression.
  - **Investigation steps (id:903a, e3c0, 241c):** three-axis turn-cluster (`context_depth`, `elapsed_wall_time`, `idle_gap_before_error`) on `bf9dd9e5` + yesterday's last `/relay` session; cold fixed-prompt probe re-posing incidents #2/#3; Anthropic status/version check.
  - **Durable deliverable (id:2d01, c345, 040a, 23e9, 6ffe):** `tools/model-probe.sh` + versioned `tools/model-probe.battery.jsonl` (~15–20 timeless items) + append-only log capturing resolved model-id-str + frontend metadata + tok_per_s; three-tier (Opus + Sonnet + Haiku); pre-registered acceptance band; 2-consecutive-miss alarm. Invocation path GATED on ToS pre-check (id:2d01). Cadence = on-demand seed now, cron deferred.
  - **Billing path REAFFIRMED 2026-06-22:** Anthropic's May plan to move `claude -p` / Agent SDK OFF subscription rate limits onto a dedicated monthly credit is **deferred** (email 2026-06-22 — subscription usage unchanged, advance notice promised before any cutover). Path A's "subscription quota, no per-token billing" rationale (id:2d01) **holds** — no new gate, no decision change; keep path B (API + `--bare`) as the advance-notice hedge. Memory `anthropic-agent-sdk-billing-deferred`; broader evaluation = TODO id:00a5.
  - **Detection rule:** flag only on **2 consecutive** out-of-band runs; tokens/sec is the weak silent-swap hedge (silent same-label swap near-unprovable without baseline; the probe is what makes the NEXT suspicion answerable).

- [x] [INPUT — meeting] DEFERRED (decided 2026-06-17): Distributed relay orchestrator — multi-machine, dynamic membership <!-- id:de4e --> <!-- DEFERRED-CLOSED 2026-07-13 (relay human): ticked to clear the recurring roadmap-lint DECIDED-LEFT-OPEN warn; reopen if multi-machine relay is ever needed. -->
  - **Meeting HELD 2026-06-17 — decided DEFERRED on quota economics (do NOT execute, no
    further `/meeting` owed).** Design-gate originally: choose the coordination substrate
    before any code. Captured 2026-06-16 from a working session; the gate was resolved by
    the 2026-06-17 meeting (see D1 below). Relabel per id:9c92 (review 2026-06-18) — the
    old "DECISION GATE / needs a /meeting" heading contradicted the resolved block below.
  - **Why**: leases (`claim.sh`) + `relay.toml` are flock-on-local-dir → single-host
    only, so concurrent `/relay` on zomni+fievel has NO cross-machine mutual exclusion
    (both fully work the same repo; slower one's `--ff-only` push strands). Also lifts
    the `min(16, cores-2)` per-workflow local-parallelism ceiling by spreading across
    machines.
  - **Seed brief** (start the meeting here): `docs/meeting-notes/2026-06-16-2257-distributed-relay-orchestrator-SEED.md`.
  - **⚠️ MEETING HELD 2026-06-17 — D1 constraints (reframed premise, do NOT build now):**
    - **GitHub-as-control-plane / ref-CAS REJECTED.** Serverless is the point; GitHub
      coordination dependency is a no-go.
    - **If ever built:** peer rendezvous (zomni ↔ fievel try to talk directly); if
      unreachable → degrade-to-solo (each assumes it is alone, no quorum). Rare
      split-brain (low-likelihood if both online but cloudflare tunnel fails) caught
      after the fact by `md-merge.py` line-scoped writes + `--ff-only` reject +
      `orphan-scan --cross-ledger`. Optimistic concurrency + merge backstop, NOT CAS.
    - **Deferred reason:** zomni alone exhausted the 7-day→daily quota share 2026-06-16;
      cross-machine throughput is moot until quota economics change.
    - See `docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`.
  - **Lead candidate**: ~~git-remote-as-control-plane (CAS ref-locks)~~ **REJECTED** —
    see D1 above. Future candidate: direct peer rendezvous + degrade-to-solo.
  - **Related**: id:ebfb / id:0902 (current single-host claim registry),
    `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`.

- [ ] [HARD — decision gate] Cold fixed-prompt probe: re-pose Opus-degradation incidents #2 (confident-wrong "zkm-* on another machine") and #3 (over-engineered ~/.claude branch-split) against fresh Opus; record pass/fail vs the recorded incident behaviour, finding written into `docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`. Promoted 2026-07-13 (user) from TODO id:e3c0 (single-id-two-views — same id spans both ledgers). **Why HARD**: requires apex judgment to assess whether fresh Opus reproduces the confident-wrong / over-engineering behaviour. Bounded: two fixed prompts, pass/fail each, one meeting-note write. <!-- id:e3c0 --> — 🚧 GATED (auto, id:3801; route:human): Cold probe needs memory/CLAUDE.md-free Opus (id:2d01 relay-probe user); creds not yet copied (id:dba3 HANDS residue) + sudo forbidden; same-user run is contaminated. — needs /relay human
- [x] [HARD] Close the mechanical-orphan resolution loop so [MECHANICAL] items can't rot (user 2026-07-13: "needs more automation otherwise these things get lost"). relay-doctor check-12 (id:1bd1) already DETECTS a [MECHANICAL] ROADMAP item with no matching recipe in the drop-dir, but resolution is fully manual (an Opus session hand-authors the recipe JSON) so orphans silently accumulate — the loud-detection/silent-no-op anti-pattern. Build the resolution half WITHOUT breaking the whitelist trust boundary (no auto ROADMAP→pending/ execution): (a) a `/relay review` (or discovery) sub-step that per orphan AUTO-DRAFTS a recipe skeleton into a NEW `recipes/drafts/` dir (id/repo prefilled; host from `[host:]`; resource from `[INTENSIVE — <res>]`; cmd/est_wall/acceptance_artifact left as explicit TODO for an Opus reviewer) — a draft is NOT executable (daemon only consumes pending/), so an Opus reviewer still deliberately promotes draft→pending; (b) LOUD-surface every orphan + un-promoted draft in RELAY_STATUS.md + the `/relay human` gather; (c) the resource-probe bespoke-token gap is already fixed alongside (r5-jvm/lean/xvfb-electron, commit e980b07); (d) add a periodic RETRY for check-and-deferred recipes — `mechanical-daemon.path` is `PathModified`-triggered with NO retry timer, so a recipe that defers once (resource busy / host mismatch / intensity at that instant) stalls forever until `pending/` is next modified (observed 2026-07-13: the ac14 recipe deferred at the pre-fix tick and could not self-re-evaluate after the fix landed). Add a low-cadence `mechanical-daemon.timer` (or equivalent) so deferred recipes are retried, closing the "deferred → silently stuck" hole. First real instance: isochrone id:ac14 (recipe hand-authored + dropped 2026-07-13). Acceptance: a fresh [MECHANICAL] orphan produces a surfaced draft within one review pass, and a deferred recipe re-attempts without a manual nudge; no orphan or deferred recipe is ever silent. <!-- id:8a6b -->
- [x] [ROUTINE] BUG: discovery classifier emits a FALSE `execute` verdict ("Open executor-actionable [ROUTINE] ROADMAP items present") for repos with NO open actionable [ROUTINE] item. — FIXED 2026-07-13: root cause was NOT the predicate (correct) but `gather-repo-state.sh`'s `top_intensive` filter under-excluding gated/`[MECHANICAL]` `[INTENSIVE]` lines → `classify-verdict.sh` fold(b) fabricated a phantom `[ROUTINE]`. Fix (line 267): added `[MECHANICAL]|🚧|BLOCKED` to the exclusion. RED spec `tests/test_classify_false_execute_no_routine.sh` green; isochrone→review, it-infra→no-execute; suite 232/0. Re-checkable via the test. Observed 2026-07-13 (run relay-20260713-130624-24135): **isochrone** (zero [ROUTINE] items at all — only [INPUT — meeting] + gated [MECHANICAL]) and **it-infra** (both [ROUTINE] items id:935e/6e27 are `[x]` closed) each got execute-dispatched and immediately handed back "no executor-actionable work" — wasted a worktree + Opus/Sonnet child per false dispatch. The `actionable_routine_open` / `roadmap_actionable_open` predicate (`classify-repo.sh`, also `classify-verdict.sh`) is over-counting: it appears to treat closed `[x]` and/or absent [ROUTINE] as open-actionable. A RED test reproducing BOTH cases is the spec; fix the predicate to require primary-lane [ROUTINE] AND open `[ ]` AND not @manual/🚧/BLOCKED. <!-- id:2ab2 -->
- [x] [HARD] Handbacks must be LOUDLY tracked + stop the re-dispatch loop (user 2026-07-13: "when relay agents hand back, that should be loudly tracked and fixed somehow"). `handback-followup.py` (id:3801) durably gates ITEM-level handbacks (size-out / decision-gate / hard-split), but a WHOLE-DISPATCH handback ("no executor-actionable work / classifier verdict wrong", route=none) just no-ops → the repo is re-dispatched EVERY round (observed: it-infra false-execute in rounds 3,5,6,7,8 of run relay-20260713-130624-24135 — ~5 wasted children on ONE bogus verdict). Add: (a) **dispatch-level suppression** — a repo+verdict that hands back "no work" is NOT re-dispatched again in the same run until its discover-sig changes for a genuine reason (negative-cache / cooldown), so a false/stale verdict can't loop; (b) **loud repeat-tracking** — the exit summary + RELAY_STATUS flag any repo that handed back ≥2× in a run as an ALERT (a repeating handback is a bug signal, not noise) — and feed each into the id:2ab2-style "file + investigate" path rather than evaporating; (c) route=none should leave a durable breadcrumb. Complements id:2ab2 (which fixes the specific false-execute predicate) — this is the defense-in-depth so ANY future false/stale verdict is capped + surfaced, never silently looped. <!-- id:1432 -->
- [ ] [HARD] Strong-model audit: code review, security, and design coherence <!-- id:401c --> <!-- relay:recurring-audit -->
  - **Why HARD**: requires adversarial judgment — finding subtle bugs, security issues,
    and internal contradictions in design docs that a weaker model would miss or dismiss.
    Also requires holding the full design history in mind to spot feasibility gaps.
  - **Acceptance**: a meeting note documenting findings across three passes:
    (1) **Code review** — correctness bugs, error handling gaps, shell quoting issues,
    race conditions, unhandled edge cases in scripts and Python helpers;
    (2) **Security audit** — injection risks (command, path, jq), unvalidated inputs
    at system boundaries, secrets exposure, file permission assumptions;
    (3) **Design coherence** — check currently-unreviewed design decisions (anything
    added since last Fable turn) for sensibility, feasibility, and internal
    contradictions (e.g. a TODO gate that can never fire, a contract rule that
    contradicts another). Each finding is either fixed inline (if trivial), or
    becomes a new TODO/ROADMAP item with the finding quoted as context. No finding
    is silently dropped — if assessed as acceptable risk, say so explicitly.
  - **Tests**: none (audit output is the deliverable; follow-on items get their own tests)
  - **Done-check**: meeting note at `docs/meeting-notes/YYYY-MM-DD-HHMM-strong-model-audit.md`
    exists; every finding is either fixed, tracked, or explicitly accepted with rationale.
  - **Context**: run after each significant batch of Sonnet executor work or design changes.
    First run: covers all work since `fable-ckpt-20260612-1328`. Subsequent runs: diff
    against the most recent `fable-ckpt-*` tag (same window as review mode step 2).
  - **Run log** (recurring item — stays open by design):
    - Run 1 (2026-06-12-1811): `fable-ckpt-20260612-1328`..HEAD — see meeting note.
    - Run 2 (2026-06-15-1520): `fable-ckpt-20260612-1827`..HEAD (relay scripts surface) — F1/F2 → id:c8db.
    - Run 3 (2026-06-15-1745): `relay-ckpt-20260615-1559`..HEAD — **2 defects fixed inline**:
      `test_relay_executor.sh` asserted a stub commit 608800b removed (suite was 1-red on
      arrival, now 48/0); id:3826 gaming-flag logger was a dead feed (review dispatch prompt
      never requested its fields) — fixed + regression-guard added. See
      `docs/meeting-notes/2026-06-15-1745-strong-model-audit.md`.
    - Run 4 (2026-06-15-1759): `relay-ckpt-20260615-1748`..HEAD (1 commit: `bf70a52`
      statusline/check-deps.sh) — **clean**: no code/security defects. One **coherence drift
      fixed inline** — id:414a was still marked `GATED` on id:fa05+id:dfaf, both now shipped;
      updated the gate line to CLEARED so a future strong session isn't misled into skipping it.
      See `docs/meeting-notes/2026-06-15-1759-strong-model-audit.md`.
    - Run 5 (2026-06-15-1937): `relay-ckpt-20260615-1748`..HEAD (~270 lines / 10 files; code:
      relay-loop.js ×2 + 2 tests) — **clean**: no code/security defects, no inline fix needed.
      Verified the two pool-crash fixes (failed-shard surfacing via order-preserving `chunks[i]`;
      removal of `new Date()`/`process.env` forbidden in the Workflow sandbox) correct with genuine
      regression guards, and the cross-ledger state coherent (0 open ROUTINE / 3 open HARD; d5e0
      summary agrees). See `docs/meeting-notes/2026-06-15-1937-strong-model-audit.md`.
    - Run 6 (2026-06-15-1937b): `relay-ckpt-20260615-1937..HEAD` (only first-seen code:
      the 2-line `paused` filter in gather-human-backlog.sh, 7456e1f) — **clean**: no
      code/security/coherence defects. One forward-robustness gap **fixed inline** — the
      new `paused = true` sweep-skip filter shipped without a test; added a non-vacuous
      regression guard (repoD fixture) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-1937b-strong-model-audit.md`.
    - Run 7 (2026-06-15-2147): `relay-ckpt-20260615-2129..HEAD` (only first-seen code:
      the `warn_nested_worktrees` stale-checkout guard in gather-human-backlog.sh,
      83d8614) — **clean**: no code/security/coherence defects (`set -e`-safe grep
      guards, `-F` fixed-string prefix match with trailing-slash, stdout/stderr split all
      correct). One forward-robustness gap **fixed inline** (same class as Run 6) — the
      new warning shipped without a test; added a non-vacuous regression guard (section 4:
      real-git nested-worktree fixture + clean-repo negative control + stdout-clean
      assertion) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-2147-strong-model-audit.md`.
    - Run 8 (2026-06-16-0650): `relay-ckpt-20260615-2150..HEAD` (first-seen code: the
      profiler batch — `profile-run.sh` + `profile-runs-batch.sh` + their tests, id:a59e/
      id:08a3, ~615 lines) — **clean**: no code/security defects (pure-read, stdlib-only,
      `grep -- "$ARG"` option-safe, no injection/traversal/secrets). One coherence drift
      **fixed inline** — both scripts' header comments documented a one-wildcard search root
      (`projects/*/subagents/workflows`) while the code+real layout use two
      (`projects/*/*/...`); updated the comments to match. One cosmetic dead-code residue in
      profile-run.sh (empty-list loop + unused `at_cap_intervals`) flagged + explicitly
      accepted (no behavioural effect). Cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0
      agrees). Suite 52/0. See `docs/meeting-notes/2026-06-16-0650-strong-model-audit.md`.
    - Run 9 (2026-06-16-0928): `relay-ckpt-20260616-0653..HEAD` (~586 lines / 14 files;
      observability id:c8b6 + drain/gated-HARD id:2d20 + quota-seatbelt id:4267 + new
      relay-burn.sh id:219b) — **clean**: no code/security defects. One doc/impl discrepancy
      **fixed inline** — `relay-state-write.sh` event-append header claimed "SAME flock" but
      correctly flocks the target events file (not the shared $LOCK); corrected the comment +
      Paths note + `--help` range. Three findings **accepted** w/ rationale: relay-burn.sh
      `date -d "$reset"` awk-shellout injection seam (LOW — `resets_at` is provider-controlled
      API data; filed as forward-robustness TODO id:287b), a dead tautology sub-condition in
      the segment reduce (cosmetic), and code-only sub-ids 15bd/cd19/03a5/219b (inline
      provenance for tracked parents, not ledger tokens). Cross-ledger coherent (0 ROUTINE /
      3 HARD, d5e0 agrees). Suite 53/0. See `docs/meeting-notes/2026-06-16-0928-strong-model-audit.md`.
    - Run 10 (2026-06-16-1247): `95d3d07..HEAD` (first-seen code since Run 9; ~944 lines /
      16 files: orphan-reconcile D1/D2/D3 + relay-econ.py + archive-done multiline +
      gather-human-backlog gated-HARD sweep) — **1 defect fixed inline**: `relay-reconcile.sh`
      `--integrate`/`--discard` with no branch arg died on a `set -e` `shift 2` count error
      BEFORE the friendly `<branch> required` guard; fixed to `shift; shift || true` + a
      non-vacuous behavioural regression guard in `test_relay_reconcile_mode.sh` (proven it
      fails on the reverted form). One **doc nit fixed inline** (relay-econ.py header field
      names). One **LOW accepted** (gather-human-backlog `awk -v`, id:c8db class). No security
      defects; cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0. See
      `docs/meeting-notes/2026-06-16-1247-strong-model-audit.md`.
    - Run 11 (2026-06-16-1222): `5ab8c12..HEAD` (first-seen since Run 10, EXCLUDING Run 10's
      own already-audited merge d36208a) — **clean**: window was LEDGER-ONLY (TODO id:0547
      +1, RELAY_LOG ckpt +4; zero code/scripts/python). No code to review, no security
      surface. Coherence pass verified TODO id:0547's injected-unit-vs-discovery-unit race
      diagnosis against relay-loop.js (L71 invariant, L617 un-deduped injection merge, L808
      same-run re-entrant lease — all accurate; sound entry, no contradiction). Cross-ledger
      coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0 (audit-only, no test changes).
      See `docs/meeting-notes/2026-06-16-1222-strong-model-audit.md`.
    - Run 12 (2026-06-16-1122): `d3ca7a9..HEAD` (first-seen since Run 11, EXCLUDING Run
      11's own already-audited merge `5914c72`) — **clean**: window was LEDGER-ONLY (sole
      first-seen change = the Run 11 checkpoint paragraph in RELAY_LOG.md +4; zero
      code/scripts/python — `git diff --name-only -- '*.sh' '*.py' '*.js'` empty). No code
      to review, no security surface, no new design decision/gate. Cross-ledger coherent
      (0 ROUTINE / 3 HARD; all three HARD ids `[ ]` in both ROADMAP+TODO, d5e0 agrees).
      Suite 58/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-16-1122-strong-model-audit.md`.
    - Run 13 (2026-06-17-1102): first-seen code since the last audit (`2026-06-16-1247`) —
      5 files: `discover-sig.sh` (88L), `relay-loop.js` diff (id:c3a6 cache integration, ~52L),
      `model-probe.sh` (241L), `settings-env.py` (90L), `model-probe.battery.jsonl`. **Clean —
      no inline fixes** (code clean to a high bar): discovery cache correctly hashes a superset
      of the 9 shard inputs, fail-open sound throughout; settings-env.py idempotent/non-clobbering;
      battery JSONL valid, no secrets. **2 LOW findings tracked**: id:4348 (discover-sig.sh
      `upstream` read without fetch → bounded origin-behind under-invalidation — needs a measured
      fetch-vs-accept decision) + id:b9b5 (model-probe.sh grade `echo`→`printf` robustness). 3
      findings explicitly accepted (awk -v repo-name = id:c8db-class zero-risk; review-range
      covered by HEAD+tag hashing; probe's no-`--model` = D6 observe-don't-assert by design). Run
      via `/relay . --afk` (Opus hard-execute). See `docs/meeting-notes/2026-06-17-1102-strong-model-audit.md`.
    - Run 14 (2026-06-17, via /relay human Pareto pick): `relay-ckpt-20260617-1326..HEAD` — first-seen
      code = the id:bbd2 `migrate-state-dirs.sh` rewrite (166L) + `test_migrate_state_dirs.sh` (new).
      Ran as a 3-pass adversarial audit (correctness / security / design-coherence) of THIS session's
      own work. **4 real defects fixed inline** (audit caught them in freshly-written code): (1) HIGH —
      jsonl merge `cat src dest | awk` fused two records into one corrupt line when src lacked a trailing
      newline (silent log loss); fixed with `awk 1 … | awk 'NF && !seen'` + a no-trailing-newline test.
      Verified the LIVE `relay-events.jsonl` was NOT corrupted (the appender always terminates lines → 0
      fused / 358 valid). (2) MED — dir-union swallowed a partial `cp` failure then `rm -rf`'d src → lost
      un-copied children; now drops src only on cp success, else refuses. (3) MED — idle guard failed OPEN
      on `claim.sh`/`stat` errors and peeked one base; now fails CLOSED and peeks both old+new. (4) MED —
      `ASSUME_IDLE` bypass now warns loudly on stderr. Test grew 9→12 cases (added no-trailing-newline,
      NEW-newer snapshot, type-mismatch refusal). Design/spec claims all independently re-verified TRUE
      (symlinks, 358 events, 48 gather). 1 LOW tracked: id:16e9 (pre-existing flaky `test_relay_claim_liveness.sh`,
      roadmap:7570 — unrelated to this change). Suite 66/66.
    - Run 15 (2026-06-19-2005): first-seen code since Run 14's own audit commit `61020a0`
      (`61020a0..HEAD`, ~1.9 kLOC / 9 prod files) — the L1/L2 token-skeleton + data-loss-fix
      batch (ids aa93 clean-tree-gate + git-lock-push autostash-refuse, 11ad gather-repo-state,
      0d31 relay-status-publish, c855 push-seed cache, 3801 handback-followup.py, b841 nested
      quotaThresholds fold, 2425 crossedBucket). **Clean** — no inline code/security fix needed.
      Verified: gather-repo-state.sh builds JSON via env vars (no injection), discover-sig.sh ⟷
      gather-repo-state.sh hash the SAME superset (no stale-verdict hazard for the c3a6/c855
      caches), push-seed seeds `idle` only at provably-drained 0/0 (no under-dispatch), handback
      follow-up POSIX-escapes every shell arg + fire-and-forget, git-lock-push/clean-tree-gate
      both refuse to force-clean a foreign-dirty tree, profile-run.sh rollup-needle removed.
      shard-canary corpus is the correct behavior-preservation net for the 11ad refactor.
      1 LOW tracked: id:05e8 (`test_git_lock_push_slash_branch.sh` flaked on the first full-suite
      run, green in isolation + on re-run — pre-existing fetch/push timing flake, id:16e9 class,
      NOT new /tmp contention; both tests isolate via mktemp). Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-19-2005-strong-model-audit.md`.
    - Run 16 (2026-06-19-2015): first-seen change since Run 15's own audit commit `36fb824`
      (`36fb824..HEAD`) — **clean: LEDGER-ONLY window**. Sole first-seen change = the Run 15
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      36fb824..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. The RELAY_LOG paragraph is internally consistent (audit
      verdict + suite count + tracked-flake id) — no contradiction. Cross-ledger coherent
      (0 open ROUTINE / 3 HARD — dba3/401c/3346; the 4th `[ ]` HARD line is the DEFERRED
      design entry de4e, not executable; d5e0 agrees). Both pre-existing tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-19-2015-strong-model-audit.md`.
    - Run 17 (2026-06-19-2017): first-seen change since Run 16's own audit commit `250613f`
      (`250613f..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16 class). Sole first-seen change
      = the Run 16 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only 250613f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. **One coherence drift fixed inline** (Run 4/Run 8
      class) — TODO id:d5e0's hand-rolled "review 2026-06-16 1900" summary still listed the
      CLOSED id:10c0 (state-dir rename, `[x]` 2026-06-17 w/ completion id:bbd2) as an open HARD
      and OMITTED the open id:dba3; corrected the enumeration to the live ROADMAP set
      (dba3/401c/3346 + DEFERRED de4e). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2017-strong-model-audit.md`.
    - Run 18 (2026-06-19-2039): first-seen change since Run 17's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen
      change = the Run 17 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The RELAY_LOG paragraph is
      internally consistent (verdict + inline-fix note + suite count). Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable;
      all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2039-strong-model-audit.md`.
    - Run 19 (2026-06-19-2117): first-seen change since Run 18's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18 class). All first-seen
      changes are Run 18's own ledger/doc artifacts (RELAY_LOG checkpoint paragraph +8,
      ROADMAP run-log line +10, the Run 18 meeting note +67, a 1-line TODO d5e0 touch);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The two new RELAY_LOG
      paragraphs (Run 17 + Run 18) are internally consistent (verdict + suite count 76/0).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e
      DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees,
      Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 76/0. See `docs/meeting-notes/2026-06-19-2117-strong-model-audit.md`.
    - Run 20 (2026-06-19-2118): first-seen change since Run 19's own audit commit `f24b99e`
      (`f24b99e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19 class). Sole first-seen
      change = the Run 19 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only f24b99e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. The RELAY_LOG paragraph is internally consistent
      (verdict + no-inline-fix note + suite count 76/0). Cross-ledger coherent (0 open ROUTINE /
      3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both
      ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9,
      id:05e8) did NOT recur. Suite 76/0. See `docs/meeting-notes/2026-06-19-2118-strong-model-audit.md`.
    - Run 21 (2026-06-19-2155): first-seen change since Run 20's own audit commit `39592e8`
      (`39592e8..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class). First-seen
      changes = the Run 20 strong-execute + review checkpoint paragraphs in RELAY_LOG.md and two
      newly-minted TODO design items (id:81cb statusline per-session ctx state file; id:daf0
      screenshots + README refresh) under a new `## docs & presentation` header; `git diff
      --name-only 39592e8..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface (the two specs are purely-local additive sketches; id:daf0 itself flags the
      capture-privacy hazard for the build pass). Both new items internally sound (id:81cb's
      `.session_id`/`$CLAUDE_SESSION_ID` key both sides agree on is correct — statusline parses only
      `.transcript_path` today; id:daf0's README-vs-SKILL.md boundary consistent). **One coherence
      drift fixed inline (Run 4/8/17 class)** — the TODO id:401c MIRROR line still read "Latest ✓
      Run 19"; Run 20 had since run (ledger-only); refreshed it to Run 21. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three
      open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). id:16e9 did NOT
      recur; id:05e8 flaked once (75/1) then green in isolation + full-suite rerun (76/0), exactly
      as id:05e8 predicts. Suite 76/0 on rerun. See `docs/meeting-notes/2026-06-19-2155-strong-model-audit.md`.
    - Run 22 (2026-06-21-1656): first-seen change since Run 21's own audit commit `b0b4076`
      (`b0b4076..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class).
      First-seen changes = Run 21's strong-execute checkpoint + the two 2026-06-21 review
      checkpoint paragraphs in RELAY_LOG.md, a REVIEW_ME box (flaky-claim-liveness note),
      two new TODO design items (id:ebd0 [HIGH PRIORITY — SECURITY] global pre-push privacy
      gate; id:d2cd [HIGH PRIORITY] lock-hygiene umbrella), the id:ebd0 privacy sanitization,
      and an archived done entry; `git diff --name-only b0b4076..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY. No code to review, no security surface. gaming-scan clean (no DELETED_TEST/
      ADDED_SKIP/REMOVED_ASSERT). **One coherence drift fixed inline (Run 4/8/17/21 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 21"; refreshed to Run 22. Design
      coherence verified on both new items: id:d2cd's 5 cited sub-ids (3b18/6366/bae5/d187/
      3558) all exist in the ledgers and the umbrella framing is sound; id:ebd0's sanitization
      (e886e6f) correctly moved leak specifics to private memory (no-leak-specifics directive).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED
      non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1656-strong-model-audit.md`.
    - Run 23 (2026-06-21-1713): first-seen change since Run 22's own audit merge `c40b20e`
      (`c40b20e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22 class).
      Sole first-seen change = the Run 22 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only c40b20e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 22 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 22";
      refreshed to Run 23. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1713-strong-model-audit.md`.
    - Run 24 (2026-06-21-1626): first-seen change since Run 23's own audit merge `b2db0bc`
      (`b2db0bc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22/23 class).
      Sole first-seen change = the Run 23 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b2db0bc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 23 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22/23 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 23";
      refreshed to Run 24. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1626-strong-model-audit.md`.
    - Run 25 (2026-06-21-1842): first-seen change since Run 24's own audit merge `99a1f2e`
      (`99a1f2e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–24 class). First-seen = three
      RELAY_LOG checkpoint paragraphs + a real ROADMAP design-state change (`01e54c4`): id:dba3
      auto-gated `[HARD — strong model]` → `[HARD — decision gate]` route:human. `git diff
      --name-only 99a1f2e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY → no code/security surface.
      gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). **Design coherence: the
      id:dba3 gate change verified COHERENT** — closure genuinely needs the claude-probe OS user
      (id:d0c0, useradd/sudo — forbidden for an unattended relay child) + real Opus/Sonnet/Haiku
      token runs, so route:human is correct (consistent with the id:dba3 body, the open id:23e9
      seeding gate, and project memory; the gate will fire for a human, not silently — no
      can-never-fire gate). **One coherence drift fixed inline (Run 4/8/17/21/22/23/24 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 24"; refreshed to Run 25. Cross-ledger
      coherent (0 open ROUTINE / 3 open HARD — dba3 now decision-gated, 401c, 3346 gated; de4e
      DEFERRED non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1842-strong-model-audit.md`.
    - Run 26 (2026-06-21-1835): first-seen change since Run 25's own audit merge `cb83ad1`
      (`cb83ad1..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–25 class). Sole first-seen
      change = the Run 25 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only cb83ad1..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 25 verdict + dba3-gate-coherent + mirror-line drift fix + suite 76/0).
      **One coherence drift fixed inline (Run 4/8/17/21/22/23/24/25 class)** — the TODO
      id:401c MIRROR line still read "Latest ✓ Run 25"; refreshed to Run 26. Cross-ledger
      coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346;
      de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary
      agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1835-strong-model-audit.md`.
    - Run 27 (2026-06-21-1903): first-seen change since Run 26's own audit merge `32f430d`
      (`32f430d..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–26 class). Sole first-seen
      change = the Run 26 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 32f430d..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 26 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 26"; refreshed to Run 27. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1903-strong-model-audit.md`.
    - Run 28 (2026-06-21-1919): first-seen change since Run 27's own audit merge `8b82136`
      (`8b82136..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–27 class). Sole first-seen
      change = the Run 27 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8b82136..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 27 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 27"; refreshed to Run 28. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1919-strong-model-audit.md`.
    - Run 29 (2026-06-21-1935): first-seen change since Run 28's own audit merge `8016dfa`
      (`8016dfa..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–28 class). Sole first-seen
      change = the Run 28 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8016dfa..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 28 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27/28 class)** — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 28"; refreshed to Run 29. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1935-strong-model-audit.md`.
    - Run 30 (2026-06-22-0140): first-seen change since Run 29's own audit merge `422e95d`
      (`422e95d..HEAD`) — **SUBSTANTIVE CODE window** (breaks the Runs 11/12/16–29
      ledger-only streak): ~831 insertions / 11 code files. Production: gather-human-backlog.sh
      `emit_gated_hard`→`emit_hard_lanes` (id:78ff explicit `[HARD — pool|meeting|hands]`
      lane tags, untagged=LOUD nonzero reject id:415b); relay-reconcile.sh `--all` cross-repo
      orphan list (unreadable repo SURFACED not swallowed — the id:4e14 anti-pattern avoided);
      orphan-scan.sh `--promotion` + `xledger-ok` (id:d9b0 seam tooling); git-lock-push.sh
      `GIT_TERMINAL_PROMPT=0` + `ssh-add -l` precheck + BatchMode push; new
      tools/check-no-silent-swallow.sh swallow-ban guard (id:4347, advisory→`--enforce`).
      **CLEAN — no code/security defects** across all 3 passes: lane awk regex verified
      against the live 4 open HARD items (all classify right; `[—-]` backwards-range is a
      benign gawk literal set); rc-plumbing survives `set -e`; no injection (relay.toml
      trusted, fixed grep patterns, quoted `git -C`); git-lock-push HARDENS auth. Design
      coherent: id:78ff contract consistent across hard-lanes.md/collector/human.md/test;
      `route:human`→meeting bucket (not hands) **explicitly accepted** (auto-gate emits a
      coarse human-route; fine pool/meeting/hands is a human hand-tag job); swallow-ban
      ships ADVISORY (231 un-annotated swallows in 51 scripts = exactly why not yet
      enforcing). gaming-scan clean. **One coherence drift fixed inline (Run 4/8/17/21–29
      class)** — TODO id:401c MIRROR line still read "Latest ✓ Run 29"; refreshed to Run 30
      (d5e0 itself NOT stale this run). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open
      in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur (id:6b91's CLAIM_TTL fix hardens the id:16e9 class). Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0140-strong-model-audit.md`.
    - Run 31 (2026-06-22-0145): first-seen change since Run 30's own audit merge `00cfff7`
      (`00cfff7..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–29 class). Sole first-seen
      change = the Run 30 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 00cfff7..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 30 verdict + suite 80/0). **No coherence drift this run** — unlike
      the Run 4/8/17/21–30 class, the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 30 refreshed the mirror to Run 30; d5e0 not stale).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated /
      401c / 3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean
      run. See `docs/meeting-notes/2026-06-22-0145-strong-model-audit.md`.
    - Run 32 (2026-06-22-0215): first-seen change since Run 31's own audit merge `d55fd25`
      (`d55fd25..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0208` / `e37df3a`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31 class). Sole first-seen change = the Run 31
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      d55fd25..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 31 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 31). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0215-strong-model-audit.md`.
    - Run 33 (2026-06-22-0317): first-seen change since Run 32's own audit merge `b315aed`
      (`b315aed..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0217` / `59b0b99`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31/32 class). Sole first-seen change = the Run 32
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      b315aed..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 32 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 32). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0317-strong-model-audit.md`.
    - Run 34 (2026-06-22-0712): first-seen change since Run 33's own audit merge `62b58fa`
      (`62b58fa..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0712` / `c95852b`) —
      **LEDGER-ONLY window**: `git diff --name-only 62b58fa..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (the window = two TODO+ROADMAP design-analysis commits, `ca1e5f1` id:7809 +
      `31d854b` id:98f0, plus the Run 33 RELAY_LOG checkpoint paragraph). No code to review,
      no security surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      **Design-coherence pass (substantive this run, unlike the pure-vacuity LEDGER runs):**
      the two NEW `[HARD — meeting]` items are internally consistent and well-formed —
      id:7809 (auto-reconcile-on-restart: a `.relayactive`/heartbeat marker + a TIERED
      safe-vs-judgment orphan classifier — auto-integrate clean/green/ledger-only, SURFACE
      BLOCKED/partial/red; the zkm-stt fixture case is cited as live evidence the judgment
      tier is justified; relates 689c/3313/4e14/0902/98f0/194e — no contradiction) and
      id:98f0 (outage-resilient LOCAL loop: the user-corrected three-way bind — cloud
      `/schedule` survives an outage but can't reach local `~/src`/worktrees/fievel; the only
      local-reaching fit, an OS systemd timer running `claude -p "/relay --afk"`, hits the
      headless permission wall the user won't bypass with `--dangerously-skip-permissions`;
      options a–f well-formed, ties to id:2d01 dedicated-OS-user path — coherent). Both
      correctly routed `[HARD — meeting]` per id:78ff lanes and mirrored single-id-two-views
      into ROADMAP. **2 coherence drifts fixed inline** (the recurring Run 4/8/17 class): the
      TODO d5e0 summary still read "3 open ROADMAP items, all HARD" but the window added two
      open HARD (7809/98f0) → corrected to 5; the id:401c MIRROR line still read "Latest ✓
      Run 33" → refreshed to Run 34. Cross-ledger coherent after fix (0 open ROUTINE / 5
      executable HARD — 401c [pool] / 3346 / dba3 [decision-gate] / 7809 / 98f0; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0712-strong-model-audit.md`.
    - Run 35 (2026-06-22-0722): first-seen change since Run 34's own merge `40bc011`
      (`40bc011..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0722` / `9702417`) —
      **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen change = the Run 34
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      40bc011..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/
      REMOVED_ASSERT). The Run 34 RELAY_LOG paragraph is internally consistent (verdict +
      window + suite count + mirror-drift note match its own meeting note + run log).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346
      [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). **1 coherence drift fixed inline** (Run 4/8/17 mirror class) — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 34"; refreshed to Run 35. Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0722-strong-model-audit.md`.
    - Run 36 (2026-06-22-0737): first-seen change since Run 35's own merge `69c0bc5`
      (`69c0bc5..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0737` / `c0dece8`) —
      **LEDGER-ONLY window**: `git diff --name-only 69c0bc5..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (window = the new id:f576 TUI ghost-fragment TODO meta-issue `c54c96e`, the
      `-0730` review(relay) LEDGER-ONLY commit+merge `852c58a`/`4f2200d`, plus the
      `-0730`/`-0737` RELAY_LOG checkpoint paragraphs). No code to review, no security
      surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT; no test files
      changed). **Design-coherence pass (substantive):** the new id:f576 entry
      (Claude Code TUI ghost workflow-progress/statusline fragments after exiting
      `/workflows`) is internally consistent and well-formed — correctly classified
      cosmetic (Ctrl+L/SIGWINCH clears it), plausible render-race root cause, routed as an
      external/harness meta-issue with NO executable lane tag → correctly TODO-only (not
      promoted to ROADMAP, not in the d5e0 count); `#1 upgrade past v2.1.181` is sound (box
      runs 2.1.177); `disableWorkflows: true` correctly flagged UNSUITABLE here (relay pool
      depends on the Workflow tool) — no contradiction. RELAY_LOG checkpoint paragraphs
      internally consistent. **1 coherence drift fixed inline** (recurring Run 4/8/17/35
      mirror class) — the TODO id:401c MIRROR line still read "Latest ✓ Run 35"; refreshed
      to Run 36. Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0737-strong-model-audit.md`.
    - Run 37 (2026-06-22-0942): first-seen change since Run 36's own audit merge `b93f024`
      (`b93f024..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0942` / `183a272`) —
      **SUBSTANTIVE CODE window** (breaks the Run 31/32/33/35/36 ledger-only streak): 403
      insertions / 6 files. First-seen code = the new `relay/scripts/roadmap-archive.sh`
      (id:6b67 [ROUTINE], Relay ROADMAP archiver, 167 L, shipped by a Sonnet executor in
      `f6f594b`) + `tests/test_roadmap_archive.sh` (201 L, 9 hermetic cases, `# roadmap:6b67`)
      + Makefile registration (relay_FILES/EXEC/ALLOW). **CLEAN — no code/security defects**
      across all 3 passes: trap-ordering sound (last EXIT trap cleans both temp+lock, no leak);
      conservative prior-commit/≥30d gate correct — a working-tree-only tick is NEVER archived
      (verified T3 positive / T4 negative); multi-line block capture + `<!-- id:XXXX -->` token
      preservation + no-section-pruning (deliberate divergence from archive-done.sh, ROADMAP
      headers are structural) all verified; quoted `<<'PYEOF'` heredoc with argv-passed inputs
      = no injection, no path traversal beyond the repo, stdlib-only Python, no secrets/network,
      lock covered by the `*.lock` gitignore. gaming-scan clean (test file wholly NEW — additions
      only, no deleted asserts / added skips / removed checks). Design coherent: id:93cc→id:6b67
      single-id-two-views chain sound (93cc = TODO "Prompt is too long" meta-issue, 6b67 =
      fix-direction (b) archiver promoted to ROADMAP; no duplicate-id mint; test maps its item;
      ticked `[x]` ⇒ suite green = DoD). **1 LOW accepted** — `trap 'rm "$LOCK_FILE"'` removes a
      flock'd lock file (unlink-race vs the canonical append.sh/git-lock-push.sh persistent-lock
      pattern); theoretical only — script is `-n` non-blocking (concurrent run cleanly skips),
      has NO automated caller today, rare+idempotent+single-writer; documented future-fix trigger
      (drop the rm if an automated caller is added). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (ROADMAP execution unit closed,
      broader TODO design-ledger umbrella stays open) — not drift from this window. **1 coherence
      drift fixed inline (recurring Run 4/8/17/35/36 mirror class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 36"; refreshed to Run 37 (d5e0 count line NOT stale this run
      — already 5 open HARD / 0 ROUTINE after id:6b67 closed). Cross-ledger coherent (0 open
      ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / 7809
      [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five open in both
      ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes (id:16e9, id:05e8)
      did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0942-strong-model-audit.md`.
    - Run 38 (2026-06-22-0953): first-seen change since Run 37's own audit merge `8258aa3`
      (`8258aa3..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0953` / `9ec0b6b`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36 class). Sole first-seen
      change = the Run 37 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 8258aa3..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh "$repo" 8258aa3` exit 0, no output),
      no new design decision/gate (Pass 3 — the Run 37 checkpoint paragraph is internally
      consistent with the Run 37 run-log entry + meeting note: same window `b93f024..HEAD`,
      same id:6b67 subject, same suite 81/0; no contradiction). **Pre-existing accepted (out
      of window)** — `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x];
      both predate this window and are the intended single-id-two-views shape (already accepted
      Run 37). **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37 mirror class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 37"; refreshed to Run 38 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed). Cross-ledger
      coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five
      open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0953-strong-model-audit.md`.
    - Run 39 (2026-06-22-1004): first-seen change since Run 38's own audit merge `0174a69`
      (`0174a69..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-1004` / `3cb4d7a`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36/38 class). Sole first-seen
      change = the Run 38 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 0174a69..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh . 0174a69` exit 0, no output), no new
      design decision/gate (Pass 3 — the Run 38 checkpoint paragraph is internally consistent
      with the Run 38 run-log entry + meeting note: same window `8258aa3..HEAD`, same LEDGER-ONLY
      verdict, same suite 81/0; no contradiction). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (already accepted Run 37/38).
      **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37/38 mirror class)** — the
      TODO id:401c MIRROR line still read "Latest ✓ Run 38"; refreshed to Run 39 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable;
      all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked
      flakes (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-1004-strong-model-audit.md`.
    - Run 40 (2026-06-22-1601): first **CODE** window since Run 39's LEDGER-ONLY runs —
      `3600642..HEAD` (HEAD = `relay-ckpt-20260622-1715` / `10d837e`), ~251 lines / 12 files.
      First-seen code: the id:93cc ROADMAP discovery-trimmer in `gather-repo-state.sh`, the
      id:7d1e per-verdict progress buckets in `relay-loop.js`, and the id:bde8 loop-hint
      resilience-wording correction (`loop-hint.sh` + SKILL.md), plus the id:98f0/7809
      outage-resilience meeting note. **1 forward-robustness defect fixed inline** — the id:93cc
      trimmer's `python3 … 2>/dev/null || true` failed CLOSED to an EMPTY roadmap on a trimmer
      crash → would silently misclassify the repo as `handoff` (relay-loop.js ~L630 "roadmap
      missing") and re-do C1/C2; changed to fail-OPEN `|| cat "$path/ROADMAP.md"` + a non-vacuous
      regression guard in `test_gather_repo_state.sh` (proven RED on the reverted `|| true` form).
      Pass-1 otherwise clean (trimmer block-parsing correct; per-verdict buckets pure display
      grouping, zero behavioural change, consistent with the pre-existing Integrate bucket).
      Pass-2 security clean (`gaming-scan.sh . 3600642` exit 0; no injection — trimmer reads a
      quoted env path, JS changes are literals). Pass-3 design-coherence: loop-hint correction
      matches memory `babysitter-durable-cron-no-op`; verified the meeting note's claimed
      `[HARD — meeting]→[HARD — hands]` retag of 7809/98f0 landed in ROADMAP and that new items
      e149/0994 are wired. **2 coherence drifts fixed inline (recurring d5e0/mirror class)** —
      (a) the d5e0 count line read "5 open ROADMAP items" with 7809/98f0 mislabelled
      `[HARD — meeting]`; corrected to 7 open HARD with e149/0994 added + the lane fix; (b) the
      TODO id:401c MIRROR line read "Latest ✓ Run 39"; refreshed to Run 40. Cross-ledger coherent
      (0 open ROUTINE / 7 open HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 test-files on a clean run
      (the new regression guard is an assertion inside test_gather_repo_state.sh, 17→18 cases).
      See `docs/meeting-notes/2026-06-22-1601-strong-model-audit.md`.
    - Run 41 (2026-06-22-1757): first-seen change since Run 40's own audit merge `f3c26f8`
      (`f3c26f8..HEAD`, HEAD = `relay-ckpt-20260622-1757` / `4574c3b`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40 class). `git diff --name-only f3c26f8..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY — the only code in the raw `10d837e..HEAD` range
      (`gather-repo-state.sh` + `test_gather_repo_state.sh`, `c941c4e`) is Run 40's OWN
      already-audited id:93cc fail-open fix, out of this window. First-seen changes: Run 40's
      strong-execute+review checkpoint paragraphs in RELAY_LOG.md; the Agent-SDK / `claude -p`
      subscription-billing DEFERRAL note (`e06088f` — new TODO `[MEETING]` id:00a5 multi-perspective
      applications eval + a dba3 "Billing path REAFFIRMED" addendum + a 98f0 billing parenthetical);
      and the review tick of TODO id:bde8 `[ ]`→`[x]` (`561c3fa`, cross-ledger D2 fix). No code to
      review, no security surface (`gaming-scan.sh . f3c26f8` exit 0). Pass-3 design-coherence:
      id:00a5 is internally sound (single TODO-only token, meeting-lane → correctly NOT promoted to
      ROADMAP; cross-refs id:2d01/98f0/dba3/hermes-deferral-contract all resolve), the billing notes
      across dba3/98f0/00a5/memory `anthropic-agent-sdk-billing-deferred` are mutually consistent (no
      contradiction with id:2d01's path-A rationale), and bde8 is now canonically `[x]` in both
      ledgers. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/21/40)** — the
      TODO id:401c MIRROR line read "Latest ✓ Run 40"; refreshed to Run 41. The d5e0 count line needed
      NO change (already 7 open HARD / 0 ROUTINE; no items opened/closed this window). Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both
      ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-1757-strong-model-audit.md`.
    - Run 42 (2026-06-22-1818): first-seen change since Run 41's own audit merge `b65ba59`
      (`b65ba59..HEAD`, HEAD = `relay-ckpt-20260622-1818` / `00f54cf`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41 class). `git diff --name-only b65ba59..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 41 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`00f54cf`). No code to review, no security surface
      (`gaming-scan.sh . b65ba59` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 41 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0, 1 mirror-line drift);
      no item opened/closed this window. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41)** — the TODO id:401c MIRROR line read "Latest ✓ Run 41"; refreshed
      to Run 42. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1818-strong-model-audit.md`.
    - Run 43 (2026-06-22-1827): first-seen change since Run 42's own audit commit `a56bed7`
      (`a56bed7..HEAD`, HEAD = `relay-ckpt-20260622-1827` / `9db884a`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41/42 class). `git diff --name-only a56bed7..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 42 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`9db884a`). No code to review, no security surface
      (`gaming-scan.sh . a56bed7` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 42 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0); no item opened/closed
      this window. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/40/41/42)**
      — the TODO id:401c MIRROR line read "Latest ✓ Run 42"; refreshed to Run 43. The d5e0 count
      line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1827-strong-model-audit.md`.
    - Run 44 (2026-06-23-0701): first-seen code since Run 43's own audit commit `c66c6f4`
      (`c66c6f4..HEAD`, HEAD = `relay-ckpt-20260622-2215` / `e5962f3`) — **REAL CODE window**
      (not LEDGER-ONLY): id:bae5 uv.lock-cascade exemptions (`gather-repo-state.sh`
      `lock_only_unaudited`/`dirty_lock_only` + relay-loop.js review/dirty exemptions),
      id:e107 EXECUTOR-ACTIONABLE @manual/human-only guard (relay-loop.js), id:2c42 deferred
      ledger write-back (meeting/SKILL.md + todo-update/SKILL.md + .gitignore + red→green spec).
      **CLEAN — no inline code/security fix.** Pass-1: bae5's lock booleans diff the SAME
      `latest..HEAD` range as `commits_since` (can't disagree with the review verdict), use a
      fixed-string whole-line `grep -vx 'uv.lock'` (root-only, conservative), all new pipelines
      `set -e`-safe (`|| true` + `[[ ]]`); `$NF` porcelain extraction correct for modify/rename;
      e107 mirrors the EXECUTABLE-HARD gate pattern (id:2d20) — no-op-execute thrash rationale
      sound. Pass-2: gather additions pure-read (no eval/injection/secrets); bae5 dirty-lock
      auto-commit is a bounded named git op on a trusted relay.toml path; id:2c42 replay applies
      only under a FRESH claim via allowlisted flock'd helpers. Pass-3: bae5/e107 slot cleanly
      into the documented precedence (no never-firing gate, no contradiction); id:2c42 matches
      its acceptance verbatim (generic breadcrumb wired only at step 2a, replay in both /meeting
      + /todo-update, gitignore entry); af04 note records the worktree-per-/meeting rejection.
      `gaming-scan.sh . c66c6f4` exit 0. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41/42/43)** — the TODO id:401c MIRROR line read "Latest ✓ Run 43";
      refreshed to Run 44. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE;
      the id:2c42 ROUTINE item closed this window). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 83/0 on a clean run. See
      `docs/meeting-notes/2026-06-23-0701-strong-model-audit.md`.
    - Run 45 (2026-06-23-0939): first-seen code since Run 44's own audit commit `0e60f1f`
      (`0e60f1f..HEAD`, HEAD = `relay-ckpt-20260623-0923` / `6dbecf9`) — **REAL CODE window**:
      id:000d deterministic `is_finished` guard (gather-repo-state.sh + relay-loop.js),
      id:1d64 margin-aware quota-stop staleness, id:3c0f `[HARD — pool]` token sync,
      id:69ef install-manifest completeness guard; id:09a3 (`roadmap-lint.sh`) shipped only
      its RED spec `tests/test_roadmap_lint.sh` (script not yet written) — correctly
      EXPECTED-RED, item still open. **1 HIGH defect FIXED INLINE (id:000d):** the JS-side
      `is_finished` demote guard was DEAD code — `DISCOVER_SCHEMA.units[]` did not declare
      `is_finished` and the shard-prompt per-repo-fields list never instructed copying it, so
      the deterministic value computed by gather-repo-state.sh never reached the unit object
      (the JS reads `u.is_finished`, which was always `undefined`). The only live path was the
      non-deterministic LLM shard-prompt instruction — exactly the path id:000d's backstop
      existed to correct; the pre-existing structural test passed because it grepped the guard
      TEXT, not its behaviour. Fixed: declared the schema property, added an explicit "COPY
      is_finished verbatim" prompt line, and added two non-vacuous assertions to
      `test_relay_loop_structure.sh` (schema declares it + prompt instructs the copy) that fail
      on the pre-fix form. Pass-1 otherwise CLEAN: id:1d64 moved `decay_threshold`/`bucket_threshold`
      earlier so they're defined before the new stale-margin block calls them (correct ordering),
      margin math + missing-bucket→exit2 sound; id:3c0f/69ef pure literal/positive-grammar checks.
      Pass-2: no new injection/traversal/secrets (`awk -v` + `${!envname}` read fixed-domain
      provider/bucket inputs; is_finished block pure-read). Pass-3: the guard now closes its own
      loop (deterministic value → unit → JS backstop), demote-only invariant intact, no
      contradiction with the bae5 lock-only-dirty exemption. `gaming-scan.sh . d068334` exit 0.
      **Mirror drift fixed inline (Run 4/8/17/… class)** — TODO id:401c MIRROR line read "Latest
      ✓ Run 44"; refreshed to Run 45. Cross-ledger coherent (0 open ROUTINE after 000d/1d64/3c0f/69ef
      closed this window; open executable-or-gated HARD: 09a3 [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; the d5e0 prose
      enumeration is slated for dissolution under id:1de1/659c and still predates id:09a3 — left
      as-is, not re-enumerated, since 09a3's re-dispatch is suppressed and the count authority is
      moving to the id:2840 index). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite
      87/0 + 1 EXPECTED-RED (id:09a3) on a clean run. See
      `docs/meeting-notes/2026-06-23-0939-strong-model-audit.md`.
    - Run 46 (2026-06-23-0945): `d342839..HEAD` (window start = Run 45's audit-note
      commit) — **LEDGER-ONLY, CLEAN by vacuity**. Only commits: `b2b6ee9` (the `--no-ff`
      merge LANDING Run 45's already-audited work — not re-audited) + `1d4b9cb` (checkpoint,
      RELAY_LOG +4). `git diff d342839..HEAD` excluding RELAY_LOG/relay.toml is EMPTY → no
      first-seen code (passes 1+2 N/A). **One coherence finding, fixed inline:**
      `orphan-scan --cross-ledger` flagged id:3c0f/69ef (TODO:[ ] vs ROADMAP:[x]) — a
      scope-split FALSE-POSITIVE (id:d9b0 §3 class): both builds genuinely closed in
      ROADMAP/Run 45; their tokens appear in TODO only inside the still-open umbrella
      line-34 ("lane-token drift + grammar lint", pending id:09a3). Added the
      `<!-- xledger-ok: ... -->` annotation id:d9b0 built for exactly this → cross-ledger
      now exits clean. id:09a3 NOT annotated (still open in ROADMAP too, parked orphan, no
      divergence). gaming-scan `"$PWD" d342839` exit 0; suite 87/0 + 1 EXPECTED-RED (id:09a3).
      Mirror: TODO id:401c line refreshed Run 45→Run 46. See
      `docs/meeting-notes/2026-06-23-0945-strong-model-audit.md`.
    - Run 48 (2026-06-23-1730): first-seen code since Run 46's own audit commit `993d905`
      (merge `80a8441..HEAD`) — **REAL CODE** (Run 47 review shipped id:ad74 + id:09a3 in
      this window, never strong-audited). **1 HIGH defect fixed inline**: the id:ad74
      JS-side INTENSIVE promote backstop in relay-loop.js was a NO-OP — the exact symmetric
      twin of the id:401c Run 45 dead-guard bug, in the very feature meant to be the PROMOTE
      counterpart of that DEMOTE guard. Branch 1 (skipped→unit) was provably-dead code
      (`top_intensive && !u` unreachable; skipped rollup items carry no `top_intensive`);
      branch 2 patched an idle unit's `.intensive` but never flipped `verdict` off `'idle'`,
      so `actionable = units.filter(u => u.verdict !== 'idle')` dropped it BEFORE the
      INTENSIVE partition — silent drop, not even surfaced as deferred. Rewrote to operate
      on emitted units only and FLIP idle→execute (survives the filter → intensive partition
      → `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`); dropped the dead branch.
      Added non-vacuous static guards (2c)/(2d) to `test_relay_loop_intensive_emit.sh`
      (verified: both FAIL against pre-fix JS, pass against fix). roadmap-lint.sh (id:09a3)
      + gather `top_intensive` field clean; lint correctly wired into review §5 + human. 1
      coherence ACCEPTED (c3a6 cache: `top_intensive` is a pure fn of the already-hashed
      ROADMAP blob → no sig change). Cross-ledger drift fixed inline (id:ad74 TODO:[ ] vs
      ROADMAP:[x] — build now genuinely complete post-fix → ticked the TODO twin). gaming-scan
      `"$PWD" 80a8441` exit 0; suite 89/0/0. Mirror: TODO id:401c refreshed Run 46→Run 48
      (Run 47 was the review that shipped this window, not an audit run). See
      `docs/meeting-notes/2026-06-23-1730-strong-model-audit.md`.
    - Run 49 (2026-06-23-1749): first-seen change since Run 48's own audit merge `7dfe7e0`
      (`7dfe7e0..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46 class). Sole
      first-seen change = the Run 48 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 7dfe7e0..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 48 verdict + suite 89/0/0 + the id:ad74 fix).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO; d5e0 agrees). roadmap-lint.sh exit 0;
      gaming-scan `"$PWD" 7dfe7e0` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT
      recur. Mirror: TODO id:401c line refreshed Run 48→Run 49. See
      `docs/meeting-notes/2026-06-23-1749-strong-model-audit.md`.
    - Run 50 (2026-06-23-1724): first-seen change since Run 49's own audit merge `12b151e`
      (`12b151e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49 class). Sole
      first-seen change = the Run 49 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 12b151e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 49 verdict + roadmap-lint 0/gaming-scan 0/suite
      89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c
      [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 12b151e` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 49→Run 50. See `docs/meeting-notes/2026-06-23-1724-strong-model-audit.md`.
    - Run 51 (2026-06-23-1724b): first-seen change since Run 50's own audit merge `b46be9a`
      (`b46be9a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50 class). Sole
      first-seen change = the Run 50 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b46be9a..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY (verified
      the earlier `efbb7bd` id:d530 TODO note is an ancestor of `b46be9a` — covered by Run 50,
      not first-seen). No code to review, no security surface, no new design decision/gate. The
      RELAY_LOG paragraph is internally consistent (Run 50 verdict + roadmap-lint 0/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" b46be9a` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 50→Run 51. See `docs/meeting-notes/2026-06-23-1724b-strong-model-audit.md`.
    - Run 52 (2026-06-23-1724c): first-seen change since Run 51's own audit merge `9dfce93`
      (`9dfce93..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51 class). Sole
      first-seen change = the Run 51 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 9dfce93..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 51 verdict + orphan-scan/roadmap-lint/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9dfce93` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 51→Run 52. See `docs/meeting-notes/2026-06-23-1724c-strong-model-audit.md`.
    - Run 53 (2026-06-23-1724d): first-seen change since Run 52's own audit merge `8052b4f`
      (`8052b4f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52 class).
      Window = the Run 52 strong-execute checkpoint paragraph in RELAY_LOG.md (+4) AND one new
      TODO discussion item, id:9000 (`[HARD — meeting]` inter-session coordination channel, +1);
      `git diff --name-only 8052b4f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review,
      no security surface. Coherence pass on the sole new design artifact (TODO id:9000):
      `[HARD — meeting]` lane correct for a discussion placeholder; every cross-reference
      resolves to a real, consistent item (id:0902/ebfb lease / id:c144 ledger-lease-exempt /
      id:2c42 deferred write-back / id:c012 `/relay stop` / id:98f0/e149 watchdog heartbeat);
      observe-first gate (≥2–3 recurrences, FIRST logged instance) intact, no contradiction
      with the af04 worktree-per-meeting rejection — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" 8052b4f` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 52→Run 53. See
      `docs/meeting-notes/2026-06-23-1724d-strong-model-audit.md`.
    - Run 54 (2026-06-23-1909): first-seen change since Run 53's own audit merge `e905c84`
      (`e905c84..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53 class).
      Window = two RELAY_LOG checkpoint paragraphs (Run 53 strong-execute 18:38 + reviewer
      doc-only 18:51, +8) AND one in-place TODO edit to id:9000 (the UPDATE 2026-06-23
      incident-resolved urgency-reframe, ±1); `git diff --name-only e905c84..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. No code to review, no security surface. Coherence pass on the
      sole new design artifact (id:9000 reframe): correctly narrows scope from "prevent
      corruption" (now redundant) to "avoid wasted stale-base work + surface intent" because
      the cited backstop **id:aa93** (dirty-main-checkout guard, ROADMAP `[x]` shipped
      2026-06-18 — clean-tree-gate.sh in integrate step 1) RESOLVES and supports the claim;
      observe-first gate STRENGTHENED ("the backstop held"), every original cross-ref
      preserved + resolves, lane tag unchanged — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" e905c84` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 53→Run 54. See
      `docs/meeting-notes/2026-06-23-1909-strong-model-audit.md`.
    - Run 55 (2026-06-23-1724e): window = since Run 54's audit merge `2cd8d6e`
      (`2cd8d6e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54
      class). `git diff --name-only 2cd8d6e..HEAD` = only RELAY_LOG.md + TODO.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Window = three RELAY_LOG checkpoint paragraphs
      (8e041af reviewer 18:51, 92addcb strong-execute 19:13 = Run 54's own ckpt, 4ee6ffd
      reviewer 19:40) AND one `todo(meeting)` commit (8679992) minting two new
      design-deferred TODO items. No code → no Pass-1/Pass-2 surface (clean by vacuity).
      Pass-3 coherence on the sole new design artifact: id:74c7 (`/meeting --cross` inline
      path skips canonical persona-load setup) + id:d23f (same inline path skips the
      EnterPlanMode→ExitPlanMode approval gate) — both minted, sharply scoped to an
      explicit a-vs-b decision (re-dispatch-always vs carry-scaffolding), correctly
      cross-referenced (id:1d01 distinguished, id:d44d, id:a6cb, each other), cite the
      source zkm meeting note, and correctly TODO-parked (design judgment needed, not
      ROADMAP-promotable). id:d23f correctly carves out the by-design Class-3
      decisions→ledger deferral as NOT-the-bug. No contradiction, no dead gate, no defect.
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool]
      / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees).
      orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 2cd8d6e`
      exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c
      line refreshed Run 54→Run 55. See `docs/meeting-notes/2026-06-23-1724e-strong-model-audit.md`.
    - Run 56 (2026-06-23-2024): window = since Run 55's audit merge `578c854`
      (`578c854..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55
      class). `git diff --name-only 578c854..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `ca4a743` (checkpoint 20260623-2001
      strong-execute) adds one RELAY_LOG paragraph = Run 55's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 578c854` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 55→Run 56. See `docs/meeting-notes/2026-06-23-2024-strong-model-audit.md`.
    - Run 57 (2026-06-23-2031): window = since Run 56's audit merge `9782379`
      (`9782379..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56
      class). `git diff --name-only 9782379..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `2b60f5f` (checkpoint 20260623-2011
      strong-execute) adds one RELAY_LOG paragraph = Run 56's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9782379` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 56→Run 57. See `docs/meeting-notes/2026-06-23-2031-strong-model-audit.md`.
    - Run 58 (2026-06-23-2037): window = since Run 57's audit merge `9b2abd7`
      (`9b2abd7..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57
      class). `git diff --name-only 9b2abd7..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `3813fef` (checkpoint 20260623-2021
      strong-execute) adds one RELAY_LOG paragraph = Run 57's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9b2abd7` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 57→Run 58. See `docs/meeting-notes/2026-06-23-2037-strong-model-audit.md`.
    - Run 59 (2026-06-23-2040): window = since Run 58's audit merge `c8d4469`
      (`c8d4469..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58
      class). `git diff --name-only c8d4469..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `8d8838d` (checkpoint 20260623-2029
      strong-execute) adds one RELAY_LOG paragraph = Run 58's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8d4469` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 58→Run 59. See `docs/meeting-notes/2026-06-23-2040-strong-model-audit.md`.
    - Run 60 (2026-06-23-2044): window = since Run 59's audit merge `73e4903`
      (`73e4903..daf5694`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59
      class). `git diff --name-only 73e4903..daf5694` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `daf5694` (checkpoint 20260623-2038
      strong-execute) adds one RELAY_LOG paragraph = Run 59's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 73e4903` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 59→Run 60. See `docs/meeting-notes/2026-06-23-2044-strong-model-audit.md`.
    - Run 61 (2026-06-23-2054): window = since Run 60's audit merge `9da3a6f`
      (`9da3a6f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60
      class). `git diff --name-only 9da3a6f..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `a4d670b` (checkpoint 20260623-2047
      strong-execute) adds one RELAY_LOG paragraph = Run 60's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9da3a6f` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 60→Run 61. See `docs/meeting-notes/2026-06-23-2054-strong-model-audit.md`.
    - Run 62 (2026-06-23-2102): window = since Run 61's audit merge `91d639a`
      (`91d639a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61
      class). `git diff --name-only 91d639a..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `564f217` (checkpoint 20260623-2056
      strong-execute) adds one RELAY_LOG paragraph = Run 61's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 91d639a` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 61→Run 62. See `docs/meeting-notes/2026-06-23-2102-strong-model-audit.md`.
    - Run 63 (2026-06-23-2110): window = since Run 62's audit merge `a360ac6`
      (`a360ac6..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61/62
      class). `git diff --name-only a360ac6..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `e7d7e4f` (checkpoint 20260623-2104
      strong-execute) adds one RELAY_LOG paragraph = Run 62's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" a360ac6` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 62→Run 63. See `docs/meeting-notes/2026-06-23-2110-strong-model-audit.md`.
    - Run 64 (2026-06-23-1724f): `c8127e0..HEAD` (HEAD `69dd4d8`) — **LEDGER-ONLY clean
      by vacuity**. `git diff --name-only c8127e0..HEAD` = only `RELAY_LOG.md`;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `69dd4d8` (checkpoint 20260623-2113
      strong-execute) adds one RELAY_LOG paragraph = Run 63's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8127e0` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 63→Run 64. See `docs/meeting-notes/2026-06-23-1724f-strong-model-audit.md`.
    - Run 65 (2026-06-23-1724g): window = since Run 64's audit merge `69dd4d8`
      (`69dd4d8..HEAD`, HEAD `17c062f`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–64
      class). `git diff --name-only 69dd4d8..HEAD` = RELAY_LOG.md + ROADMAP.md + TODO.md + the
      Run 64 meeting note (all Run 64's own audit + checkpoint ledger writes);
      `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `34c8a1c` (Run 64 audit), `417321f` (its
      merge), `17c062f` (checkpoint 20260623-2123 = Run 64's own record). No code → no
      Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design item, gate, or
      contract change → no Pass-3 artifact (Run 64's own ledger records are internally
      consistent: its verdict + cited gates match this run's re-verification; TODO mirror
      Run 63→64 correct). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 69dd4d8` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 64→Run 65. See
      `docs/meeting-notes/2026-06-23-1724g-strong-model-audit.md`.
    - Run 66 (2026-06-23-1724h): window = since Run 65's audit commit `9330f72`
      (`9330f72..HEAD`, HEAD `62fc2c7`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–65
      class). `git diff --name-only 9330f72..HEAD` = RELAY_LOG.md only (Run 65's own checkpoint
      paragraph); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `5b1e0a4` (Run 65 merge), `62fc2c7`
      (checkpoint 20260623-2132 = Run 65's own record). No code → no Pass-1/Pass-2 surface (clean
      by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3 artifact
      (Run 65's own RELAY_LOG paragraph is internally consistent: its verdict + cited gates match
      this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 9330f72` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 65→Run 66. See
      `docs/meeting-notes/2026-06-23-1724h-strong-model-audit.md`.
    - Run 67 (2026-06-23-2145): window = since Run 66's audit commit `a689119`
      (`a689119..HEAD`, HEAD `5e1a216`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–66
      class). `git diff --name-only a689119..HEAD` = RELAY_LOG.md only (Run 66's own checkpoint
      paragraph, +4 lines); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `b8cda3c` (Run 66 merge),
      `5e1a216` (checkpoint 20260623-2140 = Run 66's own record). No code → no Pass-1/Pass-2 surface
      (clean by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3
      artifact (Run 66's own RELAY_LOG paragraph is internally consistent: its verdict + cited checks
      match this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 /
      98f0 / 0994 [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO;
      d5e0 agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" a689119` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 66→Run 67. See
      `docs/meeting-notes/2026-06-23-2145-strong-model-audit.md`.
    - Run 69 (2026-06-30-1855): window = `8d8d40b..HEAD` (HEAD `7527cb1`), since Run 68 —
      133 commits / ~6007 insertions across 88 files; substantive engine surface ~21
      scripts+code files + tests (`substantive_unaudited=true`). Four days of mechanical-classifier
      (id:4d8e) + outage-resilience build: NEW classify-verdict.sh (85df), classify-repo.sh (3f0f),
      backtest-verdict.py (5f93), decision-queue.sh (de31), drain.mjs (d58f), heartbeat.sh (e149),
      host-gate.sh (43b9), memory-append.sh (6f61), pathspec-drop-guard.py (b67e), relay-watchdog
      (98f0); MODIFIED relay-loop.js (drain/heartbeat/phase-buckets/worked_ids/quota-extrapolation),
      gather-repo-state.sh + classify-repo.sh execve-overflow temp-file fix (07be/3f0f), claim.sh
      heartbeat-gated liveness (33d3), scan-routed --apply (678e), ckpt-tag graceful degrade (a7a3).
      **Pass-1 code review CLEAN** + **Pass-2 security CLEAN** (no correctness/injection defects —
      verified classify-verdict pure-stdin parity-guards, execve temp-file fixes, heartbeat
      ts+TTL, claim fail-safe heartbeat gate, decision-queue set-e-safe resolve, drain.mjs
      byte-identical inline copy, scan-routed idempotent flock'd write, per-round heartbeat keyed on
      stable state.runId). **Pass-3: 2 ledger drifts FIXED INLINE** — (1) id:1bbd `[x]` ROADMAP /
      `[ ]` TODO (lane-anchor fix shipped+merged → ROADMAP authoritative; ticked the TODO twin);
      (2) d5e0 count prose listed the shipped e149/7809/98f0/0994 [HARD — hands] batch as open —
      re-derived to 3 open executable-or-gated (401c [pool] / 3346 [meeting] / dba3 [decision-gate];
      de4e [meeting] DEFERRED). orphan-scan --cross-ledger now 0; roadmap-lint 0; gaming-scan
      `"$PWD" 8d8d40b` 0; todo-conformance 0; suite 135/0/0. 3 accepted-not-defect items (scan-routed
      inbox-done swallow + new-id fallback, pathspec-guard conservative-block). See
      `docs/meeting-notes/2026-06-30-1855-strong-model-audit.md`.
    - Run 68 (2026-06-26-0926): window = `5e1a216..HEAD` (HEAD `8d8d40b`), since Run 67 —
      **first NON-ledger window since Run 48** (`substantive_unaudited=true`): ~4091/-50 across
      35 files (14 scripts + 21 tests), three days of relay-engine work (id:5c00 quota pre-gate,
      c012 graceful-stop, d530 --priority/--exclude, 9973 HARD-pool demote-guard, 365b
      recurring-audit gate + circuit breaker, a707 human-gated INTENSIVE carve-out, 1b11 PID
      claim, 9221 orphan first-wins, c095 heading-as-item, a643 resource claim, 2147 atomic
      ledger commit, 71f2 workflow-template lint, 3441 todo-conformance, 678e scan-routed,
      2dea unpromoted-scan, relay-doctor). **Pass-1 code review CLEAN** (no correctness defects —
      verified commit-ledger scoped-add+escape-reject, todo-conformance stable-lineno --fix +
      duplicate-mint guard, gather substantive_unaudited fail-open + deterministic work_sig,
      relay-loop demote/breaker/pre-gate all demote-only+injected-exempt, the
      lint-workflow-templates single-pass lexer). **Pass-2 security CLEAN** (sed/jq/path/PID
      surfaces: 4-hex id validation before sed, realpath `../*|/*` reject, `jq -n --arg`,
      numeric-only `kill -0` with documented conservative PID-reuse caveat). **Pass-3: 1
      cross-ledger drift FIXED INLINE** — id:5c00 was `[x]` in ROADMAP but `[ ]` in TODO (work
      genuinely done+merged → ROADMAP authoritative); ticked the TODO twin, orphan-scan
      --cross-ledger now exit 0. todo-conversion-policies.md v1 + the 9973/365b/a707/000d guard
      lattice internally coherent. **Accepted (not a defect):** gaming-scan
      `ADDED_SKIP:test_relay_doctor_wiring.sh:60` = benign false-positive (the regex
      `report.only` substring tripped the heuristic on a real report-only assertion).
      roadmap-lint exit 0; todo-conformance exit 0; gaming-scan `"$PWD" 5e1a216` exit 0;
      suite 106/1/0 — the 1 failure is the KNOWN flaky `test_resource_claim_pid.sh` (id:ab5c),
      passed 3/3 in isolation → effectively 107 green. Mirror: TODO id:401c line refreshed
      Run 67→Run 68. See `docs/meeting-notes/2026-06-26-0926-strong-model-audit.md`.

- [ ] [INPUT — meeting] Sub-agent meeting simulation for main-ctx isolation <!-- id:3346 -->
  - **Why HARD**: architectural — moves the whole meeting transcript generation out
    of the main context into a sub-agent; touches broker contract, persona loading,
    decision routing, and note-writing; wrong cut loses the user's live view.
  - **Acceptance**: see TODO id:3346. **GATED — do not start**: gate is "opencode
    port validated (proves broker contract is stable) + ≥1 meeting with ctx > 200k".
    Listed here for visibility only; remains parked in TODO.md until the gate fires.

- [x] [ROUTINE] REVIEW_ME.md archiver — extend `archive-closed.sh` to a 3rd ledger <!-- id:85d3 -->
  - **What**: `relay/scripts/archive-closed.sh` today archives closed `- [x]` items from
    TODO.md + ROADMAP.md only. `REVIEW_ME.md` (the human review queue) accumulates closed
    `[x]` items with NO archiver (measured 2026-07-14: 15 closed / ~20 KB in this repo).
    Add REVIEW_ME.md as a third source, draining its closed top-level `- [x]` blocks into a
    `REVIEW_ME.archive.md` sibling.
  - **Spec / how it differs from TODO/ROADMAP**: REVIEW_ME items are NOT cross-ledger
    checkbox twins — a REVIEW_ME line often *references* an `id:` whose real ledger home is
    TODO/ROADMAP, so the twin-safe open-twin protection does NOT apply: archive a REVIEW_ME
    `[x]` block on its own state. Reuse the EXISTING block model (a top-level `- [x]` bullet
    plus every following line until the next top-level bullet or heading — this already
    captures column-0 prose + `>` blockquote correctly). NEVER move/prune the
    `# Human review queue` H1 header or its `<!-- budget: … -->` marker. Idempotent; a
    second run is a clean no-op. `--dry-run` reports the REVIEW_ME count alongside TODO/ROADMAP.
  - **Acceptance**: `tests/test_review_me_archive.sh` (roadmap:85d3) is green — a fixture
    REVIEW_ME.md with a closed `[x]` item (incl. a column-0 prose line + a `>` blockquote in
    its body) and an open `[ ]` item → the closed block (with its prose/blockquote) moves to
    `REVIEW_ME.archive.md`, the open item + the `# Human review queue` header + budget marker
    stay, second run is a no-op.
  - **Done-check**: tick this box, then `make test` fully green.
  - **Note**: the periodic-trigger WIRING (systemd timer / `/relay review` sub-step) is
    id:046a's job — this item only adds the REVIEW_ME *capability* to the archiver, which is
    independently testable. Reuses open TODO twin id:85d3 (single-id-two-views).

- [x] [ROUTINE] ROADMAP archiver: capture column-0 prose/blockquote + move emptied transient headers <!-- id:546b -->
  - **Bug 1 (prose/blockquote orphaning) — `relay/scripts/roadmap-archive.sh` only**: its
    `is_continuation()` treats a `[x]` item's body line as part of the block ONLY if the line
    is blank or indented, so a **column-0 prose paragraph or `>` blockquote** (common in
    ROADMAP item bodies) is left stranded in ROADMAP.md when the `- [x]` header moves to the
    archive — splitting the record across two files. Fix: adopt the SAME block boundary
    `archive-closed.sh` already uses (a block runs until the next top-level `- [` bullet OR
    any heading), so column-0 prose/blockquote is captured. `archive-closed.sh` does NOT have
    this bug — do not regress it.
  - **Bug 2 (emptied transient headers left behind) — BOTH `roadmap-archive.sh` AND
    `archive-closed.sh`**: after every item under a `##`/`###` grouping heading is archived,
    the emptied heading is left in ROADMAP.md as clutter. **DECIDED (user 2026-07-14): move an
    emptied transient grouping header INTO the archive together with its block** (preserving
    grouping context), NOT delete-in-place. **Protected — NEVER moved even when emptied**: the
    H1 title line (`# …`) and the standing buckets whose heading text is exactly one of
    `Items`, `Current`, `Done`, `Backlog` (case-insensitive, ignoring any trailing
    `<!-- … -->`). Only move a header that (a) is non-protected AND (b) had ≥1 item archived
    THIS run AND (c) now has zero remaining top-level items under it. A header that was ALREADY
    empty on arrival (author placeholder) is left untouched. This REVERSES the prior
    "headers structural — no pruning" stance (test T9), by explicit user directive.
  - **Acceptance**: `tests/test_roadmap_archive.sh` updated + green:
    (a) NEW case — a `[x]` item whose body has a column-0 prose line AND a `>` blockquote →
    both move to the archive, nothing stranded in ROADMAP.md;
    (b) new coverage in `tests/test_roadmap_archive_prose_headers.sh` — a non-protected
    transient grouping header (e.g. `## batch 2020-01-01`) whose only item is archived → the
    header moves to `ROADMAP.archive.md` and is gone from ROADMAP.md; a protected `## Items`
    header whose only item is archived → STAYS in ROADMAP.md; an already-empty header on
    arrival is left in place. NOTE: existing T9 in `tests/test_roadmap_archive.sh` asserts the
    protected `## Items` header stays — it REMAINS GREEN under the new behavior (Items is
    protected); only refresh its now-stale "no section pruning" rationale comment, do not delete it;
    (c) same emptied-header-move behavior verified for `archive-closed.sh` (extend
    `tests/test_archive_closed.sh` if present, else add coverage).
  - **Done-check**: tick this box, then `make test` fully green.
  - **Reuses** open TODO twin id:546b (single-id-two-views). Relates id:6b67 (built
    roadmap-archive.sh), id:046a (archive-closed consolidation).

## Capability-keyed lane taxonomy — slice A (meeting 2026-07-02-1924)

Slice A of the capability-keyed lane taxonomy + mechanical-run daemon
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`).
**Additive only** — introduces the `[MECHANICAL]` capability tier, its recipe/permit/probe
substrate, and the check-and-defer resource arbitration, WITHOUT renaming any existing lane
(the `[HARD — *]`→new-vocab rename is slice B, GATED below). Single-id-two-views (D2): every
id reuses its open TODO.md twin under the `[UMBRELLA]`.

## Capability-keyed lane taxonomy — wave 2a (MECHANICAL end-to-end)

Wave 2a makes the `[MECHANICAL]` tag END-TO-END: slice A shipped the CONSUMER half only
(the classifier RECOGNIZES `[MECHANICAL]`→the pool-inert `mechanical` verdict), but no
relay layer PRODUCES the tag and nothing RUNS it. Source of truth: the
`## Amendment 2026-07-02 (post-build — the `[MECHANICAL]` producer gap)` section of
`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`. These
three items (single-id-two-views D2 — each reuses its open TODO.md twin) are UN-GATED —
their deps (A1 id:7616, A2 id:64d3, A4 id:e407, A5 id:68dc) are all landed `[x]`. Uses the
CURRENT lane vocabulary (`[ROUTINE]`/`[HARD — pool]`) — the two-axis rename is wave 2b
(B1/B2, GATED below), NOT here.

## Capability-keyed lane taxonomy — wave 2b (lane-vocabulary RENAME)

Wave 2b executes the `[HARD — <suffix>]` → two-axis-vocabulary RENAME ratified in the meeting
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`, decisions
1+2). **This is the meeting's flagged BLAST-RADIUS step** — the lane vocabulary was hardened
four days ago across ~30 lane-asserting tests + the crash-prone `relay-loop.js` engine, so the
rename is deliberately staged **additive-then-flip** with a deterministic converter and a
DUAL-VOCABULARY lint window (both old and new accepted ERROR-free for one window). NEVER a
flag-day (Riku). Dep A1 (id:7616, `[MECHANICAL]` tag) is landed `[x]`, so B1 is now UN-GATED
and dispatchable; B2 stays gated on B1 (below). Single-id-two-views (D2): both ids reuse their
open TODO.md twin.

**Target taxonomy (decision 1).** Two orthogonal axes — **capability**: `[ROUTINE]` (executor
LLM) · `[HARD]` (strong LLM) · `[INPUT — {meeting,decision,access}]` (human ± LLM; sub-type =
effort) · `[MECHANICAL]` (compute only) — × **resource** (orthogonal): `[INTENSIVE — <res>]`.
The MAPPING: the THREE UNAMBIGUOUS 1:1 renames the converter AUTO-APPLIES — `[HARD — pool]`→`[HARD]`,
`[HARD — meeting]`→`[INPUT — meeting]`, `[HARD — decision gate]`→`[INPUT — decision]`. `[HARD — hands]`
is DELIBERATELY NOT auto-converted: "hardware/sudo/secret/on-device/rehearsal" fragments across FOUR
destinations — `[MECHANICAL]` (a daemon can run it) · `[INPUT — access]` (human provides a
credential/key/physical access) · `[INPUT — decision]` (human must ratify, e.g. it-infra fd30
post-gate decisions) · `[INPUT — meeting]` (human+LLM design judgment, e.g. a rehearsal whose
outcome needs interpretation) — so the converter FLAGS every `[HARD — hands]` item for per-item
human judgment (those four candidates) and converts it to NONE of them (no default). Aligns with M3
(id:3ef7) + the conformance-sweep detector-surfaces/human-decides rule. `[ROUTINE]` / `[MECHANICAL]`
/ `[INTENSIVE — <res>]` are UNCHANGED. **SCOPE (owner-locked):** this wave
migrates THIS repo's contract + lane-readers + tests + THIS repo's own ROADMAP/TODO item tags
only. Cross-repo item re-tagging in OTHER repos is a SEPARATE gated migration — the dual-vocab
window is exactly what lets those migrate later.

### GATED — B2 migration (DEP: 4f02, NOT dispatchable until B1 lands)

Parked under a GATED heading (roadmap-lint-exempt, non-dispatchable) until B1 (id:4f02) ships
the converter + dual-vocab window. This is a LARGE migration — its acceptance DECOMPOSES into
three separable sub-checks (B2a readers+references / B2b relay-loop.js / B2c this-repo
ledgers+tests) that MAY be dispatched as separate executors (see the handoff report's split
recommendation). Do NOT dispatch until 4f02 is ticked.

- [ ] [INPUT — decision] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) — **human 2026-07-11 (relay human): keep OPEN, gate re-confirmed.** Blocker is the cross-repo re-tag, NOT tooling (lane-convert id:4b37 shipped): 27 own repos + project_manager scan.py still emit old vocab (71 live `[HARD — pool|meeting|hands|decision gate]` tags), so flipping old→ERROR now would break them. This is `[INPUT — decision]` = a deliberate coordinated migration the human triggers (each repo's next `/relay handoff` runs `lane-convert`, then this closes), never autonomous pool work. <!-- id:7df1 -->
  - **Why**: B2 (id:8111) landed reader+reference+engine DUAL-ACCEPT — old and new vocab both
    ERROR-free. The window must stay OPEN until every OTHER surface is on the new vocab, then close
    in one deliberate flip. This is the tail the meeting deliberately deferred.
  - **Acceptance**:
    1. `lane-convert.sh --in-place` on THIS repo's `ROADMAP.md` + `TODO.md` (own tags only; the
       converter auto-renames pool/meeting/decision-gate and FLAGS each `[HARD — hands]` — resolve
       those per-item into one of the four candidates by M3/human judgment, never a blanket default).
    2. Migrate the ~30 lane-asserting `tests/test_*.sh` + `test_hard_lane_buckets.sh` marker-set
       cross-check to the new vocab.
    3. FINAL step — CLOSE the window: `roadmap-lint.sh` + `gather-human-backlog.sh` make an OLD-vocab
       lane a hard ERROR (drop the dual-accept branches; delete the "window OPEN" prose in
       hard-lanes.md/human.md/review.md/handoff.md/conventions.md).
  - **Done-check**: `make test` fully green with every lane-asserting test on the new vocab AND an
    old-vocab `[HARD — pool]` fixture now LINT-REJECTED (a new red-then-green window-closed test).
  - **Blocked on**: 3ef7 (M3 per-item `[HARD — hands]` re-lane must resolve this repo's hands items
    first) AND the cross-repo re-tag (other own repos + `project_manager`'s `scan.py`, id:b466, must
    speak new vocab — the window can't close while any consumer is old-vocab-only). Closing early
    would break every repo still on `[HARD — *]`.
  - **d259 RATIFIED 2026-07-06 (meeting `docs/meeting-notes/2026-07-06-0959-machine-tag-format-endgame.md`):** endgame = (C) tag-first bracketed position (B rejected). The reorder tool (`lane-convert --reorder` isolated mode) + tag-first WARN lint are built AHEAD, ungated, as **id:4b37** — NOT authored inside this item. So this item's acceptance step 1 becomes: run the ALREADY-BUILT `lane-convert --in-place --reorder` (renames + reorders in one pass), and step 3's FINAL flip also flips 4b37's tag-first lint WARN→ERROR alongside old-vocab→ERROR (one window-close). Delete the 7 anchoring reimplementations in the step-2 reader migration.

## lane-anchor hotfix (relay handoff 2026-07-03)

## recipe explicit-success-marker doctrine (relay handoff 2026-07-03)

## case-c bare-only lane count (relay handoff 2026-07-03, owner-signed-off)

## mechanical-lane representability fix (relay HARD, user-injected id:baf1, 2026-07-10)

## Relay orphan-worktree reconcile (meeting 2026-06-16-0938, id:a4e9)

Decomposition of the orphan-reconcile design. **Sequence: D1 → D2/D3** (D2's reconcile
mode and D3's binding both operate on the `relay/orphan/*` namespace D1 creates). D4
(id:a692, note-only forward-flag) and D6 (id:122f, fsck ADVISORY follow-on, gated "ships
after D1–D3") stay in TODO.md — not executor work yet.

## Model probe (id:dba3 deliverable)

Sub-items of the `[HARD — strong model]` umbrella id:dba3. Design fully settled in
`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md` (D2/D5/D6) and
`docs/meeting-notes/2026-06-17-0905-model-probe-tos-and-band.md` (D1/D2). Promoted to
ROADMAP 2026-06-17 so executors can work them; id:dba3 and id:23e9 (seed) stay `[HARD]`.
