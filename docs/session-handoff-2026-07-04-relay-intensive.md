# Session handoff — 2026-07-04 (relay mechanization + intensive run)

> **Local/untracked note.** This is a transient next-session handoff, intentionally left
> UNTRACKED (not committed to the public repo). Read it, act on the pending items, then
> delete it. Nothing here is private, but it is session-state, not durable project doc.

## ✅ COMPLETE 2026-07-04 ~21:4x — all done, pushed (commit 0f1023e); 3bf7/07da ticked [x]

**Scientific result (3bf7 reverse-English controls, 15 models):**
- **U4r −0.275 (15/15 neg) → sign-flip = English-vocab bias** (was +0.530)
- **U6r −0.649 (15/15 neg) → sign-flip = English-vocab bias** (was +0.414)
- **U7r +0.646 (15/15 pos) → NO flip = genuine non-English signal** — the sole inhabitant of the
  MEDIUM "productive zone". This is the load-bearing result for the characterization paper.
**07da:** U5 collapse **+5.40 → +0.82** grand-mean d; all OLD-template `†` footnotes removed; 15/15 cells redesigned.
**Verify:** `uv run pytest -q` = 87 passed. Pushed df78c66..0f1023e (write-up + 30 sweep commits together).

**TWO PAPER-CONTENT JUDGMENT CALLS the user should review (flagged by the agent):**
1. **Fixed a pre-existing arithmetic error:** the U2r grand-mean row read −0.480/−1.49 but the mean
   of its own per-model values is −0.493/−1.56. The agent corrected it (cited in the new comparison).
   Per-model values untouched. → user should confirm the correction.
2. **Pre-existing ~5% systematic offset** in non-U5 scorecard "Mean d" (e.g. U2 doc +2.36 vs tooling
   +2.61) — possibly an older data snapshot / different pooling. Left non-U5 rows alone; used honest
   tooling value for new U5. → **worth a look before final paper submission** (out of scope here).
3. Minor: cross-lingual U5 — non-English fine-tunes show slightly stronger residual U5 than the
   English avg; noted in a footnote, interpretation not rewritten (core claim rests on U1/U2/U4).

**d58f (write Experiment-1 results section) still `[HARD — hands]`** — the paper-section write-up
that folds all this in is the next linguistics step, not done here. fbcc (`[HARD — pool]`) was
deferred by the relay this run (linguistic-unversals was busy) — a future relay run picks it up.

## UPDATE 2026-07-04 ~21:3x — BOTH sweeps done; write-up agent DISPATCHED

- **3bf7: 15/15 U4r/U6r/U7r. 07da: 15/15 U5 @ SVO+subject_RC_position. 0 failures.** GPU + repo
  claims freed. 30 sweep commits are LOCAL+unpushed on linguistic-unversals main.
- **Write-up Opus agent RUNNING** (bg agent): claims the repo, computes U4r/U6r/U7r grand-mean
  log-ratios + Cohen's d (§2.4) using the repo's OWN effect-size tooling, re-does the Tier-1 U5
  matrix (removes OLD-template `†` footnotes), runs pytest, commits line-scoped, pushes the
  write-up + the 30 sweep commits together, and ticks/annotates 3bf7/07da. On its completion →
  ping the user with the consolidated result.

## UPDATE 2026-07-04 ~21:2x — relay 2nd run DRAINED (healthy); 3bf7 done; 07da ~done

- **Relay `wf_de5dea62-436` completed: 8 rounds, 416 agents, 0 errors, `quotaStopped:false`,
  backlog DRAINED** (the seeded burn samples fixed the quota-cache-unreadable 1-round stop).
  Substantive work across ~20 repos incl. the routed 3ef7 re-lanes: **zkm-telegram 8734/36b7**
  (author-split done), meeting-rpg 383b, isochrone. Pool is now idle → remaining work is
  human-lane + the in-flight sweeps.
- **1 handback (benign):** linguistic-unversals deferred — `resource:local-llm` held by ling-07da.
  Correct serialization (relay refused to collide); parked worktree already auto-pruned, no lost work.
- **NOTE:** the relay did NOT integrate/push linguistic-unversals (deferred), so the 3bf7 + 07da
  sweep commits are LOCAL+unpushed on main → push after the write-up agent commits RESULTS.md.
- **3bf7 done (15/15). 07da on last model (aya-expanse-8b, 14/15 committed)** → write-up agent next.

## UPDATE 2026-07-04 ~17:5x — 3bf7 DATA DONE (15/15, 0 fail); 07da running

