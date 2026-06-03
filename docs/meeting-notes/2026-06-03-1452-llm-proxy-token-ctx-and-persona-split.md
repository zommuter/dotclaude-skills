# 2026-06-03 — Local LLM proxy for token/ctx accounting + persona/plan separation

**Started:** 2026-06-03 14:52
**Session:** 2d412a34-bd4a-4e22-ad07-f02023c7b819
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔭 Otto (observability — new)
**Topic:** Should a local LLM proxy sit between Claude Code and the Anthropic API to measure token/ctx (incl. cached state), and should the meeting skill split persona roleplay from plan/decision logic via agents?

## Surfaced discoveries
- [2026-05-14 dotclaude-skills] Per-prompt ctx multiplier; sibling-helper scripts return only short stdout — current ctx tooling approximates, never measures.
- [2026-05-20 dotclaude-skills] A renderer/terminal does NOT reduce ctx budget — only a side-channel (HTTP broker) does.
- [2026-05-21 dotclaude-skills] broker.py is session-keyed, built for a global fixed-port daemon (64109); the existing localhost side-channel precedent.

## Agenda
1. Does the token/ctx-analysis goal warrant a MITM proxy, or is the data already available more cheaply (transcript `usage` objects)?
2. Should persona roleplay be separated from plan/decision logic — now, or deferred to an agent-based design?

## Discussion

### Agenda 1 — proxy vs. transcript parser

🔭 **Otto:** Before we design a proxy, where does the ground truth actually live? I checked. Every assistant turn in `~/.claude/projects/*/<session>.jsonl` already carries a `usage` object: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, plus the ephemeral 5m/1h cache split. That is the exact (un)cached state the request asks for — straight from the API response, persisted to disk after every turn.

🏗️ **Archie:** Confirmed. And nothing reads it. `cost-of.sh:15-17` estimates tokens as `SIZE_KB/4`; `meeting-cost.log` stores a `kb` size proxy, not real tokens. The statusline (`statusline-command.sh:226-231`) reads live `.context_window.total_input_tokens/total_output_tokens` from stdin but only totals — no cached/uncached split. So the precise breakdown exists on disk and is currently thrown away.

😈 **Riku:** Then state the proxy's unique value-add plainly, because "get token counts incl. cached state" is not it — that's already free. A MITM proxy gives you exactly three things the transcript doesn't: (a) real-time visibility *before* the turn is persisted, (b) request-side inspection of what context was composed *before* the call, (c) a way to avoid the rate-limited OAuth usage endpoint the statusline leans on (~5 req/token, `statusline-command.sh:49-50`). Is the goal — *analysis* — served by any of those? Analysis is retrospective. The transcript is written per turn. You don't need pre-persistence streaming to analyse ctx bloat after the fact.

🔭 **Otto:** And there's a measurement-integrity cost. A MITM proxy perturbs the system it measures — it sits in the critical path of every API call, adds latency, and becomes a single point of failure for the whole session (point `ANTHROPIC_BASE_URL` at it and a proxy bug = dead session). The first rule of instrumentation is don't perturb the thing you're measuring. The transcript-on-disk source is zero-perturbation. For pure measurement, it strictly dominates.

✂️ **Petra:** N=2 check on the proxy. Consumer 1 = ctx/token analysis — but the parser serves that. Consumer 2 = ? Live statusline cached-ratio — statusline already has totals on stdin. I can't name a second real consumer that *requires* the proxy and isn't served more cheaply. The proxy fails N=2. The parser, by contrast, has one clear consumer and is ~20 lines of jq. Ship the cheap thing.

😈 **Riku:** The user explicitly hedged: *"maybe even parallel token-count requests if metadata doesn't provide enough data."* The finding answers that conditional directly — metadata (the `usage` object) **does** provide enough, including (un)cached. So `/v1/messages/count_tokens` round-trips are redundant: the response already returns exact post-hoc counts with cache attribution. The "if metadata isn't enough" branch never fires.

🏗️ **Archie:** So the concrete first step is small and known: a Stop hook (or a `cost-of.sh` rewrite) that `jq`-parses the `usage` lines from `transcript_path` and replaces the `SIZE_KB/4` estimate with real `input/output/cache_read/cache_creation` sums. `meeting-cost-logger.sh` already receives `transcript_path` and already greps it (`:27-28`) — it just doesn't parse usage. The wiring exists; we add a jq pass and new CSV columns.

