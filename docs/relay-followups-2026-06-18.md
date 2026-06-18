# Relay gated-[HARD] follow-ups — your action reference (2026-06-18)

Companion to `docs/meeting-notes/2026-06-18-1219-cross-gated-hard-triage.md`. Lists every
item from that triage that needs *you* (a secret, hardware, sudo, a config step, or a future
decision) — what it is, the **fastest way to check it's ready**, and the **fastest way to
tackle it**. The autonomous `/relay` pool does NOT touch any of these (it skips secrets/
hardware/sudo and won't re-decide), so they sit here until you act.

## How to tackle, by type (the general rule)

| Type | Entry point | Why not the others |
|---|---|---|
| Hands-on task, decided, needs secret/hardware/sudo | **plain session, cwd = the repo, "let's tackle <id>"** | not `/meeting` (nothing to decide), not `/relay human` (no judgment box), not autonomous `/relay` (can't supply secret/hw) |
| A future design decision | `/meeting` (or `/meeting --cross`) in/over the repo | needs persona scrutiny + your ratification |
| Already-[ROUTINE]/ungated code work | `/relay` or `/relay next` (autonomous) | the pool can do it unattended |
| Externally-gated (data/adoption/time) | **nothing to run** — watch the gate | no work exists until the condition flips |

## A. EXECUTABLE — need your hands (no decision left)

Tackle each with a **plain working session, cwd in the repo, "let's do <id>"**:

| id | repo | what | what you provide / do | fastest readiness check |
|---|---|---|---|---|
| **fd1e** | zomni | CF Access app `zomni*.zommuters.net` + Pocket-ID IdP | the Cloudflare API token (secret) | always ready; use `cloudflare-tunnel-deploy` skill. Sequence after 1d14/560c for end-to-end value |
| **935e** | zomni | live gaming freeze/evict test of `zomni-gamemode` | launch DBH, run `zomni-gamemode on`, watch | script already installed (`/usr/local/bin/zomni-gamemode`); just needs a real game session |
| **9321** | zomni | XPU seed-hunt (OpenVINO GPU) — INTENSIVE | run `gen_portraits.py --pilot <persona> --openvino` on zomni's Arc; supervise (OOM-risk) | substrate done (riku locked seed 100); run the documented cmd |
| **fd30** | zomni | gemma4-e4b `--reasoning off` rollout — INTENSIVE | edit `/etc/llama-swap/config.yaml` (sudo), retire llama-3.2-3b slot, audit `ZKM_LLM_MODEL` defaults | gate passed (TTFT 21s→0.62s); watch for a project that intentionally pins llama-3.2-3b |
| **7bef** | zomni | etckeeper commits carry sudo-caller's git identity | sudo on `/etc` (set `/root/.gitconfig` or a `SUDO_USER` wrapper) | always ready; standalone |
| **7b35** | isochrone | add Zurich as 2nd region (picker + OSM/GTFS crop + preset) | run on zomni (JVM/r5py + real data) | DE/CH border confirmed clean (id:7ed0); region machinery landed |
| **3fcb** | isochrone | OSM overlay stage C (bespoke, MapLibre deferred) | strong-model `hard` work — can go via `/relay` if you don't want to drive it | decided D6; has Acceptance — actually pool-dispatchable |
| **401c** | dotclaude-skills | recurring strong-model audit | runs itself in a strong session: `/relay review dotclaude-skills` | ready after any batch of executor work to audit |
| **dba3** | dotclaude-skills | Opus quality probe — investigation + offline probe | runnable now (offline/free); live-seed waits on d0c0 OS-user/ToS | sub-items 903a/e3c0/241c are free reads |

**Quickest single move for A:** run **`/relay`** once (foreground) — it sweeps 3fcb, 401c, dba3, and the now-`[ROUTINE]` puzzle 7590 / ungated zomni 1d14·560c. Then the secret/hardware/sudo ones (fd1e, 935e, 9321, fd30, 7bef, 7b35) remain for hands-on zomni sessions.

## B. PARKED — gates only YOU can open (highest-leverage human levers)

| id | repo | gate you control | how to open it | unblocks |
|---|---|---|---|---|
| **ec51 → 383b** | meeting-rpg | configure opencode with an adequate model (Anthropic key **or** local qwen3.5-35b, n_ctx ≥32k) | plain session in meeting-rpg: "resolve ec51" — set up opencode + re-run probes id:130b | **383b** (opencode port) **+ dotclaude-skills 3346** (sub-agent meeting sim). **Best two-for-one lever.** |
| **f103** | zkm-notmuch | the core tag-REMOVAL merge semantic is undecided (data-loss risk) | `/meeting` in **zkm core** on `amendments.py::merge_fields` retract-mode, then split core(a)+plugin(b) | f103 + any future tag-removal propagation |
| **8740/62cb/a711** | zkm-photo | zkm Phase 3 (WebUI) hasn't started | nothing to do until **you decide to start zkm WebUI work** — then these re-scope | the 3 photo features |

## C. PARKED — externally-gated (nothing to run; just watch)

These flip on usage/time, **not** on anything you can force. ⚠️ They will NOT auto-surface when
the gate clears (that's the id:7ace gap) — until that's built, re-run `/relay human --all`
periodically (or check the column below) to catch a flipped gate.

| id | repo | gate | quickest "is it ready yet?" check |
|---|---|---|---|
| **1e77** | chidiai | ≥50 outcome rows + ≥10 unverified | `find ~ -name '*.chidi.jsonl' | xargs wc -l` (currently 0) |
| **efc2** | ai-codebench | the 244b GPU matrix run finishes | is ROADMAP id:244b ticked? (it's the prerequisite) |
| **5cc5** | proton-moresync | a first external user appears | adoption signal — you'll know |
| **7cf2** | zomni | an OOM-kill or sustained PSI-full stall | `grep -c 'oom_kills_since_last=[1-9]' ~/.local/state/zomni/mem-logger.log` (currently 0) |
| **1e36** | meeting-rpg | n=3–5 human-run live treatment meetings | `tools/check-ttfl-ready.sh` (Stop hook announces readiness) |
| **007b** | project_manager | a cache-sync channel exists AND ≥2-machine usage | `jq -r .machine ~/.cache/project_manager/history.jsonl | sort -u` (currently `zomni` only) |
| **de4e** | dotclaude-skills | quota economics change | already-decided-deferred; cosmetic relabel = id:9c92 |

## D. Postponed decisions (the triage tail — resume in a follow-up `/meeting --cross`)

These needed a real decision but were below the 80-20 line this round (tracked: id:fc04):

- **zkm-ner 7b4e** — scrub/extraction-cache coherence (3 named alternatives; data-integrity). Recommend a focused decision: rewrite-cache vs port-isolated-POS-gate vs per-store tombstone.
- **puzzle-pwa 6bef** — custom n-gon: Z⁸ integer model vs float coexistence. Leaning: reject unsupported n for now, defer float free-placement to its own decomposed track.
- **meeting-rpg 5d27** — portrait license gate (legal/cost: commission vs CC vs license-cleared-AI). Only needed before an itch.io/Steam public release — decide when a release is actually planned.
