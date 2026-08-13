# `id:4fb8` — evidence for D2-A's gate on the interim ledger substrate (`id:55f6`)

**Status: EVIDENCE + RECOMMENDATION ONLY. Nothing was decided, nothing was built in the repo,
no ledger was migrated, no repo file was edited or committed.** All prototype code and fixtures
live in this scratchpad. `id:55f6`'s "Do NOT start building" was honoured throughout.

Sketched against the **amendments** (D4-A marker-truth / D5-A `priority:` in gaps of 100 /
D2-A gated), not the item's original prose.

---

## Executive summary

| Question | Answer | Evidence |
|---|---|---|
| Does a ported collector return an identical id set + `actionable_routine_open`? | **Yes — 28/28 real ledger states, exact match on all 8 emitted fields** | `equiv.py` over HEAD + 27 historical `ROADMAP.md` revisions, `aro` ranging 0–20 |
| Is the migration lossless in general? | **No — one live divergence class found: an indented `- [ ]` sub-item silently VANISHES** | `divergence.py` case D1: flat `aro=1`, tree `aro=0` |
| Is the collector I ported representative? | **No. `discover-repo.sh` is the LEAST representative of the twelve** | it reads a ledger in exactly one 8-line block and delegates the rest |
| Would per-item files have prevented the 4 stranded units? | **No — 2 of the 3 surviving branches also conflict on CODE files** | `stranded.sh`, `live_conflicts.py` |
| Dissolution rate, fleet-wide, today | **2 of 6 conflicting relay branches** | `live_conflicts.py` |
| Dissolution rate, this repo's whole history | **4 of 6 ledger-conflict pairs** | `conflict_analysis.py` over 416 merges |
| Current cost | **5 ledger-conflicting merges in 416 merges (1.2%) over 95 days = 0.37/week** | `git merge-tree` replay of every merge |
| Recommendation | **BUILD-NARROWER** — `id:c74e`'s per-id *bodies* only, checkbox lines stay put | below |

---

## Deliverable 1 — one collector, ported end to end

### 1.1 Which collector, and why the "smallest" pick is a trap

The gate names `discover-repo.sh` (200 lines) as "the obvious candidate". **It is the wrong
one, and the reason is itself a finding.** `discover-repo.sh` makes no git calls and does no
filesystem hunting by design (its own header, `:45`); it composes `reconcile-repo.sh` +
`classify-repo.sh` and folds their JSON. Its *entire* ledger-reading surface is one 8-line
block (`:167-174`) that regexes open `[ROUTINE]` lines out of `ROADMAP.md` for the SAME-ITEM
carve-out. Porting it against a per-item tree is ~10 lines and proves nothing, because the
`actionable_routine_open` and `actionable_routine_ids` the equivalence contract names are
produced by its delegate, **`classify-repo.sh` (467 lines)**.

