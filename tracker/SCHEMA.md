# The common intermediate schema + the bespoke-grammar → tracker mapping

**TODO `id:2bb1`** (`children-of:4a5c`) · ratified source:
`docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md`
(decision **D2**, as amended by `--fabled` findings 5, 6 and 7).

This document **is the deliverable**. The meeting ratified that *"the mapping is the
durable artifact and survives any tool outcome, including git-bug"* — Plane, Vikunja and
git-bug are all downstream of this file, and none of them is chosen here.
*Out of scope, explicitly: committing to a tool at schema time.*

| Artifact | What it is |
|---|---|
| `tracker/SCHEMA.md` | this file — the prose contract and the full construct-by-construct mapping |
| `tracker/schema/ledger-intermediate.schema.json` | the machine-readable contract (JSON Schema 2020-12) an adapter reads |
| `tracker/ledger-map.py` | the executable contract — reference mapper, validator, round-trip projector (stdlib-only python3) |
| `tracker/fixtures/` | fixture ledgers + the golden intermediate documents derived from them |

The three contracts must agree. `ledger-map.py validate` **cross-checks the JSON Schema
against the mapper's own enums and required-key set** and fails loudly on drift — there
is no stdlib JSON Schema validator and this repo takes no dependencies, so the invariants
are enforced in code and the published schema is pinned to them rather than trusted.

## Scope boundary — what this item is NOT

| Concern | Item |
|---|---|
| Fleet driver: `relay.toml` own-set, `# path:` overrides, pinned-SHA reads, upserts, tombstones, idempotency | `id:94ce` |
| Plane / Vikunja adapters | `id:90f2` |
| Repo-entity `classify-repo.sh` verdict derivation | `id:c17d` (this schema emits the repo entity with `verdict: null`) |
| Recurring host-side import timer | `id:f116` |
| Control-arm comparator board | `id:8066` |

`ledger-map.py import` handles **one repo tree** and never touches the network, a tracker,
or `relay.toml`. Markdown remains SSOT and **no relay script writes to a tracker** (D4).

## 1. The three non-negotiables

### 1.1 Composite `(repo, id)` key — `uid`

4-hex `id:` tokens are minted **per repo** and are **never fleet-unique**
(TODO `id:c3f6` caveat 1). The primary key is therefore

```
uid = "<repo>/<key>"      key = the 4-hex id, or a "~"-prefixed synthetic key
```

`id` alone is **never** a key. An adapter that keys on `id` will silently merge two
unrelated items from two repos; that is the failure mode `--fabled` finding 6 named.

### 1.2 Per-view status — never collapsed

The defining pathology of the current substrate is **one id with two statuses**: the same
`<!-- id:XXXX -->` token lives in `TODO.md` (the design ledger, "why") and in `ROADMAP.md`
(the execution queue, "now"), and their checkboxes can disagree. That disagreement is what
`meeting/orphan-scan.sh --cross-ledger` exists to report. A schema with one `status` field
**launders** it (finding 5).

So the schema carries **three independent view fields**, each `open | done | absent`:

| Field | View |
|---|---|
| `todo_status` | `TODO.md` ∪ `TODO.archive.md` |
| `roadmap_status` | `ROADMAP.md` ∪ `ROADMAP.archive.md` |
| `review_status` | `REVIEW_ME.md` ∪ `REVIEW_ME.archive.md` |

`absent` means *this view does not carry the item at all* and is distinct from `open`.
Plus an explicit flag:

```
drift = (todo_status != absent) ∧ (roadmap_status != absent) ∧ (todo_status ≠ roadmap_status)
```

`validate` treats a `drift` value that contradicts the pair as a **fatal** error, so the
collapse cannot creep back in.

`derived_status` (`backlog | queued | done | needs-decision`) exists **only** so an adapter
has one field to drive a board column. It is explicitly **derived, never authoritative**,
and its rule is: **an OPEN view always beats a DONE view.** A drifting item is therefore
never rendered `done` — that too is a fatal validator check. Promotion `TODO → ROADMAP` is
`backlog → queued`, which is Hank's meeting insight ("promotion is just a different
progress state") expressed in the schema.

