# 2026-07-06 — Machine-tag format endgame (d259 spike)

**Started:** 2026-07-06 09:59
**Session:** 21fcfc8f-4a0f-4794-aa46-2d66ec8bd70e
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate — blast radius/touch-once), ✂️ Petra (productivity/YAGNI), 🎛️ Orla (mechanized-consumer lens), ⚙️ Sage (format & parsing lens)
**Topic:** Ratify the endgame tag format for relay lane tags — (A) harden brackets + tag-first-among-trailing lint / (B) todo.txt-style `@sigil`/`key:value` / (C) tag-truly-first bracketed position — with blast-radius, rendering, and 7df1-fold analysis. Resolves d259 (spawned by `2026-07-03-0830-todo-lane-tag-format-prior-art.md`).

## Prior state (verified this session)
- **(A)'s parser-hardening floor already SHIPPED** (id:0d58): `[MECHANICAL]` anchored into the sole whitespace-delimited lane reader; suite green. The tag-first WARN *floor* (id:ad8a) also shipped 2026-07-03 (report-only split-brain detector: flags when the raw-first-tag scan and the backtick-stripped scan diverge).
- **7df1 (B2c-finalizer) already carried a TENTATIVE fold-in note** ("FOLD-IN (d259 decision, A→C): extend lane-convert.sh to reorder `- [ ] **title** [TAG]` → `- [ ] [TAG] **title**` in the SAME --in-place pass; delete the 7 anchoring reimplementations"). So d259's job was to RATIFY (confirm C) / overturn (pure-A) / escalate (B).
- New vocab (post-4f02): `[ROUTINE]`, `[HARD]`, `[INPUT — meeting|decision|access]`, `[MECHANICAL]`, `[INTENSIVE — <res>]`.
- 7 anchoring reimplementations exist (classify-repo.sh `min()`, gather-repo-state `roadmap_primary_lane`, gather-human-backlog backtick-strip, unpromoted-scan `primary_lane`+fb7f, classify-verdict.sh, handback-followup.py, roadmap-lint case-c).

## Agenda
1. Endgame choice: (A) pure-harden / (B) `@sigil` / (C) tag-first-position.
2. If C: converter-reorder mechanics + tag-first lint + idempotency risk.
3. Sequencing vs 7df1 — does folding widen the gate?

## Discussion

### Item 1 — endgame choice A/B/C
🏗️ **Archie:** By the time 7df1 runs the vocab is already `[ROUTINE]`/`[HARD]`/`[INPUT — …]`/`[MECHANICAL]`/`[INTENSIVE — …]`. Under **(A)** the tag stays anywhere and we keep the `min()`-over-`LANE_TAGS` anchoring in all 7 readers forever, guarded by a tag-first-among-trailing lint. Under **(C)** the tag becomes the first token after the checkbox and every reader collapses to one fixed-offset regex `^- \[[ x]\] (\[[^\]]+\])`, deleting those 7 reimplementations. **(B)** swaps the sigil to `@routine`/`input:meeting`. Key fact: 7df1's `lane-convert.sh --in-place` is *already* rewriting every lane tag for pool→HARD; adding a reorder (C) to that pass is marginal, adding a sigil grammar (B) is a second grammar.

⚙️ **Sage:** Container migration was already rejected (todo.txt loses GitHub `- [ ]` rendering + the invisible `<!-- id -->`), so B is only "swap `[LANE]`→`@lane`". The wrinkle that kills B's appeal: compound lanes have an em-dash — `[INPUT — meeting]`, `[INTENSIVE — r5-jvm]`. A clean sigil wants `input:meeting`/`intensive:r5-jvm` (`key:value`, no spaces) → B isn't a find-replace, it restructures the compound lanes. C keeps the brackets exactly and just moves them; a fixed-offset `\[[^\]]+\]` swallows `[INPUT — meeting]` whole.

🎛️ **Orla:** From the mechanized-consumer side (id:4d8e, shrink the LLM surface) I want the lane regex-extractable with zero LLM fallback. B gives that lexically (one grammar); C gives it positionally with a *fixed offset* — just as deterministic, no grammar change. I said last time "lexical beats positional, but only marginally over a well-linted positional rule" — C is the *fixed-offset* form, the strongest positional. B's marginal gain over C is nil and costs a grammar rewrite. B's justification doesn't survive.

✂️ **Petra:** YAGNI: the triggering bug was latent-not-live and A already fixes it. If 7df1 weren't happening I'd say pure-A, defer C forever. But 7df1 *is* on the roadmap and *is* rewriting every tag → the reorder is near-free in that window and lets us delete 7 reimplementations (negative maintenance). The line I hold: C is only worth it folded into 7df1; never as its own migration pass.

😈 **Riku:** The trap was never "we built brackets" — it's "we migrate twice because we flinched." Cheapest moment to reposition a tag is while your hands are already on every tag. So **C, folded into 7df1, touch-once.** Risk to name: the reorder is NOT a 1:1 string replace like the rename — `lane-convert.sh` is a dumb text transform, and lifting `[TAG]` to first position idempotently across multi-tag items (`[MECHANICAL] [INTENSIVE — res]`) and prose brackets is real parsing. That's Item 2; it doesn't change the choice.

