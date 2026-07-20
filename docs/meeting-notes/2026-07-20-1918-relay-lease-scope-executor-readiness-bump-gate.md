# 2026-07-20 — Relay reliability: lease scope, executor-readiness detection, and the bump-close gate

**Started:** 2026-07-20 19:18
**Session:** ebd81aaf-65a5-4baa-b47d-de2892e83426
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration / lease topology), ⚙️ Sage (skill-runtime / contract mechanics)
**Topic:** Two inbox items from the loderite manual relay-drain (2026-07-20) surface three relay-reliability defects — a meeting↔executor lease collision, over-eager `execute` routing for not-ready items, and a premature user-visible bump-close.

## Surfaced context
- `claim.sh` SCOPE INVARIANT (id:179e, meeting D2 k3s-parallelity): the hard lease guards *code/worktree integration only*; ledger-only writes peek-and-warn (id:c144) — but the enforcement code doesn't implement this.
- [[bump-trigger-changelog]] (id:e647/b8fa): reviewer bumps at integrate *per user-observable close* — "user-observable" is reviewer judgment.
- review.md §3(c) / [[relay-human-gather-underreport]]: "name the real app entry actually wired," not a subset/harness.
- Global CLAUDE.md: "a delegated agent's verdict is a recommendation, never a self-settling decision" / "no quiet decisions."
- [[claim-asymmetry]]: claim collisions were OBSERVED, fix gated on ≥2–3 recurrences — routed:4361 is now a concrete recurrence with owner friction.
- id:46f6 typed-edge engine (closure-by-checkbox; UNRESOLVED = loud) — the SSOT for resolving `gated-on:` edges.
- id:7a05 / id:077d shared git-hook enforcement framework ([[Git-hook enforcement substrate (7a05 reconciliation)]]) — reconcile-before-greenfield; checks plug in as one engine.

## Agenda
1. routed:4361 — a `--mode meeting` claim hard-refused a parallel executor's `--mode execute` acquire. How do we make `claim.sh` honor its own SCOPE INVARIANT?
2. routed:1c08a — `actionable_routine_open` over-reports: `execute` routed repeatedly for owner-on-device-pending / spike-gated / spec-less items. Detect+suppress, or surface-why-not-ready?
3. routed:1c08b — a `@manual`-acceptance item was bump-closed on a "driver's directive" → premature bump. Tighten the user-visible-close gate.

## Discussion

### Item 1 — the meeting↔executor lease collision (routed:4361)

🏗️ **Archie:** The bug is in `claim.sh:192–205`. `acquire` is mode-blind — it records `--mode` (line 221) but the refusal test is purely `is_live($shard)` on the same safekey from a different run. `/meeting`'s setup claim (`meeting/SKILL.md:20`, `acquire <repo> --mode meeting`) sits on the exact key the hard code lease uses, so a later `acquire <repo> --mode execute` from an executor is refused. The SCOPE INVARIANT (claim.sh:11–26) *says* a meeting is ledger-only and peek-and-warns — but the meeting's own setup acquires the hard-lease key anyway. Doc and code disagree.

😈 **Riku:** The incident asymmetry: the meeting wrongly held, the executor was wrongly blocked. The reporter's workaround (owner-authorized lease-ignore + path-scoped commits + `git-lock-push --ff-only`) worked cleanly — evidence the two run safely concurrent. Whatever we do must let the executor proceed, while keeping the two-real-executors-refuse-each-other invariant.

🎛️ **Orla:** Three framings, constrained by the one-shard-per-key storage: **X** (mode-aware, same key) fails because a meeting+execute can't coexist in one shard file — execute would clobber the meeting's shard; **Y** (advisory signal on a distinct key `meeting:<repo>`) leaves the hard-lease key `<repo>` untouched by a meeting so an executor acquire is never refused; **Z** (meeting stops acquiring, peek-and-warn only) is simplest but drops the pool→meeting half of the bilateral guard.

✂️ **Petra:** Z is "dissolve over guard" — least code. Is the pool-skip load-bearing?

🎛️ **Orla:** In one case: the meeting rescopes item A while the pool concurrently executes+integrates A (the "reshape a shared plan" hazard). Today that's guarded bilaterally — the meeting checks the pool (peek-and-warn) AND the pool checks the meeting (the advisory claim). Z keeps only the first half.

🏗️ **Archie:** Which is why I favour **Y** — the collision was never inherent to the bilateral guard, only to the key conflation. X collapses into Y anyway.

