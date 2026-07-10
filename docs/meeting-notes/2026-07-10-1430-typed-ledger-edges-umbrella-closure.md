# 2026-07-10 — Typed ledger edges: umbrella closure + gate resolution for `orphan-scan.sh`

**Started:** 2026-07-10 14:30
**Session:** d2b404be-5033-4058-9a70-3367a1b2b341
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — standing in this project per `docs/meeting-notes/meeting-style.md`)
**Topic:** `orphan-scan.sh --shipped` cannot see an umbrella TODO item whose close condition is "all children landed" — it inherits gate words from quoted child clauses and is suppressed as EXTERNAL-WAIT. What should the detector learn?

## Origin — a failed warrantability check

`/meeting id:65f9` was invoked. The warrantability self-check **failed**: id:65f9's architecture was
decided 2026-07-07 (`2026-07-07-1228-relay-discovery-off-workflow.md`, D1–D4) and its three buildable
children (`9d97`, `7402`, `54fc`) are all `[x]` in `TODO.archive.md`. Its own text states the close
condition: *"This umbrella stays open until the children land."* They landed. A persona meeting on 65f9
would have re-litigated settled decisions.

The user retargeted the session to the genuinely-undecided question: **why did the repo's own
shipped-drift detector never say so?**

## Surfaced discoveries
- [2026-05-21 dotclaude-skills] A meeting↔tracker correlation key must be a *stored opaque token frozen on write*, NOT a re-derived content hash of mutable text.
- [2026-06-11 dotclaude-skills] Advisory-only gate flags in `classify.sh`: script detects vocabulary presence (grep), model judges satisfaction — the advisory constraint collapses the downside of dumb detection (a false positive costs one glance, never a wrong skip).
- [2026-05-14 dotclaude-skills] `orphan-scan.sh` was once *disabled outright* for FP rate; the re-enable gate was the opaque `id:XXXX` token (F-B).
- [2026-05-14 dotclaude-skills] Sibling-helper pattern: script does cheap first-pass extraction, model does final verification — only the script's short stdout enters context.

No open GitHub issues/PRs; no inbox items routed here; no orphan-scan or cross-ledger drift.

## Agenda
1. What exactly is the defect — gate-word scope, or a missing relation type?
2. Where should the relation type live: stored marker, prose parsing, or nowhere?
3. Loud-failure surface and backfill scope.
4. (Added) Inline classification of the backfill corpus.

## Discussion

### Item 1 — locating the defect

🏗️ **Archie:** The symptom is `orphan-scan.sh:153`. `wait_re` is matched against the whole item line, so
`\bgated\b` anywhere suppresses the item. On `TODO.md:190` both hits sit inside quoted *child* clauses.
Neither describes a gate on 65f9 itself.

😈 **Riku:** Then scope the regex to the item's own clause. Why isn't that the whole answer?

🏗️ **Archie:** Because scoping only stops the suppression. Un-suppressed, 65f9 falls to the TICK-READY
branch, which demands a test carrying `# roadmap:65f9`. An umbrella meeting item has no test. It goes
from invisible to still-invisible — a different code path, same silence.

✂️ **Petra:** Two independent defects. State them separately or this meeting produces mush. **(a)** Gate
words matched line-wide rather than clause-locally. **(b)** No predicate for "umbrella whose close
condition is child completion." (a) is necessary for (b), nowhere near sufficient.

⚙️ **Sage:** And (a) alone changes almost nothing observable: 86 of 235 open id-bearing items (37%) are
currently suppressed. Un-suppress them and they land in TICK-READY, whose only gate is "is there a green
test named after me?" Most have none, so they'd be silently dropped again. Worth saying before someone
ships (a) as a quick win.

### Item 2 — where does the relation type live?

😈 **Riku:** I ran the cheap hypothesis before endorsing anything. The naive predicate — *every `id:`
referenced on the line is `[x]`* — scores **precision 0/3, recall 0/1**. It fires on `ab5c` (flaky-test
bug; refs are provenance), `9d2b` (open pre-flip gate), `9e06` (open detector gap) — all genuinely open.
And it does *not* fire on 65f9, whose refs include still-open `Relate:` pointers `2ec4`, `882a`, `a17a`.

