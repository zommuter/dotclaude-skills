# 2026-06-13 — Handoff REVIEW_ME wave: test-posture, unrunnable tests, triage

**Started:** 2026-06-13 17:51
**Session:** a7cf5f60-746e-4d25-b34f-e0e672c4aa35
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), ⚙️ Sage (skill-runtime)
**Topic:** Triage ~27 open REVIEW_ME judgment calls from the 2026-06-13 Opus-standin handoffs; settle the recurring relay-contract patterns, route the rest.

## Surfaced
- 📥 Inbox routed here (read-only, not this topic): broker.py event-history ring (from meeting-rpg, `routed:1f5e`).
- Orphan scan: clean (forward). Reverse-orphan ADVISORY: several in-session completions never mirrored (expected).

## Agenda
1. Test posture — may handoff C3 ship *green* tests (regression-guards) when the feature is already built?
2. "Red by construction" — how to handle tests the relay host cannot run (no Android SDK / no game-ROM fixture)?
3. Triage the remaining ~21 per-repo items — batch the safe confirms, fix the unsafe one, route the genuinely-HARD design items.

## Discussion

**Item 1.** 🏗️ Archie: the relay is now handing off *already-built* repos (rawrora GyroHelper, claude-organizer scripts, recurheb update); C3's "red = spec" breaks because a faithful test is green on arrival. 😈 Riku: the hazard is *what a green guard pins* — rawrora's axis-swap/sign tests freeze behavior the reviewer itself flagged as possibly-buggy; a green guard launders a bug into "tested behavior" unless flagged. ✂️ Petra: no new item class (N=2 fails); `[ROUTINE]`/`[HARD]` + a REVIEW_ME flag suffice. 🎛️ Orla: split the absolute rule into red-spec (unbuilt) vs labeled-green-guard (extant); verification-before-merge still audits guards. ⚙️ Sage: one-paragraph handoff.md C3 edit.

**Item 2.** 🏗️ Archie: zomni has no Android SDK/Gradle (droidclaw, rawrora) and no retail ROM (romtrans id:663a); children asserted redness "by construction" (uncompilable) — a promissory note, not verification. 😈 Riku: the nastier trap is the ROM-gated test that *skips* → suite reads green while the fix is unverified; a skip is not a pass. 🎛️ Orla: relay's host-capability boundary — mark unverified + push the real build/verify to where the env exists (Docker fievel / Termux pixel / ROM on disk); else HANDBACK like ai-codebench GPU items. ✂️ Petra: out of scope to give zomni every SDK + a licensed ROM — fix is honesty in the artifact.

**Item 3.** ✂️ Petra: most remaining items are "confirm the current reading" (zomAI CORS-wildcard for a LAN box, recurheb's 5 README readings, collaib OR-threshold/whitespace-trim, opus-4-8 default) — batchable. 😈 Riku: romtrans `_rebuild_bytes` proportional splice can cut German mid-word and *silently corrupt* multi-segment messages — a latent data-corruption bug, not a preference; safe default is skip/over_budget until a per-segment design. rawrora axis/sign are A1 frozen-bug guards — behavior confirmation is the user's, on-device. 🏗️ Archie: the `[HARD]` items (zomAI→zelegator subtree, droidclaw `:gateway` delete, llama-server proxy, collaib 948d/aaaf, zomAI bcb8 adapter) each hide a real fork the executor was right not to guess — route to dedicated design, don't rubber-stamp. 🎛️ Orla: model-default confirms are claude-api facts, fold into the batch.

## Decisions

- **D1 (handoff contract).** C3 may ship a GREEN **regression-guard** for already-built behavior instead of a red spec — never delete working code to manufacture a red. The guard MUST be marked in the test header and MUST carry a REVIEW_ME "is this correct or are we freezing a bug?" entry. An *unflagged* green guard is not acceptable. handoff.md C3 updated. **Out of scope:** a new "verify" item class (rejected per N=2).
- **D2 (handoff contract).** A test the relay host cannot run (missing toolchain/fixture) is marked `# unverified — run in <env>`, recorded in RELAY_LOG + REVIEW_ME, and is NOT counted as a verified red spec; the item's done-check MUST execute it in the real env, and a skipped/uncompiled test is NOT a pass. No env at executor either → HANDBACK (hardware/fixture-gated). handoff.md C3 updated. **Out of scope:** installing every SDK/fixture on zomni; the licensed game-ROM in particular.
- **D3 (triage).** Batch-accept the current interpretations: zomAI CORS-wildcard / streaming-seam / audio-layout / `claude-opus-4-8` default; recurheb's 5 README readings (a24f fixed-ref, e22b concat-order, 59de two-tick, 8482 scalar-p, d95b unbounded baseline); collaib OR-threshold (f103) + whitespace-trim (7ad5); romtrans order-strict (id:21d8, executor may relax to multiset if it rejects good translations) + a new `ctrl_mismatch` status (over the semantically-wrong `over_budget`); claude-organizer cleanup_candidates removal (c259) + argparse robustness fix (9d11). **Out of scope per-item discussion** — these stand as confirmed.
- **D4 (safety override).** romtrans `_rebuild_bytes` must NOT guess-splice multi-segment German by source proportion — for M1, mark multi-segment messages `over_budget`/skip rather than silently corrupt; a per-segment translator return is a later design. (Overrides the child's "accept for M1" lean.)
- **D5 (routing).** The genuinely-`[HARD]` specced items stay `[HARD]` and need their own design before any executor touches them (executors must not guess the fork): claude-organizer id:32fc (zomAI→zelegator: preserve 2 commits via git-subtree vs reference-and-archive — Gil's plumbing call), droidclaw id:dd73 (`:gateway` delete vs keep-as-OC-Protocol-v3-reference), droidclaw `llama-server` proxy direction, collaib id:948d/aaaf (multi-region tracking, structured-JSON observations), zomAI id:bcb8 (Anthropic adapter shape — model default `claude-opus-4-8` is confirmed; only the adapter-vs-parallel-path shape is open). Already tracked as `[HARD]` in-repo; no new dispatch.
- **rawrora axis-swap (4ad2) + sign-convention (98a0)** stand as D1 regression-guards; the *behavior* correctness (device sensor↔display orientation, offset sign) is the user's to confirm on-device at leisure — flagged, not silently blessed.

## Action items
- [x] handoff.md C3: regression-guard posture (D1) — **done in-session** (this commit). Closed-state confirmed 2026-06-21 (orphan-scan cleanup, mechanization-audit session). <!-- id:9297 -->
- [x] handoff.md C3: env-gated `unverified` posture (D2) — **done in-session** (this commit). Closed-state confirmed 2026-06-21 (orphan-scan cleanup, mechanization-audit session). <!-- id:e986 -->
- [ ] Apply the D3 batch-accept REVIEW_ME confirmations + D5 stays-HARD notes across romtrans, claude-organizer, collaib, rawrora, zomAI, recurheb (tick boxes + decision note per this meeting); also mirror D1/D2 into `references/review.md` so the test-integrity audit treats green-guards and unverified-env tests correctly. <!-- id:3114 -->
- [ ] romtrans `_rebuild_bytes`: skip/over_budget multi-segment messages instead of proportional guess-splice (D4); add a roadmap id in-repo. → routed to romtrans inbox <!-- routed:6da4 -->
