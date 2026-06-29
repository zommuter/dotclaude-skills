# 2026-06-29 — Inbox auto-reconcile: open the slice-2 gate (id:678e, continuation)

**Started:** 2026-06-29 11:16
**Session:** bc20e396-4ef2-4860-92d5-33c6769235c2
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔩 Gil (cross-repo write integrity), 🧮 Reni (idempotent multi-writer set-merge)
**Topic:** Continuation of the 2026-06-25 inbox-reconcile contract (D1–D5: slice-1 detection shipped, slice-2 auto-write GATED). Decide whether the slice-2 gate is now open, settle the own-but-unconfirmed-target wrinkle that surfaced today, and decompose slice-2 into buildable units.

## Surfaced discoveries / prior art
- 2026-06-25 D1–D5 (`docs/meeting-notes/2026-06-25-2335-inbox-auto-reconcile-cross-repo.md`): detection-first; slice-2 = class-A reversible INBOUND stub gated on target-resolution (incl. polyrepo `# path:`, b257) + `claim.sh peek` skip + `routed:` idempotency; class-B prose / unresolvable target forever surface-only; runs once per cross-repo sweep honoring `paused`/`--exclude`; `RELAY_INBOX` path injection.
- THIS session dogfooded slice-1 (`scan-routed.sh`): emitted exact ready-to-run commands; 4 class-A dead-letters (routed:6976/4097/38db→dotclaude-skills, bfe0→mathematical-writing) hand-routed with zero resolution error; 2 UNRESOLVED (kienzler-homepage — own but no relay.toml block) surfaced.
- Profile (pre-emption-eligible, high): prefers reversible-and-visible over hard auto-action; ask-don't-auto on ambiguous/identity calls. Lever-first.
- [2026-06-22 truncocraft] inbox CAS+symlink split / pool-vs-meeting main-checkout collision (discoveries.md).

## Agenda
1. Is the slice-2 gate open — does the dogfood satisfy "proven target-resolution"?
2. The own-but-unconfirmed-target wrinkle (NEW): kienzler-homepage UNRESOLVED — class-B-forever or distinct disposition?
3. Decompose slice-2 into buildable `[ROUTINE]` units + ledger outcome.

## Discussion

**Agenda 1 — gate open?** 🏗️ Archie: D2's gate was "proven target-resolution"; scan-routed shipped + this session emitted the exact `append.sh -t inbox / inbox-done` command per dead-letter, 4 hand-run with zero error — slice-2 just wraps that printed command in an idempotent writer behind a claim-peek; whole substrate exists. 🧮 Reni: build it idempotent-by-construction keyed on `routed:XXXX` (f103 discipline) — grep target TODO for the token or its id-twin before writing; additive, re-runnable every sweep. 🔩 Gil: the bite is committing into another private repo's main checkout — needs `claim.sh peek` skip, own `commit-ledger.sh` commit (never `git add -A`), polyrepo resolution (b257: zkm-plugin target → zkm central TODO); scan-routed already has the resolver. ⚙️ Sage: make it a `--apply` flag on the EXISTING scan-routed (lever-first), default report-only. ✂️ Petra: gate opens class-A only; must not balloon into auto-onboard. 😈 Riku: profile prefers reversible-and-visible; n=1 dogfood is thin, but the auto-write does exactly the rote action we did 4× for the unambiguous class-A subset, everything ambiguous stays surfaced, and it's additive+idempotent+reversible+claim-guarded (D4's bar) — observe-first graduation; require a `--dry-run`/diff so the first sweep is inspectable.

**Agenda 2 — own-but-unconfirmed target.** 🏗️ Archie proposed a distinct UNCONFIRMED-OWN disposition (own per discover-repos.sh but no relay.toml block → actionable "confirm + re-scan"). 😈 Riku pre-empted (profile high-conf): ask-don't-auto — auto-onboard is out by the user's own stance (musAIviz overstep this session confirms); class-B-forever mislabels a fixable gap as permanent so the FOUC bug rots. ✂️ Petra: N=2 holds (kienzler + musAIviz this session). **User reframed sharper than the options:** the resolution axis is repo-EXISTENCE, not relay.toml membership — TODO *routing* ≠ relay *management*; just update the target repo's TODO without onboarding (matches id:3947 proposal-1). UNCONFIRMED-OWN dissolves.

**Agenda 3 — decompose.** 🏗️ Archie: 3 internal pieces (target-resolver / idempotent stub-writer / safety-wrapper). ✂️ Petra: ONE `[ROUTINE]` item, not four tickets; slice-2 graduates `[HARD — meeting]`→`[ROUTINE]`. ⚙️ Sage: build path = `/relay handoff dotclaude-skills` promotes + writes red spec → executor builds. 🔩 Gil: red test covers polyrepo / non-relay-own / nonexistent + idempotency + `--dry-run`. 🧮 Reni: idempotency key survives promotion (grep `routed:` OR minted `id:` twin).

## Decisions
- **D1.** Open the slice-2 gate. Build slice-2 as `scan-routed.sh --apply`: class-A reversible INBOUND stub only, idempotent on `routed:XXXX` (grep target TODO for the routed token OR its minted `id:` twin before writing), `claim.sh peek` skip for relay-managed targets, own `commit-ledger.sh` commit (clean tree, never `git add -A`), mandatory `--dry-run`/diff. The dogfood (4 class-A hand-routes, zero error) satisfies the 2026-06-25 "proven target-resolution" precondition. **Out of scope:** auto-onboarding any repo into relay.toml.
- **D2.** Target-resolution is by **repo-existence, not relay.toml membership.** Resolve `[target]` to a repo path via the canonical resolver (discover-repos.sh `own` + relay.toml `# path:` for polyrepo central-ledger, b257; an own repo on disk with no relay.toml block still resolves). Repo exists → write the stub into ITS TODO.md, no onboarding. Only a target matching NO repo on disk is UNRESOLVED → class-B surface-only. TODO routing ≠ relay management; the UNCONFIRMED-OWN special case dissolves (kienzler just gets its TODO amended — the user's original intent). relay.toml onboarding stays a separate, explicitly-asked decision. **Out of scope:** auto-onboarding; class-B prose auto-parse.
- **D3.** Slice-2 ships as ONE `[ROUTINE]` item (id:678e child), acceptance = the 3 internal pieces + 5 red-test cases (polyrepo→central TODO, non-relay-own→its TODO, nonexistent→UNRESOLVED, idempotent re-run = no-op, `--dry-run` = no write + diff). Re-tag id:678e slice-2 `[HARD — meeting]` → `[ROUTINE]`. Build via `/relay handoff dotclaude-skills`. **Out of scope:** the emit-time per-routed stub (id:3947 proposal-1) — separate future item.

## Action items
- [ ] Build slice-2 `scan-routed.sh --apply` per D1/D2/D3 (class-A idempotent auto-write; resolve-by-existence; `claim.sh peek` skip; own `commit-ledger.sh` commit; `--dry-run`; red tests for the 5 cases). Re-tag id:678e slice-2 → `[ROUTINE]`; promote via `/relay handoff dotclaude-skills`. <!-- id:678e -->
- [ ] (dogfood D2 now, manual) File the 2 remaining inbox dead-letters routed:7bcd (FOUC bug) + routed:b10a (contact note) into `kienzler-homepage/TODO.md` directly (no onboarding) + `inbox-done` — proves the non-relay-own write path before slice-2 automates it.
