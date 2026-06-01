---
name: meeting-live
description: Broker-augmented design meeting — same as /meeting but streams persona discussion to an external renderer via HTTP broker, with γ-branch decision handling. Set MEETING_LIVE=1 to self-start the broker daemon; unset/0 = lazy-connect only (never spawns). Use for Class 3 meetings or subject-given invocations where a renderer is attached or expected.
---

# Meeting-Live Skill

Broker-augmented variant of `/meeting`. Behaviour is identical to canonical `/meeting` when no broker subscriber is present. Set `MEETING_LIVE=1` to self-start the broker daemon (idempotent); unset/`0` = lazy-connect only. When a renderer is attached (`/status.subscribers > 0`), persona discussion streams via the broker and decision points use POST `/question` + GET `/await` instead of AskUserQuestion.

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
7. **Connect to broker:** Only on Class 3 / subject-given paths (not Class 1/2 dispatch).
   - **Probe the flag with `echo "$MEETING_LIVE"`** (plain expansion). Do **not** use `${MEETING_LIVE:-unset}` or any `${VAR:-default}` form — default-expansion syntax triggers the Bash parameter-expansion permission prompt as a class, regardless of allowlist. `1` = opt-in self-start; empty or `0` = lazy-connect only (never spawns a process). Tuning: `MEETING_BROKER_PORT` (default 64109), `MEETING_BROKER_IDLE` (idle-shutdown seconds; 0=never).
   - **Authoritative port (launcher contract):** probe `echo "$MEETING_BROKER_PORT"` (plain expansion). If set, liveness-probe it via `~/.claude/skills/meeting/broker-curl.sh "$MEETING_BROKER_PORT" <sid> status` — if the response contains `"subscribers"`, store as `<port>` and **skip** the lazy-connect below. The launcher (`meeting-rpg`) exports this and writes the matching `web/config.json`; when present and live it is authoritative, so the renderer and the skill never diverge onto different brokers. (This avoids reading a stale `broker.json` left by a since-dead ephemeral-fallback broker.)
   - **Lazy-connect (fallback):** only if `<port>` still unset, read `jq -r .port /tmp/meeting-rpg/broker.json` — if present, store as `<port>`; otherwise clear `<port>`.
   - **Probe liveness (if `<port>` set):** call `~/.claude/skills/meeting/broker-curl.sh <port> <sid> status` — if response contains `"subscribers"`, daemon is live; otherwise clear `<port>`.
   - **Self-start (MEETING_LIVE=1 only, if `<port>` still unset):** spawn `python3 ~/.claude/skills/meeting/broker.py` with `run_in_background=true`; poll `jq -r .port /tmp/meeting-rpg/broker.json` (≤3s) until port appears; store as `<port>`. Advertise: print `http://127.0.0.1:<port>/events?session=<sid>` and `curl -N http://127.0.0.1:<port>/events?session=<sid>` for a second terminal.
   - **If `<port>` unset after all steps:** note "no broker found, running as canonical /meeting" in chat; continue without broker for the rest of the session.

## With a subject argument

1. **Warrantability self-check** (see format spec). If the request looks like a bug fix, one-liner, or already-decided feature, respond "are you sure you want a meeting?" and briefly explain why it might be overkill — before running the agenda. If it clearly passes, note that and proceed.
2. **Past-meetings audit (ADVISORY — observation window)**: run `~/.claude/skills/meeting/orphan-scan.sh`. Uses exact `<!-- id:XXXX -->` match; FP is ~0 by construction (un-IDed legacy lines skipped). Display any candidates labeled `ADVISORY — not yet authoritative` before opening the agenda. Once zero spurious candidates are confirmed over an observation window of N meetings, drop the ADVISORY caveat and treat output as authoritative. *(F-B shipped 2026-05-21; prior DISABLED state lifted.)*
3. Call `EnterPlanMode`. Accumulate the transcript in the plan file the system creates.
4. **Run the interactive meeting**: open with attendees line + topic, then follow the format spec (agenda → named discussion → decision points → decisions → action items).
   - **At the start of each agenda item**, if `<port>` is set, poll `~/.claude/skills/meeting/broker-curl.sh <port> <sid> status` and store the returned `subscribers` count. Use this count for both the discussion and the decision point of that item (re-poll only if renderer attachment may have changed).
   - **Discussion (persona lines):** Controlled by `subscribers`:
     - `subscribers > 0` (renderer attached): POST one batched block per agenda item to `/event` **only** — do **not** print the verbatim discussion to chat. The user reads discussion in the renderer. Single call: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> event '{"text":"<escaped block>"}'`.
     - `subscribers = 0` (headless) or `<port>` unset: print the **complete, verbatim discussion** to chat as in canonical `/meeting`; **skip** the `/event` POST (no listener).
   - **Decision point:** Controlled by `subscribers`:
     - `subscribers > 0`: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> question '<json>'`; `~/.claude/skills/meeting/broker-curl.sh <port> <sid> await`; map returned `answer` to the options list. Do **not** print transcript to chat.
     - `subscribers = 0` or `<port>` unset: print complete verbatim transcript to chat, then use AskUserQuestion as normal.
