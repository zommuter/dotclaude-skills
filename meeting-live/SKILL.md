---
name: meeting-live
description: Broker-augmented design meeting — same as /meeting but streams persona discussion to an external renderer via HTTP broker, with γ-branch decision handling. Set MEETING_LIVE=0 to run identically to canonical /meeting. Use for Class 3 meetings or subject-given invocations where a renderer is attached or expected.
---

# Meeting-Live Skill

Broker-augmented variant of `/meeting`. Behaviour is identical to canonical `/meeting` when `MEETING_LIVE=0` or no broker subscriber is present. When a renderer is attached (`/status.subscribers > 0`), persona discussion streams via the broker and decision points use POST `/question` + GET `/await` instead of AskUserQuestion.

## Setup (run at every invocation)

1. **Find project root**: run `git rev-parse --show-toplevel`. If not in a git repo, use cwd.
2. **Capture metadata**: run each of the following as a **separate Bash call** (one command per call — combined calls don't match the allowlist):
   - `echo "$CLAUDE_SESSION_ID"`
   - `date '+%Y-%m-%d %H:%M'`
   - `date '+%H%M'`
   - `git config user.name`
   Store the results as literals — use them for the meeting-note filename, header lines, and in-transcript human attribution. Do not re-expand these in Write calls; embed the captured values directly.
3. **Load format spec**: read `~/.claude/skills/meeting-live/format.md`. If `<root>/docs/meeting-notes/meeting-style.md` exists, append its contents to your working context under "## Project-specific overrides". Honour any natural-language overrides (e.g. "exclude Riku", "include Sage as standing", "meetings here are casual") — no structured parsing, just follow them.
4. **Load persona registry**: read `~/.claude/skills/meeting-live/personas.md`. If the meeting calls for any persona by name, onboard them with their established lens from the registry — no re-introduction needed.
5. **Surface relevant discoveries**: read `~/.claude/skills/meeting/discoveries.md`. At the start of the meeting, mention entries that intersect the meeting topic.
6. **Load user profile**: read `~/.claude/skills/meeting/user-profile.md`. Personas may apply pre-emption per the rule defined in `format.md` (eligible + med+ confidence + contradiction; Riku ≫ others).
7. **Start broker (skip if `MEETING_LIVE=0`):** Only on Class 3 / subject-given paths (not Class 1/2 dispatch).
   - Spawn: `python3 ~/.claude/skills/meeting-live/broker.py "$CLAUDE_SESSION_ID"` with `run_in_background=true`.
   - Poll for port: `jq -r .port /tmp/meeting-rpg/$SID/broker.json` (foreground, ≤2s; use the literal captured session ID, not `$SID`). Store as `<port>`.
   - On success: advertise in chat — print the plain URL `http://127.0.0.1:<port>/events` and the stream command `curl -N http://127.0.0.1:<port>/events` for a second terminal.
   - On timeout/bind-fail: note "broker unavailable, falling back to standard mode" in chat; clear `<port>`; continue as canonical `/meeting` for the rest of the session.

## With a subject argument

1. **Warrantability self-check** (see format spec). If the request looks like a bug fix, one-liner, or already-decided feature, respond "are you sure you want a meeting?" and briefly explain why it might be overkill — before running the agenda. If it clearly passes, note that and proceed.
2. **Past-meetings audit (DISABLED)**: orphan-scan.sh suppressed — FP rate too high (differently-phrased action items resurface as orphans every run regardless of TODO.md status). Skip this step. Re-enable after F-A or F-B redesign ships (see TODO.md).
3. Call `EnterPlanMode`. Accumulate the transcript in the plan file the system creates.
4. **Run the interactive meeting**: open with attendees line + topic, then follow the format spec (agenda → named discussion → decision points → decisions → action items).
   - **Discussion (persona lines):** If `<port>` is set, POST **one batched block per agenda item** (not per exchange line) to `/event` — after the verbatim transcript is already printed as visible chat text. Single call: `~/.claude/skills/meeting/broker-curl.sh <port> event '{"text":"<escaped block>"}'`. The broker is an additive channel; visible chat output is unchanged.
   - **Before each decision point:** poll `~/.claude/skills/meeting/broker-curl.sh <port> status` (if `<port>` set). Parse `subscribers`.
     - If `subscribers > 0` (renderer attached): `~/.claude/skills/meeting/broker-curl.sh <port> question '<json>'` to send the decision prompt; `~/.claude/skills/meeting/broker-curl.sh <port> await` to block for the response. Map the returned `answer` back to the decision options list.
     - Else (headless): use AskUserQuestion as normal.
5. **Print transcript before every AskUserQuestion** — output the **complete, verbatim discussion text** for the most recent agenda item as visible chat content, not a summary. Required even in headless mode.
6. Proceed to end-of-meeting steps.

## With no subject (default mode)

1. Read `<root>/TODO.md`. *(Orphan-scan disabled — FP rate too high; pending F-A/F-B redesign in TODO.md.)*

   > **Scope discipline:** `<root>/TODO.md` is the *sole* authority for this invocation. Do **not** read or write any other `TODO.md` — not the parent repo's, not a sibling worktree's, not one textually referenced from within this file (e.g. `> Subset of ../../TODO.md`). An empty `## Current` section, or one where all items are checked, is a valid terminal state — report "no open work at `<root>`" and stop; do not look elsewhere for "real" work. If `<root>/TODO.md` does not exist, report missing and ask the user — do not auto-create.

   Then run:
   ```bash
   find . -mindepth 2 -maxdepth 3 -name TODO.md \
     -not -path './.git/*' -not -path '*/node_modules/*' \
     -not -path '*/.venv/*' -not -path '*/*/.git/*' 2>/dev/null
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
   - Class 1 → proceed to implementation in normal mode (no plan mode, no meeting). Broker not started.
   - Class 2 → call `EnterPlanMode`; use Claude Code's native explore → design → present → ExitPlanMode workflow. No persona scaffolding. Broker not started. After `ExitPlanMode` and implementation: write a **Class 2 planning record** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` using the Class 2 template defined in `format.md`. Content synthesises the plan file; plan file is left to Claude Code's auto-cleanup.
   - Class 3 → proceed as if `/meeting-live <candidate>` was invoked (full meeting flow, broker started per step 7).
   On "pick something else": re-ask with the next candidate.

## End-of-meeting steps

1. **Write meeting note** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`. Use the captured date, HHMM, and slug derived from the meeting title. Include `**Started:**` and `**Session:**` header lines populated with the captured literals.
1b. **Mirror action items to TODO.md** (Step 5b): before calling ExitPlanMode, add every `## Action items` entry that will outlive this session to `<root>/TODO.md` (create a new section if needed; write only to `<root>/TODO.md` — never to a parent-path file). Each entry must cite the meeting-note path. Class 2 planning records skip this step — their action items are resolved in-session by implementation. In-session ad-hoc items (resolved before ExitPlanMode) also skip. Purpose: orphan-scan is a *failsafe*, not the primary tracking mechanism.
2. **Profile observations**: for each new behavioural observation the model noticed during the meeting (decision patterns, domain fluency, scope tolerance), ask via AskUserQuestion [save to user-profile / save to user-memory / discard]:
   - *user-profile* → add an entry to `~/.claude/skills/meeting/user-profile.md` using the `## <trait>` format (Observation/Why/Confidence/Pre-emption-eligible).
   - *user-memory* → write a `user`-type entry to `~/.claude/projects/<slug>/memory/<topic>.md`; add pointer to MEMORY.md.
   - *discard* → skip.
3. **Memory classification**: for each key decision or finding, ask via AskUserQuestion [project / discovery / universal / discard]:
   - *project* → write a `project`-type memory entry to `~/.claude/projects/<slug>/memory/<topic>.md`; add pointer to `MEMORY.md`. Body: "Decision: ... **Why:** ... **How to apply:** ...".
   - *discovery* → run `~/.claude/skills/meeting-live/append.sh -t discoveries -e "- [YYYY-MM-DD <project>] <one-sentence finding> — see <meeting-note-path>"`.
   - *universal* → propose a concrete `~/.claude/CLAUDE.md` edit and ask approval. Do not write directly.
   - *discard* → skip.
4. **Persona registry**: for each new ad-hoc persona introduced, ask [save to global registry / meeting-only]. On save, run `~/.claude/skills/meeting-live/append.sh -t personas -e "- 🔣 **Name** — one-sentence lens. Introduced YYYY-MM-DD (<project>/<meeting-slug>)."` (replace `🔣` with an appropriate emoji).
5. Call `ExitPlanMode`.

> **IMPORTANT — end-of-meeting writes:** Always use `~/.claude/skills/meeting-live/append.sh -t discoveries -e "…"` or `append.sh -t personas -e "…"` for registry appends. **Never** use direct Edit or Write on `discoveries.md` or `personas.md` — those trigger a permission prompt even though Edit is generally allowlisted. `append.sh` is the allowlisted path.

## Constraints during a meeting

- No file edits except the plan file and the final meeting note.
- No implementation work mid-meeting even if asked — defer until after ExitPlanMode.
- New topics that arise mid-meeting must be captured as "Amendment session" in the transcript, not silently inserted.

## Broker γ-branch reference

| State | Discussion | Decision point |
|---|---|---|
| `MEETING_LIVE=0` | Chat only | AskUserQuestion |
| Broker up, `subscribers=0` | Chat + POST `/event` | AskUserQuestion (headless) |
| Broker up, `subscribers>0` | Chat + POST `/event` | POST `/question` + GET `/await` |
| Broker unavailable | Chat only | AskUserQuestion |

Broker endpoints (all at `http://127.0.0.1:<port>`):
- `GET /status` → `{"subscribers": N}`
- `POST /event` body `{"text": "..."}` → streams to renderer
- `POST /question` body `{"text": "...", "options": [...]}` → sends decision prompt to renderer
- `GET /await` → blocks until renderer POSTs `/response`; returns `{"answer": "..."}`
- `POST /response` body `{"answer": "..."}` → renderer submits an answer, unblocks `GET /await` (broker.py:49-53). Manual test: `~/.claude/skills/meeting/broker-curl.sh <port> response '{"answer":"<choice>"}'`
- `GET /events` → SSE stream

**Debug recipe (readable event tail):**
```bash
~/.claude/skills/meeting/broker-curl.sh <port> events | while read line; do echo "$line" | sed 's/^data: //' | jq -r '.text // .'; done
```
Raw SSE emits `data: <json>` — the recipe strips the prefix and extracts `.text` for human-readable tailing in a second terminal.

**All broker calls use `broker-curl.sh` — never raw curl to 127.0.0.1.** This keeps the allowlist to one entry: `Bash(~/.claude/skills/meeting/broker-curl.sh *)`.
