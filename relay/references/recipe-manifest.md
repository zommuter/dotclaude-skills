# Recipe manifest — drop-dir contract + schema (id:64d3)

**Single source of truth** for the recipe JSON schema and the `{pending,running,done}/`
drop-dir lifecycle the (gated, not-yet-built) mechanical-run daemon (A3) will consume.
This item (A2, meeting 2026-07-02-1924 decision 3) pins the contract and ships a LOUD
validator so a malformed recipe can never reach the daemon; it does **not** build the
daemon itself and does **not** wire `relay/scripts/inject.sh`.

## The core safety invariant: WHITELISTED, never auto-scanned

Recipes are **whitelisted / relay-authored only**. A recipe reaches `pending/` because
a relay reviewer session (Opus) deliberately wrote it there — the drop-dir itself, not
a tag on a ROADMAP item, is the gate. The daemon (A3) MUST NEVER auto-scan ROADMAP.md,
TODO.md, or any other ledger to invent or infer recipes on its own. This mirrors
devil's-advocate Riku's constraint from the meeting: an automatic scanner that turns
ROADMAP items into executable recipes would let a mis-tagged or adversarial ROADMAP
line silently trigger execution with no human-authored intermediate artifact. The
registry (the set of files relay-authored into `pending/`) is the only trust boundary;
nothing upstream of it is trusted to author a recipe.

## Drop-dir lifecycle

Default location: `~/.config/relay/recipes/{pending,running,done}/` — i.e.
`recipes/pending`, `recipes/running`, `recipes/done` under the recipe root
(env-overridable via `RELAY_RECIPE_DIR`, default `~/.config/relay/recipes`, for
hermetic testing — `recipe-validate.sh` itself doesn't touch the drop-dir, but any
daemon/wrapper built on top of it must honor this override the same way).

- **`pending/`** — a relay reviewer session authors a recipe JSON file here. This is
  the ONLY directory anything outside the daemon ever writes to.
- **`running/`** — the (future) daemon moves a recipe here the instant it starts
  executing it, so a crash mid-run leaves an unambiguous "was running" marker instead
  of silently vanishing from `pending/`.
- **`done/`** — the daemon moves the recipe here on completion (success or failure),
  alongside (or pointing at) the `acceptance_artifact` the recipe named.

Only the daemon (A3, not built by this item) performs the `pending → running → done`
moves. `recipe-validate.sh` is a pure validator: given a single recipe file path, it
checks the file against the schema below and exits 0/nonzero — it never lists a
directory or moves anything.

## Recipe JSON schema

Every recipe is a flat JSON object with exactly these 7 fields:

| Field | Type | Notes |
|---|---|---|
| `id` | string | non-empty; the relay item/run id this recipe executes |
| `repo` | string | non-empty; which repo the command runs in |
| `cmd` | string | non-empty; the shell command to execute |
| `host` | string | non-empty; which host the recipe is bound to (mirrors the `[host:<name>]` ROADMAP tag) |
| `est_wall` | integer | **positive** integer seconds; the estimated wall-clock budget |
| `resource` | string | non-empty; the `resource:<name>` claim token this recipe should acquire (see `resource-claims.md`) |
| `acceptance_artifact` | string | non-empty; path/pointer to the artifact that proves completion |

Example:

```json
{
  "id": "7616",
  "repo": "ai-codebench",
  "cmd": "make bench-drain",
  "host": "zomni",
  "est_wall": 3600,
  "resource": "local-llm",
  "acceptance_artifact": "results/latest.json"
}
```

## Validator: `relay/scripts/recipe-validate.sh`

```bash
relay/scripts/recipe-validate.sh <recipe.json>
```

- Exit 0, **silent**, on a well-formed recipe.
- Exit **nonzero** with a LOUD `ERROR: <field> ...` line on stderr naming the FIRST
  offending field, on:
  - any of the 7 keys missing,
  - any string field that is missing, non-string, or empty,
  - `est_wall` missing, non-integer (floats and booleans included), zero, or negative.
- **No silent coercion** — a malformed field is always a loud rejection, never quietly
  fixed up or defaulted (repo-wide no-silent-swallow rule, id:4347).

Built with `python3` stdlib `json` for parsing/typing (never fragile string munging —
the CLAUDE.md JSON gotcha), wrapped in `set -euo pipefail` bash per the repo's script
convention.

## Context / non-goals

- Mirrors the `acquire-resource.sh` / `resource-claims.md` script+doc idiom already
  used for the `resource:<name>` claim vocabulary.
- Does **not** build the mechanical-run daemon that performs the `pending → running →
  done` moves (A3, gated on this item landing).
- Does **not** wire `relay/scripts/inject.sh`.
- The `resource` field's value should match the shared `resource:<name>` vocabulary in
  `relay/references/resource-claims.md` when the recipe's command needs to serialize
  against a contended physical resource (local-llm, gpu, …).