So the honest port is: **`classify-repo.sh`'s Step-2 ROADMAP loop + `resolve-gates.sh`'s gate
resolution** (the actual producer of the contract's two fields), plus **`todo-conformance.sh`**
(the gate's named alternative, and the one with the hardest positional state).

### 1.2 The layout sketched against

Per D4-A (marker = truth, path = derived) and D5-A (`priority:` in gaps of 100, ties by id asc):

```
ledger/ROADMAP/<id>.md
---
id: b09e
priority: 300
section: "## Items"
section_exempt: false
under_heading_item: false
src_line: 24
---
- [ ] [ROUTINE] title … <!-- gated-on:4fb8 --> <!-- id:b09e -->
  continuation lines, verbatim
```

Gates stay as in-line `<!-- gated-on:XXXX -->` markers in the item's own body (D4-A). No
directories encode gate state. Non-item top-level content goes to `_chrome.md` — see §1.5,
this is load-bearing.

### 1.3 Equivalence result — 28/28 identical

`equiv.py` runs the flat reference and the tree port over **28 real ledger states**: this
repo's HEAD (`ROADMAP.md` 1,572 lines / 207 KB, `TODO.md` 669 KB, `TODO.archive.md` 647 KB)
plus 27 historical `ROADMAP.md` revisions sampled from `git log` (every 15th commit touching
it). Every field matched — `actionable_routine_ids` (order-sensitive), `actionable_routine_open`,
`roadmap_open`, `roadmap_actionable_open`, `open_mechanical`, `surfaced_open`, `hasRoutine`,
and the `why_not_ready` surface set:

```
dotclaude-skills  OK  aro=0/0   ids_eq=True  open=57/57  actionable=8/8
1d6d147           OK  aro=20/20 ids_eq=True  open=74/74  actionable=31/31
4be0627           OK  aro=18/18 ids_eq=True  open=72/72  actionable=29/29
cd54125           OK  aro=9/9   ids_eq=True  open=64/64  actionable=20/20
…                                                       (24 more)
28/28 identical
```

HEAD alone has `aro=0` (every open item is currently human-laned or parked), which would have
made a single-state test vacuous — hence the historical corpus, where `aro` ranges 0–20.

The flat reference is validated against the **live script**: `relay/scripts/classify-repo.sh
--emit unit` on this repo emits `actionable_routine_open: 0`, `open_mechanical: 0`,
`hasRoutine: true`, and `flat_classify.py` reproduces all three. `todo-conformance.sh TODO.md`
emits 12 `orphan` findings; the flat transplant reproduces exactly 12, and the tree port
reproduces the same 12.

### 1.4 Where it does NOT come out identical — one live divergence

`divergence.py` mutates the real ledgers and re-checks. Four of five adversarial cases stayed
identical (duplicate id, section rename, ordinary promotion, heading-as-item). **One diverges,
and it is the dangerous direction:**

```
D1  an indented `- [ ] [ROUTINE]` sub-bullet under an existing item
    roadmap_open             flat=58   tree=57
    roadmap_actionable_open  flat=9    tree=8
    actionable_routine_open  flat=1    tree=0
    actionable_routine_ids   flat=['dead']   tree=[]
```

Cause: `classify-repo.sh:164` matches `\s*- \[ \] ` — **indented sub-checkboxes count as
items**. A per-item exploder has to decide whether an indented checkbox is a new item or part
of the parent's body; treating it as body (the only choice consistent with
`todo-conformance.sh`, which never lints indented lines) makes the item **disappear from
dispatch entirely**. Today `ROADMAP.md` has 0 indented open checkboxes, so the corpus is
clean by luck; `TODO.md` has **11**. The two flat collectors already disagree with each other
on this construct, and the migration is forced to pick a side.

This is under-dispatch, not the re-dispatch hazard the gate names — but it is the same class:
a silently mis-migrated item. It would need a migration-time refusal (fail loudly on any
indented checkbox) rather than a silent choice.

### 1.5 How much changed, and what needed judgement

**`classify-repo.sh` Step-2 loop (~145 lines of the 467-line script):**

| | |
|---|---|
| Lines changed | 84 diff lines, of which **~40 are net-new plumbing** (frontmatter parser, tree loader, D5-A sort) |
| Mechanical | all of it except one line. `for ln in file` → `for … in load_tree(dir)`; the per-line predicates (`LANE_TAGS` anchoring, `@manual`/`@container`/`@owner-verify`, `🚧`/`BLOCKED on`, `⚠ SURFACED`, `@wire`, the `<!-- id: -->` anchor) are **line-scoped and ported byte-identically** |
| Needed real judgement | **exactly one line**: `in_exempt_section`. Flat derives it from a running heading scan (`_EXEMPT_HEADING_RE` over `##+` lines). A per-item tree has no headings, so the fact must be **hoisted into frontmatter at migration time** — a new denormalised field with no reconciler |

That single line is the whole port's real content, and it is a **new drift surface D4-A does
not cover**. D4-A ratified "marker is truth, path is derived, a mechanical check reconciles"
**for gates only**. Section membership gets the opposite treatment: it becomes truth-in-
frontmatter with *no* source to reconcile against, because the heading it was derived from no
longer exists. Renaming `## Items` → `## Items (deferred)` is one flat edit that re-parks every
item beneath it; in the tree it is an N-file frontmatter rewrite with nothing to detect the
half-done state. Measured N for this repo: `## Relay` holds **89** TODO items, the ROADMAP
human-triage heading holds **33**.

(My `divergence.py` D3 case reports IDENTICAL only because the harness re-explodes after the
mutation. That tests *migration* fidelity. In steady state the tree is SSOT and nobody
re-explodes — the drift is real and untested by construction.)

**`todo-conformance.sh` (249 lines):** the grammar (`classify_todo`) ports **unchanged** — every
rule is line-scoped. Two structural changes, one good, one bad:

- *Good:* the `--fix` path's line-number machinery (15 line-number references, `sed -n "${ln}p"`,
  `sed -i "${ln}s|…|"`, plus a `$path.conformance.lock` flock) collapses to "open the item's
  file, rewrite it". That is a genuine simplification — maybe −25 lines.
