# @manual BDD automation triage — 2026-06-13

~129 `@manual` BDD scenarios across 20 feature files, classified by automatability so the
backlog isn't treated as one immovable manual wall. Source: triage agent over all feature
files + repo stacks. Tiers: **T1** automatable now (CLI/HTTP/file, no harness) · **T2**
harness-needed (browser/TUI) · **T3** fixture/env-gated (ROM/device/Pi/firmware) · **T4**
irreducibly manual (real camera/mic/CAPTCHA, or live-Claude/config by convention).

## Totals
| Tier | Count | Disposition |
|---|---|---|
| T1 automatable-now | 21 | `[ROUTINE]` items → relay executors write subprocess tests |
| T2 harness-needed | 29 | `[HARD]` items → stand up one Playwright + Textual pilot, then convert |
| T3 fixture/env-gated | 17 | recorded; automate when the fixture lands |
| T4 truly-manual | 62 | minimized per-device human checklist (~14 are "manual by convention") |

## Per-repo
| repo / file | stack | T1 | T2 | T3 | T4 | disposition |
|---|---|--:|--:|--:|--:|---|
| project_manager/proj_cli | cli | 6 | – | – | 1 | T1 [ROUTINE] (scratch-config subprocess; pytest harness already exists) |
| zkm/cli-journeys | cli | 5 | 1 | – | 3 | T1 [ROUTINE] (mock server / lockfiles / doctor) |
| zelegator/cli | cli | 5 | 1 | – | 3 | T1 [ROUTINE] (keyword/rule paths, no live LLM) |
| ai-codebench/dashboard | cli | 2 | – | 1 | – | T1 [ROUTINE] (regenerate + loop-badge grep) |
| ai-codebench/tui | tui | – | 6 | – | – | T2 [HARD] (Textual `pilot` harness — built-in, no dep) |
| collaib/observer | web | – | 7 | – | 2 | T2 [HARD] (Playwright + mock OpenAI SSE server) |
| puzzle-pwa/journeys | web | – | 9 | – | 2 | T2 [HARD] — **id:41ef** exists |
| cyclotomic/grid-ui | web | – | 5 | – | 3 | T2 [HARD] — **id:71ee** exists (SVG, lighter) |
| isochrone/manual-journeys | web | – | 1 | – | 3 | low ROI (1 T2) — deferred; note only |
| romtrans/m1_translate | cli | – | – | 5 | 1 | T3 — needs retail OoT ROM + API key; in-emulator visual check stays T4 |
| droidclaw/http_api_e2e | android | – | – | 5 | 1 | T3 — needs device or mock engine; Telegram leg T4 |
| droidclaw/chat_ui | android | – | – | – | 4 | T4 — native ARM64 + Compose, no emulator path |
| rawrora/aurora_capture | android | – | – | – | 7 | T4 — physical camera/gyro |
| zomAI/voice_assistant | web | (3) | – | 3 | 1 | T3 — Pi + whisper/Piper/Ollama; mic recording T4 |
| proton-moresync/backup | cloud | – | – | 1 | 4 | T4 — live Proton account + CAPTCHA |
| helferli/voice-journey | firmware | – | – | – | 5 | T4 — physical VoCat, real mic/speaker |
| helferli/ota-disable | firmware | – | – | 3 | – | T3 — flashed firmware + serial console |
| dotclaude-skills/install | cli | – | – | – | 3 | T4 by convention — **already covered** by tests/test_makefile_skills.sh (DEST_DIR) |
| dotclaude-skills/meeting | cli | – | – | – | 5 | T4 — live Claude skill invocation |
| dotclaude-skills/relay-executor | cli | – | – | – | 3 | T4 — live executor+reviewer sessions |

## Conquer order
1. **T1 now** — `[ROUTINE]` items in project_manager, zkm, zelegator, ai-codebench(dashboard); the self-looping relay drains them (executors write the tests). Remove `@manual` from converted scenarios.
2. **T2 harness** — `[HARD]` items: Textual `pilot` for ai-codebench/tui; Playwright for collaib (puzzle-pwa id:41ef + cyclotomic id:71ee already filed). isochrone (1 scenario) deferred.
3. **T3** — leave `@manual`, note the fixture blocker; automate when the ROM/device/Pi/firmware is present (romtrans, droidclaw API, zomAI, helferli OTA).
4. **T4** — minimized per-device manual lane; the dotclaude-skills "convention" ones are largely redundant with existing bash suites.
