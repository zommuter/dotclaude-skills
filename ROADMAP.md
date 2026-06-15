# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

<!-- DESIGN CLUSTER: "safe concurrent + resource-aware relay dispatch" — KEYSTONE id:8ac5
     (claim/assignment primitive) unifies id:7b7a (lease = enforcement), id:8d52 (intensive =
     resource claim), id:d748 (meeting respects claims). One dispatch gate + one lock-with-TTL
     machinery; decide together (one /meeting). Origin: 2026-06-15 chat. -->

- [ ] Task-claim primitive — relay sessions "claim" roadmap items (PM-board style) [HARD — decision gate] <!-- id:8ac5 -->
  - **Context**: 2026-06-15 user idea — like a PM tool assigns an issue to an individual, a relay
    SESSION claims a roadmap item (or a resource) so others see it's owned and don't double-work it.
    This is the UNIFYING primitive the cluster was circling: id:7b7a's per-repo lease becomes the
    *enforcement* of a claim (merge-collision safety), id:8d52's `[INTENSIVE]` is a claim on a
    *resource* (`local-llm`) not an item, and id:d748's "holdable meeting" is `/meeting` respecting
    (and able to take) claims. The human (/relay human), the pool, executor sessions, and /meeting
    all read/write the SAME claim records.
  - **Maps onto single-id-two-views (D2)**: the `<!-- id:XXXX -->` token is the join key. Today
    TODO = "why" (design) and ROADMAP = "now" (queue). A claim adds a THIRD view — "who/owned-by" —
    keyed by the same id ("single-id-three-views"). ROADMAP stays the source of truth for WHAT; the
    claim registry is the source of truth for WHO/NOW.
  - **Open design questions (for the cluster /meeting)**: (1) WHERE claims live — in the ledger item
    itself (visible, git-tracked, but write-contended + churny) vs a dedicated flock'd registry
    (`~/.config/fables-turn/claims.toml` or per-id files; fast, but a second surface to reconcile) vs
    relay.toml. Leaning: dedicated registry + a read-only VIEW surfaced in RELAY_STATUS.md (or a
    `/relay board`) for PM-board visibility WITHOUT write-contending the ledger. (2) Claim granularity
    — item-level vs repo-level: item-level gives more parallelism BUT two items in one repo still merge
    into ONE main checkout, so a claim does NOT remove the need for per-repo integration serialization
    (id:7b7a) or disjoint-paths (existing guardrail). Claim = assignment/visibility; lease = merge
    safety — complementary layers, not a replacement. (3) Claim lifecycle — claim → heartbeat → release/
    expire (TTL), so an OOM-killed session's stale claim is reclaimable (memory `oom-local-model-session-kills`).
  - **Acceptance**: a claim record `{id, repo, runId/session, mode, claimed_at, heartbeat, status}`
    written via a flock'd helper; discovery/dispatch skips live-claimed ids and reclaims expired ones;
    claims surfaced read-only in RELAY_STATUS.md; covered by the bash suite. Co-decide with id:7b7a/8d52/d748.

