# 2026-08-21 — Combined tracker substrate: convergence, ledger cost, and the cb22 adjudication

**Started:** 2026-08-21 08:03
**Session:** 55831c0e-21f1-48dc-933d-fabc7839a524
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 📊 Lexi (DMAIC/SPC — pre-registration, small-n, flow-vs-stock), 🗄️ Cassi (derived-data persistence, sharded-file vs fat-blob, sync-vs-backup separation)
**Topic:** What actually remains gating the tracker substrate, whether the three programmes converge, and adjudication of the 13 cross-repo homonym tokens.

## Premise correction made at setup

The meeting was called to combine `cb22` + `09f9`. **`id:09f9` is already ratified and closed** —
`cartulary/TODO.archive.md:17`, `- [x] [INPUT — meeting] **Ratify the record STORAGE TOPOLOGY —
one central tree, or a `records/` tree per repo?**`, settled 2026-08-12. A research pass earlier
in the session reported it as "still-unratified … deliberately not scheduled" and that was relayed
to the owner before being checked against the marker. Corrected at setup, before any agenda item.

Same failure mode twice more in the same session: the `tracker/homonym-allowlist.txt` header still
claims *"NOTHING HERE IS ADJUDICATED … parses as an EMPTY list"* for a file that now carries **63
active entries and 17 `# UNCONFIRMED`**; and a first attempt to look up the gate items used a bare
`grep id:XXXX` across two repos, matching prose mentions — the define-vs-refer defect the
2026-08-18 cartulary discovery names. All three are the concept this fleet keeps paying for:
a restatement drifting from its source, with nothing testing the prose.

## Surfaced discoveries

- [2026-08-18 cartulary] Narrowing a stored ref format fires the tree's OWN referential-integrity check on 100% of correct data — a ref-format narrowing must land its resolver at EVERY traversal in the same seam.
- [2026-08-18 cartulary] A round-trip test is only as wide as its normaliser; adding an optional field to a schema silently un-covers it.
- [2026-08-18 cartulary] Live self-instance of the define-vs-refer defect: an unanchored duplicate-guard tripped on a PROSE mention. Anchor on `<!-- id:XXXX -->`, never the bare token.
- [2026-08-18 dotclaude-skills] "Mechanical" is not the same as "correct": two tested, deterministic, model-free tools can give OPPOSITE answers about the same ledger edge because they encode different questions by design.
- [2026-08-20 project_manager] The ratified-vs-restated drift on mathematical-writing's carve gate — and its note that the narrowing "diverges on cartulary, the most likely near-term candidate."

## Agenda

1. ~~Adjudicate cb22 and settle the fail-condition clock~~ — folded into 4 after the owner chose 2&3.
2. Do the external tracker (`4a5c`), the git-native ledger (cartulary/`55f6`) and the derived index (`2840`) converge or stay parallel?
3. What does a ledger item cost to keep?
4. cb22 adjudication (added at the closure gate).

## Verified state at meeting time

| id | State | Note |
|---|---|---|
| `4a5c` tracker pilot | `[x]` closed | spawned the children |
| `8066` control-arm board | `[x]` closed | the pilot's pre-registered CONTROL ARM |
| `90f2` adapters | `[ ]` open | both arms verified live (Vikunja 2026-08-10, Plane 2026-08-11); box deliberately unticked |
| `e977` 78 class-A homonyms | `[ ]` open | deferred onto `cb22` |
| `cb22` 13 cross-referenced | `[ ]` open | **the one true blocker**; `[INPUT — author]` |
| `2840` derived index | `[ ]` open | held as the NAMED FALLBACK |
| `55f6` interim ledger substrate | `[ ]` open | `[INPUT — meeting]` |
| `09f9` storage topology | `[x]` **closed 2026-08-12** | premise correction above |

Tracker-path ids resolve in **dotclaude-skills**, not cartulary (`4a5c`/`90f2`/`e977`/`8066`/`55f6`/`cb22` = 0 occurrences in cartulary). `2840` is the one shared token (38 here, 3 there); `09f9` is purely cartulary's (0 here).

Measured, not recalled — loderite `ROADMAP.md` = 346,667 chars / 1385 lines:

| segment | lines | chars | share |
|---|---:|---:|---:|
| open `- [ ]` | 129 | 148,468 | 42.8% |
| closed `- [x]` (all already stubbed) | 110 | 69,589 | 20.1% |
| other prose / sub-bullets | — | 128,610 | 37.1% |

Largest single open item line: 9,187 chars. `TODO.md` = 392,043 bytes.

## Discussion

**Item 2 — convergence.**

🏗️ Archie put the three side by side and argued the framing was wrong: `4a5c` is an external
tracker reached through adapters over `schema/ledger-intermediate.schema.json`; cartulary is a
git-native TOML-per-record store with a derive-time validity gate; `2840` is an index whose own
ledger text says "md stays SSOT; index = cache, not truth." Not three candidates for one slot —
storage, cache, and view.

🗄️ Cassi made that distinction load-bearing: in build-cache terms cartulary is the store, `2840`
the derived artifact, the tracker a remote view. Derived data has one non-negotiable property —
reconstructible from the source alone, or it stops being a cache and becomes a second source of
truth.

✂️ Petra's N=2 objection resolved on that reading, conditional on writing the constraint down:
`2840` is held as the named fallback, and a fallback that can only be rebuilt by the thing it
backstops is not a fallback. Derivable from markdown *alone* — no cartulary dependency, no tracker
dependency — or it silently dies the first time someone optimises it.

😈 Riku took the other side: "three layers" is the comfortable answer, and comfortable answers are
how you end up with three half-built things. Today that is `90f2` unticked, `e977` unticked, `cb22`
unadjudicated, `55f6` at `[INPUT — meeting]`, `2840` open since June — five open boxes and a 339 KB
markdown file still doing all the work. His minimum evidence to change position: one layer
demonstrably serving a query the markdown cannot — not "the adapter runs", a question actually
asked and not grep-able.

📊 Lexi added a measurement consequence: the pilot carries a pre-registered fail condition — four
weeks from first successful full import, measured against `8066`. If the three converge, the
control arm *is* the treatment and the condition becomes unmeasurable by construction. Keeping them
separate is what preserves falsifiability.

**Item 3 — cost per item.**

🗄️ Cassi opened on the measurement: the closed items are already stubbed, so archiving harder
recovers a fifth and leaves 277 KB. The bulk is live items and the prose under them.

🏗️ Archie: the per-item cost *is* the item body — rationale, meeting citation, amendments, verbatim
owner quotes, all of which the meeting note already contains.

📊 Lexi tied it to the session's other findings: the mathematical-writing `TOOL` narrowing and the
cartulary R1 Discussion-cited-as-Decisions are both items restating their source instead of pointing
at it. One root cause, three symptoms — 339 KB ledgers, derived-doc drift, and a 197k-token child
prompt.

✂️ Petra: then the intervention is a grammar rule, not a substrate — and a lint is the only option
on the table that adds no new point of failure.

😈 Riku pressed: some of that prose is load-bearing precisely because the meeting note is long and
nobody re-reads it. 🏗️ Archie offered the empirical answer — an executor either finishes green from
the item text or hands back — and 📊 Lexi noted that is a flow metric, measurable before and after.
*(The `--fabled` pass later refuted this metric; see D2-A.)*

**Item 4 — cb22.**

🏗️ Archie: far more prepared than its label. Shape classification done 2026-08-18 and recorded so it
is not re-derived. Live count **13, not 15**. All 17 cross-reference hits are the weakest kind —
prose mentions the sibling repo name; **zero typed edges, zero structural cross-repo
parent/children/blocked_by**.

😈 Riku set the boundary before any question: the worksheet quotes titles from ~51 mostly-private
repos and this repo is public. Adjudicate by shape and count; no titles in the transcript or the
note. Evidence lives in `~/.cache/relay/tracker/`, regenerable in ~6 s, never committed.

🗄️ Cassi flagged S3 as the one with standing beyond bookkeeping — two items, both still open,
deliberately filed in two repos: the live cross-repo link the pilot exists to surface.

📊 Lexi noted what ratifying unblocks: the fleet import exits 3 by design until these resolve, so
one ~15-minute pass clears `cb22` → `e977` → `90f2`.

## Decisions

