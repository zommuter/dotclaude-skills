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

## The `@needs-auth` marker — human-held secret / interactive-auth wall (id:a505)

`@needs-auth` is a **marker**, NOT a lane — it is orthogonal to the `[HARD — *]` /
`[INPUT — *]` lanes AND to `@manual`. It records that a piece of work is blocked on a
**human-held secret or an interactive-auth wall** a relay child cannot clear unattended.
The definition is **broad**: any human-held secret OR interactive auth — sudo/askpass,
polkit/pamac, ssh/login, gpg/credential, browser-OAuth, a decryption passphrase, a
private export. (Decided in `/meeting` 2026-07-14-1135, D1/D2/D3.)

**Orthogonal to `@manual`.** An item may carry BOTH: `@needs-auth` means a human must
**provide a secret**; `@manual` means a human must **run/verify**. They are independent
markers, not alternatives.

**Carrier = a per-repo `REVIEW_ME.md` box (D2).** There is deliberately **NO** global
`~/.config/relay/auth-queue.md` file — a single shared, unversioned, destructively-edited
store repeats the id:9fdb hazard. The `@needs-auth` box lives in the affected repo's own
`REVIEW_ME.md`, versioned with that repo.

**Four MANDATORY fields per box.** A conforming `@needs-auth` box states, explicitly:

| Field | What it records |
|---|---|
| **what-secret** | the exact secret/credential/auth needed (e.g. "the Signal linked-device QR", "sudo password on fievel") |
| **where-it-goes** | where the secret is applied (env var, file path, login prompt, keyring) |
| **exact-command** | the exact command a human runs to supply it / unblock the work |
| **why** | why the work is blocked on it (what strands without it) |

**Recognition (not the filter).** `relay/scripts/gather-human-backlog.sh` and
`relay/scripts/roadmap-lint.sh` RECOGNIZE `@needs-auth` as a known marker — it is never
flagged as an unknown/untagged token. The AI-free **offline lister** that filters and
surfaces every `@needs-auth` box across own repos is a separate item (id:1750); this
contract only fixes the marker's meaning and the four-field shape it must carry.

**Executor-contract rule (D3, VERSIONED).** A child hitting a `@needs-auth` wall RECORDS
a conforming box and clean-continues the separable remainder (defaulting to a clean
handback when separability is uncertain), rather than stranding the unit — see rule 6 in
`relay/references/executor-contract.md` (contract v7+).

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

## North star — capability-keyed vocabulary (id:4f02, meeting 2026-07-02-1924 decision 1)

**Ratified target vocabulary.** Two orthogonal axes, replacing the venue-keyed
`[HARD — <lane>]` spelling above: the **capability** axis says *what kind of actor
the item requires*, not *which queue it sits in* — dispatch venue is DERIVED from the
capability tag, never spelled into it.

| Capability tag | Meaning | Touches an LLM? |
|---|---|---|
| `[ROUTINE]` | executor-tier LLM (cheap Sonnet) | yes |
| `[HARD]` | strong/apex LLM, unattended-safe | yes |
| `[INPUT — meeting]` | human design judgment (`/meeting`) | yes (meeting session) |
| `[INPUT — decision]` | human decides, no design session needed (auto-gate) | no |
| `[INPUT — access]` | human credential/hardware/physical action | no |
| `[INPUT — author]` | human-expert-authored content/prose (not a design decision, not credential/hardware) | no |
| `[MECHANICAL]` | pure compute, no LLM or human runs it (a host daemon does) | no |

The orthogonal **resource** axis is unchanged: `[INTENSIVE — <resource>]` composes
with any capability tag (operative on `[ROUTINE]`/`[HARD]`/`[MECHANICAL]`,
advisory-inert on the `[INPUT — …]` human lanes) — see "The orthogonal resource axis"
above, which stays coherent under the rename.

### Rename mapping (old → new)

The three UNAMBIGUOUS 1:1 renames (auto-converted by `relay/scripts/lane-convert.sh`,
id:4f02):

| Old (`[HARD — *]`) | New | Ambiguity |
|---|---|---|
| `[HARD — pool]` | `[HARD]` | none — 1:1 |
| `[HARD — meeting]` | `[INPUT — meeting]` | none — 1:1 |
| `[HARD — decision gate]` | `[INPUT — decision]` | none — 1:1 (covers the `🚧 route:decision-gate` auto-gate alias too) |

`[HARD — hands]` has **NO single auto-default** (amendment 2026-07-02, correcting
decision 1's original coarse `[INPUT — access]` mapping). It fragments across
**FOUR** candidate destinations by **per-item human judgment** — the converter never
guesses which:

| Candidate destination | When |
|---|---|
| `[MECHANICAL]` | the run itself needs no LLM/human — a daemon can execute it (id:2313's "needs an LLM?" branch) |
| `[INPUT — access]` | needs a live credential / physical hardware / on-device action, no open judgment call |
| `[INPUT — decision]` | needs a human decision but not a design session (e.g. it-infra fd30 "post-gate decisions") |
| `[INPUT — meeting]` | needs actual design judgment / interpretation (e.g. a rehearsal needing interpretation) |

`relay/scripts/lane-convert.sh` therefore LEAVES every `[HARD — hands]` item
UNCHANGED and FLAGS it on stderr naming all four candidates — resolving each one is
per-item judgment work (M3, id:3ef7 / B2), not a mechanical rewrite.

### Dual-vocab migration window (OPEN as of id:4f02; still open)

Both spellings — the old `[HARD — pool|meeting|hands|decision gate]` venue-keyed
lanes documented above, AND the new capability-keyed vocabulary in this section — are
**ERROR-free** in `roadmap-lint.sh` during the window. An item carrying BOTH an old
lane and its new rename simultaneously (e.g. `[HARD — pool]` + `[HARD]` on one line)
is still a case-c tag/prose conflict (never both). The window CLOSES (old-vocab →
lint ERROR) only at the tail of B2 (id:8111), after every reader and this repo's own
ledgers/tests are migrated — that flip is deliberately NOT part of this item.

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
