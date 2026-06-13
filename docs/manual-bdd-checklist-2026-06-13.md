# Manual BDD checklist (T4) — 80-20, 2026-06-13

The ~48 irreducibly-manual `@manual` BDD scenarios (real hardware / real I/O / live cloud /
live-Claude), from `bdd-automation-triage-2026-06-13.md`. **Do the TOP 12 first** — they're
foundational: each confirms a repo's core feature or unblocks the rest of its scenarios
(no point checking edge cases before the core path works). Then the rest, **batched per
device/lane** so you knock out a device in one sitting.

## ⭐ Top 12 (highest leverage — do these first)
1. **proton-moresync** — first-run auth + CAPTCHA → backup tree is produced. *Gates the entire product; nothing else runs until auth works.*
2. **helferli (VoCat)** — single-turn: wake-word → spoken reply. *The core voice loop; every other helferli scenario builds on it.*
3. **droidclaw** — model download/load → first chat reply. *App is inert until a model loads; unblocks chat_ui + API scenarios.*
4. **rawrora** — capture button → photo saved with correct ISO/shutter. *The core capture feature.*
5. **puzzle-pwa** — drag-to-spawn a piece + edge-snap. *Core game-loop interaction (the 2 touch/offline scenarios; the other 9 are Playwright-automatable id:41ef).*
6. **zomAI** — browser mic → transcribe → assistant reply. *The one irreducible mic leg of the voice path (text/API path is T3-mockable).*
7. **droidclaw** — Telegram round-trip (OpenClaw → device → reply). *Headline integration; confirms the whole bridge.*
8. **proton-moresync** — unattended re-run (idempotent, no CAPTCHA). *Confirms it actually backs up repeatedly, not just once.*
9. **helferli** — second-turn multi-turn conversation. *Conversational core beyond single-shot.*
10. **rawrora** — recording start/stop + gyro overlay toggle. *The differentiating capture feature.*
11. **cyclotomic-projection** — two-finger pinch-zoom on a real touch device. *The one touch leg (pan/wheel/vectors are Playwright-automatable id:71ee).*
12. **romtrans** — in-emulator: walk past a sign → German text shows. *The end-to-end visual payoff confirming the whole translation pipeline (the ROM-fixture logic is T3).*

## Rest, by device/lane (batch per sitting)
### Android device (rawrora + droidclaw) — needs a physical ARM64 phone
- rawrora: live-preview aspect ratio; ISO/shutter persists across gallery; overlay-toggle visibility; developer-mode volume gesture; exposure defaults.
- droidclaw chat_ui: stop-generation mid-reply; markdown rendering; new-chat resets state.
- droidclaw: error codes / model-not-ready states (mostly T3 via mock; on-device confirm optional).

### VoCat firmware (helferli) — needs the provisioned device + mic/speaker
- silent dismiss (no reply on silence); touch-dismiss; non-speech noise gate (doesn't wake on noise).
- OTA-disable (3): boot-log shows OTA off; voice round-trip still works; factory-reset re-provisions. *(Already covered by `tools/relay/tests/test_ota_disable.py` + `test_ws_audio.py` — on-device run is confirmation only.)*

### Live Proton account (proton-moresync)
- backup-tree matches the documented standard layout; session-locked self-recovery.

### Real touch / PWA install (puzzle-pwa, cyclotomic)
- puzzle-pwa: PWA offline install + launch.
- cyclotomic: one-finger pan on touch; PWA install/offline.

### Visual sign-off (isochrone) — human eye, or a later pixel-diff harness
- e-bike vs bike isochrone containment looks right; smoke-screenshot eyeball; warped-OSM overlay legibility.

### Live-Claude / live-config (dotclaude-skills) — LOWEST priority, largely redundant
- meeting.feature (5): persona voices, decision-point flow, broker render, AskUserQuestion seq, cross-repo routing.
- relay-executor.feature (3): pick/implement/tick loop, blocked-item handling, reviewer diff audit.
- install.feature (3): `make install` against live `~/.claude`. **Already covered** by `tests/test_makefile_skills.sh` (DEST_DIR) — these `@manual` entries are documentation, not test debt; consider deleting.

## Note on T3 (fixture/env-gated, NOT in this list)
~9 of the 17 T3 scenarios are **Claude-deliverable via a mock/fixture** (mock engine for droidclaw API, synthetic mini-ROM for romtrans codec/inject, fixture `output/` tree for ai-codebench, mock model server for zomAI HTTP path) — being filed as roadmap items. Only the real-ROM/real-device/real-data verification legs land in the T4 list above.
