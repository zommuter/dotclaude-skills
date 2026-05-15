# 2026-05-15 — /todo-update should remove empty sections from TODO.md

**Started:** 2026-05-15 11:21
**Session:** 3e2ad648-bb7f-4840-936f-e083b3d3ca3f
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Make the todo-update skill prune sections of TODO.md that have become empty.

## Agenda
1. Define "empty section" and which headings are protected from removal.
2. Where the pruning logic lives (extend `archive-done.sh` vs. SKILL.md prose vs. new script) and when it triggers.
3. Edge cases and explicit out-of-scope.

## Discussion

### Agenda 1 — definition of "empty section" + protection

Archie anchored on the live file: two empty shapes exist — zero task lines (`## git-diary-workflow`) vs. only-`[x]` history (`## hooks`, `## meeting skill — allowlist`). Riku named three failure modes: (1) `## Done` is transiently zero-line and is the archive target — must be unconditionally protected (`SKILL.md:93`); (2) "no unchecked items" would delete `[x]` history that `archive-done.sh` is meant to relocate by age, not destroy; (3) a mid-edit cleared section would be nuked (low cost — heading re-add is one line + git preserves it). Petra proposed the minimal safe definition: prunable iff zero `- [ ]` AND zero `- [x]` between heading and next heading/EOF, with a name-based protected list. Sage refined: protect by *name* (`Done`, `Current`) not by template position, since the live file has no `## Current`. Archie surfaced the concrete consequence: under this definition only `## git-diary-workflow` is pruned from the live file.

**Decision 1 (Zommuter):** A section is prunable iff its body contains **zero task lines** (`- [ ]` *and* `- [x]` both absent) between its heading and the next heading or EOF, AND its heading text is not in the protected set `{Done, Current}` (case-sensitive match on the heading label). Out of scope: section merging, reordering, de-duplication.

### Agenda 2 — where the logic lives + trigger ordering

Archie laid out three loci (extend archive-done.sh / new script / SKILL.md prose). Sage pre-empted on the lever-first pattern toward extending archive-done.sh and ruled out prose-only via the 2026-05-14 77%-bypass discovery. Riku named the gap: archive-done.sh is gated <50 lines (and the live file is 48 lines — would not be pruned today). Petra rejected ungating archive wholesale (scope creep) in favour of an independent always-on prune pass. Sage identified the gate lives in SKILL.md prose *and* the script; relocating it into the script (script always invoked; archives only ≥50 lines, prunes always) fixes the prose-bypass reliability gap. Riku flagged this as a deliberate scope addition justified by the present 48-line-file failure, not speculation.

**Decision 2 (Zommuter):** Add an always-on empty-section prune pass to `archive-done.sh`. Relocate the ≥50-line gate from SKILL.md prose into the script: the script is always invoked; the prune pass always runs; the archive pass stays gated at ≥50 lines. `SKILL.md` Step 4 prose drops the "skip if <50 lines" condition. Deliberate scope addition (gate relocation prose→script) accepted on evidence: the live 48-line TODO.md has an empty section now and would not be pruned under the keep-prose-gate alternative.

### Agenda 3 — implementation shape + edge cases

Archie: the 50-line gate is an early `exit 0` at `archive-done.sh:19-23` (mirrored in `SKILL.md:79`); relocation means converting it to "skip archive pass" not "exit script", and single-sourcing it in the script (drift-aversion). Riku named two correctness traps: (1) `archive-done.sh:77-79` `if not to_arch: sys.exit(0)` would discard a prune if nothing is archived — prune write must not be gated on `to_arch`; (2) prune-after-archive converges in one pass (a section whose last `[x]` is archived this run becomes empty and is pruned same session) — no upside to prune-before. Sage: only `##`+ are prunable sections; H1 `# TODO` and pre-first-`##` preamble are structural and untouched; protected-label match strips `#`s + whitespace, case-sensitive vs `{Done, Current}`; on excision, collapse to exactly one blank line between survivors. Petra locked scope: one prune pass, gate relocation, SKILL.md prose edit — nothing else. Converged with no user decision required.

## Decisions
- **D1 — "empty" definition:** prunable iff body has zero `- [ ]` AND zero `- [x]` lines between heading and next heading/EOF, AND heading label ∉ `{Done, Current}` (case-sensitive). Out of scope: merge/reorder/dedup.
- **D2 — locus + gate:** prune pass added to `archive-done.sh`; ≥50-line gate relocated SKILL.md-prose→script; script always invoked; prune always runs; archive stays ≥50-gated. SKILL.md Step 4 prose drops the line-count condition.
- **D3 — shape:** prune *after* archive, unconditional; only `##`+ headings prunable (H1/preamble safe); case-sensitive label match for protection; clean single-blank-line excision; write-if-either-changed.

## Action items
- [x] **Add empty-section prune pass to `archive-done.sh`** — implemented in session 3e2ad648; `dotclaude-skills/todo-update/archive-done.sh` restructured with `do_archive` flag, prune pass after archive logic, no `sys.exit(0)` on empty `to_arch`. Synthetic round-trip and live check both pass.
- [x] **Edit `todo-update/SKILL.md` Step 4** — "skip if fewer than 50 lines" removed; gate now lives in the script. Done in same session.
- [x] **Synthetic round-trip test** — verified: <50-line fixture (prune only, no archive), ≥50-line fixture (archive + prune-after in same pass), `## Done`/`## Current`/H1 all protected. All assertions pass.
