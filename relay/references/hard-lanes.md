# `[HARD]` lane vocabulary — the shared lane contract (id:78ff / id:b466)

**Single source of truth** for the explicit `[HARD]` lane tags. Two tools READ this
contract and MUST agree on its marker set:

- `relay/scripts/gather-human-backlog.sh` (bash, dotclaude-skills, id:78ff) — buckets
  the cross-repo human backlog for `/relay human`.
- `project_manager`'s `scan.py` (python, id:b466) — splits the `proj relay` cockpit
  `Meeting⛔` count into the same buckets.

If you change a lane spelling here, change it in BOTH consumers (the acceptance test
`tests/test_hard_lane_buckets.sh` cross-checks the marker set against this doc).

## Why an EXPLICIT lane (decision 2026-06-21, user "obviously explicit")

`[HARD]` is overloaded: it only means "needs the apex tier, not a cheap Sonnet
routine" — it does NOT say the *disposition*. Before this contract,
`gather-human-backlog.sh::emit_gated_hard` lumped EVERY open `[HARD]` item as "needs a
/meeting" (its "completeness over false-negatives" over-correction), so ~40 HARD items
read as 40 meetings — when most are exactly what an Opus `/relay --afk` pool already
executes via the `hard` verdict (id:da26). The lane is therefore an EXPLICIT
bracket-tag the collectors READ — zero executability-guessing — and an untagged
`[HARD]` is a LOUD reject (id:415b grammar-tightening-with-loud-rejection: never
silently default a disposition).

## The three lanes

Every open `[HARD]` ROADMAP item declares exactly one lane in its bracket tag:

| Lane tag | Disposition | Who runs it |
|---|---|---|
| `[HARD — pool]` | Bounded, unattended-safe apex work | the `/relay --afk` pool's `hard` verdict (id:da26) — NOT surfaced to human triage |
| `[HARD — meeting]` | Needs a design decision before anyone can build it | `/meeting` / `/meeting --cross` |
| `[HARD — hands]` | Hardware / sudo / secret / on-device / rehearsal | the human ("you run these") — NOT a meeting, NOT the pool |

### Recognized aliases (meeting lane)

The relay auto-gate machinery (id:3801) emits `[HARD — decision gate]` and inline
`🚧 ... route:meeting|human|decision-gate` markers. These are EXACT SYNONYMS of the
`meeting` lane — collectors recognize them as `bucket = meeting`, they are NOT
untagged. Do not mass-rewrite an auto-emitted `[HARD — decision gate]` tag to
`[HARD — meeting]` by hand: that tag is machine-managed and the two spellings are
equivalent in this contract.

## The `[MECHANICAL]` capability tier (id:7616, meeting 2026-07-02-1924 decision 1)

A FOURTH capability tag, additive alongside `[ROUTINE]` and the `[HARD — *]` lanes:
pure-compute work no LLM or human runs at all — local-LLM benchmarks, pytorch pilots,
any artifact a host daemon can produce unattended. An LLM session only REVIEWS the
resulting artifact; it never runs the compute itself.

| Property | Value |
|---|---|
| Class tag | `[MECHANICAL]` (standalone, or composed with `[INTENSIVE — <resource>]`) |
| Who runs it | a **host daemon / CLI** (A3, gated — not built by this item) |
| Pool disposition | **pool-inert** — the classifier's `mechanical` verdict is never dispatched by the `/relay --afk` pool (same non-dispatch treatment as a human verdict) |
| Human disposition | **human-inert too** — `gather-human-backlog.sh` keeps a `[MECHANICAL]` item out of every human-triage bucket (hard_pool/hard_meeting/hard_hands/manual/review_me); it is neither pool work nor human-triage backlog |
| `[INTENSIVE — <resource>]` | **composes** — an `[INTENSIVE]` resource-axis modifier may co-occur, e.g. `[MECHANICAL] [INTENSIVE — local-llm]`; the resource axis stays orthogonal, same as on any other lane |
| Two-lane conflict | `[MECHANICAL]` is itself a capability lane — combining it with a `[HARD — *]` lane on the same item (e.g. `[MECHANICAL] [HARD — pool]`) is a tag/prose lane conflict, rejected by `roadmap-lint.sh` exactly like two `[HARD — *]` tags would be |
| Classifier verdict | `mechanical` (`relay/scripts/classify-verdict.sh`) — fires when `open_mechanical >= 1` and nothing higher-priority is present (no actionable `[ROUTINE]` / unaudited commits / `[HARD — pool]` / promotable or surface TODO backlog); `intensive` stays `""` on it (id:5ac6 invariant `intensive!="" => verdict in {execute,hard}` holds unchanged) |

This item (id:7616, slice A) adds ONLY the tag + verdict plumbing — it does NOT build
the daemon consumer (that is A3, gated). The slice-B `[HARD — *]` → two-axis-vocabulary
rename (gated, B1/B2) is where `[MECHANICAL]` folds into the renamed lane vocabulary
alongside the resource axis; until then it stands as its own additive capability tier.

## The orthogonal resource axis (NOT a lane)

`[INTENSIVE — <resource>]` (id:8d52) is an ORTHOGONAL resource modifier, not a lane.
An `[INTENSIVE]` item still carries one of the three lanes — e.g. a pool-executable
intensive item is `[HARD — pool] [INTENSIVE — local-llm]`. The resource axis governs
*scheduling* (run-serially-alone, exclusive `resource:` claim); the lane governs
*disposition* (who acts on it). Never use `[INTENSIVE — ...]` in place of a lane tag.

### Operative vs advisory (id:9062, meeting 2026-06-30-2238)