- [ ] Cross-session relay dispatch safety: per-repo lease + single-writer shared state [HARD — decision gate] <!-- id:7b7a -->
  - **Context**: 2026-06-15 — "what happens if I run a 2nd `/relay` session while the pool is
    live?" Today: NOTHING prevents same-repo overlap. relay-loop.js has no run-lock/lease/flock;
    discovery is not worktree-aware (won't skip a repo another run already has a child in);
    `relay.toml` + `RELAY_STATUS.md` are written by a plain agent with no flock (whole-file
    clobber / dropped per-repo fields). Worktree DIRS are safe (run-id keyed) and the PUSH is
    flock-guarded (`git-lock-push.sh`), but two children can `merge --no-ff` into one main
    checkout (status→merge→tag→push not atomic across sessions). Same family as TODO id:3558
    (independent-session flock'd merge-to-canonical) + memories `parallel-session-state-coordination`,
    `d5-worktree-per-session`, `oom-local-model-session-kills` (held worktree = in-flight signal).
  - **Why decision-gate**: changes the D5/D6 invariant ("one integration per remote", see id:bc9d)
    and the cross-session contract; lock TTL/heartbeat policy and who-yields trade-offs are
    non-obvious and hard to reverse. Decide in the cluster /meeting.
  - **Acceptance (sequence cheapest-first)**: (1) worktree-aware discovery — skip any repo with a
    FRESH foreign-runId worktree under `~/.cache/fables-turn/worktrees/<repo>/` (near-free, kills
    the worst case); (2) flock'd single-writer for `relay.toml` (field-scoped read-modify-write)
    and `RELAY_STATUS.md` (per-runId section or merge, not clobber) — reuse the append.sh/md-merge.py
    fd8/9 pattern; (3) formal per-repo flock'd lease (`~/.cache/fables-turn/leases/<repo>.lock`,
    `{runId,pid,mode,heartbeat}` + TTL so an OOM-killed session's lease expires); (4) `/relay executor`
    acquires the repo lease at start (refuse/warn if a live pool holds it) — ideally worktree-isolated
    per D5.6/id:3558. Each step independently testable in the bash suite.
  - **Reuse**: link/co-resolve TODO id:3558 (single-id-two-views — same token spans both ledgers).

- [ ] `[INTENSIVE — <resource>]` tag: gate local-LLM/heavy work behind explicit permission [HARD — decision gate] <!-- id:8d52 -->
  - **Context**: 2026-06-15 user request. Local-LLM tasks (ai-codebench benchmarks, zkm embedding
    index) hammer GPU/RAM — memory `oom-local-model-session-kills`: Gemma 26B killed all 6 sessions;
    ~57s cold TTFT (cf id:642f). Run-1 already handed these back ad hoc ("hardware-gated for an
    unattended relay turn… never an unattended relay child" — zelegator id:462c, linguistic-unversals
    id:3071). This makes it a first-class, deterministic tag instead of per-child judgment.
  - **Shape**: a resource modifier ORTHOGONAL to the verdict axis (NOT a replacement for
    `[ROUTINE]`/`[HARD]`), two-part like the HARD tags so the gate knows which resource:
    `[ROUTINE] [INTENSIVE — local-llm]`, `[HARD — strong model] [INTENSIVE — local-llm]`.
  - **Acceptance**: (1) discovery parses the modifier; an `[INTENSIVE]` unit is NEVER auto-dispatched
    by the default unattended pool — surfaced in RELAY_STATUS "Queued — needs explicit permission"
    (extends `feedback-relay-unattended-default`: never run resource-doomed work unasked). (2) Global
    resource semaphore `~/.cache/fables-turn/resources/<resource>.lock` — at most one local-llm task
    at a time; conservative default = it RUNS ALONE (pool pauses new dispatch / forces POOL_WIDTH=1
    while held) — this is the actual OOM fix. (3) Opt-in to run them: `/relay --allow-intensive`
    (flag) and an **AFK mode** `/relay --afk [duration]` ("I'm away, do something useful" — drains
    light work, then chews intensive items one-at-a-time within a time/quota budget, reports back).
    (4) Tagging: strong children tag per criteria in `conventions.md` (cite OOM + TTFT), PLUS a coarse
    per-repo default `[repos.ai-codebench] intensive = true` / `[repos.zkm] intensive = true` as a
    safety net; item-level tags override.
  - **Why decision-gate**: run-alone vs reduced-width, budget semantics, and resource taxonomy are
    judgment calls; pairs with the id:7b7a lock machinery. Decide in the cluster /meeting.

- [ ] `/meeting` ↔ relay-loop mutual hold (holdable meeting while a pool is live) [HARD — decision gate] <!-- id:d748 -->
  - **Context**: 2026-06-15 user request. `/meeting` writes the shared ledgers (TODO/ROADMAP/REVIEW_ME)
    in the MAIN checkout while the relay pool merges worktree branches into the same files (D2
    single-id-two-views; CLAUDE.md already notes md-merge.py + `orphan-scan.sh --cross-ledger` for
    residual drift). A meeting started mid-pool can collide at integration. Need a mutual-hold so the
    two actors don't write the shared ledgers concurrently.
  - **Acceptance (design)**: decide the yield direction — (a) `/meeting` detects a live pool (lease/
    runlock from id:7b7a) and HOLDS/queues its ledger writes until a safe point, or (b) the pool
    yields a short window to an interactive meeting, or (c) both coordinate via the same per-repo lease
    keyed on dotclaude-skills. Likely reuses id:7b7a's lease + single-writer helper rather than a
    separate mechanism. Must keep meeting's read/think phase unblocked (only the WRITE-BACK holds).
  - **Why decision-gate / reuse**: this is the id:7b7a lease applied to the `/meeting` actor — co-decide
    in the cluster /meeting; don't build a parallel lock.

- [x] Relay integrator bottleneck — per-repo serialization, cross-repo concurrency (done 2026-06-15, reviewer) <!-- id:bc9d -->
  - **Context**: 2026-06-15 — investigating "the pool only runs ~1-wide". Work agents
    (review/execute/hard) DO run concurrently (harness cap `min(16, cores-2)`; I/O-bound API
    calls, no mutual block). The apparent serialism was the **single global integrator**
    (`integrationChain` promise chain, relay-loop.js): every repo's integration ran one-at-a-time,
    and each is a full Sonnet agent running 4 deterministic commands (merge --no-ff → ckpt-tag.sh
    → git-lock-push.sh → worktree prune), ~1–2 min each. Checkpoints are stamped at integration,
    so tags landed ~1–2 min apart no matter how wide dispatch was — that even spacing is what
    *looked* like a 1-wide pool. (The per-unit quota-agent throttle in 82a2dda was a separate,
    minor win, NOT this.)
  - **Fix shipped**: replaced the single `integrationChain` with a per-repo chain map
    (`integrationChains: Map<repo, tailPromise>`, `enqueueIntegration(repo, fn)`). Same-repo
    integrations still serialize (preserving review→execute re-chain ordering into one main
    checkout); DISTINCT repos integrate concurrently — distinct remotes don't conflict, and
    git-lock-push.sh still flocks per-repo for the residual same-remote case. This restates the
    D5/D6 invariant from "one concurrent integration per POOL" to "one per REMOTE", which is the
    only thing safety actually requires. Checkpoint throughput now scales with dispatch width.
  - **Tests**: `tests/test_relay_integrator_per_repo.sh` (`# roadmap:bc9d`) — no global
    integrationChain; enqueueIntegration keyed by repo; per-repo map get/set; drain awaits all
    chains; integration still not wrapped in parallel(). `test_relay_loop_structure.sh` (3)
    updated to the per-repo assertion.
  - **Follow-up (deferred, not blocking)**: integration agent could be Haiku and/or BATCH several
    repos per call to further cut the ~1–2 min/repo agent overhead — left for a later pass; the
    per-repo concurrency above is the primary throughput lever.

- [ ] Contract tests for relay install-completeness + quota-stop invocation [ROUTINE] <!-- id:5f09 -->
  - **Context**: On 2026-06-15 the default `/relay` autonomous pool was non-functional and
    the full suite was green. Two contract bugs shipped undetected: (1) the Makefile
    `relay_FILES`/`_EXEC`/`_ALLOW` lists omitted `scripts/quota-stop.sh` and
    `scripts/relay-loop.js`, so `make install` never symlinked the Workflow engine or the
    quota helper agents invoke by installed path; (2) `relay-loop.js`'s `quotaGate()` called
    `quota-stop.sh --tier T <agents> 0` with bare positionals, but the script only accepts
    `--tier/--agents/--wall` and exits 2 on anything else — tripping the fail-safe STOP on
    every gate check. Fixed in 5481502; tests did not catch either.
  - **Acceptance**: (1) a test asserts every `relay/scripts/*` file appears in the Makefile's
    `relay_FILES` (and every executable `.sh` in `relay_EXEC`/`relay_ALLOW`), so a new helper
    can't ship un-symlinked; (2) a test asserts the `quota-stop.sh` invocation string embedded
    in `relay-loop.js` uses only flags `quota-stop.sh` actually parses (`--tier/--agents/--wall`)
    — ideally by extracting the command and dry-running it, else by static flag-set match.
  - **Tests**: extend `tests/test_relay_loop_structure.sh` (quota-stop invocation) and add a
    Makefile-manifest check (new `tests/test_relay_install_manifest.sh` or fold into an existing
    install test); header `# roadmap:5f09`.
  - **Done-check**: tick this box, then full `make test` green.

- [x] De-fable checkpoint tags + durable model-tracked Fable-bonus-recheck queue [HARD — strong model] (done 2026-06-15, reviewer; merges id:e030) <!-- id:96a8 -->
  - **Acceptance**: `relay/scripts/ckpt-tag.sh` emits `relay-ckpt-YYYYMMDD-HHMM` annotated
    tags (not `fable-ckpt-*`); the RELAY_LOG.md append + the model+role annotation label are
    unchanged; existing `fable-ckpt-*` tags are never rewritten. `relay/scripts/relay-loop.js`
    finds the latest checkpoint / commit range / standin by matching BOTH prefixes
    (`git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`), so a repo whose `last_ckpt`
    is still `fable-ckpt-*` keeps working across the boundary. `integrate()` writes a durable,
    model-tracked Fable-bonus-recheck queue into relay.toml on a STRONG (review/handoff/hard)
    checkpoint — `last_strong_ckpt`, `strong_model`, `fable_rechecked` — which an executor
    (sonnet) checkpoint never clears (masking fix, id:e030); the id:9821 elevation consults
    `strongRecheckPending` (un-rechecked strong ckpt) as an OPTIONAL, non-gating recheck
    candidate. The three relay.toml fields are documented in `relay/SKILL.md` (State) and
    `relay/references/conventions.md`.
  - **Tests**: `tests/test_relay_tag_scheme.sh` (`# roadmap:96a8`) — ckpt-tag.sh emits a
    `relay-ckpt-*` tag (hermetic run), label/RELAY_LOG unchanged; relay-loop.js dual-prefix
    matching + the three relay.toml fields + the strongRecheckPending consume wiring; docs
    mention the fields.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_tag_scheme.sh` then full `make test`.

- [x] `/fables-turn human` mode — cross-repo human-backlog triage (the human as 3rd actor) [ROUTINE] (done 2026-06-15, reviewer) <!-- id:2892 -->
  - **Acceptance**: `fables-turn/SKILL.md` documents a `human` mode — the invocation
    block carries `/fables-turn human [repo-list | --all]`, a `## Human mode` section
    describes the 3-tier triage and points at `references/human.md`, frames Opus as apex,
    and notes it generalizes the planned `review_me`. `references/human.md` exists and
    specifies the 3 tiers (AUTO-ANSWERABLE / BATCH-DECIDABLE / CHEWY), the
    `@manual`-never-auto-tick rule, and the tier-C → `/meeting --cross` routing.
    `scripts/gather-human-backlog.sh` is a read-only helper (`set -euo pipefail`, optional
    repo args, hermetic via `SRC_DIR`/`RELAY_TOML` overrides) that scans relay.toml `own`
    repos' `REVIEW_ME.md` for open `- [ ]` boxes and emits a TSV
    (`repo path kind box_summary`, `kind=review_me|manual`), flagging `@manual` boxes
    (REVIEW_ME and ROADMAP) as `kind=manual`; closed `- [x]` boxes are never emitted. The
    helper joins the Makefile `fables-turn` FILES/EXEC/ALLOW.
  - **Tests**: `tests/test_fables_human.sh` (`# roadmap:2892`) — SKILL.md documents the
    mode + invocation; references/human.md exists and specifies the 3 tiers +
    @manual-never-auto-tick + tier-C→/meeting --cross; gather-human-backlog.sh emits the
    TSV and flags @manual (hermetic fixture).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_human.sh` then full `make test`
    after ticking.
  - **Context**: TODO id:72cc — codifies a hand-run procedure. Interactive strong-turn
    PROCEDURE (uses AskUserQuestion, so NOT a Workflow); mirrors handoff.md/review.md as
    reference-doc procedures. Per-repo commit in the main checkout (the /meeting REVIEW_ME
    write-back path, id:15d5), not a worktree merge. Opus is apex; an auto-answer is a
    CLAIM the next review re-checks (anti-gaming, downgrade a→b when unsure).

- [x] HARD-execute verdict + tested Fable-probe cache helper for the autonomous pool [HARD — strong model] (done 2026-06-15, reviewer) <!-- id:da26 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (a new verdict class
    with an apex-only gate that must never leak HARD work onto the Sonnet execute tier),
    and the steady-state scheduling invariant. Wrong gating dispatches a doomed strong
    unit on Fable, or — worse — runs unbounded HARD work on Sonnet.
  - **Acceptance**: relay-loop.js gains a `hard` verdict (in DISCOVER_SCHEMA's enum +
    an `openHard` count). The classifier emits `hard` when a repo has NO unaudited
    commits, NO open `[ROUTINE]`, but ≥1 open `[HARD` item (precedence
    review > execute > hard > handoff > idle). `PRIORITY = { execute:0, review:1, hard:2,
    handoff:3 }`. A `hard` unit is DISPATCHED only when `STRONG_MODEL === 'claude-opus-4-8'`
    (apex); on Fable / the `-d` defer path it is left for Fable handoff-C5/review-step6 and
    surfaced in RELAY_STATUS Queued. NEVER on the Sonnet execute tier. The hard child works
    ONE bounded `[HARD]` item under handoff-C5 "only-if-small-enough" discipline, ticks the
    box only if genuinely green, and returns the standard report. Integration uses a
    `strong-execute (<model>, fable-standin, relay-loop)` checkpoint label. `scripts/probe-fable.sh`
    manages the front door's 2 h Fable-probe cache (`check` → fresh-available/fresh-unavailable/
    stale/absent; `set <true|false> [ts]`), hermetically testable (PROBE_CACHE override, no model).
    SKILL.md documents the `hard` verdict + references the helper in step 0.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9` + da26 §18 checks:
    enum, PRIORITY order, opus-only gate, Sonnet-never-HARD, strong-execute label, refDoc),
    `tests/test_probe_fable.sh` (`# roadmap:da26`) — fresh-available/unavailable, stale (>2h),
    absent, malformed, set-persistence, bad-arg.
  - **Done-check**: `tests/run-tests.sh tests/test_probe_fable.sh tests/test_relay_loop_structure.sh`
    then full `make test` after ticking.
  - **Context**: TODO id:da26 (c) — ratified 2026-06-15 (user): accept Opus doing `[HARD]`
    work while Fable is out. Built on the Opus-apex pivot (f64c28b). Reuses handoff.md C5,
    `worktreePathFor`/`branchFor`, and the existing `standInSuffix` logic.

- [x] Add a batched `say` subcommand to broker-curl.sh and route broker-mode.md through it [ROUTINE] <!-- id:3b02 -->
  - **Acceptance**: `broker-curl.sh <port> <session> say` reads plain-text lines from
    stdin and POSTs **one `/event` per line** (per-line painting in the renderer must
    be preserved — never collapse lines into a single event). A `--opener` first-line
    flag marks the first stdin line with `"kind":"opener"` for TTFL logging. Text with
    apostrophes/quotes/backslashes survives intact (JSON built with `jq -n --arg`
    internally). stdout stays quiet on success (HTTP responses discarded); curl/HTTP
    failures still reach stderr and exit non-zero. Empty stdin lines are skipped.
    `meeting/broker-mode.md` §Discussion is updated so the per-persona-line example
    uses ONE `say` call per agenda item instead of one Bash call per line (this is
    the actual ctx win: ~25–35 tool-call records/meeting → ≤10). Existing endpoints
    (`status events event question await response`) are unchanged.
  - **Tests**: `tests/test_broker_say.sh` (`# roadmap:3b02`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_broker_say.sh` then full `make test` after ticking
  - **Context**: `meeting/broker-curl.sh` (case-arm dispatch; keep the existing
    brace-default and quoting gotchas documented in CLAUDE.md §Gotchas),
    `meeting/broker-mode.md` (only the Discussion example block needs rewording —
    keep the "never batch into one event" semantics explicit). Mock broker fixture:
    `tests/fixtures/mock-broker.py`. TODO id:3b02 is the origin item — option (b)
    batching was chosen; do not also implement (a)/(c).

- [x] Add the Fable-class caveat to the γ-branch reference table in broker-mode.md [ROUTINE] <!-- id:44ba -->
  - **Acceptance**: in `meeting/broker-mode.md`, the `## γ-branch reference` section
    contains a visible Fable note attached to the table — either a `> **Fable note:**`
    blockquote directly under the table or a footnote marker on the three
    `AskUserQuestion` fallback rows (`MEETING_LIVE=0`, `subscribers=0`,
    `Broker unavailable`). The note must say that on Fable-class harnesses
    `AskUserQuestion` is replaced by inline-prose numbered prompts and point to
    `format.md §Interactive mode §Harness-class gate`. The `subscribers>0` row needs
    no caveat (broker routing makes the rendering limit irrelevant). Table content
    itself stays otherwise unchanged.
  - **Tests**: `tests/test_fable_caveat.sh` (`# roadmap:44ba`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_fable_caveat.sh` then full `make test` after ticking
  - **Context**: TODO.md "broker-mode.md γ-branch table missing Fable caveat" item;
    `docs/meeting-notes/2026-06-12-0749-fable-harness-interactive-mode-fix.md`.
    Prose cross-refs already exist elsewhere in the file — the fix is specifically
    AT the table, which is what gets skimmed.

- [x] Cover fables-turn and projects skills in the Makefile installer [ROUTINE] <!-- id:1ec1 -->
  - **Acceptance**: `make install-fables-turn` and `make install-projects` exist and
    symlink the skills into `$(DEST_DIR)` (override-able, default `~/.claude/skills`).
    fables-turn installs `SKILL.md`, `references/{handoff,review,conventions,templates}.md`,
    and `scripts/{discover-repos,ckpt-tag}.sh` (scripts chmod +x), creating the
    nested `references/` and `scripts/` directories under the destination —
    extend the `SKILL_RULES` template with a `mkdir -p` of each file's dirname
    rather than flattening paths. projects installs `SKILL.md` only. Both skills are
    in `SKILLS` so `make install`, `make status`, `make uninstall` cover them, and
    `make help` lists them. fables-turn's two scripts join the allowlist generation
    (`fables-turn_ALLOW`). Neither skill has LOCAL files. `make status-fables-turn`
    reports nested files correctly.
  - **Tests**: `tests/test_makefile_skills.sh` (`# roadmap:1ec1`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_makefile_skills.sh` then full `make test` after ticking
  - **Context**: `Makefile` (per-skill variable convention at top + `SKILL_RULES`
    define). The skill was hand-symlinked on 2026-06-12; the Makefile is the
    canonical installer and must not lag. Test with `DEST_DIR=$(mktemp -d)` —
    never the real `~/.claude`.

- [x] Add tools/ctx-budget.sh — per-skill SKILL.md token-budget audit [ROUTINE] <!-- id:32d6 -->
  - **Acceptance**: `tools/ctx-budget.sh [root]` (default: git toplevel) scans every
    `*/SKILL.md` in the repo and prints one TSV line per file:
    `<relpath>\t<est_tokens>\t<gate>\t<OK|WARN>`, where `est_tokens = bytes/4`
    (the repo's established chars/4 convention, same as cost-of.sh SIZE_KB/4) and
    `gate` is 2000 tokens by default, override via `CTX_BUDGET_GATE` env var.
    Files over gate get `WARN`; exit code is 0 either way (advisory logger, not a
    blocker — "observe before preventing"). A `--summary` flag prints only the WARN
    lines plus a final `total: N files, M over gate` line. Executable, `set -euo
    pipefail`, no dependencies beyond coreutils.
  - **Tests**: `tests/test_ctx_budget.sh` (`# roadmap:32d6`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_ctx_budget.sh` then full `make test` after ticking
  - **Context**: TODO.md "git-diary-workflow SKILL.md size audit" item and the
    global "per-prompt ctx multipliers" heuristic — mandatory-after-every-prompt
    skills multiply their size by prompt count, so their SKILL.md size needs a
    cheap recurring check. ARCHITECTURE.md §9 for the advisory-only philosophy.

- [x] Show the session token total in the statusline context segment [ROUTINE] <!-- id:2520 -->
  - **Acceptance**: `statusline/statusline-command.sh` line 1 displays the context
    segment as `<pct>%(<tokens>)` where `<tokens>` is `TOTAL_TOKENS` (input+output,
    already computed) humanized: `<1000` → as-is, `≥1000` → `N.Nk` with one decimal
    truncated to `Nk` when ≥10k (e.g. `115000` → `115k`, `9500` → `9.5k`, `730` →
    `730`). Same color as the existing context percentage. No new network calls, no
    layout change elsewhere on the line. Script must still produce output when run
    with `HOME` pointing at an empty temp dir (no credentials → fetch skipped).
  - **Tests**: `tests/test_statusline_tokens.sh` (`# roadmap:2520`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_statusline_tokens.sh` then full `make test` after ticking
  - **Context**: `statusline/statusline-command.sh` (CONTEXT_* block around line
    251–258; final echo at the bottom). Fixture stdin JSON:
    `tests/fixtures/statusline-input.json`. Origin: TODO.md "Statusbar: other
    cost-saving indicators" (this implements the first candidate; cache-read ratio
    is out of scope — it needs transcript parsing).

- [x] Extend the id-token ecosystem to ROADMAP.md (scan-ids, orphan-scan union, classify relay line) [HARD — strong model] <!-- id:de9c -->
  - **Why HARD**: cross-script invariant — three scripts must agree on what counts
    as the id-bearing ledger, and the wrong call silently reintroduces token
    collisions or orphan-scan false positives; also requires deciding how the
    classifier should treat relay-managed lines (judgment, not mechanics).
  - **Acceptance**: (1) `append.sh` gains a `scan-ids [<root>]` subcommand printing
    every existing `id:XXXX` token (one per line, sorted unique) from the ledger
    file set, which now includes `ROADMAP.md`; `new-id`/`new-ids` use the same scan
    so freshly minted tokens can never collide with roadmap ids. (2)
    `orphan-scan.sh` includes `ROADMAP.md` in the TODO-union read (forward and
    reverse modes): a meeting-note item whose token lives in ROADMAP.md is not an
    orphan. (3) `classify.sh` emits class `RELAY` for the TODO.md relay mirror line
    (`Relay: N open ROADMAP items`) so `/meeting` no-arg dispatch never proposes a
    meeting on it. Resolves TODO id:62f5 part (a).
  - **Tests**: `tests/test_id_ecosystem.sh` (`# roadmap:de9c`)
  - **Done-check**: `tests/run-tests.sh tests/test_id_ecosystem.sh`
  - **Context**: executed by the reviewer in this handoff turn (C5). See
    ARCHITECTURE.md §3.

- [x] Create the `fables-executor` skill: versioned SKILL.md + Makefile registration + test [ROUTINE] <!-- id:7691 -->
  - **Acceptance**: `fables-executor/SKILL.md` exists with `name`/`description` frontmatter
    and a `## Executor contract <!-- fables-executor contract v1 -->` heading carrying the
    5 rules verbatim + ROADMAP item format recap + RELAY_LOG conventions + Maintenance
    bump-rule note. `fables-executor` is in `Makefile` `SKILLS` with `_FILES := SKILL.md`
    and empty `_EXEC/_ALLOW/_LOCAL`. `dotclaude-skills/CLAUDE.md` `## Relay contract`
    section is the thin pointer (`<!-- fables-executor contract v1 -->`). Version-consistency
    grep: the `vN` in `fables-executor/SKILL.md` equals the `vN` in `CLAUDE.md`'s pointer.
    `fables-turn/references/conventions.md` no longer contains the fenced 5-rule block.
    `handoff.md` C1 and `review.md` step 4 reference the pointer, not the block.
  - **Tests**: `tests/test_fables_executor.sh` (`# roadmap:7691`)
  - **Done-check**: `tests/run-tests.sh tests/test_fables_executor.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-1404-fables-executor-skill.md`;
    TODO id:fba6. The skill body + all reference-file edits may already exist from the
    review turn that wrote this item — verify before re-implementing.

- [ ] Strong-model audit: code review, security, and design coherence [HARD — strong model] <!-- id:401c -->
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

- [x] Autonomous relay front-door: `/fables-turn` no-keyword default mode [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:230f -->
  - **Why HARD**: redesigns the fables-turn SKILL.md trigger surface and dispatch logic; requires
    judgment on the unattended-safe confirmation contract and how the skill hands off to the Workflow engine;
    wrong front-door behaviour silently skips repos or blocks the unattended run.
  - **Acceptance**: invoking `/fables-turn` with no keyword (no `handoff`/`review` argument) starts the
    autonomous pool loop. Non-interactive by default: operates only on relay.toml `classification=own`
    confirmed repos; surfaces (never asks about) new/dirty/needs_review repos in `RELAY_STATUS.md`.
    `--interactive` flag re-enables `AskUserQuestion` confirmations. Front door invokes the
    `relay-loop.js` Workflow script (id:83c9) and exits after the Workflow completes, printing the
    RELAY_STATUS.md path and HANDBACK count. Existing `handoff` and `review` keyword modes are
    unchanged and fully compatible. SKILL.md updated to document the new default mode and the knobs
    (`STRONG_TIER`, `--interactive`, quota-threshold env var).
  - **Tests**: `tests/test_fables_front_door.sh` (`# roadmap:230f`) — verify (1) no-keyword invocation
    without relay.toml confirmed repos surfaces a message + exits cleanly; (2) `--interactive` flag is
    passed through to Workflow args; (3) existing keyword modes remain functional (dry-run check).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_front_door.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md` D1/D2.
    fables-turn/SKILL.md and relay-loop.js (id:83c9) must coexist. Workflows are opt-in by design (user
    invoking the command counts as explicit opt-in per harness rules — no extra gate needed).

- [x] Workflow script `relay-loop.js` — priority-mixed 5-wide autonomous pool [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:83c9 -->
  - **Why HARD**: complex Workflow JS orchestrating pool concurrency, the serialized integrator, quota
    guards, and graceful drain — all interacting. Wrong sequencing causes concurrent pushes (the
    double-decrement bug from prior executor runs); wrong quota gate causes runaway or premature stop;
    wrong graceful-drain loses in-flight worktrees.
  - **Acceptance**: `fables-turn/scripts/relay-loop.js` is a valid Workflow script with `export const meta`.
    Scheduler: per-repo classifier maps confirmed repos to {execute(Sonnet)/review(strong)/handoff(strong)/idle};
    pool fills up to 5 execute slots first; backfills idle slots with review (unreviewed-executor-work priority
    > fresh handoff). SERIALIZED integrator: after each agent completes, ONE coordinator agent runs
    `--no-ff` merge → `ckpt-tag.sh` → `git-lock-push.sh --ff-only` — never two repos integrating concurrently
    (one-push-per-repo-per-turn invariant). Quota-stop: calls the id:9934 quota helper; on threshold crossed,
    stops dispatching new units and lets in-flight agents + ALL integration debt finish before `return`.
    `STRONG_TIER` env var (default `fable`, `opus` pilotable) sets `model:` on review/handoff agents.
    `log()` emits phase transitions; `RELAY_STATUS.md` rewritten on each integration.
    **Income preference (user directive 2026-06-12):** within a verdict class, repos flagged
    `income = true` in relay.toml are dispatched first; the class ordering itself is unchanged.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9`) — static checks: (1) `meta` block
    present with required fields; (2) no `AskUserQuestion` call in the script; (3) integration block
    serialized (no bare `parallel()` over the integration step); (4) `STRONG_TIER` variable referenced.
    Integration-behaviour tests deferred to the A6 pilot (live integration is too expensive for unit tests).
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_structure.sh` then full `make test` after ticking
  - **Context**: meeting note D2/D3/D5. Gil's constraint: Workflow JS can't run git; the integrator MUST
    be an agent that calls the bash scripts. Petra's fallback (not default): if the in-script integrator
    proves unwieldy, the integrator agent returns branch names and the front-door turn integrates — but
    don't build the fallback pre-emptively. Reuses `scripts/ckpt-tag.sh`, `scripts/discover-repos.sh`,
    and `git-diary-workflow/git-lock-push.sh --ff-only`. See also id:9934 (quota helper) and id:aeaf (STRONG_TIER).

- [x] Tier-aware quota-stop helper for relay-loop.js [ROUTINE] <!-- id:9934 -->
  - **Acceptance**: `fables-turn/scripts/quota-stop.sh [--tier sonnet|strong]` (or a JS helper inline in
    relay-loop.js) reads `/tmp/claude-usage-cache.json` and exits 0 (below threshold) or 1 (at/above).
    Sonnet tier: stop if `seven_day_sonnet`, `five_hour`, OR `seven_day` utilization ≥ threshold
    (env `RELAY_QUOTA_THRESHOLD`, default 0.90 = 90%). Strong tier: stop if `five_hour` OR `seven_day`
    ≥ threshold. **Scale (review fix 2026-06-12):** the live cache stores `.utilization` as a
    0–100 percent (e.g. `37.0`), while `RELAY_QUOTA_THRESHOLD` is a 0–1 fraction — the script
    converts internally (`val >= threshold*100`). Tests must use percent-scale fixtures. Stale cache (mtime > 10 min) or missing file → print a warning to stderr and exit 2
    (caller treats as "stop, uncertain"); missing-key in JSON → same. Threshold 0.90 is the default;
    override via env for piloting. Seatbelt: if agent-count arg `N` ≥ 200 or wall-clock arg `S` seconds ≥ 7200,
    also exit 1 regardless of cache.
  - **Tests**: `tests/test_quota_stop.sh` (`# roadmap:9934`) — synthetic cache JSONs at 0.85/0.90/0.95
    utilization for each relevant bucket; stale/missing file; seatbelt cap triggers.
  - **Done-check**: `tests/run-tests.sh tests/test_quota_stop.sh` then full `make test` after ticking
  - **Context**: meeting note D5. `/tmp/claude-usage-cache.json` format is maintained by
    `statusline/statusline-command.sh` (keys: `five_hour`, `seven_day`, `seven_day_sonnet`, each with
    a `percent_used` or similar field — verify the exact key names from the statusline script before coding).
    NEVER call `/api/oauth/usage` directly (429s after ~5 requests total).

- [x] `STRONG_TIER` config knob in relay-loop.js and front-door SKILL.md [ROUTINE] <!-- id:aeaf -->
  - **Acceptance**: relay-loop.js reads `STRONG_TIER` env var (values: `fable` | `opus`, default `fable`);
    passes it as `model:` override to all review and handoff agent() calls. Front-door SKILL.md documents
    the knob: `STRONG_TIER=opus /fables-turn` or `--strong-tier opus` flag. Sonnet execute agents never
    receive the STRONG_TIER override. If `STRONG_TIER` is unset or empty, defaults to `fable`.
  - **Tests**: `tests/test_strong_tier_knob.sh` (`# roadmap:aeaf`) — verify the JS script references
    `STRONG_TIER` and the SKILL.md documents it (grep-based static check).
  - **Done-check**: `tests/run-tests.sh tests/test_strong_tier_knob.sh` then full `make test` after ticking
  - **Context**: meeting note D4. Opus model ID: `claude-opus-4-8`. fable-class model match: `claude-fable-5`.
    Workflow agent() `model:` override is a first-class field — no wrapper needed.

- [x] `RELAY_STATUS.md` cross-repo rollup writer [ROUTINE] <!-- id:80e2 -->
  - **Acceptance**: relay-loop.js writes/rewrites `~/.config/fables-turn/RELAY_STATUS.md` (or a path
    configurable via `RELAY_STATUS_PATH` env var) on every integration and every phase transition.
    Template sections: `## In-flight` (repo, mode, agent-id), `## Completed this run` (repo, mode,
    ckpt-tag, push status), `## Queued` (repo, classifier verdict), `## Blocked / HANDBACKs` (repo,
    reason, worktree path), `## Quota remaining` (all three buckets with % remaining and reset time if
    available), `## REVIEW_ME open items` (per-repo count + path). Header: `# RELAY_STATUS — last updated
    <ISO timestamp>  run: <runId>`. File is overwritten each time (not appended). Also printed to `log()`
    as a condensed one-liner on each rewrite (so /workflows live view shows progress without the full file).
  - **Tests**: `tests/test_relay_status.sh` (`# roadmap:80e2`) — verify template sections present and
    non-empty for a synthetic completed-run payload; verify `log()` line appears in the condensed form.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_status.sh` then full `make test` after ticking
  - **Context**: meeting note "Surfacing (settled, no vote)". Per-repo REVIEW_ME.md stays the judgment-call
    channel (written by handoff/review children as before). RELAY_STATUS.md is read-only for humans —
    never edited by executor sessions.

- [x] Pilot autonomous pool on 1–2 income repos [HARD — strong model] (done 2026-06-12, run relay-20260612-2304: 6 integrated, 3 HANDBACKs recovered, quota drain verified; retrospective in RELAY_LOG.md 23:50 entry; Opus-handoff pilot NOT run — no handoff units classified; follow-ups id:bae5/59ea/1dff) <!-- id:1ad7 -->
  - **Why HARD**: first-contact with the real relay loop; templates and the executor contract will need
    revision after seeing actual unattended behaviour; judgment required on HANDBACK handling, REVIEW_ME
    quality, and whether priority-mixed scheduling converges as designed. Also the natural window to pilot
    `STRONG_TIER=opus` on handoff/review and compare output quality.
  - **Acceptance**: at least one complete unattended run on zkWhale or trAIdBTC (income repos) without
    manual intervention. `RELAY_STATUS.md` is produced **with all six template sections populated
    correctly — this is the behavioral check of the id:80e2 writer (its unit test is static-grep
    only; rescoped here by 2026-06-12 review)**. Any HANDBACKs are documented with root-cause.
    A short retrospective paragraph is appended to RELAY_LOG.md in this (dotclaude-skills) repo noting
    what needed revision and whether the Opus-handoff pilot was run.
  - **Tests**: none (pilot output is the deliverable; follow-on fixes get their own tests/items)
  - **Done-check**: `RELAY_STATUS.md` exists post-run; retrospective paragraph committed to RELAY_LOG.md here.
  - **Context**: meeting note A6 / D3 / D6. Gate: id:230f (front door) + id:83c9 (relay-loop.js) + id:9934
    (quota helper) must all be implemented first. Do not run fleet-wide until at least one income-repo
    pilot validates the design. This item is the verification gate before `--all` runs.

- [x] `--fable-down` / `-d` flag for executor-only relay runs (Fable inaccessible) [HARD — strong model] (done 2026-06-13, reviewer) <!-- id:3737 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (pool partitioning, zero-execute edge,
    deferred-unit surfacing) plus the SKILL.md front-door (Opus self-guard, Workflow args pass-through,
    invocation block, knobs table). Wrong placement would silently skip the Opus guard or fail to
    surface deferred units, masking the outage.
  - **Acceptance**: `--fable-down`/`-d` flag parsed by the front door and passed as `args.fableDown`
    into `relay-loop.js`. When set: (1) review and handoff units are partitioned out of the dispatch
    queue and surface in RELAY_STATUS Queued with reason `deferred: --fable-down, strong model skipped`;
    (2) execute (Sonnet) units proceed normally; (3) zero-execute edge exits cleanly with a log line;
    (4) integrator, quota gate, and drain logic are untouched. Opus self-guard in SKILL.md Default-mode
    step 0: if the session model is `claude-opus-*` and `-d` is not set, print a warning + `sleep 10`
    before launching the Workflow; suppressed when `-d` is set. Auto-probe deferred (forward-compatible:
    a future probe sets `args.fableDown = true` identically).
  - **Tests**: `tests/test_fable_down_flag.sh` (`# roadmap:3737`) — 11 static-grep checks
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_flag.sh` then full `make test` ✓
  - **Context**: meeting note `docs/meeting-notes/2026-06-13-0825-fable-down-detection.md`;
    https://www.anthropic.com/news/fable-mythos-access (access pull announced).

- [x] Separate Fable-availability from fallback policy (two-switch: `-d` × `STRONG_TIER`) [ROUTINE] <!-- id:5902 -->
  - **Acceptance**: `--fable-down`/`-d` asserts ONE axis only — "the Fable strong tier is
    unavailable this run" — and composes with `STRONG_TIER` (which chooses WHICH strong
    model review/handoff agents use). The FABLE_DOWN defer/demote block in `relay-loop.js`
    is gated on `FABLE_DOWN && STRONG_MODEL === 'claude-fable-5'`: (1) `-d` alone (STRONG_TIER
    `fable`) → defer strong work, executor-only (prior id:3737 behaviour, preserved exactly);
    (2) `-d` + `STRONG_TIER=opus` (STRONG_MODEL `claude-opus-4-8`) → SUBSTITUTE Opus, skip the
    defer block, dispatch review/handoff normally on Opus (already marked `fable-standin` by
    `standInSuffix`). Startup `log()` and explanatory comment describe both axes. SKILL.md
    knobs row documents defer-vs-substitute; a `/fables-turn -d --strong-tier opus` usage
    example is added near the STRONG_TIER examples.
  - **Tests**: `tests/test_fable_down_strong_tier.sh` (`# roadmap:5902`) — static-grep that the
    defer block is gated on `STRONG_MODEL === 'claude-fable-5'`, that no ungated `if (FABLE_DOWN) {`
    remains, and that SKILL.md documents the substitute combo + usage example.
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_strong_tier.sh` then full `make test` ✓
  - **Context**: follow-up to id:3737. The `-d` flag conflated "Fable unavailable" with "defer
    all strong work"; STRONG_TIER already chose the strong model, so the two compose. Opus
    model ID `claude-opus-4-8`; Fable-class match `claude-fable-5`.

- [ ] Sub-agent meeting simulation for main-ctx isolation [HARD — strong model] <!-- id:3346 -->
  - **Why HARD**: architectural — moves the whole meeting transcript generation out
    of the main context into a sub-agent; touches broker contract, persona loading,
    decision routing, and note-writing; wrong cut loses the user's live view.
  - **Acceptance**: see TODO id:3346. **GATED — do not start**: gate is "opencode
    port validated (proves broker contract is stable) + ≥1 meeting with ctx > 200k".
    Listed here for visibility only; remains parked in TODO.md until the gate fires.