✂️ **Petra:** That's the finding. A line-level `id:` reference is **overloaded** — it carries *child*,
*relates-to*, and *gated-on* with identical syntax. The detector cannot distinguish them because the
markdown does not record the type. Everything downstream is guessing.

🏗️ **Archie:** So: a stored marker, `<!-- id:65f9 children:9d97,7402,54fc -->`, written at SPLIT time.
Closure computed over a *typed* edge set, not a scraped one. No prose parsing.

😈 **Riku:** Three objections. 235 items lack the marker (backfill). A marker is only as truthful as its
writer — a stale list makes the detector confidently mis-fire, which is worse than silence (id:4347).
And what stops us inventing a schema whose sole consumer is a report-only detector nobody runs twice?

⚙️ **Sage:** Objection two has the precedent answer: the 2026-06-11 `classify.sh` shape — script detects,
model judges, output is **ADVISORY**. A wrong `children:` list costs one glance. It never auto-ticks.

✂️ **Petra:** Objection three is my own N=2 rule, and it passes. Consumer one: `orphan-scan --shipped`.
Consumer two: **id:dc60**, already decided, specifying *one* `edges.json` producer over `routed:` /
shared-id / `[[coupling]]` / `[[link]]` edges, feeding the dc60 CLI and the id:36f1 web graph. A typed
`children:` edge is a first-class citizen of that graph and is currently absent from it.

😈 **Riku:** I accept N=2. I reject backfill-by-default. *(User overruled: backfill all ~50 multi-ref
suppressed items.)*

### Item 3 — loud-failure surface

😈 **Riku:** Fifty items is not a sweep a script can perform. Deciding whether `d5e0`'s 42 references are
children or an index is judgment per item — the 2026-06-26 conformance-sweep pilot already settled this:
*tooling is the detector, conversion is judgment.* What makes it survivable is that **extraction** stays
mechanical: a script pulls each reference with its surrounding phrase; only phrases enter context.

😈 **Riku:** Now the failure mode I care about. `children:9d97,7402,54fc` names three tokens. Suppose one
is a typo, or names a deleted id, or a child that only ever lived in `ROADMAP.md`. The predicate asks
"are all children `[x]`?" A missing id is *not* `[x]`. So the umbrella silently reads "not ready" —
forever, invisibly, for the wrong reason. **Fail-open silent swallow.** We'd have replaced an accidental
blindspot with a load-bearing one.

🏗️ **Archie:** So an unresolvable child is not "open." It is **UNRESOLVED**, its own loud class.

⚙️ **Sage:** Three umbrella classes, disjoint — the existing two already collapsed into each other once.
`UMBRELLA-READY` must **not** require a `# roadmap:` test; that's a separate branch, not a widened one.

😈 **Riku:** Accepted, with Sage's ordering constraint: defect (a) lands **first, in the same change**. If
a suppressed line never reaches the umbrella branch, the predicate provably cannot run.

🏗️ **Archie:** Closure reads `TODO.md` (`[x]`) ∪ `TODO.archive.md`. **`ROADMAP.md` is out of scope** — a
child closed in ROADMAP but open in TODO is exactly the drift `--cross-ledger` exists to flag; reading it
here would paper over that with a green umbrella.

✂️ **Petra:** Then self-healing is free: a re-opened child flips the umbrella back on the next run. The
marker records the *edge*; the ledger records the *state*. Keeping those separate is why this works.

### Item 4 — inline classification, and two surprises

😈 **Riku:** Read `TODO.md:25`. **id:ee62** is an open `[HARD — meeting]`: *"Use VISIBLE annotations, not
HTML comments, for metadata that should render,"* whose step (5) is *"audit other HTML-comment-as-meaning
uses."* We were one step from shipping the exact thing an open meeting item exists to stop.

⚙️ **Sage:** ee62 pre-adjudicates it, in our favour. Verbatim: *"OPAQUE correlation keys with no
standalone human meaning (`<!-- id:XXXX -->`, `<!-- routed:XXXX -->`) MAY stay as comments; MEANINGFUL
annotations carrying a human-readable reason/decision should be VISIBLE."* `children:` carries opaque
tokens and no prose reason — same class as `routed:`.