### 1.3 Cross-repo id collisions are LOUD

Two classes, because they have genuinely different consequences:

| Class | What | Default | `--allow-homonym <token>` |
|---|---|---|---|
| **A — homonym** | the same bare 4-hex token exists in ≥2 repos, and nothing references it across repos | **FATAL** (exit 3) | downgraded to a counted `WARN` — **only for the tokens named on the list** |
| **B — ambiguous reference** | a cross-repo `routed:` edge names a token that exists in ≥2 repos, so the edge cannot resolve to one `(repo, id)` | **FATAL** (exit 3) | **still FATAL** — never downgradable, listed or not |

Default-fatal for class A is the meeting's ratified wording ("cross-repo 4-hex collisions
fail loudly at import") taken literally. An escape hatch exists because at ~60 repos and
459+ items over a 65 536-token space, homonyms are *expected*, and the composite key
already disambiguates them. **That hatch is an explicit per-token ALLOW-LIST of adjudicated
tokens, never a blanket switch** (`id:ca24`, owner-decided 2026-08-10, superseding the
`--allow-homonyms` boolean `id:2bb1` originally shipped):

```bash
python3 ledger-map.py validate fleet.json --allow-homonym cccc --allow-homonym 91cc
python3 ledger-map.py validate fleet.json --allow-homonym-file adjudicated-homonyms.txt
```

- `--allow-homonym TOKEN` is repeatable; `--allow-homonym-file PATH` reads one token per
  line (`#` comments and blank lines ignored). Both take **literal 4-hex tokens** — a
  wildcard, a prefix, or `all` is rejected outright (exit 2).
- **The bare boolean is gone.** `--allow-homonyms` is not an option and argparse rejects
  it, so the blanket-downgrade path cannot come back by habit — asserted by
  `tests/test_tracker_homonym_allowlist_ca24.sh`.
- A **listed** token warns; an **unlisted** one is still fatal and named. This is what
  keeps "cross-repo collisions fail loudly at import" operative for everything a human has
  not adjudicated: the recurring fleet import (`id:94ce`) can carry its adjudicated list,
  but it **cannot** switch class A off wholesale, so a *new* homonym still stops the run.
- A listed token that is not actually a homonym in the document is reported as a **stale**
  adjudication (`WARN`), so the list cannot silently accumulate.

**Class B is never downgradable** and needs no policy debate: the edge is
genuinely unresolvable, and a tracker that guesses one target is worse than one that stops.

A duplicate `uid` (the same id twice **inside** one repo) is always fatal — that is id
reuse, not a homonym.

## 2. Construct-by-construct mapping

Every construct below is either **mapped** or has an explicit **loud-lossy policy**.
Nothing is silently dropped (`id:4347` no-silent-swallow, `[[no-swallow-stderr]]`).

### 2.1 Checkboxes and identity

| Construct | Mapping |
|---|---|
| `- [ ] …` | the owning view's status → `open` |
| `- [x] …` / `- [X] …` | the owning view's status → `done` |
| item absent from a view | that view's status → `absent` |
| `<!-- id:XXXX -->` | `id`, and the `uid` key. **Anchored only** — a bare or backticked `id:XXXX` in prose is NOT an id (the `id:4da4`/`0d58` bare-substring trap; same discipline as `relay/scripts/lib-anchored-id.sh`) |
| two or more `<!-- id: -->` markers on one line | the **first** is the owning id (the `lib-anchored-id.sh` convention); reported as `multi-id-line` |
| membership in `TODO.archive.md` / `ROADMAP.archive.md` | `archived: true`, plus a `sources[]` entry with `archived: true`. Archive membership is **not** closure — an archived parent can nest an open sub-item — so the checkbox still decides the status. Active file wins over archive for the same view (first-wins, matching `lib-typed-edges.sh`); a second observation for the same view is reported as `duplicate-view-observation` |

