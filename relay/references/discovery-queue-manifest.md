# Discovery queue — drop-dir contract + schema (id:9d97)

**Single source of truth** for the discovery-queue JSON schema and the drop-dir
lifecycle written by `relay/scripts/discover-repos-mechanical.sh` — the mechanical
discovery PRODUCER (2026-07-07 meeting decision D2,
`docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md`). This item ships the
producer + the schema-checked queue file; it does **not** wire the executor prelude to
consume the queue (that's D3, id:7402, gated on this item) and does **not** eliminate the
residual `agent()` queue-read (also id:7402/D3 — irreducible while the executor is a
long-lived fs-blind Workflow).

## Why this is a NEW drop-dir, not the recipe one

`~/.config/relay/recipes/{pending,running,done}` (id:64d3/b3d0,
`recipe-manifest.md`) already exists, but its schema is a flat
`{id,repo,cmd,host,est_wall,resource,acceptance_artifact}` object describing **one
executable command** the mechanical-run daemon (A3) runs. A discovery snapshot is a
different shape entirely — an **array of per-repo classification verdicts** to be
**read** by the executor prelude, nothing to execute — so folding it into the recipe
schema would be a category error, not reuse. The two drop-dirs are siblings under
`~/.config/relay/`, not the same directory.

## Drop-dir lifecycle

Default location: `~/.config/relay/discovery-queue/` (env-overridable via
`RELAY_DISCOVERY_QUEUE_DIR`, for hermetic testing — mirrors the `RELAY_RECIPE_DIR`
idiom).

- **`queue-<run_id-or-noid>-<epoch>.json`** — one snapshot file per producer
  invocation, kept for history/forensics. Never pruned by this script (a future
  retention policy, if wanted, is out of scope here).
- **`latest.json`** — always the most recent snapshot. This is the file the (future,
  gated) executor-prelude consumer reads.

Both files are written **atomically** (write to a `.tmp.$$.<name>` file in the SAME
directory, then `mv -f`) so a concurrent reader never observes a half-written file.

## Discovery-queue JSON schema

A single flat JSON object:

| Field | Type | Notes |
|---|---|---|
| `schema_version` | integer | currently `1` |
| `generated_at` | string | ISO-8601 UTC timestamp of this snapshot |
| `run_id` | string | the `--runid` the producer was invoked with, or `""` |
| `repos` | array | `{"repo": "<name>", "path": "<abs>"}` — every confirmed own repo considered this round, in enumeration order |
| `units` | array | concatenation, in repo-enumeration order, of every per-repo `discover-repo.sh` call's `units[]` (0 or 1 entries each — see `discover-repo.sh`'s own routing) |
| `surfaced` | array | concatenation of every per-repo call's `surfaced[]`, PLUS one synthesized `{"repo","reason"}` entry per repo the producer itself could not even hand to `discover-repo.sh` (missing path / not a git repo / nonzero exit) — never silently dropped (no-silent-swallow, id:4347) |
| `skipped` | array | concatenation of every per-repo call's `skipped[]` |

Each `units`/`surfaced`/`skipped` entry is the untouched object `discover-repo.sh`
(id:64b4) emitted for that repo — the producer never mutates, re-derives, or
re-classifies a verdict; it only enumerates repos and folds each call's output. This is
what makes **determinism parity** with the prior Haiku `discover-run` shard trivial:
both call the exact same `discover-repo.sh` per repo, so the same repo state always
yields the same verdict content regardless of which caller (mechanical script vs. the
Haiku shard) ran it.

## Producer: `relay/scripts/discover-repos-mechanical.sh`

```bash
relay/scripts/discover-repos-mechanical.sh [--runid <id>] [--live-claims <csv>] [--main-branch <name>]
```

- Enumerates CONFIRMED own repos from `relay.toml` (`classification = "own"`, honoring
  the `# path:` comment override and the `paused` flag — the same parser as
  `relay-doctor.sh`/`relay-reconcile.sh`/`gather-human-backlog.sh`).
- For each repo, execs `discover-repo.sh` unmodified — **zero LLM, no `claude -p`,
  no `agent()`** anywhere in this script.
- Assembles the aggregate object above and **schema-checks it before the atomic
  write**: a sub-call producing non-JSON, a non-object JSON value, or a non-list
  `units`/`surfaced`/`skipped` field aborts the whole run with a LOUD `ERROR:` on
  stderr and a nonzero exit — nothing is ever written to the drop-dir half-formed.

## systemd `--user` unit

`tools/discover-repos-mechanical.service` (oneshot) + `tools/discover-repos-mechanical.timer`
(every 15 min, mirrors `tools/quota-sample.timer`'s cadence idiom) — installed via
`make install-discovery-timer`. **Not auto-enabled by this build** — installing the
symlinks and enabling the timer is a deliberate manual step the user runs when ready
(`make install-discovery-timer`, which itself does `systemctl --user enable --now`).

## Context / non-goals

- Does **not** wire `relay/scripts/inject.sh` or the executor prelude to consume the
  queue — that is id:7402 (D3), gated on this item landing.
- Does **not** eliminate the residual `agent()` bridge-read the executor Workflow needs
  to ingest a round's discovery results (irreducible while the executor is a
  long-lived fs-blind Workflow; see the meeting note's D3/D4).
- Does **not** extend the run-heartbeat (id:e149) to cover this timer as a second
  liveness domain — that is id:54fc, also gated on this item.
