# 2026-08-10 — Replacing the markdown ledgers with a work-tracking substrate

**Started:** 2026-08-10 09:06
**Session:** a35f46e6-97db-4c00-b52c-4ab08d9f50b1
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing), 🛰️ Hank (host-fleet config topology; cache-vs-derivation), 🏷️ Tilda (new — work-management substrate lens: tracker data models, API-vs-file access, agent-writability, sync topology, export and lock-in)
**Topic:** Should `TODO.md` / `ROADMAP.md` be replaced by a real work-tracking substrate (Vikunja, Fossil, …)?

> **`--fabled`:** run. One closing Fable-5 adversarial pass, 11 findings, **5 forced amendments**, all accepted. See `## --fabled closing pass`.

## Context — measured, not recalled

| Fact | Value |
|---|---|
| Ledger files fleet-wide (`~/src/*/`, `zkm/plugins/*/`) | 119 (`TODO.md` + `ROADMAP.md`) |
| Total ledger lines | 17,344 |
| `dotclaude-skills/ROADMAP.md` **after** archiving 100 done items this session | 1,738 lines / **254,087 bytes**, **69 open** ⇒ ~25 lines of prose per open item |
| `loderite/ROADMAP.md` | 1,682 lines / 264,060 bytes, 82 open |
| Non-test scripts in this repo reading/writing the two filenames | 34 |
| Test files touching them | ~150 |
| Live consequence | 2026-08-01: oversized ROADMAP → `Prompt is too long` → executor died, 481 lines parked as orphan, `RELAY_STATUS.md` reported a false `HANDBACKs (none)` |

Landed earlier in this same session (verified, `make test` 354/0/10-expected-red): `id:f54d`
wired `roadmap-archive.sh` into the integrator; `id:4f9b` added a pre-dispatch prompt-size
gate that refuses naming cause + remedy.

## Agenda

1. What is the *actual* pain — format, size, merge-collision, or queryability?
2. What hard constraints must any substrate satisfy, given LLM agents are the primary writers?
3. Candidates: keep-markdown + derived index (`id:2840`) · Vikunja · Fossil · GitHub Issues · local SQLite/Taskwarrior · others.
4. Smallest reversible first step.

## Discussion

### Round 1 — separating the pains

😈 **Riku** split the bundled complaint into four: **(a) size** (the executor death), **(b) merge
collisions** on a non-union checkbox, **(c) queryability**, **(d) format drift** in the bespoke
grammar. Only (b) and (d) are structural; (a) he attributed to the unwired archiver, (c) to grep.

🏷️ **Tilda** named the axis that actually selects between candidates: **who writes, and through
what interface.** The primary writer is an LLM agent in a sandbox, running unattended, sometimes
offline — which inverts the usual tracker trade-off. Vikunja puts a daemon in the pool's hot path;
Fossil's append-only ticket log genuinely answers (b) but means a second VCS across ~60 repos.

🛰️ **Hank** raised the collision with prior art: **`id:2840` ratified "markdown is SSOT, the index
is a cache, md wins, writes only touch md."** A tracker is the same axis with the sign flipped.
One of them must be explicitly amended. He also noted `[[dc5b-ledger-collision]]` — *"only getting
the state out of the shared file dissolves a ledger-merge collision"* — is the owner's own ratified
conclusion and is, verbatim, an argument for a tracker.

✂️ **Petra** applied the trigger discipline: `[[todo-infra]]` gated GitHub Issues on a topology-3
trigger (first outside PR/issue) that has never fired; in a one-human fleet, a tracker's core value
(shared visibility, assignment, notification) is worth ~zero.

⚙️ **Sage** raised the constraint he thought decisive: the executor contract **serializes ROADMAP
item text into an LLM prompt**, so markdown is prompt-native; and the `id:` ecosystem is
git-archaeology-friendly by construction (`git log -S id:93cc` is how the 2026-08-01 root cause was
found).

😈 **Riku** argued the contrary case: **the markdown ledger has grown a bespoke database with none
of a database's guarantees.** `roadmap-lint.sh`, `todo-conformance.sh`, `orphan-scan --cross-ledger`,
`md-merge.py`, `lib-typed-edges.sh`, `archive-closed.sh`, `unpromoted-scan.sh`, `scan-routed.sh` are
a schema validator, referential-integrity checker, transaction manager and GC — hand-written in bash.
`[[md-merge-1b1a]]` (silent append on no-match) and `[[acc7-write-integrity]]` (a phantom write) are
*missing-database* problems, each having cost a real incident.

