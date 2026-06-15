# Strong-model audit — Run 5 (2026-06-15 19:37)

Recurring item id:401c. Window: `relay-ckpt-20260615-1748`..HEAD (the latest checkpoint
audited by Run 4 was `…-1748`; this picks up everything merged since, per the item's
"diff against the most recent `*-ckpt-*` tag" rule).

## Window

Substantive (non-checkpoint, non-merge) commits:

```
a8fe504 relay: FIX 2nd pool-crash in logGamingFlags — process.env not in Workflow sandbox
db5ec43 relay: FIX pool-crashing new Date() in logGamingFlags (id:3826) — Workflow ShimDate
953cf2e relay: surface failed discover shards (network resilience) instead of silently dropping repos
3c5fc08 todo: file id:cfa9 — connectivity-resilient relay (craft deterministic workflow per session)
6049fee review 191123: reconcile cross-ledger checkbox state (D2) — tick fa05/dfaf/3826, refresh d5e0
7277df6 relay: review relay-20260615-193130-2122 — verify id:3826 process.env fix genuine
```

Net diff: ~270 lines across 10 files. The code surface is `relay/scripts/relay-loop.js`
(2 fixes), two new tests, plus ledger/doc reconciliation. (`statusline/check-deps.sh` was
already audited in Run 4 — `bf70a52` is the boundary commit of the previous window and is
not re-reviewed.)

## Pass 1 — Code review

`relay-loop.js` — both fixes reviewed line-by-line:

- **Failed-shard surfacing (953cf2e)** — the `for…of` over `shardResults` became
  `shardResults.forEach((r, i) => …)` so a null shard result can map back to its repos via
  `chunks[i]`. **Index alignment is correct**: `shardResults = await parallel(chunks.map(…))`
  and `parallel()` preserves input order (Promise.all semantics), so `chunks[i]` is exactly
  the chunk that produced `shardResults[i]`. Each surfaced entry is `{repo: repo.repo, reason}`
  where `repo` ranges over `chunks[i]` (own-repo objects that carry `.repo`) — shape matches
  the other `surfaced.push` sites. `shardOk` stays false only when ALL shards fail → `discovery`
  stays null → the round fails gracefully (resumable). Sound and net-better than the old silent
  `continue` that dropped a failed shard's repos invisibly.
- **`logGamingFlags` Date removal (db5ec43)** — `ts: new Date().toISOString()` → `ts: ts || ''`,
  with `ts` threaded from the call site `logGamingFlags(unit.repo, state.runId, report, result.ts || state.ts)`.
  `state.ts = discovery.ts = prelude.ts` (an agent-produced ISO string, schema field at L464),
  so in practice `ts` is a real timestamp; `''` is only a defensive fallback. The Workflow
  runtime's ShimDate throws synchronously on any `new Date()`, and that throw escaped `integrate()`
  (the `.catch` only guards the agent promise, not the synchronous body) → whole-pool crash.
  Removing it is correct.
- **`logGamingFlags` process.env removal (a8fe504)** — `${process.env.HOME || '~'}/.claude/…`
  → a literal `'~/.claude/logs/relay-gaming-flags.log'`, expanded shell-side by the spawned
  agent (`python3 -c "os.path.expanduser(...)"`). The Workflow sandbox has no Node `process`,
  so the reference threw the same way. Correct: path resolution moves to the only layer that
  can do it (the agent's shell).
- **`node --check` passes**; the `test_relay_no_date_api.sh` grep finds **zero** forbidden-API
  occurrences outside whole-line comments — verified directly. No defect.

## Pass 2 — Security audit

- **`logGamingFlags` shell construction** — the JSON body is interpolated into a single-quoted
  shell literal in the agent prompt with `json.replace(/'/g, "'\\''")` — the canonical
  close-quote / escaped-quote / reopen-quote pattern. The `json` content derives from
  agent-returned `report` fields (ROADMAP ids, gaming-flag reason strings); single-quote
  escaping neutralizes the only shell-break character inside a `'…'` literal. The log **path**
  is now a fixed literal (no interpolation), removing the prior `process.env` interpolation
  surface entirely. No injection finding.
- **Failed-shard surfacing** — `reason` strings are static; `repo.repo` is an own-repo name
  from config, not external input. No new boundary. Clean.
- No new file-permission assumptions, no secrets, no path traversal introduced. **Clean.**

## Pass 3 — Design coherence

Swept the three currently-open `[HARD — strong model]` items and the ledger reconciliation:

- **id:401c** (this item) — recurring, correct by design.
- **id:3346** (sub-agent meeting simulation) — still `GATED — do not start` (opencode port +
  >200k-ctx meeting). Gate has NOT fired. Correctly parked. No action.
- **id:414a** (Tier-B canary harness) — gate marker reads `Gate CLEARED 2026-06-15` (set in
  Run 4), consistent with fa05/dfaf shipped; `review.md` references `gaming-scan.sh` and the
  script exists. Coherent. No action.
- **Cross-ledger state (id:d5e0)** — TODO d5e0 now reads "3 open ROADMAP items, all HARD …
  ZERO open ROUTINE". Re-derived against ROADMAP.md directly: **0 open `[ROUTINE]` lines, 3
  open `[HARD` lines** (id:401c, id:414a, id:3346). The 191123 review (6049fee) correctly
  ticked fa05/dfaf/3826 in TODO to match their ROADMAP closure. Agrees — no drift.
- **id:cfa9 (3c5fc08)** — new `[DESIGN/meeting]` connectivity-resilient-relay item is well-formed,
  routes open questions to a meeting, and correctly links the two Date/shard fixes audited above
  as motivating incidents. The "mechanize the mechanical steps / local-model fallback / lean on
  resume" framing is internally consistent with the existing id:23fe / id:95e3 / id:bc39 track.
  No contradiction. No action.

## Verdict

**No code or security defects in the window.** Both relay-loop.js fixes (failed-shard surfacing,
forbidden-Workflow-API removal) are correct, with genuine regression-guard tests
(`test_relay_no_date_api.sh`, the `chunks[i]` assertion added to `test_relay_discover_shard.sh`).
Cross-ledger state is coherent; the new design item (id:cfa9) is well-formed. Nothing fixed
inline this run (the window was already clean). Item id:401c stays open (recurring by design);
Run-5 log entry appended. Full suite green (50 passed, 0 failed) — unchanged by this note.
