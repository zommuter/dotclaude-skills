# 2026-06-01 — user-profile.md context strategy

**Started:** 2026-06-01 15:58
**Session:** 107a71bd-5196-456c-adc7-1d1a660bb506
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔧 Quinn (inference-server internals — re-onboarded for embedding-server cost angle)
**Topic:** `user-profile.md` hit 656 lines (≥600 trigger from 2026-05-14 skill-ctx-bloat audit). Design a context strategy. Tobias's addendum: consider zkm overlap.

## Surfaced discoveries
- [2026-05-14 dotclaude-skills] Skill ctx-bloat three-class taxonomy: α=setup-load (user-profile.md dominant at 390 lines then), β=audit-pass waste, γ=consumer-file growth — this meeting is the deferred α-class fix. See `2026-05-14-1015-skill-ctx-bloat-audit.md`.
- [2026-05-14 dotclaude-skills] Sibling-helper script pattern: bash script reads N lines internally, returns short stdout; P2-symlinked + allowlisted via Makefile/allowlist.py.
- [2026-05-08 zkm] BGE-M3 is the strongest local bilingual DE+EN embedder for hybrid retrieval.

## Agenda
1. Is 656 lines a real problem, and what is the cheapest safe cut?
2. zkm overlap — can/should we reuse zkm for retrieval, and is there a shared abstraction with discoveries.md RAG?
3. Mechanism + sequencing: static split vs topic-filter vs RAG; what ships now vs is gated.

## Discussion

### Agenda 1 — Is 656 lines a real problem, and what's the cheapest safe cut?

**🏗️ Archie:** SKILL.md:20 reads the whole file unconditionally at setup step 6, every invocation — zero filtering today. The file is a *local* install-path file (Makefile `meeting_LOCAL`), not a repo artifact. Growth steep: 390 lines / 27 traits on 2026-05-14 → 656 / 53 now. The cleanest cut axis falls out of usage: the only in-meeting consumption is persona pre-emption, gated on `eligible + med/high confidence + contradiction`. By that rule, 24 of 53 entries (the ineligible ones) can *never* fire during a meeting — inert at read time. That's a ~45% static cut with no semantic machinery.

**✂️ Petra:** That's the 80-20 and I'd stop there for now. The trigger is a heuristic, not measured pain. The audit *explicitly deferred* α as "hardest, needs RAG or topic filtering." Warranted move today: archive the inert entries to a sidecar that setup does NOT read, then re-measure. Out of scope: anything that adds a running-server dependency to a file read.

**😈 Riku:** Two objections. First — what breaks if we cut wrong? Pre-emption depends on full presence; entries are interlinked. The safe archive axis isn't "ineligible" — it's the intersection provably inert under the rule: **ineligible OR (eligible AND low-confidence)**, because rule (b) kills low-confidence eligible entries by definition. Second — has anyone measured setup-ctx as a fraction of total meeting tokens? If it's 5%, this is polishing a non-problem. Pre-empting per [[empirical-pilot-preference]]: measure before committing to anything structural.

**⚙️ Sage:** Topic-filtering is ruled out for the *first* move. In no-arg mode — how this meeting was dispatched — setup step 6 runs *before* the topic is known (classification happens after). A topic-filter at step 6 has nothing to filter against without re-architecting setup ordering. The confidence/eligibility split is *static and topic-free* — works at setup with no reordering. That asymmetry sequences static-split first.

**😈 Riku:** Agreed — the static split is the only one of the three that's both safe-by-rule and topic-free.

**🏗️ Archie:** One wrinkle: the end-of-meeting step *writes* to the profile and can promote a low-confidence entry as evidence accumulates. The archive can't be write-only-forgotten — promotion must pull an entry back. "Archive" = lazy-load split, not delete.

**[Zommuter]:** Measure, then static split.

### Agenda 2 — zkm overlap: reuse, and a shared abstraction with discoveries.md?

