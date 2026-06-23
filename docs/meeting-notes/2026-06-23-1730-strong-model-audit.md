# Strong-model audit — 2026-06-23 17:30 (id:401c Run 48)

**Window:** first-seen code since Run 46's own audit commit (`80a8441..HEAD`, the merge
landing Run 46). Run 47 (review) shipped the id:ad74 INTENSIVE-emit work in this window —
that code is therefore FIRST-SEEN for this audit (Run 47 was a review verdict, not a
strong-model code audit of its own freshly-written backstop).

**Window contents (code-only `*.sh`/`*.py`/`*.js`):**
- `relay/scripts/roadmap-lint.sh` (NEW, 167L — id:09a3 grammar validator)
- `relay/scripts/gather-repo-state.sh` (+18 — id:ad74 `top_intensive` field)
- `relay/scripts/relay-loop.js` (+60 — id:ad74 schema field, shard rule, JS backstop)
- `tests/test_relay_loop_intensive_emit.sh` (NEW, 46L — id:ad74 static spec)
- non-code: Makefile (lint manifest), human.md/review.md (lint wiring), ledger files.

`gaming-scan.sh "$PWD" 80a8441` → exit 0 (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
Suite 89/0/0 at the final commit.

---

## Pass 1 — code review (correctness)

### HIGH (fixed inline): the id:ad74 JS-side INTENSIVE promote backstop was a NO-OP

`relay/scripts/relay-loop.js` ships an `id:ad74 — JS-side INTENSIVE promote backstop`
block, advertised (twice, in the shard prompt at the `INTENSIVE-EMIT-GUARD` line and in
the `top_intensive per repo` field doc) as the JS-side enforcement that "a shard that
ignores this instruction will still be self-corrected." As written it self-corrected
**nothing** — both of its branches were dead:

1. **Branch 1 — skipped→unit promote — provably dead code.** The loop iterated
   `[...units, ...skipped.map(...)]` and computed
   `const top_intensive = u ? (u.top_intensive || '') : ''`, then gated the skipped-repo
   promote on `if (top_intensive && !u)`. That condition is unreachable: `top_intensive`
   is forced to `''` whenever `!u`. Moreover the `skipped` rollup item schema
   (`DISCOVER_SCHEMA.properties.skipped`) is `{repo, reason}` only — it never carries
   `top_intensive` — so a skipped-only repo's intensive resource is genuinely
   unrecoverable from the merged JS data. (Exact symmetric twin of the **id:401c Run 45**
   dead-guard bug: "the guard was dead because the value never reached the unit object.")

2. **Branch 2 — patch idle unit's `.intensive` — ineffective.** For a unit the shard
   parked as `verdict:'idle'`, the backstop set `u.intensive = u.top_intensive` but left
   `u.verdict === 'idle'`. Downstream, `actionable = discovery.units.filter(u =>
   u.verdict !== 'idle')` drops every idle unit **before** the INTENSIVE partition
   (`for (const u of actionable) { if (u.intensive) … }`) ever runs. So patching
   `.intensive` on a still-idle unit never reaches dispatch — the unit is silently
   dropped, not even surfaced as `intensiveDeferred`.

Net: the exact failure id:ad74 was filed to self-correct (the `--afk` run on 2026-06-23
where the shard classified ai-codebench `idle` despite an open `[INTENSIVE — local-llm]`
item id:244b, blocking the overnight drain) would STILL be a silent drop if the shard
prompt instruction alone didn't take — the JS "backstop" gave a false sense of a second
line of defence. The shipped tests (`test_relay_loop_intensive_emit.sh`) are
static-presence greps only and could not catch this.

**Fix (inline):** rewrote the backstop to operate on emitted units only (every idle repo
also emits a `verdict:'idle'` unit per the shard contract, and the shard copies
`top_intensive` verbatim onto units), and for an idle unit with `top_intensive` it now
**flips `verdict` to `'execute'`** (so it survives the idle filter and reaches the
INTENSIVE partition → `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`) in addition
to setting `.intensive`. Dropped the dead skipped-source branch and documented why it was
dead. PROMOTE-only (idle→execute, never demotes), injected units exempt.

**Regression guard (non-vacuous):** added clauses (2c)/(2d) to
`tests/test_relay_loop_intensive_emit.sh` — (2c) asserts the backstop block flips an idle
verdict to `'execute'` (not merely patches `.intensive`); (2d) asserts it does NOT gate on
a skipped-entry source (`top_intensive && !u` — the dead branch). Verified non-vacuous:
both FAIL against the pre-fix JS (`git stash` of just the JS, ran the test → 2 fails),
pass against the fix. (Found+fixed a SIGPIPE-under-`pipefail` flake in the test's own
`awk | grep -q` while writing it — captured the window into a var first.)

Consistent with the established convention that relay-loop.js classification logic is
**structurally** tested (live integration deferred to id:1ad7) — these are static
structure assertions strengthened to lock the behavioural property the fix establishes.

### Other code — clean

- `roadmap-lint.sh` (id:09a3): correct. `set -euo pipefail`; arg resolution (no-arg /
  dir / file) sound; lane vocabulary READ from `hard-lanes.md` (single source, id:78ff)
  with a fail-safe built-in fallback + a loud stderr warning if the doc is unreadable;
  section gating via `nocasematch` on parked-bucket headings; only top-level `- [ ]`
  linted (closed/indented skipped); best-effort log never crashes the lint. Its dedicated
  test (`test_roadmap_lint.sh`) is non-vacuous (4 cases, incl. a real violation set).
  Lint runs clean on this repo's live ROADMAP (exit 0).
- `gather-repo-state.sh` (id:ad74): the `top_intensive` derivation
  `grep -m1 -oP '^- \[ \].*?\[INTENSIVE — \K[^\]]+'` is option-safe (no leading-dash
  injection — input is a here-string of the roadmap var), `|| true` keeps `set -e` happy,
  emitted through the env-var JSON encoder (no shell/JSON injection).

## Pass 2 — security

No new injection / traversal / secrets surface. `roadmap-lint.sh` takes a path arg and
reads files only (no eval, no command construction from content); `grep -oE` over a
trusted sibling doc. `gather-repo-state.sh`'s new field uses the existing safe env→JSON
encoder. relay-loop.js changes are pure in-memory object manipulation. **No findings.**

## Pass 3 — design coherence

- **id:c3a6 discovery-cache superset — coherent, no under-invalidation.** `top_intensive`
  is a NEW gather field the shard reads, which would normally require adding it to
  `discover-sig.sh`'s hash blob (the documented hazard). But `discover-sig.sh` already
  hashes the FULL `cat ROADMAP.md`, and `top_intensive` is a pure function of an
  `[INTENSIVE — …]` line in that file — any change to it changes the hashed roadmap blob,
  so the cache invalidates correctly. Covered transitively; **explicitly ACCEPTED** (no
  sig change needed).
- **id:09a3 lint wiring — coherent.** Added to all three Makefile manifests
  (`_FILES`/`_EXEC`/`_ALLOW`) and wired into BOTH review §5 ("grammar-lint the open items
  first") and human triage prose, exactly as the item required. "Surfaces, never
  auto-rewrites" mirrors id:78ff's back-fill-at-source precedent — no contradiction with
  the gather's untagged-`[HARD]` LOUD-reject (the lint is a strict superset net).
- **Cross-ledger drift fixed inline.** `orphan-scan --cross-ledger` flagged id:ad74
  (TODO:[ ] vs ROADMAP:[x]) — the id:d9b0 §3 / Run 46 scope-split class. The build is now
  genuinely complete AND functioning (post this audit's HIGH fix), so ticked the TODO twin
  (single-id-two-views state sync). Cross-ledger clean post-fix.

## Verdict

REAL CODE window. **1 HIGH defect fixed inline** (id:ad74 JS backstop no-op — the
symmetric twin of the id:401c Run 45 dead-guard bug, in the very feature built to be the
PROMOTE counterpart of that DEMOTE guard) + non-vacuous regression guard. roadmap-lint.sh
(id:09a3) and the gather field clean. 1 coherence point accepted (c3a6 transitive
coverage), 1 cross-ledger drift fixed (ad74 TODO tick). gaming-scan 0. Suite 89/0/0.