- *Bad, and it defeats the collector's purpose:* **all 12 of its findings on the real `TODO.md`,
  and all 143 on `ROADMAP.md`, live in `_chrome.md`** — 100%, both files. The linter exists to
  find top-level lines that are **not well-formed items**. A per-item tree cannot represent a
  non-item, so every one of them lands in a leftover flat file. That file is small (1% of
  `TODO.md`, 8% of `ROADMAP.md`) but it is a **reintroduced shared, non-union, hand-edited
  markdown file holding exactly the content that is malformed** — plus every heading, which is
  what the `section:` frontmatter is denormalised from.

### 1.6 Extrapolation to the other eleven — is my pick representative?

**No, in both directions, and the two errors do not cancel.**

`discover-repo.sh` (200) is *unusually easy* — the easiest of the twelve. `classify-repo.sh`'s
loop is *middling*. The heavy ones are heavier than either:

| Collector | Lines | Port character |
|---|---|---|
| `discover-repo.sh` | 200 | **trivial** — 1 ledger read, ~10 lines |
| `unpromoted-scan.sh` | 436 | line-scoped; likely near-mechanical |
| `classify-repo.sh` | 467 | **the one measured** — ~40 new lines, 1 judgement call |
| `gather-repo-state.sh` | 486 | same `in_exempt_section` walk (`lib-roadmap-sections.sh` consumer) — same 1 judgement call, twice |
| `todo-conformance.sh` | 249 | grammar free, `--fix` simplifies, **purpose partly defeated** (§1.5) |
| `orphan-scan.sh` | 518 | 14 line-number references; cross-ledger id correlation — probably simplifies |
| `scan-routed.sh` | 337 | 5 line-number references; cross-repo, mostly line-scoped |
| `gather-human-backlog.sh` | 782 | mostly line-scoped; own-id resolution is already a known-fragile spot |
| `meeting/append.sh` | 539 | **append-to-a-section** is its whole job — becomes "create a file + pick a priority"; rewrite, not port |
| `roadmap-lint.sh` | 763 | 41 heading/section references; owns `is_exempt_heading`. Its *grammar* rules become per-file (easier); its *section* rules lose their referent |
| `roadmap-archive.sh` | 256 | **does not port.** Its documented contract is "a grouping heading that this run EMPTIES … is MOVED into the archive with it, UNLESS protected (H1/Items/Current/Done/Backlog)". With no headings, that semantic has to be re-invented from scratch |
| `meeting/md-merge.py` | 428 | **becomes largely moot — see §3.2.** It is already an id-keyed, flock'd, atomic, non-clobbering per-item writer *inside* the flat file |

Honest extrapolation: roughly **half the ~5,400 lines port mechanically** (the line-scoped
predicates, which dominate), **~2 collectors get rewritten** (`roadmap-archive.sh`,
`meeting/append.sh`), **~2 lose their reason to exist in current form** (`md-merge.py`,
partly `todo-conformance.sh`), and the **same one judgement call — where does section
membership live? — recurs in at least 4** (`classify-repo`, `gather-repo-state`,
`roadmap-lint`, `roadmap-archive`) and must be answered identically in all of them or the
`lib-roadmap-sections.sh` twin-consumer invariant breaks. That is a real "×57 repos" migration,
not a cheap bridge.

---

## Deliverable 2 — the conflict trade, measured

### 2.1 Current cost

**Method (reproducible):** replay every merge in this repo's history with
`git merge-tree --write-tree --name-only <p1> <p2>` and record which conflict, on what.

```
total merges scanned:                416      (2026-05-10 → 2026-08-13, 95 days)
merges that conflicted at all:        10      (2.4%)
merges that conflicted on a ledger:    5      (1.2%)
ledger-conflict (merge,file) pairs:    6
```

**Rate: 0.37 ledger-conflicting merges per week**, in the fleet's most heavily-relayed repo.

For each of the 6, I computed which item ids each side changed relative to the merge base.
Per-item files dissolve the conflict iff those sets are disjoint:

