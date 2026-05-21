# 2026-05-21 — meeting-live broker: global daemon, opt-in spawn, AI-M4 closure

**Started:** 2026-05-21 10:07
**Session:** e19c54b1-76ab-4abd-a2f5-bde8e10c981b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🌐 Polly (PWA/multi-client — re-onboarded; broker-as-multi-client-substrate is her lens)
**Topic:** AI-M4 closure; whether to keep per-meeting auto-spawn or move to a global fixed-port broker daemon routed by Claude session id; opt-in vs opt-out spawn policy.

## Agenda
1. AI-M4 closure — does the no-listener pilot complete it, or are MEETING_LIVE=0 opt-out + mid-meeting listener toggle still owed?
2. Broker topology — per-meeting ephemeral-port spawn (current) vs single global fixed-port daemon routed by Claude session id.
3. Spawn trigger / opt-in vs opt-out — auto-ensure, explicit opt-in, or lazy-connect only.

## Discussion

### Agenda 1 — AI-M4 closure

The no-listener Class 3 run exercised clause (a): broker up, subscribers=0 → AskUserQuestion fallback (γ-table "Broker up, subscribers=0" row, SKILL.md:97). AI-M4 has a second clause: MEETING_LIVE=0 opt-out path (step 7 skip, all-chat). That path was NOT exercised by the no-listener run — the user let the broker spawn and fall back; MEETING_LIVE=0 is a different code path.

During the meeting the user ran MEETING_LIVE=0 and confirmed the opt-out path works. **Decision: AI-M4 complete.** Both clauses verified live.

Mid-meeting listener toggle (start/stop between decision points) is NOT in AI-M4's contract. Deferred as AI-M5 — test after topology ships, since topology changes the daemon model. Note (Riku): the "10s" estimate for a confirming run was wrong — /meeting-live startup is minute-range, not 10s.

### Agenda 2 — Broker topology

**Key finding pre-meeting:** broker.py is already session-keyed (`get_session(sid)` :14; POST reads `session` from body :37; GET from query :59). broker-curl.sh never sends `session`, so routing is dormant (all calls hit `sid=""`). The global daemon the user imagined is exactly what broker.py was written for; the per-meeting spawn leaves the routing as dead code.

**Framing correction (Riku):** ephemeral ports (bind 0) never collide — the OS guarantees a free port each time. The real costs of the per-meeting model are: N broker processes, renderer can't predict the port (must read per-session broker.json), and minute-range spawn+poll each meeting. The motivation "parallel meetings blocking multiple ports" was imprecise; the redesign case is process-count + renderer predictability + multi-client substrate.

**Decision: one global fixed-port daemon, routed by Claude session id.** Three-file change:
1. broker.py — bind `MEETING_BROKER_PORT` (default 64109); on bind-fail, `/status`-probe to discriminate our-daemon (success) vs stranger (fall back to ephemeral); write actual port to global `/tmp/meeting-rpg/broker.json`; idle self-shutdown (gated by `MEETING_BROKER_IDLE`, default on).
2. broker-curl.sh — add a session argument; forward as `session` in POST body and `?session=` in GET query. This activates the dormant routing.
3. meeting-live/SKILL.md — replace per-meeting spawn with lazy-connect + opt-in self-start (see Agenda 3).

Lifecycle resolved: skill starts the daemon on demand (never frozen waiting on an absent coordinator — 2026-05-20 dependency-ownership decision honoured); daemon owns its own teardown via idle self-shutdown (no immortal orphan). N=2 consumers (meeting-live + meeting-rpg) clear Petra's N=2 bar; the routing code already exists, so this is activation, not new infrastructure.

**Port: 64109** = `0x7A6D ('zm') | 0x8000 = 0xFA6D`. Derivation: ASCII 'z'=122, 'm'=109 → 0x7A6D = 31341 (literal "zm"), with the high bit set to land in the IANA dynamic range (49152–65535) AND above this machine's ephemeral ceiling (32768–60999). 31341 itself is below the ephemeral floor here but sits in the registered/User range and is less portable-safe on machines with a lower ephemeral floor. 64109 satisfies: IANA-dynamic, above the default Linux ephemeral ceiling of 60999, unregistered, portable. No service registered to it. Configurable via `MEETING_BROKER_PORT`.

### Agenda 3 — Spawn trigger

Live mode was always subscriber-gated (subscribers=0 ≡ canonical /meeting per γ-table). The MEETING_LIVE opt-out only governed daemon-process existence + URL advertisement, not meeting behaviour.

