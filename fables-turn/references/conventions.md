# fables-turn shared conventions

Two audiences: the **environment facts** below inform every agent prompt; the
**executor contract** lives in the `fables-executor` skill (`fables-executor/SKILL.md`
in dotclaude-skills). Handoff/review embed a thin versioned pointer into managed repos
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

## Executor-contract pointer

The full executor contract (5 rules + ROADMAP/RELAY_LOG format conventions) lives in
the `fables-executor` skill at `dotclaude-skills/fables-executor/SKILL.md`. The
canonical version marker is `<!-- fables-executor contract vN -->` on the
`## Executor contract` heading inside that file.

**Handoff C1** writes the following thin pointer into the managed repo's `CLAUDE.md`
(as its own `## Relay contract` section), replacing any older verbatim block:

```markdown
## Relay contract <!-- fables-executor contract v2 -->

This repo is managed by a reviewer/executor relay. Load the `fables-executor` skill
(`/fables-executor`) before working on any item, then follow its rules exactly.
```

**Review step 4** checks whether the pointer's `vN` matches the current skill version.
If stale (pointer vN < skill vN), refresh the pointer line to carry the current vN.
The pointer body text ("Load the `fables-executor` skill …") is stable and does not
change with version bumps.
