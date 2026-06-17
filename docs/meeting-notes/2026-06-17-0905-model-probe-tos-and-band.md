# 2026-06-17 — Model-probe ToS pre-check + acceptance-band pre-registration (id:2d01, id:23e9)

**Started:** 2026-06-17 09:05
**Session:** 75c84d29-8dee-4cc9-b325-1d846721b98b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 📊 Cal (calibration/UQ), 📊 Lexi (Lean Six Sigma / SPC — re-onboarded), 🔭 Otto (observability), ⚙️ Sage (skill-runtime / invocation), ⚖️ Cleo (platform-ToS legality — re-onboarded)
**Topic:** Resolve the BLOCKING invocation-path ToS pre-check (id:2d01) and pre-register the acceptance band for the standing model-probe (design half of id:23e9), so build (id:c345/id:040a) can proceed on the right path.

## Surfaced discoveries
- [2026-06-17 dotclaude-skills] Relay discovery shards silently inherited the Opus session model — a tier omission cost ~35% of relay spend (id:c3a6). Precedent: silent model-tier behaviour is real and costly here — the very thing the probe exists to catch.

## Setup findings (pre-agenda — ToS research performed this session)

Source documents fetched live (not from memory) this session:
- **Consumer Terms §3** (anthropic.com/legal/consumer-terms): prohibits accessing the Services "through automated or non-human means, whether through a bot, script, or otherwise" — **"Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it."**
- **Claude Code headless docs** (code.claude.com/docs/en/headless): `claude -p` non-interactive mode is an officially documented, supported feature for scripts/CI/CD (shown in `package.json` lint scripts, build scripts, CI/CD pipelines). → satisfies the "where we otherwise explicitly permit it" limb. `--bare` is "the recommended mode for scripted and SDK calls."
  - **Critical coupling:** "Bare mode skips OAuth and keychain reads. Anthropic authentication must come from `ANTHROPIC_API_KEY` or an `apiKeyHelper`." → `--bare` (the harness-free mode) REQUIRES an API key. Subscription OAuth cannot run bare.
  - `--output-format json` returns `total_cost_usd` + per-model cost breakdown; `system/init` event reports resolved model string — useful for D2 frontend-metadata capture.
- **Usage Policy** (anthropic.com/legal/aup): no restriction on benchmarking / evaluation / quality-measurement. Only relevant bar is "model scraping/distillation" = using outputs to TRAIN a competing model (not our use case).
- **Commercial Terms §D.4** (API): bars using the API to "build a competing product or service, including to train competing AI models." Internal self-monitoring is neither.

**Net:** both invocation shapes are in-bounds for low-volume self-monitoring. New lever the research surfaces: `--bare` (the harness-free, same-result-on-every-machine mode) requires an API key, so the ToS-clean path and the measurement-clean path coincide on path B. This was the basis of the room's initial recommendation, but the user improved on it (see Agenda 1 decision).

## Agenda
1. (id:2d01) Invocation path — given both A and B are in-bounds, and `--bare` (the harness-free measurement mode the probe wants) forces an API key, which path is the DEFAULT and what is the residual ToS posture?
2. (id:23e9, design half) Pre-register the acceptance band: pass-rate floor + latency/throughput band, before any data exists. Seeding deferred (build-blocked on id:c345/id:040a).

## Discussion

### Agenda 1 (id:2d01): invocation path — default + residual posture

⚙️ **Sage:** The note flagged this as gated, not bakeable, and the live read settles it: `claude -p` is not a gray-area "script hitting the consumer endpoint" — Anthropic documents it as a first-class scripting/CI feature, which is exactly the "where we otherwise explicitly permit it" carve-out in Consumer Terms §3. So path A isn't *prohibited*. But the thing I didn't know yesterday and the docs make explicit: `--bare` — the recommended scripted mode, the one that strips CLAUDE.md/hooks/skills so you measure the model and not my own `~/.claude` — *requires* `ANTHROPIC_API_KEY`. It skips OAuth/keychain entirely. You cannot have harness-free measurement on a subscription. That collapses the choice.