```
b50e8b5  ROADMAP.md  DISJOINT   sideA=7 sideB=1
1b2ac7c  ROADMAP.md  SAME-ITEM  cb3e
1b2ac7c  TODO.md     SAME-ITEM  cb3e
607749d  TODO.md     DISJOINT   sideA=1 sideB=1
40c892d  ROADMAP.md  DISJOINT   sideA=1 sideB=1
067fb54  TODO.md     DISJOINT   sideA=8 sideB=3
                                → 4 dissolved, 2 not
```

### 2.2 The motivating incident, verified — and it does not say what the item says

`id:2b4b` records the "why now": run `relay-20260812-122721-23819` left **four branches with
real unmerged commits** while `relay-reconcile.sh --all` reported "0 parked orphans". Per the
CLAUDE.md rule that a claim about code behaviour is a derived doc, I re-derived it against the
branches themselves (`stranded.sh`). Three survive; loderite's is gone. All three still
conflict today:

| repo | branch | conflicts on |
|---|---|---|
| cartulary | `…-execute-repo-1` | `ROADMAP.md` **+ `tests/test_gitattributes_guard.py` (add/add) + `tests/test_tier_a_validator.py`** |
| dotclaude-skills | `…-review-repo-0` | `REVIEW_ME.md` + `ROADMAP.md` |
| escapement | `…-review-repo-0` | `REVIEW_ME.md` + `ROADMAP.md` **+ `tests/test_registry_prose_intake.py` (add/add)** |

**Two of the three would still be stranded under a per-item ledger tree**, because they also
conflict on code — two executors independently created the same new test file. A ledger
substrate does not touch that class at all. The item's framing ("a child that hits a
ROADMAP.md merge conflict … hands back") is accurate for the ledger half and incomplete for
the incident.

### 2.3 Dissolution rate, fleet-wide, today

`live_conflicts.py` over **all 31 `refs/heads/relay/*` branches in `~/src/*`**; 6 conflict with
their `main`:

```
loderite        …execute-1068-0   DISSOLVED       ROADMAP.md:disjoint
truncocraft     …execute-1068-0   DISSOLVED       ROADMAP.md:disjoint
cartulary       …execute-repo-1   NOT-dissolved   ROADMAP.md:SAME(65bd,9cc2,ee78) +code
escapement      …review-repo-0    NOT-dissolved   REVIEW_ME.md:SAME +ROADMAP.md:SAME(2064) +code
dotclaude-skills…review-repo-0    NOT-dissolved   REVIEW_ME.md:SAME(55 entries) ROADMAP.md:SAME(ed3f)
linguistic-univ …review           NOT-dissolved   ROADMAP.md:disjoint  +CLAUDE.md
                                                  → 2 dissolved / 4 not
```

**Combined across both samples: 6 of 12 measured conflict instances dissolve.** The interim
removes about half of a 0.37/week problem in the busiest repo.

### 2.4 A blocker nobody has named: `REVIEW_ME.md` has no ids

`REVIEW_ME.md` is one of the three shared non-union write surfaces (CLAUDE.md, Conventions),
and it conflicts in **2 of today's 6**. Measured:

```
REVIEW_ME.md top-level checkbox entries:  57
…carrying an <!-- id:XXXX --> token:       2
```

**55 of 57 entries cannot be filed into an id-keyed per-item tree at all** — there is no key.
The migration would have to mint 55 ids first (and the corresponding count across ~57 repos),
which is itself a ledger-wide write. This is why the dotclaude-skills row above shows
`SAME(_noid_0 … _noid_54)`: with no ids, *every* entry collides with *every* entry.

### 2.5 Introduced cost

D4-A genuinely removes the rename/rename hazard: gates are content edits, so gate transitions
never move a file. What remains:

- **`priority:` renumbering — effectively zero.** Gaps of 100 mean insertion never renumbers.
  The cost is not renumbering, it is *volume*: the meeting accepted "~69 values per repo". The
  real number for this repo, if both ledgers explode (they must — half the measured conflicts
  are in `TODO.md`), is **57 ROADMAP + 431 TODO = 488 values**, ~7× the accepted estimate,
  ×57 repos. `id:5a14`'s lint has to police all of them.
