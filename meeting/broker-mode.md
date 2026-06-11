# Broker mode

Loaded by `/meeting` step 7 only when `$MEETING_LIVE` is set or a renderer is detected. Describes what changes when a broker is active. Everything else (setup steps 1–6, meeting flow, end-of-meeting steps) is canonical SKILL.md — do not restate it here.

## Step 7 — connect to broker

Only on Class 3 / subject-given paths (not Class 1/2 dispatch).

- **Probe the flag with `echo "$MEETING_LIVE"`** (plain expansion). Do **not** use `${MEETING_LIVE:-unset}` or any `${VAR:-default}` form — default-expansion syntax triggers the Bash parameter-expansion permission prompt as a class, regardless of allowlist. `1` = opt-in self-start; empty or `0` = lazy-connect only (never spawns a process). Tuning: `MEETING_BROKER_PORT` (default 64109), `MEETING_BROKER_IDLE` (idle-shutdown seconds; 0=never).
- **Authoritative port (launcher contract):** probe `echo "$MEETING_BROKER_PORT"` (plain expansion). If set, liveness-probe it via `~/.claude/skills/meeting/broker-curl.sh "$MEETING_BROKER_PORT" <sid> status` — if the response contains `"subscribers"`, store as `<port>` and **skip** the lazy-connect below. The launcher (`meeting-rpg`) exports this and writes the matching `web/config.json`; when present and live it is authoritative, so the renderer and the skill never diverge onto different brokers. (This avoids reading a stale `broker.json` left by a since-dead ephemeral-fallback broker.)
- **Lazy-connect (fallback):** only if `<port>` still unset, read `jq -r .port /tmp/meeting-rpg/broker.json` — if present, store as `<port>`; otherwise clear `<port>`.
- **Probe liveness (if `<port>` set):** call `~/.claude/skills/meeting/broker-curl.sh <port> <sid> status` — if response contains `"subscribers"`, daemon is live; otherwise clear `<port>`.
- **Self-start (`MEETING_LIVE=1` only, if `<port>` still unset):** spawn `python3 ~/.claude/skills/meeting/broker.py` with `run_in_background=true`; poll `jq -r .port /tmp/meeting-rpg/broker.json` (≤3s) until port appears; store as `<port>`. Advertise: print `http://127.0.0.1:<port>/events?session=<sid>` and `curl -N http://127.0.0.1:<port>/events?session=<sid>` for a second terminal.
- **If `<port>` unset after all steps:** note "no broker found, running as canonical /meeting" in chat; continue without broker for the rest of the session.

## Discussion and decision-point routing

At the start of each agenda item, if `<port>` is set, poll `~/.claude/skills/meeting/broker-curl.sh <port> <sid> status` and store the returned `subscribers` count. Use this count for both the discussion and the decision point of that item (re-poll only if renderer attachment may have changed).

**Shell-quoting rule — apostrophes in text content break single-quoted literals.**
Always build the JSON body with `jq -n --arg` so text containing `'` (e.g. "flock'd", "don't") is safely escaped:
```bash
BODY=$(jq -n --arg text "<block>" '{"text": $text}')
~/.claude/skills/meeting/broker-curl.sh <port> <sid> event "$BODY"
```
Never pass a raw single-quoted JSON literal when the text is user- or persona-controlled.

**Discussion (persona lines):**
- `subscribers > 0` (renderer attached): POST a parseBlock-visible **opener stub first** to mark t0, then **compose-and-POST each persona line individually** (compose → POST → compose → next), so the renderer paints each line as it is authored. Do **not** print the verbatim discussion to chat. The opener must be a dialogue line (emoji + `**Name:**` format) — not a `#` heading or `**Key:**` metadata line (those are skipped by `parse.js`). Include `"kind":"opener"` in the opener body for TTFL logging. Example:
  ```bash
  OPENER=$(jq -n --arg text "🏗️ **Archie:** *(opening <item>)*" '{"text":$text,"kind":"opener"}')
  ~/.claude/skills/meeting/broker-curl.sh <port> <sid> event "$OPENER"
  # Then for each persona line — compose the line, POST immediately, then compose the next:
  LINE=$(jq -n --arg text "🏗️ **Archie:** <line text>" '{"text":$text}')
  ~/.claude/skills/meeting/broker-curl.sh <port> <sid> event "$LINE"
  LINE=$(jq -n --arg text "😈 **Riku:** <line text>" '{"text":$text}')
  ~/.claude/skills/meeting/broker-curl.sh <port> <sid> event "$LINE"
  # ... one POST per persona line (never batch the block)
  ```
