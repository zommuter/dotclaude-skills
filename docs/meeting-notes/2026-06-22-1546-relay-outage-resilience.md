# 2026-06-22 — Relay outage-resilience (id:98f0 + id:7809)

**Started:** 2026-06-22 15:46
**Session:** 5c8ae3a5-cc02-4157-9bb8-5d7289a097e4
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🛠️ Sven (systemd/OS-scheduler, new), 🎛️ Orla (relay-fleet orchestration, new)
**Topic:** Make the local relay loop survive a session/outage kill (id:98f0) and recover a dead run's leftovers automatically and safely on restart (id:7809).

## Surfaced discoveries / prior context
- `babysitter-durable-cron-no-op` (2026-06-22): three-way bind confirmed; `CronCreate durable:true` is a no-op locally; stopgap = in-session cron.
- `model-probe-tos-invocation-path` (id:2d01): a **dedicated OS user running subscription `claude -p` with an empty `~/.claude`** is already the ToS-cleared path for the model probe — precedent for the deferred heavy build.
- `relay-orphan-park-keep-ref` (id:a4e9): dead-run worktrees are parked (dir removed, branch ref kept → `relay/orphan/*`); refs ARE the registry; human runs `/relay reconcile`. id:7809 pushes the *safe* subset toward auto-integrate.
- Relay claim/lease heartbeat exists (id:0902) — the carrier chosen for the liveness marker.
- Design heuristics in play: *observe before preventing*, *constraint archaeology*, *pilot small-n conservatism*.

## Agenda
1. id:98f0 — outage-resilience path: heavy unattended infra now vs observe-first (watchdog + notify) vs accept stopgap?
2. id:7809 — auto-reconcile-on-restart: liveness marker design, safe-vs-judgment classifier conservatism, and entrypoint.
3. Build order, scope cuts, and the cheap immediate fixes (loop-hint nudge, upstream bug report).

## Discussion

