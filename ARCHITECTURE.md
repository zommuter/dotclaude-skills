# Architecture — dotclaude-skills

Decisions with rationale and rejected alternatives. The deeper record is
`docs/meeting-notes/` (each decision below cites its note where one exists).

## 1. Publishing: per-file symlinks ("P2"), not copies

The live skill in `~/.claude/skills/<skill>/` *is* the repo file, via one symlink
per spec file (`make install`). Rationale: zero drift — an edit here is live
immediately, and what's published on GitHub is exactly what runs.

Rejected:
- **Copy-on-install** (rsync): silent drift between live skill and repo.
- **Whole-directory symlink**: the skill dirs must also hold *local-only*
  accumulator files (`discoveries.md`, `user-profile.md`) that may contain private
  data; a dir-level symlink would put them inside the repo tree and one `git add -A`
  away from publication. Per-file symlinks let public spec files and private local
  files coexist in the same installed directory.
  (`docs/meeting-notes/2026-05-10-1658-publish-meeting-skill.md`)

Consequence: always edit via `~/src/dotclaude-skills/`, never via the symlink path
— some tooling resolves symlinks inconsistently and permission rules are
path-literal.

## 2. Allowlist generator: 8 entries per script, merged idempotently

Claude Code's Bash permission matcher is a literal string-prefix match, so the same
script is a *different* pattern depending on how it's invoked: tilde vs absolute,
via the `~/.claude/skills` symlink vs the source tree, bare vs with arguments.
`tools/allowlist.py` therefore generates 4 path forms × 2 arg shapes and merges
them set-union into `settings.json` (backup + atomic write). Patterns the
generator cannot express (e.g. commands carrying unexpanded `$VARS`) live as
literals in `tools/allow-extra.txt`.

Rejected: hand-maintaining the allowlist (constant prompt regressions after every
new script); a single wildcard `Bash(*)` (defeats the permission model).
(`docs/meeting-notes/2026-06-01-1221-makefile-allowlist-generator.md`)

## 3. `id:XXXX` opaque tokens as the cross-file correlation key

Every action item that must survive across files (meeting note → TODO.md →
ROADMAP.md) carries a random 4-hex token in an HTML comment. `orphan-scan.sh`
flags meeting-note items whose token is absent from the union of TODO.md +
TODO.archive.md; matching is exact, so false positives are ~0 by construction.
Un-IDed legacy lines are deliberately skipped (clean cutover; old notes stay
frozen).

Rejected ("F-A"): fuzzy text matching between note lines and TODO lines —
FP-prone, breaks on rewording, was the original design and produced noise.
(`docs/meeting-notes/2026-05-21-0934-orphan-scan-fb-hash-id.md`)

Token minting is centralized in `append.sh new-id` which greps the known
id-bearing files to guarantee collision-freedom. **Any new id-bearing file class
must be added to that scan and to orphan-scan's union read** (ROADMAP.md joined
the ledger via roadmap item de9c — `append.sh scan-ids`, orphan-scan union read,
classify RELAY class; spec: `tests/test_id_ecosystem.sh`).

## 4. `append.sh` as the sole writer for shared registries

Direct Edit/Write on `discoveries.md`/`personas.md` triggers permission prompts
(path outside project) and risks interleaved writes from parallel sessions.
`append.sh` is allowlisted once, takes `-e`/`-f`/stdin, and serializes with
`flock`. The same flock-everything pattern governs `diary-append.sh` (plus
pending-file replay on lock timeout), `git-lock-push.sh` (per-repo push
serialization, 30 s timeout → commit-local-and-warn), and `ckpt-tag.sh`.

Rationale: parallel Claude sessions are a normal operating mode here (D5
worktree-per-session program); every shared mutable file needs a single
serialized write path. (`docs/meeting-notes/2026-06-03-1613-parallel-session-state-coordination.md`)

## 5. Meeting broker: canonical here, opt-in, one HTTP wrapper

`broker.py` (stdlib-only SSE broker) lives in this repo; `meeting-rpg` (the
renderer/launcher) symlinks in. An earlier decision (D7) had it the other way
around — reversed so the published skill is self-contained.
(memory: broker-canonical-home)

- **Opt-in default** `MEETING_LIVE=0`: `/meeting` never spawns processes unless
  asked; lazy-connect probes an existing broker first, the launcher's exported
  `MEETING_BROKER_PORT` is authoritative over stale `/tmp/meeting-rpg/broker.json`.
- **All HTTP via `broker-curl.sh`**: one wrapper = one allowlist entry, and the
  jq-based JSON building (apostrophe safety, no brace-defaults in `${...}`) is
  written once instead of per-call.
- Known cost: each wrapper call is a tool-call record in main context — the
  batched `say` subcommand (roadmap item 3b02, shipped) cuts this to one call
  per agenda item (~25–35 records/meeting → ≤10) while preserving one `/event`
  per line for renderer painting; full sub-agent isolation of the meeting
  transcript is the gated HARD item 3346.

