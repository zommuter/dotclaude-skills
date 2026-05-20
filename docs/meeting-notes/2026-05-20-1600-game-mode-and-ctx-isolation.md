# 2026-05-20 — `/meeting` game-mode + chat-context isolation

**Started:** 2026-05-20 16:00
**Session:** 83430b39-002a-4adc-8c0f-5168fe5548f5
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Add game-mode hook to `/meeting` so meeting-rpg renderer can drive the discussion via HTTP broker; decide whether the chat-context-bloat problem deserves an independent fix using the same IPC even with no game attached.

## Agenda
1. Are these one decision or two? — game-mode and ctx-isolation may be coupled or orthogonal.
2. What is the trigger surface and minimum mechanism for game mode on the `/meeting` skill side?
3. What does the plan-file (and chat output) do under game mode vs. headless ctx-isolation?
4. VN-terminal as parallel architecture: competing or complementary?
5. MVP scope + action items.

## Discussion

### Agenda 1 — One decision or two?

🏗️ **Archie:** Mechanically they share the same primitive: replace "print transcript + AskUserQuestion" with "POST to broker + long-poll GET." Game mode = a renderer consumes the events. Headless ctx-isolation = nothing consumes the events (or `tail -f` consumes them locally), but the chat output collapses regardless. The savings come from *not re-including the verbatim transcript in subsequent turn inputs*, not from the renderer existing.

⚙️ **Sage:** Confirmed by the prior meeting note: "If the game UI provides the visual transcript, the transcript-first-reading requirement is fulfilled *outside the chat*, and the chat can collapse to a one-liner." The visual side is one consumer; `cat /tmp/meeting-rpg/<sid>/transcript.jsonl` is another. Same emit path.

😈 **Riku:** What breaks if we treat them as one? The transcript-first-reading rule is a *user behavioural requirement* — Tobias has corrected the skill twice for skipping it (profile entry, high confidence). If headless ctx-isolation collapses chat to a one-liner with no renderer running, the requirement is structurally unmet. We need a fallback the user actually reads before answering.

✂️ **Petra:** N=2 check: game-mode has one consumer (meeting-rpg, still pre-MVP). Headless-mode has one consumer (the chat-context budget). If both ship together as one mechanism with two front-ends, that *is* N=2 for the shared broker. If only one ships, we're building infra for a hypothetical.

🏗️ **Archie:** Practical coupling: the meeting-rpg MVP-Live action item already needs the `/meeting` skill modified to talk to the broker. The marginal cost of also exposing a "no-renderer" mode is one env var check and a fallback printer — a few lines.

😈 **Riku:** Then the real question is *what does the no-renderer fallback do to satisfy transcript-first-reading*.

