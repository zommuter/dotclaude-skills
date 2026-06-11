# 2026-06-11 — git-diary-workflow SKILL.md trim

**Started:** 2026-06-11 09:21
**Session:** 1e0d457f-7a26-4a03-bc0e-5561c632d0f8
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing)
**Topic:** Trim `git-diary-workflow/SKILL.md` (171 lines) before it crosses the per-prompt-ctx gate — without risking missed commits.

## Surfaced discoveries
- [2026-05-08 .claude] git-diary-workflow uses capture-first pattern for `$CLAUDE_SESSION_ID`; `<<'EOF'` quoted-heredoc required — drives the inline comment on line 29.
- [2026-05-10 .claude] Bash matcher refuses unquoted `<<EOF` as a class; allowlist patterns are shape-sensitive — explains some code-block verbosity.

## Agenda
1. Is a trim warranted at 171/200, or note-and-defer until the gate fires?
2. Which content is safe to cut vs. must stay inline (missed-commit risk)?
3. Destination for removed content — compress in place, extract to on-demand REFERENCE.md, or delete?

## Discussion

**Agenda 1 — warrant + scope.**
🏗️ Archie: file splits at line 129 — happy-path procedure (Steps 1/1b/1c/2/3, every run, must stay inline) vs. exception/reference (Gotchas, Merge Conflicts, Error Handling, Verification, rare). Conditional-load extraction is mechanically possible (broker-mode.md pattern). Compress-in-place is strictly good (shorter prose, identical steps, no downside); extraction is the speculative axis — separable.

😈 Riku: governing asymmetry — a missed commit / wrong-files-staged is silent and unrecoverable; token cost is recoverable. Over-aggressive trim trades recoverable cost for unrecoverable risk. Pre-emption (high-confidence profile "observe before bulk action"): speculative extraction at 171/200 with no observed friction contradicts user instinct.

⚙️ Sage: file is loaded every substantive prompt; per-prompt ctx multiplier real (~1.3k tok × prompt density), but already paid today; gate is a review trigger, not a cliff. Conditional-load is reliable when the trigger is deterministic.

✂️ Petra: scope is "compress-in-place banks headroom; extraction is its own separate gated decision."

**User:** leaning compress-in-place — and raised the metric question: lines vs. characters vs. tokens?

**Agenda 1 cont. — the ruler.**
⚙️ Sage: gate intent is context cost = tokens; lines are a lazy proxy (3 vs 300 chars/line).
😈 Riku: line-based gate can be gamed — drop lines, pack survivors, tokens rise; minimum evidence is a token count.
✂️ Petra (N=2): consumers of a token ruler ≥3 (this audit gate, format.md "per-prompt ctx multipliers", deferred todo-update watch). Estimate, don't instrument.
🏗️ Archie: dependency-free `wc -c / 4` matches `cost-of.sh` SIZE_KB/4 convention already in use.
😈 Riku: accept chars/4 as estimate; honest gate = **2k tokens** (≈ ~200 lines proxy). Current file: ~1.27k/2k.

**User decision (metric):** chars/4 token estimate.

**Closing — compression targets.**
🏗️ Archie: (1) Step 1c (lines 95–110) repeats Step 1b's manifest+msg+lock-push block verbatim — collapse to back-reference, drop duplicate code (~10 lines). (2) Co-Authored-By explainer (45–48) duplicates 32–38 — merge. (3) Tighten prose in 1b and Gotchas/Merge-Conflicts intros.
😈 Riku (contract): every executable instruction at 171 lines must survive post-trim — capture-first session-ID, `<<'EOF'` quoted-heredoc, never-`git add -A`, never-amend/force/--no-verify, ask-user-on-conflict. 1c-by-reference safe ONLY because 1b retains one full inline copy.
✂️ Petra (out of scope): file extraction (deferred), procedure changes, touching `git-lock-push.sh`/`diary-append.sh`.
⚙️ Sage: update existing id-keyed TODO watch-line to token form — re-spec, not new item.

## Decisions
- **Compress-in-place only.** Tighten verbose prose and remove duplicated code in `git-diary-workflow/SKILL.md`; keep every section inline. No file split. **Out of scope:** extracting exception-path sections to an on-demand REFERENCE.md (deferred, open only if 2k-token gate is hit), any procedure change, any edit to `git-lock-push.sh` or `diary-append.sh`.
- **Specific compression targets:** (1) collapse Step 1c's duplicated manifest+msg+lock-push block to a back-reference to Step 1b (1b retains full inline copy); (2) merge Co-Authored-By explainer (lines 45–48) into inline guidance at 32–38; (3) tighten prose in Step 1b and Gotchas / Merge-Conflicts intros. Target ≈150 lines / ~1.05k tokens.
- **Preservation contract (must survive):** capture-first `$CLAUDE_SESSION_ID` step; `<<'EOF'` quoted-heredoc requirement; "never `git add -A`/`git add .`"; "never amend/force/--no-verify/--no-gpg-sign unless asked"; "ask the user on merge conflict, never force-resolve"; the manifest-mode contract (commit only this session's files). One complete inline copy of the manifest+lock-push pattern remains (in Step 1b).
- **Gate re-expressed in tokens.** Re-spec the `git-diary-workflow` watch-line in TODO.md: `~(wc -c)/4 tokens vs. 2k gate`. Reuses `cost-of.sh` SIZE_KB/4 convention. **Out of scope:** exact tokenizer/API counting.
- **(Separate action, post-meeting)** Apply `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` to `~/.claude/settings.json` to cap context at 200k. Not part of this trim.

## Action items
- [ ] Compress `git-diary-workflow/SKILL.md` in place per the targets above; verify preservation contract (every listed instruction still derivable). Contract: post-trim `wc -c`/4 < 2k tokens; no procedural step dropped; one full inline manifest+lock-push pattern in Step 1b. See `docs/meeting-notes/2026-06-11-0921-git-diary-skillmd-trim.md`. <!-- id:5a5c -->
- [ ] Re-spec the `git-diary-workflow SKILL.md size audit` watch-line in `TODO.md` from line-based to token form: `~(wc -c)/4 ≈ N tokens vs. 2k gate`; same id-keyed line. See `docs/meeting-notes/2026-06-11-0921-git-diary-skillmd-trim.md`. <!-- id:e57b -->