😈 **Riku:** Caveat for the record: Y's pool-skip must match the advisory shard by `repo` field, and a manual executor drain should *proceed past* a meeting's advisory claim with a WARN, not a refusal.

**→ Owner decision (D1, first pass): Y — separate advisory key.**

### Item 1 amendment — Fable re-review corrected a false premise

An independent Fable-5 adversarial reviewer read the *actual consumers* (`relay-loop.js`, `reconcile-repo.sh`, live ROADMAP.md) and found:
- The meeting's current acquire passes **no `--repo`** (`meeting/SKILL.md:20`); the pool builds its live-repo set from `.repo` values (`relay-loop.js:909`). Moving to key `meeting:<repo>` without also adding `--repo <root-basename>` makes the advisory claim invisible to every repo-field matcher. Mandatory add + spec test.
- **There is no dispatch-time pool→meeting skip today.** The only repo-field consumer is the worktree-reap guard (`reconcile-repo.sh:152–162`), which never fires for a meeting (no worktree). The only thing that ever made the pool back off a meeting-held repo was the same-key acquire refusal (`relay-loop.js:1590`) — the exact accident Y removes. So as first framed, Y silently degenerates into the rejected Z for the pool-skip purpose; the "preserves the bilateral guard" claim was **false**.

Re-opened as an amendment. Building a real dispatch-time skip means pulling forward id:9000 (bilateral advisory honor, previously held at observe-first) and may be dissolved by id:5a39 (meeting-as-relay-producer). Owner chose the branch.

**→ Owner decision (D1, amended): branch b — ship the distinct-key executor-unblock now; record the pool→meeting skip as aspirational, gated on id:9000/5a39. No false "preserved guard" claim.**

### Item 2 — `actionable_routine_open` over-reports not-ready items (routed:1c08a)

🏗️ **Archie:** `classify-repo.sh:144–158` increments `actionable_routine_open` for an open `[ROUTINE]`/`@wire`-pool item unless `is_human` / `blocked` / `in_exempt_section`. The reporter's three leak-through states match no carve-out: on-device-pending, spike-gated ("pending d215"), spec-less ("⚠ SURFACED — no RED spec").

⚙️ **Sage:** Three different classes, three different right answers: (1) on-device/owner-verify-pending → a normalized `@owner-verify` tag the executor gate excludes; (2) spike/dependency-gated → honor the typed `gated-on:` edge; (3) no-RED-spec/SURFACED → route to `handoff`, not `execute`.

😈 **Riku:** No prose substring greps — that's the id:4da4/0d58 trap ("pending" is too common). Mechanize only the *structured* signals (typed `gated-on:` edge, SURFACED status); make the fuzzy on-device residue a LOUD "why-not-ready" surface, never a silent execute.

🎛️ **Orla:** = hybrid (C): detect the reliable ones, surface the rest loudly — satisfies the reporter's "detect OR surface" both ways.

✂️ **Petra:** N=2 scope alarm — three markers plus a route plus a surface. But the reporter hit all three in one drain (recurrence cleared), and classes 2/3 reuse existing machinery (typed-edge ledger, surface-count fold). Marginal new build = the `@owner-verify` tag + loud surface.

**→ Owner decision (D2): C (hybrid), all three classes in one handoff.**

**Fable amendment (folded in):** `gated-on:` must resolve against the *target id's checkbox state* via the id:46f6 typed-edge engine (block iff target still open; dangling/unresolvable → LOUD, never a silent block) — **not** "line contains `gated-on:` ⇒ blocked". Live ROADMAP lines 43/45/47 are *done* items still carrying the edge; an unconditional read would make the block permanent (a silent rotting under-dispatch). Reuse the 46f6 engine, don't reimplement edge resolution in `classify-repo.sh`'s line loop. Also: define `@owner-verify` / `@owner-accepted` / `@manual` side-by-side in `hard-lanes.md` (what each marks, which excludes from `actionable_routine_open`); `@owner-verify` joins the conservative `is_human`-style exclusion (under-dispatch-safe direction). FLAG: class-3 "no RED spec" detection keys on the per-repo `# roadmap:XXXX` test-header convention — define the signal per-repo-convention or it silently no-ops in repos lacking it.

### Item 3 — the user-visible-close + bump gate (routed:1c08b)

🏗️ **Archie:** `version-bump.sh` is called by the serialized integrator only for a close the reviewer *judged* user-observable (D1; `version-bump.sh:10`). The incident: a `@manual`-acceptance item ("NOT executor-closeable") was bump-closed on a "driver's directive" → premature v0.58.x bump. Two failures: the acceptance was the *owner's* to give, and nothing verified the *real app entry* calls the new path (a dev harness was mistaken for shipped).

