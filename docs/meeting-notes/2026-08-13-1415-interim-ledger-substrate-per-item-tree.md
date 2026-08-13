# 2026-08-13 — Interim ledger substrate: per-item tree as a bridge (id:55f6)

**Started:** 2026-08-13 14:15
**Session:** 99a65222-c4a7-4a14-860d-31a1d3277877
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🏷️ Tilda (work-management substrate), 🔩 Gil (git object model / merge), 🛰️ Hank (config topology, cache-vs-derivation)
**Topic:** Whether to explode the flat markdown ledgers into a per-item file tree as a cheap interim before cartulary lands — and if so, on what terms.

> **--fabled:** the opt-in closing Fable-5 adversarial pass RAN. Fable was available
> (`fable-config.sh check` → `available`, exit 0). It returned **10 findings, 7 of which
> forced amendments** — every one of the five ratified decisions was amended. See
> `## --fabled closing pass` below.

## Surfaced discoveries

`EMBED_ENDPOINT` was unset and `discoveries.md` is 195 KB, so a keyword pass was run instead of the
full read (deviation recorded rather than hidden).

- `[2026-08-12 cartulary]` `merge=union` in `.gitattributes` **silently corrupts** — two branches
  editing the same scalar merge clean, emit two `key = value` lines, no conflict shown.
- `[2026-08-12 cartulary]` Registering **any** custom merge driver on a path **defeats git's add/add
  refusal** — git hands the driver `basesize=0`.
- `[2026-08-10 dotclaude-skills]` Archiving done items does **not** bound a markdown ledger —
  `ROADMAP.md` stayed 254 KB / 69 open after 100 items were archived. The bloat is the open backlog.
- `[2026-08-12 escapement]` A sibling repo's ratified decision can expire your premise **mid-meeting**,
  and only a closing pass will catch it. *(This recurred here: see F6.)*

## Agenda

1. **Premise check** — is "cartulary is the ratified END state, this is the interim" true today, and
   what is the live status of the `id:4a5c` tracker pilot?
2. Does an interim earn its cost, or does it double the migration? (`id:55f6` vs `id:c74e` vs wait)
3. Gate-state-as-a-directory is duplicated state — which side is truth?
4. Does ROADMAP **file order** survive a directory layout?
5. What renders the human view, and how do the 12 collectors port?

## Discussion

### 1 — The premise

🏗️ **Archie** checked the item's framing sentence — *"cartulary (`id:4a5c` pilot, TOML-per-record) is
the ratified END state"* — against ratified sources. Two clauses hold, one is a splice.

The TOML clause is **true and verified**: `cartulary/TODO.md:15`, verdict `id:6107` **closed
2026-08-12**, arm (b) TOML-per-record, owner-ratified; git-bug out on R2+R8 absent, recutils out
because 1.9's FK *and* composite-key checks both exit 0 on violations.

The `id:4a5c` clause is a splice. `4a5c` ratified a **tracker pilot** — Plane and Vikunja,
shadow-mode, markdown stays SSOT (`TODO.md:382`). Cartulary is a different project founded a day
later, and its `ARCHITECTURE.md:46` records R1 — *"Offline write from any fleet machine including
Termux — no server, no daemon in the hot path"* — annotated **"`id:330d`; killed Vikunja/Plane."**

😈 **Riku** argued the annotation should not be swallowed: a derived doc cannot narrow a ratified
decision, and `dotclaude-skills/TODO.md:382` still heads the section **DECIDED — tracker pilot** with
live open work beneath it (`id:90f2` both adapters verified LIVE, Beads admitted as a third arm;
`id:e977` 15 homonyms still blocking the fleet import; `id:2902` the offline-write criterion with
nowhere to be logged). He noted the sharpest edge: `330d`'s offline-write question was deliberately
converted into a **pilot acceptance criterion** — measure, don't argue — and R1 then cites `330d` as
having *killed* Plane/Vikunja, which is the argument the conversion existed to prevent, made before a
single occasion was logged.

