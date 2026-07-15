# TDD rigor in the relay — the refactor step + what else from Red-Green-Refactor

**Started:** 2026-07-15 23:48
**Session:** cb877143-e282-440b-bc91-cd5ac20d389d
**Chair:** Zommuter
**Attendees:** Zommuter (chair), 😈 Riku (what's enforceable), 🦀 Kaz (verification tooling), 🎛️ Orla (relay verify-before-merge), ✂️ Petra (scope)
**Mode:** design meeting → same-session implementation (apex/Opus)

## Context

The relay does Red→Green (handoff writes the failing test = spec; executor makes it pass) but the chair "doesn't see any refactoring." The executor contract rule 2 *requires* "a refactor pass is done" — but nothing verifies it, and the RELAY_LOG self-report has no refactor field. Decide how to make refactor real, and what else from strict TDD to enforce vs leave advisory.

## Key finding

**Refactoring cannot be verified mechanically** (Kaz): it is behaviour-preserving, so tests stay green whether you refactored or not — no diff signature distinguishes "refactored" from "didn't need to." An unverified contract clause that *reads* as enforced rots (Riku) — like a `#[cfg(kani)]` harness nobody runs, it fails silently. **But** the *negative* signal — "did you leave obvious duplication?" — IS mechanically detectable, and a *dedicated* refactor pass (not inline) IS verifiable via "suite green before+after, no test changes."

## Decisions (D1–D4, ratified)

- **D1 — Refactor becomes a loud claim.** Executor RELAY_LOG self-report MUST carry a `refactor:` line — what was cleaned up, or `none needed — <reason>`; blank/absent is a violation (like an empty `# swallow-ok:`). Forcing function, not a proof. No mechanical *proof* gate. Executor contract rule 2/4, bumped **v8→v9**. <!-- id:108e -->
- **D2 — Reviewer cross-checks it.** `review.md` §2b check 6: flag `refactor: none needed` ONLY when the committed diff visibly contradicts it (dead code, duplication, leftover RED-spec scaffolding). Judgment-only. <!-- id:108e -->
- **D3 — Triangulation stays a handoff property.** One `handoff.md` sentence (C3): write RED specs with enough distinct cases that special-casing is harder than implementing — the proactive complement to §2b's fixture-special-casing check. <!-- id:108e -->
- **D4 — Small steps / commit discipline unchanged.** Rule 5 ("commit early and often") suffices; a "did you take small steps" self-report is a rubber-stamp trap.

## Forward-flags (filed, not built)

- **Duplication/similarity linter (id:2c94)** — chair forward-flag: mechanize D2's cruft-check with existing libs (`jscpd`, pylint duplicate-code, token-similarity). It can't prove refactoring happened, but "did you leave duplication?" IS detectable — a deterministic backstop to the reviewer's eyeball.
- **`/relay refactor` apex mode (id:22da)** — chair proposal: a dedicated, opt-in, apex-tier mode that searches for and applies cross-cutting refactors under the **verifiable** invariant (full suite green before+after, zero test-file changes) — the mechanically-honest home for refactoring the inline executor pass can't verify. Consumes id:2c94's hotspots as its target list. Deserves a short design pass first: propose-vs-apply, scope-bounding, behaviour-preservation limits (under-specified suites), overlap with the executor's local inline refactor.

## Action items

- Executor `refactor:` self-report line + review §2b cross-check + handoff triangulation sentence + contract v9. <!-- id:108e -->
- Duplication/similarity-linter mechanization of the cruft-check (existing libs). <!-- id:2c94 -->
- Design + build `/relay refactor` apex mode (verifiable refactor pass; 4 pinned design points). <!-- id:22da -->

## Related

`relay/references/executor-contract.md` (rule 2/4, v9), `relay/references/review.md` §2b, `relay/references/handoff.md` C3, id:373e (clean-worktree exit gate, prior meeting), id:fbbf (contract-bump no longer triggers review churn — makes the v9 bump cheap).