`[INTENSIVE]` is **operative** (serial-alone scheduling, exclusive `resource:` claim,
`--intensive` gate, classifier flag) **only on relay-dispatchable lanes** (`[ROUTINE]`,
`[HARD — pool]`). On human lanes (`hands`, `meeting`, `decision gate`, `@manual`) it is
an **advisory OOM note** — mechanically inert, NOT a violation. Not "amplification of
HARD" (routine-intensive is operative). The dispatch hazard is neutralised by
`gather-repo-state.sh`'s `top_intensive` exclusion (id:a707), which already keeps human
lanes out of the intensive pool regardless of their tag. `roadmap-lint.sh` therefore
accepts `[INTENSIVE]` on any recognised lane; only a lane-less `[INTENSIVE]` (no class
tag at all) is a grammar error.

### Lane criterion for an INTENSIVE item: `pool` vs `hands` (id:db39, meeting 2026-06-30)

"Intensive" is about compute weight, NOT who acts — an `[INTENSIVE]` item is NOT
automatically `hands`. Lane it `[HARD — pool]` (so the `--intensive` pool runs it
serially-alone via the `hard` verdict, id:da26) **iff ALL FIVE** hold; otherwise keep
it `hands` (or `meeting` when (e) is the failure):

- **(a) Automatable done-check** — verifiable by a script/test, no human observation
  (a screenshot, an "is this honest" eyeball). *Fail → hands.*
- **(b) No irreversible destructive side-effect** without a confirm — a `rm`/overwrite of
  artifacts a worktree child would run unattended. *Fail → hands.*
- **(c) No live secret / sudo / physical device / network credential** a worktree child
  cannot reach. *Fail → hands.*
- **(d) `scripts/host-gate.sh` satisfiable** on the pool host (host-bound work carries the
  matching `[host:<name>]` tag, id:43b9). *Fail → hands until run on the right host.*
- **(e) No open design/judgment sub-step** ("decide X", "post-gate decisions"). *Fail →
  `meeting`.*

**Needs an LLM? branch (id:2313, meeting amendment 2026-07-02).** An item that passes
a–e is not automatically `[HARD — pool]` — first ask whether the run itself needs an
LLM session at all:
- **Compute-only, no-LLM, no human judgment** (a benchmark battery, a training/eval
  run, a `model-probe.sh`-style pilot) that passes a–e ⇒ **`[MECHANICAL]`** — daemon-run
  (A3, id:b3d0), not pool-dispatched. This is the producer instruction handoff.md C2
  follows (id:9c88) when it recognizes compute-only work.
- **Needs an LLM session** (code review, judgment, an interactive turn) and passes a–e
  ⇒ `[ROUTINE]`/`[HARD — pool]` as before.
- **Fails a–e** (needs a human's hands/eyes/credential) ⇒ stays `[HARD — hands]` (or
  `meeting` when (e) is the failure) — unchanged.

Worked verdicts (the policy is only as good as its calls):
- `ai-codebench` id:244b (benchmark drain, idempotent `--resume`, dashboard done-check,
  zomni-bound) → passes a–e → **`[HARD — pool] [INTENSIVE — local-llm] [host:zomni]`**.
- `it-infra` id:c5e9 (unused-GGUF `rm`) → fails (b) → **stays hands**.
- `it-infra` id:fd30 (`--reasoning off` *post-gate decisions*) → fails (e) → **stays hands**.
- `it-infra` id:9321 (XPU seed-hunt, live GPU+sudo+LLM-stack) → fails (c) → **stays hands**.

This criterion does NOT add a marker — it only governs which existing lane an INTENSIVE
item carries — so `tests/test_hard_lane_buckets.sh` (marker-set cross-check) is unaffected.

## Canonical marker set (the contract both consumers parse)

```
[HARD — pool]                      → bucket: pool
[HARD — meeting]                   → bucket: meeting
[HARD — decision gate]             → bucket: meeting   (auto-gate alias, id:3801)
🚧 ... route:meeting               → bucket: meeting   (auto-gate inline alias)
🚧 ... route:human                 → bucket: meeting   (auto-gate inline alias)
🚧 ... route:decision-gate         → bucket: meeting   (auto-gate inline alias)
[HARD — hands]                     → bucket: hands
[HARD]  (no recognized lane)       → bucket: untagged  → LOUD reject, exit nonzero
```

`untagged` is a HARD ERROR, not a default: a `[HARD]` item with no recognized lane
makes `gather-human-backlog.sh` print a loud `ERROR:` line to stderr and exit nonzero
so the gap is fixed at the source, never silently bucketed.

## Live-availability gate for `[INTENSIVE]` auto-launch (id:68dc, A5)

The mechanical-run daemon (`[HARD — pool]` A3, gated on 68dc + others) does not launch
an `[INTENSIVE — <resource>]` recipe on the permitted-intensity window (A4) alone. Two
conditions must BOTH hold:

1. **Permitted-intensity window** (A4) — `relay intensity` graded window
   (`~/.config/relay/permitted-intensity.json`): `est_wall ≤ max_wall_seconds ∧
   resource ≤ resource_ceiling ∧ now < expires_at`.
2. **Live availability** — `relay/scripts/resource-probe.sh <resource>` (gpu/ram/cpu
   measured headroom, `local-llm` claim-only) AND no live `resource:<res>` claim held
   in the shared `claim.sh` registry (the same registry `[INTENSIVE]` scheduling already
   uses — see `resource-claims.md`). **Check-and-defer, never preempt**: a busy resource
   just defers the launch to the next daemon tick, it never suspends or kills a holder.

Both gates are advisory reads with no side effects — the daemon composes them at launch
time, it does not hold or extend any claim itself until it actually starts a recipe.
