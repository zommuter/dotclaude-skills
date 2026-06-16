# Strong-model audit — Run 10 (2026-06-16-1247)

Recurring audit item id:401c. Window: **first-seen code since Run 9** (audit commit
`95d3d07`) up to HEAD (`2571e3f`, checkpoint `relay-ckpt-20260616-1238`). Run 9
(2026-06-16-0928) covered `relay-ckpt-20260616-0653..HEAD`; everything after its audit
commit is this run's window. ~944 insertions / 16 files (non-ledger). Suite 58/0 on
arrival and after the inline fixes.

Window contents (first-seen code): orphan-reconcile build (D1 park id:689c in
relay-loop.js prose, D2 `relay-reconcile.sh` id:3313, D3 suppress-redispatch id:1f53
prose), `relay-econ.py` economics (id:08a3), `archive-done.sh` multi-line bullet fix
(routed:0076), `gather-human-backlog.sh` gated-HARD sweep (id:f6c9), Makefile/README/
SKILL.md/human.md doc updates, and their tests.

## Pass 1 — Code review (correctness, error handling, quoting, races, edge cases)

**DEFECT FIXED INLINE — `relay-reconcile.sh` arg-parse swallows the friendly
missing-arg guard.** The `--integrate`/`--discard` arms used
`target="${2:-}"; shift 2`. Under `set -e`, `shift 2` with only one positional arg
(the flag given as the LAST token, no branch value) **fails the shift count check and
exits via set-e** BEFORE reaching the intended `[ -n "$target" ] || { echo "<branch>
required"; exit 2; }` guard — so `relay-reconcile.sh <repo> --integrate` died with a
cryptic shift error / silent set-e exit instead of the helpful message. The `${2:-}`
default was written to tolerate the missing value but `shift 2` defeated it. Fixed to
`shift; shift || true` (consume the flag, then best-effort consume the value), so the
parse loop reaches the friendly guard in all three cases (verified in isolation). Added
a **non-vacuous behavioural regression guard** to `tests/test_relay_reconcile_mode.sh`
(section 5): a hermetic fresh git repo with no orphans, asserting both `--integrate`
and `--discard` with no branch exit `2` with the `<branch> required` message. Proven it
catches the regression — reverting to `shift 2` makes the guard FAIL (exit 1, not 2).
The missing-arg path exits before any merge/tag/push, so the test never crosses the
integration boundary.

**Accepted (LOW) — `gather-human-backlog.sh emit_gated_hard` uses `awk -v name=`/`-v
path=`.** awk's `-v` processes C-style backslash escapes (the id:c8db F1 class). Here
the values are repo names and filesystem paths from relay.toml `own` config (controlled,
no backslashes on Linux in practice) and feed only `printf` output, never a destructive
op. Same zero-today / forward-robustness posture as id:c8db — accepted, not filed.

**Clean — `relay-econ.py`.** Pure-read, stdlib-only. `subprocess.run(..., timeout=120)`
with no `check=`; a profile-run failure yields empty stdout → `json.loads("")` raises →
caught by `except Exception: continue`. `union_ms` interval-merge is correct (sorted,
single-pass coalesce). Cache-rate accounting reads the **correct** field names
(`tokens_cache_read`/`tokens_cache_create`) — verified against profile-run.sh lines
229-230. `--limit`/`--json` arg loop is index-safe for normal use (a trailing `--limit`
with no value would IndexError, same CLI-misuse class as the sibling profile scripts —
not a defect). `model_key` falls back to `sonnet` safely.

**Clean — `archive-done.sh` multi-line bullet fix.** The continuation-gather logic
(`is_continuation` + trailing-blank trim, lines 67-104) correctly moves a `[x]` bullet
with its indented sub-bullets/wrapped prose as one unit, and blank lines between wrapped
lines don't terminate the unit while trailing blanks are returned to the document gap.
Section-pruning still protects `Done`/`Current`. Has its own test.

**Clean — relay-loop.js orphan-park/suppress (id:689c/id:1f53).** These are discovery
**agent prose** (the established relay-loop.js pattern — discovery is an `agent()`, not
inline JS), coherent with the D1/D3 specs and the 2026-06-16-0938 meeting note. The
`relay/orphan/*` refs-as-registry approach (no manifest) matches the ratified design.

## Pass 2 — Security (injection, unvalidated boundaries, secrets, permissions)

No command/path/jq injection seams introduced. `relay-reconcile.sh` passes all branch/
repo args to git as separate, quoted positional args (`git -C "$repo" branch -D "$br"`),
never eval'd; `normalize_branch` only prefixes a fixed namespace. The `--integrate` path
correctly refuses on dirty tree and on a diverged base (`sync-origin.sh`, id:c3f7) and
aborts+leaves on merge conflict — it cannot half-merge or checkpoint on a bad base. No
secrets touched; no new file-permission assumptions. `relay-econ.py` is pure-read.
`emit_gated_hard` awk-`-v` noted in Pass 1 (LOW, accepted).

## Pass 3 — Design coherence (sensibility, feasibility, internal contradictions)

- **Cross-ledger coherent.** ROADMAP: 3 open items, **0 ROUTINE / 3 HARD** (id:401c
  recurring audit; id:3346 gated sub-agent meeting sim; id:414a Tier B gaming-canary).
  TODO summary line id:d5e0 agrees exactly ("3 open ROADMAP items, all HARD", same ids,
  ZERO ROUTINE). `orphan-scan.sh --cross-ledger` reports no disagreement.
- **f6c9 gated-HARD sweep limitation is documented and self-consistent.** `emit_gated_hard`
  statically detects only the two purely-textual gates (`[HARD — decision gate]` tag, or a
  `## Gated`/`do not start`/`deferred` section) and explicitly defers acceptance-text gates
  ("blocked on …", multi-session) to the tier-(c) `/meeting` route. Consequence: id:3346
  (`[HARD — strong model]`, gated only in its acceptance sub-bullet under `## Items`) is NOT
  flagged by the static sweep — by design (it surfaces via the pool's model-classified
  RELAY_STATUS Blocked entry instead). Not a contradiction; the doc states this limit.
- **id:414a gate genuinely CLEARED.** Confirmed fa05 (gaming-scan.sh) + dfaf (review.md §2
  delegate) both shipped — `review.md` references `gaming-scan.sh` and the script exists.
  The item is dispatchable HARD (fixture craft needs strong-model judgment), not blocked.
- **Makefile install-manifest complete.** Both new scripts (`relay-econ.py`,
  `relay-reconcile.sh`) are in `relay_FILES`/`_EXEC`/`_ALLOW`; the id:5f09 contract test
  passes, so neither can ship un-symlinked.

## Outcome

One **DEFECT fixed inline** (relay-reconcile.sh missing-arg guard + regression test),
one **doc nit fixed inline** (relay-econ.py header field-name precision), one **LOW
finding accepted** (emit_gated_hard awk-`-v`, id:c8db class). No new TODO/ROADMAP items.
No code/security/coherence defects left open. Suite 58/0.
