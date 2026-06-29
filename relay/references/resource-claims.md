# Relay claim invariants

## The `hard` lease guards CODE/WORKTREE integration ONLY (id:179e)

Meeting D2 (`docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`)
narrowed the relay's repo lease. The **single source of truth** for the split:

- **HARD lease** = a per-repo `claim.sh acquire <repo> --mode <execute|review|hard|handoff|intensive>`.
  It serializes the actors that build code in a worktree and **integrate** it into the
  repo's main checkout. Two of those must never run on the same repo concurrently — that
  is the whole job of the lease.
- **LEDGER-ONLY writes** (`TODO.md` / `ROADMAP.md` / `REVIEW_ME.md`, written via
  `meeting/md-merge.py` or `relay/scripts/commit-ledger.sh`) are **NOT** protected by the
  hard lease. `/meeting` step 2a (id:c144) and `/relay human` (`human.md` §5) do **not**
  acquire it for a ledger write-back; they **peek-and-warn, then proceed**. A ledger write
  is made safe instead by three layers:
  1. the per-file **flock** in `md-merge.py` / `commit-ledger.sh` (atomic write),
  2. the **atomic scoped commit** (id:148b / id:2147 — stages only the named file, never
     `git add -A`; the integrator likewise never `git add -A`, id:debf), and
  3. the post-hoc **`meeting/orphan-scan.sh --cross-ledger`** divergence backstop.

**Why:** acquiring the hard lease for a ledger write over-blocks it for the full duration
of a multi-repo pool run (the `routed:da2f` incident) — id:c144 removed that over-blocking.
The bilateral advisory claim the pool would *honor* for ledger writes is the separate,
observe-first **id:9000** follow-up; today the peek is read-only awareness, not a gate.

This invariant is mirrored in the `relay/scripts/claim.sh` header (the mechanism's SSOT).

---

# `resource:<name>` claim vocabulary — the shared serialization key (id:a643)

**Single source of truth** for the `resource:<name>` claim keys that let the relay's
`--intensive` scheduler serialize against contended physical resources. Two actors
ACQUIRE the same key and therefore collide on it:

- the relay pool's **intensive child** — `relay-loop.js` (~L1200) dispatches a unit
  carrying an `[INTENSIVE — <resource>]` lane modifier (id:8d52) and does
  `claim.sh acquire resource:<resource> --mode intensive`, stopping (handback) if busy;
- a **standalone intensive job** running OUTSIDE the relay (e.g.
  `~/.claude/logs/ai-codebench-drain.sh`'s detached `llama-server -ngl 99`), which now
  acquires the SAME key for its lifetime via `relay/scripts/acquire-resource.sh`.

Because both sides key on the identical `resource:<name>` string, a held claim by
either side makes the other's `claim.sh acquire` exit non-zero — so two heavy loads
can never run concurrently and OOM-kill each other ([[oom-local-model-session-kills]],
the 2026-06-12 Gemma-26B 6-session kill).

## The contract: the resource token is the `[INTENSIVE — <resource>]` token

The `<resource>` in a `resource:<resource>` claim key MUST be byte-identical to the
`<resource>` an item's `[INTENSIVE — <resource>]` lane tag carries (id:8d52,
`hard-lanes.md` §"The orthogonal resource axis"). That is the whole mechanism: the
relay derives its claim key from the item's tag, and a standalone job names the same
token, so the two keys are the same string and the claim collides.

| Resource token | What it serializes | Used by |
|---|---|---|
| `local-llm` | a single local GGUF / llama-server / llama-swap / ollama model load (the default `intensive = "local-llm"` repo coarse tag) | the relay intensive child; `ai-codebench-drain.sh` (and any future local-model drain) |
| `gpu` | exclusive GPU use when the contention is the device itself rather than a specific model runtime | GPU-bound standalone jobs + any `[INTENSIVE — gpu]` item |

The set is intentionally small — add a token here ONLY when a real second consumer
needs to collide on it, and tag the corresponding ROADMAP items `[INTENSIVE — <token>]`
with the same spelling. A typo'd token is NOT an error the tools can catch (the keys
simply don't collide and the serialization silently fails) — so the spelling
discipline lives here, in one doc both sides read.

**The token set is open-ended — non-LLM resources are valid too.** `[INTENSIVE]` is an
orthogonal *resource* axis (id:8d52), not LLM-specific: any contended physical resource a
unit should run alone against may name a token. Two such bespoke tokens are already in use
(both currently on closed `mathematical-writing` items, so dormant): `lean` (a real
`lake env lean` round-trip on a ~7 GB CoW Mathlib fixture — long cold start, large
disk/RAM) and `xvfb-electron` (a headless VS Code/Electron host under a virtual
framebuffer). These have NO standalone (outside-relay) consumer today, so they only ever
serialize one relay intensive unit against another — but if such an item reopens, spell the
token exactly as listed here so the keys collide. (Historical note: the original Lean item
spelled it `xvfb/electron`; prefer the slash-free `xvfb-electron` going forward so the
safekey is unambiguous.)

## Standalone-job wrapper: `acquire-resource.sh`

A standalone intensive job composes the EXISTING `claim.sh` (id:ebfb) — it builds NO
new lock:

```bash
# wrap a command for its whole lifetime (acquire → run → always-release on exit):
relay/scripts/acquire-resource.sh local-llm --run drain-$$ -- ./ai-codebench-drain.sh

# or manage the lifetime yourself (a long detached job):
relay/scripts/acquire-resource.sh local-llm --acquire --run drain-$$   # exit 1 if busy
#   …do the heavy work…
relay/scripts/acquire-resource.sh local-llm --release --run drain-$$   # idempotent
```

Crash-safety: the claim's mtime-TTL + recorded PID (claim.sh §staleness) means a job
that dies without releasing has its claim auto-expire on the next relay reap — a dead
drain NEVER wedges the relay. Conversely, while the job is genuinely live the claim is
fresh (the wrapper does not heartbeat a long bare-`--acquire` job, so a job expected to
run past the TTL should either use the wrapped form, which keeps the process alive
under the trap, or refresh via `claim.sh heartbeat resource:<name> --run <run>`).

## Wiring the actual drain (out of THIS repo)

`~/.claude/logs/ai-codebench-drain.sh` lives OUTSIDE this repo (it is a local,
un-versioned operator script), so the drain's own one-line wrap — prefixing its
`for` loop body / its invocation with `acquire-resource.sh local-llm --run drain-$$ --`
— is applied where that file lives, not here. This repo ships the reusable primitive +
vocabulary + the collision test; the per-job wrap is a one-liner the operator adds at
the drain's home. (A relay child cannot commit a file outside its repo worktree.)
