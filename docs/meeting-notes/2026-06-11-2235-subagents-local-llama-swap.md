# 2026-06-11 — Subagents using local llama-swap models alongside remote Anthropic

**Started:** 2026-06-11 22:35
**Session:** 0b028e7f-ee05-4950-8a0d-563ec2de2aa1
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🎛️ Orla (multi-agent orchestration), 🔧 Quinn (inference-server internals)
**Topic:** How to let Claude Code subagents use local llama-swap models in addition to remote Anthropic ones.

## Surfaced discoveries
- [2026-06-05 dotclaude-skills] ToS tripwire: routing *non-Claude* inference through a CC subscription seat needs an Anthropic-terms citation first. (Reverse case — local models on own HW — does not trip it.)
- [2026-06-03 dotclaude-skills] ANTHROPIC_BASE_URL localhost-hop proxy spike already ran on port 61842 — passthrough proven, but it was pure pass-through to Anthropic (no translation).
- [2026-06-11 meeting-rpg] opencode's declared model context limit silently diverges from actual llama-server n_ctx; ContextOverflowError fires before any tool call.
- [2026-05-12 helferli] llama-swap on zomni is OpenAI-compatible at localhost:8080/v1; opencode already talks to it via @ai-sdk/openai-compatible.

## Hard technical facts
- CC Agent-tool subagents run **in-process**, sharing one global `ANTHROPIC_BASE_URL`. No per-subagent provider field.
- Agent `model` field accepts only `sonnet|opus|haiku|inherit` — not arbitrary provider strings.
- llama-swap: `http://localhost:8080/v1`, OpenAI-compatible. Models: qwen3.5-0.8b, llama-3.2-3b, deepseek-r1-7b, qwen3-coder-30b, qwen3.5-35b.
- opencode is a working reference runner pointing at llama-swap via `@ai-sdk/openai-compatible` (`~/.config/opencode/opencode.json`).
- No `~/.claude/agents/` defined yet; no ANTHROPIC_BASE_URL in active settings.

## Agenda
1. Architecture: how does a subagent reach a local model?
2. Routing policy: which tasks go local vs remote, and who decides?
3. Scope of first deliverable.

## Discussion

### Item 1 — How a subagent reaches a local model

Three candidate architectures:

**A — Translating proxy at ANTHROPIC_BASE_URL.** Routes by model name; hijacks a CC alias (e.g. haiku→qwen) and translates Anthropic⇄OpenAI on each turn. 😈 Riku: routes the *entire* session through a hand-rolled MITM, poisons the alias globally, and must fake tool-use blocks/SSE/stop-reason semantics that llama-server doesn't implement. 🔧 Quinn: Q4 models with small real n_ctx + full CC system prompt = context blown before anything useful happens (declared-vs-actual trap). **Rejected unanimously.**

**B — Tool/MCP delegation.** Anthropic stays orchestrator; local models are exposed as a tool (curl/MCP) returning text for bounded jobs (summarize, classify, draft, extract). No interception, no global state. ⚙️ Sage: composes natively with skill system, allowlistable. 🔧 Quinn: matches the small-model/small-prompt hardware reality.

**C — opencode runner.** Shell out to opencode (already wired to llama-swap) for sub-tasks that need a real agentic loop. Gives local models tool access (Read/Write/Bash); adds opencode as a runtime dep and a second config surface that drifts from llama-swap aliases.

🎛️ **Orla's fork:** In B and C, the local model is a *worker behind a tool call* — it answers, it does not act on CC tools. Only A or C give the local model a real CC tool loop. The architectural question is whether you need local models to *act* (agentic) or just *answer* (bounded transforms). Personas converged on B-spine / C-reserve / drop-A.

**User redirect:** spike B vs C empirically before committing to either.

### Item 1b — Spike design

🔧 Quinn / 🎛️ Orla: B and C are not symmetric — three interesting cells:
1. Bounded task via B (curl one-shot) — baseline.
2. Same bounded task via C (opencode run) — runner overhead vs. bounded job.
3. Smallest agentic task via C only — pass/fail on whether a Q4 local model completes an unaided tool loop.
Cell 4 (agentic via B) is empty — B can't loop.