😈 **Riku:** Accepted, but ee62 is still open, so the *syntax* is not settled. `children:` inherits
whatever ee62 decides. Forward-flag, not a blocker.

**Classification of all 50 candidates: 5 genuine umbrellas, 5 ambiguous, 40 not-umbrellas.**

😈 **Riku:** Two things bite. **First, `4d8e` is tagged `[UMBRELLA]` in its own title, and its twelve line
references are *not* its children** — the real ones (`a0b6`, `5eb3`, `5ac6`, `9d2b`) appear nowhere on the
line. Had we accepted "a self-declared umbrella's refs are its children," we'd have produced garbage on
the one item that self-identifies. The stored marker is not a convenience over prose-parsing;
prose-parsing was never viable. **Second, the UNRESOLVED class has real instances:** `fc04`'s children
`5d27`/`6bef`/`7b4e` live in *meeting-rpg*, *puzzle-pwa*, *zkm-ner*. Cross-repo children are a real
category, not a typo class.

✂️ **Petra:** And **`65f9` is the only `UMBRELLA-READY` item in the corpus.** All five umbrellas got
marked; four have open children. The detector's first run surfaces exactly the item that motivated the
meeting. That is calibration, not noise.

🏗️ **Archie:** A third thing I didn't expect. Typing the `gated-on` edge — which we scoped *out* — fires
on three items **today**, because every gate has since closed: `6b81` (*gated on `ebfb` + `3558`*, both
`[x]`), `23e9` (*once `c345` + `040a` land*, both `[x]`), `3536` (*gated on `672b`*, `[x]`). Three items
are unblocked right now and nothing says so.

⚙️ **Sage:** Not a new capability. **id:7ace** is an *open TODO*: *"Gate-resolution detection:
externally-resolving `[HARD]` gates never auto-surface as actionable."* A typed `gated-on:` edge is the
mechanical, intra-ledger half of the detector 7ace asks for. Not all of it — 7ace's examples resolve on
external events no ledger edge can see.

✂️ **Petra:** `gated-on:` clears my N=2 bar more cleanly than `children:` did. What it does not clear is
this session's scope. *(User overruled: both edges, this change.)*

😈 **Riku:** Then the gate edge needs judgment the umbrella edge didn't, and I want the trap classes on
the record. **Inverted direction:** `93cc` says *"(id:8bea now gated on this)"* — 8bea is gated on 93cc,
not the reverse; `3e89` says *"must land BEFORE"* with both refs `[x]`, so proximity marks it GATE-READY
when it isn't gated at all. **Non-id gates:** `82c4` (*"gated on user leak-check"*), `6563`
(`RELAY_RUN_ID`), `dc60` (*"gap analysis"*) — no token, ever. **Prose false positives:** `33c2` contains
*"An executor gated on 'test passes'"*, describing executors, not itself.

🏗️ **Archie:** The payoff survives all three. GATE-READY today is exactly `6b81`, `23e9`, `3536` — no
fourth. `0749` is the instructive near-miss: *"gated on the id:2840 derived index, **NOT** on 672b"* —
and `672b` is `[x]`. Proximity marks it ready; the prose disclaims it.

⚙️ **Sage:** Which closes the no-silent-swallow loop. Gate vocabulary present but **no** `gated-on:`
marker → the detector cannot conclude "ungated." It must say **`UNMARKED-GATE`**. That catches every
non-id gate, every backfill miss, every future unmarked item. The detector's silence then *means*
something.

✂️ **Petra:** One caveat on `3536`: its line ends *"ROUTED 2026-06-29 to project_manager inbox."* It is
GATE-READY here but its home is elsewhere. The detector reports; the human routes.

## Amendment session (post-ratification, pre-implementation)

Two corrections surfaced while preparing the write. Both were **verified empirically**, not by inspection.

