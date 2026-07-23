# 2026-07-23 — Semver-bump + CHANGELOG enforcement cluster: consolidate four items, settle the refactor cadence

**Started:** 2026-07-23 23:20
**Session:** 02a4e274-0d9b-4cc7-beb6-a47046a93cb5
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🛰️ Hank (host-fleet config topology; cache-vs-derivation), 🔩 Gil (git object-model / plumbing)
**Closing pass:** 🜂 Fable (`claude-fable-5`), adversarial re-review before recording — see `## Fable closing pass`
**Topic:** Consolidate id:7034 / id:d1b2 / id:f6d5 / `routed:b21c` into one defect + one build, and decide whether an internal refactor bumps.

## Surfaced discoveries

- `[2026-07-12 dotclaude-skills]` Repo self-governance (id:8ef3/a6e1): a manifest-less symlink-published toolkit versions only its contract surfaces (git = repo SSOT).
- `[2026-07-01 zkm-stt]` A content-derived cache key dissolves the revert hazard of a hand-bumped version counter.

## Agenda

1. Are id:7034 / id:d1b2 / id:f6d5 / `routed:b21c` one item or four? What is the actual defect?
2. Where does enforcement live, and does it belong in the id:7a05/077d framework or before it?
3. `routed:b21c` — adopt a global default cadence, or keep the *when* per-project?
4. Sequencing, and the changelog consequence of (3).

## Discussion

### The defect, located

🏗️ **Archie** put the actual defect on the table, which all four items describe and none names. There are **three** integration paths, and the bump/CHANGELOG step exists in exactly one:

| Path | Bump/CHANGELOG? |
|---|---|
| Workflow pool integrator — `relay/scripts/relay-loop.js:2006-2011` (steps 2a/2b) | **Yes** |
| Off-Workflow drain — `relay/scripts/drain-driver.mjs` | **No** — `grep -c 'version-bump\|changelog-append'` = **0** |
| Supervised/interactive integrate — `relay/SKILL.md` invariant 5 | **No** — verify → isolation → `--no-ff` → `ckpt-tag.sh` → push → prune → relay.toml. No bump step exists to forget. |

`routed:c545`'s claim ("SKILL.md invariant 5 and review.md have NO version-bump step") was verified and is correct. loderite's four unbumped waves and its CHANGELOG stale since v0.51.0 were not a reviewer forgetting a step — they ran a path where the step was never written down.

😈 **Riku** ruled id:7034's framing wrong on that evidence: it says the mechanism "landed but nothing FORCES it fires", implying a compliance problem, so it reaches for enforcement. You cannot enforce a step onto a procedure that does not contain the step. Enforcement on the drain path today would fire on every drain integrate — a permanent red light, not a guard.

✂️ **Petra** re-sorted the four by what they would actually build: f6d5 = build the missing step; 7034 = subsumed (its content is a missing-step report); d1b2(b) = a genuinely different invariant (catches a **hand** bump outside the relay entirely); d1b2(a) = independent and the weakest.

🛰️ **Hank** gave the topology reason to prefer one *callable* unit: `relay-loop.js:2a/2b` is an **LLM instruction inside a prompt string** — ~40 lines of prose telling a model to run two scripts in the right order with the right conditional flags. That prose is a hand-maintained cache of a procedure; copying it into two more places yields three caches of one derivation, drifting independently.

🔩 **Gil** supplied the plumbing argument against a prose checklist: f6d5 point (4) — *"lightweight tags are NOT carried by `git-lock-push --follow-tags`"* — is correct. `--follow-tags` pushes annotated tags reachable from the pushed ref and skips lightweight ones. A human following prose types `git tag v0.5.2`; a script types `git tag -a`. The failure is invisible until you look at the remote.

😈 **Riku** attached the condition that the bump *level* is not derivable (`version-bump.sh:65` already refuses anything but explicit `--level`; D1 of meeting `2026-07-17-1541` rejected full derivation), so the new script must take the judgement as a **required** argument including an explicit `none` — any default trades a missing step for a wrong one.

### The refactor cadence

🏗️ **Archie** found the gap worse than `routed:b21c` states. Three live documents give three answers for "internal refactor, no user-visible change":

