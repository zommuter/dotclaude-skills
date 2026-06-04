# 2026-06-03 — meeting-live → canonical backmerge

**Started:** 2026-06-03 15:29
**Session:** 8520676a-bfab-4256-8681-76eadd8dda21
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing for this project)
**Topic:** Fold the `meeting-live` WIP sibling back into canonical `/meeting`, decide merge shape and sequencing.

## Surfaced discoveries
- [2026-05-20 dotclaude-skills] WIP sibling skill as time-boxed verification scaffold: copy SKILL.md, symlink unchanged spec files, fold back after ≥1 successful pilot + delete the sibling.
- [2026-06-03 dotclaude-skills] /meeting end-of-meeting writes execute while still in plan mode — ExitPlanMode should come first (ordering caveat for whatever we land).
- [2026-05-20 dotclaude-skills] VN-terminal/renderer is NOT a ctx-isolation mechanism; only emitting fewer bytes via the broker side-channel reduces ctx budget.

## Agenda
1. Two gates got conflated — which governs the backmerge?
2. Merge shape: full inline collapse vs lazy broker spec.
3. Sequencing and the savings gate's fate after merge.

## Discussion

### Agenda 1 — which gate governs the backmerge?

🏗️ **Archie:** Two distinct questions wear one hat. (A) "Should `meeting-live` stop being a separate WIP sibling?" — governed by the WIP-scaffold pattern, condition ≥1 pilot, **met** (session 8667f44a, 2026-06-01). (B) "Is broker mode worth defaulting on?" — governed by the 3-pilot ≥5k savings gate. We've been treating (B) as the merge gate. It isn't. You can merge the *code* without declaring it the *default*.

😈 **Riku:** That's a convenient reframing. Merge before savings are proven and we've shipped 40 lines of broker spec into every meeting — headless or not. Minimum evidence to flip me: the merged broker branch is genuinely dormant — zero behavioural, near-zero ctx cost — when no renderer is attached.

⚙️ **Sage:** Riku's dormant test is satisfiable. The broker branch is gated on `$MEETING_LIVE` + a `subscribers` poll; with no renderer, `subscribers=0`, path provably identical to canonical. Behavioural risk: zero. Ctx cost from spec text: real but separable from the savings question.

✂️ **Petra:** The drift tax is nobody's pricing. Every canonical improvement now gets hand-applied twice. That tax is paid *now*, every session. Decoupling (A) from (B) stops the bleed immediately.

### Agenda 2 — merge shape

🏗️ **Archie:** Shape A — full inline collapse (one 118-line file). Shape B — lazy broker spec: canonical stays ~78 lines + a 3-line probe/pointer; broker delta moves to `meeting/broker-mode.md`, loaded only when live.

⚙️ **Sage:** Shape B is drift-proof by construction. `broker-mode.md` contains *only* the broker delta — never restates setup steps 1–6. It physically cannot fall behind on a setup-step change. Shape A removes drift via one file; Shape B removes drift by making the broker spec orthogonal to the flow — the stronger guarantee.

😈 **Riku:** Two files = two things that can desync. And you've added a probe to the hot path of every headless meeting.

⚙️ **Sage:** The probe is one bash call meeting-live already runs today — relocated cost, not new. The pointer's only job is "is a renderer present?" — a runtime check, not restated semantics. Nothing to desync.

✂️ **Petra:** Headless meetings (the majority) never pay the broker ctx tax + drift-proofing. Take B. One insistence: `broker-mode.md` must be P2-symlinked + in the allowlist generator, or we've reintroduced a publishability gap.

### Agenda 3 — sequencing, sibling deletion, savings gate

🏗️ **Archie:** One session. broker-mode.md + pointer + symlink/allowlist + delete sibling. Sibling is committed — deletion is `git revert`-able.

😈 **Riku:** Accepted on condition: broker-curl round-trip (status/question/await) is actually *run and recorded* in this meeting note as a pre-deletion gate. If it fails, deletion waits.

✂️ **Petra:** Same-session is fine. Keeping the parallel skill alive "as fallback" *is* the drift tax we just voted to kill.

🏗️ **Archie:** Savings gate survives, re-scoped: meeting-rpg id:58e3 (2 pilots left) now measures unified `/meeting` with `MEETING_LIVE=1` and decides only whether broker becomes the *default*. Canonical id:7b4c rewritten accordingly.

⚙️ **Sage:** ExitPlanMode-ordering fix is a separate follow-up, don't bundle with this merge.

## Pre-deletion gate: broker-curl round-trip

**PASS** (session 8520676a, 2026-06-03):
- `status` → `{"subscribers": 0}` ✓
- `question` → `{}` ✓
- `await` (after manual `/response "A"`) → `{"id": null, "answer": "A"}` ✓

## Decisions
1. **WIP-fold-back condition governs (≥1 pilot — met).** Merge now to stop the drift tax. Out of scope: deciding broker mode is the default — stays with the re-scoped savings gate.
2. **Shape B — lazy broker spec.** Canonical gets a ~3-line step-7 probe/pointer; broker delta moves to `meeting/broker-mode.md`, P2-symlinked + in allowlist generator, loaded only when live. Option 3 (γ-ref inline) noted for later — deferred. Corollary: the 5 drift features need zero carry-over (canonical already has them; broker-mode.md never restates setup steps).
3. **One-session merge, round-trip-gated deletion.** broker-mode.md + canonical pointer + symlink/allowlist + `make install` + broker-curl round-trip (recorded as pre-deletion gate) + delete `meeting-live/`. Renderer-button live verification covered by next savings pilot + git rollback. ExitPlanMode-ordering fix is a separate follow-up.
4. **Savings gate survives, re-scoped.** meeting-rpg id:58e3 + canonical id:7b4c rewritten: "measure unified skill with MEETING_LIVE=1, 2 remaining pilots, decide default-on."

## Action items
- [ ] Create `meeting/broker-mode.md` — broker delta only (step-7 connect/self-start, per-item event streaming, decision-point γ-branch, γ-branch reference). Contract: never restates setup steps 1–6. [session 8520676a]
- [ ] Add step-7 probe/pointer to canonical `meeting/SKILL.md`. Contract: headless meeting never reads broker-mode.md. [session 8520676a]
- [ ] Add `broker-mode.md` to `meeting_FILES` + allowlist generator; run `make install`. Contract: `~/.claude/skills/meeting/broker-mode.md` is a symlink. [session 8520676a]
- [x] Run broker-curl round-trip (status/question/await); record PASS/FAIL above. Contract: deletion proceeds only on PASS. [session 8520676a] DONE 2026-06-03: PASS recorded above (session 8520676a). <!-- id:54ba -->
- [ ] Delete `meeting-live/` (merge local discoveries.md first). Contract: `/meeting-live` no longer registered; git history retains for rollback. [session 8520676a]
- [ ] Rewrite canonical id:7b4c + meeting-rpg id:58e3 to re-scoped savings gate. [session 8520676a]
- [ ] ExitPlanMode-before-end-of-meeting-writes ordering fix in `meeting/SKILL.md`. See `~/src/meeting-rpg/docs/meeting-notes/2026-06-03-1502-r4-end-of-meeting-prompts-renderer.md`. <!-- id:c762 -->