**A1 — D1's concrete syntax was wrong and would have corrupted `TODO.md`.** Ten parsers across
`meeting/` and `relay/scripts/` hard-assume the id comment terminates immediately after the four hex
digits: `orphan-scan.sh` (×6, `(?<=<!-- id:)[0-9a-f]{4}(?= -->)`), `md-merge.py:135`,
`handback-followup.py` (×3), `unpromoted-scan.sh` (×2), `backtest-historical.py`, `relay-doctor.sh`,
`classify.sh:36`, `tests/run-tests.sh:33`. Tested against three candidate shapes:

| shape | orphan-scan | md-merge | handback-followup (`$`-anchored) |
|---|---|---|---|
| A `<!-- id:X children:… -->` (as ratified) | ✗ | ✗ | ✗ |
| B `<!-- id:X --> <!-- children:… -->` | ✓ | ✓ | ✗ |
| **C `<!-- children:… --> <!-- id:X -->`** | ✓ | ✓ | ✓ |

Form A is not merely unparsed — since `md-merge.py update-ids` **appends** any id it cannot find, writing
form A would have appended duplicate lines rather than updating in place. The mandated safe-write tool
would have been the corrupting agent. **The marker is therefore form C: `children:` / `gated-on:` are
SEPARATE sibling comments placed BEFORE the terminal `<!-- id:XXXX -->`, which must remain last on the
line.** This is the same failure class as the 2026-07-03 lane-tag hotfix (a second substring reader
bypassing the anchoring the first reader established).

**A1b — the "id comment is terminal" invariant already has exactly one violator.** `id:78ff` carries a
trailing `<!-- xledger-ok: … -->` after its id comment — which is precisely the annotation ee62 step (4)
targets. Consequence: `handback-followup.py:71`'s `$`-anchored regex is *already* broken on that one line
today (pre-existing, not introduced here), and the marker parser must find `children:`/`gated-on:` as
siblings appearing anywhere *before* `<!-- id:XXXX -->`, without end-of-line anchoring.

**A2 — D6 is dissolved rather than implemented.** D6 called for scoping `wait_re` to "the item's own
clause," which requires a prose-clause parser — the very thing D1 rejected. Structural alternative: **an
item bearing a typed marker skips the gate-word heuristic entirely** and is decided by the typed
predicate; an unmarked item takes the existing `wait_re`/`completion_re` path, unchanged. 65f9 then
reaches the umbrella branch because it is *marked*, not because a regex got smarter. No clause parser is
written, the 86 currently-suppressed unmarked items keep their exact present behaviour (zero blast
radius), and prose is parsed nowhere. *Prefer dissolving a problem structurally over guarding it.*

## Decisions

