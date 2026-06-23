# Strong-model audit — Run 46 (2026-06-23 09:45)

ROADMAP id:401c (recurring). Window: `d342839..HEAD` (HEAD = `1d4b9cb` /
`relay-ckpt-20260623-0944`). Window start = Run 45's audit-note commit (`d342839`).

## Verdict: LEDGER-ONLY / CLEAN by vacuity — one inline coherence fix

The window since Run 45 carries **no first-seen code**. The only two commits are:

- `b2b6ee9` — the `--no-ff` merge that LANDED Run 45's own audited work onto main
  (id:000d/1d64/3c0f/69ef + the HIGH dead-`is_finished`-guard fix Run 45 already
  vetted). Re-auditing a merge of already-audited code would double-count.
- `1d4b9cb` — a checkpoint commit, `RELAY_LOG.md` +4 lines only (bookkeeping).

`git diff d342839..HEAD -- ':(exclude)RELAY_LOG.md' ':(exclude)relay.toml'` is
**empty** — confirms zero code/script/Python delta outside the ledger. Same shape
as Runs 42/43 (ledger-only, clean-by-vacuity).

## Three passes

1. **Code review** — N/A: no first-seen scripts/Python/JS in the window. (Run 45
   covered the real code: id:000d `is_finished` guard, id:1d64 margin-aware
   quota-stop staleness, id:3c0f `[HARD — pool]` token sync, id:69ef install-manifest
   completeness guard; id:09a3 `roadmap-lint.sh` shipped only its RED spec.)
2. **Security audit** — N/A: no new input/boundary/injection surface introduced.
3. **Design coherence** — **one finding, fixed inline** (below).

## Finding (design coherence) — cross-ledger scope-split false-positive — FIXED INLINE

`orphan-scan.sh --cross-ledger` flagged two divergences on arrival:

```
id:3c0f — TODO:[ ] ROADMAP:[x] (checkbox state disagrees across ledgers)
id:69ef — TODO:[ ] ROADMAP:[x] (checkbox state disagrees across ledgers)
```

Investigated: NOT real drift. The id:3c0f/69ef **builds are genuinely closed** —
`[x]` in ROADMAP, code shipped in Run 45. Their tokens appear in `TODO.md` only as
*references inside another item's prose* — the open umbrella item on TODO line 34
("HARD-pool lane-token drift + ROADMAP grammar lint", a follow-up that stays open
pending id:09a3 `roadmap-lint.sh`, which is itself still open / parked-orphan). This
is exactly the **scope-split false-positive** documented in id:d9b0 §3: a reused id
legitimately spans a *closed ROADMAP build* and an *open TODO umbrella that merely
mentions it* — re-flagged every review forever = alarm fatigue.

**Fix (the remedy id:d9b0 built for this):** added an `<!-- xledger-ok: ... -->`
annotation to the TODO line-34 umbrella, marking the divergence intentional. Verified
`orphan-scan.sh --cross-ledger` now exits clean (zero flags) — the annotation
suppresses the two false-positives, and an *un*-annotated divergence would still flag
(per `test_ledger_seam.sh`). id:09a3 was NOT annotated: it is still open in ROADMAP
too (parked orphan), so it does not diverge.

## Mechanical checks

- `gaming-scan.sh "$PWD" d342839` → exit 0, no flags.
- `orphan-scan.sh --cross-ledger` → clean (post-fix).
- Suite: 87 passed, 0 failed, 1 EXPECTED-RED (`test_roadmap_lint.sh`, roadmap:09a3
  still open — parked orphan `relay/orphan/relay-20260623-083216-13413-hard` holds
  its implementation, awaiting human reconcile; the red test is correctly the spec).

## Cross-ledger / open-item coherence

After the fix, cross-ledger is fully consistent. Open HARD items:
- id:09a3 `[HARD — pool]` — parked orphan (impl committed, awaiting reconcile).
- id:3346 `[HARD — meeting]`, id:dba3 `[HARD — decision gate]` (gated on /relay human).
- id:e149 / id:7809 / id:98f0 / id:0994 `[HARD — hands]` (human-attended lane).
- id:de4e DEFERRED (quota economics).
No open `[ROUTINE]` items. The `d5e0` prose count line is left as-is (slated for
dissolution under id:1de1/659c).

## Run log

- Run 46 (2026-06-23-0945): `d342839..HEAD` (Run 45's merge + 1 checkpoint) —
  **LEDGER-ONLY, CLEAN by vacuity**; one inline coherence fix (xledger-ok annotation
  on the id:3c0f/69ef scope-split, per id:d9b0). gaming-scan 0, suite 87/0 + 1
  EXPECTED-RED, cross-ledger coherent post-fix.