- **3bf7 data-run COMPLETE:** all 15 models have `results/perplexity_reversed/<m>/{U4r,U6r,U7r}.jsonl`,
  per-model commits landed (LOCAL, unpushed — the relay integrator will bundle-push, or push at end).
- **07da running:** auto-acquired `resource:local-llm` the instant 3bf7 released; measuring U5
  (redesigned pairs, assertion passed) across 15 models, ~1 h. bg `blocdoc0v`.
- **Write-up agent trigger is `blocdoc0v` completion** (= both data runs done). Then spawn the
  Opus write-up agent per the plan below.

## UPDATE 2026-07-04 ~17:31 — sweep + relay re-launched (both running)

- **3bf7 GOTCHA found:** `scripts/run_queue_remaining.sh` **falsely reports 3bf7 done**. Its
  `is_complete()` only checks that `results/perplexity_reversed/<model>/` is *non-empty* —
  but those dirs held only the OLD **U2r/U10r** results, NOT the new **U4r/U6r/U7r** (e463,
  2026-06-30) that 3bf7 requires. The driver skipped all 15 models on first run. The
  reversed pairs for U4r/U6r/U7r had never been generated. **A future session must not trust
  that driver for 3bf7** (a fix would tighten `is_complete` to check per-universal).
- **3bf7 now running correctly (bg bash `bm5a2j55t`, claim `ling-3bf7-6562da64`):** generated
  U4r/U6r/U7r pairs via `06_generate_reversed.py --n-pairs 300` (U2r/U10r preserved, seed 42
  deterministic), then a per-model sweep `03_measure_perplexity.py --model <15> --universal
  U4r U6r U7r --input-dir data/sentence_pairs_reversed --output-dir results/perplexity_reversed`
  (driver: `scratchpad/3bf7-sweep.sh`, per-model commit). ~9 min/model × 15 ≈ 2–2.5 h.
  Wrapped in `resource:local-llm` so the relay can't collide. **NOTE:** 3bf7's full done-check
  also needs the RESULTS.md §2.4 write-up (grand-mean log-ratios + Cohen's d) — the DATA run is
  what's running; the §2.4 analysis is a separate follow-up.
- **07da (U5 sweep) — QUEUED behind 3bf7 (bg bash `blocdoc0v`, waits on `resource:local-llm`).**
  Found the same stale-data trap: on-disk `data/sentence_pairs/U5.jsonl` is the OLD template
  (`SVO+relative_clause`); 3071 committed only the primary's *result*, not regenerated pair
  data. Verified the redesigned grammar IS live (temp regen → `SVO+subject_RC_position`). The
  queued driver (`scratchpad/07da-sweep.sh`) waits for 3bf7 to free the GPU, then: regenerates
  U5 pairs (asserts `SVO+subject_RC_position`, else aborts), commits them, and re-measures U5
  across **all 15 models** (not just 14 — for pair-consistency, since the primary's provenance
  was ambiguous) with per-model commits. ~1.5–2 h after 3bf7 finishes.
  **NOTE:** 07da's done-check also wants the RESULTS.md Tier-1 matrix updated (no OLD-template
  U5 `†` footnotes) — that write-up is a separate follow-up after the data lands.
- **Relay re-launched:** `/relay --intensive --quota-7d 85% --strong-model opus`, Workflow
  `wf_de5dea62-436`. Seeded burn samples (d7=72%, in the Workflow-visible
  `~/.config/relay/quota-samples.jsonl`) so the quota fallback can extrapolate. Its local-llm
  intensive units DEFER to the held sweep claim (correct serialization); everything else runs.

## ⚠ POOL OUTCOME (completed 2026-07-04 ~17:14) — intensive tail did NOT run

The `wf_275aafa6-e7b` pool **stopped after 1 round** with `stopReason:
"quota-cache-unreadable"` — **NOT** the 85% cap. Root cause: the background Workflow's
`/tmp` is a separate namespace so it couldn't read `/tmp/claude-usage-cache.json`, and the
burn-sample fallback was stale (last samples Jul 2, `util:null`) → the fail-safe
extrapolation had no data → conservative stop. **Real quota is fine: 7-day = 72%** (cap
85%, resets 2026-07-07). This is the documented gap in `quota-stop.sh`'s header, not fully
closed.

