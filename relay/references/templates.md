# relay artifact templates

Three fenced templates. Handoff children instantiate them at repo root; review
children update them in place. Placeholders in `<angle brackets>`.

## ROADMAP.md

```markdown
# Roadmap <!-- relay roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

## Items

- [ ] <imperative title> [ROUTINE] <!-- id:XXXX -->
  - **Acceptance**: <observable criteria, user-visible where possible>
  - **Tests**: <test file/function names, each marked `# roadmap:XXXX`> (currently RED)
  - **Done-check**: `<exact command an executor runs to verify, e.g. uv run pytest -k xxxx>`
  - **Context**: <files involved, constraints, pointers into ARCHITECTURE.md>

- [ ] <imperative title> [HARD — strong model] <!-- id:XXXX -->
  - **Why HARD**: <judgment/architecture/ambiguity reason>
  - **Acceptance**: <criteria>
```

Rules baked into the format:
- `<!-- id:XXXX -->` tokens come pre-allocated by the orchestrator
  (`~/.claude/skills/meeting/append.sh new-ids N <repo-root>`); never invent tokens.
- Every `[ROUTINE]` item MUST list its red tests; an item without failing tests is
  not handed off, it stays `[HARD]` until the reviewer writes them.
- TODO.md mirror: exactly one line in the repo's TODO.md —
  `- [ ] Relay: N open ROADMAP items <!-- id:XXXX -->` (own token; update N on
  every roadmap change, tick when zero remain).
- Orthogonal markers (NOT lanes) may co-occur on an item — `@manual` (human runs/verifies),
  `@needs-auth` (human-held secret), `@wire` (executor-verifiable via a host/e2e RED spec).
  An open `@wire` item on a primary executor lane (`[ROUTINE]`/`[HARD — pool]`/`[HARD]`)
  counts as executor-actionable → `verdict=execute`; `@manual` stays excluded. A two-phase
  feature is the D3 **two-linked-items split** (a `@wire` executor item + a separate
  `@manual` human item `gated-on:` it), never a mutable re-tag. All markers are defined in
  `relay/references/hard-lanes.md` (the grammar SSOT).

## RELAY_LOG.md

```markdown
# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->

## <YYYY-MM-DD HH:MM> — <reviewer|executor> (<model>)

<One paragraph: what was done, friction, surprises. Reviewer entries come from
ckpt-tag.sh; executor entries are appended manually per the relay contract.
HANDBACK entries describe exact state + worktree branch of interrupted work.>
```

Created by ckpt-tag.sh on first checkpoint; `.gitattributes` gets
`RELAY_LOG.md merge=union` at the same time, before any executor exists.

## REVIEW_ME.md

```markdown
# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

- [ ] <test file::test name> (roadmap:XXXX) — <one line: the ambiguity and the
  interpretation the test encodes>
```

A ticked box means "interpretation confirmed"; to correct one, edit the test (or
leave a note under the item) and the next review turn re-derives the roadmap item.
