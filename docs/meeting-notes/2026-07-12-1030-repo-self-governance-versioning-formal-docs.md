# 2026-07-12 — Repo self-governance: versioning + formal doc conventions

**Started:** 2026-07-12 10:30
**Session:** 3ebc9ec4-e462-4406-a1d7-1b6e53900c1b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, new), 🛰️ Hank (config-mgmt / cache-vs-derivation, new)
**Topic:** Should this manifest-less, meeting-notes-driven toolkit adopt formal governance artifacts — a version scheme (id:8ef3) and/or formal doc conventions ADR/SOP/UML (id:a6e1) — or keep dissolving governance into existing machinery?

## Triage note
Selected in a no-subject `/meeting` default-mode audit as an 80-20 combine: id:8ef3 (versioning) + id:a6e1 (formal docs) share one core tension — *add a parallel record vs dissolve into existing machinery* — and a6e1's own text cites 8ef3. Routed OUT of this session: id:cece (mattpocock prior-art — read/watch-first research, no live decision yet), id:83eb (persona-onboarding skill-internals — different domain), id:2a3d (glossary — natural home is project_manager per id:dc60). Surfaced-but-separate: 2 open `[ROUTINE]` ROADMAP items ingested today (id:3273 git-lock-push stall timeout, id:1b18 diary-append replay deadlock) → `/relay review dotclaude-skills` in a strong session.

## Agenda
1. **Versioning (id:8ef3):** does the repo need a version scheme given "the live install IS the published version"? If so, what does a "version" mean, on what substrate, triggered by what?
2. **Formal doc conventions (id:a6e1):** adopt ADRs / written SOPs / UML — decided *per-artifact* — or dissolve each into existing machinery (typed ledger edges id:46f6, id:2840 derived index, id:dc60 edge graph)?

## Grounding facts
- 267 git tags, **all `ckpt-*`; zero `vX.Y.Z`** — no semver today.
- Executor contract self-versions: `relay/references/executor-contract.md` is at **v6**, with a documented bump-and-update-pointer discipline (`:141`); `CLAUDE.md`'s `## Relay contract` pointer must match its `vN`.
- Other de-facto contract surfaces: memory-index frontmatter format (id:2e6d), the allowlist generator's literal 8-entries-per-script expansion, the classify.sh TSV column contract.
- Typed ledger edges `children:`/`gated-on:` already decided (2026-07-10, id:46f6); `id:ee62` contests opaque `<!-- ... -->` markers vs VISIBLE annotations.
- Global `~/.claude/CLAUDE.md` Versioning rule assumes a `pyproject.toml`-style manifest this repo deliberately lacks.

## Discussion — Topic A: Versioning (id:8ef3)

✂️ **Petra:** N=2, up front. Name two consumers who would *pin* a version of this repo. It's installed by `make install` as per-file symlinks into one person's `~/.claude`; the live symlink IS the published artifact. There is no downstream that says "I need dotclaude-skills v1.3." Zero named consumers → a repo-wide semver has nothing to serve. I'm out on the manifest before we start.

⚙️ **Sage:** Agreed on repo-wide, but don't overshoot to "no versions anywhere," because we already version the thing that actually needs it. `executor-contract.md` is at v6, and it self-versions *precisely because* a stale copy causes silent relay breakage — the `/relay executor` session and the `CLAUDE.md` pointer must agree on `vN` or work is done against the wrong contract. That's not decoration; it's a compatibility handshake. The pattern that earns its keep is a **version marker on a compatibility surface**, not a number on the whole repo.

🛰️ **Hank:** This is the cache-vs-derivation split I keep hitting. A repo "version" is a *derivation* — git already computes it (the SHA, the log, the tag graph). Hand-maintaining a `VERSION` file is authoring a cache of something the tool already derives, and a hand-edited cache is exactly the drift generator you don't want. A contract `vN`, by contrast, is a **decision**, not a derivation: it encodes "consumers built against ≤v5 must re-read." Nothing derives that for you, so authoring it is legitimate. So the rule falls out cleanly: git owns the repo version; humans author versions only where a consumer's compatibility depends on it.