### 2.2 Id-less TODO lines — **policy: import-as-untracked** (never skip)

The meeting required an explicit choice between *import-as-untracked* and
*skip-and-report*, "never a silent skip". **Chosen: import-as-untracked.** A skipped item
is invisible on the board, and board completeness is the point; an imported one is visible
and obviously second-class.

- `id: null`, `identity: "untracked"`
- `uid = "<repo>/~<sha1-12 of (view + normalized title)>"` — the `~` prefix makes an
  untracked key unmistakable and un-confusable with a 4-hex token; `validate` enforces it.
- Every such line is also reported as `id-less-item` with its file and line, so the
  ledger can be fixed at the source.

**Keyed on content, not position** — deliberately. A `(file, line)` key re-keys every
item below an insertion, which an upserting importer (`id:94ce`) sees as a mass
delete-and-recreate. The known, accepted cost: **rewording an untracked line's head text
mints a new key**, which reads as tombstone + create. That is the price of having no id;
minting one via `meeting/append.sh new-id` is the fix, and the `id-less-item` report is
how you find them.

### 2.3 `REVIEW_ME.md` boxes — **policy: attach when anchored, else standalone untracked**

Review boxes have no `id:` by convention, and they are a genuinely different kind: a
human-decision prose box, which is prose *because markdown has no assignee field*.

| Box shape | Mapping |
|---|---|
| carries `<!-- roadmap:XXXX -->` or `<!-- id:XXXX -->` | **attaches** to the existing `(repo, XXXX)` item: sets that item's `review_status` and adds label `has:review-box`. It does **not** mint a second item — that would double-count the same work on the board |
| no anchored marker | a **standalone** item, `kind: "review_box"`, `identity: "untracked"`, synthetic `~` key, `assignee: "human"`, `derived_status: "needs-decision"`; reported as `review-box-unanchored` |

`review_status` is a **third view**, never folded into `todo_status`/`roadmap_status` — a
box's state is not a ledger checkbox. A review box carries no capability lane, so a missing
lane on one is **not** the `hard-lanes.md` loud reject and emits no `lane:` label (emitting
`lane:untagged` would make a box on a `[HARD]` item read as both).

### 2.4 Capability lanes and the resource axis

Source of truth: `relay/references/hard-lanes.md`. Both vocabularies are live (the
dual-vocab migration window is still open), so both are mapped, with legacy items tagged.

| Ledger tag | `lane` | extra labels |
|---|---|---|
| `[ROUTINE]` | `routine` | — |
| `[HARD]` | `hard` | — |
| `[MECHANICAL]` | `mechanical` | — |
| `[INPUT — meeting\|decision\|access\|author\|user]` | `input` | `input:<kind>` |
| `[HARD — pool]` *(legacy)* | `hard` | `venue:pool`, `vocab:legacy` |
| `[HARD — meeting]` *(legacy)* | `input` | `input:meeting`, `vocab:legacy` |
| `[HARD — decision gate]` *(legacy)* | `input` | `input:decision`, `vocab:legacy` |
| `[HARD — hands]` *(legacy)* | `input` | `input:unresolved-hands`, `vocab:legacy` |
| `[INTENSIVE — <resource>]` | *(unchanged)* | `resource:<resource>` — **orthogonal**, never a lane |
| `[host:<name>]` | *(unchanged)* | `host:<name>` |
| no recognised tag | `untagged` | `lane:untagged` + **report** `untagged-lane` |
| unrecognised `[HARD — <x>]` / `[INPUT — <x>]` | `untagged` / lane w/o kind | **report** `unknown-hard-lane` / `unknown-input-kind` |

