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
5. **Green regression-guards** (handoff C3 D1, meeting 2026-06-13-1751) — a test that was
   GREEN since the handoff (pinning already-built behavior) is legitimate ONLY if it is
   marked a regression-guard AND has a REVIEW_ME "is this correct or a frozen bug?" entry.
   FLAG an unmarked green test that silently pins behavior with no such REVIEW_ME — it may
   be freezing a bug (e.g. rawrora's axis-swap/sign). Do not treat "passes today" as
   self-justifying.
6. **`unverified` / skipped tests are NOT passes** (handoff C3 D2) — a test tagged
   `# unverified — run in <env>` or one that SKIPS (missing toolchain/fixture: Android SDK,
   game-ROM, etc.) must NOT be counted as green. If the diff closes a `[ROUTINE]` item on
   the strength of a skipped/uncompiled/unverified test, FLAG it and keep the item open
   until the test actually runs green in the required env. A skip is not a pass.

Anything flagged here is surfaced prominently in the return report and the roadmap item
is reopened.

## 3. BDD suites

Run the BDD suites. For `@manual` scenarios, emit the checklist into REVIEW_ME.md (or
the return report) for the human rather than attempting to automate them.

## 4. Spec-drift audit

Does the implementation still match `ARCHITECTURE.md` rationale (new dependencies,
restructurings, abandoned decisions)? Update the doc to reflect reality, or flag the
conflict if the drift looks unintended. Also check the `## Relay contract` pointer in
`CLAUDE.md`: if the `<!-- relay-executor contract vN -->` version number is older than
the canonical marker in `dotclaude-skills/relay/references/executor-contract.md`,
refresh the **whole pointer line** to the current vN form (from conventions.md
§Executor-contract pointer). A pointer still carrying the pre-rename
`<!-- fables-executor contract v2 -->` marker is the stale case this rewrites to v3 —
replacing both the marker and the body (old `Load the fables-executor skill` →
new `Load /relay executor`).

**User-facing docs are drift surface too** (added 2026-06-12, user directive): check
that `README.md` (feature/skill/usage tables, install instructions) and any user-facing
pages under `docs/` still describe what shipped in this diff window — a new command,
mode, knob, or artifact that the README doesn't mention is spec drift, same as a stale
ARCHITECTURE.md. Fix small gaps inline; queue a roadmap item for rewrites bigger than
the review turn should absorb.

## 5. Re-derive ROADMAP.md

- Close items whose tests are genuinely green; update the TODO.md summary count.
- **Single-id-two-views (D2):** when you add or promote a ROADMAP item for work the
  repo's `TODO.md` already tracks under an `<!-- id:XXXX -->`, REUSE that token — mint a
  fresh one (`append.sh new-ids N <root>`) ONLY for genuinely new work this re-derivation
  surfaced. A duplicate id for already-tracked work is undetectable by orphan-scan (two
  ids look like two items); reusing the token is what lets `orphan-scan.sh --cross-ledger`
  catch a "closed in ROADMAP, left open in TODO" divergence. When you close a ROADMAP item
  whose token also lives in `TODO.md`, tick the TODO line too (consistent checkbox state).
- Re-scope items that proved underspecified.
- Promote/demote `[HARD]` ↔ `[ROUTINE]` based on what executors actually struggled
  with — read commit messages (`friction:` lines) and RELAY_LOG.md entries.
- Cross-repo follow-ups go to the shared inbox (`append.sh -t inbox`), never into
  another repo's TODO.md.
- **Report `routine_open`** = the number of OPEN (unticked) `[ROUTINE]` items after this
  re-derivation. The supervisor uses it for review→execute chaining: `routine_open > 0`
  re-enqueues an execute unit for this repo in the SAME pool (no waiting for the next
  pool's discovery). Note: one execute turn works AS MANY open `[ROUTINE]` items as it can
  finish (it's per-repo, not per-item) — so `routine_open` is "is there executor work
  left," not "how many turns." A review still follows each execute batch (D3 anti-gaming).

## 5b. Qualify unqualified ledger additions (reverse-handoff, D6)

Between relay turns a human or a `/meeting` session adds items directly to `TODO.md`
(or `ROADMAP.md`) — often **ledger-neutral**: no `[ROUTINE]`/`[HARD]` qualifier, no
acceptance criteria, no spec test. `/meeting` writes design-ledger items this way **by
design** (it owns the "why", the relay owns difficulty). Find them and finish the
handoff the meeting deliberately left open:

```bash
git diff "$LAST"..HEAD -- TODO.md ROADMAP.md   # new '- [ ]' lines added this window
```

For each newly-added open item:
- **Execution-ready work** (a concrete change with an observable done-state) → do a
  **mini-handoff**: promote it to `ROADMAP.md` with a `[ROUTINE]`/`[HARD]` tag,
  acceptance criteria, a done-check, and (for `[ROUTINE]`) a red spec test — **REUSING
  its existing TODO `<!-- id:XXXX -->`** (single-id-two-views, D2; never mint a duplicate).
- **Design-judgment work** (ambiguous scope, two plausible approaches) → leave it as a
  TODO/`REVIEW_ME` item and note it as a `/meeting` candidate; do NOT force it into
  ROADMAP.
- **Deferred / gated** items (explicit reopen-gate with unmet conditions, activation
  date in the future, or a `[HARD]` design task) → **skip**; they are not yet executor
  work.

Record each qualification in the diff window's `RELAY_LOG.md` paragraph (which item,
what tag/size you gave it). This is the symmetric half of single-id-two-views: handoff
C2 promotes TODO→ROADMAP at handoff time; this step catches what `/meeting`/manual edits
added *after* handoff.

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
