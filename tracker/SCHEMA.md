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
| `tracker/repo-entity.py` | the **repo-level** entity deriver (`id:c17d`, §7) — fills `repos[].verdict` from `control-board.sh --json` |
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
| Repo-entity `classify-repo.sh` verdict derivation | `id:c17d` — **landed**, see §7 (`ledger-map.py` still emits `verdict: null`; `tracker/repo-entity.py` fills it) |
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
| two or more `<!-- id: -->` markers on one line | **AMBIGUOUS — no id is assigned** (`id:6059`). The line imports as *untracked* (synthetic key) and is reported as `multi-id-line`. There is no safe positional rule: the grammar spells "this line **is** X" and "this line **refers to** X" identically, and the two live shapes put the owning id at opposite ends — a body that QUOTES a literal marker puts it **last** (dotclaude-skills `TODO.md`, the `id:f346` item), a TRAILING REFERENCE puts it **first** (loderite `ROADMAP.md` L211/L229/L628, `routed:3ad9`, where the trailing marker points at a *closed* item). First-wins and last-wins each mis-attribute one shape, silently. Same refusal in `lib-anchored-id.sh`, `lib-typed-edges.sh` and `md-merge.py`. Count, never dedup: `<!-- id:466d --> <!-- id:466d -->` (the same id twice) is also ambiguous. The durable fix is a define-vs-refer grammar (`routed:20ce` / cartulary `id:344d`), not a tie-break |
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
| carries an anchor whose id is owned by **no** `TODO`/`ROADMAP` line | a **standalone** item exactly as the unanchored row, **plus** label `dangling-anchor:XXXX`; reported as `review-box-dangling-anchor` (`id:b7f4`) |
| no anchored marker | a **standalone** item, `kind: "review_box"`, `identity: "untracked"`, synthetic `~` key, `assignee: "human"`, `derived_status: "needs-decision"`; reported as `review-box-unanchored` |

