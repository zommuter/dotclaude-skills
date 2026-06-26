# Strong-model audit — Run 68 (2026-06-26-0926)

**Item:** ROADMAP id:401c (recurring `[HARD — pool]` strong-model audit).
**Window:** `5e1a216..HEAD` (HEAD `8d8d40b`) — everything since Run 67 (2026-06-23-2145).
The first NON-ledger window since Run 48: ~4091 insertions / 50 deletions across 35 files
(14 scripts + 21 test files), three days of relay engine work. `substantive_unaudited=true`
(audit ref = `last_strong_ckpt`; commits `6ca4bff` feat(5c00) + the rest are real).

Scope audited (the new/changed engine surface):
`acquire-resource.sh`, `commit-ledger.sh`, `scan-routed.sh`, `todo-conformance.sh`,
`unpromoted-scan.sh`, `relay-doctor.sh`, `lint-workflow-templates.mjs`, `pool-args.mjs`,
`redispatch-guard.mjs`, the `relay-loop.js` additions (id:5c00 quota pre-gate, id:c012
graceful stop, id:d530 --priority/--exclude, id:9973 HARD-pool demote-guard, id:365b
re-dispatch circuit breaker + substantive_unaudited/work_sig wiring, id:a707 human-gated
INTENSIVE carve-out), `gather-repo-state.sh` (substantive_unaudited / work_sig /
open_hard_pool), `claim.sh` (id:1b11 PID-liveness), `orphan-scan.sh` (id:9221 first-wins),
`roadmap-lint.sh` + `todo-conformance` (id:c095 heading-as-item), and the
`todo-conversion-policies.md` v1 playbook (5974007).

## Pass 1 — code review: CLEAN (no correctness defects)

Reviewed every new script line-by-line. The work is uniformly high quality, defensive, and
heavily tested (suite 107, see below). Spot-confirmed the load-bearing invariants:

- **`commit-ledger.sh`** — scoped `git add -- <rel>` only, never `git add -A` (id:debf); each
  path resolved via `realpath -m --relative-to` with an explicit `../*|/*` escape reject;
  flock on `.git-lock-push.lock`; clean no-op when nothing staged; commit-only (never pushes,
  never stash/reset/checkout — id:aa93). The atomic-ledger guarantee holds.
- **`todo-conformance.sh --fix`** — appends a minted id only to `missing-id` lines; line
  numbers are stable (append-to-EOL never reflows), re-reads each line under flock before
  editing, and SKIPS any line bearing a non-canonical inline `id:XXXX` (the duplicate-mint
  guard). Minted token is validated `^[0-9a-f]{4}$` before reaching `sed` — no sed-injection.
- **`gather-repo-state.sh`** — `substantive_unaudited` is genuinely FAIL-OPEN (stays true
  unless the audit ref resolves AND every commit is a `relay:/fable: checkpoint` or uv.lock-only);
  `nonckpt_shas` is `sort`-ed so `work_sig` is deterministic and stable across the pool's own
  checkpoint churn (checkpoints are excluded from the hash input). `open_hard_pool` correctly
  excludes a `relay:recurring-audit` item when `substantive_unaudited=false`.
- **`relay-loop.js` guards** — the id:9973 demote-guard and id:365b circuit breaker are both
  DEMOTE-ONLY, injected-exempt, and run after the merge; the breaker dispatches on counts 1-3
  and suppresses at 4 (`count > 3`). The id:5c00 quota pre-gate early-returns before the shard
  fan-out and relies on `quotaStopped` to break the outer loop. The inline copies are
  byte-equivalent to `pool-args.mjs` / `redispatch-guard.mjs` (structural test pins it).
