# 2026-05-20 — Meeting-skill broker integration

**Started:** 2026-05-20 16:45
**Session:** d19787aa-2a3d-4fd1-8efc-f1814682669a
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Execute D2–D7 of `2026-05-20-1600-game-mode-and-ctx-isolation.md` now that `wt/ipc-preflight` validated `broker.py`. Resolve remaining open questions: broker.py promotion path, SKILL.md surgery shape, AskUserQuestion handling under broker mode, headless UX, allowlist additions.

## Agenda

1. broker.py promotion path — wt/ipc-preflight → meeting-rpg → P2 symlink into dotclaude-skills.
2. SKILL.md surgery shape — spawn location, port capture, OSC-8 advertisement.
3. AskUserQuestion under broker mode — replace, mirror, probe-and-branch, or split discussion/decisions.
4. Headless-mode UX — no renderer attached.
5. Allowlist additions.
6. MVP cut-line + action items.

## Discussion

### Agenda 1 — broker.py promotion path

🏗️ **Archie:** Two-hop symlink chain across three repos under prior D7 is feasible but unusual for a runtime executable.

😈 **Riku:** Failure mode under D7: external `git clone dotclaude-skills` without sibling meeting-rpg → broken symlink → `/meeting` broker mode unusable. Publishability regression.