😈 Riku: concrete task + pass/fail line per cell.
- Bounded: "summarize this git diff in 5 bullets." Pass = coherent + correct; record latency + n_ctx fit.
- Agentic: "append a line to a markdown file, confirm it." Pass = opencode+local completes the edit unaided.

⚙️ Sage: probe real n_ctx first (via `/v1/models` or tiny overflow probe) — config-failure ≠ capability-failure.
✂️ Petra: throwaway, ~1 session. Output = a finding + go/no-go. No skill/MCP/config built before the finding.

### Item 2 — Routing policy

😈 Riku: classifier is premature infra — no outcome data yet; silent-misroute failure mode (a misrouted task gets a worse local answer without notice). 🔧 Quinn: capability boundary is task-class × *specific model* (llama-3.2-3b tool-calling round-trip is broken; only qwen3-coder-30b is a real code model) — too fine-grained to hardcode pre-measurement. 🏗️ Archie: start manual → delegations naturally generate the log → promote to heuristic or classifier only when evidence exists.

**User: manual now, zelegator later.**

🎛️ Orla: auto-routing's future home is *zelegator* (existing semantic router), not a new classifier in dotclaude-skills. 😈 Riku condition: log delegations in a zelegator-consumable shape (task text, chosen model, outcome) from the start — cheap now, expensive to reconstruct.

### Item 3 — Scope of first deliverable

✂️ Petra: deliverable = spike + finding. 🏗️ Archie: if bounded-B passes, the "tool" is a ~10-line curl+jq wrapper — commit that as v0. ⚙️ Sage: thin wrapper is the correct v0 + the logging point; MCP server is N=2-gated (no second consumer yet). 🔧 Quinn: wrapper must probe real n_ctx and fail loud on overflow — never silently truncate. 🎛️ Orla: agentic-C result → documented escape hatch only, no built infrastructure.

## Decisions
- **D1 — Architecture: tool-delegation (B) is the spine; opencode-runner (C) reserved for the agentic case; translating-proxy (A) rejected.** B keeps Anthropic as orchestrator, treats local models as bounded workers, no global blast radius. A poisons a CC alias globally and must reimplement Anthropic API semantics over an OpenAI llama-server that doesn't support them. *Out of scope:* A entirely; giving local models the full CC tool loop except via C.
- **D2 — Gate on a 3-cell spike before building anything.** (1) probe real n_ctx for the candidate model; (2) bounded "summarize this diff in 5 bullets" via B=`curl localhost:8080/v1/chat/completions` AND C=`opencode run` — compare latency/quality/context-fit; (3) smallest agentic "append a line to a file, confirm it" via C only — pass/fail. Output: go/no-go finding that picks the spine. *Out of scope:* any skill/MCP/config before the finding.
- **D3 — Routing policy: manual delegation; auto-routing forward-flagged to zelegator.** Orchestrating agent invokes the local tool on request; every delegation logs task/model/outcome in a zelegator-consumable shape. *Out of scope:* any classifier/router in dotclaude-skills — zelegator owns model-selection when evidence warrants.
- **D4 — First deliverable: spike + finding + (conditional on B passing) a thin curl+jq wrapper** with outcome logging and loud-fail on n_ctx overflow. MCP server is N=2-gated. opencode-for-agentic and zelegator-for-auto-routing are documented forward-flags, no work minted. *Out of scope:* MCP server, routing heuristic, productionization.

## Action items
- [ ] Run the 3-cell spike (D2): probe real n_ctx; bounded "summarize diff" via curl (B) and `opencode run` (C); smallest agentic "append line + confirm" via opencode (C). Write results table + go/no-go finding. Contract: finding states whether B suffices alone or C earns a slot. <!-- id:95e3 -->
- [ ] Conditional on bounded-B passing: commit a thin `curl`+`jq` local-delegation wrapper with outcome logging (task/model/outcome, zelegator-consumable) and loud-fail on n_ctx overflow. Contract: routes a bounded prompt to localhost:8080/v1, appends one log line per call, no silent truncation. <!-- id:85d2 -->
- [ ] Forward-flags (documented, no work now): (a) auto-routing local-vs-remote → zelegator (semantic-router-benchmark is where the eval lives); (b) opencode → agentic-local escape hatch, gated on a real two-consumer need. <!-- id:f579 -->
