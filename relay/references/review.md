# Review mode — per-repo child procedure

A review child runs inside its own worktree for ONE repo, evaluating what executor
sessions (and any manual work) did since the last checkpoint, then re-deriving the
roadmap. The core obligation is **trust-but-verify**: confirm formerly-red tests went
green by genuine implementation, not by weakening the spec.

## 1. Establish the diff window

```bash
# Match BOTH checkpoint prefixes: relay-ckpt-* (current) and fable-ckpt-* (historical;
# a repo may still carry one as its latest tag until its next checkpoint).
LAST=$(git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1)
git log --stat "$LAST"..HEAD
```

Review ALL commits since `$LAST`, not only executor-attributed ones — the user may
have worked manually between turns.

## 2. Test-integrity audit

A formerly-red test that is now green is only valid if the IMPLEMENTATION changed to
satisfy the ORIGINAL test.

### 2a. Mechanical pass — run `gaming-scan.sh` first (id:fa05)

```bash
~/.claude/skills/relay/scripts/gaming-scan.sh "$(pwd)" "$LAST"
```

`gaming-scan.sh` covers the three cheap deterministic checks:

- **Deleted test files** — `DELETED_TEST:<path>` for any test file removed since `$LAST`.
- **Added skip/xfail/`.only`/`@pytest.mark.skip`** — `ADDED_SKIP:<path>:<line>`.
- **Removed assert/expectation lines** (net removal) — `REMOVED_ASSERT:<path>:<counts>`.

Any output from this pass is an automatic flag. Surface every `DELETED_TEST` /
`ADDED_SKIP` / `REMOVED_ASSERT` line in `gaming_flags` in the return report.
These three checks are the single source of truth for mechanical gaming detection —
do not re-implement them inline.

### 2b. Judgment-residue checks (prose only — bash cannot do these)

1. **Resurrection check** — for each formerly-red, now-green test that was MODIFIED,
   run its ORIGINAL version against the NEW implementation; it must pass:
   ```bash
   git show "$LAST":path/to/test_x.py > /tmp/orig_test_x.py
   # run /tmp/orig_test_x.py against the current working tree
   ```
   If the original test now fails, the executor changed the spec, not the behaviour.
   **Negative control**: a legitimate resurrection changes only the INPUT line (not
   the assertion) — e.g. the id:3b02 case where only the input to broker-say was
   corrected and all `assert`/`expect` lines remained intact. Only flag if the
   ASSERTION logic changed.

2. **Fixture special-casing** — grep the implementation diff for literals that appear
   only in test fixtures (the code branching on the exact test inputs). This is
   model-judgment; no mechanical bash check can reliably detect it.