⚙️ **Sage** proposed a middle path: keep markdown SSOT, but build the `id:2840` index as a **real
SQLite schema with constraints**, catching Riku's defect class at rebuild time with no migration.
🛰️ Hank and ✂️ Petra endorsed it as cache-vs-derivation done right and strictly inside ratified scope.

### Amendment round 1 — two premises corrected by the owner

**Premise (a) refuted by measurement.** The owner: *"Size is not fixed by archive, cf. Loderite's
vast backlog."* Verified: the archiver had already run — done items 100 → 1 — and `ROADMAP.md` is
**still 1,738 lines / 254 KB with 69 open items**. Archiving is structurally incapable of touching
open-item prose. 😈 Riku retracted his own point (a); it had been load-bearing.

🏗️ **Archie** stated the corrected argument: a tracker's real win is **addressability**.
`relay-loop.js` embeds the *whole file* because a text file's only granularity is "all of it." With
`GET /issues/{id}` the child prompt carries one item plus its dependency closure, and 254 KB is
never assembled. That deletes the failure mode rather than mitigating it.

🛰️ **Hank** identified the largest single insight, from the owner's *"the promotion TODO → ROADMAP
is just a different progress state"*: today the two ledgers are **two stores holding the same items**,
and `orphan-scan --cross-ledger`, `unpromoted-scan.sh`, the `id:2840` index, review-step-5's
twin-close and the whole dc5b collision are all consequences of that duplication. **In one item
store with a status field, promotion is `status: backlog → queued` and every one of them becomes
unrepresentable.**

⚙️ **Sage** withdrew his middle path, naming why it fails rather than merely conceding: dashboards,
re-assignment, `@routine` labels and dependency edges are properties of the **SSOT**, not the cache —
a read-only cache cannot be acted from. `REVIEW_ME.md` is prose *because* markdown has no assignee
field.

### The mapping (🏷️ Tilda)

| Today (bespoke markdown grammar) | Tracker primitive |
|---|---|
| `TODO.md` vs `ROADMAP.md` (two stores) | one store, **`status`** field |
| `- [ ]` / `- [x]` | status open / done |
| `[ROUTINE]` / `[HARD]` / `[INPUT — decision]` / `[MECHANICAL]` | **labels** |
| `<!-- gated-on:XXXX -->` | **blocked-by relation** |
| `<!-- children-of:XXXX -->` | **parent / subtask** |
| `REVIEW_ME.md` prose boxes | **assignee = human** + status `needs-decision` |
| `<!-- routed:XXXX -->` + shared inbox | cross-project **move / link** |
| `<!-- id:XXXX -->` | primary key |
| `orphan-scan`, `unpromoted-scan`, `roadmap-lint`, `todo-conformance` | schema constraints |
| whole-file prompt embedding | `GET /issues/{id}` |

### Candidate survey (web-verified this session, not recalled)

**Strong fits.** **Plane** — self-hosted Linear-alike, ~55k stars; **custom workflow states**
(matches promotion-as-status directly), blocking/blocked-by relations, cycles/modules, REST API,
reported MCP server + Projects-as-Code YAML, air-gapped deploy supported; multi-container compose.
**Vikunja** — single Go binary + SQLite/Postgres; `task_relations` (blocking, blocked-by, subtask,
parent, precedes) with **circular-dependency rejection at the API layer**; list/kanban/gantt/table;
Swagger API with **scoped tokens**; lightest ops; weaker custom status workflow.
**OpenProject / Redmine** — most mature dependency modelling (precedes/follows + Gantt); heavier, dated.