**`[HARD — hands]` is never auto-resolved.** `hard-lanes.md` records that it fragments
across **four** destinations (`[MECHANICAL]`, `[INPUT — access]`, `[INPUT — decision]`,
`[INPUT — meeting]`) by per-item human judgment, and that `lane-convert.sh` deliberately
refuses to guess. This mapper refuses too: it maps to the placeholder
`input:unresolved-hands` **and reports every one** as `legacy-hands-unresolved`. A tracker
label that silently picked one of the four would be exactly the drift the ledger rules
forbid.

`untagged-lane` is reported, not fatal: `TODO.md` legitimately carries untagged lines, and
`roadmap-lint.sh` / `gather-human-backlog.sh` own the enforcement at the source. The
mapper's job is to make the count visible, not to become a second enforcement point.

### 2.5 Markers

| Marker | Mapping |
|---|---|
| `@manual` | `marker:manual`, `assignee: human` |
| `@needs-auth` | `marker:needs-auth`, `assignee: human` |
| `@wire` | `marker:wire` |
| `@owner-verify` | `marker:owner-verify`, `assignee: human` |
| `@owner-accepted:YYYY-MM-DD` | `marker:owner-accepted` + `owner_accepted: "YYYY-MM-DD"`. **Owner-only**: an importer *carries* it, never mints it — writing it is a gaming violation (`id:8089`). It is a close-gate marker, not a dispatch-gate one, so it does **not** move `assignee` |
| any other `@token` | **report** `unknown-marker` — never silently ignored |

`assignee` derivation (adapters need one): `input` lane or a human marker → `human`;
`mechanical` → `daemon`; `routine` → `executor`; `hard` → `apex`; review box → `human`.

### 2.6 Gates

| Construct | Mapping |
|---|---|
| `🚧` anywhere in the item text | label `gate:blocked` |
| `BLOCKED on` / `blocked on` | label `gate:blocked` |
| `🚧 … route:meeting` / `route:human` | `lane: input`, `input:meeting` (exact synonyms per `hard-lanes.md`) |
| `🚧 … route:decision-gate` | `lane: input`, `input:decision` |
| `<!-- gated-on:a,b -->` | `blocked_by: ["<repo>/a", "<repo>/b"]` — the tracker **blocked-by relation** |

The blocked predicate mirrors `relay/scripts/classify-repo.sh:220` verbatim rather than
inventing a second one. An inline `route:` marker **refines** an item that has no explicit
lane; it never overrides one.

### 2.7 Typed ledger edges (`id:46f6`) — all comment-anchored

| Construct | Mapping |
|---|---|
| `<!-- children-of:XXXX -->` | `parent: "<repo>/XXXX"` — the tracker **parent/subtask** relation |
| `<!-- children:a,b -->` | `children: ["<repo>/a", "<repo>/b"]` (same relation, stated from the parent) |
| `<!-- gated-on:a,b -->` | `blocked_by` (see 2.6) |
| `<!-- routed:XXXX -->` | `links[] {kind: "routed", token, target_uid: null}` — a **cross-repo** move/link. `target_uid` stays `null` until fleet-level resolution, and a token resolving to ≥2 repos is a **class-B fatal collision** |
| `<!-- settles:XXXX -->` | `links[] {kind: "settles"}` |
| `<!-- decided-in:<path> -->` | `links[] {kind: "decided-in", path}` |

`parent`, `children` and `blocked_by` are **intra-repo** by construction: a typed edge's
bare token is minted in the item's own repo. Only `routed:` crosses repos. Dangling
targets are a `WARN`, never a silent drop and never a block — matching the `id:65f5`
rule that an unresolvable `gated-on:` target is loud but non-blocking.

### 2.8 Sub-bullets and structure

| Construct | Mapping |
|---|---|
| `**Acceptance** …` | `fields.acceptance` |
| `**Tests** …` | `fields.tests` |
| `**Done-check** …` | `fields.done_check` |
| `**Context** …` | `fields.context` |
| any other continuation line under an item | appended to `body` (verbatim) |
| `## <heading>` / `### <heading>` | `section: "<heading>"` |
| a section whose name matches `gated\|deferred\|done\|icebox\|archive\|parked` | `section_gated: true` (mirrors `roadmap-lint.sh:256`) |
| narrative prose **between** items (e.g. the `DECIDED 2026-08-10` block) | **not an item** — no tracker primitive carries it; **reported** as `section-prose` with a count |