🏗️ **Archie:** Reversed alternative (a'): broker.py canonical in dotclaude-skills; meeting-rpg symlinks in. One source, two pointers; clean public clone.

⚙️ **Sage:** Prior D7's directional choice was made without weighing publishability; legitimate to re-aim.

✂️ **Petra:** Revisit pays vs ongoing friction.

😈 **Riku:** Matches `[[dependency-ownership-instinct]]` (skill owns broker's lifecycle) and `[[drift-aversion]]` (one canonical, two pointers).

**A1 — Zommuter:** Recommended (a') + amendment: ship as WIP sibling skill (`meeting-live/`) during verification; production `/meeting` stays untouched as fallback. Reopens prior D2 (sibling skill) temporarily as a [[empirical-pilot-preference]] scaffold; folds back into canonical `/meeting` after ≥1 successful live meeting end-to-end.

### Agenda 2 — SKILL.md surgery shape

🏗️ **Archie:** Surgery happens in `meeting-live/SKILL.md` (WIP sibling). Cleanest insertion: new setup step 7, gated on `MEETING_LIVE != "0"` AND Class 3 / subject-given path. Class 1/2 paths skip broker entirely.

⚙️ **Sage:** D6-honouring port capture: `run_in_background=true` spawn, then a separate foreground Bash call polls `/tmp/meeting-rpg/$SID/broker.json` (≤2s) reading `.port`. Two Bash calls; respects "one Bash call per command" rule.

😈 **Riku:** Failure modes: bind-fail (poll timeout → fallback to verbatim chat with note), partial-write race on broker.json (theoretical, vanishingly unlikely; forward-flag).

✂️ **Petra:** Bundle Q2a (spawn location) + Q2b (port capture) + Q2c (chat advertisement: OSC-8 hyperlink + plain URL) as one decision. Token cost: ~30 curl-calls × ~60–80 tokens each = ~1.5–3k tokens/meeting overhead.

🏗️ **Archie:** Savings dwarf cost: a verbatim discussion is 3–8k tokens × N turns of re-inclusion. Order-of-magnitude net win.

**A2 — Zommuter:** Bundled recommended. **Amendment raised mid-decision: LLM-proxy at the Claude Code ↔ Anthropic API boundary as parallel architecture.**

#### Amendment session — LLM-proxy

🏗️ **Archie:** API-boundary proxy could observe assistant outputs and fan persona lines to renderer broker — zero SKILL.md curls.

😈 **Riku:** Discovery 2026-05-20 ≡ failure: observation ≠ removal. Bytes are already in conversation history.

⚙️ **Sage:** Cache-rewriting variant (proxy strips verbatim discussion from outgoing API history) would achieve ctx-savings BUT: breaks prompt-cache (key hashes exact bytes — every turn cache-miss); desyncs harness view from API view; tool-use ID preservation fragile.

🏗️ **Archie:** Proxy's real niche: renderer fan-out without modifying SKILL.md. Different goal from broker; composes additively.

✂️ **Petra:** Forward-flag, not MVP.

**Amendment outcome:** A2 = bundled recommended. LLM-proxy filed as forward-flag for meeting-rpg.

### Agenda 3 — AskUserQuestion under broker mode

🏗️ **Archie:** Four shapes — α (full replacement), β (mirror), γ (probe + branch), δ (discussion via broker, decisions in chat).

⚙️ **Sage:** No renderer exists yet (`wt/renderer-*` all `[ ]` in meeting-rpg/TODO.md). α blocks on first decision point — 600s `/await` timeout with no response path. Unusable until renderer ships.

😈 **Riku:** β: discussion-savings only; decision-text still in chat. γ: requires new broker endpoint OR timeout heuristic; complexity-multiplier. δ: matches prior D3 verbatim; AskUserQuestion path unchanged from canonical; cleanest precursor to α.

✂️ **Petra:** Token math — δ saves ~10–20k/meeting; α saves ~15–25k but blocks without renderer; γ comparable to α/β but state-dependent.

🏗️ **Archie:** δ is exactly prior D3. Recommended.

😈 **Riku:** Pre-emption check [[transcript-first-reading]]: under δ + headless, the workflow is "read broker stream via `curl -N` in a second terminal, answer chat AskUserQuestion." Mechanism is consistent.

**A3 — Zommuter:** γ (probe + branch) selected. Plus: file LLM-proxy in meeting-rpg's TODO with UX rationale (renderer fluidity + user-response injection on broker/IPC failure), even though ctx-savings unavailable.

### Agenda 4 — Headless-mode UX (under γ)

🏗️ **Archie:** Under γ, headless case auto-falls-back to AskUserQuestion when `/status.subscribers == 0`. Discussion still streams via `/event`. User reads with `curl -N http://127.0.0.1:<port>/events` from a second terminal.

⚙️ **Sage:** broker.py needs a small addition: subscriber-counter + `/status` GET endpoint returning `{subscribers: N}`. ~10 LOC.

😈 **Riku:** Subscriber-disconnect mid-meeting → next decision flips path. Acceptable; document as expected behaviour.

**A4 — δ-branch is automatic via γ. Advertise both OSC-8 hyperlink AND `curl -N` command in chat. broker.py gains `/status` endpoint.**

### Agenda 5 — Allowlist additions

🏗️ **Archie:** Three new patterns in `~/.claude/settings.json`:
- `Bash(curl http://127.0.0.1:* *)` — broker writes/reads (`/event`, `/question`, `/response`, `/await`, `/status`).
- `Bash(python3 /home/tobias/.claude/skills/meeting-live/broker.py *)` — broker spawn (absolute path; tilde patterns silently miss for Bash per discovery 2026-05-10).
- `Bash(jq -r * /tmp/meeting-rpg/*/broker.json)` — port read.

😈 **Riku:** Discovery 2026-05-10 (glob-swallow): scope curl pattern to literal `127.0.0.1` (loopback-only); outbound URLs require different host substring → don't match.

**A5 — Three entries; loopback-only scoping; verify during pilot dry-run.**

### Agenda 6 — MVP cut-line

✂️ **Petra:** In: broker.py promotion + `/status`; meeting-live WIP sibling; SKILL.md step 7; γ branch logic; allowlist entries; live pilot. Out: renderer implementation (separate meeting-rpg worktrees); LLM-proxy (forward-flag).

## Decisions

- **D1 — broker.py canonical home:** `~/src/dotclaude-skills/meeting/broker.py`. Symlinks: `~/.claude/skills/meeting/broker.py` and `~/src/meeting-rpg/broker/broker.py` both point at it. Reverses prior meeting's D7 direction. Out of scope: meeting-rpg-canonical home; duplicate copies.
- **D2 — WIP sibling skill for verification:** Ship broker integration as `~/src/dotclaude-skills/meeting-live/` + `~/.claude/skills/meeting-live/`. Canonical `/meeting` untouched. Spec files (`format.md`, `personas.md`, `append.sh`, `cost-of.sh`) symlink-in from `meeting/`. Merge trigger: ≥1 successful live meeting end-to-end. Out of scope: permanent sibling-skill architecture (reaffirms prior D2 post-pilot).
- **D3 — Setup-step shape:** New step 7 in `meeting-live/SKILL.md`, gated on `MEETING_LIVE != "0"` AND Class 3 / subject-given path. Two Bash calls: (a) `run_in_background=true` spawn; (b) foreground poll of broker.json (≤2s) reading `.port`. Chat advertises OSC-8 hyperlink + plain URL + `curl -N` instruction. Out of scope: synchronous spawn wrappers; spawn at step 0; OSC-8-only chat lines.
- **D4 — Decision-point handling (γ):** broker.py gains `/status` endpoint returning `{subscribers}`. At each decision point, skill polls `/status`; if `subscribers > 0` → POST `/question` + GET `/await`; else → AskUserQuestion fallback. Discussion (persona lines) always POSTs to `/event`. Out of scope: full α replacement; pure-mirror β; static δ.
- **D5 — Allowlist additions:** Three entries in `~/.claude/settings.json`: `Bash(curl http://127.0.0.1:* *)` (loopback-only), `Bash(python3 /home/tobias/.claude/skills/meeting-live/broker.py *)`, `Bash(jq -r * /tmp/meeting-rpg/*/broker.json)`. Out of scope: tilde-prefixed Bash patterns.
- **D6 — LLM-proxy forward-flag:** Filed in `~/src/meeting-rpg/TODO.md`. Rationale: renderer fluidity + user-response-injection resilience. Trade-off: no ctx-savings without prompt-cache breakage. Trigger: broker MVP validated AND demand for renderer attachment without skill modification. Out of scope: implementing in dotclaude-skills.

## Action items

- [ ] **AI-1 — Promote broker.py to dotclaude-skills canonical home** — copy `~/src/meeting-rpg/wt/ipc-preflight/broker.py` to `~/src/dotclaude-skills/meeting/broker.py`; add `/status` endpoint returning `{"subscribers": <count>}` (per D4); commit. Then symlink `~/src/meeting-rpg/broker/broker.py → ~/src/dotclaude-skills/meeting/broker.py` (after meeting-rpg's `wt/ipc-preflight` merges to main). Contract: `python3 ~/src/dotclaude-skills/meeting/broker.py $SID` writes broker.json; `curl http://127.0.0.1:<port>/status` returns subscriber count.
- [ ] **AI-2 — Create `meeting-live/` WIP sibling skill** — at `~/src/dotclaude-skills/meeting-live/`; copy `meeting/SKILL.md` to `meeting-live/SKILL.md`; symlink `format.md`, `personas.md`, `append.sh`, `cost-of.sh`, `broker.py` from `../meeting/`. Add `~/.claude/skills/meeting-live/` symlink. Contract: `/meeting-live` invokable in Claude Code with all canonical specs intact.
- [ ] **AI-3 — Modify `meeting-live/SKILL.md` setup step 7 + γ branch** — insert step 7 (spawn + port + advertise per D3); modify decision-point handling per D4 (poll `/status`, branch on subscribers); ensure `MEETING_LIVE=0` opt-out short-circuits all broker behaviour. Contract: with `MEETING_LIVE=0`, behaviour identical to canonical `/meeting`; with `MEETING_LIVE` unset, broker spawns + advertises + persona lines off-chat + decision branch on subscriber count.
- [ ] **AI-4 — Allowlist entries in `~/.claude/settings.json`** — three patterns from D5. Verify each via dry-run before live meeting. Contract: no permission prompts during `/meeting-live` session execution.
- [ ] **AI-5 — Pilot live meeting + merge trigger** — once AI-1 through AI-4 land, run a real `/meeting-live <subject>` end-to-end. On success: fold `meeting-live/SKILL.md` deltas into canonical `meeting/SKILL.md`, delete `meeting-live/` sibling, close this TODO. On failure: log failure mode as forward-flag, keep WIP sibling alive. Contract: ≥1 successful live meeting whose chat-side budget (measured via `cost-of.sh`) is ≥5k tokens lower than a comparable canonical-mode meeting.
- [ ] **AI-FF1 — LLM-proxy forward-flag (in meeting-rpg)** — file in `~/src/meeting-rpg/TODO.md`: API-boundary proxy for renderer fan-out without SKILL changes; rationale: response fluidity + user-response injection if broker/IPC fails; trade-off: no ctx-savings without prompt-cache breakage. Trigger: broker MVP validated AND demand for skill-unmodified renderer attachment. Contract: TODO entry exists in meeting-rpg, cross-linked to this note.
