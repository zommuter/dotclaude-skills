# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

- [ ] Add a batched `say` subcommand to broker-curl.sh and route broker-mode.md through it [ROUTINE] <!-- id:3b02 -->
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

- [ ] Cover fables-turn and projects skills in the Makefile installer [ROUTINE] <!-- id:1ec1 -->
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

- [ ] Sub-agent meeting simulation for main-ctx isolation [HARD — strong model] <!-- id:3346 -->
  - **Why HARD**: architectural — moves the whole meeting transcript generation out
    of the main context into a sub-agent; touches broker contract, persona loading,
    decision routing, and note-writing; wrong cut loses the user's live view.
  - **Acceptance**: see TODO id:3346. **GATED — do not start**: gate is "opencode
    port validated (proves broker contract is stable) + ≥1 meeting with ctx > 200k".
    Listed here for visibility only; remains parked in TODO.md until the gate fires.