⚙️ **Sage:** Three plausible no-renderer fallbacks: (i) skill still prints to chat (zero savings); (ii) skill writes to plan file only (plan file isn't shown in chat UI); (iii) skill writes to a local file the user `tail -f`s. Only (iii) preserves the requirement without losing the budget win.

**A1 — Zommuter: one mechanism, two front-ends.** Shared broker IPC; renderer and `tail -f`-style local consumer subscribe to the same event stream. Petra's N=2 satisfied by the two front-ends.

### Agenda 2 — Trigger surface and minimum mechanism

🏗️ **Archie:** Three trigger surfaces. (α) Env var `MEETING_RPG_MODE=1`; skill checks in setup and switches behaviour. (β) Sibling `/meeting-rpg` skill with copy-pasted SKILL.md. (γ) Detect a running broker on `/tmp/meeting-rpg/<sid>/broker.json` and auto-switch. (α) is one if-check; (γ) is fragile (broker spawn timing race); (β) duplicates 200 lines of spec.

⚙️ **Sage:** α aligns with meeting-rpg's `claude --env MEETING_RPG_MODE=1` action item. (β) is the [[meta-skill-isolation-instinct]] pattern Tobias raised for cross-project — but here the *context* loaded is essentially identical (same personas, same agenda flow), only the IO path differs. No context-bleed risk; β looks over-isolated.

😈 **Riku:** What breaks under α? If the env var is set but no broker is reachable, Tobias sits frozen at AskUserQuestion. Either (1) launcher discipline (meeting-rpg launcher spawns broker before `claude`), (2) skill probes broker.json and falls back to normal mode, or (3) skill fails loudly. (2) is friendliest for headless: env var becomes `MEETING_IPC_MODE=1` (renderer-agnostic), broker presence determines whether a renderer is attached.

✂️ **Petra:** Minimum mechanism: (1) setup-step check for env var + broker.json + port reachable; (2) replace print+AskUserQuestion with POST /question, GET /await; (3) each persona line POSTs /event; (4) plan file: keep writing; (5) chat output: one-liner per agenda or silent.

🏗️ **Archie:** Steps 1–4 uncontroversial. Step 5 (chat output volume) is the load-bearing knob.

😈 **Riku:** Failure modes: (a) chat-collapse so aggressive the user has no idea what happened; (b) chat-print so verbose we lose the savings. One-line decision summary per agenda is reversible and gives an audit trail without re-broadcasting the discussion.

⚙️ **Sage:** AskUserQuestion is the mechanical harness handshake. Replacing with broker round-trip means decision-point markers are skill-managed, not harness-managed. Worth noting; not a blocker.

**A2 — Zommuter:** env var + auto-fallback, **refined: the skill itself hosts the HTTP server.** No external-broker dependency: skill spawns a minimal Python HTTP+SSE server, advertises the URL as a clickable terminal link at meeting start. Dissolves the broker-absent fallback question entirely. Chat prints one-liner per agenda decision.

### Agenda 3 — Self-hosted server lifecycle, plan-file role, activation policy

🏗️ **Archie:** Lifecycle: spawn at setup via `python3 broker.py --session $SID --port 0`; broker prints chosen port and long-runs. Print one chat line advertising clickable OSC-8 hyperlink. Cleanup at end-of-meeting via `/shutdown` POST.

😈 **Riku:** Failure modes — (a) port-collision on advertise path (mitigated by `$CLAUDE_SESSION_ID`); (b) leakage on harness crash (mitigate with 30-min idle timeout in broker); (c) load-bearing portability question: can the harness keep a background daemon alive across Bash tool boundaries?

⚙️ **Sage:** Resolved cleanly: Bash tool's `run_in_background=true` is the supported path for long-running processes — survives across tool calls within a session, harness tracks the pid. Cleaner than `nohup ... & disown`.

✂️ **Petra:** Plan-file role: (P1) keep writing, broker is additive; (P2) replace with broker-managed state; (P3) hybrid tee (≡ P1 in practice). P1 = harness-managed plan file is the safety net.

🏗️ **Archie:** Prefer P1 — if broker dies the meeting note is still reconstructable. Extra cost = one curl per chunk; marginal.

😈 **Riku:** Activation options: (T1) always-on; (T2) opt-in `MEETING_LIVE=1`; (T3) opt-out `MEETING_LIVE=0` (default on, escape hatch). T3 matches empirical-pilot-by-default.

⚙️ **Sage:** [[empirical-pilot-preference]] + [[resource-gating-fluency]] point at T3.

**A3 — Zommuter:** (1) P1; (2) T3 (opt-out); (3) yes to daemon-survival probe before committing broker.py. Plus new forward-flag: **what about a custom VN-rendering terminal emulator?**

### Agenda 4 — VN-terminal vs. HTTP-broker: competing or complementary?

🏗️ **Archie:** Different problems. HTTP-broker solves ctx-budget — discussion bytes go to a side-channel, never on stdout. VN-terminal solves rendering — same bytes still on stdout, terminal just *displays* them as VN. Harness re-feeds whatever Claude emitted. **VN-terminal alone does not reduce token budget.**

😈 **Riku:** A "filtering terminal" can't help either — the harness owns the pty bytestream, not the terminal.

⚙️ **Sage:** Confirmed by Claude Code internals. The only way to keep bytes out of next turn is to not emit them in the first place — exactly what broker mode does.

✂️ **Petra:** Verdict: VN-terminal is **complementary** — a candidate renderer alongside Ren'Py / Tauri / Textual (closest analogue: `wt/renderer-textual` in meeting-rpg). Forward-flag, don't block MVP.

🏗️ **Archie:** Adds: if Tobias runs `claude` *inside* a VN-rendering terminal, that terminal IS the renderer (reads from broker via local socket). Broker + VN-terminal compose.

**A4 — Zommuter:** VN-terminal as complementary renderer + forward-flag. **Sequencing decision: wait for broker.py results from meeting-rpg's `wt/ipc-preflight` worktree** (currently in progress) before committing the broker integration on this skill's side.

### Agenda 5 — MVP scope

Given A4's wait-for-ipc-preflight sequencing, this skill's MVP is **the integration spec, not the broker itself**. Once meeting-rpg's broker.py validates daemon-survival via `run_in_background=true`, port discovery, and curl long-poll, the skill side is a SKILL.md edit + minor tooling.

## Decisions

- **D1 — Scope frame:** Game-mode and headless ctx-isolation are one mechanism with two front-ends (renderer subscribes / `tail -f`/browser subscribes). Out of scope: separate mechanisms.
- **D2 — Trigger surface:** Env var `MEETING_LIVE` controls activation; skill **self-hosts** the HTTP server. Chat advertises clickable OSC-8 hyperlink to live view. Out of scope: sibling `/meeting-rpg` skill (β); external-launcher coordination.
- **D3 — Chat output:** One-liner per agenda decision (`→ A2 resolved: <decision>`). Verbatim discussion in broker stream + plan file, never re-printed to chat. Out of scope: full-silence-until-end; verbatim-mirroring under broker mode.
- **D4 — Plan-file role:** P1 — keep writing the plan file as today; broker is additive (tee). Plan file is safety net for broker crashes. Out of scope: P2 broker-only; replacing plan-file workflow.
- **D5 — Activation default:** Opt-out — broker on by default; `MEETING_LIVE=0` falls back to verbatim-in-chat. Out of scope: opt-in default (T2); always-on with no escape (T1).
- **D6 — Daemon mechanism:** `run_in_background=true` (Bash tool's tracked-background facility). Out of scope: `nohup ... & disown`; PID-file ad-hoc lifecycle.
- **D7 — Sequencing:** Do NOT implement broker.py in this skill yet. Wait for meeting-rpg's `wt/ipc-preflight` to validate (a) daemon survival across Bash boundaries, (b) port advertisement via `/tmp/meeting-rpg/<sid>/broker.json`, (c) curl long-poll round-trip. Port the validated broker.py over (likely P2 symlink: `dotclaude-skills/meeting/broker.py` → `meeting-rpg/broker/broker.py`). Out of scope: parallel broker.py development here.
- **D8 — VN-terminal:** Forward-flag only. Adds `wt/renderer-vn-terminal` to meeting-rpg's parallel renderer exploration. Composes with broker; **not** a substitute. Out of scope: replacing broker with terminal-marker emission; blocking MVP on terminal exploration.

## Action items

- [ ] **AI-1 — Upstream-skill integration TODO** — add to `dotclaude-skills/TODO.md` "meeting skill" section; body cross-links this note and meeting-rpg D9. Contract: TODO entry exists and is mutually cross-linked. See: this note.
- [ ] **AI-2 — Trigger: meeting-rpg `wt/ipc-preflight` ships validated broker.py** — once that lands, open `/meeting meeting-skill-broker-integration` to execute D2–D6: symlink `dotclaude-skills/meeting/broker.py → meeting-rpg/broker/broker.py` (P2 pattern); edit `~/.claude/skills/meeting/SKILL.md` setup step to spawn broker via `run_in_background=true`, capture port from stdout, print clickable URL, gate behaviour on `MEETING_LIVE != "0"`. Contract: dry-run meeting through self-hosted broker emits one-liner-per-agenda in chat and full transcript on the browser/curl URL. See: this note.
- [ ] **AI-3 — Forward-flag VN-terminal renderer** — file in `meeting-rpg/TODO.md` (not dotclaude-skills): "wt/renderer-vn-terminal — custom terminal emulator that renders broker SSE stream as VN; composes with broker mode; forward-flagged 2026-05-20-1600." Contract: TODO exists in meeting-rpg. See: this note.
- [ ] **AI-4 — Discovery entry** — append to `~/.claude/skills/meeting/discoveries.md` via `append.sh`: VN-terminal does not reduce token budget (harness owns pty bytestream); only side-channel emission (broker) does. See: this note. (Resolved in end-of-meeting steps.)
