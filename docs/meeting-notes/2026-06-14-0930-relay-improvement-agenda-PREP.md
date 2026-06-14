# PREP — fables-turn relay improvement meeting (NOT YET HELD)

Status: **prep / agenda only.** To be run in a separate `/meeting` session.
Prepared 2026-06-14 from a working session that (a) launched the autonomous pool,
(b) hit a real Fable-outage failure, and (c) analysed the design against prior art.
Each agenda item carries a minted `id:` token so the meeting's decisions and any
resulting TODO/ROADMAP items correlate via `orphan-scan.sh`.

When held, this becomes the meeting record (rename/replace the PREP marker, fill in
the Decision per item). Personas: cost/quota hawk, anti-gaming skeptic, ops/SRE,
publishability advocate.

## Framing — where the relay sits relative to prior art

The relay is, in one line, **"Ralph Wiggum with a separated, adversarial QA tier and
a cheaper labour tier."** Geoffrey Huntley's "Ralph" = one model, one prompt, looped
over one repo, git+filesystem as memory, brute force. fables-turn keeps that loop
skeleton (`runRound()` in a `while`, ROADMAP/CLAUDE.md as the looped instructions,
`fable-ckpt-*` tags + append-only RELAY_LOG as durable memory) but splits the single
agent along three axes Ralph collapses:

- **who specifies** (handoff: docs, roadmap, red tests as spec, BDD),
- **who executes** (cheap Sonnet, ROUTINE only),
- **who verifies** (review: re-runs the *original* test versions against new code,
  audits test integrity / spec drift).

Convergences with prior art (none referenced in-repo — arrived at independently):
- **BabyAGI/AutoGPT** task-list-in-a-loop with planner→prioritiser→executor roles
  → the `execute → review → handoff` verdict scheduler IS that prioritisation layer,
  but with git checkpoints + tests as ground truth (what stopped BabyAGI looping).
- **Orchestrator-worker** (Anthropic multi-agent research) + **cross-turn persistent
  state** (relay.toml) + **model tiering**.
- **Generator–Verifier / LLM-as-judge** — but the verifier is a *stronger, independent*
  model on a separate turn (sound direction; most self-critique uses the same model).
- **Model cascades / FrugalGPT** — cheap-for-bulk, expensive sets the bar (tests).
- **TDD agents** (Aider test-driven, SWE-bench harnesses) — "red test = open spec",
  with the sharp anti-overfitting move of re-running *original* tests.
- **CI/CD** — handoff = author specs+tests, execute = implement, review = gated merge,
  ckpt tags = releases. The cleanest mental model.

The through-line for improvements: the way to make a Ralph loop *trustworthy* is an
independent, stronger verifier — so the highest-leverage moves make that verifier
**adversarial and plural** rather than a single trusting pass.

---

## Agenda items

### 1. Separate Fable-availability from fallback policy (two-switch) — `id:5902`
**Status: fix in progress this session** (gate the FABLE_DOWN defer/demote block on
`STRONG_MODEL === 'claude-fable-5'`; `-d` + `STRONG_TIER=opus` substitutes Opus instead
of deferring). Meeting only needs to **ratify the final semantics** and decide on the
deeper axis below.