⚖️ **Cleo:** Agreeing on the legality gradient. Consumer Terms §3 names two exits from the automation ban: API key (verbatim), or explicit permission (interpretive). Path B sits on the *first, unambiguous* exit — the API-key limb is named verbatim. Path A sits on the *second, interpretive* limb — "explicitly permit it," which the headless docs support but which is a reading, not a quote. The Usage Policy adds nothing against us (only model-scraping-to-train is barred, which we aren't), and Commercial §D.4 only bars building a competing model. So the risk gradient is: B = clean on the named limb; A = defensible on the interpretive limb. For low-volume on-demand, A's residual risk is small — but B removes the interpretation entirely. When one path needs no lawyering, take it.

🔭 **Otto:** And B is also the *better instrument*, independently of ToS. The whole point of the probe is zero-perturbation measurement of the model. Subscription `claude -p` loads `~/.claude` — my hooks, the user's CLAUDE.md, auto-memory — into every probe item. That's the harness contaminating the measurement, the exact thing Riku guarded against in D2 ("keep each prompt bare so we measure the model, not the harness"). `--bare` IS that guard, mechanized. The ToS-clean path and the measurement-clean path are the same path.

🏗️ **Archie:** Concretely, then: the invocation function becomes `claude --bare -p "<item>" --output-format json` with `ANTHROPIC_API_KEY` in the env. `--output-format json` hands us `total_cost_usd` + per-model breakdown and the `system/init` model id for free — feeds D2's frontend-metadata line directly. The swappable-function design still holds: A stays implementable behind the same interface as a fallback if someone has no API key.

😈 **Riku:** Two costs on B. (1) B spends real money per token instead of subscription quota — pennies for the seed, but log `total_cost_usd` so it never silently grows. (2) The bigger trap: if B uses the API and A uses the harness, they are *not the same model-serving path*. The probe measures whatever path it runs on. So pin it: B measures the **API** serving path. That's honest and sufficient — but write in the note that the probe's verdict is scoped to the API serving path, not "Opus the platform."

✂️ **Petra:** Decided, not deliberated. Both in-bounds; B cleaner on ToS AND measurement AND gives free cost/metadata; A retained as contaminated fallback behind the same function. N=2 consumers (B default, A fallback) — the swappable abstraction earns itself.

**[Zommuter — decision on Agenda 1]:** Path **A**, but improved: run `claude -p` as a **separate OS user with a specifically-crafted or empty `~/.claude`**. That gives harness-free measurement by *isolation* (the probe user loads only an empty/minimal config) rather than by `--bare`+API-key — keeping subscription quota (no per-token billing) and the "explicitly permitted" ToS limb. Plus a new TODO to file: consider running Claude generally — or at least in `/relay` mode — as a separate OS user so even auto-mode can't break anything beyond that user's permissions (needs group setup on `~/src` etc). That's its own **sandboxing meeting** — file it for later.

🔭 **Otto:** The user's option is strictly better for *this* question: the original incident (id:dba3) happened on an **interactive subscription** Opus session. The "B measures the API not the subscription" caveat cuts *against* B — path A under a clean probe-user measures the very serving path that exhibited the problem. Isolation-by-empty-`.claude` removes the harness contamination, while keeping fidelity to the incident.

😈 **Riku:** Then my scoping caveat flips to a feature, not a wart: the probe's verdict is explicitly scoped to the **subscription serving path** — which is the path we actually care about. Guards that survive: (1) the probe user's `~/.claude` must be *verified empty/minimal* at run time — assert it, or the config is empty by construction; (2) record which OS user + config-hash produced each sample; (3) path B (API key) stays behind the same swappable function. N=2 survives (A-isolated primary, B latent).

✂️ **Petra:** Scope holds. The sandboxing/separate-user-for-relay idea is a bigger surface (group perms on `~/src`, write-isolation, polkit) — correctly punted to its own meeting. For *this* build, the only delta vs. the prior note is: invocation = `claude -p` run as a dedicated probe user with an empty `~/.claude`; no `--bare`, no API key required; verdict scoped to subscription serving path; D6 swappable function unchanged.

### Agenda 2 (id:23e9, design half): pre-register the acceptance band

📊 **Cal:** D3's non-negotiable was *pre-register before data so we can't move goalposts*. The honest move: commit the **decision rule** (seed-data → flag function), not a guessed number. Numbers fall out of the seed mechanically; nobody re-picks the formula after seeing the seed.

📊 **Lexi:** Textbook SPC — each tier is its own process (Opus/Sonnet/Haiku have different pass profiles and wildly different tok/s; never pool). Pass/fail → **c-chart** (count of failed items per run). Throughput → individuals chart. But ±3σ from ~5 seed points is fantasy precision. Start with a wide robust band; tighten only once enough runs accumulate.

📊 **Cal:** Items are timeless/deterministic → healthy tier passes ≈ all, baseline near ceiling. On a 15–20 binary battery, a **1-item swing is noise; 2 items is signal**. Pre-registered rule: per tier, baseline = seed pass-count; **flag if a run drops ≥2 items below baseline**, AND only on **2 consecutive runs** (D3). A c-chart with the control limit pinned at baseline+2 defects — no fake σ.

🔭 **Otto:** Throughput is the *weak* silent-swap hedge, not a gate — say so loudly. Pre-register **advisory**: center = median tok/s over seed, band = **median ± 30%** (wide on purpose; tighten to ±3·MAD once ≥20 runs). Latency: capture, band loosely, **never gate on alone** (network/queue-contaminated).

😈 **Riku:** Guards: (1) band is **per battery-version** — any battery edit resets baseline to empty; no baseline ⇒ can only seed, cannot flag. (2) "≥2 items, 2 consecutive" is the *whole* rule — no human "looks borderline" override (reintroduces the n=4-anecdote failure mode that started id:dba3). (3) Seed = **5 cold runs/tier** (minimal, fixed in advance; tightens as runs accumulate; needs to be right on day one only in the sense that it's FIXED, not OPTIMAL).

✂️ **Petra:** Hard scope line: this meeting **pre-registers the rule; it does NOT seed.** Seeding is build-blocked on id:c345 + id:040a. Out of scope: LLM-judge, dashboard, auto-rollback, auto-tightening, long-context paired variant (v2).

🏗️ **Archie:** The D2 log schema carries everything the rule needs. The band-rule is a reader over `~/.claude/logs/model-probe.jsonl` grouped by `(model, battery_version)`. Formula goes into this note verbatim so the future seed-and-close step is mechanical, not a re-litigation.

**[Zommuter — decision on Agenda 2]:** Ratify the c-chart + advisory-tok/s rule (Recommended).

## Decisions

- **D1 — id:2d01 (BLOCKING pre-check) RESOLVED.** Live ToS read (Consumer Terms §3, Usage Policy, Commercial §D.4, Claude Code headless docs — all fetched this session, not from memory): **both invocation shapes are in-bounds** for low-volume self-monitoring. Consumer Terms §3 carves automated use out of its ban two ways — the **API-key limb** (path B) and the **"where we otherwise explicitly permit it"** limb, which documented `claude -p` satisfies (path A). Usage Policy restricts only model-scraping/distillation-to-train; Commercial §D.4 restricts only building a competing model.
  **Chosen path: A** — subscription `claude -p`, run as a **dedicated OS user with an empty/minimal `~/.claude`**, achieving harness-free measurement by *isolation* rather than `--bare`+API-key. Rationale: keeps subscription quota (no per-token billing), stays on the documented-feature ToS limb, and is **faithful to the subscription serving path where the original id:dba3 incident occurred** (the probe measures the path that exhibited the problem). The D6 swappable invocation function is retained — path B (API key + `--bare`) stays implementable behind the same interface as a latent alternative for the API serving path.
  **Verdict scoping:** probe results are explicitly scoped to the path measured (subscription serving path under A); an A-greenlight is not proof about the API path, and vice-versa. Record OS-user + config-hash alongside each sample so path drift is detectable.
  *Out of scope (punted to its own sandboxing meeting, id:d0c0):* the broader "run Claude / `/relay` as a separate sandboxed OS user" question — needs group setup on `~/src`, write-isolation, polkit interaction.

- **D2 — id:23e9 design half RESOLVED (seeding deferred, build-blocked).** Pre-registered acceptance band, committed 2026-06-17 BEFORE any data, per model tier (Opus/Sonnet/Haiku), keyed by `(model, battery_version)`, never pooled across tiers; seed = first **5 cold runs/tier**:
  - **Pass-rate gate (load-bearing):** baseline = pass-count over the 5 seed runs (timeless/deterministic items ⇒ baseline ≈ ceiling). Flag iff a run is **≥2 items below baseline pass-count** AND that holds for **2 consecutive runs** (c-chart, control limit pinned at baseline+2 defects).
  - **Throughput (advisory only — weak silent-swap hedge):** center = median tok/s over seed runs; band = **median ± 30%**; advisory-flag on 2 consecutive out-of-band runs. Tighten to **median ± 3·MAD** once ≥20 baseline runs exist (manual review trigger, not automated).
  - **Latency:** captured and reported; **never gates** (network/queue-contaminated).
  - **Battery-version reset:** any edit to `model-probe.battery.jsonl` bumps its version and resets the baseline to empty; a `(model, battery_version)` with <5 runs can only seed, never flag.
  - **No human override:** the ≥2-item / 2-consecutive rule is the entire flag criterion — no discretionary "looks borderline" calls (that reintroduces the n=4-anecdote failure mode that started id:dba3).
  - *Out of scope:* seeding itself (gated on id:c345 + id:040a), LLM-judge, dashboard, auto-rollback, auto-tighten automation, long-context paired variant (v2).

## Action items

- [x] **id:2d01 CLOSED** — ToS finding recorded (this note). Both paths permitted; chosen = path A run as a dedicated empty-`~/.claude` OS user; verdict scoped to subscription serving path. <!-- id:2d01 -->
- [ ] **id:c345 OS-user refinement (addendum to existing build item):** the probe's invocation function must run `claude -p` **as the dedicated probe OS user with a verified empty/minimal `~/.claude`**; assert the config is empty/minimal at run time (a stray CLAUDE.md there re-contaminates); record **OS-user + config-hash** alongside each sample so config drift is detectable. Path B (API key + `--bare`) remains behind the same swappable function. <!-- id:c345 -->
- [ ] **id:23e9 — reduced to seed+close (still build-blocked on id:c345 + id:040a):** once the probe + tests land, run 5 cold seed runs per tier under the D2 pre-registered band formula, fill the per-tier baselines, then close id:dba3 with the finding written into `docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`. <!-- id:23e9 -->
- [ ] **id:d0c0 — sandboxing meeting:** hold a design meeting on running Claude — or at least `/relay` mode — as a separate OS user so auto-mode cannot break anything beyond that user's permissions (group setup on `~/src` etc., write-isolation, polkit interaction). Filed for later; not designed here. <!-- id:d0c0 -->
