# fables-turn shared conventions

Single source of truth, two audiences: the **environment facts** below inform every
agent prompt; the **executor-contract block** is copied verbatim into every generated
CLAUDE.md. Never paraphrase the contract — review mode detects stale copies by the
version marker.

## Environment facts (inject into every child-agent prompt)

- **OS**: Manjaro Linux — install packages with `pamac`, never `pacman -S` directly.
- **Python**: `uv` for environments and dependency management (`uv venv`, `uv pip`,
  `uv run`); never bare pip into system Python.
- **Homepage deploy** (kienzler-homepage): `git push` to the bare repo on fievel;
  a `post-receive` hook deploys with `--ff-only`. Any NEW served file requires
  extending the Caddy whitelist — a deploy without the whitelist entry silently 404s.
- **Sudo**: `SUDO_ASKPASS=/usr/lib/ssh/ssh-askpass sudo -A` (graphical prompt).
- **Locale**: de_CH context, English for code/docs, ISO 8601 dates, 24-hour time, SI units.

## Relay invariants (orchestrator + children)

- One subagent per repo; within a repo, parallel tasks only on disjoint paths.
- Verification-before-merge: tests green in the worktree → single integration branch →
  `--no-ff` merge by the orchestrator → ONE push per repo per turn via
  `~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only`. Children NEVER push.
- Children do not run git-diary-workflow or todo-update; they return a
  `diary_fragment` and the orchestrator batches.
- Every touched repo ends the turn with a `fable-ckpt-YYYYMMDD-HHMM` annotated tag and
  a RELAY_LOG.md paragraph (both via `scripts/ckpt-tag.sh`).
- Cross-repo action items discovered mid-work go to the shared inbox
  (`~/.claude/skills/meeting/append.sh -t inbox`), never into another repo's TODO.md.

## Executor-contract block

Copy the fenced block below **verbatim** (including the version comment) into every
generated/refreshed CLAUDE.md, as its own `## Relay contract` section.

```markdown
## Relay contract <!-- fables-turn contract v1 -->

This repo is managed by a reviewer/executor relay. Executor sessions (you, unless
you were told you are the reviewer) follow these rules:

1. **Scope**: work only `[ROUTINE]` items from ROADMAP.md, one item per session.
   Never start `[HARD]` items — they are reserved for the reviewer model.
2. **Definition of done**: the item's previously-failing tests pass, a refactor
   pass is done, and the FULL test suite is green. Nothing else counts.
3. **Test integrity**: never weaken, delete, skip, or rewrite a test to make it
   pass. The reviewer diffs all test files against the last `fable-ckpt-*` tag
   and re-runs the original test versions; gamed tests will be found and the
   item reopened. If a test looks wrong or the spec seems ambiguous: STOP,
   append `BLOCKED: <item-id> <reason>` to RELAY_LOG.md, and pick another item.
4. **Self-report**: before ending the session, append one paragraph to
   RELAY_LOG.md — what was done, friction encountered, anything surprising.
   If an item was mis-sized (too big/small for one session), add a
   `friction: <item-id> <note>` line to the relevant commit message.
5. **Hygiene**: commit early and often with conventional messages; never force-push;
   never edit ROADMAP.md item definitions (tick checkboxes only); pamac not pacman;
   uv for Python.
```

When review mode finds a CLAUDE.md whose contract block is missing or has a version
marker older than the current one in this file, it refreshes the block (and only the
block) as part of its docs pass.
