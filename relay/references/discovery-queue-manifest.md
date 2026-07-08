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
| `surfaced` | array | concatenation of every per-repo call's `surfaced[]`, PLUS one synthesized `{"repo","reason","producer_error":true}` entry per repo the producer itself could not even get a usable verdict for — missing path / not a git repo, `discover-repo.sh` exiting nonzero, or `discover-repo.sh` exiting 0 with empty/non-JSON/malformed stdout (id:0fa0 finding b) — never silently dropped (no-silent-swallow, id:4347), and never aborts the OTHER repos' entries. The `producer_error` marker is what distinguishes these synthesized entries from a genuine surfaced verdict `discover-repo.sh` itself emitted (e.g. a dirty repo) |
| `skipped` | array | concatenation of every per-repo call's `skipped[]` |

### `queue_sig` — the content-address stamp (id:4860)

Every `units`/`surfaced`/`skipped` entry additionally carries a **`queue_sig`** string:
the per-repo SUPERSET signature `discover-sig.sh` (id:c3a6) computed for that repo when
this snapshot was produced. It is the ONE field the producer adds on top of
`discover-repo.sh`'s verdict content — everything else in the entry is untouched.

| Field | Type | Notes |
|---|---|---|
| `queue_sig` | string | `discover-sig.sh`'s sha256-hex signature for this entry's repo at snapshot time, **or `""`** (the fail-open sentinel — an empty sig is stamped **as-is**, never a fabricated hash) |

**Why it exists** (id:4860 — discovery-queue verdict/state coherence): the live consumer
(`relay-loop.js` CASE A) copies a repo's classify verdict from this queue only when the
snapshot is fresh by **file mtime**. mtime alone lets a *stale* verdict through — an
executor commits at T, so the T−10min snapshot's `execute`/`idle` verdict is copied when
the live state now demands `review`; a repo can also go dirty *after* the snapshot,
bypassing the `blocked` guard. **Content-addressing closes both**: CASE A copies a repo's
verdict ONLY when its `queue_sig` is **byte-identical** to that repo's **LIVE** sig (the
prelude's `discover-sig.sh` value for that round) — a pure string equality, not judgment.
On any mismatch (or a missing `queue_sig`) the runner falls to the CASE B live
`discover-repo.sh` path for that repo. `relay-loop.js` then **re-asserts** the same
equality JS-side (`u.queue_sig === sigByRepo[u.repo]`) as a **mangle canary**: a Haiku
bridge-copy that dropped/garbled the sig (or any field) fails the assert, so the unit is
**dropped and surfaced loudly**, never dispatched on stale/mangled state (costs one round).

`queue_sig` respects `discover-sig.sh`'s **fail-open** contract verbatim: an empty
sentinel sig (git error / non-repo path) is stamped as-is and simply never matches the live
sig → that repo always takes the live path (fail-safe, never a stale copy). The producer
passes the same `--live-claims` it was invoked with through to `discover-sig.sh` so the
`inlive` section of the sig matches what the live loop computes for a claimed repo.

Each `units`/`surfaced`/`skipped` entry is otherwise the untouched object `discover-repo.sh`
(id:64b4) emitted for that repo — the producer never mutates, re-derives, or
re-classifies a verdict; it only enumerates repos, folds each call's output, and adds the
`queue_sig` stamp. This is
what makes **determinism parity** with the prior Haiku `discover-run` shard trivial:
both call the exact same `discover-repo.sh` per repo, so the same repo state always
yields the same verdict content regardless of which caller (mechanical script vs. the
Haiku shard) ran it. The producer adds `--no-reconcile` (read-only), which changes only
whether reconcile's *side-effects* run — not the classify verdict content, since reconcile
mutates + surfaces in-flight/orphan cases but never re-derives a repo's verdict.

## Producer: `relay/scripts/discover-repos-mechanical.sh`

```bash
relay/scripts/discover-repos-mechanical.sh [--runid <id>] [--live-claims <csv>] [--main-branch <name>]
```

- Enumerates CONFIRMED own repos from `relay.toml` (`classification = "own"`, honoring
  the `# path:` comment override and the `paused` flag — the SHARED `own_repos()` parser
  in `relay/scripts/lib-own-repos.sh`, sourced by this script AND `relay-doctor.sh`,
  id:0fa0 finding e). A relay.toml that EXISTS but fails to parse (syntax error, duplicate
  key) makes `own_repos()` return nonzero; this script checks that exit status explicitly
  and, on failure, exits nonzero LOUDLY on stderr **before** writing any queue file and
  **before** beating the heartbeat (id:0fa0 finding a) — mirrors `relay-doctor.sh`'s
  `registry_parse_check` (id:2945).
- For each repo, execs `discover-repo.sh --no-reconcile` — **zero LLM, no `claude -p`,
  no `agent()`** anywhere in this script. `--no-reconcile` makes this a genuinely
  **READ-ONLY snapshot** (id:9d97 data-loss fix): it takes only the side-effect-free
  classify path and SKIPS `reconcile-repo.sh`'s bounded git side-effects (fetch, ff-merge,
  `uv.lock` commit, and worktree **reap/park** = `git worktree remove --force` + branch
  rename). A snapshot timer has no view of the live pool's in-flight worktrees and passes no
  `--live-claims`, so without this flag reconcile would treat every live executor worktree as
  stale and destroy it. The **LIVE dispatch loop** (`relay-loop.js`) NEVER consumes reconcile
  results from this queue: it ALWAYS runs `reconcile-repo.sh` **LIVE per round** (with
  `--live-claims` + `--runid`) for the side-effecting reconcile half — ff-merge behind-origin,
  `uv.lock` cascade commit, worktree reap/park, live-claims filtering — and takes **only** the
  deterministic CLASSIFY verdict from this queue when it is fresh (falling back to the full live
  `discover-repo.sh` when the queue is missing/stale). See the discover-run recipe's STEP 0 in
  `relay/scripts/relay-loop.js` (CASE A = live reconcile + queue classify; CASE B = full live
  exec). The producer's snapshot being based on un-fetched, un-reconciled local state is fine:
  the live loop reconciles on real pool state when it truly dispatches; the queue only ever
  supplies the classify verdict.
- Assembles the aggregate object above. A per-repo blob that is non-JSON, a non-object
  JSON value, or has a non-list `units`/`surfaced`/`skipped` field is isolated into
  `surfaced` as a `producer_error` entry for THAT repo only (id:0fa0 finding b) — it
  never aborts the other repos' already-collected verdicts. Only a genuine
  ASSEMBLY-level failure (the records file itself unreadable) is a LOUD `ERROR:` on
  stderr with a nonzero exit — nothing is ever written to the drop-dir half-formed.
- **Heartbeat = usable output** (id:0fa0 finding c): the heartbeat is beaten only when
  the written snapshot has at least one non-`producer_error` entry (any `units[]`
  entry, or any `surfaced[]`/`skipped[]` entry that isn't `producer_error`-marked). If
  every confirmed repo errored, the snapshot is still written (consumer transparency)
  but the heartbeat beat is skipped and a loud stderr line is printed, so the outage
  watchdog correctly reports the producer domain stale instead of reading "producing
  garbage" as healthy.

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