- **Archive/close moves files.** `TODO.archive.md` was modified in **143 commits** (2 in May,
  56 in Jun, 74 in Jul, 11 in Aug ≈ **1.6/day**). Items moved per archive commit: median 3,
  mode 1, max 19. Each becomes a `git mv` of 1–19 files. Archive-vs-edit on the same item is a
  modify/delete conflict — roughly as bad as today's content conflict, not clearly worse.
- **Same-item concurrent edit — the class per-item files never dissolve.** Measured at
  **2 of 6 historically and 3 of 6 today** (cartulary `65bd/9cc2/ee78`, escapement `2064`,
  dotclaude-skills `ed3f`). Note the direction: in *today's* sample same-item collisions are
  the **majority** of the non-dissolved cases, not the tail.
- **Storage/frontmatter overhead:** exploded `TODO.md` totals 730 KB vs 669 KB flat (+9%);
  `ROADMAP.md` 203 KB of items + 15.7 KB chrome vs 207 KB flat.

### 2.6 Against this repo's own heuristics

- *Observe before preventing:* the observation exists and is **0.37 ledger-conflicting merges
  per week, halved**. The prevention is a ~5,400-line, 57-repo migration. This heuristic argues
  against, clearly.
- *Archiving does not bound ledger size* (`ROADMAP.md` stayed 254 KB / 69 open after archiving
  100 items) — **this one argues FOR**, and it is the interim's strongest surviving card. It is
  a *size/context* argument, not a conflict argument, and the meeting filed the item under
  conflicts. Today's `ROADMAP.md` is 207 KB and `roadmap_bytes` is already a live field
  (`id:4f9b`) precisely so dispatch can refuse an oversized prompt. Per-item files fix that
  outright: a child loads its own 3.5 KB item instead of 207 KB.
- *Prefer dissolving structurally over guarding* — argues for; but see §3.2.

---

## Deliverable 3 — recommendation (a RECOMMENDATION, not a decision)

### 3.1 **BUILD-NARROWER** — `id:c74e`'s per-id bodies, checkbox lines stay in place

Adopt `id:c74e`'s cheaper alternative: **per-id files for item BODIES only, leaving the
checkbox lines where they are** in `ROADMAP.md` / `TODO.md`. Do **not** explode the checkbox
lines, do not add `priority:`, do not add `section:`, do not move gates.

Why the evidence points here:

1. **It captures the benefit that survived scrutiny and drops the one that did not.** The
   size/context benefit is real and unbounded by archiving (207 KB `ROADMAP.md`; mean item
   3.5 KB; longest single line 8,503 chars). The conflict benefit is 6-of-12, and the bulk of a
   conflict's *surface area* is the multi-KB body prose, not the one-line checkbox — moving the
   bodies out shrinks what can collide without touching a single collector's parsing.
2. **Zero collectors port.** Every one of the twelve reads `^\s*- \[[ x]\] ` lines under
   headings. Leave those lines in place and the ~5,400 lines stay untouched, `in_exempt_section`
   keeps its referent, `roadmap-archive.sh`'s heading semantics keep theirs, `append.sh` keeps
   appending to a section, and `md-merge.py`'s id-keyed contract is unchanged.
3. **It sidesteps the two blockers.** No ids needed for `REVIEW_ME.md`'s 55 keyless entries
   (they keep their lines); no forced choice on indented sub-checkboxes; no 488-value
   `priority:` field to lint (`id:5a14` becomes unnecessary, not merely gated).
4. **It is reversible and cheap to abandon** if cartulary lands — the bodies are markdown files
   keyed by id, which is trivially re-ingestible into a TOML-per-record store.

### 3.2 The strongest argument against my own position

**The narrow version does not fix the thing that actually stranded units.** A body-only split
still leaves the checkbox lines in one flat non-union file, so an executor's tick and a
reviewer's tick still collide there. Of my 12 measured instances, the ones that dissolve are
exactly the *disjoint checkbox-line* cases — and body-only keeps those lines together. So the
narrow build buys context/size and body-conflict surface, and buys **~0 of the 6 dissolutions**.
If the owner's priority is the stranded-unit class specifically, BUILD-NARROWER is the wrong
answer and full per-item is the right one.

Three things blunt that objection, and the owner should weigh them:

- Full per-item only dissolves **2 of today's 6** anyway (code conflicts and same-item
  collisions dominate), so even the maximal build leaves the class mostly intact.
