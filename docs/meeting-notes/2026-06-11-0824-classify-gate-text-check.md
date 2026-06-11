# 2026-06-11 — classify.sh gate-text check

**Started:** 2026-06-11 08:24
**Session:** 70c09e8c-fddb-4291-99cf-84c4bf9d81d3
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime lens) (new)
**Topic:** Add an advisory gate-presence flag to classify.sh so condition-gated TODO items are visually distinct from genuinely impl-ready C1 items.

## Surfaced discoveries
- [2026-05-14 dotclaude-skills] Class 1 sweep found 4/5 impl-ready items already done but not closed — model judgment alone misses closure/gate state; verify live state before treating C1 as actionable.
- [2026-05-15 dotclaude-skills] A gate duplicated in SKILL.md prose + its called script is unreliable under the ~77%-bypass population; single-source the gate in the deterministic script layer.

## Agenda
1. Warrant: build a gate-text check now, or defer (observe-first)?
2. Signal shape: orthogonal warning column vs. overloading the CLASS token (`C1-GATED`)?
3. Detection: which trigger phrases, and how to handle cleared-gate false positives?

## Discussion

### Item 1 — Warrant

🏗️ **Archie:** `classify.sh:37-42` scores any unchecked item with a meeting-note link + `## Decisions` heading as C1, unconditionally. The C2 keyword hint (line 45) only fires in the no-link branch. Gate language in the body is invisible to the script.

😈 **Riku:** Zero mis-dispatches on record. CLAUDE.md says "Observe before preventing." Minimum evidence to change my position: one logged instance where model dispatched a gated item without catching the gate.

✂️ **Petra:** N=2 satisfied: (1) canonical `/meeting` no-arg step 2/3 runs model-judgment gate filter by hand; (2) `/meeting-cross` step 3 does the identical hand-filtering. Two consumers re-deriving the same signal manually every run — exactly the duplication the 2026-05-15 discovery warns about.

⚙️ **Sage:** Script detects gate *presence* (deterministic grep), never *satisfaction* (model read). Same shape as orphan-scan's ADVISORY: flag says "check this," model still decides. Cost-of-being-wrong near-zero.

😈 **Riku:** That reframe matters. An advisory flag that never changes CLASS collapses the downside. The profile's "implement now when cost-of-being-wrong is asymmetrically low" exception fits here. I concede.

**→ User picked:** Build advisory flag.

### Item 2 — Signal shape

🏗️ **Archie:** Option A: tail-appended 5th TSV column, empty or `GATED`. CLASS unchanged. Option B: `C1-GATED` class token.

⚙️ **Sage:** Gatedness is a second axis, orthogonal to warrant. `C1-GATED` conflates axes, breaks the `C1 > C2 > C3` priority sort in meeting-cross step 5. Column wins.

✂️ **Petra:** Both consumers read TSV as model context, not rigid positional parsing — appending a column can't break them. Column wins on blast radius.

😈 **Riku:** Visibility concern for the column withdrawn — bucket-summary prose renders the flag explicitly; presentation is the model's job.

### Item 3 — Detection precision

🏗️ **Archie:** Live TODO vocabulary: `build-gated`, `condition-triggered`, `Reopen trigger`, `Reopen gate`, `Sole gate`, `gated on`, `blocked on`. Pattern: `gated?|gate:|reopen (gate|trigger)|condition-triggered|blocked on`, case-insensitive.

😈 **Riku:** False-positive trap: `AI-5 savings gate — confirmed` and `flip gate — cleared` contain gate vocabulary but are cleared. A naive grep flags them. If it drove skipping, those items would be buried.

⚙️ **Sage:** It doesn't drive skipping. `GATED` = "body has gate language; model, read the condition." On a cleared gate the model reads "confirmed"/"cleared" and proceeds. The flag was correct to fire. FP cost: one glance.

✂️ **Petra:** Do NOT detect cleared-vs-open in bash — that reimports the model's job. Dumb grep for presence only.

😈 **Riku:** `[x]` items already excluded at line 17. FP surface is only open items mentioning a now-satisfied gate — small set. Satisfied.

## Decisions
- **Build the gate-text check as an advisory flag only.** classify.sh detects gate *presence*; the model retains the *satisfaction* judgment. The script never skips or reclassifies a gated item. Out of scope: any path where the script demotes a class or removes an item from the bucket.
- **Signal shape: tail-appended 5th TSV column** (`CLASS \t ID \t SUMMARY \t NOTE-LINK \t GATE`), value empty or `GATED`. CLASS token (C1/C2/C3) unchanged. Out of scope: `C1-GATED`-style class overloading; per-axis token products.
- **Detection: single case-insensitive `grep -qiE`** for `gated?|gate:|reopen (gate|trigger)|condition-triggered|blocked on` against the ID-stripped `$body`, independent of the link/keyword classification branch. Out of scope: distinguishing cleared from open gates in bash, severity, reason-capture.
- **Contract + consumers updated.** classify.sh header comment documents the 5th field; `/meeting` no-arg step 3 and `/meeting-cross` step 4 each instruct rendering the `GATED` flag in per-item one-liners.

## Action items
- [x] Add `GATE` column to `classify.sh`: `grep -qiE` gate-vocab against ID-stripped `$body`, emit empty or `GATED` as 5th printf field. Update header-comment contract. Contract: id:ab70 and id:cbb5 flag `GATED`; ungated items have empty 5th field; columns 1-4 byte-identical to before. File: `meeting/classify.sh`. <!-- id:aff9 -->
- [x] Add one-line render instruction to bucket-summary step of both consumers. Contract: `/meeting` no-arg step 3 and `/meeting-cross` step 4 each mention rendering the GATE flag. Files: `meeting/SKILL.md`, `meeting-cross/SKILL.md`. <!-- id:389d -->