| Source | Refactor-only close → |
|---|---|
| Global `~/.claude/CLAUDE.md` §Versioning, loose-0.x | **minor** — *"minor = anything else (feature, dep change, internal refactor, behaviour change)"* |
| `relay-loop.js:2a` (id:e647, meeting `2026-07-17-1541` D1) | **no bump** — *"A REFACTOR-ONLY / internal-cleanup close must NOT bump"* |
| `routed:b21c` proposal | **patch** |

😈 **Riku**: b21c's premise ("the *when* is left per-project") is therefore wrong — it is specified three times incompatibly, and one of those is the global rule b21c wants to amend. He also pre-empted the scope question: b21c was **owner-ratified for loderite**, which is not ratification as a fleet default — the same distinction the owner drew in the Yantrala call (a truncocraft-scoped screen wrongly applied to yinyang-puzzle).

✂️ **Petra** found the N=2 anyway: every manifest-bearing repo the relay integrates hits this, and the relay's integrator already had to invent an answer *because* the global rule gave none.

🛰️ **Hank** argued the relay's rule is the one that actually fires, unattended, dozens of times a week; the global doc is read by a human who may or may not act. When they disagree the integrator wins in practice, so the doc is a stale cache of a behaviour it does not control.

😈 **Riku** flagged that this resolves the conflict in the relay's favour without the owner deciding it, and laid out the real cost each way: *no bump* keeps version numbers meaningful but lets a repo absorb months of internal work at a frozen version (the loderite complaint); *minor* drains the minor number's signal; *patch* records internal work but redefines patch away from "bugfix only".

🔩 **Gil** noted the asymmetry: every bump drags a lockfile regen, and in zkm's case an ~18-plugin `uv.lock` cascade — so patch-per-internal-integrate is the most expensive option and the one that fires most often.

### Sequencing consequence

🏗️ **Archie** named the downstream effect of D3: `changelog-append.sh` release-buckets with `--version` and date-buckets without, so a semver repo's CHANGELOG now interleaves both. 😈 **Riku** held that the date entries are what make D3 defensible rather than dismissive — suppress them and b21c is answered with "your internal work is recorded nowhere". 🛰️ **Hank** scoped the global edit to its minimum: the phrase "internal refactor" in the loose-0.x *level* enumeration is the only wrong part.

## Fable closing pass

Invoked at the closure gate. **`/meeting --fabled` is NOT built** (id:7e87 open, `ROADMAP.md:165`, gated on id:7681; `validate-flags.sh:132` — *"today just `--cross`; `--fabled` will land the same way"*), so the intent was honoured manually via a `claude-fable-5` agent. The probe cache read `available: true` but **stale**; Fable answered, so it is up.

Fable's findings were treated as a **recommendation, never self-settling** (CLAUDE.md delegated-verdict rule). Every load-bearing claim was verified before it reached a decision:

| Fable claim | Verification |
|---|---|
| Integrate agent runs on Sonnet | ✅ `relay-loop.js:2034` — `{ label: …, schema: INTEGRATE_SCHEMA, model: 'sonnet' }` |
| `drain-driver.mjs` cannot host the call; `drain-integrate.sh` is merge-only | ✅ file exists, `grep -c 'version-bump\|changelog-append'` = 0 |
| `version-bump.sh` commits **then** tags | ✅ step (4) `git commit -q`, step (5) `git tag -a` |
| `changelog-append.sh` bucket lookup is first-match-anywhere | ✅ `hdr_idx = next((i for i, ln in enumerate(lines) if matches(ln)), None)`; new bucket inserts before the *first* header |
| `version-bump.sh` leaves the manifest dirty on lockfile-regen failure | ✅ step (1) writes the manifest; step (2) `\|\| exit 1` with no rollback |

Four decisions were amended as a result. **Verdict: RECORD WITH FIXES.**

## Decisions

Amendments below are **superseding entries citing what they supersede** — the ratified originals are recorded verbatim, never silently rewritten.

- **D1 — Build ONE `release-hygiene.sh`, wired to three call sites.** `release-hygiene.sh <repo> --level minor|patch|none --summary … --ids …` owns the ordered bundle. `--level` is **required and three-valued with no default** — the bump level is a judgement (`version-bump.sh:65`, meeting `2026-07-17-1541` D1), so a default would trade a missing step for a wrong one. No-op on version-less repos. id:f6d5 is the build item; **id:7034 closes as superseded by it**, its ENFORCE intent carried by the completeness test in D1-A3.
  *Out of scope:* deriving the bump level; a `major` level (pre-1.0 ceiling — recorded as a known limit).