🏗️ **Archie:** Let me make the surface list concrete, because "compatibility surface" needs to be enumerable or it's vibes. Today: (1) `executor-contract.md` v6 — has the marker + a bump discipline at `:141`. Latent, unversioned but should be: (2) the memory-index frontmatter format (id:2e6d) — a hook regenerates `MEMORY.md` from it; a format change silently breaks the index; (3) `classify.sh`'s TSV column contract — SKILL.md parses fixed columns; (4) the allowlist generator's 8-entries-per-script expansion. These are the places a "version" would carry information. A repo number would carry none.

😈 **Riku:** What breaks *today* if we do nothing repo-wide? Nothing — that's the honest answer, and it's the argument for deferral, not for building. But I'll name the one real pull: it's a **public** repo. A GitHub visitor asking "what changed between when I looked last and now" has no answer but `git log`, which is noisy. That's a genuine gap — but the fix is a thin `CHANGELOG.md` written *on demand*, not a semver machine. Minimum evidence that would flip me to a real scheme: one external consumer who needs to pin a version to install reproducibly. Until that exists, a version scheme is infrastructure for a user who hasn't shown up.

✂️ **Petra:** And note the global `~/.claude/CLAUDE.md` Versioning rule — bump-and-tag, bump-includes-lockfile — is written *for* `pyproject.toml` repos. It doesn't "apply and we're violating it"; it structurally doesn't reach a manifest-less bash+md repo. The correct move is to make that exemption **explicit** in this repo's CLAUDE.md so a future session doesn't "helpfully" apply the global rule and mint a phantom `VERSION` file.

🛰️ **Hank:** One caution on the contract-marker convention so it doesn't rot: whatever carries a `vN`, its bump discipline has to be *co-located and enforced*, like the executor contract already does (`:141`). A marker nobody bumps is worse than none — it asserts a compatibility guarantee it isn't keeping. So "bless the convention" must mean "document which surfaces carry a marker AND that changing the surface requires bumping it," not just sprinkle version comments.

🏗️ **Archie:** Concretely then: a short CLAUDE.md subsection listing the versioned contract surfaces + the "change the contract ⇒ bump the marker ⇒ update any pointer" rule, generalizing what executor-contract already does. No `VERSION` file, no `vX.Y.Z` tags, no manifest. Git stays the repo SSOT.

## Discussion — Topic B: Formal doc conventions (id:a6e1)

🏗️ **Archie:** Take the three artifacts separately, per the item's own instruction. **ADRs first.** Meeting notes already carry ≈ADR fields — Context / Decisions / Action items — but they're *chronological*, not *decision-indexed*, and they can be superseded silently. The live example is `id:65f9`: decided 2026-07-07, stale-open ever since, and nothing flagged it. That's the exact gap ADRs claim to fill: "given decision X, is it still current?" But we already have the decision handle — the `id:` token — and a typed-edge graph over it (`children:`/`gated-on:`, id:46f6). A `superseded-by:` / `status:` edge on the id closes the `id:65f9` gap without a second file to keep in sync.

🛰️ **Hank:** And "status: superseded" is a *derivation*, not a fact you author twice. If `id:X` carries a `superseded-by:Y` edge, its superseded-ness is computable — that's what id:2840's derived index and id:dc60's edge graph are *for*. An ADR file with a hand-maintained `status:` field is a cache of that derivation, and the moment you edit the edge but not the file (or vice-versa) they drift. So the move is: adopt the **edge** as the source of truth, let the index/graph *derive* the ADR-style status view on demand. You get the ADR benefit (decision-indexed, supersession-tracked) with zero parallel record.

😈 **Riku:** I'll block the syntax, not the direction. `id:ee62` is still open and it says human-readable *reasons/decisions* must be **VISIBLE**, not buried in opaque `<!-- ... -->` tokens. `superseded-by:abc1` is exactly the opaque form ee62 objects to. So a `superseded-by:` edge **inherits `id:ee62` as a hard blocker** — the visible-annotation syntax has to land first, or we're shipping the thing ee62 was raised to prevent. Ratify the direction today; gate the implementation on ee62. Minimum evidence I'd need to drop the ADR-file idea entirely: that the edge + derived view actually surfaces a silent-supersession case `id:65f9`-style. That's a testable contract, not a vibe.