**Disqualified, each on a named axis.** **Taskwarrior 3 / TaskChampion** — best agent ergonomics in
the field (`task add`/`task export` JSON, offline, no daemon, real `depends:`, UDAs) but **no web
dashboard**, and 3.0's local DB is explicitly not rsync/Syncthing-safe. **git-bug** — issues stored
in git objects, offline, CLI+TUI+`webui`; but **no dependency model**, per-repo only, maintainers
still call it *"not fully stable."* **Forgejo/Gitea** — has issue dependencies and would double as a
git host, but boards are rudimentary and **[gitea#37151](https://github.com/go-gitea/gitea/issues/37151)
(April 2026) records that board ordering has no API at all, filed explicitly as blocking agentic
workflows** — hitting both hard requirements at once. **Fossil** — elegant single binary, tickets sync
with the repo, but no real dependency relations and a second VCS across ~60 repos; demoted by Tilda
herself. **Huly** — CockroachDB + Redpanda, not for one operator. **GitHub Issues + Projects v2** —
best agent interface (`gh`) and zero ops, but **this repo is public and has a privacy pre-push gate**;
ruled out on privacy independently of the never-fired topology-3 trigger.

### Amendment round 2 — archaeology dropped, dashboard requirement enlarged

The owner: *"I'm not sure I even want TODO git-archaeology in the future, it's not common convention
to actually bury issue tracking in the source code repo itself except in Fossil."*

🏗️ **Archie** recorded the consequence: **if archaeology isn't wanted, markdown need not survive as
an export** — the endgame is tracker-as-SSOT with the `.md` ledgers eventually *deleted*, not
generated. ⚙️ **Sage** retired his strongest objection: of his two bundled claims, only "the prompt
needs markdown text" survives, and that is one render call.

🛰️ **Hank** found a design flaw in what was about to be ratified: the owner asked for **fleet-level,
repo-grained state across ~60 repos** (*"which projects can currently relay-pool, which ones need my
feedback, which ones are currently design-drained"*), but the pilot was scoped to one repo and so
structurally could not show it. He noted the producer already exists — `classify-repo.sh` emits
exactly this per-repo verdict — and only a renderer is missing: `RELAY_STATUS.md` is a per-run
round-log, and `project_manager` has no web view.

😈 **Riku** asked whether a derived board over `classify-repo.sh` gets 80% for 5%, and answered his
own question: it is **necessary but not sufficient** — read-only, no re-assignment, no dependency
sort, no effect on prompt size — but should be named as a separate deliverable so a stalled tracker
pilot doesn't take it down.

✂️ **Petra** revised her own scope: since shadow mode touches none of the 34 scripts regardless of
breadth, importing all ~60 repos costs barely more than one and is the only shape that tests both
requirements. 🏷️ **Tilda** added the structural recommendation: a **common intermediate JSON** plus
one thin adapter per target, so the mapping — the actual intellectual content — happens once,
tool-independently.

## --fabled closing pass

**Verdict: run, Fable available, 11 findings — 5 FORCED amendments, 6 hardening. All 5 forced
amendments accepted by the owner; all 4 hardening groups adopted.**

1. **(FORCED)** Shadow mode cannot produce evidence about any requirement that motivated D1 — every
   one is a *write* interaction — and *"markdown SSOT, read-only view, rebuild from md"* is verbatim
   the `id:2840` architecture D1 amends. The pilot as designed cannot discriminate "2840 was right,
   we never built it" from "we need a tracker."
2. **(FORCED)** No import cadence or idempotency specced. A one-shot import is stale within a day, so
   the fail condition fires with probability ~1 *regardless of tracker merit*.
3. **(FORCED)** The headline requirement is repo-grained; the import is item-grained; the derivation
   is unspecced and neither tool computes it. Ironically the *fallback* addresses it more directly
   than the pilot.
4. **(FORCED)** The fail condition is unfalsifiable — no duration, no measurement — and lacks a
   baseline comparator, so it measures the value of *a* dashboard, not of *this substrate*.
5. **(FORCED)** The schema has one `status` per id, but the defining pathology is one id with **two**
   statuses; collapsing them silently launders drift.
6. (hardening) Identity keying unspecced — 4-hex ids collide fleet-wide; `routed:` edges cross repos.
7. (hardening) "Day one" contradicts "the mapping is the real work" — ratify a **loud lossy v0**. Plus
   GIGO: the board inherits every lie the ledgers tell.
8. (hardening) Nothing distinguishes this from `id:2840`'s seven unbuilt weeks; D5 routes to the very
   repo that sat on `routed:1e99`. Attach ids, lanes, and a pre-registered expiry.
9. (hardening) Two resident boards contaminate a habit-formation measurement.
10. (hardening) State transitions leave **reviewable git diffs** and enter **unreviewable API calls**;
    executor children holding API credentials is a live surface given `id:5937` (permissionMode=auto
    denies nothing). Materially favours the git-bug direction ⇒ sequence D5 as a **gate**.
11. (hardening) "Reversal = `docker compose down`" is understated; the named fallback is itself a
    third unbuilt artifact.

**Judged sound as ratified:** D2's schema-plus-thin-adapters shape; the exclusions of Forgejo,
GitHub and Fossil; and the owner's archaeology call.

**Escalation counter: 5 forced amendments this session (threshold ≥2).** Second independent firing
after `[[fabled-escalation-trigger-fired-4]]` (count 4, 2026-07-26), and higher. Standing evidence
for the per-decision pass and multi-pass `id:8df5` — owner's call, tracked as `id:43c8`.

## Decisions

- **D1 — Adopt a real work-tracking substrate, piloted.** This is an **explicit amendment to
  `id:2840`** ("markdown stays SSOT, the index is a cache"), recorded as an amendment on premises
  `id:2840` never weighed plus one now refuted — **not** a reinterpretation of its words.
  - *Refuted:* archiving bounds ledger size. Measured false — 69 open items = 254 KB post-archive.
  - *Not wanted (owner, this session):* git-archaeology for issues.
  - *Never weighed:* dashboards, assignee/re-assignment, labels, typed dependencies, and
    promotion-as-status — none of which a read-only cache can meet at any implementation quality.
  - **`id:2840` stays OPEN and annotated, neither closed nor built** — it is the fallback if the
    pilot fails. **Correction made during write-back:** the meeting initially said `id:659c` stays
    open; that is **wrong** — `id:659c` was **CLOSED 2026-07-29** (relay human, owner call;
    `TODO.archive.md:501`, `ROADMAP.archive.md:2865`). Its live successor is **`id:75db`**
    ("Re-decide the id:2840 derived-index consumer: (A) extend the index to emit checkbox-state +
    counts, or (B) keep `orphan-scan --cross-ledger` and drop the count prose"). The fallback named
    by this meeting's fail condition implies **option (A)** — annotated on `id:75db`, not decided
    there, since `id:75db` is its own `[INPUT — meeting]` item.
  - *Out of scope:* deleting any markdown ledger during the pilot; changing any of the 34 scripts or
    ~150 tests during the pilot.
- **D2 — One common intermediate JSON schema + thin adapters** (`id:2bb1`). Fields: `id`, `repo`,
  `status`, `labels`, `assignee`, `blocked_by`, `parent`, `title`, `body`. **Amended per finding 5:**
  the schema carries **per-view status** (`todo_status` + `roadmap_status`) or an explicit `drift`
  flag — never a collapsed single status — so cross-ledger drift is *represented*, and the board
  becomes the first place it is visible. **Amended per finding 6:** composite key `(repo, id)`;
  cross-repo 4-hex collisions **fail loudly at import**; an explicit stated policy for id-less TODO
  lines and REVIEW_ME boxes (import-as-untracked vs skip-and-report), never a silent skip.
  The mapping is the durable artifact and survives any tool outcome, including git-bug.
  *Out of scope:* committing to a tool at schema time.
- **D3 — Shadow-import all ~60 repos; `loderite` is the deep-fidelity pilot** (82 open items).
  **Amended per finding 2:** the import is a **recurring, idempotent pipeline**, not an event —
  host-side timer (the Workflow sandbox has no filesystem and no HTTP), upsert on `(repo, id)`,
  tombstone handling, and **each repo read at a pinned git SHA** per pass so a live relay merge never
  yields torn state. **Amended per finding 3:** the import **also creates one repo-level entity per
  repo** carrying `classify-repo.sh`'s verdict as labels/status — without it the fleet board cannot
  answer the question that motivated it. **Amended per finding 7:** v0 is **explicitly lossy** and
  says so — every pass emits an unmapped-constructs report with counts; loderite is the vehicle for
  burning that list down. *Out of scope:* fixing ledger data quality (the board inherits ledger lies;
  a trust failure may be a data failure, and must be distinguished from a tool failure).
- **D4 — Shadow mode plus a bounded owner-only write experiment.** Markdown stays SSOT and **zero
  relay scripts write to the tracker**. **Amended per finding 1:** the owner may edit freely on the
  **loderite** pilot; those edits are never written back, but a **reconciliation report enumerates
  what each edit would require of a write path** — and that report is the first real spec of the
  34-script migration. Without this the pilot could only ever evaluate read-only dashboards, i.e.
  the very architecture D1 amends. *Out of scope:* any write-back path in this phase.
- **D5 — git-bug is a GATE on non-shadow adoption, not a parallel curiosity** (amended per finding
  10). Question: could git-bug's git-object storage be extended or merged to cover the relation /
  label / assignee features Plane and Vikunja provide? It preserves reviewable state transitions and
  needs no service and no credentials distributed to executor children. Routed to `project_manager`.
- **D6 — Primary tracker deferred (`id:da1a`).** Both adapters are written against the schema; the
  **primary for the behavioural window is chosen after the adapters exist**, on real loderite data
  rather than on a survey. The second runs as a one-week fidelity spot-check, **not** a resident
  board (finding 9 — two resident boards halve the chance either becomes the habit).

### Pre-registered fail condition (amended per finding 4)

- **Window:** 4 weeks, starting at the **first successful full import**.
- **Comparator (control arm):** the cheap read-only board over `classify-repo.sh` output is **built
  as part of the experiment**, not held as insurance. Without it the measurement is
  tracker-vs-nothing and reports the value of *a* dashboard rather than of *this substrate*.
- **Measure:** a concrete usage proxy, not self-report.
- **Fail ⇒** the migration is unearned; fall back to the control-arm board + a constrained-SQLite
  `id:2840` index (`id:659c` / `routed:1e99`, kept open for exactly this reason).

### Pre-registered expiry (finding 8) — with a recorded residual

**Owner's call: 4 weeks from the actual _start_ of work** (not from this meeting's date). If no
successful full import has run by 4 weeks after work begins, the decision **auto-lapses** and the
fallback fires **without another meeting**.

> **Residual, surfaced not resolved:** an expiry keyed to "actual start" leaves the **never-started**
> case unbounded — which is precisely the shape of `id:2840`'s seven unbuilt weeks that finding 8
> was written to prevent. A `start-by` backstop date would close it. **Deliberately NOT invented
> here** — it is the owner's call, and is left open on `id:43c8`'s sibling line rather than
> silently chosen.

## This meeting resolves `id:4a5c` — and two of its questions were NOT weighed

Discovered during write-back: **`id:4a5c`** (filed by the owner 2026-07-29, `[INPUT — meeting]`,
TODO.md "## ledger substrate") is this meeting's brief, in far more detail than the agenda carried.
It is **closed by this note**, and the action items below are `children-of:4a5c` — no duplicate
cluster is minted (single-id-two-views).

Its analysis largely **agrees** with what was decided independently here: it cites `id:dc5b` as
supporting precedent, quantifies the concurrency tax (28 of 38 ledger-touching scripts use `flock`),
records the owner's capability reframe (*"better dependency (gated-on) tracking, what's in progress,
what's elaborated on"*), and measures the three capability gaps — **dependency coverage ~9%** (40
typed edges across 459 items, the rest prose), **in-progress NOT EXPRESSIBLE AT ALL** (a strict
2-state checkbox; in-flight state lives in `claim.sh` + `RELAY_STATUS.md` and *evaporates when the
run ends*), and **elaboration state** having only a lint proxy. It also carries a second independent
incident (`id:f762` / `routed:6fd8`): the inbox's vanish-on-resolve semantics made absence ambiguous
and produced a **false data-loss defect** against a working tool.

**Two of its explicitly-posed questions this meeting did NOT weigh. Recording the gap rather than
implying coverage:**

1. **Its option (3) — tracker as SSOT for the EXECUTION QUEUE ONLY** (`ROADMAP.md` moves; `TODO.md`
   stays markdown, being low-churn and mostly human-written). `id:4a5c` argues this is *"the shape
   that takes dc5b's dissolution where the collisions actually are while paying the availability
   cost only where it buys something."* This meeting weighed options (1), (2) and (4) and chose a
   full-tracker direction without ever putting (3) on the table. Note that Fable's finding 5
   (per-view `todo_status` + `roadmap_status`) partially preserves the two-view distinction inside
   the schema, but that is **not** the same as leaving `TODO.md` as SSOT.
2. **The cross-machine / offline write path.** `id:4a5c`'s "honest counter": today's parallelism is
   cross-machine (zomni / cartmanjaro / fievel / pixel), git syncs it with no service, no
   availability requirement and offline writes that reconcile later. A central DB **converts a class
   of merge conflicts into a class of availability failures**, and an agent that writes a file today
   would need a CLI/API path that works from a **Termux session on a phone**. Fable's finding 10
   touched the daemon-liveness half; the phone/offline write path was never discussed.

Filed as `id:330d` — surfaced, **not decided**.

## Action items

- [ ] [HARD] Author the common intermediate JSON schema + the full bespoke-grammar→tracker mapping (per-view status/drift flag; composite `(repo,id)` key; loud cross-repo collision failure; explicit id-less policy). Contract: a schema doc + fixture JSON; a test asserting a fixture ledger with a known cross-ledger drift round-trips with BOTH statuses preserved, and that a synthetic cross-repo id collision exits non-zero. See `docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md`. <!-- id:2bb1 -->
- [ ] [HARD] Build the markdown→intermediate-JSON importer over all ~60 repos (relay.toml own-set is the authority for the repo list + paths, honouring `# path:` — never a `~/src/*` glob). Pinned-SHA read per repo, upsert on `(repo,id)`, tombstones, loud-lossy unmapped-constructs report with counts. Contract: two consecutive runs over an unchanged fleet produce zero diffs; a mid-run ledger edit cannot produce torn state. <!-- children-of:2bb1 --> <!-- id:94ce --> <!-- gated-on:2bb1 -->
- [ ] [HARD] Write both adapters (Plane, Vikunja) against the intermediate schema. Contract: same fixture JSON yields equivalent item graphs — relations, labels, assignee, statuses — in both targets. <!-- children-of:2bb1 --> <!-- id:90f2 --> <!-- gated-on:2bb1 -->
- [ ] [HARD] Repo-level entity derivation: emit one entity per repo carrying `classify-repo.sh`'s verdict (relay-poolable / needs-feedback / design-drained / idle / blocked) as labels or status, so the fleet board answers the motivating question. Contract: for a fixture fleet, each repo's board status equals `classify-repo.sh`'s verdict for that repo. <!-- children-of:2bb1 --> <!-- id:c17d --> <!-- gated-on:2bb1 -->
- [ ] [HARD] Build the **control-arm** board — read-only, derived over existing `classify-repo.sh` output. This is the experiment's comparator, not insurance; the fail condition cannot be evaluated without it. Overlaps `project_manager`'s `id:36f1` web-graph item — reconcile before building rather than duplicating. <!-- id:8066 -->
- [ ] [ROUTINE] Host-side recurring import: `.service` + `.timer` (systemd `--user`) driving the importer on a cadence. `relay-loop.js` cannot do this — the Workflow sandbox has no filesystem and no `process.env` (id:2ec4). Contract: timer fires, import is idempotent, a failed pass never leaves partial state. <!-- children-of:94ce --> <!-- id:f116 --> <!-- gated-on:94ce -->
- [ ] [INPUT — access] Deploy Plane and Vikunja (docker compose) on a host reachable by the importer. Decide the host (zomni vs fievel) and whether the relay's host-side scripts can reach it unattended. Note finding 10: this makes a daemon a future relay liveness dependency, which the watchdog/heartbeat machinery knows nothing about. <!-- id:a532 -->
- [ ] [INPUT — author] Run the bounded owner-only write experiment on the loderite board and produce the reconciliation report enumerating what each edit would require of a write-back path. That report IS the first real spec of the 34-script migration. <!-- id:6f01 --> <!-- gated-on:90f2 -->
- [ ] [INPUT — decision] Pick the PRIMARY tracker for the 4-week behavioural window once both adapters exist and loderite is imported; the other becomes a one-week fidelity spot-check. Also set the expiry clock's start date, and decide whether to add the `start-by` backstop the meeting deliberately left open (the never-started case is currently unbounded). <!-- id:da1a --> <!-- gated-on:90f2 -->
- [ ] [INPUT — decision] `--fabled` escalation trigger fired a SECOND time, at 5 forced amendments (2026-08-10; first firing was 4 on 2026-07-26). Decide whether to build the per-decision Fable pass (fire before each `AskUserQuestion`) and the full multi-pass `id:8df5`. <!-- id:43c8 -->
- [ ] Explore whether git-bug's git-object storage can be extended/merged to cover the relation + label + assignee features Plane and Vikunja provide — as a GATE on non-shadow adoption (finding 10: keeps state transitions reviewable, no service, no credentials to executor children). → routed to `project_manager` inbox <!-- routed:2558 -->
- [ ] [INPUT — decision] Two questions `id:4a5c` posed that this meeting did NOT weigh: **(1)** its option (3) — tracker as SSOT for the EXECUTION QUEUE ONLY (`ROADMAP.md` moves, `TODO.md` stays markdown), which `id:4a5c` argues is the shape that pays the availability cost only where it buys something; **(2)** the cross-machine / offline write path — a central DB converts merge conflicts into availability failures, and an agent writing a file today would need a CLI/API path that works from a Termux session on a phone. Decide whether either reopens D1/D3, or record them as considered-and-declined. <!-- children-of:4a5c --> <!-- id:330d --> <!-- gated-on:2bb1 -->
- [ ] Annotate `id:2840` (open — the named fallback) and `id:75db` (the live successor to the CLOSED `id:659c`; this meeting's fail condition implies its option A) as amended-by-this-meeting. *(done in this session's write-back; recorded here for the audit trail.)*
