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
**Cross-project mode:** if the skill argument is exactly `--cross` (literal token, nothing else), read `~/.claude/skills/meeting/cross-mode.md` and follow it for the entire session. The metadata captured in step 2 is available to cross-mode.md for the routing-trail note. Skip steps 2b onward — cross-mode.md owns the full cross flow. Stop reading this document.

2b. **Git hygiene check** (run after metadata, before loading anything else):
   - Run `git status --short` (one Bash call). If empty → proceed silently.
   - If dirty → run `git log -1 --format="%cr|%s"` (one Bash call) to get last commit age and subject.
   - **Classify the situation**:
     - **Failure-analysis candidate**: last commit ≥ 2 hours ago **and** the dirty files include work artifacts — any of `TODO.md`, files under `docs/meeting-notes/`, source files (`.py`, `.sh`, `.ts`, `.js`, `.rs`, `.go`, `.md` outside docs). Interpretation: `git-diary-workflow` likely failed to run after a prior work session.
     - **Light case**: otherwise (fresh edits, or only config/lock files, or last commit is recent).
   - Surface the dirty file list and last commit info as visible text in both cases.
   - Ask via `AskUserQuestion` before proceeding:
     - *Failure-analysis candidate*: options `["Commit now (run /git-diary-workflow)", "Hold a failure-analysis meeting on the missed commit", "Proceed to meeting anyway"]`
     - *Light case*: options `["Commit first, then meeting", "Proceed anyway"]`
   - **On "Commit now"**: tell the user to run `/git-diary-workflow` in a separate prompt, then re-invoke `/meeting`. Stop here — do not continue setup.
   - **On "Failure analysis"**: pivot this invocation — override the meeting subject to `"git-diary-workflow failure: why didn't the post-prompt commit run?"` and proceed as a subject-mode meeting on that topic. The dirty-file list and last-commit info become the meeting's context artefact.
   - **On "Proceed anyway"**: continue setup normally.
3. **Load format spec**: read `~/.claude/skills/meeting/format.md`. If `<root>/docs/meeting-notes/meeting-style.md` exists, append its contents to your working context under "## Project-specific overrides". Honour any natural-language overrides (e.g. "exclude Riku", "include Sage as standing", "meetings here are casual") — no structured parsing, just follow them.
4. **Load persona registry**: read `~/.claude/skills/meeting/personas.md`. If the meeting calls for any persona by name, onboard them with their established lens from the registry — no re-introduction needed.
5. **Surface relevant discoveries**: if `EMBED_ENDPOINT` is set and a meeting subject was provided (i.e., `/meeting <subject>`), run:
   ```bash
   ~/.claude/skills/meeting/retrieve-top-k.py \
     --file ~/.claude/skills/meeting/discoveries.md \
     --query "<subject>" \
     --chunk-sep "^- \[" \
     --k 15
   ```
   Use the stdout as the discoveries context. If the script exits non-zero, `EMBED_ENDPOINT` is unset, or this is a no-arg invocation, fall back to reading `~/.claude/skills/meeting/discoveries.md` (full). At the start of the meeting, mention entries that intersect the meeting topic.

   **GitHub prior art** (subject mode only): also run:
   ```bash
   ~/.claude/skills/meeting/gh-audit.sh search "<subject>"
   ```
   If stdout is non-empty, surface any matching issues/PRs alongside the discoveries block labeled `GitHub prior art — issues/PRs matching this topic`. Exit 0 with no stdout means no GitHub remote or no matches — skip silently. Do not label as ADVISORY; GitHub search results are factual, not scan candidates.
6. **Load user profile**: run `~/.claude/skills/meeting/profile-active.sh --filter` via Bash (filter mode — emits only pre-emption-eligible med/high-confidence entries + file header; flip gate cleared 2026-06-05: ratio consistently 0.26–0.34 ≪ 0.60, setup-ctx ~30% of meeting cache_read tokens; ratio still logged to `~/.claude/logs/meeting-profile-active.log` each run for observability). Treat the script's stdout as the profile content for this session. Personas may apply pre-emption per the rule defined in `format.md` (eligible + med+ confidence + contradiction; Riku ≫ others).
7. **Broker mode (recommended — launch via `~/src/meeting-rpg/meeting-rpg <topic>` to activate):** Probe `echo "$MEETING_LIVE"` (plain expansion — **never** `${MEETING_LIVE:-...}`). If non-empty, or if a broker may be running (probe `echo "$MEETING_BROKER_PORT"`), read `~/.claude/skills/meeting/broker-mode.md` and follow it for the rest of step 7, per-item discussion routing, and decision points. If `$MEETING_LIVE` is empty and no broker is probed live, skip `broker-mode.md` entirely — the meeting proceeds as canonical. **Savings confirmed 2026-06-05:** ≥5k tok/meeting across 3 pilots (discussion suppressed from chat → no context inflation; auto-detects renderer via `$MEETING_BROKER_PORT`).