- **`lint-workflow-templates.mjs`** — a real single-pass character lexer (code / line / block /
  sq / dq / tmpl / regex states with `${…}` nesting), flags ONLY an unescaped backtick in
  template content glued to a following word char (the `` `hard`` desync signature). No
  false-positive path on a legitimate close (always followed by a non-word char), an escaped
  `` \` ``, or a backtick inside a comment/string. col tracking is diagnostic-only.

## Pass 2 — security audit: CLEAN

Injection / boundary surfaces checked:
- **Command/sed injection** — minted ids validated to 4-hex before `sed -i`; no user string
  reaches a shell eval.
- **Path traversal** — `commit-ledger.sh` rejects any ledger path escaping the repo root via
  the normalized `../*|/*` check; `scan-routed.sh` / `unpromoted-scan.sh` resolve repo paths
  only from relay.toml `own` blocks (tomllib parse), never from inbox content.
- **jq** — claim JSON is built with `jq -n --arg` (no inline interpolation); `live_pid` read
  back with `jq -r '.live_pid // ""'`.
- **PID liveness (`claim.sh`)** — `pid_alive` guards numeric-only (`*[!0-9]*` reject) before
  `kill -0`; keyed on the DEDICATED `live_pid` field so non-`--pid` callers are unaffected.
  The PID-reuse caveat is documented and CONSERVATIVE (a recycled pid only ever EXTENDS a
  claim → at worst the relay defers an intensive unit it needn't have; never a data-loss or
  steal-while-live hazard). Acceptable.
- No secrets, no world-writable assumptions, no `2>/dev/null` that swallows a real failure
  (the few `|| true` are on logging / best-effort cleanup, consistent with id:4e14).

## Pass 3 — design coherence: ONE drift FIXED INLINE

- **FIXED — cross-ledger drift id:5c00.** `orphan-scan.sh --cross-ledger` flagged
  `id:5c00 — TODO:[ ] ROADMAP:[x]`. The quota PRE-GATE work is genuinely done and merged
  (the early-return is in `runRound()`, `test_relay_loop_structure.sh` carries the ordering
  assertions, suite green), so the ROADMAP `[x]` is authoritative; the TODO twin had not been
  ticked. Ticked TODO id:5c00 → `[x]`. `orphan-scan --cross-ledger` now exits 0 clean.
- **Coherent — `todo-conversion-policies.md` v1.** The new playbook (P1 non-canonical ids /
  P2 stale-dup / P3 relocate-by-type / P4 status-as-task + "flag, don't guess" residual +
  mechanical-vs-judgment split) is internally consistent and matches the detector's
  `missing-id`/`orphan` classes. No contradiction with `todo-conformance.sh` or handoff C2.
- **Coherent — the new guard family.** id:9973 (demote) ↔ id:365b (recurring-audit gate +
  circuit breaker) ↔ id:a707 (human-gated INTENSIVE carve-out) ↔ id:000d (is_finished) form a
  consistent DEMOTE/PROMOTE backstop lattice; each is injected-exempt and demote-only where it
  must be. No gate that can never fire, no rule contradicting another.

## Accepted (not a defect)

- **gaming-scan `ADDED_SKIP:tests/test_relay_doctor_wiring.sh:60`** — benign false-positive.
  Line 60 is a real assertion `grep -qiE 'never a hard block|report.only|never.*block'`
  verifying that `review.md` documents the relay-doctor sub-step as report-only; the regex
  substring `report.only` tripped the ADDED_SKIP heuristic. It is not a gamed test-skip.
  gaming-scan exits 0 (informational).

## Verification

- `tests/run-tests.sh`: 106 passed / 1 failed / 0 expected-red. The lone failure is the
  KNOWN flaky `test_resource_claim_pid.sh` (id:ab5c) — passed 3/3 in isolation; the suite is
  effectively green (107).
- `roadmap-lint.sh "$PWD"` exit 0; `todo-conformance.sh TODO.md` exit 0;
  `orphan-scan.sh --cross-ledger "$PWD"` exit 0 (after the id:5c00 fix);
  `gaming-scan.sh "$PWD" 5e1a216` exit 0.

**Verdict:** the three-day relay-engine batch is clean — no code or security defects, one
cross-ledger coherence drift fixed inline. No finding silently dropped.
