# Strong-model audit — Run 34 (2026-06-22 07:12)

ROADMAP id:401c (recurring `[HARD — pool]`). Adversarial three-pass audit
(code review / security / design coherence) over the first-seen window since the
last audit.

## Window

- **Range**: `62b58fa..HEAD`, where `62b58fa` is Run 33's own audit merge and
  HEAD = checkpoint `relay-ckpt-20260622-0712` / `c95852b`.
- **Files touched**: `RELAY_LOG.md`, `ROADMAP.md`, `TODO.md` only.
- **Code files** (`git diff --name-only 62b58fa..HEAD -- '*.sh' '*.py' '*.js'`):
  **EMPTY** — LEDGER-ONLY window.
- **Substantive commits in window**:
  - `ca1e5f1` — id:7809 auto-reconcile-on-restart added; both id:7809 and id:98f0
    mirrored into ROADMAP under `[HARD — meeting]` lanes (single-id-two-views).
  - `31d854b` — id:98f0 durable-babysitter analysis corrected (cloud `/schedule`
    can't reach local repos; OS-timer hits the headless permission wall).
  - (plus the Run 33 checkpoint paragraph in RELAY_LOG.md.)

## Pass 1 — Code review

No `*.sh` / `*.py` / `*.js` changed in the window. **CLEAN by vacuity** — there is
no code, error handling, quoting, or race surface to review.

## Pass 2 — Security audit

No code, no new system-boundary input, no new file-permission assumption, no
secrets surface introduced. **CLEAN by vacuity.**

`gaming-scan.sh "$repo" 62b58fa` emitted nothing (no DELETED_TEST / ADDED_SKIP /
REMOVED_ASSERT) — the mechanical anti-gaming pass is clean.

## Pass 3 — Design coherence (substantive this run)

Two NEW open `[HARD — meeting]` items entered the ledger this window. Reviewed both
for sensibility, feasibility, and internal contradiction:

**id:7809 — auto-reconcile-on-restart.** A `.relayactive`/heartbeat marker plus a
TIERED safe-vs-judgment orphan classifier so a restarting loop auto-handles a dead
run's SAFE leftovers (clean / green / ledger-only → auto-integrate) and SURFACES the
judgment ones (BLOCKED / partial / red → strong turn / `/relay human`) rather than
needing a manual `/relay reconcile`. **Coherent**: the user's "do NOT over-automate"
nuance is preserved as the central design constraint (blind auto-merge of partial/red
work would push broken code to main); the zkm-stt fixture-contradiction case is cited
as live evidence the judgment tier is genuinely needed (the reviewer had to fix a
self-contradictory test fixture, not just merge). Correctly relates to id:689c
(orphan-park already runs on startup discovery — the gap is auto-INTEGRATE, not park),
id:3313/id:4e14 (reconcile + `--all`), id:0902 (the marker could extend the existing
claim heartbeat), id:98f0 (the durable-babysitter gap that makes dead runs common),
id:194e (failure ledger). No contradiction. Correctly routed `[HARD — meeting]` →
build only after a design pass.

**id:98f0 — outage-resilient LOCAL relay loop without `--dangerously-skip-permissions`.**
The user CORRECTED an earlier framing this window: cloud `/schedule` is NOT the
resilient answer because a cloud routine runs in Anthropic's cloud and physically
cannot reach local `~/src` repos, worktrees, or the fievel LAN remote. The only
mechanism that both survives a local session kill AND reaches local repos is an
OS-level scheduler (a user systemd timer — already used for `quota-sample.timer` — or
system cron) running `claude -p "/relay --afk"` per tick; but that hits the headless
permission wall, which the user will not bypass with `--dangerously-skip-permissions`.
**Coherent and now correctly framed as a genuine three-way bind** (in-session
mechanisms die with the session; cloud survives but can't reach local; local OS timer
reaches but is permission-walled). Options a–f are well-formed and non-overlapping
(broad allowlist / dedicated-OS-user scoped allowlist per id:2d01 / sandboxed
auto-approve / accept best-effort in-session cron / investigate `durable:true` no-op /
fix the misleading `loop-hint.sh` nudge). Ties correctly to id:2d01
(`model-probe-tos-invocation-path`, the dedicated-OS-user precedent), id:8602
(loop exit-reason channel), id:888a (no in-`/loop` marker). No contradiction.

Both items are `[HARD — meeting]` (design judgment required before build), matching
the id:78ff lane grammar, and were mirrored into both ROADMAP and TODO under the same
ids (single-id-two-views). No gate that can never fire; no contract rule contradicting
another.

### Coherence drifts fixed inline (recurring Run 4/8/17 class)

Two hand-maintained cross-ledger summary lines went stale when the two new HARD items
landed. Both fixed in this audit (no code change):

1. **TODO d5e0 summary** still read *"Relay: 3 open ROADMAP items, all HARD"* listing
   only 401c/3346/dba3 (+ de4e DEFERRED). The window added two open HARD (7809, 98f0)
   → corrected to **5 open executable HARD** with the full enumeration and lane tags.
2. **TODO id:401c MIRROR line** still read *"Latest ✓ Run 33"* → refreshed to this run
   (Run 34) with the verdict.

## Cross-ledger state (after inline fixes)

- **0 open ROUTINE.**
- **5 open executable HARD**: id:401c `[HARD — pool]` (this recurring audit), id:3346
  `[HARD — meeting]`, id:dba3 `[HARD — decision gate]`, id:7809 `[HARD — meeting]`,
  id:98f0 `[HARD — meeting]`.
- **1 DEFERRED non-executable**: id:de4e (distributed orchestrator, decided 2026-06-17).
- All five executable HARD ids are `[ ]` open in BOTH ROADMAP and TODO; d5e0 summary now
  agrees.

## Suite

`tests/run-tests.sh`: **80 passed, 0 failed, 0 expected-red** on a clean run. Both
pre-existing tracked flakes (id:16e9 `test_relay_claim_liveness.sh`, id:05e8
`test_git_lock_push_slash_branch.sh`) did NOT recur.

## Verdict

**CLEAN.** Code + security clean by vacuity (LEDGER-ONLY window). Design-coherence
pass found no contradiction in the two new `[HARD — meeting]` items and fixed two
recurring-class cross-ledger summary drifts inline. No new TODO/ROADMAP follow-on
items minted (no defect, no accepted-risk requiring tracking). Suite 80/0.
