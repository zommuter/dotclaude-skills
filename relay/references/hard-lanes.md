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

## The orthogonal resource axis (NOT a lane)

`[INTENSIVE — <resource>]` (id:8d52) is an ORTHOGONAL resource modifier, not a lane.
An `[INTENSIVE]` item still carries one of the three lanes — e.g. a pool-executable
intensive item is `[HARD — pool] [INTENSIVE — local-llm]`. The resource axis governs
*scheduling* (run-serially-alone, exclusive `resource:` claim); the lane governs
*disposition* (who acts on it). Never use `[INTENSIVE — ...]` in place of a lane tag.

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