⚙️ **Sage:** From the skill-runtime side: this stays entirely within the existing hook + sibling-script pattern. No `ANTHROPIC_BASE_URL` indirection, no daemon in the request path, no new allowlist surface beyond a script path. It composes with the broker if we ever want live streaming, but doesn't require it. Clean.

😈 **Riku:** Minimum evidence that would flip me toward the proxy later: a concrete need to *act on* request composition before the call (block/rewrite/cache-tune in-flight), OR the transcript proving insufficient for some specific question. Neither is present. Per the standing heuristic — *observe before preventing, build the logger first* — the logger is the transcript parser. Gather real usage data, then decide if a proxy is ever warranted.

**User decision (agenda 1):** Parser now **+ a minimal pass-through proxy spike** to validate real-time / request-side visibility. Accepts that N=2 isn't yet established and that the spike carries critical-path risk.

### Agenda 1b — spike guardrails (post-decision)

😈 **Riku:** If we're spiking the proxy, it must not be able to kill a real working session. Three guardrails, non-negotiable: (1) **opt-in only** — `ANTHROPIC_BASE_URL` is set *only* in a dedicated experiment session, never exported globally; normal sessions never route through it. (2) **plain-http localhost hop** — Claude Code → `http://127.0.0.1:PORT`, proxy originates its *own* TLS to `api.anthropic.com`; no cert-MITM, no trust-store surgery. (3) forward `Authorization`/`x-api-key`/all headers byte-for-byte — the OAuth bearer passes through untouched.

🔭 **Otto:** The real technical risk isn't auth, it's **streaming**. Claude Code consumes SSE — the proxy must stream response chunks through *unbuffered*, or the TUI hangs waiting for a turn that never flushes. That's the spike's actual success criterion: does a streaming turn survive the hop intact? If passthrough streaming works, log two things — request-body size (the composed input context, pre-call) and the response `usage` (real-time, pre-persistence). Those are the only two signals the transcript can't give you early.

🏗️ **Archie:** So the spike is a stdlib pass-through (same `ThreadingHTTPServer` family as `broker.py`, or `aiohttp` if streaming in stdlib gets painful), bind 127.0.0.1, a port in the 61000–65535 band per the broker precedent. It is a throwaway experiment artifact, not a daemon — no systemd unit, no auto-start.

✂️ **Petra:** And it stays a spike. Explicitly out of scope: promoting it to standing infra, putting it in any default path, wiring it to the broker, or building request-mutation features. The spike answers one question — "does a localhost passthrough survive a streaming session, and what does request-side + real-time usage look like?" — then we re-decide with N≥2 in hand. The parser ships regardless of how the spike turns out.

⚙️ **Sage:** Spike artifacts live in the repo (e.g. `meeting/contrib/`), not symlinked into `~/.claude/skills/`. The parser changes go through the normal hook path. Keep the two deliverables separate so the parser can land even if the spike is abandoned.

### Agenda 2 — separating persona roleplay from plan/decision logic

🏗️ **Archie:** Today one Claude context does everything: voices Archie/Riku/Petra, accumulates the transcript in the plan file, calls `AskUserQuestion`, and writes the meeting note. Persona text and orchestration logic share one stream. The user's idea is to split the roleplay out — "maybe via separate agents later."

⚙️ **Sage:** Mechanically, a skill *can* spawn subagents mid-flow — even inside plan mode, as long as each agent is read-only and returns text (no edits but the plan file). So "one Agent per persona per agenda item, returning that persona's argument" is runnable. The catch is the interactive shape: the meeting is turn-by-turn with `AskUserQuestion` between items, and those decision points are orchestrator-owned and sequential. Agents can generate the *discussion*, but the orchestrator still has to collect, interleave, and gate on the human. So agents parallelise the talk, not the control flow.

😈 **Riku:** What's the problem we're solving? "Separate roleplay from plan" is a mechanism, not a goal. The candidate goal is **viewpoint independence** — right now one model voices all three personas, so Riku's "refutation" is the same model pattern-matching a rebuttal it already knows the answer to. Genuine independent contexts would make Riku actually try to refute. That's the adversarial-verification argument and it's real. But: is mode-collapse an *observed* problem here? Has any past meeting failed because the personas converged too easily? I don't have that evidence on the table. Per *observe before preventing*, don't build agent infra to fix a failure we haven't logged.