The 2026-05-20 "skill self-hosts broker" decision (avoid freeze on absent coordinator) is neutralised by the γ-branch fallback: an absent daemon falls back to AskUserQuestion, not a freeze. So auto-start is safe to make optional.

**Decision: lazy-connect by default + opt-in self-start (MEETING_LIVE inverted to opt-in).**
- Bare `/meeting-live`: reads global broker.json; if a daemon is up (port responds to `/status`) with subscribers → live mode; else canonical AskUserQuestion. **Never launches a process.**
- `MEETING_LIVE=1` (unset/`0` = off): skill self-starts the daemon idempotently, advertises `…/events?session=<sid>`, enables live branching.

Ephemeral fallback: global `/tmp/meeting-rpg/broker.json` is the ground truth for the actual port. Clients read the file; 64109 is the preferred-bind and documented default for external clients. `MEETING_BROKER_PORT` env (default 64109) is the single knob for daemon, systemd unit, and Caddy proxy config.

systemd --user unit: bundled in this ship as an optional always-on path. `meeting-broker.service` + README snippet. `MEETING_BROKER_IDLE=0` disables idle-shutdown when systemd-managed. Lazy-connect + self-start work with zero systemd.

Cross-repo (user-directed): meeting-rpg should launch the broker on its startup and keep it alive (game = renderer host = natural daemon owner). meeting-live invoked from the game lazy-connects. TODO filed in meeting-rpg.

## Decisions
- **AI-M4 complete** — both contract clauses verified live. Out of scope: mid-meeting listener toggle (now AI-M5, pending global-daemon ship).
- **Topology: one global fixed-port broker daemon at 64109, session-routed.** Activates dormant routing in broker.py. Out of scope: 0.0.0.0 / multi-machine bind — daemon stays 127.0.0.1, remote reach via Caddy/Cloudflared unchanged.
- **Port 64109** (`0x7A6D | 0x8000 = 0xFA6D`). IANA-dynamic, above default ephemeral ceiling, unregistered, portable. Configurable via `MEETING_BROKER_PORT`.
- **Spawn: lazy-connect default + opt-in self-start** (`MEETING_LIVE` inverted: `=1` enables, unset/`0` = off). Bare invocation never launches a process. Out of scope: auto-ensure/opt-out (the behaviour the user disliked).
- **Discovery file is ground truth** for the actual bound port; bind-fail discrimination tells our-daemon from stranger.
- **systemd --user unit bundled** with `MEETING_BROKER_IDLE` knob.
- **meeting-rpg owns daemon lifecycle** in the game context; meeting-live lazy-connects from there.

## Action items
- [ ] **broker.py** (`~/src/dotclaude-skills/meeting/broker.py`) — bind `MEETING_BROKER_PORT` (default 64109) instead of port 0; bind-fail discriminates our-daemon vs stranger via `/status`-probe; write actual port to global `/tmp/meeting-rpg/broker.json`; idle self-shutdown gated by `MEETING_BROKER_IDLE`. Contract: two concurrent sessions share one daemon; `GET /status?session=<sid>` returns that session's subscriber count. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
- [ ] **broker-curl.sh** (`~/src/dotclaude-skills/meeting/broker-curl.sh`) — add session argument; forward as `session` in POST body and `?session=` in GET query. Contract: session A calls never reach session B subscribers. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
- [ ] **meeting-live/SKILL.md** (`~/src/dotclaude-skills/meeting-live/SKILL.md`) — replace step-7 per-meeting spawn with lazy-connect + `MEETING_LIVE=1` opt-in self-start; pass session id on every call; advertise `…/events?session=<sid>` (self-start path only); document inverted semantics + `MEETING_BROKER_PORT`/`MEETING_BROKER_IDLE`. Contract: bare invocation with no daemon ≡ canonical /meeting; `MEETING_LIVE=1` ensures daemon + advertises. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
- [ ] **meeting-broker.service** + README (`~/src/dotclaude-skills/meeting/`) — systemd --user unit; `MEETING_BROKER_IDLE=0`; documents `MEETING_BROKER_PORT`. Contract: `systemctl --user start meeting-broker` → daemon on 64109, lazy-connect works. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
- [ ] **AI-M5** — once global daemon ships, pilot mid-meeting listener toggle: attach/detach subscriber between decision points; confirm live↔AskUserQuestion flip per the per-decision /status re-poll. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
- [ ] **meeting-rpg broker lifecycle** (`~/src/meeting-rpg/TODO.md`) — meeting-rpg launches broker.py on startup (idempotent, port 64109) and keeps it alive; meeting-live lazy-connects. See: `docs/meeting-notes/2026-05-21-1007-meeting-live-broker-global-daemon.md`.