- **Round 1 DID land (productive, 0 handbacks, all pushed):** meeting-rpg (review a376/383b —
  my routed re-lane), loderite (execute 1029, substantive), zkm-social (execute 297a,
  substantive), whalemountain (execute 4903/e3fd/d9ef, substantive), cyclotomic-projection,
  zkm, llm-from-scratch, 21cashus (reviews), isochrone (review 11c3/2558 — my routed
  re-lane), zkm-stt (**HARD** af5a, substantive).
- **NOT run (deferred by the premature stop):** intensive units helferli/it-infra/ai-codebench
  (local-llm), zkWhale (ram), trAIdBTC (network-bulk); hard leAIrn2learn/toesnail; handoff
  yinyang-puzzle; review zkm-telegram.
- **Mitigation applied:** seeded 2 fresh burn samples (2026-07-04T17:16, d7=72%) so a re-run's
  fail-safe extrapolation has recent data and won't 1-round-stop on the cache gap again.
- **➡ DECISION (pinged the user):** quota headroom is thin (72→85%, resets Jul 7). Options:
  (a) re-run the pool now to attempt the intensive+hard tail (respects the 85% cap, but heavy
  local-llm work could reach it fast); (b) run the linguistics sweep standalone now (pool is
  idle → no contention, `acquire-resource.sh` still correct); (c) wait for the Jul 7 reset.
  Left for the user's call — NOT auto-re-run unattended into thin quota with a just-failed gate.
- **Fix candidate (file it):** close the quota-cache-unreadable gap for background Workflows —
  either point `USAGE_CACHE` at a non-`/tmp` path relay-loop forwards, or have the pool seed a
  fresh burn sample in its own prelude so the fallback always has data.

## TL;DR — what is happening right now

- **The pool has now COMPLETED** (see outcome above). Originally launched via
  `/relay --intensive --quota-7d 85% --strong-model opus`.
  - Run ID: `wf_275aafa6-e7b` (Workflow, `relay-loop.js`).
  - Config: `STRONG_TIER=opus`, `allowIntensive=true`, quota cap **85% on both 7-day
    buckets** (`SEVEN_DAY` + `SEVEN_DAY_SONNET`). Host = **zomni**.
  - It self-feeds (execute → review → hard → handoff) across confirmed own repos until the
    85% cap, two dry discoveries, or the 30-round seatbelt.
  - Watch: `/workflows`, `tail -F ~/.config/relay/relay-events.jsonl`, or
    `~/.config/relay/RELAY_STATUS.md`.
  - Wind down: `/relay stop` (graceful drain) or `/relay stop --now` (hard, parks
    worktrees as `relay/orphan/*` → recover with `/relay reconcile`).

## Completed & committed this session

1. **b50e (delete 000d/9973/ad74 backstops) — re-checked, still NO-GO, gate narrowed to
   (c).** Background opus agent verdict. (a) id:854c instrumentation live-in-code
   (`emitBackstopFire()` → `relay-events.jsonl`), (b) id:3134 resolved (e833 shipped) — I
   also **ticked 3134** (was stale-open pending e833). Only criterion (c) remains: *a
   window of non-drained forward runs with 000d/9973/ad74 firing 0 times.* Recorded a
   dated RE-CHECK note on the b50e item (ROADMAP.md:165). Commits: `d43d706`, `30774a7`.
   - **➡ NEXT-SESSION ACTION:** the running pool IS a non-drained forward window. After it
     finishes, run `grep '"kind":"backstop"' ~/.config/relay/relay-events.jsonl`. If still
     empty across the pool's execute/hard rounds → b50e flips **GO**, delete the three
     guards. If any fired → triage that event instead.

2. **3ef7 (M3 cross-repo `[HARD — hands]` re-lane audit) — done.** Ran
   `gather-human-backlog.sh` (23 hands items / 12 repos, 0 untagged). Full audit recorded
   on the 3ef7 item (TODO.md:54-57). 4 automation-win candidates were routed to the inbox
   and then **auto-filed into their repos** by the reconcile (see below).

3. **Linguistics sweeps re-laned** (in `linguistic-unversals`, commit `df78c66`) per
   db39/2313: id:3bf7 + id:07da → `[MECHANICAL] [INTENSIVE — local-llm] [host:zomni]`;
   id:fbcc → `[HARD — pool] [host:zomni]` (dropped `[INTENSIVE]`, CPU-only). d58f left
   `[HARD — hands]` (a write-up, not a sweep). dotclaude-skills 3ef7 note updated (`0c2035c`).