- `subscribers = 0` (headless) or `<port>` unset: print the **complete, verbatim discussion** to chat as in canonical `/meeting`; **skip** the `/event` POST.

**Decision point:**
- `subscribers > 0`: build JSON with `jq -n --arg`, e.g. `BODY=$(jq -n --arg text "<question>" --argjson options '<options-array>' '{"text":$text,"options":$options}')`, then `~/.claude/skills/meeting/broker-curl.sh <port> <sid> question "$BODY"`; `~/.claude/skills/meeting/broker-curl.sh <port> <sid> await`; map returned `answer` to the options list. Do **not** print transcript to chat.
- `subscribers = 0` or `<port>` unset: print complete verbatim transcript to chat, then use AskUserQuestion as normal.

**Transcript-visibility rule:** the user must be able to read the verbatim discussion before each decision. When `subscribers > 0`, the renderer feed satisfies this (chat suppression is intentional — source of the token savings). When headless, chat output satisfies it.

## γ-branch reference

| State | Discussion | Decision point | End-of-meeting prompts (steps 3–5) |
|---|---|---|---|
| `MEETING_LIVE=0` | Chat only | AskUserQuestion | AskUserQuestion |
| Broker up, `subscribers=0` | Chat only | AskUserQuestion (headless) | AskUserQuestion (per-prompt re-probe) |
| Broker up, `subscribers>0` | opener stub + per-line `/event` (chat suppressed) | POST `/question` + GET `/await` | POST `/question` + GET `/await` (per-prompt re-probe) |
| Broker unavailable | Chat only | AskUserQuestion | AskUserQuestion |

Broker endpoints (all at `http://127.0.0.1:<port>`):
- `GET /status?session=<sid>` → `{"subscribers": N}`
- `POST /event` body `{"text": "...", "session": "<sid>"}` → streams to renderer
- `POST /question` body `{"text": "...", "options": [...], "session": "<sid>"}` → sends decision prompt to renderer
- `GET /await?session=<sid>` → blocks until renderer POSTs `/response`; returns `{"answer": "..."}`
- `POST /response` body `{"answer": "...", "session": "<sid>"}` → renderer submits an answer, unblocks `GET /await`. Manual test: `BODY=$(jq -n --arg answer "<choice>" '{"answer":$answer}'); ~/.claude/skills/meeting/broker-curl.sh <port> <sid> response "$BODY"`
- `GET /events?session=<sid>` → SSE stream

**Debug recipe (readable event tail):**
```bash
~/.claude/skills/meeting/broker-curl.sh <port> <sid> events | while read line; do echo "$line" | sed 's/^data: //' | jq -r '.text // .'; done
```

**All broker calls use `broker-curl.sh` — never raw curl to 127.0.0.1.** This keeps the allowlist to one entry: `Bash(~/.claude/skills/meeting/broker-curl.sh *)`.

## End-of-meeting prompt routing

Steps 3 (profile), 4 (memory), and 5 (persona-registry) in `SKILL.md` use `AskUserQuestion` by default. When `<port>` is set, apply the γ-branch **per prompt** — re-probe `/status` before each one:

1. **Re-probe:** `~/.claude/skills/meeting/broker-curl.sh <port> <sid> status` → get `subscribers`.
2. **`subscribers > 0`:** build question JSON with `jq -n` (same escaping rules as in-meeting decision points), POST `/question`, GET `/await`, map `answer` to the options list — proceed with the matching action.
3. **`subscribers = 0` or probe fails:** fall through to `AskUserQuestion` as canonical.

**If `<port>` unset:** skip all probes; use `AskUserQuestion` exclusively (no behaviour change).

**Options per prompt:**

| Step | `text` | `options` array |
|---|---|---|
| 3 — Profile observation | `"Profile observation: <observation>"` | `["save to user-profile", "save to user-memory", "discard"]` |
| 4 — Memory classification | `"Memory: <decision or finding>"` | `["project", "discovery", "universal", "discard"]` |
| 5 — Persona registry | `"New persona: <Name>"` | `["save to global registry", "meeting-only"]` |

For step 4 with multiple decisions/findings: issue one `/question` + `/await` per item, re-probing `/status` each time.

**Example (step 3 — profile):**
```bash
BODY=$(jq -n --arg text "Profile observation: prefers phase-gated scope" \
  --argjson options '["save to user-profile","save to user-memory","discard"]' \
  '{"text":$text,"options":$options}')
~/.claude/skills/meeting/broker-curl.sh <port> <sid> question "$BODY"
~/.claude/skills/meeting/broker-curl.sh <port> <sid> await
# map returned {"answer": "save to user-profile"} → proceed with user-profile action
```
