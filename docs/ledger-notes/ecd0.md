# id:ecd0

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

Observed loderite 2026-08-01**: `/relay reconcile .` correctly reported "no parked orphans" while `relay/handoff/savegame-migration` (13 days old, +340 lines including a 230-line RED spec `tests/savegame-migration.test.ts`, id:290e) and 21 merged `relay/*` branches sat unreachable by it. **Fix direction (the reporter's, preserved)**: make the CONSUME side ALSO enumerate unmerged `relay/*` branches outside the orphan namespace, or make parking branch-driven rather than worktree-driven. **Carve-out that must survive the fix**: `relay/exec/25c6` is NOT this bug — a `contract_met=false` HANDBACK is held by design (SKILL.md invariant 5) and must stay OUT of the orphan namespace. <!-- routed:47da --> <!-- id:ecd0 -->

## Original title (verbatim, before the `id:64f9` rewrite)

**`relay-reconcile.sh` reads ONLY `refs/heads/relay/orphan/*`, but parking is WORKTREE-driven — so once a worktree directory is gone its branch can NEVER be parked and is invisible to BOTH halves** — verified in code by the reporter. The consume side: `relay-reconcile.sh:91` sets `ORPHAN_NS` and `:189`/`:227`/`:361` are its only readers, so nothing user-invocable populates that namespace. The produce side: the park half lives in `reconcile-repo.sh` (`kind:park` -> `worktree-retire.sh:188` `git branch -m $branch relay/orphan/$bn`), which only runs inside a LIVE pool discovery round (split out of the LLM shard, id:a0b6) — and its park candidates are enumerated from WORKTREES (`reconcile-repo.sh:133` PLAN walks `$RELAY_WORKTREE_BASE`; `:171`/`:180` key the action on the worktree basename `$bn`), NOT from branches. **