4. **Inbox reconcile** (`scan-routed.sh --apply`, mandatory on the autonomous launch)
   filed **8 class-A items** into their target repos and drained 1 twin. Filed the four
   3ef7 candidates: isochrone `id:2558`, zkm-telegram `id:8734`, it-infra `id:5502`,
   meeting-rpg `id:a376`; plus f506 (gamemode), and **two new inbound items into
   dotclaude-skills**: `id:4368` (meeting must ignore AskUserQuestion timeout nudge) and
   `id:dc81`→`id:abbd` (relay-state-write.sh toml-set writes unquoted hyphenated values →
   invalid TOML — a real bug worth fixing).

## WRITE-UPS (3bf7 §2.4 + 07da Tier-1 matrix) — mechanism decided: background agent

- **NOT relay review** (it audits/verifies + re-derives ROADMAP; it does not author). Review is
  only a BACKSTOP — it would notice stale RESULTS.md and keep the item open.
- **Relay `hard` could** (write-up = apex authorship = `[HARD — pool]`), but needs it tracked as
  its own `[HARD — pool]` item + a quota-having relay run reaching it. Under the `[MECHANICAL]`
  data-run retag the write-up is otherwise INVISIBLE to the relay.
- **CHOSEN: one background Opus agent**, spawned when BOTH data sweeps land (the `07da` bg job
  `blocdoc0v` completing = both done, since it's queued after 3bf7). It will: acquire the
  linguistic-unversals claim (repo is relay-`hard`-claimed NOW — working **fbcc** — so DO NOT
  edit its ledgers until that frees), read the JSONL, write RESULTS.md §2.4 (3bf7 reversed-control
  grand-mean log-ratios + Cohen's d per model) + update the Tier-1 U5 matrix/scorecards removing
  OLD-template `†` footnotes (07da), run the repo's consistency/tests, commit, and tick/annotate
  3bf7/07da. Minted follow-up ids if splitting is wanted: **6cf9** (3bf7 §2.4), **7ee1** (07da Tier-1).
- **Trigger:** on the `blocdoc0v` (07da) completion notification, spawn that agent. Relay review
  is the safety net if the session is lost before then.

## PENDING — ready-to-run, NOT started (your call)

### A. Daemon/mechanical intensive sweep (3bf7/07da) — co-run with the pool, serialized
The `[MECHANICAL]` sweeps have no daemon yet, so run them manually **through the shared
`resource:local-llm` claim** so they can't OOM against the running pool's intensive units.
Exact command (idempotent driver, self-committing per model):

```bash
~/src/dotclaude-skills/relay/scripts/acquire-resource.sh local-llm --run ling-sweep-$$ -- \
    bash ~/src/linguistic-unversals/scripts/run_queue_remaining.sh
```

- **Mechanism:** both the pool's `[INTENSIVE — local-llm]` child and this wrapper acquire
  the *identical* `resource:local-llm` key → they serialize (take turns on the GPU), both
  finish, neither dies. If the pool holds the GPU, the wrapper exits 1 without running —
  wrap in `while ! …; do sleep 60; done` for a fire-and-forget retry.
- **NEVER run `run_queue_remaining.sh` un-wrapped** while the `--intensive` pool is live —
  the pool would be blind to it → double model load → OOM (the 2026-06-12 6-session kill).
- fbcc does NOT contend (CPU-only, `[INTENSIVE]` dropped) and the pool may pick it up
  itself as a `hard` unit on zomni.
- Reference: `relay/references/resource-claims.md`.

### B. Unpushed reconcile commits
`scan-routed.sh` committed INBOUND stubs directly to main in: **it-infra, isochrone,
zkm-telegram, meeting-rpg** (and dotclaude-skills got 4368/abbd). These were left for the
pool / next session to push (avoided racing the live pool). Verify and push any that the
pool didn't already carry:
`for r in it-infra isochrone meeting-rpg; do git -C ~/src/$r log --oneline origin/main..HEAD; done`
(zkm-telegram is under `~/src/zkm/plugins/zkm-telegram`).

## Open mechanization threads (unchanged, for context)
- **id:7df1** — close the dual-vocab window. Gated on 3ef7 + cross-repo re-tag. As the
  routed re-lanes land in each repo's handoff, this unblocks.
- **id:65f9 / 2ec4** — the off-Workflow mechanical-run daemon (what would run the
  `[MECHANICAL]` sweeps automatically, acquiring `resource:local-llm` itself). Not built.
- **id:abbd** (new) — relay-state-write.sh toml-set unquoted-value bug.