`section-prose` is the largest honest loss in v0, and it is exactly what finding 7 meant by
ratifying an *explicitly lossy* v0: the ledgers carry substantial decision prose that is
not attached to any checkbox. `loderite` is the vehicle for burning that list down.

## 3. The loud-lossy report

Every document carries `unmapped[]` (construct, file, line, text, reason) and
`unmapped_counts` (construct → count). `import` also prints the counts to **stderr**. The
current construct set:

`id-less-item` · `review-box-unanchored` · `untagged-lane` · `legacy-hands-unresolved` ·
`unknown-hard-lane` · `unknown-input-kind` · `unknown-marker` · `multi-id-line` ·
`duplicate-view-observation` · `section-prose`

A consumer asserts the lossy surface is **shrinking** by comparing `unmapped_counts`
across passes; it never has to read every entry.

## 4. Round-trip — what is preserved, and what is not

`ledger-map.py render-status` projects each item back to its per-view checkbox states.
That projection is the contract's round-trip: **markdown → JSON → the status pair**, with
drift intact. `tests/test_tracker_schema_drift_roundtrip.sh` asserts it against the
fixture ledgers' actual checkbox lines, in **both** drift directions.

Full prose re-rendering to markdown is **deliberately not implemented**. D1 records the
owner's call that git-archaeology for issues is not wanted and that markdown "need not
survive as an export" — so the information a round-trip must preserve is the status pair
and the relation graph, not the byte-exact source. Claiming a byte-exact round-trip we do
not test would be the derived-doc drift this repo's own rules forbid.

## 5. Versioning

`schema_version` is a **contract-surface** marker in the sense of `CLAUDE.md` §Versioning:
this repo has no repo-wide version, and markers exist only where a stale copy breaks
*silently*. An adapter reading a changed document with an unchanged version is exactly that
case. Bump `schema_version` on any change to a required key or an enum, in the same commit
as the change, and update `ledger-map.py`'s `SCHEMA_VERSION` — `validate` fails loudly if
the two disagree. An adapter must **refuse** a `schema_version` it does not know.

## 6. Fixtures

| Path | What |
|---|---|
| `fixtures/repo-alpha/` | ledgers exercising every construct in §2, with cross-ledger drift in **both** directions (`id:1111` open-in-TODO/done-in-ROADMAP; `id:2222` the reverse) |
| `fixtures/repo-beta/` | the collision repo: `cccc` is a class-A homonym, `cafe` is the class-B ambiguous routed target |
| `fixtures/expected/repo-alpha.json` | the golden intermediate document (the contract's "fixture JSON") |
| `fixtures/expected/repo-beta.json` | ditto for repo-beta |
| `fixtures/expected/fleet-collision.json` | the merged two-repo document — the collision case |

Regenerate from `tracker/`:

```bash
python3 ledger-map.py import repo-alpha fixtures/repo-alpha > fixtures/expected/repo-alpha.json
python3 ledger-map.py import repo-beta  fixtures/repo-beta  > fixtures/expected/repo-beta.json
python3 ledger-map.py merge fixtures/expected/repo-alpha.json fixtures/expected/repo-beta.json \
  > fixtures/expected/fleet-collision.json
```

Output is byte-deterministic (sorted keys, sorted items, `path` recorded as given), so a
regeneration that differs is a real behaviour change — `tests/test_tracker_golden_fixture.sh`
pins it.

`repo-alpha/1111` deliberately carries `children-of:4a5c` with **no** `4a5c` item in the
fixture, so the dangling-parent `WARN` path is exercised: a dangling typed edge is loud but
never fatal and never silently dropped.