✂️ **Petra:** N=2 for ADR-**as-file**: name two decisions that needed an immutable, one-file-per-decision record that meeting-notes + id-edges could not serve. Nobody can — so no ADR file format, no `adr/` directory. **SOPs:** we already *have* two de-facto ones — the `/relay` executor contract and `git-diary-workflow`'s SKILL.md. Labeling them "SOP" is a one-line CLAUDE.md pointer, near-zero cost, and it makes the de-facto explicit. Do that. **UML:** one live case, `id:a17a` (the relay state diagram). One instance is not a convention. Defer; it lives or dies as that item.

⚙️ **Sage:** Second Petra on SOPs, and name the trap: do **not** create an `SOP/` tree. In a skills repo the SOP *is* the SKILL.md / contract file, co-located with the code it governs — that co-location is strictly better than a separate directory a reader has to cross-reference. The whole win here is "one place to look." A parallel `SOP/` or `adr/` directory reintroduces exactly the sync-two-records cost we're trying to avoid. So: a one-line "these files are our SOPs" pointer in CLAUDE.md, and nothing structural.

🏗️ **Archie:** So Topic B collapses to three verdicts: ADR → a `superseded-by:`/`status:` typed edge extending id:46f6, gated on id:ee62; SOP → a one-line CLAUDE.md label of the two existing de-facto SOPs, no directory; UML → no adoption, id:a17a stays the sole case. All three dissolve into machinery we already run rather than adding a parallel record.

## Decisions
- **D-A (id:8ef3):** No repo-wide semver/manifest/`VERSION` file/`vX.Y.Z` tags. **Git is the repo-version SSOT.** Adopt a per-contract-surface `vN` marker convention (generalize executor-contract v6) with co-located bump discipline; enumerate the surfaces. Make the manifest-less exemption from the global Versioning rule explicit in CLAUDE.md. CHANGELOG deferred (trigger: first external consumer needing a reproducible pin). *Out of scope:* `VERSION` file, semver tags, per-skill versions.
- **D-B (id:a6e1):** Dissolve per-artifact, don't add parallel records. **ADR** → reject ADR-as-file (N=2 fails); adopt a `superseded-by:`/`status:` typed ledger edge extending id:46f6, letting id:2840/id:dc60 derive the status view; GATED on id:ee62; acceptance = the derived view surfaces a silent-supersession case (id:65f9-style). **SOP** → one-line CLAUDE.md pointer naming the two de-facto SOPs (executor-contract, git-diary-workflow SKILL.md); no directory. **UML** → no general adoption *now*; deferred into id:a17a as the venue to explore broader diagram application (not a permanent no). *Out of scope:* `adr/`/`SOP/` directories, immutable per-decision files, hand-maintained status fields.

## Action items
- [x] Add a **Versioning** subsection to `CLAUDE.md` (manifest-less by design; git = repo SSOT; global rule exemption; contract-surface `vN` marker table + bump discipline). Done this session; closes id:8ef3. <!-- id:8ef3 -->
- [x] Add a **SOP** pointer to `CLAUDE.md` Conventions naming the two de-facto SOPs; no directory. Done this session; SOP limb of id:a6e1. <!-- id:a6e1 -->
- [ ] `superseded-by:`/`status:` typed ledger edge extending id:46f6; **GATED on id:ee62** (visible-annotation syntax). Acceptance: the derived view (id:2840/dc60) surfaces a silent-supersession case, id:65f9-style. File: extends the typed-edge convention in `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. <!-- id:2041 -->
- [x] Annotate **id:a17a** as the venue to explore broader UML/diagram application (UML-deferred verdict recorded there). Done in write-back; UML limb of id:a6e1. <!-- id:a17a -->