5. **Transcript-visibility rule** — the user must be able to read the verbatim discussion before each decision. When `subscribers > 0`, the renderer feed satisfies this (chat suppression is intentional — this is the source of the token savings). When headless, chat output satisfies it. If `subscribers` flips mid-meeting, the rule applies to the current count at the start of each agenda item.
6. Proceed to end-of-meeting steps.

## With no subject (default mode)

1. Read `<root>/TODO.md`. Run `~/.claude/skills/meeting/orphan-scan.sh` (**ADVISORY — observation window**): display any candidates before the classifier output as `ADVISORY — orphan scan candidates (informational; exact-ID match, un-IDed legacy skipped)`. Not authoritative until observation window clears. *(F-B shipped 2026-05-21; prior DISABLED state lifted.)*

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
   - Class 1 → proceed to implementation in normal mode (no plan mode, no meeting). Broker not started.
   - Class 2 → call `EnterPlanMode`; use Claude Code's native explore → design → present → ExitPlanMode workflow. No persona scaffolding. Broker not started. After `ExitPlanMode` and implementation: write a **Class 2 planning record** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` using the Class 2 template defined in `format.md`. Content synthesises the plan file; plan file is left to Claude Code's auto-cleanup.
   - Class 3 → proceed as if `/meeting-live <candidate>` was invoked (full meeting flow, broker started per step 7).
   On "pick something else": re-ask with the next candidate.

## End-of-meeting steps

1. **Write meeting note** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`. Use the captured date, HHMM, and slug derived from the meeting title. Include `**Started:**` and `**Session:**` header lines populated with the captured literals.
1b. **Mirror action items to TODO.md** (Step 5b): before calling ExitPlanMode, add every `## Action items` entry that will outlive this session to `<root>/TODO.md` (create a new section if needed; write only to `<root>/TODO.md` — never to a parent-path file). Each entry must cite the meeting-note path. **For each item, mint a unique ID via `~/.claude/skills/meeting/append.sh new-id` and embed it as `<!-- id:XXXX -->` at the end of the line in the meeting note AND in the TODO.md entry** (same token in both). The first invocation of this session that creates meeting-note items should call `append.sh new-id` once per item before writing. In-session ad-hoc items (resolved before ExitPlanMode) skip ID minting — they never reach TODO. Purpose: orphan-scan uses this `<!-- id:XXXX -->` for exact correlation; un-IDed lines are skipped (clean cutover). Class 2 planning records skip this step — their action items are resolved in-session by implementation.
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
| Broker up, `subscribers=0` | Chat only | AskUserQuestion (headless) |
| Broker up, `subscribers>0` | `/event` only (chat suppressed) | POST `/question` + GET `/await` |
| Broker unavailable | Chat only | AskUserQuestion |

Broker endpoints (all at `http://127.0.0.1:<port>`):
- `GET /status?session=<sid>` → `{"subscribers": N}`
- `POST /event` body `{"text": "...", "session": "<sid>"}` → streams to renderer
- `POST /question` body `{"text": "...", "options": [...], "session": "<sid>"}` → sends decision prompt to renderer
- `GET /await?session=<sid>` → blocks until renderer POSTs `/response`; returns `{"answer": "..."}`
- `POST /response` body `{"answer": "...", "session": "<sid>"}` → renderer submits an answer, unblocks `GET /await` (broker.py:49-53). Manual test: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> response '{"answer":"<choice>"}'`
- `GET /events?session=<sid>` → SSE stream

**Debug recipe (readable event tail):**
```bash
~/.claude/skills/meeting/broker-curl.sh <port> <sid> events | while read line; do echo "$line" | sed 's/^data: //' | jq -r '.text // .'; done
```
Raw SSE emits `data: <json>` — the recipe strips the prefix and extracts `.text` for human-readable tailing in a second terminal.

**All broker calls use `broker-curl.sh` — never raw curl to 127.0.0.1.** This keeps the allowlist to one entry: `Bash(~/.claude/skills/meeting/broker-curl.sh *)`.
