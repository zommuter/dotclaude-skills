# Strong-model audit — Run 72 (id:401c)

- **When**: 2026-08-12-1413
- **Window**: `0454e8f..HEAD` (HEAD `1b7e9bb`) — first-seen code since Run 71's own audit
  commit (`0454e8f`, the 2026-08-11-2145 pass). 72 commits; ~780 lines of production code
  across 10 scripts + 12 new test files + 2 fixtures (1954 lines total by `--stat`).
- **Model / lane**: Opus-apex HARD-execute child (id:da26), `/relay` pool.
- **Suite**: `make test` → **394 passed / 0 failed / 1 expected-red** on the committed tree.

The window is the L-wave / mechanical-proxy hardening batch that landed 2026-08-11 evening →
2026-08-12 midday: the routed:a923 injection-scope fix, id:76d2/66d9 provisioning
self-verify + gitignore, id:9e48 proxy-currency check, id:93ac command-fence precedence,
id:06a1/3222/a104 hop-failure visibility, id:ed3f lint coverage, and the verify-isolation
`|| true` fix.

## Pass 1 — Code review

**Verdict: clean. No inline fix needed.** Every production diff is well-reasoned and
correct at a high bar. Notable checks:

- `provision-worktree.sh` (id:76d2/66d9): the `info/exclude` write resolves the target via
  `git rev-parse --git-path info/exclude` (correct — in a linked worktree `<wt>/.git` is a
  file and the per-worktree `info/exclude` is not honoured by git; the repo-common file is
  the only working target, matching the in-code VERIFIED note). Idempotent (grep -qxF before
  append), trailing-newline-safe before glue, and the closing `PROVISION-OK <resolved>` token
  is emitted only after both postconditions (worktree registered + branch exists) pass — a
  genuine fail-closed certificate the filesystem-less parent can gate on. The two `|| true`
  symlink lines are correctly scoped and documented as deliberate.
- `verify-isolation.sh`: the added `|| true` on the `symbolic-ref -q | sed` fallback is a
  real bug fix, not decoration — under `set -o pipefail` + `set -e` the `-q` exit-1 on a
  missing `origin/HEAD` killed the whole gate with empty output on every hermetic fixture.
  `base="${default_branch:-main}"` degrades correctly to `main`. Reproduced-before-fixing per
  the in-code note; covered first by `test_provision_symlink_ignored_76d2.sh`.
- `mech-currency.sh` (NEW, id:9e48): fail-closed on every unknown (missing/malformed state
  file, dead pid, undeterminable source digest). Liveness is `kill -0 OR /proc` — correct for
  the tiered-OS-user case where `kill -0` returns EPERM cross-user. The source digest is
  obtained by importing `mechanical-proxy.py` and calling its own `allowlist_digest()` — one
  implementation of the predicate, which is the right call (a second hand-rolled digest is
  exactly the drift that reopens the id:9e48 bug class). Import is side-effect-free (state
  written from `main()` only), so the check cannot clobber the file it inspects.
- `inject.sh` peek/take `--repo` scoping (routed:a923): `in_scope()` uses `jq -r '.repo //
  ""'`, exact-match, unscoped ⇒ pass-through. `take` skips (never consumes) out-of-scope
  shards under the same flock; the log line reports `consumed=N left-pending=M`. Single call
  site preserved.
- `gather-repo-state.sh` (id:1022): typed `gated-on:` edges routed through the shared
  `resolve-gates.sh` → `lib-typed-edges.sh` engine (no second inline parser), fail-open if
  the resolver cannot run, stderr not swallowed. Correct.