**Evidence:** 2026-06-14 09:07 run — plain `/fables-turn` defaulted `STRONG_TIER=fable`,
Fable was down, and *every* review/handoff unit died with a terminal API error → 18
handbacks + 18 orphan worktrees, zero useful strong work (see that run's RELAY_STATUS).
User verdict: *"-d was mis-designed, or we need two separate switches."*

**The two axes:** (A) is the strong tier available? (B) when it isn't, defer vs
substitute? `-d` conflated them. The in-flight fix composes `-d` × `STRONG_TIER`.
**Open question for the meeting:** should there be an **auto-probe** of Fable
availability (a cheap ping at front-door) so the *default* path degrades gracefully
without the human knowing to pass flags? Auto-probe was deferred before
([[fable-down-flag]]); the outage just provided the evidence that the no-signal case
is the common one. Tension to resolve: [[feedback-relay-unattended-default]] (id:f649)
says never *auto*-spend Opus from an unattended pool — so an auto-probe must default to
*defer*, with Opus-substitute only on explicit opt-in or an Opus-launched session.

### 2. Adversarial / plural verification for review (anti-gaming) — `id:2909`
**The weakest link given anti-gaming is the whole point.** Review is currently a single
agent per repo. A single reviewer can be talked past. Borrow the Workflow's own
adversarial pattern: for any review finding on a *judgment call* (suspected gaming,
weakened/rewritten test, skipped-test-counted-green per review.md §6), spawn 2–3
independent skeptics prompted to **refute**, majority-vote. Primitives already exist in
`relay-loop.js` (`parallel`). **Open:** cost ceiling (only escalate flagged findings,
not every closed item?), and whether perspective-diverse lenses (correctness / does-it-
reproduce / test-integrity) beat N identical refuters.

### 3. Hybrid mechanical + model discover — `id:23fe`
The verdict classifier runs a full model agent **every round** (×`MAX_ROUNDS`), on the
session model (Opus when launched on Opus). ~90% of its logic is deterministic git
state (`tag -l`, `log tag..HEAD`, grep `[ROUTINE]`, `status --porcelain`, standin tag
grep). The only irreducibly non-mechanical clause is *"dirty entry already declared
acceptable in relay.toml comments"* — NL matching of working-tree state against
free-text human prose. **Proposal:** a script precomputes the deterministic part;
escalate to a model only the dirty-vs-comment ambiguity. Wins: cheaper per-round,
deterministic + bash-testable common path, model confined to where judgment is real.
**Open:** does the heterogeneity of 24 repos (nested `# path:`, legacy layouts,
missing roadmap markers) erode the "deterministic" claim enough to keep it model-driven?

### 4. Meta-learning loop review→handoff + cross-repo batching — `id:4678`
Two related gaps:
- **No feedback from review into spec/contract quality.** Findings flow into per-repo
  relay files ([[feedback-relay-findings-flow-back]]) but recurring failure *patterns*
  across repos don't improve the `CLAUDE.md` contract template or handoff checklist.
  Ralph users hand-tune the prompt; we could synthesise a periodic "contract drift"
  pass over RELAY_LOG/REVIEW_ME across all repos.
- **Cross-repo batching.** The 20 zkm plugins share near-identical routine fixes (the
  `pypdf` / `pillow-heif` lock churn is already visible in relay.toml comments). The
  pool treats each repo independently; a fan-in detector could template a fix once.
**Open:** is this worth it before the backlog is bigger? Risk of premature abstraction.

### 5. Tests-as-spec hardening (anti-hardcode gate) — `id:2a94`
Re-running original tests catches test-*rewriting* but not an implementation that
special-cases the test inputs (the classic "game the test"). Add cheap **mutation
testing or property/randomised inputs** as a gate on closed `[ROUTINE]` items —
targets exactly this failure mode. **Open:** per-repo opt-in (not all repos have a
mutation harness); cost vs the single-vote review it would supplement.

### 6. HANDBACK / orphan-worktree GC + value-floor stop — `id:5081`
Two ops gaps that already bit us:
- **Orphan worktrees accumulate.** The 09:07 failed run left 18 worktrees on disk;
  failed *review* units have no auto-resume and no GC (review.md handback text even
  wrongly says "handoff continues from the last checkpoint"). Past OOM tie-in
  ([[oom-local-model-session-kills]]). Need an age-out/GC verdict or sweep, and
  aggregate worktree disk surfaced in RELAY_STATUS.
- **Stop condition has no value floor.** Quota/empty-only means late in a window it
  spends on trivial work. A priority threshold ("below priority P, stop when remaining
  quota < X") spends the marginal token better than the time-based
  `RELAY_QUOTA_DECAY_7D` proxy.

### 7. Hot-update / live-reconfigure a running relay-loop + auto-probe — `id:5879`
User musing: *"implement a mechanism for updating a running relay-loop somehow instead
of having to tell it to end?"* Today, applying a script fix means stop + relaunch
(`resumeFromRunId` gives a cached-prefix resume, which is close but still a restart).
**Design space for the meeting:**
- A control file the loop re-reads at each `runRound()` boundary (knobs: POOL_WIDTH,
  STRONG_TIER, quota thresholds, pause/drain) — cooperative hot-reconfig without code
  reload.
- Script hot-reload is harder (the Workflow captures the script at launch); likely out
  of scope vs the cached-resume path.
- Couples to #1's auto-probe: a running loop could flip Fable→Opus mid-run if a probe
  detects recovery/outage, *if* the control-file policy allows it.
**Open:** is cooperative re-read at round boundaries enough, or is the real ask a
supervisor that can preempt in-flight units? Start with the cheap round-boundary
re-read.

---

## Pre-wired decision inputs (so the meeting moves fast)
- Quota at outage time was healthy (98% 5h / 77% 7d) — cost is not the blocker for
  Opus-substitute *this* week; the policy question (#1 auto-probe default) is about the
  *unattended* future, not today.
- Items #2 and #5 are the two that directly harden the anti-gaming guarantee, which is
  the relay's reason to exist over plain Ralph — weight them highest.
- #3 and #7 are efficiency/ergonomics; defensible to defer if the meeting is time-boxed.