- **D1 — the three programmes stay PARALLEL for now, with a shipping gate.** Accept the layer
  distinction (cartulary = storage, `2840` = derived cache, external tracker = view) but do not
  ratify it as the terminal architecture; no new substrate work starts until one layer demonstrably
  answers a query markdown cannot. **Terminal intent, owner verbatim:** *"we're currently exploring
  multiple approaches, but at the end I don't want three points of failure but as little tooling as
  needed to get a more reliable workflow"*. Binding constraint carried from Petra: `2840` must remain
  derivable from **markdown alone**. Out of scope: converging now; retiring any programme.

- **D1-A (AMENDMENT, supersedes D1's freeze clause only — accepted from `--fabled` F1+F2).**
  The freeze binds **new substrate scope** only; work that unblocks an already-committed gate
  (`cb22` → `e977` → `90f2`) is **exempt**. The gate is operationalized by a **pre-registered query
  class** rather than "a question I couldn't grep" — as worded the bar was unfalsifiable in both
  directions. Closing `cb22` **must record the pilot's clock-start** as a dated, greppable line;
  until the clock demonstrably starts, "the pilot is alive" is vacuous — it cannot fail, so
  `2840`'s fallback trigger can never fire. Out of scope: naming the query class in this session
  (deferred to `id:eb52`).

- **D2 — attack ledger cost by SEQUENCE: slice now, lint only on evidence.** Ship `id:e68f`
  (orchestrator writes the dispatched item + its gate edges to a tmp file, hands the child a path).
  Then measure. Adopt a refer-don't-restate item-body cap only if the data supports it. Out of
  scope: a new substrate for ledger storage; shrinking existing ledgers by fiat.

- **D2-A (AMENDMENT, supersedes D2's measurement clause — accepted from `--fabled` F3+F4).**
  The measurement gets **its own id and an explicit trigger condition**, because as ratified it had
  no owner, no date and no id — the quietly-never-happens shape, which would make the lint de facto
  declined. **The metric changes** from executor handback rate to **bytes actually READ per
  dispatched item** (slice plus any ledger the child opens anyway): handback rate is noisy and
  multi-causal, small-n cannot resolve ~10pp per the fleet's own pilot-sample-size heuristic, and
  refer-don't-restate harm surfaces as pointer-chasing and silent quality loss rather than handbacks.
  The new metric also directly measures the over-read in F5.

- **D3 — cb22 adjudicated in full: 13 tokens, batched by shape.** Totals 7 genuine twins, 2 wanting
  a fresh id, 3 real coincidences, 1 borderline.
  - **S1 (4) + S2 (1)** — deliberate same-id mirrors across a parent/plugin pair, and one repo-move
    that carried its id; all sides done and archived → **recorded convention, no per-token edge**.
    One convention note ("a parent/plugin pair may deliberately share an id; that is a mirror, not a
    collision") and an importer rule.
  - **S3 (2)** — one live work item filed in two repos, both still open → **typed edge on both
    sides**. The first structural cross-repo edge in the corpus.
  - **S5 (3)** — true coincidences (false positives from an `[INBOUND routed:… from …]` preamble or
    an incidental repo-name mention) → **accept the tokens**; drop `# UNCONFIRMED`.
  - **S4 (2) + S6 (1)** — S4 is sibling-but-distinct work sharing an id, the only genuinely ambiguous
    shape → **fresh id on the executing side**; S6 topically related with independently minted ids →
    **accept**.
  Out of scope: per-token adjudication (deliberately shape-level); quoting any private-repo title.

- **D3-A (AMENDMENT, supersedes D3's S1+S2 and S4 rulings — accepted from `--fabled` F6+F7).**
  The mirror rule must **flag status disagreement loudly** rather than alias silently: S1/S2 pairs
  were both archived when adjudicated, and a later one-sided reopen would be silently aliased —
  the cross-repo equivalent of `orphan-scan --cross-ledger`, which does not exist. The
  **parent/plugin pair list must be EXPLICIT, not inferred**, so new repo pairs never inherit mirror
  semantics unreviewed. **S4 gets a fresh id PLUS a typed edge** — spec-side/execute-side is
  structurally the relationship S3 just got the corpus's first edge for; one extra line loses
  nothing, bare renaming severs it — preceded by a **sweep for references to the old token** before
  minting (the `id:c97c` bare-grep breadcrumb hazard).

- **Corrections accepted (`--fabled` F5, F8).** `id:e68f`'s claim that "the child cannot over-read"
  is **false as stated** — the child holds Read/Bash and the repo checkout, and per the banked
  deny-probe `id:5937` auto mode denies essentially nothing outside protected paths; e68f **lowers
  the default** prompt size, it is not an enforcement. `id:b018`'s corrected gate must budget for
  what a child **may pull**, not only what it is handed. The `tracker/homonym-allowlist.txt` header
  must be fixed in the same commit as the S5 accepts — it actively contradicts its own 63-entry
  contents.

- **087b bump-trigger disposition (decided in-session, outside the tracker agenda).** Ship as-is:
  a manifest repo with a substantive close and no recorded `bump_policy` hands back on its first
  pool integrate (`HANDBACK[bump]`, exit 30, fail-closed **pre-merge**, main byte-identical). Each
  repo announces itself once; the owner records its policy then. Rejected: a pre-emptive
  policy sweep (front-loads ungiven judgements) and bump-on-substantive-by-default (re-introduces
  the silent bump the release-hygiene contract reserves to the reviewer).

## `--fabled` closing pass

Ran opt-in; Fable available per `fable-config.sh check`. One closing subagent, design-critique
framing, fed a closing-time digest carrying the ratified decisions verbatim. Returned **8 findings,
F1–F8; the owner accepted ALL EIGHT.** Findings were emitted verbatim to the owner before any
decision prompt. F1/F2 → D1-A; F3/F4 → D2-A; F6/F7 → D3-A; F5/F8 → the corrections above. Fable
recorded no objection to the S5 ruling.

**Pre-registered escalation trigger — FIRED, and this is the 5th consecutive firing.** Counting only
findings that forced amending an already-ratified decision (F5 and F8 excluded as
correction/hardening): **F1, F2, F3, F4, F6, F7 = 6**, against a threshold of ≥2. Prior firings: 4
(2026-07-26), 4 (07-29), 5 (08-10), 7 (08-13). Every one of the six was a hole in reasoning ratified
minutes earlier in the same session. This is the pre-registered evidence for the per-decision pass
and the full multi-pass (`id:8df5`); recorded here so the count stays auditable. The build decision
remains the owner's.

## Action items

- [ ] Operationalize D1's shipping gate: pre-register a concrete query class (e.g. "all open items across repos blocked on X", "status history of id Y") so the gate can clear or fail; record the exemption for gate-unblocking work. Contract a test would verify: the gate names at least one query with a decidable pass/fail. <!-- id:eb52 -->
- [ ] Record the tracker pilot's CLOCK-START as a dated, greppable line when `cb22`'s writes land — the 4-week fail condition against the `id:8066` control arm cannot fire until it exists. Contract: a scanner can answer "has the clock started, and when" without reading a meeting note. <!-- id:fddb -->
- [ ] File the D2-A measurement with an explicit trigger: bytes actually READ per dispatched item (slice + any ledger the child opens), baseline before `id:e68f` lands and after. Contract: the lint decision is made on this number, or explicitly declined. <!-- id:41e4 -->
- [ ] Author the ratified `cb22` writes (pool-authorable): the S1+S2 mirror convention note + importer rule WITH the D3-A status-disagreement flag and an EXPLICIT parent/plugin pair list; 2 typed edges for S3; fresh id + typed edge for the S4 executing side after a token sweep; 4 allow-list lines with `# UNCONFIRMED` stripped (S5×3, S6×1); and fix the stale allowlist header in the same commit. Contract: the fleet import stops exiting 3. <!-- id:695d -->
- [ ] Correct `id:e68f`'s over-read claim and `id:b018`'s budget basis per F5 — e68f lowers the default, it does not enforce; b018 must budget for what a child MAY pull. Contract: neither item's text asserts an enforcement it does not have. <!-- id:9663 -->

## Forward flags (not action items)

- `id:8df5` — 5th consecutive escalation firing (6 forced amendments). Owner's build call.
- `id:55f6` remains `[INPUT — meeting]`; not opened this session.
- `meeting-question-guard` missed a turn this session that it caught earlier at comparable length — a guard that catches one instance and not the next trains false trust. Filed separately.
