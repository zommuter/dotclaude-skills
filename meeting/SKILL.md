---
name: meeting
description: Hold a structured design meeting with multi-persona scrutiny on a non-trivial decision. Trigger when a TODO item has ambiguous scope, a design has non-obvious trade-offs, or two plausible approaches exist and the wrong choice is hard to reverse. Skip for bug fixes, one-liners, or already-decided features. With no subject, audits TODO.md and recent meeting notes to recommend a session.
---

# Meeting Skill

## Setup (run at every invocation)

1. **Find project root**: run `git rev-parse --show-toplevel`. If not in a git repo, use cwd. If `$MEETING_ROOT_OVERRIDE` is set, use that value as `<root>` instead (used by `/meeting-cross` to dispatch against a different project root without `cd`).
2. **Capture metadata**: run each of the following as a **separate Bash call** (one command per call — combined calls don't match the allowlist):
   - `echo "$CLAUDE_SESSION_ID"`
   - `date '+%Y-%m-%d %H:%M'`
   - `date '+%H%M'`
   - `git config user.name`
   Store the results as literals — use them for the meeting-note filename, header lines, and in-transcript human attribution. Do not re-expand these in Write calls; embed the captured values directly.
3. **Load format spec**: read `~/.claude/skills/meeting/format.md`. If `<root>/docs/meeting-notes/meeting-style.md` exists, append its contents to your working context under "## Project-specific overrides". Honour any natural-language overrides (e.g. "exclude Riku", "include Sage as standing", "meetings here are casual") — no structured parsing, just follow them.
4. **Load persona registry**: read `~/.claude/skills/meeting/personas.md`. If the meeting calls for any persona by name, onboard them with their established lens from the registry — no re-introduction needed.
5. **Surface relevant discoveries**: read `~/.claude/skills/meeting/discoveries.md`. At the start of the meeting, mention entries that intersect the meeting topic.
6. **Load user profile**: run `~/.claude/skills/meeting/profile-active.sh` via Bash (passthrough+log by default — emits the full file and appends the active/full ratio to `~/.claude/logs/meeting-profile-active.log`; pass `--filter` or set `PROFILE_ACTIVE_FILTER=1` only after the flip gate clears). Treat the script's stdout as the profile content for this session. Personas may apply pre-emption per the rule defined in `format.md` (eligible + med+ confidence + contradiction; Riku ≫ others).
7. **Broker mode (opt-in):** Probe `echo "$MEETING_LIVE"` (plain expansion — **never** `${MEETING_LIVE:-...}`). If non-empty, or if a broker may be running (probe `echo "$MEETING_BROKER_PORT"`), read `~/.claude/skills/meeting/broker-mode.md` and follow it for the rest of step 7, per-item discussion routing, and decision points. If `$MEETING_LIVE` is empty and no broker is probed live, skip `broker-mode.md` entirely — the meeting proceeds as canonical.

## With a subject argument

1. **Warrantability self-check** (see format spec). If the request looks like a bug fix, one-liner, or already-decided feature, respond "are you sure you want a meeting?" and briefly explain why it might be overkill — before running the agenda. If it clearly passes, note that and proceed.
2. **Past-meetings audit (ADVISORY — observation window)**: run `~/.claude/skills/meeting/orphan-scan.sh`. Uses exact `<!-- id:XXXX -->` match; FP is ~0 by construction (un-IDed legacy lines skipped). Display any candidates labeled `ADVISORY — not yet authoritative` before opening the agenda. Also run `~/.claude/skills/meeting/orphan-scan.sh --reverse` and display any results labeled `ADVISORY — reverse-orphan candidates (done/inline items never mirrored to TODO; possible ledger gap)`. Once zero spurious candidates are confirmed over an observation window of N meetings, drop the ADVISORY caveat and treat output as authoritative. *(F-B shipped 2026-05-21; prior DISABLED state lifted.)*
3. Call `EnterPlanMode`. Accumulate the transcript in the plan file the system creates.
4. **Run the interactive meeting**: open with attendees line + topic. For each persona marked "(new)" in the attendees line, emit a one-sentence introduction naming their lens in the opening exchange before the agenda. Then follow the format spec (agenda → named discussion → AskUserQuestion decision points → decisions → action items).
5. **Print transcript before every AskUserQuestion — in the same turn.** Output the **complete, verbatim discussion text** for the most recent agenda item as visible chat content (not a summary), then immediately call `AskUserQuestion` in the same response. The plan file is not shown in the chat UI; the user must see the discussion *before* the options appear. Never end a turn on bare prose and emit the question in a subsequent turn — both must be in the same message.
6. Proceed to end-of-meeting steps.

## With no subject (default mode)

1. Read `<root>/TODO.md`. Run `~/.claude/skills/meeting/orphan-scan.sh` (**ADVISORY — observation window**): display any candidates before the classifier output as `ADVISORY — orphan scan candidates (informational; exact-ID match, un-IDed legacy skipped)`. Also run `~/.claude/skills/meeting/orphan-scan.sh --reverse` and display any results labeled `ADVISORY — reverse-orphan candidates (done/inline items never mirrored to TODO; possible ledger gap)`. Not authoritative until observation window clears. *(F-B shipped 2026-05-21; prior DISABLED state lifted.)*

   > **Scope discipline:** `<root>/TODO.md` is the *sole* authority for this invocation. Do **not** read or write any other `TODO.md` — not the parent repo's, not a sibling worktree's, not one textually referenced from within this file (e.g. `> Subset of ../../TODO.md`). An empty `## Current` section, or one where all items are checked, is a valid terminal state — report "no open work at `<root>`" and stop; do not look elsewhere for "real" work. If `<root>/TODO.md` does not exist, report missing and ask the user — do not auto-create.

   Then run:
   ```bash
   ~/.claude/skills/meeting/find-todos.sh
   ```
   If any paths are returned, print a warning before the classifier output: `WARNING: subdirectory TODO.md files found — consider merging into <root>/TODO.md: <paths>`. Classification proceeds against root TODO.md only; subdir items are not classified.
2. **Classify** each unchecked, non-date-triggered TODO item into one of three classes:
   - **Class 1 — impl-ready**: a linked meeting note exists whose Decisions section covers this item. The design is done; it just needs building.
   - **Class 2 — planning-worthy**: a linked meeting note frames the question but has no Decisions answer covering it; OR the TODO text signals "design/investigate/decide" with no link. Needs a plan but not a full meeting.
   - **Class 3 — meeting-worthy**: no link and ambiguous scope; use model judgement when neither rule fires cleanly.
   Skip items that are purely date-triggered (contain a specific date as their activation condition).
3. **Print the classified bucket summary** as visible text (group by class, show each item one-liner). Pick `head -1` of the highest-class non-empty bucket (priority: 1 > 2 > 3). Show one-line rationale.
4. Ask via AskUserQuestion: `[do this / pick something else]` — no "not yet" option.
5. **Dispatch by class:**
   - Class 1 → proceed to implementation in normal mode (no plan mode, no meeting).
   - Class 2 → call `EnterPlanMode`; use Claude Code's native explore → design → present → ExitPlanMode workflow. No persona scaffolding. After `ExitPlanMode` and implementation: write a **Class 2 planning record** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` using the Class 2 template defined in `format.md` (distinct from Class 3: `**Mode:**` field, no `## Discussion`, uses `## Context / ## Plan / ## Implementation findings / ## Decisions / ## Action items`). Content synthesises the plan file; plan file is left to Claude Code's auto-cleanup. No allowlist changes needed (Read+Write paths already covered).
   - Class 3 → proceed as if `/meeting <candidate>` was invoked (full meeting flow).
   On "pick something else": re-ask with the next candidate.

## End-of-meeting steps

1. Call `ExitPlanMode`.
2. **Write meeting note** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`. Use the captured date, HHMM, and slug derived from the meeting title. Include `**Started:**` and `**Session:**` header lines populated with the captured literals.
2c. **Create CLAUDE.md if missing**: if `<root>/CLAUDE.md` does not exist, create it from the meeting's decisions — include architecture, output contract, key deps, phases, scope, and related projects. Skip if CLAUDE.md already exists.
2b. **Mirror action items to TODO.md**: add every `## Action items` entry that will outlive this session to `<root>/TODO.md` (create a new section if needed; write only to `<root>/TODO.md` — never to a parent-path file). Each entry must cite the meeting-note path. **For each item, mint a unique ID via `~/.claude/skills/meeting/append.sh new-id` and embed it as `<!-- id:XXXX -->` at the end of the line in the meeting note AND in the TODO.md entry** (same token in both). The first invocation of this session that creates meeting-note items should call `append.sh new-id` once per item before writing. In-session ad-hoc items skip ID minting — they never reach TODO. Purpose: orphan-scan uses this `<!-- id:XXXX -->` for exact correlation; un-IDed lines are skipped (clean cutover). Class 2 planning records skip this step — their action items are resolved in-session by implementation.
2d. **Persona-state delta** (skip if `<root>/docs/meeting-notes/persona-state.yml` does not exist, and skip for Class 1/2 dispatch): from the in-context transcript and the picked option at each `AskUserQuestion` decision point, classify each attending persona as `advocated` (argued for the chosen option), `opposed` (argued against it / for a rejected one), or `uninvolved`. Valence is deterministic: `advocated`→+1, `opposed`→−1, `uninvolved`→0. Count `project_stats` increments: `conviction` += number of ratified decisions this meeting; `wisdom` += persona pushbacks that demonstrably changed an outcome; `tech_debt` += items explicitly deferred to out-of-scope / forward-flags. Then invoke the helper with the delta on stdin (use a **quoted heredoc** `<<'JSON'` — no shell expansion):
   ```
   python3 ~/.claude/skills/meeting/persona-state.py update \
     --root <root> \
     --slug YYYY-MM-DD-HHMM-<slug> <<'JSON'
   { "personas": { "riku": { "decision_id": "D1", "option": "<label>", "stance": "advocated", "valence": 1 }, ... },
     "project_stats": { "conviction": N, "wisdom": N, "tech_debt": N } }
   JSON
   ```
   The script reads `persona-state.yml`, appends the tuple, truncates to last-5 per persona, updates the affinity running-sum, writes YAML back (atomic), and mirrors `project_stats` + affinities to `<root>/web/persona-state.json`. Both files are gitignored; no commit needed.
3. **Profile observations**: for each new behavioural observation the model noticed during the meeting (decision patterns, domain fluency, scope tolerance), ask via AskUserQuestion [save to user-profile / save to user-memory / discard]:
   - *user-profile* → add an entry to `~/.claude/skills/meeting/user-profile.md` using the `## <trait>` format (Observation/Why/Confidence/Pre-emption-eligible).
   - *user-memory* → write a `user`-type entry to `~/.claude/projects/<slug>/memory/<topic>.md`; add pointer to MEMORY.md.
   - *discard* → skip.
4. **Memory classification**: for each key decision or finding, ask via AskUserQuestion [project / discovery / universal / discard]:
   - *project* → write a `project`-type memory entry to `~/.claude/projects/<slug>/memory/<topic>.md`; add pointer to `MEMORY.md`. Body: "Decision: ... **Why:** ... **How to apply:** ...".
   - *discovery* → run `~/.claude/skills/meeting/append.sh -t discoveries -e "- [YYYY-MM-DD <project>] <one-sentence finding> — see <meeting-note-path>"`.
   - *universal* → propose a concrete `~/.claude/CLAUDE.md` edit and ask approval. Do not write directly.
   - *discard* → skip.
5. **Persona registry**: for each new ad-hoc persona introduced, ask [save to global registry / meeting-only]. On save, run `~/.claude/skills/meeting/append.sh -t personas -e "- 🔣 **Name** — one-sentence lens. Introduced YYYY-MM-DD (<project>/<meeting-slug>)."` (replace `🔣` with an appropriate emoji).

> **IMPORTANT — end-of-meeting writes:** Always use `~/.claude/skills/meeting/append.sh -t discoveries -e "…"` or `append.sh -t personas -e "…"` for registry appends. **Never** use direct Edit or Write on `discoveries.md` or `personas.md` — those trigger a permission prompt even though Edit is generally allowlisted. `append.sh` is the allowlisted path.

## Constraints during a meeting

- No file edits except the plan file and the final meeting note.
- No implementation work mid-meeting even if asked — defer until after ExitPlanMode.
- New topics that arise mid-meeting must be captured as "Amendment session" in the transcript, not silently inserted.
