# 2026-06-05 — Honcho: memory storage/retrieval for the meeting skill

**Started:** 2026-06-05 12:13
**Session:** d8779a92-4c16-4846-ac26-9517925245c7
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🧩 Memo (agent-memory-systems) (new)
**Topic:** Should the meeting skill adopt Honcho (Plastic Labs' agent-memory service) for memory storage/retrieval, and if so in what shape?

## Surfaced discoveries
- [2026-06-01 dotclaude-skills] zkm store rejected as meeting-skill memory backend (store-scoped, 2000-char chunking, ~180s cold-load); skill depends only on the BGE-M3 `/v1/embeddings` HTTP endpoint URL, never `import zkm`, to stay publishable.
- [2026-06-03 dotclaude-skills] parser-first / proxy-deferred + agent-persona-separation deferred behind explicit trigger — pattern of deferring external infra behind a named gate.
- [2026-05-19 fievel] openclaw gateway (plastic-labs ecosystem) was deactivated — prior contact with this vendor's stack.

## Honcho facts (research, 2026-06-05)
- AGPL-3.0 (HTTP client not infected). Data model: workspace → peer → session → message → representation. Vector docs keyed by (observer, observed) peer pairs.
- Retrieval: `peer.chat` (dialectic NL reasoning query), `session.context` (token-limited bundle), `peer.representation` (static snapshot). Benchmarks: 90.4% LongMem-S.
- Self-host: Postgres+pgvector, Docker, **two** services (FastAPI + background "deriver" worker that runs an LLM over every message to extract conclusions), ≥1 LLM API key. Managed: `api.honcho.dev`, $100 free credits.
- Claude Code integration: MCP server (`mcp.honcho.dev` hosted, or self-host) — operates at harness level, orthogonal to skill files. Also integrates with OpenCode, OpenClaw, Hermes.

## Existing memory surfaces (inventory)
1. `discoveries.md` — RAG via `retrieve-top-k.py` (BGE-M3 HTTP, stateless, opt-in, full-read fallback). The only vector path.
2. `user-profile.md` — behavioral observations; `profile-active.sh --filter` (awk rule-filter, not semantic). **Local real file, deliberately not symlinked into public repo.**
3. `persona-state.yml` — derived affinity cache (shard+collapse), gitignored.
4. Auto-memory `MEMORY.md` — hand-maintained index + per-topic files (read-whole).

## Agenda
1. Is Honcho warranted for the meeting skill at all?
2. If any evaluation: which integration shape?
3. Managed vs self-host; relationship to `hermes` TODO + deferred agent-persona-separation.

## Discussion

### Item 1 — Is Honcho warranted?

🏗️ **Archie:** Honcho's only strong overlap is `user-profile.md` — its per-peer "representation" ≈ our behavioural store; `peer.chat` ≈ the awk-filter query; `session.context` ≈ discoveries-RAG. discoveries + auto-memory are different shapes Honcho doesn't naturally replace.

🧩 **Memo:** Real upside is *automatic* ambient reasoning-extraction — the deriver runs an LLM over every message and extracts conclusions without an explicit save-discard prompt. Today's capture is manual and lossy. BUT Honcho's headline benchmarks (LongMem, LoCoMo) target long-conversation-at-scale problems. Our corpus is 71 profile sections / 162 discovery lines. We do not have the problem Honcho was built to win.

✂️ **Petra:** Name two consumers where the current system *actually fails*, or defer. Candidate pains: (1) lossy manual capture, (2) no semantic "what does the user think about X" query — neither is on fire. Full-read plus the awk filter works today; the one RAG path already exists and is publishable. Against that, Honcho wants Postgres+pgvector+Docker+FastAPI+deriver+LLM-key for a personal skill. Not N=2-justified.

😈 **Riku:** Risks are sharp. (1) Privacy — `user-profile.md` is deliberately a local real file, never symlinked into the public repo; `api.honcho.dev` would ship the personal behavioural model to a third party. Hard line. (2) Publishability — skill rejected `import zkm` to depend only on a minimal HTTP embed URL; a Postgres-backed service breaks "clone and it works." (3) AGPL-3.0 flag. (4) The deriver burns LLM tokens per message; we currently do stance/valence classification in-context for zero tokens.
*Pre-emption (med-confidence):* consistent with the zkm-store rejection and the observe-before-build heuristic — external infra is deferred until the current approach demonstrably fails.

⚙️ **Sage:** Unlock: Honcho ships a Claude Code MCP. That runs at the *harness* level — `mcp.honcho.dev` or self-host — completely orthogonal to skill files. "Evaluate Honcho" doesn't have to mean "rebuild the skill's memory." It can mean "install the Honcho MCP as a standalone ambient-memory experiment" and observe whether it surfaces things the file system misses. Cheap, reversible, matches the observe-before-prevent rule.

🏗️ **Archie:** Backing Sage — backend-replacement is a rewrite of a working, privacy-sensitive surface; the MCP experiment touches zero skill files. If any motion, spend it on the one that can't break anything.

**Decision D1:** Record-and-defer. File system sufficient for current corpus. No MCP experiment, no backend pilot, no provisioning today.

### Item 2 (collapsed 2+3) — Reopen trigger + relation to hermes

✂️ **Petra:** Deferral without a named trigger is procrastination. Repo pattern: zkm-store rejection, parser-first/proxy-deferred, agent-persona-separation — each carries a concrete reopen condition.

🧩 **Memo:** Honest primary trigger is corpus-scale/loss-driven — Honcho earns its infra only when full-read stops being viable OR a manual-capture miss is logged (an observation the save-discard prompt dropped that was later needed).

⚙️ **Sage:** Capability-driven secondary — if the standalone Honcho Claude Code MCP gets installed for unrelated reasons, re-evaluating for `/meeting` is near-free. Piggyback, don't provision.

🏗️ **Archie:** `hermes` + deferred agent-persona-separation are the same external-state family: Honcho = memory-substrate question, hermes = agent-runtime question, persona-separation = dialogue-generation question. Natural home is the meeting-rpg agent/broker infra; reopen together when consumable.

😈 **Riku:** Don't over-bind. Scale/loss as primary; piggyback-MCP and meeting-rpg-wave as two opportunistic secondaries. One primary, two opportunistic.

**Decision D3:** Scale/loss primary + 2 opportunistic secondaries (see Decisions section).

## Decisions

- **D1:** Do **not** adopt Honcho as a meeting-skill memory backend now. Current file-based memory (discoveries.md + BGE-M3 RAG / user-profile.md + awk-filter / persona-state.yml / auto-memory MEMORY.md) is sufficient for corpus of this size. *Out of scope:* MCP experiment, user-profile backend pilot, managed/self-host provisioning.

- **D2:** The `honcho` investigation TODO item is **answered, not built**. Honcho's relevant facts are recorded in this note (AGPL-3.0; workspace→peer→session→message→representation; deriver = per-message LLM extraction; self-host = Postgres+pgvector+Docker+FastAPI+deriver+LLM-key; managed api.honcho.dev; Claude Code MCP at harness level).

- **D3 (reopen gate):** Primary trigger = **scale/loss** — `user-profile.md` outgrows what `profile-active.sh --filter` can keep in a sane ctx budget, OR a logged instance where an end-of-meeting save/discard prompt dropped an observation later needed. Secondary (opportunistic): (a) **piggyback** — if the Honcho Claude Code MCP gets installed for unrelated ambient-memory reasons, re-evaluate for `/meeting` near-free; (b) **fold into meeting-rpg agent-infra wave** alongside `hermes` + deferred agent-persona-separation (same external-state family). *Out of scope:* binding Honcho exclusively to hermes (over-binds the cheap piggyback path).

- **D4 (privacy invariant):** If Honcho is ever piloted, **self-host only** — `user-profile.md` is deliberately a local real file; managed `api.honcho.dev` would ship the personal behavioural model to a third party.

## Action items
- [x] Rewrite the `honcho` TODO line: mark investigation answered (record-and-defer), embed the D3 reopen gate + D4 self-host invariant, cite this meeting note. Resolved in-session. <!-- id:45ac -->