## With a subject argument

1. **Warrantability self-check** (see format spec). If the request looks like a bug fix, one-liner, or already-decided feature, respond "are you sure you want a meeting?" and briefly explain why it might be overkill — before running the agenda. If it clearly passes, note that and proceed.
2. **Past-meetings audit**: run `~/.claude/skills/meeting/orphan-scan.sh`. Uses exact `<!-- id:XXXX -->` match; FP is ~0 by construction (un-IDed legacy lines skipped). Display any candidates as orphan candidates requiring resolution before opening the agenda. Also run `~/.claude/skills/meeting/orphan-scan.sh --reverse` and display any results labeled `ADVISORY — reverse-orphan candidates (done/inline items never mirrored to TODO; possible ledger gap)`. *(Observation window closed 2026-06-11: 0 spurious FPs in 34 runs; forward scan is authoritative; reverse stays ADVISORY — expected to return in-session completions.)*

   Also run `~/.claude/skills/meeting/gh-audit.sh open` and display any output labeled `ADVISORY — open GitHub issues/PRs (supplementary orphan context)`. Exit 0 with no stdout means no GitHub remote or no open items — skip silently.
3. Call `EnterPlanMode`. Accumulate the transcript in the plan file the system creates.
4. **Run the interactive meeting**: open with attendees line + topic. For each persona marked "(new)" in the attendees line, emit a one-sentence introduction naming their lens in the opening exchange before the agenda. Then follow the format spec (agenda → named discussion → AskUserQuestion decision points → decisions → action items).
5. **Print transcript before every AskUserQuestion — in the same turn.** Output the **complete, verbatim discussion text** for the most recent agenda item as visible chat content (not a summary), then immediately call `AskUserQuestion` in the same response. The plan file is not shown in the chat UI; the user must see the discussion *before* the options appear. Never end a turn on bare prose and emit the question in a subsequent turn — both must be in the same message.
6. Proceed to end-of-meeting steps.

## With no subject (default mode)

1. Read `<root>/TODO.md`. Run `~/.claude/skills/meeting/orphan-scan.sh`: display any candidates before the classifier output as orphan scan candidates requiring resolution (authoritative; exact-ID match, un-IDed legacy skipped). Also run `~/.claude/skills/meeting/orphan-scan.sh --reverse` and display any results labeled `ADVISORY — reverse-orphan candidates (done/inline items never mirrored to TODO; possible ledger gap)`.

   Also run `~/.claude/skills/meeting/gh-audit.sh open` and display any output labeled `ADVISORY — open GitHub issues/PRs (supplementary orphan context)`. Exit 0 with no stdout means no GitHub remote or no open items — skip silently.

   > **Scope discipline:** `<root>/TODO.md` is the *sole* authority for this invocation. Do **not** read or write any other `TODO.md` — not the parent repo's, not a sibling worktree's, not one textually referenced from within this file (e.g. `> Subset of ../../TODO.md`). An empty `## Current` section, or one where all items are checked, is a valid terminal state — report "no open work at `<root>`" and stop; do not look elsewhere for "real" work. If `<root>/TODO.md` does not exist, report missing and ask the user — do not auto-create.

   Then run:
   ```bash
   ~/.claude/skills/meeting/find-todos.sh
   ```
   If any paths are returned, print a warning before the classifier output: `WARNING: subdirectory TODO.md files found — consider merging into <root>/TODO.md: <paths>`. Classification proceeds against root TODO.md only; subdir items are not classified.
2. **Pre-classify** with `classify.sh` — run:
   ```bash
   ~/.claude/skills/meeting/classify.sh <root>
   ```
   The script outputs TSV lines (CLASS, ID, SUMMARY, NOTE-LINK) for each unchecked item. Use this as the starting classification, then apply model judgment:
   - **Class 1 — impl-ready**: C1 from classify.sh (link + Decisions section present). Confirm the design actually covers this item.
   - **Class 2 — planning-worthy**: C2 from classify.sh (link without Decisions, or keyword hint). Also reclassify C1 items whose linked design is incomplete.
   - **Class 3 — meeting-worthy**: C3 from classify.sh (no link, ambiguous scope). Use model judgement when neither rule fires cleanly.
   - **Skip**: items that are purely date-triggered (activation date in text); items explicitly deferred/reopen-gated with unmet conditions.
