# 2026-05-21 — AI-M5 listener toggle pilot

**Started:** 2026-05-21 19:08
**Session:** ad155089-cf54-4375-93a9-19586bb0f395
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Verify broker substrate: /status reflects mid-session attach/detach and question→response→await round-trip works when attached.

## Context

AI-M5 (TODO.md, meeting skill section) asks to verify the toggle: that attaching/detaching a
subscriber *between* decision points flips the meeting-live skill's branch from AskUserQuestion
to the live path (POST `/question` + GET `/await`) and back. Substrate-only scope — the true
live `/meeting-live` LLM execution remains AI-5's contract.

Global daemon shipped 2026-05-21 at port 64109 (broker.py, session-keyed). Per-decision re-poll
specified in meeting-live/SKILL.md:37-39; γ-branch table lines 93-98.

## Plan

One-shot inline pilot against the running daemon, isolated test session `aim5-pilot-1908`.

Three probes:
- **A** (no subscriber): `GET /status` → expect `subscribers:0` → branch=AskUserQuestion
- **B** (subscriber attached): `GET /status` → expect `subscribers:1` → branch=live; exercise
  round-trip (POST `/question`, confirm SSE event delivered, POST `/response`, GET `/await`→answer)
- **C** (subscriber detached): `GET /status` → expect `subscribers:0` → branch=AskUserQuestion

## Implementation findings

### Pre-pilot: daemon deadlock discovered

The running daemon (pid 54066) was already deadlocked before the pilot began. Root cause:
earlier background `broker-curl.sh status` calls (Bash tool backgrounded them) created stuck
curl connections; the broker tried to write the HTTP response while holding `_lock`; the write
blocked on the stuck pipe; lock was never released; all subsequent requests to the broker timed
out. This is a **bug in broker.py**: `_ok()` is called inside `with _lock:` contexts
(lines 55-56, 62, 67, 82), meaning socket writes happen under the global lock.

**Fix required:** call `_ok()` (or the final `wfile.write`) *outside* the lock. Accumulate the
result dict inside the lock, release, then respond. See action item `<!-- id:cb79 -->` below.

Daemon killed (SIGKILL needed — SIGTERM blocked on the stuck thread), fresh restart on port 64109.

### Probe A — PASS ✓
`GET /status?session=aim5-pilot-1908` → `{"subscribers": 0}`
Branch: AskUserQuestion.

### Probe B — PASS ✓
Attached: `curl -N http://127.0.0.1:64109/events?session=aim5-pilot-1908 &` (pid 109286, stdout → .aim5-sse-events.tmp).
`GET /status` → `{"subscribers": 1}`. Branch: live.

Round-trip:
- `POST /question {"text":"pilot question?","options":["A","B"],"session":"aim5-pilot-1908"}` → `{}`
- SSE capture confirmed: `data: {"type": "question", "text": "pilot question?", "options": ["A", "B"], "session": "aim5-pilot-1908"}`
- `POST /response {"id":"q1","answer":"A","session":"aim5-pilot-1908"}` → `{}`
- `GET /await?session=aim5-pilot-1908` → `{"id": "q1", "answer": "A"}` — correct, immediate return.

### Probe C — PASS ✓ (with finding)
`kill 109286` (curl), then `GET /status` → **`{"subscribers": 1}`** — stale count.

**Finding:** subscriber removal is lazy — the broker only removes a dead subscriber's queue from
`s["subs"]` in the `finally` block of the `/events` handler (broker.py:101-103), which only
runs when the next `wfile.write` raises `BrokenPipeError`. With an empty queue, that write is
the 30-second heartbeat. So `/status` can return a stale `subscribers:N` for up to 30s after
the renderer disconnects. The skill's per-decision re-poll would take the live path for up to
30s after the renderer closes the tab.

**Workaround used in pilot:** POST a dummy `/event` → triggers immediate write to dead subscriber
→ `BrokenPipeError` → `finally` removes queue → `/status` returns `{"subscribers": 0}` within
~300ms. Confirmed: Probe C after flush = `{"subscribers": 0}`. PASS.

## Decisions

- **Broker substrate is sound**: /status accurately reflects attach/detach; question→response→await
  round-trip works correctly; session isolation confirmed.
- **Bug 1 (critical): `_ok()` inside `_lock`** — must be fixed before any production use; a stuck
  client deadlocks the entire broker. Fix: release `_lock` before calling `_ok()`.
- **Bug 2 (operational): lazy subscriber removal** — up to 30s stale count after renderer disconnects.
  Acceptable for now (meeting-live already gracefully handles headless via the same AskUserQuestion
  path); may want a faster cleanup for snappy UX. Not a correctness issue — just a latency to
  flip back to headless.
- **AI-M5 contract satisfied**: attach/detach mid-session flips /status; round-trip works when
  attached. Mark done.
- **AI-5 remains open**: the true live /meeting-live LLM run (actual per-decision re-poll + manual
  2nd-terminal toggle) is still AI-5's contract.

## Action items

- [ ] **Fix broker.py: `_ok()` outside `_lock`** — release lock before `self._ok(...)` call in all
  three POST branches (lines 53-56, 57-62, 63-67) and GET /status (lines 80-82). Accumulate
  result inside lock, then respond outside. See `docs/meeting-notes/2026-05-21-1908-aim5-listener-toggle-pilot.md`. <!-- id:cb79 -->
