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

**Discussion (persona lines):**
- `subscribers > 0` (renderer attached): POST one batched block per agenda item to `/event` **only** — do **not** print the verbatim discussion to chat. Single call: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> event '{"text":"<escaped block>"}'`.
- `subscribers = 0` (headless) or `<port>` unset: print the **complete, verbatim discussion** to chat as in canonical `/meeting`; **skip** the `/event` POST.

**Decision point:**
- `subscribers > 0`: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> question '<json>'`; `~/.claude/skills/meeting/broker-curl.sh <port> <sid> await`; map returned `answer` to the options list. Do **not** print transcript to chat.
- `subscribers = 0` or `<port>` unset: print complete verbatim transcript to chat, then use AskUserQuestion as normal.

**Transcript-visibility rule:** the user must be able to read the verbatim discussion before each decision. When `subscribers > 0`, the renderer feed satisfies this (chat suppression is intentional — source of the token savings). When headless, chat output satisfies it.

## γ-branch reference

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
- `POST /response` body `{"answer": "...", "session": "<sid>"}` → renderer submits an answer, unblocks `GET /await`. Manual test: `~/.claude/skills/meeting/broker-curl.sh <port> <sid> response '{"answer":"<choice>"}'`
- `GET /events?session=<sid>` → SSE stream

**Debug recipe (readable event tail):**
```bash
~/.claude/skills/meeting/broker-curl.sh <port> <sid> events | while read line; do echo "$line" | sed 's/^data: //' | jq -r '.text // .'; done
```

**All broker calls use `broker-curl.sh` — never raw curl to 127.0.0.1.** This keeps the allowlist to one entry: `Bash(~/.claude/skills/meeting/broker-curl.sh *)`.