3. **Green regression-guards** (handoff C3 D1, meeting 2026-06-13-1751) — a test that was
   GREEN since the handoff (pinning already-built behavior) is legitimate ONLY if it is
   marked a regression-guard AND has a REVIEW_ME "is this correct or a frozen bug?" entry.
   FLAG an unmarked green test that silently pins behavior with no such REVIEW_ME — it may
   be freezing a bug (e.g. rawrora's axis-swap/sign). Do not treat "passes today" as
   self-justifying.

4. **`unverified` / skipped tests are NOT passes** (handoff C3 D2) — a test tagged
   `# unverified — run in <env>` or one that SKIPS (missing toolchain/fixture: Android SDK,
   game-ROM, etc.) must NOT be counted as green. If the diff closes a `[ROUTINE]` item on
   the strength of a skipped/uncompiled/unverified test, FLAG it and keep the item open
   until the test actually runs green in the required env. A skip is not a pass.

5. **Faked-clean-tree check (id:373e — the v8 clean-worktree exit gate)** — the executor
   contract (rule 5b) requires the worktree to be CLEAN at exit, reached only by *committing*
   real work or *gitignoring* genuine throwaway — NEVER by DISCARDING work (`git checkout --
   <path>`, `git restore`, `git reset --hard`, `git clean`, or `git stash`/`git stash drop`).
   Watch for a clean tree reached by *deletion* rather than *completion*: an item ticked done
   whose acceptance behaviour is absent from the diff, a RELAY_LOG note mentioning a
   stash/reset/checkout to "clean up" or "make room", or a feature that looks half-removed.
   You already re-derive (§5) and re-run tests (§3) against the COMMITTED state, so a
   reverted-away change surfaces here as a missing feature or a red original test — FLAG it
   and reopen the item. (The integrator retires worktrees force-free per id:373e, so a
   genuinely-dirty exit is *surfaced-and-left*, never silently discarded — an honest executor
   hands the incomplete unit back rather than faking a clean tree.)

6. **Refactor claim vs diff (id:108e — the v9 `refactor:` self-report)** — the executor
   contract (rule 4) requires a `refactor:` line in the RELAY_LOG self-report: what was
   cleaned up, or `none needed — <reason>`. This is a **forcing function, not a proof** —
   refactoring is behaviour-preserving, so it cannot be mechanically verified, and `none
   needed` is a legitimate common answer for a small item. FLAG it ONLY when the committed
   diff **visibly contradicts** the claim: `none needed` next to obvious leftover cruft —
   dead code, duplicated blocks the acceptance implies unifying, un-removed RED-spec
   scaffolding, a copy-paste of an existing helper. Do not demand refactoring where the
   change was genuinely a clean one-liner. (Mechanizable later as a duplication/similarity
   linter — dotclaude-skills id:2c94 — which would catch the *left-duplication* signal
   deterministically; until then this is a judgment cross-check.)

Anything flagged here (from either the mechanical pass or the judgment residue) is
surfaced prominently in the return report and the roadmap item is reopened.

### 2c. Host-bound verification gate (multi-host config monorepos, id:43b9)

If a reviewed item carries a `[host:<name>]` tag (e.g. `[host:zomni]`/`[host:fievel]`;
absent ⇒ `host:any` ⇒ skip this gate — every ordinary single-host repo), its
definition-of-done (`make install`/tests) is HOST-BOUND and can only be validated on the
matching machine. Run the gate before crediting its verification:

```bash
~/.claude/skills/relay/scripts/host-gate.sh '<the ROADMAP item line>'
```

On exit 3 (the review host does not match the item's `[host:<X>]`), treat its host-bound
tests exactly like an `unverified`/skipped test (§2.4): you CANNOT count them green here.
Keep the item OPEN with a `needs host:<X>` note, surface it in REVIEW_ME, and never set
`contract_met: true` on the strength of host-bound verification that did not run on this
host. (Editing the files is host-agnostic and reviewed normally — only the install/test
verification is gated. ssh-to-host re-run is a documented future option, not built.)

## 3. Test tiers — run-or-record-skip for EVERY declared tier (id:f032)

A green claim derived from a SUBSET of a repo's test tiers is the same class of defect
as handoff C3 D2's `unverified` doctrine (§2.4): **a tier that did not run is not a
pass.** (isochrone's e2e tier sat RED for 13 days across 5 reviews that logged "suites
green" while running only the unit tiers — the worktrees lacked `node_modules` so
Playwright was silently absent.) To make that impossible:

- **(a) ENUMERATE the declared tiers.** Before running anything, list the repo's declared
  test tiers from its own manifests — `package.json` `scripts` (e.g. `test:unit`,
  `test:e2e`, `test:integration`), `Makefile` targets (`make test`, `make test-e2e`), and
  CI config (`.github/workflows/*`, etc.). That enumerated set is the tier list you owe a
  result for.
- **(b) RUN each tier, or RECORD-THE-SKIP.** Run every enumerated tier. For any tier you
  cannot run (missing toolchain/`node_modules`/fixture — exactly the §2.4 skip class),
  record the skip explicitly with its reason in BOTH `RELAY_LOG.md` and the returned
  summary — e.g. `SKIPPED-TIER: e2e — no node_modules in worktree (playwright absent)`.
  A silently-absent tier is treated as `unverified`, NOT green: if a `[ROUTINE]`/`[HARD]`
  item's done-check depends on a skipped tier, keep the item OPEN (same rule as §2.4).
- **(c) NAME the tiers actually run in any green claim.** "suites green" / "tests green"
  from a subset is BANNED wording. State which tiers ran green and which were skipped —
  e.g. "unit + integration green; e2e SKIPPED (no node_modules)" — never a bare
  suite-wide green that hides an unrun tier.

**BDD suites** are one such tier. Run them; for `@manual` scenarios, emit the checklist
into REVIEW_ME.md (or the return report) for the human rather than attempting to automate
them. A skipped BDD/e2e tier is recorded per (b), never folded silently into a green claim.

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

## 4b. Relay-health check (id:3eb5) — surface findings to REVIEW_ME, never a hard block

Run `relay-doctor.sh` on the cwd repo and include any findings in the REVIEW_ME
items for this review pass. This is **report-only** — findings are surfaced, they
NEVER block the review or cause the return contract to carry `contract_met: false`.
The goal is to catch latent relay-plumbing defects the executor wouldn't surface.

```bash
~/.claude/skills/relay/scripts/relay-doctor.sh "$(pwd)"
# or, if running from the worktree:
relay/scripts/relay-doctor.sh "$(pwd)"
```

For each issue reported by relay-doctor (cross-ledger drift, ROADMAP grammar
violations, missing reference-doc installs, parked orphan branches):

- **Cross-ledger drift** (`orphan-scan --cross-ledger` findings): add a REVIEW_ME box
  `[ ] id:XXXX — TODO:[…] ROADMAP:[…] checkbox drift` (one box per token).
- **ROADMAP grammar violations** (`roadmap-lint` findings): add a REVIEW_ME box
  `[ ] ROADMAP item id:XXXX — <lane/grammar issue>` and note it for the ROADMAP
  re-derivation in step 5 (roadmap-lint already runs there; use its output for both).
- **Mechanical-orphan** (`check-12` / id:1bd1 — an open `[MECHANICAL]` item with no recipe in
  the drop-dir): **AUTO-DRAFT it** so it stops silently rotting (id:8a6b — the resolution half of
  the loud-detection). Run `~/.claude/skills/relay/scripts/mechanical-orphan-draft.sh "$(pwd)"`
  (idempotent, WHITELIST-SAFE: it writes a `TODO:`-placeholder skeleton to `recipes/drafts/`,
  which the daemon NEVER consumes — never to `pending/`). Then add ONE REVIEW_ME box per orphan
  `[ ] [MECHANICAL] id:XXXX — recipe DRAFT auto-created in recipes/drafts/; fill its cmd/est_wall/
  acceptance_artifact and promote drafts/ -> pending/ to launch`. Never fill the recipe or promote
  it yourself — a human/Opus deliberately promotes it (the whitelist trust boundary). Orphans +
  un-promoted drafts are ALSO surfaced automatically in RELAY_STATUS.md and `/relay human`.
- **Other findings** (refs-install gap, parked orphans): add a single REVIEW_ME box
  naming the finding; the specific resolution is the human's call.
- **TODO grammar non-conformance** (`todo-conformance.sh` findings, id:3441): a TODO line
  that is not a header, an HTML comment, or a well-formed id'd checkbox item — work that
  would otherwise hide from routing. **AUTO-FIX the safe class, surface the rest, NEVER
  block** (user directive 2026-06-25): run `todo-conformance.sh --fix "$(pwd)/TODO.md"`
  to mint+append ids onto well-formed open items missing one (the `missing-id` class), then
  resolve each remaining `orphan`/`missing-id` by the owner-approved policies in
  `references/todo-conversion-policies.md` (P1–P4). Add ONE REVIEW_ME box per finding you
  cannot resolve without guessing intent (genuine task-existence / same-or-sibling-id
  ambiguity) — never fabricate a task or auto-pick a canonical id. The `--fix` + safe
  policy edits commit with the step-5 ledger commit.

If relay-doctor finds ZERO issues, note "relay-doctor: clean" in the session log;
no REVIEW_ME boxes are added.

## 5. Re-derive ROADMAP.md

- **Grammar-lint the open items first (id:09a3).** Run
  `scripts/roadmap-lint.sh` on the cwd repo's `ROADMAP.md` — a POSITIVE-grammar
  validator that LOUD-rejects ANY open `- [ ]` item not matching the proper syntax
  (a recognized `[ROUTINE]`/`[HARD]`/`[INPUT — meeting|decision|access]` lane tag — or,
  during the dual-vocab migration window, the old `[HARD — pool|meeting|hands|decision
  gate]` spelling — from `hard-lanes.md` PLUS a 4-hex `id:` token; items under a
  gated/deferred/icebox/archive
  heading are exempt). It catches deviations `gather` is blind to — an open item with NO
  class tag at all, or a malformed/unknown lane. It does NOT auto-rewrite; surface any
  violations in the return report so the strong/human turn assigns the lane at the source
  (mirrors id:78ff's "back-fill belongs to each repo's next handoff/review/human").
- **Reconcile stale-ledger drift (id:b3ee).** Run `meeting/orphan-scan.sh --shipped
  "$(pwd)"` — report-only; TICK-READY items (green linked test, no gating lexeme) and
  GATE-STALE items (gating lexeme, line >=14 days old) are advisory only, never
  auto-ticked. Verify each TICK-READY hit yourself before ticking its TODO.md checkbox;
  surface each GATE-STALE hit as a REVIEW_ME box for a human re-check of the lapsed clause.
- Close items whose tests are genuinely green; update the TODO.md summary count.
- **Single-id-two-views (D2):** when you add or promote a ROADMAP item for work the
  repo's `TODO.md` already tracks under an `<!-- id:XXXX -->`, REUSE that token — mint a
  fresh one (`append.sh new-ids N <root>`) ONLY for genuinely new work this re-derivation
  surfaced. A duplicate id for already-tracked work is undetectable by orphan-scan (two
  ids look like two items); reusing the token is what lets `orphan-scan.sh --cross-ledger`
  catch a "closed in ROADMAP, left open in TODO" divergence. When you close a ROADMAP item
  whose token also lives in `TODO.md`, tick the TODO line too (consistent checkbox state).
- Re-scope items that proved underspecified.
- **DECOMPOSED-into-seams TICKS the parent in the SAME commit (id:8504).** When you
  split an item into seams and write `DECOMPOSED into seams id:X, id:Y`, the parent is
  now a CONTAINER — its seams are the work, not the parent. In that same commit either
  **tick the parent** (`- [x]`, superseded-by-seams) or mark it `@container` (collectors
  exclude that marker). A DECOMPOSED parent left OPEN and still wearing a dispatchable/
  meeting lane double-counts against its own seams and re-surfaces as a phantom
  meeting/pool row. `roadmap-lint.sh --strict` FAILS on this (DECOMPOSED-CONTAINER); the
  authorship rule here is the prevention, the lint is the backstop.
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
- **Commit each main-checkout ledger edit ATOMICALLY (id:2147).** Every ROADMAP/TODO
  re-derivation, lane back-fill, gate annotation, or REVIEW_ME box you write here lands in
  the repo's **main checkout** (id:15d5, NOT a worktree). A modified-but-uncommitted ledger
  is dirty residue that trips the dirty-guard (id:aa93) so every later pool run DEFERS the
  repo — a self-perpetuating backlog. After your ledger edits, commit them per-repo with the
  scoped, flock'd helper (it stages ONLY the named files — never `git add -A` — and never
  stashes/resets a foreign-dirty tree):
  ```bash
  ~/.claude/skills/relay/scripts/commit-ledger.sh "$(pwd)" \
    -m "roadmap: re-derive + gate (id:3801, id:2147)" ROADMAP.md TODO.md REVIEW_ME.md
  ```
  It is a clean no-op when a named file has no change, so listing all three is safe. Do this
  before the return so an interruption can never leave a dirty-uncommitted ledger behind.

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

**On a handback (`contract_met: false`), ALSO classify it (id:3801)** — `handback_item` (the
4-hex id), `route` (`decision-gate` | `hard-split` | `human` | `none`), `gate_reason` (one short
line), and for `hard-split` a `proposed_split` array of seam units `{title, tier, dep?, id?}`.
The integrator's `handback-followup.py` then durably gates/splits the parent in ROADMAP.md so the
pool stops re-dispatching it. See handoff.md "Return contract" for the field shapes.

Do NOT push; the orchestrator merges, runs ckpt-tag.sh, and pushes once per repo.