😈 **Riku:** Textbook "a delegated agent's verdict is never self-settling" / "no quiet decisions". Gate **3a** — require an explicit greppable owner-accept marker before a user-visible/@manual-acceptance item can be bump-closed — enforces an existing rule; fail-closed-mechanizable (token present or not). Gate **3b** (grep the real app entry) is directionally right but a naive grep is unreliable both ways (indirection, re-exports, dynamic dispatch) — per mechanize-**reliability**, 3b belongs with the §2b judgment-residue checks (grep-assisted, loud), NOT a mechanical pass/fail.

✂️ **Petra:** Clean split — 3a = new hard fail-closed gate; 3b = new reviewer judgment cross-check. Out of scope: re-deriving "user-observable" in general (stays reviewer judgment per D1); a universal entry-point resolver.

**Owner amendment (raised at closure):** link 3a to the pre-commit hook.

🏗️ **Archie:** Lands on [[Git-hook enforcement substrate (7a05 reconciliation)]] (id:077d). 3a's mechanical half is a ledger-provenance check the framework hosts; a hook catches a manual bump *outside* review — the incident channel.

😈 **Riku:** Constraints: reconcile-before-greenfield — 3a becomes a *plugin* into id:077d, never a fresh hook. And only 3a is hook-able; 3b is not (same indirection reason). Don't let the hook idea bleed into pretending 3b is mechanical.

**→ Owner decision (D3): 3a hard fail-closed gate + 3b judgment cross-check; 3a homed in BOTH review.md (now) AND a git-hook plugin into 7a05/id:077d (gated on 077d readiness). 3b review-only.**

**Fable amendment (folded in):**
- **3a marker is spoofable by the exact actor that caused the incident** — a drain session could write `@owner-accepted` itself ("a lock whose key is lying next to it"). Add a provenance rule: (a) the executor contract explicitly *forbids* executors/drain sessions writing `@owner-accepted` (contract-surface change → bump `executor-contract.md` to **v10** + refresh the CLAUDE.md `## Relay contract` pointer); (b) review.md §2b gains a gaming-check — "was `@owner-accepted` introduced inside the reviewed diff by executor commits? → flag + reopen" (same forcing-function shape as the §2b.6 `refactor:` check, review.md:86–96).
- **Bind the gate at item-close, not the repo-level bump command.** The `@manual` item stays open and is *excluded from the user-observable-close set* feeding the bump decision — NOT "no bump while any @manual item lacks a marker" (which would block unrelated legitimate bumps repo-wide).
- **3b phrasing:** in review.md, say "the app's real entrypoint(s), not a dev harness" with `main.ts`/`editor.ts` as the (loderite-specific) example.

## Decisions