3. **Print the classified bucket summary** as visible text (group by class, show each item one-liner). If an item has `GATED` in the 5th TSV field, append `[GATED]` to its one-liner so the gate condition is visually obvious. Pick `head -1` of the highest-class non-empty bucket (priority: 1 > 2 > 3). Show one-line rationale.
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
2b. **Mirror action items to TODO.md**: add every `## Action items` entry that will outlive this session to `<root>/TODO.md` (create a new section if needed; write only to `<root>/TODO.md` — never to a parent-path file). Each entry must cite the meeting-note path. **For each item, mint a unique ID via `~/.claude/skills/meeting/append.sh new-id` and embed it as `<!-- id:XXXX -->` at the end of the line in the meeting note AND in the TODO.md entry** (same token in both). The first invocation of this session that creates meeting-note items should call `append.sh new-id` once per item before writing. In-session ad-hoc items skip ID minting — they never reach TODO. Purpose: orphan-scan uses this `<!-- id:XXXX -->` for exact correlation; un-IDed lines are skipped (clean cutover). Class 2 planning records skip this step — their action items are resolved in-session by implementation. **When closing an existing TODO item** (marking it `[x]` by ID), use the flock'd merge helper to avoid cross-session clobbering:
   ```bash
   ~/.claude/skills/meeting/md-merge.py update-ids --file <root>/TODO.md <<'JSON'
   {"updates": [{"id": "XXXX", "line": "- [x] description <!-- id:XXXX -->"}]}
   JSON
   ```
2d. **Persona-state delta** (skip if `<root>/docs/meeting-notes/persona-state.yml` does not exist, and skip for Class 1/2 dispatch): from the in-context transcript and the picked option at each `AskUserQuestion` decision point, classify each attending persona as `advocated` (argued for the chosen option), `opposed` (argued against it / for a rejected one), or `uninvolved`. Valence is deterministic: `advocated`→+1, `opposed`→−1, `uninvolved`→0. Count `project_stats` increments: `conviction` += number of ratified decisions this meeting; `wisdom` += persona pushbacks that demonstrably changed an outcome; `tech_debt` += items explicitly deferred to out-of-scope / forward-flags. Then invoke the helper in two steps (use **quoted heredoc** `<<'JSON'` — no shell expansion):
   ```
   # Step 1 — shard: write this session's delta to persona-events/<session>.json (zero contention)
   ~/.claude/skills/meeting/persona-state.py shard \
     --root <root> \
     --session <captured $CLAUDE_SESSION_ID> \
     --slug YYYY-MM-DD-HHMM-<slug> <<'JSON'
   { "personas": { "riku": { "decision_id": "D1", "option": "<label>", "stance": "advocated", "valence": 1 }, ... },
     "project_stats": { "conviction": N, "wisdom": N, "tech_debt": N } }
   JSON

   # Step 2 — collapse: fold all pending shards into persona-state.yml under flock, then GC shards
   ~/.claude/skills/meeting/persona-state.py collapse --root <root>
   ```
   `shard` writes to `<root>/persona-events/<session>.json` (no contention between concurrent meetings). `collapse` acquires an exclusive flock, folds all shard files into `persona-state.yml` (appends events, truncates to last-5, updates affinity running-sum), mirrors `project_stats` + affinities to `<root>/web/persona-state.json`, then deletes the shard files. Both `persona-state.yml` and `persona-events/` are gitignored; no commit needed. Add `persona-events/` to `<root>/.gitignore` if not already present.

> **Broker γ-branch (steps 3–5):** if `<port>` is set (from setup step 7), re-probe `/status` before each prompt and route through the broker when `subscribers > 0`. See `~/.claude/skills/meeting/broker-mode.md` §End-of-meeting prompt routing. `AskUserQuestion` is the fallback when `subscribers = 0` or `<port>` unset — no behaviour change from canonical.

3. **Profile observations**: for each new behavioural observation the model noticed during the meeting (decision patterns, domain fluency, scope tolerance), ask via AskUserQuestion [save to user-profile / save to user-memory / discard]:
   - *user-profile* → use the flock'd merge helper to update the relevant section without clobbering concurrent session edits:
     ```bash
     ~/.claude/skills/meeting/md-merge.py update-sections \
       --file ~/.claude/skills/meeting/user-profile.md <<'JSON'
     {"sections": [{"heading": "## <exact heading text>", "content": "## <exact heading>\n\n<full updated section body>"}]}
     JSON
     ```
     For a **new** trait (no existing heading), pass the full text; the helper appends it. For an **existing** trait, read the current section first (so you have the exact heading and prior evidence), append new evidence, then pass the full updated text.
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
