# Strong-model audit — Run 11 (2026-06-16 12:22)

- **Item**: ROADMAP id:401c (recurring `[HARD — strong model]` audit).
- **Auditor**: claude-opus-4-8 (Opus-apex HARD-execute child id:da26, fable-standin), relay run `relay-20260616-112222-29307`.
- **Window**: since Run 10's covered HEAD. Run 10 audited `95d3d07..HEAD`; this run
  covers the first-seen commits since Run 10's C5 commit (`5ab8c12..HEAD`), EXCLUDING
  Run 10's own integration merge `d36208a` (which carried only Run 10's own
  already-audited audit note + the relay-reconcile.sh fix + ROADMAP run-log entry).
- **Latest checkpoint at start**: `relay-ckpt-20260616-1250` (commit `1fcaba5`).

## Window contents (first-seen, non-Run-10)

Two commits, BOTH ledger-only (zero code, zero scripts, zero Python):

| Commit | File(s) | Lines | Kind |
|---|---|---|---|
| `03b67de` | `TODO.md` | +1 | new TODO id:0547 (live-observed race, root-caused) |
| `1fcaba5` | `RELAY_LOG.md` | +4 | Run 10 strong-execute checkpoint entry |

`git diff --stat 5ab8c12..HEAD` = `RELAY_LOG.md | 4 ++++` + `TODO.md | 1 +`. No
executable surface entered the tree in this window.

## Pass 1 — Code review

**Nothing to review.** No code, scripts, or Python helpers changed in the window. The
only code-bearing change between Run 10's audit point and HEAD lives inside Run 10's own
integration merge `d36208a` (the `relay-reconcile.sh` `shift 2`→`shift; shift || true`
fix + its regression guard + a `relay-econ.py` doc nit), which Run 10 authored AND
audited itself (see `2026-06-16-1247-strong-model-audit.md`). Re-auditing a strong
session's own already-audited fix is out of scope.

## Pass 2 — Security audit

**No security surface touched.** Both diffs are markdown ledger appends. No command/path/jq
injection seams, no system-boundary inputs, no secrets, no file-permission assumptions
introduced. Nothing to assess.

## Pass 3 — Design coherence

The one substantive artifact is **TODO id:0547** (the `03b67de` line): a live-observed
race — an injected `hard` unit and a normally-discovered `review`/`execute` unit for the
SAME repo (dotclaude-skills) dispatched in one round (run `relay-20260616-112222-29307`
round 5), ran concurrently in separate worktrees, and the non-winning units' integration
hit the winner's mid-merge dirty MAIN checkout → spurious dirty-tree handbacks (no
corruption, no work lost, but two children spent + handback noise).

**Verified the diagnosis against `relay/scripts/relay-loop.js`:**

- L71 — confirms the stated invariant `// D3: pool of distinct repos, one unit per repo.`
- L613 `units.push(...(r.units || []))` + **L617 `units.push(...(prelude.injectedUnits || []))`**
  — confirms injected units are concatenated onto the round's unit list with **no dedupe**
  against a discovery unit already present for that repo. id:0547 cites "~L617" — accurate.
- L808 `claim.sh acquire ${unit.repo} --run ${state.runId}` — the per-repo lease is keyed
  by `runId`, and `claim.sh acquire` is documented same-run RE-ENTRANT (conventions.md /
  claim registry id:ebfb), so two units of the SAME run targeting one repo both acquire it
  — no sibling-lane serialization. Accurate.

So id:0547 correctly identifies that **injection is a backdoor around the one-unit-per-repo
invariant**: the same-run re-entrant lease (a) plus the un-deduped injection merge (b)
combine to allow unguarded intra-repo parallelism — the exact thing id:ca87 says needs
sub-repo claim granularity before it is safe. The item's three graded fix options
(a: per-repo-per-round dedupe = immediate bleed-stop; b: unit-id-keyed non-re-entrant
sub-lease; c: full id:ca87 intra-repo parallelism) are sensible and correctly ordered.
Cross-references (ca87 / baf1 / ebfb / 6e9d / 719e) are all real, open, and on-point.
Checkbox state `[ ]` is correct (newly-filed bug, not yet fixed).

**No coherence defect.** id:0547 is a sound, accurately-root-caused ledger entry that
contradicts no existing contract; it surfaces a real gap rather than inventing one. The
RELAY_LOG `1fcaba5` entry is a standard, accurate Run-10 checkpoint record.

**Cross-ledger coherence** (recurring check): ROADMAP = 0 open `[ROUTINE]` / 3 open
`[HARD]` (id:401c recurring, id:414a gaming-canary gate-cleared, id:3346 GATED); the
TODO `<!-- id:d5e0 -->` summary line agrees exactly ("3 open ROADMAP items, all HARD …
ZERO open ROUTINE"). Consistent.

## Verdict

**CLEAN.** No code/security/coherence defects; no inline fix needed. Window was
ledger-only (one well-formed TODO + one checkpoint entry). Suite green at start and
after (58/0, no test changes — an audit-only run touches no tests). The next strong
session should consider acting on id:0547 fix option (a) (cheap per-repo-per-round dedupe
at the injection merge step) as a contained ROUTINE-with-care follow-up.
