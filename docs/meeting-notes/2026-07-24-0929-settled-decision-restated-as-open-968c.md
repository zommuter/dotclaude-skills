# 2026-07-24 — Stop re-presenting a settled decision as an open item (id:968c)

**Started:** 2026-07-24 09:29
**Session:** 11bbe949-33d7-4ce4-8102-1ab09663bae9
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing), 🔎 Dex (compiler/static-analysis diagnostics — re-onboarded)
**Topic:** Pick the mechanism that stops a decision, once made, being re-presented as an open question.

## Surfaced discoveries

- `[2026-07-23 dotclaude-skills]` A procedure that lives only inside ONE caller's LLM prompt string is invisible to sibling execution paths — enumerate sibling paths before calling a step landed, **and before proposing enforcement check the step EXISTS on every path you'd enforce against**.
- `[2026-07-23 dotclaude-skills]` `/meeting-parallel` dogfood: a naive summarizer framing-shades the minority; pure fan-out loses cross-examination synthesis.

## Agenda

1. What is the detectable condition? ("ledger lags a note" vs "a box asks a question already answered")
2. Which mechanism — pre-flight grep / `supersedes` backlink / note-corpus scan / staleness warning?
3. Extend existing machinery or build new? (roadmap-lint `DECIDED-LEFT-OPEN` id:dafa, `orphan-scan --cross-ledger`, typed edges id:46f6)
4. Severity and firing site.

## Discussion

### Item 1 — the detectable condition

🏗️ **Archie** anchored on two incidents of different shape. In loderite, five items (62cc, 403e, 0e99, 3fdb, a663-D5) had answers in `docs/meeting-notes/` while the ledgers still showed `- [ ]` — **ledger-lags-note**. This morning in this repo, an open REVIEW_ME box asked about d5e0/2e6d/2d20 whose ledger state was already correct as of 2026-07-21 (`TODO.archive.md:452`, `:456`, `TODO.md:146`) — nothing lagged; a **question artefact outlived its answer**. Same symptom, two mechanical conditions.

🔎 **Dex** mapped these onto the diagnostics distinction: condition A is reaching-definitions-shaped (note = definition site, ledger = use site, filenames order them); condition B resolves ids *cited inside a box body*, not the box's own id. One detector for both is imprecise at both.

✂️ **Petra** applied N=2 to the *engine*: `/meeting` and `/relay human` pre-flights are two real consumers, so an engine is warranted — but two conditions inside one engine is a separate question from two entry points.

😈 **Riku** opened as the sceptic: B's cost was ~4 tool calls; A's cost was the owner's attention (he personally caught 2 of 5). He demanded a rate, not an incident, and pre-registered his flip condition: *fires more than twice in a month → build it*.

⚙️ **Sage** flagged the runtime constraint: `/meeting` setup already runs ~15 calls including a 704-line discoveries read; candidate (a) as stated adds both context cost and LLM judgment — the thing mechanize-first exists to replace.

The panel converged on eliminations before the owner ruled. **(b) the `supersedes` backlink** is not a detector but a schema change on top of id:46f6's typed-edge grammar — Petra noted that voting it here would itself quietly re-open a settled schema decision. **(d) the staleness warning** is a degenerate (c) that fires on nearly every box older than a week. **(a) as stated** is LLM judgment in the hot path.