- **`meeting/md-merge.py` already is the per-item substrate for the same-machine path.** Its
  contract, verified in-file: *"two sessions editing different items/sections both survive;
  same-item serializes with last-under-lock winning without clobbering others"*, id-keyed on
  the anchored `<!-- id:XXXX -->` regex (`md-merge.py:178`), flock'd, atomic tmp+rename,
  optional atomic commit under the same lock. The disjoint-item benefit per-item files promise
  is **already delivered** for every concurrent-session write. What per-item files add is only
  the *cross-branch `git merge`* path — the 2-of-6.
- The residual is better attacked where it actually lives: two executors creating the same test
  file, and `REVIEW_ME.md` having no ids.

### 3.3 The `id:c74e` caveat, and whether a D4-A interim diverges from cartulary

`id:c74e`'s standing caveat — *"ratifying this migration first would sink significant cost into
a substrate `id:4a5c` might replace"* — **still binds, and D4-A did not neutralise it.**

Verified in cartulary (not taken from the meeting note): `edits.py:50` writes
`"gated_on": sorted(gated_on)`, and `merge_driver.py:119-133` performs a real 3-way set merge —
`base_set` / `ours_set` / `theirs_set` → `merged["gated_on"] = sorted(result_set)`. Cartulary's
ratified representation is a **sorted list-valued field with a working set-merge driver**.

D4-A improved the match by withdrawing path-as-truth — gates are now content, and content is
what a merge driver operates on. But the shapes still differ: D4-A's gates are **N separate
inline `<!-- gated-on:X -->` HTML comments embedded in a prose line**, cartulary's are **one
list field in a structured record**. A driver cannot be registered on the markdown to close the
gap, for a reason this repo already learned the hard way (surfaced in the same meeting):
**registering any custom merge driver on a path defeats git's add/add refusal — git hands the
driver `basesize=0`**. So the interim's gate representation is a **third form** that must be
re-ported to cartulary's, and the interim cannot borrow cartulary's driver. **Yes, it still
diverges — less than under D4, but it diverges.**

Add the timing: cartulary's `ROADMAP.md` is 10 open / 0 done, and its `id:09f9` (record storage
topology — one central tree vs a `records/` tree per repo) is **unratified and owner-deferred**.
That is the same question a full interim would answer by accident, in a different substrate.

### 3.4 If the owner rules BUILD (full per-item) anyway

Three preconditions the evidence says are non-optional, none of which any ratified decision
currently covers:

1. **Migration must fail LOUD on an indented checkbox**, never silently fold it into a body
   (§1.4 — the one measured divergence, and it deletes dispatchable work).
2. **Section membership needs a named owner and a reconciler.** D4-A gave gates marker-truth +
   a mechanical check; `section_exempt` gets frontmatter-truth with no source. It is the single
   judgement call in the port and it recurs in ≥4 collectors that share
   `lib-roadmap-sections.sh`.
3. **`REVIEW_ME.md` needs 55 ids minted before it can be exploded** — or it must be declared
   out of scope, in which case it keeps conflicting (2 of today's 6).

And a correction to a cost the meeting accepted: D5's *"~69 values per repo"* is **488 for this
repo** if both ledgers explode.

---

## Reproduction

All in this scratchpad, stdlib-only:

| File | What |
|---|---|
| `explode.py` | flat ledger → per-item tree (D4-A/D5-A layout) |
| `flat_classify.py` | verbatim transplant of `classify-repo.sh:122-266` + `resolve-gates.sh` |
| `tree_classify.py` | the PORT (`# PORT:` marks every diff-relevant change) |
| `equiv.py` | 28-state equivalence run |
| `conformance.py` | `todo-conformance.sh` grammar, flat transplant + tree port |
| `divergence.py` | 5 adversarial migration cases against the real ledgers |
| `conflict_analysis.py` | replay of all 416 merges; dissolve/not per conflict |
| `stranded.sh` | verifies the `id:2b4b` incident branches; fleet-wide branch merge status |
| `live_conflicts.py` | fleet-wide dissolve/not for every currently-conflicting relay branch |
| `stats.py` | item counts, chrome share, section sizes, finding provenance |
| `work/`, `tree/`, `hist/` | copies + exploded fixtures (never in the repo) |

```
python3 equiv.py ~/src/dotclaude-skills hist/*
python3 divergence.py
python3 conflict_analysis.py
python3 live_conflicts.py
bash stranded.sh
```
