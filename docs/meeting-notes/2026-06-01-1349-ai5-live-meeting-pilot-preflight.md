# 2026-06-01 — AI-5 pre-flight: three defects found and fixed

**Started:** 2026-06-01 13:49
**Session:** 89d0d399-b6d5-4edc-b418-1bb224565d73
**Mode:** Class 2 planning record (no meeting was held — pre-flight investigation + fix)
**Topic:** Diagnose and repair the three defects blocking the AI-5 live-meeting pilot from satisfying its ≥5k token-savings contract.

## Context

`/meeting` no-arg classification picked **AI-5 — Pilot live meeting + merge trigger** (chosen work: unblocks the gated `/meeting-cross` implementation). AI-5's contract: *"≥1 successful live meeting whose chat-side budget (via `cost-of.sh`) is ≥5k tokens lower than a comparable canonical meeting; on success, fold `meeting-live/SKILL.md` deltas into canonical and delete the sibling."*

Investigation found the pilot could not satisfy its contract as shipped. User chose **fix-then-pilot clean**.

## Plan

1. Investigate whether the web renderer exists and is interactive (pre-condition for `subscribers > 0`).
2. Check broker.py `/status` bridging logic against how the renderer subscribes.
3. Verify `meeting-live/SKILL.md` actually produces fewer chat bytes.
4. Check the launcher invocation path.
5. Fix all defects, then hand off a pilot runbook for the user-driven fresh session.

## Implementation findings

### Defect 1 — `meeting-live/SKILL.md` never reduces chat bytes (fixed)

Step 4 originally said discussion is POSTed to `/event` *"after the verbatim transcript is already printed as visible chat text… additive channel; visible chat output unchanged."* Step 5 printed the verbatim transcript before every AskUserQuestion, "Required even in headless mode." Net chat budget: identical to canonical **plus** ~1.5–3k tokens of broker curl overhead.

**Fix:** Rewrote step 4 discussion + decision bullets with `subscribers` as the gate:
- `subscribers > 0` → POST to `/event` **only**, do **not** print discussion to chat (renderer satisfies transcript-visibility; this is the source of the savings).
- `subscribers = 0` or no broker → print verbatim discussion to chat; skip `/event`.
Rewrote step 5 as a transcript-visibility rule (renderer satisfies it when `subscribers > 0`). Updated the γ-branch reference table.

### Defect 2 — `broker.py` `/status` doesn't bridge to `"live"` session (fixed)

`/event` and `/question` POST handlers fan out to `s["subs"]` **and** `sessions["live"]["subs"]` (lines 63-66, 72-75). `/status` GET handler (lines 95-98) counted only `s["subs"]`. The web renderer subscribes as `session=live` (`app.js:50`); the skill polls `/status?session=<real-sid>` → returned 0 even with a renderer attached → γ-branch always read headless.

**Fix:** Added the same bridge to `/status`:
```python
elif p.path == "/status":
    with _lock:
        subs = len(s["subs"])
        if sid != "live":
            subs += len((sessions.get("live") or {}).get("subs", []))
    self._ok({"subscribers": subs})
```
**Verified:** broker started, `curl -N .../events?session=live` held open in background, `/status?session=testsid-123` returned `{"subscribers": 1}`. Bridge is live.

### Defect 3 — Launcher invokes canonical `/meeting` (fixed)

`meeting-rpg:112` built `f"/meeting {topic}"`. Canonical `/meeting` has no broker step, so `MEETING_LIVE=1` (line 110) was silently ignored. **Fix:** Changed to `f"/meeting-live {topic}"`. Also updated the module docstring usage lines.

### Renderer status (pre-existing, no changes)

Web renderer (`~/src/meeting-rpg/web/app.js`) is complete and interactive: subscribes to `/events?session=live`, renders discussion blocks, displays decision buttons, POSTs `/response` with `{session, id, answer}`. Decision round-trip (`/response` body carries real-sid from `/question` payload → `/await` unblocks) is correct. Launcher (`~/src/meeting-rpg/meeting-rpg`) writes `web/config.json` with broker port and serves `web/` via `python -m http.server`.

## Decisions

- **D1 — Chat suppression is the savings mechanism.** When `subscribers > 0`, discussion and decision transcript are routed to the renderer only; chat emits nothing for those turns. The meeting note still captures the full verbatim discussion (permanent record unaffected).
- **D2 — `/status` bridges `"live"` subscribers for any `sid != "live"`.** Mirrors the existing fan-out logic in POST handlers. Subscriber count from the real session + the live session combined.
- **D3 — Launcher routes to `/meeting-live`.** WIP-phase value; reverts to `/meeting` as part of the post-pilot fold-back after a successful pilot.
- **Out of scope (this session):** fold-back + sibling deletion (gated on a successful pilot); renderer changes; broker endpoint additions beyond `/status` bridge; revisiting transcript-first-reading preference (renderer satisfies it).

## Action items

- [ ] **Run the AI-5 pilot in a fresh session** — launch `~/src/meeting-rpg/meeting-rpg <multi-agenda topic>` (≥3 agenda items); confirm browser shows `⬤ live` and that discussion appears in renderer only (no chat verbatim); answer decisions via renderer buttons; let meeting complete. Measure `bash ~/.claude/skills/meeting/cost-of.sh <pilot-session-id>` vs a comparable canonical meeting; on ≥5k savings: fold `meeting-live/SKILL.md` deltas into canonical, delete `meeting-live/` sibling, mark AI-5 done. See `docs/meeting-notes/2026-06-01-1349-ai5-live-meeting-pilot-preflight.md`. <!-- id:7b4c -->