## 6. classify.sh / orphan-scan.sh: mechanical pre-pass, model judges

The TODO pre-classifier emits C1/C2/C3 + an advisory `GATED` flag from cheap
grep-able signals (meeting-note link present? `## Decisions` section? gate
vocabulary?). It never decides — the model reclassifies with judgment. Same
philosophy for orphan-scan's `--reverse` mode (ADVISORY label, expected to return
in-session completions). Rationale: mechanical scripts keep token cost ~0 and are
testable; judgment stays where judgment lives.
(`docs/meeting-notes/2026-06-11-0824-classify-gate-text-check.md`)

## 7. todo-update archival: evidence-gated, prune-protected

`archive-done.sh` archives `[x]` lines only when (a) they were already `[x]` in
HEAD (count-based — "done before this session") or (b) they carry a trailing
`on YYYY-MM-DD` ≥30 days old. Empty-section pruning is unconditional but protects
`Done`/`Current` headings by name. Rationale: never archive work the *current*
session just completed (the diary/commit step still needs to see it), never
guess dates. (`docs/meeting-notes/2026-05-15-1121-todo-update-prune-empty-sections.md`)

## 8. Test harness: plain bash runner with roadmap-aware expected-red

`tests/run-tests.sh` + `tests/test_*.sh`, no framework. Chosen over **bats**
(rejected: not installed, adds a pamac dependency for zero structural gain at
this suite size) and over pytest (the codebase is bash; Python would test bash
through a subprocess layer anyway).

Distinctive rule: a failing test file whose `# roadmap:XXXX` item is still
unticked in ROADMAP.md is `EXPECTED-RED`, not a suite failure. This resolves the
relay tension between "red tests are the spec for open items" and "the full suite
must be green for the item you finish": the suite is green at every point in
time *with respect to claimed work*, and ticking a checkbox without making its
tests pass turns the suite red — an honest-by-construction done-check.

## 9. Hooks are observational loggers first

`meeting-cost-logger.sh` and `parallel-edit-detector.py` exist to *measure*
(cost calibration, parallel-edit frequency) before any prevention mechanism is
built — per the global "observe before preventing" heuristic. Don't extend them
into enforcement without logged evidence. `tools/ctx-budget.sh` follows the same
philosophy: advisory TSV scan of every SKILL.md against a 2k-token gate
(`CTX_BUDGET_GATE` override), always exit 0 — a logger, not a blocker.

## 10. Relay (fables-turn) self-hosted

The relay skill that manages this repo lives in this repo (`fables-turn/`).
Worktrees go under `~/.cache/fables-turn/worktrees/<repo>/` — outside the repo
tree so `git status` stays clean. Checkpoint tags `fable-ckpt-*` + RELAY_LOG.md
entries are written atomically by `fables-turn/scripts/ckpt-tag.sh`; children
never push (one push per repo per turn via `git-lock-push.sh`).

The integration push uses `git-lock-push.sh --ff-only` (+ `--follow-tags`,
always on): rebase would rewrite the `--no-ff` merge topology and orphan the
annotated checkpoint tags, so the relay path fails loud on divergence instead
of reconciling. The everyday diary-workflow default (`--rebase --autostash`)
is unchanged. (`docs/meeting-notes/2026-06-12-1342-fables-turn-integration-defects.md`)

Since 2026-06-12 the relay is growing an autonomous default mode (meeting note
`docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md`, D1–D6):
bare `/fables-turn` is a thin non-interactive front door over a Workflow script
(`fables-turn/scripts/relay-loop.js` — priority-mixed ≤5-wide pool, serialized
integrator, full pool logic pending id:83c9). Supporting pieces:
`scripts/quota-stop.sh` (tier-aware stop gate over the statusline's
`/tmp/claude-usage-cache.json`; cache `.utilization` is 0–100 *percent*,
`RELAY_QUOTA_THRESHOLD` a 0–1 fraction, converted internally), the
`STRONG_TIER ∈ {fable, opus}` model knob for review/handoff agents (execute
agents stay Sonnet), and the `RELAY_STATUS.md` cross-repo rollup written via an
agent (Workflow JS has no fs access). Push policy stays push-to-main with
retrospective review; unreviewed executor work is always the top-priority
strong unit.

The executor contract itself is a versioned skill (`fables-executor/SKILL.md`,
marker `<!-- fables-executor contract vN -->`); managed repos carry only a
2-line pointer in their CLAUDE.md whose vN must match — a full move into the
trigger-gated skill would lose the passively-loaded anti-gaming guarantee
(Shape B). Version consistency is test-enforced (`tests/test_fables_executor.sh`).
(`docs/meeting-notes/2026-06-12-1404-fables-executor-skill.md`)