- **D1-A1 (amends D1, Fable hole 1) — the third call site is NOT `drain-driver.mjs`.** *Superseded text:* "Wire all three integration paths (relay-loop.js, drain-driver.mjs, SKILL.md invariant 5)". `drain-driver.mjs` is a loop harness — it runs `DRAIN_ROUND_CMD`, classifies round-result JSON, manages heartbeat/quota; it never merges and never sees `report.summary`, so it cannot supply a required judgement argument. The drain call site is the **id:8ba1 apex-driver procedure** and the SKILL.md `--drain` section. f6d5 records a dependency on id:8ba1 rather than pretending the seam exists today.

- **D1-A2 (amends D1, Fable hole 2) — commit-then-tag.** *Superseded text:* bundle order "bump → lockfile → changelog → annotated tag → scoped commit". Tagging before the scoped commit lands the tag on pre-release HEAD, violating the global bump-and-tag rule. Correct order is **… → scoped commit → annotated tag**, matching `version-bump.sh` steps (4)/(5). The spec must also state explicitly whether the changelog folds into the tagged release commit or stays a second commit (today `relay-loop.js:2011` commits it separately, so the v-tag's tree does *not* contain the changelog entry) — pick one, do not let a test encode an accident.

- **D1-A3 (amends D1, Fable holes 3 + 8) — f6d5's acceptance gains a completeness test and a rollback spec.** Two of three call sites are prose executed by an LLM, and the only mechanical check (d1b2(b)) is gated on the unbuilt id:077d — so after D1+D2 nothing obliges any call site to invoke the script, violating the enforce-don't-document rule the decision cites. f6d5 acceptance therefore includes: (a) a **three-surface completeness test** grep-asserting every integration surface references `release-hygiene.sh`, modelled on the `ALLOWED_RELAY_SCRIPTS` test (id:5bbb); (b) **failure rollback** — restore the manifest on any post-rewrite failure, since `version-bump.sh` currently exits dirty and `clean-tree-gate.sh` then defers the repo indefinitely under a misleading "concurrent edit" diagnosis.

- **D2 — Split id:d1b2.** Half **(b)** (pre-commit check: manifest version changed ⇒ annotated tag in the same commit, AND actual ≥ max annotated) stays **gated on id:077d** — it catches a hand bump outside the relay, a genuinely different channel from the missing-step defect. Reconcile-before-greenfield stands (its own text and `review.md` §5c both defer to that framework).

- **D2-A1 (amends D2, Fable hole 4) — d1b2(a) is DEMOTED to advisory, not dropped.** *Superseded text:* "(a) … is DROPPED as redundant once `release-hygiene.sh` takes `--level` at integrate." The premise was wrong: `relay-loop.js:2034` dispatches the integrate agent as **`model: 'sonnet'`**, so the judgement step 2a calls "the REVIEWER's alone" is exercised by Sonnet. `--level` fixes *where* the argument is passed, not *who* judged it. The Opus handoff author annotates each ROADMAP item's bump level; the Sonnet integrator **reads** it rather than improvising, and **may override** when the close's scope shrank since handoff (a stale annotation must never force a wrong bump).
  *Out of scope:* re-tiering step 2a's integrate agent to apex — considered and not chosen here.

- **D3 — An internal refactor does NOT bump.** The relay's existing rule wins over the global doc's "minor" and b21c's "patch". Version numbers stay user-meaningful. Accepted cost: a repo can sit at a frozen version through internal work — mitigated by D5, not by a bump.
  *Out of scope:* re-deriving "user-observable" mechanically (stays reviewer judgement per id:e647 D1).

- **D4 — The global doc states LEVEL semantics only; the relay contract owns the TRIGGER.** `~/.claude/CLAUDE.md` §Versioning keeps bump-and-tag, bump-includes-lockfile, the zkm cascade, loose-0.x levels and Polyrepo, and **points at** the relay contract for when a bump fires rather than restating it. One derivation, one cache, cache labelled as such.

- **D5 — Keep the changelog mix: internal closes date-bucket.** A non-bumping internal close still writes a date-bucketed entry; user-visible closes write version-bucketed entries. This is what makes D3 an answer to b21c's "invisible work" grievance rather than a dismissal of it.

- **D5-A1 (amends D5, Fable hole 5) — the same-day interleaving is a defect, filed.** `changelog-append.sh:115` looks up a bucket by first-match **anywhere** and inserts a new bucket before the **first** header. Same-day sequence: internal close creates `## <date>` → a release inserts `## vX.Y.Z` **above** it → a second internal close that day matches the now-**below** date bucket and appends there, so post-release work permanently reads as pre-release in a file whose preamble forbids reordering. Also unresolved: standing date buckets between releases never fold into the next release, so a reader cannot tell which version ships a date-bucketed change. Filed as id:010c; the standard remedy (an `## Unreleased` bucket the next release absorbs) is scoped in that item, not decided here.

- **D6 — Apply the §Versioning edit** (owner-approved inline): (1) remove `internal refactor` from the loose-0.x level enumeration — it is a *level* list and naming a refactor there reads as an instruction to bump, which D3 forbids; (2) add a `Bump trigger` paragraph that points rather than restates.

- **D6-A1 (amends D6, Fable hole 6) — retarget the pointer and cover non-relay repos.** *Superseded text:* the paragraph cited "`relay-loop.js` step 2a". D1 demotes that step to a one-liner, so the global doc would be born pointing at a demoted surface — the derived-doc drift class the global file's own heuristic warns about. Point at `release-hygiene.sh` / "the relay contract" abstractly. Add one clause: **relay-managed repos → the relay contract owns the trigger; elsewhere the bump-and-tag rule stands on any manual bump** (§Versioning governs all repos, including ones the relay never touches).

- **D7 — The instance routes to `mathematical-writing` id:aae4, not re-filed here.** Inflownistration / information-dependency propagation is tracked at `~/src/mathematical-writing/TODO.md` under id:aae4; `dotclaude-skills/TODO.md:287` already carries a `ref:aae4` pointer marked *"(pointer — do not re-file)"*. This session is a clean instance: meeting `2026-07-17-1541` D1 decided *refactor-only → no bump*, and the follow-ups never fired — the global CLAUDE.md enumeration stayed stale, and six days later b21c's author read it and concluded the *when* was unspecified. Three documents drifted until a human called a meeting.
  *Out of scope:* building anything for aae4 here; this contributes evidence only.

**Recorded, not adopted:** Fable's NITs — `--level` has no `major` (pre-1.0 ceiling); `version-bump.sh`'s zkm cascade `--push` publishes plugin lockfiles before the parent's own push, so a parent push failure leaves plugins referencing an unpublished parent version; per-branch vs per-round bump granularity in a multi-merge drain round is unspecified; `"dep change"` survives in the level list while a purely internal dep swap is refactor-class under D3 (the same trigger/level conflation D6 fixes, one item over). None decided; surfaced for a future pass.

## Action items

- [ ] **id:f6d5** — build `release-hygiene.sh` per D1 + D1-A1/A2/A3. Contract a test would verify: `--level` required and three-valued (missing ⇒ non-zero, no default); no-op on a version-less repo; commit precedes `git tag -a`; manifest restored on post-rewrite failure; and a three-surface completeness test asserting `relay-loop.js`, `SKILL.md` invariant 5 and the `--drain` procedure each reference the script. Depends on id:8ba1 for the drain call site. `docs/meeting-notes/2026-07-23-2320-semver-changelog-enforcement-cluster.md`
- [ ] **id:010c** — fix `changelog-append.sh` same-day merge-below-release ordering (D5-A1). Contract: after a release bucket is inserted, a subsequent same-day non-release entry must not land in a date bucket positioned below it; decide and pin the `## Unreleased`-absorption behaviour. `changelog-append.sh:115`
- [ ] **id:d1b2** — amend in place per D2 + D2-A1: (a) demoted to an advisory handoff annotation the Sonnet integrator reads and may override; (b) unchanged, gated on id:077d.
- [x] **id:7034** — closed as superseded by id:f6d5 (D1); ENFORCE intent carried by D1-A3's completeness test.
- [x] **D6** — `~/.claude/CLAUDE.md` §Versioning edit applied per D6 + D6-A1.
- [x] **routed:b21c** — resolved by D3/D4/D6; global cadence settled as "refactor-only does not bump", global doc states level only.
- [ ] **→ routed to mathematical-writing inbox** — this session as an aae4 information-dependency-propagation instance (D7).
