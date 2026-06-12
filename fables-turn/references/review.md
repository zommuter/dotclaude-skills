# Review mode — per-repo child procedure

A review child runs inside its own worktree for ONE repo, evaluating what executor
sessions (and any manual work) did since the last checkpoint, then re-deriving the
roadmap. The core obligation is **trust-but-verify**: confirm formerly-red tests went
green by genuine implementation, not by weakening the spec.

## 1. Establish the diff window

```bash
LAST=$(git tag -l 'fable-ckpt-*' | sort | tail -1)
git log --stat "$LAST"..HEAD
```

Review ALL commits since `$LAST`, not only executor-attributed ones — the user may
have worked manually between turns.

## 2. Test-integrity audit

A formerly-red test that is now green is only valid if the IMPLEMENTATION changed to
satisfy the ORIGINAL test. Check, in order:

1. **Deleted tests** — any test file removed since the checkpoint is an automatic flag:
   ```bash
   git diff "$LAST"..HEAD --diff-filter=D --name-only -- '<test-dirs>'
   ```
2. **Weakened tests** — diff every changed test file and flag: removed `assert`/
   expectation lines without an equivalent addition; added `skip`/`xfail`/`todo`/
   `.only`/`@pytest.mark.skip`; loosened tolerances, timeouts, or comparison operators;
   expected values rewritten to match whatever the code now returns (hardcoded actuals).
3. **Resurrection check** — for each formerly-red, now-green test that was MODIFIED,
   run its ORIGINAL version against the NEW implementation; it must pass:
   ```bash
   git show "$LAST":path/to/test_x.py > /tmp/orig_test_x.py
   # run /tmp/orig_test_x.py against the current working tree
   ```
   If the original test now fails, the executor changed the spec, not the behaviour.
4. **Fixture special-casing** — grep the implementation diff for literals that appear
   only in test fixtures (the code branching on the exact test inputs).

Anything flagged here is surfaced prominently in the return report and the roadmap item
is reopened.

## 3. BDD suites

Run the BDD suites. For `@manual` scenarios, emit the checklist into REVIEW_ME.md (or
the return report) for the human rather than attempting to automate them.

## 4. Spec-drift audit

Does the implementation still match `ARCHITECTURE.md` rationale (new dependencies,
restructurings, abandoned decisions)? Update the doc to reflect reality, or flag the
conflict if the drift looks unintended. Also check the `## Relay contract` pointer in
`CLAUDE.md`: if the `<!-- fables-executor contract vN -->` version number is older than
the canonical marker in `dotclaude-skills/fables-executor/SKILL.md`, refresh the pointer
line (update `vN` only — the two-line pointer body is stable and does not change).

## 5. Re-derive ROADMAP.md

- Close items whose tests are genuinely green; update the TODO.md summary count.
- Re-scope items that proved underspecified.
- Promote/demote `[HARD]` ↔ `[ROUTINE]` based on what executors actually struggled
  with — read commit messages (`friction:` lines) and RELAY_LOG.md entries.
- Cross-repo follow-ups go to the shared inbox (`append.sh -t inbox`), never into
  another repo's TODO.md.

## 6. Spend remaining budget

If quota remains, execute the globally top `[HARD]` item (orchestrator decides which
repo wins across the wave). Same red-green-refactor + HANDBACK-on-cutoff discipline as
handoff C5.

## Return contract

```json
{
  "repo": "<name>",
  "branch": "<worktree branch>",
  "since_tag": "<$LAST>",
  "verified_green": ["<id>", "..."],
  "gaming_flags": ["<id>: deleted test_x", "..."],
  "reopened": ["<id>", "..."],
  "roadmap_delta": {"closed": <n>, "rescoped": <n>, "promoted": <n>, "demoted": <n>},
  "manual_checklist": "<@manual scenarios for the human, or empty>",
  "diary_fragment": "<one-paragraph summary>",
  "handback": "<text if step 6 was interrupted, else empty>",
  "contract_met": true
}
```

Do NOT push; the orchestrator merges, runs ckpt-tag.sh, and pushes once per repo.
