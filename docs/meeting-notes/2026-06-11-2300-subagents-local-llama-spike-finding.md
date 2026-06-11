# 2026-06-11 — Spike finding: B vs C for local llama-swap delegation

**Session:** 0b028e7f-ee05-4950-8a0d-563ec2de2aa1
**Mode:** Spike result (no meeting — follow-up to 2026-06-11-2235-subagents-local-llama-swap.md)
**Topic:** 3-cell spike to pick architecture spine (id:95e3)

## n_ctx probe (config-confirmed)

| Model | Declared in opencode.json | Real --ctx-size (llama-swap config) |
|---|---|---|
| qwen3.5-0.8b | 128k | **8192** |
| qwen3-coder-30b | 128k | **32768** |

Confirmed the known trap: declared context in opencode.json silently diverges from actual server n_ctx. Both models fit the bounded task (2298 prompt tokens << 8192 limit).

## Cell B — curl direct, qwen3.5-0.8b (PASS)

- **Latency:** 7230ms (cold start — model was already preloaded)
- **Prompt tokens:** 2298 / 8192 (28% of context)
- **Completion tokens:** 171
- **Stop reason:** stop (clean finish)
- **Output quality:** Coherent 5-bullet summary of the diff; minor inaccuracy in one bullet (named wrong model ID) but structure and content correct for a 0.8B model
- **Verdict: PASS**

## Cell C-bounded — opencode run, qwen3.5-0.8b (FAIL/TIMEOUT)

- **Latency:** >5 minutes with zero output produced; killed
- **Verdict: FAIL**

Candidate causes (not distinguishable from this run):
1. **opencode session-startup overhead** — SQLite session init, provider handshake, tool-schema embedding sent to model even for a plain-text task
2. **0.8B model stuck in a tool loop** — opencode sends CC tool schemas regardless of task type; a 0.8B model may enter a malformed tool-call loop and never emit a text response
3. **Confounded by parallel 30b load** — qwen3-coder-30b was accidentally loaded in parallel (spike error), adding RAM/CPU pressure during the run; qwen3.5-0.8b is "always-on" and should have been unaffected, but the measurement is tainted

Regardless of cause, even the best-case interpretation (pure startup overhead) gives Cell C a latency of several minutes vs Cell B's 7 seconds for a bounded task. **C is not competitive for bounded work.**

## Cell C-agentic — opencode run, qwen3-coder-30b (DEFERRED)

Deferred to next session: 22 GB RAM in use, 13/15 GB swap occupied; loading qwen3-coder-30b (~17 GB) would thrash swap. Terminate RAM-heavy processes first (Chromium, Electron) or run in a lighter-load session.

## Finding

**B is the spine.** For bounded transforms (summarize, classify, draft, extract), direct curl to llama-swap localhost:8080/v1 is ~40× faster than opencode for the same model. Build the thin curl+jq wrapper (id:85d2).

**C-opencode status:** Still "reserve" in the architecture, but the bounded-cell failure makes the 0.8b path implausible. The agentic case (30b model edits files via opencode tools) remains untested and is the only scenario that could still earn C a slot. Gate that test on a clean-memory session.

## What the wrapper should cover

Based on Cell B results:
- Endpoint: `http://localhost:8080/v1/chat/completions`
- Default model: `qwen3.5-0.8b` (always-on, 7s latency, 8192 ctx limit)
- Loud-fail on prompt > ~6000 tokens (leave headroom for completion)
- Log: `task_type, model, prompt_tokens, completion_tokens, latency_ms, timestamp` → one line per call (zelegator-consumable)