> **This reasoning was later found defective by the closing pass — see F6 and D1-A.** The
> "derived doc" label was applied without diffing cartulary's founding meeting note, which is the
> check the rule actually requires. Recorded here as argued, and corrected below.

🏷️ **Tilda** (who ran the `4a5c` bake-off framing) accepted R1 is probably right on the merits but
distinguished *"the pilot is superseded"* from *"someone wrote that the pilot is superseded."* The
consequence is concrete: if the pilot is dead, `id:90f2` and `id:e977` are dead work looking
dispatchable; if alive, cartulary is a parallel effort and "the ratified end state" is not settled.

✂️ **Petra** named the real cardinality: **three** live proposals, not two — `id:55f6`, `id:c74e`
(INBOUND `routed:207b`, generated indices + per-id bodies, whose own text says *"Decide them TOGETHER
or explicitly order them"*), and cartulary.

🏗️ **Archie** on readiness, since *"until cartulary lands"* is load-bearing for the word *interim*:
cartulary's `ROADMAP.md` has **10 open, 0 done**, and its `id:09f9` — record storage topology, one
central tree vs a `records/` tree per repo — is **unratified**, owner-deferred with nothing amended.
That is the same question `55f6` is asking, so ratifying a tree topology here would answer `09f9` by
accident, in a different substrate.

🔩 **Gil** corrected the item's load-bearing engineering claim. `55f6` says *"per-item files are
trivially unionable"* — they are not unionable, they are **disjoint**, which is strictly better and
needs no merge driver. The distinction matters because the fleet was burned twice this week on the
other reading (`merge=union` silently corrupting; any registered driver defeating add/add refusal at
`basesize=0`). The benefit comes from disjointness and survives only if nothing registers a driver.

🛰️ **Hank** put the cost on the table: **12 collectors, ~5,400 lines** — `roadmap-lint.sh` 763,
`gather-human-backlog.sh` 782, `orphan-scan.sh` 518, `gather-repo-state.sh` 486, `classify-repo.sh`
467, `append.sh` 446, `unpromoted-scan.sh` 436, `md-merge.py` 428, `scan-routed.sh` 337,
`roadmap-archive.sh` 256, `todo-conformance.sh` 249, `discover-repo.sh` 200 — times ~57 repos.
Against ledgers of 1,572 / 696 / 307 lines and a longest single line of **8,503 characters**. His
standing objection: nobody has measured whether the migration cost is recovered before cartulary lands.

⚙️ **Sage** flagged `cartulary/README.md` still reading *"no substrate committed yet … being decided
by a three-arm bake-off"* — stale since the 2026-08-12 verdict, and the third restatement in one
discussion to have drifted from its source.

### 2 — The owner's addition: ledger as a worktree of a separate branch

**Zommuter:** *"maybe keep the items in a subdir that's actually a worktree of a separate
issue-tracker branch (plus maybe `git merge --strategy=ours` on that to link commits to the tracker
updates)"*

🔩 **Gil** rated it the strongest shape on the merits: per-item files make collisions *unlikely*
(disjoint paths); a separate branch makes them **structurally impossible for the code-integration
path**, because `ROADMAP.md` is not in the merge at all. The four units stranded this run become
unreachable rather than rarer — dissolution over guarding. His three attacks:

1. **`git worktree` refuses to check out the same branch twice**, and the relay is multi-worktree by
   construction. `--detach` gives a read-only checkout, useless for `md-merge.py --commit`.
2. **`-s ours` is directional.** On the tracker branch (`tracker: git merge -s ours main`) it records
   "tracker state T corresponds to code state C" — sound. On `main` it records tracker as an ancestor
   while taking none of its content, so any future *real* merge is a silent no-op.
3. **Atomicity is lost.** `md-merge.py --commit` writes and commits under one flock today (closing the
   `id:debf` scoop window, keeping `id:aa93`'s dirty-guard clean). Split across branches, "code landed"
   and "box ticked" are two commits with no transaction; `-s ours` links after the fact.

🏗️ **Archie** added the fourth: **a missing worktree is indistinguishable from an empty backlog.**
`classify-repo.sh` reading an unmounted `ledger/` reports `actionable_routine_open: 0`, byte-identical
to "this repo has no work" — the silent-false-clean class (`id:47f7`, `id:4e14`).

🏷️ **Tilda** noted a tracker branch *per repo* is the per-repo answer to cartulary's deferred `09f9`,
so choosing it here would make the central-tree option materially harder to pick later.

✂️ **Petra**: tree + branch + worktree mount + link protocol + unmounted-detector is not the cheap
bridge `55f6` was pitched as.

⚙️ **Sage** named the one property lost by routing it away: a tracker branch is independently
pushable, the closest thing to cartulary's R1 available in the interim, and the only mechanism on the
table that could serve `id:2902`'s offline logging.

😈 **Riku**: strongest on merits, most expensive, one possibly-fatal unknown — not ratifiable on
argument.

### 3 — Gate state, and what replaces file order

**Verified this session:** `classify-repo.sh:12` documents `actionable_routine_ids` as *"the 4-hex ids
BEHIND that count, in ROADMAP FILE ORDER"*, and `:443` *"names `actionable_routine_ids[0]` in the
execute dispatch so the child goes straight to its item."* **File order is the dispatch priority
function.** `55f6`'s open question (d) is load-bearing, not cosmetic.

🏗️ **Archie** on gate state: `55f6`'s own question (a) spots that a `gated-on/<id>/` path and a
`gated-on:` marker are two copies of one fact. Its own suggested resolution — path derived, marker
truth, mechanical reconcile — is safe but costs the headline: if the path is derived, the filesystem
*caches* the gate graph rather than expressing it.

🔩 **Gil** argued marker-as-truth: path-as-truth makes every gate transition a **rename**, so two
sessions produce rename/rename conflicts, which git handles far worse than a one-line content edit.

😈 **Riku** insisted that if marker-truth wins, the foldered gate graph — the item's most attractive
picture — is gone, and the smaller idea should be re-pitched honestly rather than kept under the
original headline.

🛰️ **Hank** on ordering: three options, none free. A `priority:` field (explicit, but ~69 values per
repo that rot); an `NNN-<id>.md` prefix (cheap, but reprioritisation is a rename); or one ordered
index file (`c74e`'s shape — reintroduces exactly one shared non-union file).

### 4 — Amendment session: multi-gate items under path-is-truth

After `D4` ratified path-as-truth, 🏗️ **Archie** raised that a file lives in exactly one directory, so
a multi-gate item has no home. **Measured** (typed `<!-- gated-on:XXXX -->` markers only; a first pass
counting `gated-on:` per line was an upper bound including prose, and was discarded):

| repo / file | items with a typed gate | **multi-gate** |
|---|---|---|
| dotclaude-skills/ROADMAP.md | 6 | **2** |
| dotclaude-skills/TODO.md | 27 | **2** |
| loderite/ROADMAP.md + TODO.md | 25 | 0 |
| cartulary/ROADMAP.md + TODO.md | 7 | 0 |
| lodelore, relay-core | 2 | 0 |

😈 **Riku** noted one of the four is `routed:886b`, itself a silent bug *in the typed-edge engine* —
so the substrate would fail on its own reflexive case. 🔩 **Gil** laid out four representations
(compound directory, symlink, primary-in-path hybrid, refuse multi-gate), none free. The owner
ratified the **compound directory**; the closing pass then reversed it (F3 → **D4-A**).

## Decisions

**Decision provenance:** ratified through `AskUserQuestion` at each decision point (Opus-class
harness; plan mode skipped per `format.md` §Plan-mode gate). Originals are recorded verbatim below and
are **never rewritten** — the closing-pass amendments are **appended as superseding entries** citing
what they supersede.

### As originally ratified

- **D1** — Three parallel substrate programs, **named**: cartulary (TOML verdict landed `id:6107`,
  topology `id:09f9` open), the `4a5c` tracker pilot (Plane + Vikunja both verified live, Beads
  admitted as third arm, 15 homonyms blocking fleet import, `id:2902` acceptance criterion
  unrecorded), and this merged interim. **Nothing is retired**; cartulary's `ARCHITECTURE.md:46`
  "killed Vikunja/Plane" is a derived-doc claim, not a ratification.
  *Provenance: owner selected "Both live, name it".*
  **Out of scope:** retiring, re-scoping or defunding any of the three.

- **D2** — The interim **proceeds** as a per-item tree; `id:55f6` and `id:c74e` **merge into one item
  first**, carrying `c74e`'s standing caveat verbatim.
  *Provenance: owner selected options 2 AND 4 ("2&4").*
  **Out of scope:** building anything — `55f6` says "Do NOT start building".

- **D3** — The tracker-branch/worktree shape is **routed to cartulary's `id:09f9`** as a third
  candidate storage topology rather than built into the interim. The merged item records that the
  interim serves **no offline-write path**, so `id:2902` stays unserved — a named gap.
  *Provenance: owner selected "Route to 09f9, note the gap", after first leaning "spike it", floating
  "using also worktrees for each worktree's tracker state", then self-correcting: "oh that might
  become a mess though, maybe better 4".*
  **Out of scope:** the kill-criteria spike; building the branch topology in the interim.

- **D4** — Gate state: **path is truth** (the directory *is* the gate graph; no `gated-on:` marker as
  a second copy). **Amended in-session:** multi-gate items use a **compound directory**
  `gated-on/<a>+<b>/<id>.md` under a canonical sort. No frontmatter duplication.
  *Provenance: owner selected "Path is truth", then "Compound directory".*
  **Costs accepted knowingly:** gate transitions are renames (rename/rename conflicts); the compound
  name is an unordered set encoded as a string, so every reader needs a canonical sort.

- **D5** — Ordering: an explicit `priority:` frontmatter field replaces ROADMAP file order as the
  dispatch priority function.
  *Provenance: owner selected "Explicit priority field".*
  **Cost accepted:** ~69 values per repo, which rot without a lint.

### Amendments (closing pass — these SUPERSEDE the clauses named)

- **D1-A** *(supersedes D1's provenance clause; D1's "both live, name it" outcome stands)* — cartulary
  R1's *"killed Vikunja/Plane"* provenance is **UNVERIFIED**. `ARCHITECTURE.md:40` heads that table
  *"Derived at the founding meeting from the workload, not from a tool"*, which is a claim of ratified
  provenance; the meeting applied the "derived doc" label **without diffing the founding meeting
  note**, which is what the rule actually requires. Diffing that note is now a **prerequisite** before
  any retirement of, or continued funding of, `id:90f2` / `id:e977`.
  *Forced by F6. Provenance: owner selected "Correct both".*

- **D2-A** *(supersedes D2's "proceeds"; the 55f6+c74e merge stands)* — **"proceeds" is downgraded to
  GATED.** The merged item must first sketch **one collector port** and **quantify the
  rename-vs-content conflict trade** before any layout is ratified. This answers `55f6`'s own
  interim-vs-wait question with evidence instead of assumption.
  *Forced by F1 + F8. Provenance: owner selected "Amend — gate on a collector-port sketch".*

- **D3-A** *(supersedes D3's gap text and rationale; the routing outcome stands)* — the gap is **"no
  `id:2902` logging instrument"**, NOT "no offline-write path": markdown files in a git tree are
  exactly as offline-writable from Termux as today's `TODO.md`. The routing rationale cites the
  **ref-namespace mess**, not `id:2b4b` (widening reconcile's enumeration is the small, just-done
  change).
  *Forced by F7. Provenance: owner selected "Correct both".*

- **D4-A** *(supersedes D4 **and** its in-session compound-directory amendment, in full)* — **marker
  is truth, path is derived, a mechanical check reconciles** — exactly what `55f6` originally
  proposed. The compound directory is **withdrawn**; a multi-gate item carries two markers, as today,
  which merge cleanly. The `ls`-able gate graph becomes a derived view, not the truth.
  *Forced by F2, F3, F4, F5, F9. Provenance: owner selected "Amend — marker truth, per 55f6's own text".*
  **Out of scope:** path-as-truth in any form; the compound directory; the symlink and
  primary-in-path variants.

- **D5-A** *(supersedes D5's under-specified half; the `priority:` field stands)* — `priority:` in
  **gaps of 100** so insertion never renumbers; ties broken by **id ascending** so dispatch is never
  nondeterministic; and the rot-lint is **filed as a child item**, not merely intended.
  *Forced by F10. Provenance: owner selected "Amend — spaced integers + tiebreak + file the lint".*

### Carried open (deliberately not decided)

1. How an **archived** gate target resolves — under D4-A this reverts to marker resolution across the
   live+archive pair, so it folds into `id:47f7` rather than standing alone, but the merged item must
   say so.
2. What renders the human-readable view (a derived `TODO.md` is a cache per the `id:2840` doctrine,
   never committed as truth).
3. How the 12 collectors port — **now load-bearing**, since D2-A gates the whole interim on sketching
   one of them.

## --fabled closing pass

**Verdict:** Fable available (`fable-config.sh check` → `available`). One Fable-5 subagent, fed a
closing-time digest including the ratified decisions verbatim, design-critique framing. Returned **10
findings**.

**Pre-registered escalation trigger: FIRED.** Counting only findings that forced reopening or amending
an already-ratified decision: **7** (F1, F2, F3, F6, F7, F9, F10) against a threshold of **≥2**.
F4/F5/F8 are arguably forced as well. This is the **fourth** firing of the trigger (previously 4, 4,
5) and the largest; `id:8df5` (the per-decision + full multi-pass build this evidence gates) remains
**unfiled** — `routed:7b8f` is sitting in the shared inbox.

Findings, as returned:

1. **D2 ratifies "PROCEEDS" while `55f6`'s own question — interim-vs-wait — was never answered, and
   the evidence says it doubles.** Cartulary's ratified end state represents gates as a *list-valued
   field* with a 3-way set-merge driver already built and green, while D4 represents them as *paths*,
   where no driver can apply (drivers run on content, not renames). Every collector ported to read
   directory names must be re-ported to read TOML fields.
   *Independently verified: `cartulary/src/cartulary/merge_driver.py` exists (8,739 B, 2026-08-12);
   `edits.py:50` — `"gated_on": sorted(gated_on)`.* → **D2-A**
2. **D4 eliminates the redundancy that makes drift detectable, and creates a mandatory new writer no
   decision names.** Gate satisfaction is *lazy* today (readers resolve markers against the target's
   checkbox); under path-is-truth someone must actively rename every `gated-on/*X*/…` file on every
   closure. If it doesn't run, dependents sit gated forever — silent starvation. → **D4-A**
3. **The compound directory is worse than the flat file at the exact scenario it exists for.**
   Concurrent satisfaction of different gates of an `a+b` item is rename/rename(1to2): git leaves
   *both* copies and the correct resolution is a third path neither side names. Today two markers
   deleted on separate lines merge cleanly. All of it serves 4 items fleet-wide. → **D4-A**
4. **The `{gated-on, ungated}` taxonomy is poorer than the headings it replaces, and recreates
   `id:4b8f` inverted** — nowhere to park `[INPUT — decision]` items or prose deferrals except
   `ungated/`, i.e. dispatchable. → **D4-A**
5. **"Path is truth" doesn't say WHICH path** — single-id-two-views means `TODO/gated-on/x/<id>.md`
   and `ROADMAP/ungated/<id>.md` can coexist; the duplicated state survives *across trees*. → **D4-A**
6. **D1's "derived-doc claim, not a ratification" was asserted, not checked** —
   `ARCHITECTURE.md` heads the requirements table *"Derived at the founding meeting"*.
   *Independently verified at `ARCHITECTURE.md:40`.* → **D1-A**
7. **D3's recorded gap is factually wrong** — markdown in a git tree is exactly as offline-writable
   from Termux as today's `TODO.md`; what routing forgoes is `id:2902`'s logging instrument. → **D3-A**
8. **The merge-conflict claim — the interim's whole "why now" — was never quantified.** 3 of the 4
   motivating defects have landed or cheap flat-file fixes.
   *Independently verified: `ef43739` landed the `id:4b8f` fix; `TODO.md:690` still carries it as
   `- [ ]` open — a cross-ledger drift instance, not a flat-file structural defect.* → **D2-A**, `id:aa05`
9. **Bare-hex gate directories inherit the homonym problem cartulary already solved** — 93 measured
   cross-repo id collisions, which is why cartulary's ratified scheme is full-canonical `repo:id`.
   → **D4-A**
10. **D5's ordering is under-specified where classify depends on it** — ties, no insertion semantics,
    and the "will rot without a lint" cost accepted without filing the lint. → **D5-A**

**Where Fable found the design sound:** merging `55f6` with `c74e`; naming the three programs
explicitly; D3's *outcome* (though not its recorded rationale); and honouring `55f6`'s
"do not start building".

## Action items

- [ ] **Merge `id:55f6` + `id:c74e` into ONE item**, keeping `id:55f6` as the surviving token and the
  `routed:207b` breadcrumb. The merged item carries: D2-A's gate, D4-A's marker-truth model, D5-A's
  ordering contract, D3-A's `id:2902` gap, and the three carried-open questions. Contract: `id:c74e`
  is closed pointing at `id:55f6`, and `orphan-scan.sh --cross-ledger` stays clean. *(recorded on
  `id:55f6` itself)*
- [ ] **Sketch ONE collector port and quantify the rename-vs-content conflict trade** — D2-A's gate on
  the whole interim. Port the smallest of the twelve end-to-end against a per-item layout, and produce
  a defensible estimate of gate-transition frequency vs the flat-file append/toggle conflict rate.
  Contract: a future test asserts the ported collector returns an identical id set and
  `actionable_routine_open` pre/post. Nothing else is built until this lands.
  <!-- id:4fb8 -->
- [ ] **Diff cartulary's founding meeting note against `ARCHITECTURE.md` R1** to establish whether
  *"killed Vikunja/Plane"* was owner-ratified — D1-A's prerequisite. Contract: until this resolves,
  no retirement of and no new funding for `id:90f2` / `id:e977`.
  <!-- id:45aa -->
- [ ] **File the `priority:` rot-lint** as a child of the merged item — D5-A. Contract: the lint fails
  on a duplicate priority within a tree, on a non-multiple-of-100 value, and on an item missing the
  field. <!-- children-of:55f6 --> <!-- id:5a14 -->
- [ ] **Verify and close `id:4b8f`** — `ef43739` landed the fix but `TODO.md:690` still carries the
  item as `- [ ]` open. Contract: confirm `gather-repo-state`'s `open_hard_pool` no longer counts
  `[HARD]` items under a `## Gated / deferred` heading, then tick it in both ledgers if they share the
  token. <!-- id:aa05 -->
- [ ] Route the **tracker-branch/worktree storage topology** to cartulary's open `id:09f9` as a third
  candidate (records on their own ref, mounted where needed), with Gil's three attacks and Archie's
  unmounted-ledger objection attached → routed to cartulary inbox <!-- routed:2ef9 -->
- [ ] Fix cartulary's **stale `README.md` status block** ("no substrate committed yet … being decided
  by a three-arm bake-off") — the `id:6107` verdict landed 2026-08-12 → routed to cartulary inbox
  <!-- routed:450c -->

**Not action items, surfaced for the record:** `id:8df5` remains unfiled after a fourth trigger firing
(`routed:7b8f` in the shared inbox); two live `meeting/append.sh` data-loss defects also sit unadopted
in the inbox (`routed:81b8`, `routed:96da`).

---

## Post-meeting amendments (2026-08-13, after `id:4fb8` reported)

Appended after the meeting closed. The ratified text above is **unchanged**; these are superseding
entries citing what they supersede, per the decision-provenance rule.

- **D2-A → DISCHARGED, and the gate resolved to BUILD FULL.** D2-A downgraded "proceeds" to GATED on
  `id:4fb8` (sketch one collector port + quantify the rename-vs-content conflict trade). That
  evidence was produced and is preserved verbatim at
  `2026-08-13-1415-interim-ledger-substrate-4fb8-evidence.md`. **Owner ruling: BUILD FULL per-item.**
  `id:55f6` is no longer gated.

  Recorded plainly because it matters for auditability later: the delegated agent recommended
  **BUILD-NARROWER** (bodies-only), and the measured evidence pointed the same way — ledger conflicts
  at **0.37/week** (5 of 416 merges over 95 days), **2 of 6** conflicting relay branches dissolving,
  the motivating `id:2b4b` incident not preventable by any ledger substrate (2 of its 3 stranded
  branches also conflict on *code* files), and `meeting/md-merge.py` already serving as the per-item
  substrate for the same-machine path. **The owner ruled against that recommendation.** That is his
  call as domain expert and is not re-litigated here — a delegated verdict is a recommendation, never
  a self-settling decision, and this is the owner exercising exactly that distinction. The evidence is
  preserved so the trade-off he accepted stays legible.

- **D5-A's accepted cost was wrong by ~7× — amended on the measurement, not reinterpreted.** D5-A was
  ratified with the accepted cost *"~69 values per repo to maintain, and they will rot without a
  lint."* Measured: **489 for this repo alone** (`TODO.md` 432 + `ROADMAP.md` 57 checkbox items), because
  both ledgers must explode — half the measured conflicts are in `TODO.md`. **The decision stands**
  (gaps of 100, ties by id ascending, lint `id:5a14`); what is amended is the premise it was accepted
  under. At 489 hand-maintained values the lint stops being hygiene and becomes the only thing between
  the ordering and rot.

- **Six questions BUILD FULL must answer that BUILD-NARROWER would have sidestepped** — all surfaced
  by `id:4fb8`, all recorded on `id:55f6`: `in_exempt_section` has no truth source under a tree;
  `REVIEW_ME.md` has 57 entries but only **2** with id markers; the indented `- [ ]` sub-bullet makes
  an item vanish from dispatch and forces the migration to pick a side (`classify-repo.sh` and
  `todo-conformance.sh` already disagree); the leftover `_chrome.md` reintroduces a shared non-union
  file holding exactly the malformed content; `roadmap-archive.sh` and `meeting/append.sh` get
  rewritten rather than ported; and the `id:c74e` divergence caveat still binds, since D4-A's inline
  comment gates are a **third** form distinct from cartulary's sorted list field and cannot borrow its
  merge driver (`basesize=0` defeats add/add refusal).

- **`id:45aa` RULED — cartulary R1 was never ratified; the `id:4a5c` tracker pilot is ALIVE.** This
  settles the prerequisite D1-A imposed. In cartulary's founding note the "killed Vikunja/Plane"
  annotation sits at line 72 **inside `## Discussion`** (18–132), introduced as *"Petra's
  requirements"*; the `## Decisions` section begins at line 132 with five decisions each carrying a
  verbatim `**Decision provenance:**` quote, **none about R1**. `id:90f2` and `id:e977` are
  **unfrozen**. This means **D1's original reading was correct** and the closing pass's **F6** — which
  charged that the "derived doc, not a ratification" label was asserted without checking — was right
  about the process but wrong about where the check would land. F6 was itself an unchecked-premise
  finding, which is worth weighing when `id:8df5` / `id:43c8` design the per-decision Fable pass.
