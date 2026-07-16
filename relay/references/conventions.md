# relay shared conventions

Two audiences: the **environment facts** below inform every agent prompt; the
**executor contract** lives at `relay/references/executor-contract.md` (loaded by
`/relay executor`). Handoff/review embed a thin versioned pointer into managed repos
rather than copying the full block — see §Executor-contract pointer below.

## Environment facts (inject into every child-agent prompt)

- **OS**: Manjaro Linux — install packages with `pamac`, never `pacman -S` directly,
  and **NEVER `sudo pamac`** (pamac escalates via polkit itself; sudo is wrong and will
  block on an interactive prompt your unattended session can't answer).
- **Do NOT install system packages unattended.** A relay child runs without a human to
  approve a polkit/sudo prompt. If a system dependency is genuinely missing, record it
  in the `handback` (and REVIEW_ME) instead of trying to install it — never `sudo`.
- **Python**: `uv` for environments and dependency management (`uv add`, `uv pip`,
  `uv run`); deps go in the project's venv, NEVER system-wide via pamac or bare pip.
  A missing Python import is almost always a `uv sync`/`uv add` task, not a system install.
- **Homepage deploy** (kienzler-homepage): `git push` to the bare repo on fievel;
  a `post-receive` hook deploys with `--ff-only`. Any NEW served file requires
  extending the Caddy whitelist — a deploy without the whitelist entry silently 404s.
- **Sudo**: `SUDO_ASKPASS=/usr/lib/ssh/ssh-askpass sudo -A` (graphical prompt).
- **Locale**: de_CH context, English for code/docs, ISO 8601 dates, 24-hour time, SI units.
- **Worktree isolation (id:f682)**: your worktree is the ONLY place to write. Use the
  absolute worktree path in every Read/Write/Edit call (or `cd` into it and stay there) —
  never a repo-root-relative path that could resolve inside the target's MAIN checkout.
  Touching the main checkout instead of your worktree is a real observed failure mode
  (2026-07-14, loderite R2): the worktree stays EMPTY (0 commits ahead of base), the
  "commit in worktree" self-report is silently wrong, and the integrator's
  `verify-isolation.sh` gate (below) now catches it before merge — but the goal is to never
  trigger that gate in the first place.

## Relay invariants (orchestrator + children)

- One subagent per repo; within a repo, parallel tasks only on disjoint paths.
- Verification-before-merge: tests green in the worktree → single integration branch →
  `--no-ff` merge by the orchestrator → ONE push per repo per turn via
  `~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only`. Children NEVER push.
- Children do not run git-diary-workflow or todo-update; they return a
  `diary_fragment` and the orchestrator batches.
- Every touched repo ends the turn with a `relay-ckpt-YYYYMMDD-HHMM` annotated tag and
  a RELAY_LOG.md paragraph (both via `scripts/ckpt-tag.sh`). Older `fable-ckpt-*` tags are
  historical and are NEVER rewritten; every reader that finds the latest checkpoint or its
  commit range matches BOTH prefixes:
  `git -C <path> tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`. The annotation
  label still records the producing model + role (e.g. `reviewer (claude-opus-4-8,
  fable-standin, relay-loop)`) — that model-in-label is the historical record.
- **Pre-integrate isolation gate (id:f682).** BEFORE merging a child's worktree branch,
  the integrator runs `~/.claude/skills/relay/scripts/verify-isolation.sh <worktree> [--base <ref>]`
  (mirrors `clean-tree-gate.sh`'s observe-only/fail-safe shape): exit 0 = the worktree has
  ≥1 commit beyond base and a clean tree, safe to merge; exit 2 = isolation failure (empty
  worktree / dirty tree / not a worktree at all) — **abort the merge, do not force
  anything**. **Recovery doctrine**: an isolation failure usually means the work itself is
  sound but MISLOCATED (written to the main checkout instead of the worktree), not that
  the work is bad — favor salvage over discard+re-run. Finish/commit the salvageable work
  in the MAIN checkout under the repo's held relay lease (the id:15d5 pattern: `/relay
  human`/review-style writes land directly in the main checkout under a lease, no worktree
  merge needed), then re-check with `git status`/`git log` before proceeding. Only discard
  and re-dispatch the unit if the mislocated changes are unrecoverable or entangled with
  unrelated concurrent edits.

## Tagging `[INTENSIVE — <resource>]` (id:8d52)

`[INTENSIVE — <resource>]` is a **resource modifier**, orthogonal to the verdict tag —
NOT a replacement for `[ROUTINE]`/`[HARD]` (or, during the dual-vocab migration
window, the old `[HARD — <lane>]` spelling). Like the capability lane tags it names the
resource so the dispatch gate knows what's contended. A ROADMAP item carries both:

```markdown
- [ ] Re-run the embedding index [ROUTINE] [INTENSIVE — local-llm]
```

**When a strong child (handoff/review) should tag an item `[INTENSIVE — local-llm]`** —
when the item's work would:
- (a) load a local GGUF / large model into RAM/VRAM (e.g. via llama-server / llama-swap /
  ollama),
- (b) run benchmarks or evals against a local model endpoint,
- (c) do a large embedding/index rebuild over a corpus, or
- (d) otherwise carry a known OOM or long-cold-start risk.

Rationale: on 2026-06-12 a Gemma 26B run in ai-codebench **OOM-killed all 6 concurrent
sessions** (swap was raised 16→32 GB afterward), and local models have a ~57s cold TTFT.
These loads must never overlap and must never sneak into a parallel wave.

**Consequence of the tag** (so taggers understand the cost): the unit is **never
auto-run**. It needs `--allow-intensive` / `--afk`, runs **serially-alone** (the pool
collapses to width 1 while it holds the resource), and holds an **exclusive
`resource:<name>` claim** (cross-run). Without the flag it is surfaced as skipped in
`RELAY_STATUS.md`.

**Per-repo default.** A repo whose work is *uniformly* intensive (e.g. ai-codebench, the
zkm index) can instead carry a coarse default `intensive = "local-llm"` (or `= true`) in
its `[repos.<name>]` block in `~/.config/relay/relay.toml`; item-level tags
override the repo default.

## Durable Fable-bonus-recheck queue (relay.toml, id:e030)

When a STRONG unit (review / handoff / hard, i.e. `STRONG_MODEL=claude-opus-4-8`)
checkpoints a repo, the integrator records a model-tracked entry in
`~/.config/relay/relay.toml` under `[repos.<name>]`:

- `last_strong_ckpt` — the strong checkpoint's tag name.
- `strong_model` — the model that produced it (e.g. `claude-opus-4-8`).
- `fable_rechecked` — `false` until a real Fable session rechecks the repo, then its
  ISO date.

These three keys SURVIVE a later executor (sonnet) checkpoint that overwrites
`last_ckpt` — fixing the masking bug (id:e030) where a fresh executor checkpoint hid the
latest-tag `fable-standin` signal and the pending optional Fable recheck became invisible.
An executor checkpoint MUST NOT clear them. A repo with a non-empty `last_strong_ckpt`
and `fable_rechecked = false` is an **optional** Fable-recheck candidate — non-gating,
never blocks work (Opus decisions are final; `@fable-optional-recheck` is a free second
opinion only).
- Cross-repo action items discovered mid-work go to the shared inbox
  (`~/.claude/skills/meeting/append.sh -t inbox`), never into another repo's TODO.md.

## Executor-contract pointer

The full executor contract (5 rules + ROADMAP/RELAY_LOG format conventions) lives at
`dotclaude-skills/relay/references/executor-contract.md` (loaded by `/relay executor`).
The canonical version marker is `<!-- relay-executor contract vN -->` on the
`## Executor contract` heading inside that file.

**Handoff C1** writes the following thin pointer into the managed repo's `CLAUDE.md`
(as its own `## Relay contract` section), replacing any older verbatim block:

```markdown
## Relay contract <!-- relay-executor contract v5 -->

This repo is managed by a reviewer/executor relay. Load `/relay executor` before
working on any item, then follow its rules exactly.
```

**Review step 4** checks whether the pointer's `vN` matches the current contract version.
If stale (pointer vN < contract vN), refresh the pointer line to carry the current vN.
The pointer body text ("Load `/relay executor` …") is stable and does not change with
version bumps.

> Migration note: the rename from `fables-executor` to `relay` bumped the marker to v3.
> Pointers still carrying `<!-- fables-executor contract v2 -->` in external managed
> repos are **stale-but-handled** — each auto-migrates the next time that repo is
> reviewed (review §4 sees v2 < v3 and rewrites the whole pointer line to the v3 form
> above, including the new `/relay executor` body). Do NOT sweep external repos by hand.