- **D1 — Type the edges with a stored marker**, not prose parsing. **Syntax (per A1): `<!-- children:a,b,c --> <!-- gated-on:d,e --> <!-- id:XXXX -->`** — sibling comments, id comment terminal. Consistent with the 2026-05-21 stored-opaque-token discovery. Decisive evidence: `4d8e` self-declares `[UMBRELLA]` yet its line refs are not its children. *Out of scope:* typing the `relates-to` edge (id:dc60's graph may add it later). <!-- id:46f6 -->
- **D2 — The marker survives id:ee62 as an opaque correlation key.** ee62 explicitly permits opaque keys as HTML comments; `children:`/`gated-on:` carry no prose reason. **Forward-flag:** final syntax inherits ee62's decision; register this marker against ee62 step (5). *Out of scope:* resolving ee62's syntax question here. <!-- id:b883 -->
- **D3 — Both edges land in this change** (user decision, overriding the reserve-only recommendation). `gated-on:` clears N=2 independently: three items unblocked today + open id:7ace wants its intra-ledger half. *Out of scope:* 7ace's external-event gates.
- **D4 — Closure is computed over child edges alone**, against `TODO.md` (`[x]`) ∪ `TODO.archive.md`. `Relate:` and `gated-on:` never participate. **`ROADMAP.md` out of scope** (that drift belongs to `--cross-ledger`). Nothing cached — the marker records the edge, the ledger records the state.
- **D5 — Six advisory classes; unresolved is LOUD.** `UMBRELLA-READY` (report; no `# roadmap:` test required) · `UMBRELLA-OPEN` (silent) · `UMBRELLA-CROSS-REPO` (advisory, exit 0) · `UMBRELLA-UNRESOLVED` (**LOUD, exit non-zero**) · `GATE-READY` (advisory) · `UNMARKED-GATE` (advisory). `GATE-BLOCKED` silent. Nothing auto-ticks. *Out of scope:* auto-ticking, and rewriting the existing TICK-READY test-ownership branch.
- **D6 (as amended by A2) — Defect (a) is dissolved, not guarded.** A typed-marker-bearing item bypasses the gate-word heuristic entirely and is decided by the typed predicate; unmarked items keep today's `wait_re` path verbatim. No clause parser is written; the 86 suppressed unmarked items are untouched. *Superseded:* the original D6 ("scope `wait_re` to the item's own clause"), which would have required the prose parser D1 rejected.
- **D7 — id:65f9 is CLOSED.** It is the corpus's only `UMBRELLA-READY` item. `882a` remains open as the standalone trigger-gated contingency. *Out of scope:* re-opening D1–D4 of 2026-07-07.

**A3 — the detector would have been killed by its own documentation.** `id:46f6`'s TODO description
literally contained `<!-- children:a,b,c -->` and `<!-- gated-on:d,e -->` as illustrative syntax, on its
own `- [ ] … <!-- id:46f6 -->` line. The parser would have read them as real edges, failed to resolve
`a,b,c`, classified `UMBRELLA-UNRESOLVED`, and exited non-zero. Caught by a post-write edge count (9/11
instead of 8/10) and de-fanged. A marker literal must never appear in item prose.

**A4 — closing `65f9` removes the only live `UMBRELLA-READY`.** `--shipped` scopes to OPEN items, so once
65f9 is `[x]` the live ledger yields **zero** `UMBRELLA-READY` — the healthy state, not a regression. The
class is covered by hermetic fixtures, never by pointing at the real ledger.

## Findings (no action required, recorded as fact)

- **Three items are unblocked today** and nothing says so: `6b81` (gates `ebfb`+`3558` both `[x]`), `23e9` (gates `c345`+`040a` both `[x]`), `3536` (gate `672b` `[x]`; already routed to project_manager).
- **Naive reference-set closure is unusable**: precision 0/3, recall 0/1 against the live corpus.
- **Backfill classification** (50 candidates): 5 umbrellas (`65f9`, `a4e9`, `d2cd`, `78ff`, `6a3c`), 5 ambiguous (`fc04`, `dc60`, `5fc6`, `4d8e`, `415b`), 40 not-umbrellas. `415b` is *not* an umbrella — its own text says *"cross-reference … don't re-mint."*
- **`TODO.archive.md:311` holds an OPEN `- [ ]` sub-item** (`id:3ef7`), nested under an archived `[x]` parent. So closure must test the **checkbox**, never archive membership — and a parent was once closed with an open child, which is the umbrella defect in the opposite direction.
- **Two gate edges were deliberately NOT written.** `7df1`'s gate `b466` and `50c4`'s gate `508d` live in project_manager / relay-core and do not resolve locally. Rather than invent an unresolved-gate class, they stay unmarked and surface as `UNMARKED-GATE`. Tracked by `id:4245`.
- **`zkm-ner` is at `~/src/zkm/plugins/zkm-ner`, not `~/src/zkm-ner`.** Cross-repo evidence must come from `relay/scripts/lib-own-repos.sh` `own_repos()` (the canonical `relay.toml` reader honouring `# path:`), never a `~/src` glob — an improvisation that would have misclassified `fc04` as UNRESOLVED and forced a non-zero exit.
- **`--shipped` never scans indented sub-items.** Its driver greps `^- \[ \] ` anchored at column 0, so **14 of 241 open id-bearing items (6%) are invisible to every shipped class** — pre-existing, not introduced here. Three markers written this session are therefore inert: `3c4c` and `eb92` (`gated-on:8aba`) and `7df1`, which was expected to surface as `UNMARKED-GATE`. Widening the anchor would pull 14 unclassified items into all classes at once, so it is filed to be measured rather than sprung. Tracked by `id:431f`.
- **An `id:` token is not always a trackable item.** `id:36f1` lives on an indented prose sub-bullet with no checkbox — an id used as an anchor, not an item with open/closed state. My `dc60` `children:0fc7,36f1,f80b` marker was wrong on all three counts (`0fc7`/`f80b` absent locally, `36f1` not an item); it was one of the five UNSURE calls and it was a bad one. The marker was **removed** rather than left as a false edge. Final state: **7** `children:` + **10** `gated-on:` edges. Resolution must require a checkbox line, which the detector already does.
- **Report-line bloat.** Each class initially echoed the whole item line — 18 KB of stdout at the default cap, 36 KB uncapped. Pre-existing in the TICK-READY/GATE-STALE branches, invisible only because `--shipped` used to emit nothing. Report lines now print the item's **title** (≤110 chars); the `id:` token is the handle for looking up the rest. 18 159 → 2 309 chars.
- **`UMBRELLA-CROSS-REPO` must not assert a child→repo mapping.** The first implementation named the *first* confirmed own-repo string found on the line: for `78ff` (whose line contains both `zkWhale` and `project_manager`) it attributed child `b466` to `zkWhale`, though `b466` is explicitly "the project_manager Python half". Nothing in the data connects a child token to a repo name. The class now prints the unresolved tokens and the *set* of own-repo names present, as evidence — never a conclusion. A detector that confidently names the wrong repo is worse than one that names none.

## Action items

- [ ] Ship the typed-edge detector in `meeting/orphan-scan.sh`: (1) scope `wait_re` to the item's own clause (defect (a), lands first); (2) parse `children:` / `gated-on:` from the id comment; (3) add the umbrella + gate predicates and the six classes of D5; (4) exit non-zero iff any `UMBRELLA-UNRESOLVED`. Reuse the existing `grep -oP` token idiom and the `TODO.md ∪ TODO.archive.md` union-read. Contract a test would verify: one hermetic fixture ledger per class, plus a regression fixture where an item's only `gated` occurrence sits inside a quoted child clause and must **not** be suppressed. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:46f6 -->
- [ ] Teach `meeting/append.sh` to emit `children:` at split time, so the corpus stops accruing new umbrella blindspots. Contract: minting N child ids for a parent writes the parent's `children:` marker in the same call. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:06e3 -->
- [ ] Backfill the classified markers into `TODO.md` — 8 `children:` (`65f9`, `a4e9`, `d2cd`, `78ff`, `6a3c`, and the UNSURE-flagged `fc04`, `dc60`, `5fc6`) + 12 `gated-on:` (`3c4c`, `eb92`, `6b81`, `23e9`, `3536`, `ba31`, `0749`, `659c`, `7df1`, `80b8`, `50c4`, `38bf`) — written **only** via `md-merge.py update-ids --commit` (line-scoped, under flock; `TODO.md` is a shared write surface). Never `sed`. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:4245 -->
- [ ] Recover `4d8e`'s real children from `docs/meeting-notes/2026-06-30-1523-*` and mark it. It self-declares `[UMBRELLA]` but its line references are lint fixtures, not children — left unmarked this session on purpose. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:24c9 -->
- [ ] Annotate `id:ee62` (register `children:`/`gated-on:` against its step-(5) HTML-comment audit) and `id:7ace` (the `gated-on:` edge discharges its intra-ledger half; its external-event gates remain open). Contract: both TODO lines cite this note. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:b883 -->
- [ ] **[HARD — meeting] Should this toolkit adopt SOP / ADR / UML conventions?** (raised by the user during this session, in-session amendment). Weigh ADRs (immutable, status-bearing, decision-indexed) against today's chronological meeting notes — which carry ≈ADR fields but can be superseded silently, as `id:65f9` was. Note the typed ledger edges shipped here, plus `id:2840`'s derived index and `id:dc60`'s edge graph, already mechanize part of what an ADR status field would provide. Decide per-artifact, not as a bundle; prefer dissolving into existing machinery over a parallel record. `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:a6e1 -->