✂️ **Petra:** And the cost is not small. Per the standing discovery — a renderer doesn't reduce ctx, only a side-channel does — agent outputs still flow back into the orchestrator's context to be interleaved into the transcript. So N personas × M agenda items = a real token multiplier, plus latency, plus the coherence problem of stitching independent monologues into a dialogue. N=2 consumers for agent-based personas? Consumer 1 = this skill. Consumer 2 = meeting-rpg, *which already owns the "Claude runs the personas" framing.* That's the honest second consumer — and it argues for building persona-agents **there**, where the renderer and broker already live, not bolting them onto `/meeting`.

🔭 **Otto:** There's a cheaper rung on the ladder before agents: **prompt-level phase separation** inside the single context — explicitly generate persona voices in one pass, then synthesise the decision in a distinct pass. No agents, no token multiplier, just a SKILL.md structure change. It captures *some* of the "don't let the synthesiser put words in the personas' mouths" benefit at near-zero cost. If that doesn't visibly help, *then* the agent step is warranted.

🏗️ **Archie:** That laddering matches the broker state too: live/agent persona infra is already blocked on `meeting-rpg/wt/ipc-preflight` and is opt-out by default. The plumbing for multi-agent personas is being built in meeting-rpg, not here. Duplicating it in `/meeting` now would be premature and would fight the existing roadmap.

😈 **Riku:** Minimum evidence to flip me: a logged meeting where persona convergence demonstrably weakened the decision, OR meeting-rpg's agent/broker infra reaching a state where `/meeting` can *consume* it rather than reinvent it. Until one of those, this is a deferred design with a recorded trigger.

**User decision (agenda 2):** Defer, record trigger. No `/meeting` change now.

## Decisions

- **Transcript-`usage` parser is the durable deliverable.** Extend the existing measurement path to read real token fields from each assistant turn's `usage` object in `~/.claude/projects/*/<session>.jsonl` — `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` (+ ephemeral 5m/1h split) — replacing the `SIZE_KB/4` approximation in `cost-of.sh:15-17` and the `kb` column in `meeting-cost.log`. `meeting-cost-logger.sh` already receives and greps `transcript_path` (`:27-28`); add a jq pass and new CSV columns. *Out of scope:* changing the statusline; building any new aggregation UI.
- **The cached/uncached goal needs no proxy and no `count_tokens` round-trips** — the `usage` object already carries exact post-hoc counts with cache attribution. The user's "if metadata isn't enough" branch does not fire.
- **A pass-through proxy ships only as a throwaway spike**, not standing infra. Guardrails: opt-in via `ANTHROPIC_BASE_URL` in a dedicated experiment session only (never global); plain-http `127.0.0.1:PORT` hop with the proxy originating its own TLS upstream (no cert-MITM); all headers incl. the OAuth bearer forwarded byte-for-byte; port in 61000–65535 per broker precedent. **Single success criterion:** an SSE-streaming turn survives the hop unbuffered. Log request-body size (pre-call composed context) + response `usage` (pre-persistence). *Out of scope:* daemonising, systemd unit, broker wiring, request mutation, promotion to default path. Re-decide promotion only with a demonstrated real-time/request-mutation consumer (N=2 trigger).
- **Agent-based persona separation is deferred** with a recorded trigger: (a) a logged meeting where persona convergence demonstrably weakened a decision, OR (b) meeting-rpg's agent/broker infra matures enough that `/meeting` can *consume* it rather than reinvent it. Natural home is meeting-rpg (owns the persona framing + broker/renderer), not `/meeting`. *Out of scope now:* any SKILL.md change. Cheap intermediate (prompt-level voice/synthesis phase split) available if convergence is later observed.

## Action items

- [ ] Build transcript-`usage` parser: rewrite `meeting/cost-of.sh` to sum real `usage` fields via `jq` over the session `.jsonl` instead of `SIZE_KB/4`; extend `hooks/meeting-cost-logger.sh` to append real token columns to `meeting-cost.log`. Contract: `cost-of.sh <session-id>` prints exact input/output/cache_read/cache_creation token totals; a new `meeting-cost.log` line carries those four integers. <!-- id:d0ed -->
- [ ] Throwaway proxy spike: minimal localhost pass-through (stdlib or aiohttp) in `meeting/contrib/` (un-symlinked); opt-in `ANTHROPIC_BASE_URL` only. Contract: one real SSE-streaming Claude Code turn completes through the proxy unbuffered, and the proxy logs request-body size + response `usage`. Spike is abandoned-or-promoted after, never left in a default path. <!-- id:e905 -->
- [ ] Deferred — record agent-persona-separation trigger in TODO.md so the "later" is not lost: revisit when (a) logged convergence failure OR (b) meeting-rpg agent infra consumable by /meeting. <!-- id:36be -->