- **D1 (routed:4361), branch b:** Fix the meeting↔executor lease collision by moving the meeting's advisory "pool skip me" claim onto a **distinct key** (`meeting:<repo>` or equivalent), so the hard-lease key `<repo>` is never touched by a meeting and an executor's `acquire <repo> --mode execute` is never refused. The meeting acquire/release **must** pass `--repo <root-basename>` (else the claim is invisible to `relay-loop.js:909`'s repo-set) — with a spec test asserting the repo appears in the peek repo-set. A manual executor drain proceeds past a meeting's advisory claim (WARN, not refusal). **The pool→meeting dispatch-time skip is recorded as aspirational, gated on id:9000 (bilateral advisory honor, owner-held at observe-first) and possibly dissolved by id:5a39.** *Out of scope:* building the dispatch-time honor point now; changing the two-real-executors-refuse-each-other invariant.
- **D2 (routed:1c08a):** Classifier hybrid, all three not-ready classes: (1) `@owner-verify` normalized tag for owner-on-device-pending → excluded from `actionable_routine_open` via the conservative `is_human`-style path + a LOUD why-not-ready surface for un-normalized smells; (2) honor the typed `gated-on:` edge as a block **resolved against the target id's checkbox state via the id:46f6 engine** (open → block; done/dangling → not a block, loud on unresolvable) — never a bare substring read; (3) SURFACED/no-RED-spec → verdict `handoff`, not `execute`. Define `@owner-verify`/`@owner-accepted`/`@manual` side-by-side in `hard-lanes.md`. *Out of scope:* prose substring detection of any marker; a class-3 signal that assumes the `# roadmap:XXXX` convention exists in every repo (define per-repo-convention).
- **D3 (routed:1c08b):** Tighten the user-visible-close + bump gate. **3a** = hard fail-closed gate: a user-visible/@manual-acceptance item cannot be bump-closed without an explicit greppable owner-accept marker (e.g. `@owner-accepted:YYYY-MM-DD`); absent → item stays open, no bump, REVIEW_ME "needs owner-accept"; a driver's directive is insufficient; the item is *excluded from the user-observable-close set* feeding the bump (not a repo-wide bump block). **Provenance rule:** executor contract forbids executors/drain writing `@owner-accepted` (bump `executor-contract.md` → v10 + CLAUDE.md pointer refresh); review.md §2b gaming-check for an executor-introduced marker. **3a homed in BOTH** review.md (now) AND a git-hook plugin into 7a05/id:077d (reconcile-before-greenfield; a plugin, gated on 077d readiness). **3b** = reviewer judgment cross-check in review.md §2b (grep-assisted "does the app's real entrypoint call the new path, not just a dev harness?", surfaced loudly). *Out of scope:* a mechanical entry-point grep gate; re-deriving "user-observable" in general (stays reviewer judgment per D1/e647).

## Action items

- [ ] **[HARD — meeting] routed:4361 — meeting↔executor lease scope fix (branch b)**: move the meeting advisory claim to a distinct key (`meeting:<repo>`), add mandatory `--repo <root-basename>` to the meeting acquire+release (`meeting/SKILL.md` step 2-setup-claim), so an executor `acquire <repo> --mode execute` is never hard-refused by a meeting; a manual drain WARNs-and-proceeds. RED spec asserts (a) the meeting repo appears in `claim.sh peek`'s repo-set, (b) a concurrent execute acquire on `<repo>` succeeds while a meeting advisory claim is live. Record the pool→meeting dispatch-time skip as pending id:9000/5a39 in the SCOPE INVARIANT block. Contract surfaces: `claim.sh`, `meeting/SKILL.md`. Relates id:9000, id:5a39, [[claim-asymmetry]], [[parallelism-d2]]. See `docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md`. <!-- routed:4361 --> <!-- id:0ee1 -->
- [ ] **[HARD — meeting] routed:1c08a — classifier not-executor-ready hybrid (all three classes)**: in `classify-repo.sh`/`classify-verdict.sh` — (1) `@owner-verify` tag joins the conservative `is_human`-style exclusion + LOUD why-not-ready surface for un-normalized not-ready smells; (2) honor typed `gated-on:` as a block resolved via the id:46f6 engine against the target id's checkbox (open→block; done/dangling→loud, not silent); (3) SURFACED/no-RED-spec → verdict `handoff` not `execute`. Document `@owner-verify`/`@owner-accepted`/`@manual` side-by-side in `hard-lanes.md`. RED specs per class; class-3 signal defined per-repo-convention (don't assume `# roadmap:XXXX` everywhere). Relates id:46f6, id:4da4, [[mechanize-reliab]], [[classifier-4d8e]]. See the meeting note. <!-- routed:1c08 --> <!-- id:65f5 -->
- [ ] **[HARD — meeting] routed:1c08b — user-visible-close + bump gate (3a fail-closed + provenance + 077d hook + 3b judgment)**: (3a) fail-closed owner-accept-marker gate in `review.md` (absent → item stays open, excluded from the user-observable-close set feeding the bump, REVIEW_ME "needs owner-accept"); driver's directive insufficient. Provenance: forbid executors/drain writing `@owner-accepted` in `executor-contract.md` (bump → **v10** + refresh CLAUDE.md `## Relay contract` pointer) + a review.md §2b gaming-check for an executor-introduced marker. Homing: review.md now + a git-hook plugin into 7a05/id:077d (reconcile-before-greenfield, gated on 077d readiness). (3b) reviewer judgment cross-check in review.md §2b — "does the app's real entrypoint (not a dev harness) call the new path?", grep-assisted, loud. Relates id:e647, id:b8fa, id:7a05, id:077d, [[relay-human-gather-underreport]], [[bump-trigger-changelog]]. See the meeting note. <!-- routed:1c08 --> <!-- id:8089 -->

## Meta

- Fable-5 adversarial re-review was run at owner request after the three decisions were provisionally taken (this is the id:7e87 "`/meeting --fabled`" pattern, ad-hoc). It corrected a false premise in D1 and closed real gaps in D2/D3 — a concrete data point for that item.
