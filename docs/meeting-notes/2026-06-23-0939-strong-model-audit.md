# Strong-model audit — Run 45 (2026-06-23-0939)

**Item**: id:401c (recurring strong-model audit). **Window**: `0e60f1f..HEAD`
(Run 44's own audit commit → `relay-ckpt-20260623-0923` / `6dbecf9`). **REAL CODE
window** (not LEDGER-ONLY). Suite 87/0 + 1 EXPECTED-RED (id:09a3). `gaming-scan.sh
. d068334` exit 0.

## First-seen code in window

Four merged ROUTINE items + one open HARD spec:

- **id:000d** — deterministic `is_finished` guard (`gather-repo-state.sh` emits the
  flag; `relay-loop.js` shard-prompt instruction + JS-side demote guard).
- **id:1d64** — margin-aware quota-stop staleness (`quota-stop.sh`).
- **id:3c0f** — sync `relay-loop.js` classifier to the canonical `[HARD — pool]` token.
- **id:69ef** — add `references/hard-lanes.md` to the Makefile install manifest +
  general install-completeness guard.
- **id:09a3** (still open `[HARD — pool]`) — `tests/test_roadmap_lint.sh` committed as
  a RED spec; `roadmap-lint.sh` not yet written (orphaned partial work, re-dispatch
  suppressed id:1f53). Correctly EXPECTED-RED, does not fail the suite. No defect — a
  faithful red spec for an open item.

## Pass 1 — code review

**HIGH (1 defect) — FIXED INLINE: id:000d JS-side demote guard was DEAD code.**
The whole point of id:000d is a *deterministic* backstop: gather-repo-state.sh computes
`is_finished` deterministically, and the JS block at the merge point
(`if (!u.injected && u.is_finished && FINISHED_DEMOTE_VERDICTS.has(u.verdict))`) is meant
to correct a shard that over-classifies a finished repo as execute/hard/handoff. But the
deterministic value never reached the unit object:

- `DISCOVER_SCHEMA.units[].properties` did **not** declare `is_finished` → the validated
  unit cannot carry it.
- The "Per-repo fields to set on each unit" shard-prompt list did **not** instruct the
  shard to copy `is_finished` from the gather JSON.

The gather JSON is consumed by the LLM *shard* (it runs the command and classifies), not
by the JS — the JS never parses it. So `u.is_finished` was structurally always `undefined`
and the JS-side guard never fired. The only live path was the shard-prompt instruction
(line 634) — i.e. exactly the non-deterministic LLM judgment id:000d existed to backstop.
The existing `test_relay_loop_structure.sh` asserts the guard *text* is present (static
grep) and so passed despite the guard being non-functional (presence ≠ behaviour).

**Fix (committed):** (1) declare `is_finished: { type: 'boolean' }` in the unit schema;
(2) add an explicit "is_finished per repo (id:000d): COPY the gather JSON's is_finished
boolean VERBATIM" line to the per-repo-fields instruction; (3) two new non-vacuous
assertions in `test_relay_loop_structure.sh` (schema declares the property; prompt
instructs the copy) — these *fail* on the pre-fix form, pinning that the deterministic
value actually reaches the JS guard. Demote-only / review-unaffected semantics unchanged.

**id:1d64 (quota-stop margin-aware staleness) — CLEAN.** The `decay_threshold` /
`bucket_threshold` helpers were *moved earlier* in the file so the new stale-cache margin
block (which calls `bucket_threshold`) has them defined before use — correct ordering; the
later burnup/check_key callers are unaffected. The margin math (`util < threshold*100 −
MARGIN`) and missing-bucket → unsafe → `exit 2` are sound; a fresh low-util cache still
exits 0 (happy path intact). The reworded `test_quota_stop.sh` assertion (stale+low-util
now → exit 0) correctly tracks the behaviour change. `test_quota_stop_stale_margin.sh` is
hermetic (temp cache aged past STALE_SECS + tokenless creds) and non-vacuous.

**id:3c0f / id:69ef — CLEAN.** Token sync is a pure literal replacement; the static tests
assert the stale `HARD — strong model` token is gone, the canonical `[HARD — pool]` is
present, and it is defined in `hard-lanes.md` (consumers cannot drift again). The
install-completeness guard generically asserts every `relay/references/*.md` is in
`relay_FILES` — a positive grammar, not a one-off check.

## Pass 2 — security

No new injection / traversal / secrets surface. `quota-stop.sh`: `awk -v u="$_u"` and the
`${!envname}` indirect expansion both read fixed-domain inputs (provider util numbers; a
bucket name from a closed `{seven_day, five_hour, seven_day_sonnet}` set), never user
strings. `gather-repo-state.sh`'s `is_finished` block is pure-read (`grep -cP`, `[[ ]]`
comparisons) on already-gathered vars. relay-loop.js edits are schema/prompt text only.

## Pass 3 — design coherence

The id:000d guard now actually closes its own loop (deterministic value → unit → JS
backstop), matching the item's stated "relay-loop.js also enforces this guard JS-side after
shard results are merged, so a shard that ignores the instruction will still be corrected."
The demote-only invariant holds (review requires `commits_since_ckpt` non-empty → never
`is_finished`). No never-firing gate, no contradiction with the bae5 lock-only-dirty
exemption (lock-only-dirty counts as clean for finished, consistent with its dispatchable
treatment elsewhere). id:09a3 stays a faithful open spec.

## Cross-ledger

0 open ROUTINE / 7 open executable-or-gated HARD (09a3 [pool] / 3346 [meeting] / dba3
[decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable). The four
window ROUTINE items (000d/1d64/3c0f/69ef) closed this window — d5e0 summary unchanged
(still 0 ROUTINE / executable-HARD set). Both tracked flakes (id:16e9, id:05e8) did NOT
recur. Suite 87/0 on a clean run.