**🏗️ Archie:** Tobias asked us to weigh zkm. Two-layered verdict. The **zkm CLI/store is the wrong tool** here: store-scoped (no entrypoint to index a lone external file — it'd have to live inside `$ZKM_STORE` and trigger a whole-store `zkm index`), chunks by 2000-char windows not per-entry (`_chunk_texts`, embed.py:452), and `_dense_search` aggregates to max-score-*per-file* (query.py:289) — with one file in the store, every query returns that same file, never its top sections. Section granularity would mean exploding 53 entries into 53 files — absurd for a profile. But the **`zkm.embed` library is the right leverage** if retrieval is ever warranted: `embed_texts()` + `EmbedStore.topk()` hit the same BGE-M3 `/v1/embeddings` endpoint, no store required. And the `RAG-for-discoveries` TODO names *the same* primitive — profile-retrieval and discoveries-retrieval are **N=2 consumers of one capability**.

**✂️ Petra:** N=2 is real and justified *in principle*. But neither consumer has a fired pain trigger: discoveries RAG gates at ≥100 entries/≥800 lines (not reached), and profile's first move is a static split. The shared helper is a **design we name now and build when a trigger fires** — not this session.

**🔧 Quinn:** The cost asymmetry kills RAG-now. The full-read is zero-dependency and synchronous. Dense retrieval needs BGE-M3 *up*; cold, first query is ~180s (zkm's own `_EXPAND_COLD_TIMEOUT_DEFAULT`; doctor.py warns same). No zkm daemon — every call re-imports numpy + reloads `.npz` cold. You'd trade a deterministic ~650-line read for a variable, server-dependent, occasionally-180s round-trip to save a few hundred lines. Break-even is volume — retrieval wins only once full-read is genuinely large, which is exactly what discoveries' ≥800-line gate encodes.

**😈 Riku:** Honest framing: zkm-the-product gives nothing here; zkm-the-embedding-endpoint is a shared backend we'd reuse *if* we build retrieval. Spec the helper as shared, build only when one of profile/discoveries trips its volume trigger AND measured ctx fraction is material. Neither holds today.

**⚙️ Sage:** One runtime note on *where the dependency lives*. If the helper imports `zkm.query`/`zkm.embed`, the meeting skill gains a hard dependency on zkm in a reachable venv — and zkm's own note says `zkm convert ner` already fails cross-venv (py3.14 vs py3.12 numpy). A *publishable* skill can't hard-depend on a personal corpus tool. Contract: depend only on the **`/v1/embeddings` HTTP endpoint** (a config'd URL), not the zkm package. zkm and the helper become two clients of the same server.

**🏗️ Archie:** Reuse the *endpoint*, not the *package*. Helper becomes ~40 lines (chunk by `## ` heading → POST each to `/v1/embeddings` → cosine top-K → emit blocks to stdout), matching the sibling-helper pattern exactly, with the embed URL as the only new config.

**[Zommuter]:** Spec shared, build on trigger.

### Agenda 3 — Concrete mechanism: physical split vs helper-filter on one file

**🏗️ Archie:** A *physical* two-file split is the wrong shape — [[drift-aversion]]: `user-profile.md` + `user-profile.archive.md` creates a second home that invites a trait to drift into both across the promotion path. Better: keep **one file as source of truth**, change only *how setup reads it* — a sibling helper `profile-active.sh` emitting only active blocks (`eligible: yes` AND `confidence: med|high`). Step 6 calls the helper; the end-of-meeting writer still sees the full file. No second file, no coherence problem, no writer change.

**⚙️ Sage:** Strictly the sibling-helper pattern — read big, emit small stdout, P2-symlink + Makefile `_FILES/_EXEC/_ALLOW` + `make install-allowlist`. Deterministic, topic-free, sidesteps the no-arg-mode ordering problem.

**😈 Riku:** Helper-over-split agreed. But the rollout must satisfy Agenda-1's measure-first ask. Just flipping step 6 changes behaviour before knowing the cut is material. Ship the helper in **log-only mode first** — emits the *full* file (behaviour unchanged), logs `(full_lines, active_lines, ratio)` each run. After N meetings, `cost-of.sh` gives ctx fraction. *Then* flip to filtering once numbers justify it. Cheap, decisive, reversible.

**✂️ Petra:** Fine — keeps this session's build tiny: one script defaulting to passthrough+log, no SKILL.md behaviour change until gate clears. Nail down the **flip gate** so it's not an open-ended defer: flip when active/full ≤ 0.60 over ≥5 meetings AND setup-ctx is material (per `cost-of.sh`).

**🔧 Quinn:** Log-only has zero server dependency — right default. The flip stays zero-dependency too (rule-based awk, no `/v1/embeddings`). Clean separation.

**[Zommuter]:** Helper + log-only first.

## Decisions
- **A1 — Measure-then-cut:** Only in-meeting use of profile is persona pre-emption (`eligible + med/high confidence + contradiction`); ~24 of 53 entries are inert by that rule. Measure the real ratio first; then cut. *Out of scope:* deleting any entry; trimming by hand; physical archive file.
- **A2 — zkm reuse, endpoint-only, trigger-gated:** zkm CLI/store rejected (store-scoped, 2000-char chunking, file-granularity results, ~180s cold-load). Only reusable surface: BGE-M3 `/v1/embeddings` HTTP endpoint. Shared "retrieve-top-K-entries-by-topic" helper specced for N=2 (user-profile.md + discoveries.md) — built only when one crosses its volume trigger AND measured ctx fraction is material. Helper depends on the endpoint URL, never `import zkm` (publishability; [[meta-skill-isolation]] coupling direction). *Out of scope:* importing the zkm package; placing the profile in a zkm store; building the helper this session.
- **A3 — Helper on single file, log-only first:** `profile-active.sh` emits active blocks (`Pre-emption-eligible: yes` AND `Confidence: med|high`); single source of truth, no physical archive ([[drift-aversion]]). Ships passthrough+log now (zero behaviour change, zero server dep); SKILL.md step 6 calls it; step 6 flips to real filtering only after a named gate clears over ≥5 meetings. *Out of scope:* a second/archive file; embedding-based or topic-relevance filtering now.

## Action items
- [x] Build `meeting/profile-active.sh` — passthrough+log default; `--filter`/`PROFILE_ACTIVE_FILTER=1` emits active-only. Shipped 2026-06-01. Baseline: full=656, active=168, ratio=0.26. [meeting/profile-active.sh]
- [x] Wire into Makefile + `make install-meeting install-allowlist` — 8 allowlist forms merged. [Makefile]
- [x] Update SKILL.md step 6 to call `profile-active.sh` instead of raw read. Behaviourally identical while in passthrough mode. [meeting/SKILL.md]
- [ ] **profile-active.sh flip gate** — flip step 6 to `--filter` when: (a) logged ratio ≤ 0.60 over ≥5 meetings AND (b) setup-ctx is a material fraction of meeting tokens per `cost-of.sh`. Current baseline: ratio=0.26. See TODO.md. <!-- id:f8f1 -->
- [ ] **Shared skill-file retrieval helper** — endpoint-only, N=2 (profile + discoveries), built on first volume trigger. Design: chunk by `## ` heading → POST to `/v1/embeddings` → cosine top-K → emit blocks to stdout. Supersedes `RAG-for-discoveries` TODO. See TODO.md. <!-- id:040c -->