🏗️ **Archie:** For the record, C also lets the deferred tag-first lint land as enforcement that closes the window — and under C it's tag-first-*absolute* (a fixed offset), strictly simpler than A's tag-first-*among-trailing*.

**→ D1: C.** (User ratified.)

### Item 2 + 3 — reorder mechanics + sequencing
😈 **Riku:** The rename is a safe 1:1 swap; the reorder must find the recognized lane cluster, lift it, re-emit at front, and never touch a prose `[bracket]`. Cram that into `lane-convert.sh`'s sed-ish flow and we get a fragile mega-script that can silently mangle a Why-body. Isolate it: a distinct reorder mode/function with its own RED tests (multi-tag, prose-bracket, already-first no-op). Same `--in-place` invocation → still touch-once, but separately verified.

🏗️ **Archie:** Reorder spec: on a `- [ ]`/`- [x]` line, take the anchored primary lane token + any adjacent orthogonal `[INTENSIVE — …]` (order preserved), move that cluster to immediately after the checkbox, strip from old position, leave body brackets + trailing `<!-- id -->` untouched. Idempotent by construction (already-first = no-op). Surviving reader: `^- \[[ x]\] (\[[^\]]+\])( \[[^\]]+\])?`.

🎛️ **Orla:** The reorder tool + tag-first lint are pure tooling — no dependence on M3 or cross-repo vocab. 7df1's gate is about *when it's safe to run the migration + flip old-vocab→ERROR on this repo*. Building the capability + the lint (WARN) is ungated. Ship the *tool* now, RED-tested; 7df1 shrinks to "run the built tool + flip the lints to ERROR."

✂️ **Petra:** Sign-off, and it keeps scope honest: the *tool* (reorder mode + tag-first lint WARN + tests) is a bounded `[ROUTINE]` build dispatchable now; the *execution* (run on this repo's ledgers, migrate ~30 lane tests, flip lints→ERROR) stays inside gated 7df1. Don't let the tool build drag the window-close forward — the window still can't close while any consumer is old-vocab.

⚙️ **Sage:** Lint has two phases: WARN during the window (a hard tag-first ERROR would false-fire on every not-yet-reordered old-vocab line), flipping to ERROR in the SAME final 7df1 step that flips old-vocab→ERROR. One flip, one window-close. Builds on the ad8a WARN floor (split-brain detector) — the new check is "lane tag is the first token after the checkbox", a distinct rule.

**→ D2: isolated reorder mode, own RED tests. D3: build tool now (ungated), gate execution.** (User ratified both.)

## Decisions
- **D1 — Endgame = (C) tag-truly-first bracketed position, folded into 7df1, touch-once.** `- [ ] [ROUTINE] title <!-- id -->`. Reorder rides `lane-convert.sh`'s existing `--in-place` pass; the 7 anchoring reimplementations are deleted in the reader migration; surviving reader `^- \[[ x]\] (\[[^\]]+\])( \[[^\]]+\])?`. **(B) rejected** (sigil + em-dash-compound restructure for nil gain over C's fixed-offset positional rule). **(A)'s parser-hardening floor already shipped (id:0d58)** as the prerequisite. **Out of scope:** migrating the Markdown container (keeps GitHub `- [ ]` + invisible `<!-- id -->`).
- **D2 — Reorder is an ISOLATED, separately-RED-tested mode**, not bolted onto the 1:1-rename transform. Same `--in-place` invocation. Spec per Archie above; idempotent. Adversarial fixtures: multi-tag, prose-bracket, `[INTENSIVE]`-composed, already-first no-op, and a Why-body line that merely mentions `[HARD — pool]` in backticks (must NOT move — not a checkbox line). **Out of scope:** touching non-checkbox lines.
- **D3 — Build the tool NOW (ungated); gate only execution.** Reorder mode + tag-first lint (WARN, building on ad8a) + RED fixtures = a dispatchable build now (id:4b37). The RUN (lane-convert --in-place on this repo's ledgers + ~30 lane-test migration + flip old-vocab AND tag-first lint → ERROR) stays inside gated 7df1 (DEP: 3ef7 + cross-repo re-tag + b466). Lint stays WARN during the window; flips to ERROR in the same final step that closes it. **Out of scope:** moving the window-close forward.

## Action items
- [ ] **Build the tag-first reorder tool + tag-first lint (WARN) + RED fixtures** [ROUTINE] — `lane-convert.sh --reorder` (or sibling) isolated mode per D2 spec; `roadmap-lint.sh` gains a "lane tag is first token after checkbox" check in WARN mode (distinct from, builds on, the ad8a split-brain WARN floor); adversarial RED fixture set (`tests/test_lane_reorder.sh`). Ungated. Dispatch: background relay handoff (RED) → Sonnet executor. Cites this note. <!-- id:4b37 -->
- [x] Ratify 7df1's fold-in note (C confirmed, isolated reorder, 4b37 builds the tool ungated, 7df1 = run-tool + flip-lints-to-ERROR only) — done this session.
- [x] Tick d259 `[x]` in `2026-07-03-0830-todo-lane-tag-format-prior-art.md` (spike resolved; deliverable = D1/D2/D3 + id:4b37) — done this session.
