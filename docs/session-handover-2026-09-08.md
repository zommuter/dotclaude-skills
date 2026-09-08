# Session handover -- 2026-09-08 (Opus 5, 1M)

Point-in-time snapshot for the next session. Durable detail lives in the ledger items and
notes cited below -- read those; do not trust this doc if it disagrees with them.

## READ THIS FIRST: use the custom agent definitions

**A newly installed agent definition is NOT visible to an already-running session** -- the
registry is read once at startup, and dispatching an unregistered type fails with
`Agent type '<name>' not found`. This session hit that, installed the definitions, and only
after a restart could use them. So: `make install-agents` does not activate anything; a
restart does.

Three definitions are live and repo-managed (`agents/`, `AGENT_FILES` in the Makefile,
`make install-agents`, `make status-agents`):

| Type | Purpose | Use it for |
|---|---|---|
| `echo-runner` | minimal prompt, `tools: Bash`, haiku | mechanical one-command dispatch; has a live consumer in `mechanical-proxy.py` |
| `preamble-probe-wide` | minimal prompt, 11 tools, sonnet | MEASUREMENT ONLY -- not for real work |
| `preamble-probe-narrow` | minimal prompt, Bash only, sonnet | MEASUREMENT ONLY -- not for real work |

The two probes are instruments, not workers. Their bodies say "Reply with exactly the word
OK". Do not dispatch real tasks to them.

**What is NOT yet built: `relay-implementer`.** That is the actual trimmed executor
definition, and authoring it is blocked on an OWNER DECISION, not on effort -- see below.

## What LANDED this session

- **`id:c3c1` step (1) DISCHARGED -- the preamble trim mechanism is PROVEN.** The owner's
  2026-08-22 ruling was "prove the shrink first, cheaply, before migrating"; nothing had ever
  exercised it. Measured, matched-model sonnet, first-request context: default
  `general-purpose` **73,369** / minimal prompt + 11 tools **47,157** / minimal prompt + 1
  tool **40,440**. **System prompt = 26,212 tok (35.7%); tool definitions = 6,717 (9.2%).**
  The win is the PROMPT by ~4:1, which is the favourable answer -- an executor needs a wide
  toolset and can still capture the 26.2k. An irreducible ~40.4k floor survives everything.
- **`id:77d9`** -- the delegated-subagent preamble is now **~82k, not the 58.6k banked by
  `id:c3c1`/`id:10dc`**: ~40% growth in 18 days. Sonnet wall measured at ~176.7k; fixed floor
  ~95k (54% of the window before any repo work). 5 of 15 execute children died
  `Prompt is too long` in run `relay-20260908-174448-4421` -- all Sonnet, 0 of 12 Opus, which
  peaked ABOVE the Sonnet wall and survived.
- **`id:3cc7`** -- `agent-failures` (`id:06a1`) reported 2 while 7 children failed; the sets
  are DISJOINT. It counts mechanical hop failures and never child deaths, which land in the
  handback stream looking like legitimate refusals.
- **`id:e63d`** -- the `id:1432` repeat-handback alert keys on repo+verdict, not item, so
  "wisenheimer: 4 handbacks" concealed that the SAME six ids were refused all three times.
- **`id:0640`** -- `RELAY_STATUS.md` section-assignment is unstable across rounds (round 1
  left the run's only dispatched unit in no section; round 6 left 12 different repos in
  none). **Half of this item was RETRACTED in-session**: the claim that
  `relay-events.jsonl` never lands a dispatch event was a true measurement and a false
  inference -- rows land late and backdated via the `id:c8b6` off-critical-path flush.
- **`id:4263`** -- `relay-reconcile.sh --integrate` pushes `git-lock-push.sh --ff-only --all`
  and so auto-publishes to a PUBLIC remote, violating `id:f66e`. `integrate.sh` already
  narrows per-remote via `lib-private-remote.sh` + the ratification queue (`id:4d44`); the
  reconcile path never got the fix. A/B evidence: the pool withheld GitHub 5x the same day
  while one reconcile published.
- **`id:0220`** -- pool-driven mechanical daemon (move the TRIGGER, not the executor). The
  `bash`-proxy variant of that idea is REFUTED by `id:e62c`; do not re-derive it.
- **`id:3294`** (from zom.fi) and **`routed:e8e9`** (to loderite) filed/routed.
- **Orphan reconcile**: `...execute-8372-0` integrated (`relay-ckpt-20260908-1754`) after
  verifying its merge onto current main is green; `...execute-repo-0` discarded (it HANGS the
  md-merge suite, measurement preserved in `be51.md`).

## OPEN threads, priority order

1. **OWNER DECISION -- which subset of the global `CLAUDE.md` a `relay-implementer` keeps.**
   This is the only thing blocking the trim. `id:c3c1`'s own text warns that cutting the
   wrong half "silently degrades agent quality in a way no test catches", and names the rules
   that demonstrably produce good agent behaviour: no `sudo pamac`, the flock'd ledger
   helpers, `Edit`-not-`sed -i`, destructive-op hygiene, verify-before-asserting. Do NOT
   author the definition without that call.
2. **The measured win does NOT reach the children that died.** Those were relay POOL execute
   children, and the pool cannot dispatch a custom type -- `grep -c agentType
   relay/scripts/relay-loop.js` = **0**. Parent-session `Agent` dispatches get the 26.2k with
   no new plumbing; pool children need the step-(4) wiring, gated on `id:4313`. Do not
   conflate the two.
3. **Baseline gap, unexplained**: `id:77d9` measured pool Sonnet children at ~82k preamble;
   this session's default `general-purpose` sonnet baseline is 73,369. ~9k apart, different
   dispatch paths. The 26,212 saving is measured against 73,369 and its transfer to a pool
   child is UNTESTED.
4. **5 pending ratifications** on `dotclaude-skills` awaiting an owner push to GitHub
   (ckpts `1804`, `1835`, `1934`, `1947`, `2042`) -- `ratify-queue.sh list`.
5. **`...execute-64f9-0` still parked.** Do NOT integrate it: verified superseded -- it would
   re-add three CLOSED+archived items to the live `TODO.md` and overwrite a more-developed
   `37ea.md` note. Discard is the right disposition; it was left for the owner.

## Run state at handover

`/relay stop` was issued for run `relay-20260908-174448-4421` -- a TARGETED sentinel at
`~/.config/relay/STOP.relay-20260908-174448-4421`. The pool drains in-flight children and
integration debt, then returns with `stopReason: "user-stop"`. It had reached round 6:
26 dispatched, 16 integrated, 14 handbacks, 7 real child failures.

## Measurement method, so it is not re-derived

First-request context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
on the first assistant message with a usage block (the `id:10dc` method). **Grepping
transcripts for `Prompt is too long` returns ~10x false positives** -- `RELAY_STATUS`
payloads and ledger prose quote the phrase, and `id:7829`'s own title contains it. Filter to
`isApiErrorMessage:true` / `model:"<synthetic>"` or the count is meaningless.