- `relay-loop.js` (+270): the largest surface, but **all changes are visibility / scope /
  documentation — no hop's control flow changes.** `recordAgentFailure` truncates the reason
  to 200 chars and collapses whitespace (RELAY_STATUS.md cannot be blown up by a multi-KB
  model error body); `dispatchGuarded` records both failure shapes (reject AND null/empty)
  and never rethrows; `enforceInjectScope` is a loud, recoverable backstop; the `agentFailures`
  accumulator is snapshotted (id:8c85 class) and rendered as its own section only when
  non-empty (no id:8c85 cry-wolf). The review-child prompt's `unit.path` → `wt` change points
  `append.sh new-ids` at the child's worktree instead of the main checkout — `wt =
  worktreePathFor(unit)` is defined at the top of the same function (no TDZ), and the change
  is consistent with worktree isolation.
- `lint-mech-model.mjs` (id:ed3f): `AGENT_CALL_IDENTIFIERS` now also matches the guarded
  wrappers (`dispatchGuarded`/`agentGuarded`/`safeAgent`), closing the coverage gap that
  moving `releaseLease`'s fence dispatch out of a bare `agent(` call opened. Same lexer shape;
  the substring search for the fence marker + `model:` property is argument-order-agnostic.

## Pass 2 — Security

**Verdict: clean.** Two security-relevant changes, both correctly fail-closed:

- **`mechanical-proxy.py` command-fence precedence (id:93ac)** — `_strip_stdin_fence_span`
  excises the first `relay-mech-stdin` payload span BEFORE `_command_from_wrapped` searches
  for the command fence, so a payload that merely QUOTES a ```relay-mech block (ordinary
  content — this repo's own ROADMAP/SKILL carry literal such fences) can no longer SUPPLY the
  dispatched command. Verified the asymmetric-parse reasoning by hand: the non-greedy stdin
  capture stops at the inner opener's backticks, leaving the remainder starting `relay-mech\n…`
  (no leading backticks), which `_MECH_FENCE_RE` cannot re-match. In the no-legit-command
  attack shape it falls through to returning the whole wrapped text as a bare command, which
  `_command_allowed()` then refuses. Covered by `test_mech_command_precedence_93ac.sh` (177L).
- **`INJECT_SCOPE` shell splice (routed:a923)** — `ONLY_REPO` is validated against
  `/^[A-Za-z0-9._-]+$/` before it is spliced into the `ONLY_REPO=… discover-prelude.sh` mech
  command; anything outside that class becomes the sentinel `__unresolvable-scope__` (also
  splice-safe) which matches no repo — fail-closed, no shell injection, no global-drain
  fallback.
- `mech-currency.sh` reads only the state file + proxy source; no writes, no network; the
  state file is written atomically via `os.replace` (a reader never sees a half-write).
  `write_state_file` catches only `OSError` and is best-effort (a proxy that cannot publish
  state is correctly reported STALE downstream).

No injection (command / path / jq), no secrets exposure, no traversal, no unvalidated
system-boundary input found in the window.

## Pass 3 — Design coherence

`roadmap-lint.sh --strict` reports 9 open-item violations. Adjudicated:

- **NEW in this window (worth surfacing):** archiving id:33b2 and id:93ac (both BUILT this
  window — the stdin channel and the command-fence-precedence fix, audited clean in Run 71
  and here) left stale `gated-on:33b2` / `gated-on:93ac` markers on their dependents
  **id:d4ca** (`write-relay-status: haiku → model:'bash'`) and **id:e405** (convert the two
  payload-trapped haiku hops). Because the archived targets resolve nowhere, the lint reads
  the gates as DEAD (permanent-block). The technical gates are in fact SATISFIED, so the
  markers should be cleared — **but this is explicitly NOT an inline fix for an audit child**:
  (1) naively clearing d4ca's markers unblocks it into pool dispatch, while `id:09e4` (filed
  Run 71) documents that the id:33b2 stdin channel silently MISDIRECTS its payload on a
  non-leading pipeline stage — `write-relay-status`'s payload is exactly the cross-repo ledger
  prose that rides that channel, so converting it before 09e4 is resolved is premature; (2) the
  whole id:6b35 cluster is owner-gated on `id:b0b1` (the `/remote-control` no-`ANTHROPIC_BASE_URL`
  conflict), and re-targeting its gates is the owner's / next-handoff's call, not a quiet
  audit-time ledger edit on a repo with active relay churn (a reviewer checkpointed this repo
  at 13:53 today). **Disposition: TRACKED** — deterministically re-surfaced every review by
  `roadmap-lint` (id:49e0), and recorded here with the reasoning. Recommended action for the
  next `/relay handoff`: retype d4ca/e405 gates from the now-satisfied `gated-on:33b2,93ac`
  to the real remaining gate (`gated-on:b0b1` + the 09e4 dependency for d4ca), so the lint
  stops reading them as dead and the owner gate is the one visible blocker.
- **Pre-existing lint debt (NOT this window's defects):** `id:2b49` gated-on retired `id:ac7f`
  (last touched 2026-07-20); `id:ae08` DECOMPOSED-CONTAINER (its own handback-followup already
  names seams id:02b2/99e5/5b12 and it carries route:hard-split — the parent needs an
  `@container` marker or a tick); `id:1b13` NO-ACCEPTANCE-NO-TWIN (an `[INPUT — decision]`
  design question with no body clause). All three are the lint's standing backstop debt, not
  introduced in `0454e8f..HEAD`; noted, not actioned here.
- **`id:540f` / `id:c179`** DEAD-GATE on `id:e62c`/`id:b0b1` is a FALSE-positive-shaped but
  CORRECT state: both are owner-gated TODO-only items deliberately kept out of the execution
  queue by owner directive (2026-07-31) — the gate "can never open from ROADMAP" is the point
  (the owner opens it). No action; accepted with rationale.

**New TODO items filed in-window** (795d, 4d6b, b724, af56, 151c, 7703, 83c2, plus the
INBOUND cross-project routes) are problem-reports / evidence items, not design decisions
needing a wrong-cut check. They are internally consistent; 795d/4d6b/b724/af56 form a coherent
cluster of related classify-verdict/classify-repo dispatch-predicate findings (reason-string
vs decision predicate, raw-vs-gate-resolved counts, unanchored `blocked` substring, HARD
starved behind ROUTINE) — related, not contradictory. No coherence defect among them.

## Summary

Clean code + clean security across the ~780-line mechanical-proxy/provisioning hardening
window; one tracked design-coherence finding (stale `gated-on:33b2,93ac` markers on d4ca/e405
after their targets were built+archived this window — recommend the next handoff re-target to
the real owner gate `b0b1`, NOT cleared inline because that would unblock d4ca into dispatch
ahead of the unresolved id:09e4 payload-misdirection). Suite 394/0/1-xred. No finding silently
dropped.