### Agenda 1 — id:98f0 outage-resilience path
The bind is pick-two of {survives session kill, reaches local repos, no `--dangerously-skip-permissions`}. In-session mechanisms fail "survives kill"; cloud `/schedule` fails "reaches local"; an OS systemd `--user` timer firing `claude -p "/relay --afk"` gives both but hits the permission wall. Sub-paths to clear the wall: (a) curated allowlist (treadmill risk — any new relay tool silently re-introduces a hanging prompt); (b)/(c) dedicated sandboxed OS user (bounds the dangerous flag's blast radius but is a multi-session build incl. a repo-access bridge + keyring + git identity); (d′) a watchdog timer that does NOT run claude headless — detects a dead loop via the id:7809 heartbeat and notifies for one-tap restart, sidestepping the wall and doubling as the outage-frequency logger. Riku/Petra invoked *observe-before-preventing*: only one observed outage-death (2026-06-22), so the heavy unattended build is evidence-gated. Riku also noted id:2d01 cleared only the *ToS* of the dedicated-user path, not the hard repo-access bridge.

**→ DECISION 1 (user):** Build **(d′) watchdog + notify + observe-first**. Defer (a)/(b). The dedicated-OS-user path is **already tracked separately** (id:2d01) — cross-reference, do not re-mint. Ship the cheap fixes (nudge + upstream report) alongside.

### Agenda 2 — id:7809 auto-reconcile-on-restart
Today the loop parks dead-run worktrees (id:689c, refs-are-the-registry id:a4e9) but stops there. id:7809 auto-handles the *safe* subset and surfaces the rest. Sven: the watchdog (decision 1) and the reconcile need the *same* liveness signal — reuse the id:0902 claim heartbeat, don't mint a second source of truth that can disagree with the lease. Riku: "suite green ⇒ integrate" is gameable (zkm-stt id:c1aa was green only *after* the reviewer fixed a self-contradictory fixture); the headless auto-lane must clear the **same** bar as a human `/relay review` (mechanical `gaming-scan.sh` + no-test-weakening + full suite + clean tree + ledger/trivial diff) and default to SURFACE on any ambiguity or anything needing strong-model judgment. Orla: that makes the entrypoint a single code path — `/relay reconcile --auto`, loop-invoked at startup on stale heartbeat — not a forked startup hook that duplicates review logic.

**→ DECISION 2 (user, 3 parts):**
- **Marker:** extend the existing id:0902 claim/lease heartbeat (runId + `heartbeat_ts` + TTL); shared by the watchdog AND the reconcile. No `.relayactive` file.
- **Safe bar:** SAFE (auto-integrate) = clean tree + mechanical `gaming-scan.sh` pass + full suite green + ledger-only/trivial diff. ANY ambiguity, or anything needing strong-model judgment → JUDGMENT (parked + surfaced via REVIEW_ME / `/relay human`). Headless auto-lane never clears a weaker bar than a human review; conservative classifier defaults to JUDGMENT.
- **Entrypoint:** `/relay reconcile --auto` (one code path with the human reconcile; `--auto` gates auto-integrate of SAFE-only). The loop invokes it at startup on a stale heartbeat.

### Agenda 3 — build order, scope, cheap fixes
The heartbeat is the shared foundation (both the watchdog and `/relay reconcile --auto` read it), so it goes first; then the fully-local `/relay reconcile --auto`; then the watchdog+notify whose log becomes the evidence gate to revisit the deferred heavy build. Two cheap fixes ship independently. Sven: model the watchdog on the proven `quota-sample.timer` `--user` pattern, `make install-*`-able, notify channel configurable (PushNotification → notify-send fallback).

**→ DECISION 3 (user):** Build in order — (1) heartbeat liveness on the claim/lease, (2) `/relay reconcile --auto` (id:7809), (3) watchdog timer + notify (id:98f0). The watchdog log is the re-open gate for the deferred heavy unattended-infra build (xref id:2d01). Ship the two cheap fixes now, independently.

## Decisions
1. **id:98f0 outage-resilience = observe-first.** Build a watchdog: a systemd `--user` timer that detects a dead relay loop (via the shared heartbeat) and notifies for a one-tap restart — NOT a headless `claude -p`. It clears the permission wall entirely and logs every outage-death. The genuinely-unattended heavy paths (curated allowlist / dedicated sandboxed OS user) are **deferred behind the watchdog's outage-frequency evidence**; the dedicated-OS-user path is already tracked as id:2d01 (cross-reference, not re-minted). *Out of scope:* any `--dangerously-skip-permissions` use, the curated-allowlist treadmill, the new OS-user repo-access bridge — until evidence warrants.
2. **id:7809 auto-reconcile-on-restart.** (a) Liveness via the existing id:0902 claim/lease heartbeat (runId + `heartbeat_ts` + TTL); shared by watchdog + reconcile; no new marker file. (b) SAFE (auto-integrate) = clean tree + mechanical `gaming-scan.sh` pass + full suite green + ledger-only/trivial diff; ANY ambiguity or anything needing strong-model judgment → JUDGMENT (parked + surfaced via REVIEW_ME / `/relay human`); conservative classifier defaults to JUDGMENT; headless auto-lane never clears a weaker bar than a human `/relay review`. (c) Entrypoint = `/relay reconcile --auto` (one code path with the human reconcile), loop-invoked at startup on a stale heartbeat. *Out of scope:* blind auto-merge, weakening the review bar, a forked startup hook, strong-model judgment in the headless lane.
3. **Build order + cheap fixes.** Heartbeat → reconcile --auto → watchdog. Watchdog log gates the deferred-heavy-build re-open (id:2d01). Ship now, independent: fix the misleading `loop-hint.sh`/step-0a "unattended resilience" nudge; file the `CronCreate durable:true` no-op upstream.

## Action items
- [ ] **Heartbeat liveness on the relay claim/lease** — extend id:0902 to write runId + `heartbeat_ts` + a TTL, with a staleness check helper both the watchdog and reconcile consume. Contract: a test asserts a heartbeat older than TTL reads as "dead run", a fresh one as "alive". File: `relay/scripts/claim.sh` (+ a `relay/scripts/heartbeat.sh` or equivalent). Session 5c8ae3a5. <!-- id:e149 -->
- [ ] **id:7809 — `/relay reconcile --auto` + conservative safe-classifier** — loop-invoked at startup on stale heartbeat; SAFE = clean + mechanical gaming-scan + suite-green + ledger/trivial diff → auto-integrate; everything else → parked + surfaced. Same bar as a human review; defaults to JUDGMENT. Contract: a test feeds a green-but-gamed parked orphan and asserts it is SURFACED not integrated; a clean ledger-only orphan is auto-integrated. Files: `relay/` reconcile path + `relay-loop.js` startup. Session 5c8ae3a5. <!-- id:7809 -->
- [ ] **id:98f0 — watchdog timer + notify (observe-first)** — systemd `--user` timer (modelled on `quota-sample.timer`) reading the shared heartbeat; on a dead loop, notify (PushNotification → `notify-send` fallback, configurable) and log the event. `make install-*`-able. Contract: a test asserts a stale-heartbeat tick emits a notification + a log line; a live tick is silent. The log is the evidence gate to revisit the deferred heavy build (xref id:2d01). Files: `tools/relay-watchdog.{sh,service,timer}` + Makefile + a test. Session 5c8ae3a5. <!-- id:98f0 -->
- [ ] **Fix misleading loop-hint nudge** — `loop-hint.sh` / step-0a currently promises `/loop` gives "unattended resilience"; correct it to state `/loop`/cron dies with the session (only resilient to relay's own early-exit within a live session). Cheap, ship now. Files: `relay/` loop-hint. Session 5c8ae3a5. <!-- id:bde8 -->
- [ ] **File `CronCreate durable:true` no-op upstream** — report that `{durable:true, recurring:true}` returns `[session-only]` locally (the flag appears to be a no-op). Cheap, ship now. Session 5c8ae3a5. <!-- id:0994 -->

(Note: id:98f0 and id:7809 retain their tokens — the meeting resolved their design; they are now build items, retagged `[HARD — meeting]` → `[HARD — hands]` in ROADMAP since the meeting precondition is met.)