**The dangling-anchor row is not a third policy — it is the missing branch of the first
two** (`id:b7f4`). The original table assumed an anchored box always finds its twin; a box
anchored to an id nothing owns fell between the rows and kept the bare 4-hex key while
carrying `id: null`, which is precisely the state `validate` rejects (*"no id but its key
is not a synthetic `~` key"*). Because `validate` is whole-document, **one** such box made
an entire real repo unimportable. Two alternatives were rejected:

- *keep the 4-hex key* — breaks the uid invariant and the `uid` pattern, and is what the
  defect already did;
- *promote the anchor to the box's own `id`* — fabricates a **tracked** item for an id no
  ledger owns: a ghost row on the board, and a false positive for every id-consuming
  scanner (`orphan-scan.sh`, the typed-edge resolvers).

Standalone-untracked keeps the box **visible** (board completeness is the point of §2.2's
import-as-untracked ruling) while the `dangling-anchor:XXXX` label and the loud report keep
the broken reference **recoverable** — the fix is to write the missing ledger line or drop
the anchor, and the report says which file and line to fix.

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
| `[INPUT - meeting\|decision\|access\|author\|user]` | `input` | `input:<kind>` |
| `[HARD - pool]` *(legacy)* | `hard` | `venue:pool`, `vocab:legacy` |
| `[HARD - meeting]` *(legacy)* | `input` | `input:meeting`, `vocab:legacy` |
| `[HARD - decision gate]` *(legacy)* | `input` | `input:decision`, `vocab:legacy` |
| `[HARD - hands]` *(legacy)* | `input` | `input:unresolved-hands`, `vocab:legacy` |
| `[INTENSIVE - <resource>]` | *(unchanged)* | `resource:<resource>` — **orthogonal**, never a lane |
| `[host:<name>]` | *(unchanged)* | `host:<name>` |
| no recognised tag | `untagged` | `lane:untagged` + **report** `untagged-lane` |
| unrecognised `[HARD - <x>]` / `[INPUT - <x>]` | `untagged` / lane w/o kind | **report** `unknown-hard-lane` / `unknown-input-kind` |

**`[HARD - hands]` is never auto-resolved.** `hard-lanes.md` records that it fragments
across **four** destinations (`[MECHANICAL]`, `[INPUT - access]`, `[INPUT - decision]`,
`[INPUT - meeting]`) by per-item human judgment, and that `lane-convert.sh` deliberately
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

`id-less-item` · `review-box-unanchored` · `review-box-dangling-anchor` · `untagged-lane` · `legacy-hands-unresolved` ·
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
case. An adapter must **refuse** a `schema_version` it does not know.

### 5.1 When to bump

Bump in the **same commit** as the change, on any of:

1. a change to a **required key**;
2. a change to an **enum**;
3. a change to a documented **value space** — even with no key added or removed, and even
   where no `enum` keyword existed to change.

**Clause 3 is the `id:8c7f` amendment, and it is not a clarification — it changes the
answer.** `id:c17d` kept `1.0.0`, defensibly by the letter of clauses 1–2: it added only
optional properties to a `$defs/repo` that already required `verdict`. But it also
*replaced `verdict`'s documented value space* — three of the five documented values
(`relay-poolable` / `needs-feedback` / `design-drained`) became `board_column` values —
and because the property carried its value space in **prose only**, with no `enum`
keyword, clause 2 never fired and no validator could catch it. A consumer written against
`1.0.0` is silently wrong: it reads a `verdict` it has never heard of, or filters for one
that can no longer occur. Treat a changed value space as **semantically non-additive**.

The structural half of the fix: `verdict` and `board_column` now carry real `enum`s, and
`ledger-map.py validate` **checks them** (§7) — because nothing in this repo runs a JSON
Schema validator, an `enum` keyword alone catches exactly nothing.

### 5.2 One declared version, not four

The constant existed in **four** uncross-checked copies (`ledger-map.py`, this JSON Schema,
`repo-entity.py`, `adapters/adapter_common.py`) plus a scrape in `fleet-import.sh`. Now:

| Place | How it gets the version |
|---|---|
| `tracker/schema/ledger-intermediate.schema.json` | `properties.schema_version.const` — **the single source** |
| `tracker/ledger-map.py` | a literal, pinned to the schema `const` by `schema_cross_check()` (`fleet-import.sh` scrapes this exact spelling) |
| `tracker/repo-entity.py` | **derived** — reads the `const` |
| `tracker/adapters/adapter_common.py` | **derived** — reads the `const` |

`validate`'s `version_copy_check()` enforces the collapse rather than merely documenting
it: any line in those files that mentions a schema version *and* carries a literal `X.Y.Z`
must name the current one, so a re-hardcoded stale copy is a loud error.

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

## 7. Repo entities — the verdict (`id:c17d`)

`ledger-map.py` emits one repo entity per import with `verdict: null`, because it never
runs the classifier. `tracker/repo-entity.py` fills it. Fable finding 3 is the reason the
entity exists at all: without a repo-level entity the board cannot answer *"which repos
need me?"* — the question that motivated the pilot — because that answer is not a property
of any single item.

**Contract**: for a fixture fleet, each repo's board status **equals**
`classify-repo.sh`'s verdict. `tests/test_tracker_repo_entity.sh` asserts it the literal
way — it runs `classify-repo.sh --repo … --emit unit` per fixture repo and compares the
verdict string byte-for-byte against the emitted entity.

| Field | Source | Note |
|---|---|---|
| `verdict` | `classify-repo.sh --emit unit`, **verbatim** | `null` ⇒ the classifier produced nothing for this repo (producer error), **never** an invented value |
| `board_column` | `control-board.sh`'s display grouping | carried *alongside* the raw verdict, so the grouping collapses nothing |
| `board_label` | `render-verdict.sh` | the only sanctioned emitter of `drained` (`idle` → `drained`) |
| `verdict_reason`, `counts`, `verdict_source`, `verdict_generated_at` | same unit | provenance + staleness, so a board row is not a dead end |
| `labels` | derived | `verdict:<raw>` + `board:<column>`, or `verdict:unavailable` |

No status vocabulary is authored here — **both** vocabularies already existed
(`classify-verdict.sh`'s enum and `control-board.sh`'s columns), and a test greps
`classify-verdict.sh`'s `verdict = "…"` assignments so a new classifier verdict cannot
land without this file knowing it.

```bash
relay/scripts/control-board.sh --json > board.json
tracker/repo-entity.py emit   --board board.json            # repos-only document
tracker/repo-entity.py enrich doc.json --board board.json   # fill a mapped document
tracker/repo-entity.py validate-repos doc.json
```

`repo-entity.py` is a **pure function of two JSON documents**: it reads no `relay.toml`,
resolves no path, and writes no file (the fleet driver is `id:94ce`; D4's "no relay script
writes to a tracker" holds). It ships a purity test on `tests/lib/assert-repo-unchanged.sh`.

Two gaps are **named, not silently worked around**:

- `--emit unit` drops the `unpromoted` promote/surface counts (`id:6daf`), so a repo entity
  cannot carry them. They are **not** re-derived by a second `unpromoted-scan.sh` call —
  when `id:6daf` lands they arrive through the same pipe into `counts`.
- ~~`ledger-map.py validate` checks `items[]` exhaustively and **does not look at `repos[]`
  at all**.~~ **CLOSED by `id:8c7f`**: `validate` now checks the repo entities' required
  keys, duplicate repo names, and both value spaces (`verdict`, `board_column`), and
  `schema_cross_check()` covers `$defs/repo` — which previously had **zero** drift
  protection, since it read only `$defs.item`. A retired `verdict` value fails with the
  migration named in the error. `repo-entity.py validate-repos` keeps the verdict↔column
  invariant (a real verdict may not sit in `unclassified`, and vice versa), which is a
  *relation* between two fields rather than a value space.

`head_sha` is declared as of **1.1.0**. It was written by `fleet-import.sh` and read by
`fleet-state.py` (every `changed_at_sha` / `tombstoned_at_sha` comes from it) while being
undeclared in the schema entirely — load-bearing and uncross-checked.

~~`schema_version` stays **1.0.0**.~~ **Superseded**: this change replaced `verdict`'s
value space, which §5.1 clause 3 now makes a bump. The document version is **1.1.0**.

## 8. The adapters (`id:90f2`)

| Path | What |
|---|---|
| `tracker/adapters/adapter_common.py` | the layer both adapters must agree on: the `schema_version` refusal gate, the **per-view carrier** (`id:857d`), and the canonical item graph the equivalence contract is stated over |
| `tracker/adapters/vikunja_adapter.py` | `plan` · `graph` · `apply` · `verify` |
| `tracker/adapters/plane_adapter.py` | `plan` · `graph` · `apply` |

`plan` and `graph` are **pure and offline**; `apply`/`verify` are the only networked verbs
and no test invokes them (`tests/test_tracker_adapter_equivalence.sh` asserts the offline
property with sockets disabled). Both adapters read credentials **by injection from the
environment only** — a literal-credential grep is part of the test.

### 8.1 What "equivalent item graphs" means

The item graph each adapter is compared on is **recovered from that adapter's own emitted
target payloads**, never re-derived from the source document — otherwise both sides would
merely echo the input and the comparison would be vacuous. Nodes carry `uid`, `title`,
`assignee`, the canonical label set, all three view statuses, `drift` and `derived_status`;
edges carry the canonical kinds `parent` / `child` / `blocked_by` / `link`, with the
dangling flag. The contract is asserted on all three fixture documents.

### 8.2 The `id:857d` per-view gate — binding, not advisory

Each adapter **must carry the `todo`/`roadmap`/`review` triple into its target**, plus a
visible drift marker. An adapter that reads only `derived_status` and renders one column
satisfies §1.2 in the JSON while defeating it in the product: cross-ledger drift becomes
invisible exactly where the owner would look for it. `adapter_common.check_gate()` is the
executable form, asserted for **both** adapters, and the test also proves the gate is not
vacuous by feeding each adapter a deliberately collapsed plan and requiring rejection.

The triple is written **twice** — as `view:<view>=<state>` labels *and* as an anchored
`[[ledger-views …]]` marker in the description — and recovery cross-checks them, so a
half-edited board is loud rather than quietly wrong. The marker is bracketed **plain
text, not an HTML comment**: both targets sanitise rich text, and a stripped comment would
silently delete the carrier.

### 8.3 Live verification status

| Target | Status |
|---|---|
| **Vikunja** | **VERIFIED LIVE** against v2.4.0 (2026-08-10): 19 items + 39 labels + 3 relations applied to the pilot project, `verify` PASS, re-apply idempotent (0 created), and a deliberately removed `view:todo=` label was **caught** by `verify` (exit 3) and repaired by re-apply |
| **Plane** | **VERIFIED LIVE** against v2.6.3 (2026-08-11, `id:90f2`): 19 items + 39 labels + 3 relations applied to the pilot project, `verify` PASS, re-apply idempotent. ~~UNVERIFIED — blocked on `id:02f7`~~ — **corrected 2026-08-18**: that blocker (rootless-podman/netavark nftables defect, nothing binding the proxy port) was RESOLVED by a host reboot on 2026-08-10 and the item is archived; this row asserting otherwise was stale for a week. Note the stack currently needs a manual start after each reboot — the quadlets carry no `[Install]` section — which `id:a532` now ratifies as boot-persistent |

Two known Plane gaps, recorded rather than papered over: its public API v1 documents no
issue-relation endpoint, so `blocked_by` / `link` edges emit a loud `WARN` and survive only
in the issue body (`parent` / `child` use the native `parent` field and are fine); and the
`derived_status → workflow state` map is **not injective** (`backlog` and `needs-decision`
share a column), which is exactly why `derived:<state>` is also a label.

A scoped Vikunja API token (`projects`/`tasks`/`labels`) **cannot** reach
`/tasks/{id}/labels` or `/tasks/{id}/relations` — both 401 (observed 2026-08-10). The
adapter therefore prefers a JWT from `VIKUNJA_USER`/`VIKUNJA_PASSWORD` when present and
falls back to `VIKUNJA_TOKEN`.