🏗️ **Archie** put the live misfire on the record as the closest thing to a trial of this family: `roadmap-lint.sh:354` fires `DECIDED-LEFT-OPEN` on the bare uppercase substring `SUPERSEDED` anywhere in an open item's line. On id:931c that word referred to id:f599, not to 931c. The remedy applied that morning was to **reword the item's prose to appease the detector** — the detector training the corpus, not the corpus informing the detector. 🔎 **Dex** identified it as the fifth instance of the unanchored-grep family (roadmap-lint `id_re`, `unpromoted-scan`'s bare `grep -qF`, `inbox-done`'s substring match, md-merge's fail-open append), and drew the invariant: **any mechanism here must key on anchored structural evidence — a token inside a named section — never on prose vocabulary.**

### Amendment session — parallel loderite audit (new evidence, mid-meeting)

The owner introduced a parallel loderite audit that collapsed **nine or ten findings into one failure mode**: a decision lands in a note, and *the item that provoked it is never updated* — lane tag stays `meeting`, gate text stays stale, visible prose keeps asking the settled question, resolution lands in a comment, a sibling item, or 100 lines away.

😈 **Riku withdrew his observe-first hold without hedging**: he had pre-registered "more than twice in a month"; nine or ten instances across two audits clears it. His false-positive concern survived, re-aimed at the mechanism's *shape*.

🔎 **Dex** noted the audit **inverts** Archie's direction: not a corpus search but an **obligation on the item** — closer to "declared but never defined" than to reaching-definitions, and it cannot miss an item because the item is the unit of check.

✂️ **Petra** priced adoption: ~66 open meeting-lane items become findings on day one, and id:7df1 is the live precedent — still open precisely because flipping old lane vocabulary to ERROR "would LOUD-reject all 41" remaining tags across 12 repos.

⚙️ **Sage** flagged that the audit's recommended bookkeeping batch targets **loderite's** ledgers, and that a delegated agent's verdict is evidence plus a recommendation, never a settled decision.

### Items 2–4 — shape, home, severity

🏗️ **Archie** established the architectural fact: `orphan-scan.sh:89` already loads `docs/meeting-notes/*.md` + `TODO.md` + `TODO.archive.md` + `ROADMAP.md`, and already carries five directions; `roadmap-lint` reads only ROADMAP, `todo-conformance` only TODO — neither spans the needed corpus. 🔎 **Dex** added that `--shipped` already dates lines by `git blame` author-time (`:32`), so no new dating primitive appeared to be needed.

😈 **Riku** required a precedence rule: when the obligation and the scan both fire on one item, **the scan wins** — it carries the evidence, the obligation only reports an absence.

### `--fabled` closing pass (adversarial, before any durable write)

The owner invoked `--fabled`. **The flag is not built** (id:7e87, open, design-settled 2026-07-20); `validate-flags.sh` accepts the token because it is in the manifest, so the guard does not warn. The manual equivalent was run: one adversarial Fable-5 subagent fed a self-contained digest of the seven decisions, instructed to refute. Fable returned (probe cache updated to available). **Every load-bearing claim was re-verified in-session before being allowed to reverse a ratified decision.**

1. **D7 REFUTED.** `git blame` author-time is *last-modified*, not creation. `meeting/md-merge.py` replaces whole lines by id token and is the mandated ledger-edit path (`/meeting` write-back, `/relay human`, `todo-update`) — used twice on the morning of this meeting, on id:74e7 and id:ebd0. Grandfathered items would flip to hard-ERROR on their first routine edit: **the WARN population erodes by churn, not resolution.** `--shipped` uses blame for "unchanged ≥14d", where last-modified is the *correct* semantic; D7 borrowed it for creation dating, where it is wrong.
2. **D1(ii) REFUTED.** Verified in-session: the founding note `docs/meeting-notes/2026-07-17-1541-*.md` writes its Decisions items as backticked bare tokens — `` `8ef3` ``, `` `b8fa` ``, `` `e647` `` — with **zero** `id:XXXX` forms, so the scan scores nothing on the exact class id:968c exists to catch. Only **124 of 203** notes carry a `## Decisions` heading. And it over-fires: **id:010c is open at `TODO.md:358` while appearing under the 2026-07-23 note's Decisions heading — because that decision *filed* it.**
3. **D1(i) REFUTED as self-defeating.** "A back-reference to a note dated after its own last question" has no fixed point: adding the required back-reference is itself an edit, moving the line's date past every existing note.
4. **False-"settled" burial CONFIRMED at scale.** The ids most cited under Decisions sections are the most-referenced *open* work (id:46f6, id:65f9 appear 5–6 times each, both `- [ ]`). A triager acting on the scan's list would close the repo's most load-bearing open items — Riku's id:2e6d/7d97 hazard, generalised.
5. **D5/D2 WEAKENED — reconcile-before-greenfield violated.** `roadmap-lint.sh:350-359` already ships this rule. The id:968c item text *explicitly asked* whether the two share an implementation; the seven decisions never answered it. Two predicates in two scripts owned by two skills, with divergent word lists and exemptions — and under single-id-two-views the same line text lives in both ledgers, so one line could PASS one and FAIL the other.
6. **D6/D3 conflict.** `orphan-scan`'s contract is "exits 0 regardless (caller decides severity)" — advisory by design — while D3 needs an ERROR tier. That machinery already exists at `roadmap-lint.sh:335`.
7. **D4 SOUND**; D6's mechanics sound.

The owner ratified all three amendments. **Named trade, accepted explicitly:** as amended, the mechanism is forward-looking — the anchored markers exist only in notes authored after it lands, so it scores **zero** on the existing 203-note corpus. It prevents the next instance rather than finding the last nine; those still need a human pass.

## Decisions

- **D1 (amended by A2) — build both a back-reference obligation and a corpus scan, BOTH keyed on anchored markers, never prose.** The scan reports *only* Decisions bullets carrying an explicit `<!-- settles:XXXX -->` edge; the obligation checks *presence* of a `<!-- decided-in:<note-relpath> -->` backref on an open `[* — meeting]` / `[INPUT — decision]` item. **Explicitly out of scope:** any date comparison between item and note (no fixed point — D1(i) refutation), and any bare `id:` grep over Decisions prose (both over- and under-fires — D1(ii) refutation).
- **D2 (re-scoped by A3) — the self-consistency check ships first, but it is an EXTENSION of a shipped rule, not greenfield.** Reconcile with `roadmap-lint.sh`'s `DECIDED-LEFT-OPEN` (id:dafa) before writing anything new. **Out of scope:** a second independent predicate.
- **D3 — severity is two-tier: WARN across the existing grandfathered population, hard ERROR for items created after the rule lands.** Enforced where `--strict` already lives (`roadmap-lint.sh:335`). **Out of scope:** blocking any relay round or auto-ticking anything.
- **D4 — this meeting does not touch loderite.** The audit's bookkeeping batch (REVIEW_ME.md:504 + the 0e99 twin, f7c7 superseded-by 5445, retire TODO.md:257, the 9a6b contradiction) is recorded as a pointer for loderite's own session; the 9a6b fix needs owner ratification because it is a judgment about which side is right. **Out of scope:** any cross-repo write from this session.
- **D5 — the contradiction predicate is state-claim-vs-checkbox, scoped.** An OPEN `- [ ]` item whose visible text asserts a terminal state about **itself** (RESOLVED / DECIDED `<date>` / SUPERSEDED / DONE / CLOSED / DEFERRED) is a contradiction, **unless** the assertion is scoped to another id (`id:XXXX is superseded`). **Out of scope:** cross-file contradiction detection (the id:74e7 Makefile-vs-SKILL.md class is not covered by this rule).
- **D6 (split by A3) — homes: the contradiction predicate becomes a SHARED helper** called by `roadmap-lint` (ROADMAP, keeping its `--strict`) and `todo-conformance` (TODO) — modelled on `relay/scripts/lib-typed-edges.sh`, which id:65f5 already extracted as "one engine, two callers". The two correlation rules ship as `orphan-scan.sh` directions `--unbackrefed` and `--settled`, advisory-only, which now matches that script's stated contract. **Out of scope:** a new standalone script; giving orphan-scan a severity mechanism.
- **D7 REFUTED and REPLACED by A1 — the ERROR-tier boundary is a committed fixture snapshot** of the open meeting-lane id set at rule-land time; "new" = not in the fixture. **Explicitly out of scope:** `git blame` author-time (dates last edit, destroyed daily by `md-merge.py` whole-line rewrites) and `git log --reverse -S` (O(items) per run).
- **A3 corollary — this AMENDS id:dafa**, and this morning's id:931c prose reword is to be **reverted** once the corrected scoped predicate lands: the reword appeased a bug rather than fixing the item.
- **Recorded constraint** — when `--unbackrefed` and `--settled` both fire on one item, the scan wins; it carries the evidence, the obligation reports only an absence.

## Action items

- [ ] Extract the D5 state-claim predicate into a shared helper (model: `relay/scripts/lib-typed-edges.sh`, id:65f5 "one engine, two callers") with the other-id scoping exemption and the union word list; call it from `roadmap-lint.sh` (replacing the bare-substring rule at `:350-359`) and from `todo-conformance.sh`. Contract a test would verify: an open item reading "id:YYYY is SUPERSEDED" passes; an open item reading "RESOLVED 2026-07-19" fails; both linters return the same verdict on the same line text. Amends id:dafa; reverts the id:931c reword. <!-- id:5533 -->
- [ ] Define the `<!-- settles:XXXX -->` / `<!-- decided-in:<note> -->` typed-edge grammar as an extension of id:46f6's edge vocabulary, and add `orphan-scan.sh --unbackrefed` + `--settled` as advisory directions over it. Contract: `--settled` reports an id ONLY when a Decisions bullet carries an explicit `settles:` edge — a bare `id:` mention under Decisions must produce zero output (fixture: the 2026-07-23 note's id:010c, open and merely cited, must not be reported). <!-- id:8913 -->
- [ ] Build the committed fixture snapshot that draws D3's WARN/ERROR boundary: capture the open meeting-lane id set at rule-land time into a checked-in file; "new" = absent from it. Contract: an item whose line is rewritten by `md-merge.py` stays in the WARN tier. Gated on id:5533. <!-- gated-on:5533 --> <!-- id:cb3e -->
- [ ] Human pass over the nine-or-ten instances the amended (forward-looking) mechanism will not catch — the existing corpus needs eyes, not a tool. Scope: loderite's audit findings plus this repo's equivalents. <!-- id:d1fb -->
- [ ] loderite bookkeeping batch (REVIEW_ME.md:504 + 0e99 twin, f7c7 superseded-by 5445, retire TODO.md:257, the 9a6b contradiction) → routed to loderite inbox <!-- routed:b81c --> *(per D4 this session writes nothing in loderite; its own session applies the batch, and 9a6b needs owner ratification since it is a judgment about which side is right)*
- [ ] `/meeting --fabled` (id:7e87) remains unbuilt — this meeting ran the manual equivalent for the second time (first: 2026-07-23 semver cluster). Two dogfood runs, both of which refuted ratified decisions. *(existing item, not re-filed)*
