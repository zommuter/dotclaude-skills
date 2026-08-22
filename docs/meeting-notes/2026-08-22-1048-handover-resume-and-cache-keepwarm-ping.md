# 2026-08-22 — Handover/resume, and the cache keep-warm ping

**Started:** 2026-08-22 10:48
**Session:** e6a00aeb-2a37-4b22-8c4f-3ed9fa9c5213
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔧 Quinn (KV-cache / cold-start, re-onboarded), 🗄️ Cassi (derived-data persistence, re-onboarded)
**Topic:** Whether to build an auto-ping that holds the prompt cache warm, and/or an automated "prepare handover for the next session" — and where each belongs.
**Mode note:** Opus-class, so plan mode was skipped per `format.md` §Plan-mode gate; discussion ran as visible chat. `--fabled` was passed and produced **two** adversarial passes (the second requested by the owner after the amendment round materially changed the decision set).

## Agenda

1. Is the keep-warm ping economically sound at all?
2. What is the handover artifact, and does it fold into `id:7e9a`?
3. What gets built now vs. measured first?

## Discussion

### Item 1 — the ping

Quinn opened by correcting the framing: this is not a local KV cache but Anthropic **prompt caching** — a server-side cached prefix with a TTL, kept alive only by *using* it, which is a billable request. Authoritative multipliers (`claude-api` skill, `shared/prompt-caching.md`): cache read ≈ 0.1× base input; cache write **1.25× at the 5-minute TTL, 2× at the 1-hour TTL**; 5-minute is the default, `ttl: "1h"` is an opt-in API parameter.

The first analysis was **wrong in two ways, both corrected in-session**. It quoted 1.25× flat (wrong for the 1h tier) and, worse, drew a verdict about a distribution from its losing tail — recommending the ping be dropped on overnight/weekend economics the owner had never asked about. The owner's actual cases (reading a transcript, waiting on background agents, lunch, an orchestrator waiting on a pool) all sit far inside the win zone at a 1h TTL.

The owner then challenged the TTL premise directly: *"you said `ttl: 1h` is opt-in though, and I think I read that's API calls only, not subscription / claude code sessions?"* — a challenge that could not be settled from the docs, which describe the API parameter and say nothing about which surfaces use it.

Archie traced the owner's 5-minute mental model to its source: `statusline/statusline-command.sh` hardcodes `300` (at lines 340/345/348), derived from transcript mtime, and never verifies it. The `KV:` segment had been asserting a constant it never checked.

**The question was then settled by measurement, not argument.** Transcript JSONL already carries per-message `usage`, including `cache_creation` as an object. Over this session (356 messages with usage): `ephemeral_1h_input_tokens` = **1,187,930**, `ephemeral_5m_input_tokens` = **0**. The second `--fabled` pass replicated this across **15 recent sessions spanning 8 repos** — `ephemeral_5m` = 0 in every one. Claude Code subscription sessions use the 1-hour TTL exclusively. This dissolved the elaborate proxy-capture mechanism the amendment round had just designed: the deciding field was already on disk.

### Item 2 — handover and resume

Cassi's initial position — that a handover doc is merely a cache of a derivable view — did not survive contact with the real artifact. Auditing `docs/HANDOVER-2026-08-22.md` section by section: "what shipped", suite state, branch and quota are derivable; **owner rulings, traps paid for, method notes, and "the one thing to do first" are not**. Roughly the top half derives, none of the bottom half does — and the bottom half is what a next session would miss.

Archie's counter reframed it: those categories are not homeless. Rulings belong in `TODO.md`/`ROADMAP.md` under the no-quiet-decisions rule; traps and method notes belong in `discoveries.md` and the memory store. Today's four rulings and yesterday's traps had in fact landed there. So the handover doc is a **symptom of unreliable writes, not of homeless information**.

The owner rejected the natural conclusion (force more into those stores) on bloat grounds — `TODO.md` carries 563 open boxes and its bloat is separately tracked (`id:2840`, `id:4a5c`). Adding load to a store with an unsolved bloat problem is a bad trade.

The owner then reframed the requirement decisively: the handover should stay current **automatically**, ideally surviving an **OOM-kill**, or else detect that it hasn't and offer a "transcript since last update" catch-up. Sage established that this rules out close-time triggers entirely — SIGKILL runs no hooks, so `/exit`-hooked or Stop-hooked sweeps work only when you exit politely, which is precisely when you least need them. Cassi noted the transcript JSONL is appended live and survives a kill, so nothing is ever *lost* — it is only expensive to re-read, which turns the catch-up sweep from data recovery into an on-demand re-derivation.

### Item 2 (continued) — prior art, `id:cece`

The owner stopped the wrap-up to insist the prior art be read **first**: `mattpocock/skills`, cloned to `~/src/mattpocock-skills`. Its `skills/productivity/handoff/SKILL.md` is ~10 lines: user-invoked only (`disable-model-invocation: true`), summarises the current conversation, writes to the **OS temp dir, explicitly not the workspace**, takes an optional argument (*"What will the next session be used for?"*), includes a "suggested skills" section, requires redaction, and rules: *"Do not duplicate content already captured in other artifacts … Reference them by path or URL instead."*

That last rule is the derivable-vs-authored split, arrived at independently and stated more strongly than this meeting had it. Two ideas were entirely absent from our design: the **tailoring argument** (which dissolves the "at close you can't know what's needed" objection — you simply ask) and the **suggested-skills** field.

Riku then used the prior art against our own design: his handoff is ten lines and no machinery; ours proposed an event-driven writer, a systemd watchdog, a death detector and a catch-up sweep, buying only OOM survival and not-forgetting. The governing *observe before preventing* rule says build the logger first — and we had no measurement of how often a session actually dies uncleanly with unrecorded work.

### Item 2 (continued) — handoff vs `/compact` vs `--continue`

The owner raised `/compact`, which he avoids because he does not want to lose transcribed history and does not trust the mechanism. **The first half is a false premise, corrected:** compaction changes only what is in the context window; the on-disk JSONL is append-only and untouched. The second half (distrust of what a model-chosen summary keeps) survives intact.

The owner then corrected the assistant in turn: *"an OOMed session can still be `--continue`'d, so handoff as only option is plain wrong."* Correct — `--continue` resumes a dead session from its transcript. Handoff versus `--continue` is therefore a **cost-and-curation** choice, never an availability one, and the cost half is the same cache economics as the ping.

## `--fabled` pass 1 — 12 findings

Findings recorded verbatim in-session. Load-bearing ones: **F1** the entire cost model was API dollar pricing applied to a quota-metered subscription account — quota, not tokens, is what binds; **F2** the ratified `MECH_PROXY_DEBUG_SHAPE` capture fires only on `model=="bash"` and logs only a request-text prefix, so it could observe none of the deciding bytes; **F6** the `id:98f0` watchdog is blind to interactive sessions (they never emit heartbeats), so D5's gate counter was structurally zero forever. Also **F3/F4/F5** (ping tree had no null branch, an unbounded silent-spend branch keyed to a liveness predicate the repo's own memory records as broken, and an unstated primitive), **F7–F12** (invented counterfactual, resume forbidden from reading its own snapshot, `file:line` rot, matrix dead cell, no snapshot keying rule, and a ratified line-cite that had already gone stale within one session).

## `--fabled` pass 2 — 11 findings on the delta

Requested by the owner on the grounds that half the decision set had never faced an adversary, and that the assistant had defused F5 with its own reasoning and then re-ratified D1 on that defusing. It was justified:

- **F2·1** D1 was re-ratified on the exact number its own probe exists to measure. Break-even is `(2−w)/w` pings, where `w` is quota's weighting of a cache read: **19 at w=0.1, but 1 at w=1**. `w` is unmeasured.
- **F2·2** The arithmetic was slightly wrong (marginal lapse is 1.9×P, not 2.0×) and **the "wins decisively for 10 min – 3 h" claim was wrong for most of that band** — for any gap **≤ 1 h the measured 1h TTL already covers it for free**. The mechanism earns only on the (1 h, 3 h] tail. The per-ping cost also silently omitted the ping's own suffix write and its output tokens — omissions that flattered the conclusion.
- **F2·3** Shipping the ping **censors** the very data D2 needs; and a lapse is *already retrospectively visible* (a gap > TTL bills `cache_creation` instead of `cache_read`), so the deciding observation was free on disk the whole time.
- **F2·4** The ping primitive is still unstated, and D5's collapse removed the only external component that could host it; also "ping hourly" at exactly the TTL **is** a lapse — cadence must be sub-TTL (~55 min).
- **F2·6** `bump_policy = patch` fires a bump on **every** integrate (`integrate.sh:496-504` — no no-bump branch exists under any level policy), contradicting the ratified 2026-07-17-1541 D1 rule; under loose-0.x it mints semantically false patch versions; and a fleet default permanently silences the escalation whose resolution path is a per-repo owner judgement. The three handbacks were that mechanism **working**.
- **F2·7** "Unclean-death frequency" is undeliverable from transcripts: there is **no clean-exit sentinel**, so last-entry-then-silence describes every ended session.
- **F2·8/9/10/11** quota-probe preconditions; hardcoding 3600 recreates the rot class; D14 overlaps existing surfaces; D3's fix is gated on the still-undecided keying rule, and snapshots in `~/.claude/projects` land inside D2's own glob.

**Escalation trigger (`id:8df5`/`id:43c8`):** ~23 forced-amendment findings across two passes against a threshold of 2 — by a wide margin the largest firing recorded (history 4/4/5/7/6). Surfaced here so the trigger is auditable. **The build decision remains the owner's.**

## Decisions

- **D1 — the ping is NOT built and its shape is NOT pre-decided.** Un-ratified twice: first on F3/F4/F5, then again after F2·1–F2·3 showed the re-ratification rested on unmeasured `w` and on arithmetic that dropped terms in its own favour. **D2 runs first.** Any future shape must satisfy: a null branch (stop pinging, pay one re-warm — cost-identical at break-even and full-fidelity); a hard budget pinned at `(2−w)/w`; sub-TTL cadence (~55 min, not "hourly", since a ping at 60:01 is itself a lapse); the ping's own suffix write and output tokens counted; and a resolved primitive. Out of scope: shipping any ping before D2 reports.
- **D2 — one stdlib-only transcript analyzer**, no proxy work, over `~/.claude/projects/*.jsonl` (excluding the snapshot path, F2·11). Reports: idle-gap distribution; cached-prefix size per gap; `cache_read` vs `cache_creation` totals; **historical lapse frequency and real re-warm cost** (a gap > TTL bills `cache_creation` — F2·3); and whether the 1h TTL premium earns out. Preconditions for its quota probe (F2·8): reuse `tools/quota-sample.sh` rather than raw-curling `/api/oauth/usage` (which 429s aggressively), require a quiesced fleet window, and use a deliberately large cache read since endpoint resolution is unknown. Out of scope: the invented handoff-size counterfactual (F7).
- **D3 — `resume` derives on read.** "Standalone" means **graceful degradation when no snapshot exists**, NOT ignoring one that does; resume MAY read the snapshot (F8). Must never read the transcript; fast-start is a hard constraint; composed from `control-board.sh`, `claim.sh`, `heartbeat.sh`, `ratify-queue.sh`, `ledger-slice.sh`. Gated on D10's keying rule.
- **D4 — fix the statusline**, but do not swap one unverified constant for another (F2·9): correct the 300s, add a provenance comment pointing at D13, fix the "KV" wording if inaccurate, and have D2 assert the `ephemeral_5m == 0` invariant on fresh transcripts so the next silent TTL change is detected rather than mis-displayed for months.
- **D5 — the systemd watchdog is dropped**; death detection moves to D2. But F2·7 stands: transcripts carry no clean-exit sentinel, so a **SessionEnd hook writing a sentinel** is required for the population D5 cares about. The snapshot writer stays gated on what that reports.
- **D6 — snapshot only**; do NOT force new writes into `TODO.md`/`discoveries.md` while their bloat is unresolved.
- **D7 — prior art compared** (`id:cece`, done this session; repo cloned to `~/src/mattpocock-skills`).
- **D8 — file the meeting-question-guard defect** with **two competing hypotheses**: `stop_hook_active` persistence, and background task-notification entries interleaving into the transcript and confusing `trailing_segment()`. Discriminate against the log's timestamps; make the silent loop-guard path log. Evidence: it blocked at 11:05, went silent across several long prose turns, then fired reliably again — clustered misses, not permanent disarm.
- **D9 — the three-row matrix is the rule**: live background work → `/compact` only; context exhausted with nothing live → either; session dead → `--continue` (full fidelity, pays a cold read) **or** handoff → fresh (lean, curated). The skill must name what it does NOT cover: live work is already gone at death, and "handoff → fresh" requires a snapshot written *before* death, which the gated writer will not produce during the observation period.
- **D10 — snapshots live in `~/.claude/projects`** (existing private git-tracked store, private remote, committed hourly). **Keying: per-session**, mirroring how transcripts are already stored (`<repo-slug>/<session-id>`), so parallel sessions never clobber; resume selects the most recent for the repo. Snapshot size must be bounded (the store is committed hourly, so every version accumulates in git history).
- **D11 — citation precision**: `id:XXXX` first (churn-proof, guaranteed by the orphan-scan ecosystem); `file:line` only SHA-pinned or as a fallback where no id exists. A bare filename is a homework assignment, not a reference. Plus the borrowings: optional tailoring argument (default "a fresh session continues exactly this work"), a suggested-skills section, and explicit redaction.
- **D12 — fleet default `bump_policy = minor`, per-repo override.** Recorded as an **EXPLICIT OWNER AMENDMENT** to the ratified 2026-07-17-1541 D1 rule, not as a quiet config default. What it overrides, stated plainly: a level policy bumps on **every** integrate (no no-bump branch exists), so refactor-only closes will now mint versions, contrary to that rule; and the fleet default silences the per-repo escalation the gate was designed to force. `minor` was chosen over `patch` because it is the harmless over-signal where `patch` is the harmful under-signal under loose-0.x. The owner accepted this trade knowingly after the premise was corrected. Out of scope: version-less repos (this one), which never reach the manifest-keyed gate.
- **D13 — the prompt-cache TTL is 1 hour, exclusively** (measured; `ephemeral_5m` = 0 across 15 sessions / 8 repos, `ephemeral_1h` totals 190k–7.6M). The owner's recollection that `ttl:"1h"` is API-only is refuted for Claude Code subscription sessions. The 1h TTL carries a 60% write premium over 5m (2× vs 1.25×) — ≈890k token-equivalents in this session — but this is **inert as a decision input**: the TTL is harness-chosen and no owner action follows.
- **D14 — a post-pool/transcript cost-analysis skill**, scoped as a **thin wrapper over D2's script**; the quota side extends `tools/quota-report.py` rather than duplicating it (F2·10).

## Action items

- [ ] Build D2's stdlib-only transcript analyzer (idle-gap distribution, prefix size, cache_read vs cache_creation, historical lapse frequency + re-warm cost, 1h-premium earn-out, `ephemeral_5m==0` invariant assertion); exclude the snapshot path from its glob <!-- id:3412 -->
- [ ] D2's quota-weighting probe for `w`, honouring F2·8's preconditions (reuse `tools/quota-sample.sh`, quiesced fleet window, deliberately large cache read) <!-- id:22f2 -->
- [ ] Fix `statusline/statusline-command.sh` (300 at lines 340/345/348) with a provenance comment citing D13, not a bare 3600; fix the "KV" wording if inaccurate <!-- id:7da0 -->
- [ ] SessionEnd hook writing a clean-exit sentinel, so unclean death becomes observable (F2·7) <!-- id:002a -->
- [ ] Adopt the simple user-invoked `handoff` skill with the D11 borrowings; state in-skill which situation it does NOT cover (D9) <!-- id:749d -->
- [ ] `resume` (D3), gated on D10's per-session keying <!-- id:6279 -->
- [ ] File the meeting-question-guard defect with both hypotheses; make the silent loop-guard path log (D8) <!-- id:5beb -->
- [ ] Implement the `bump_policy = minor` fleet default as an explicit amendment, naming what it overrides (D12) <!-- id:65ad -->
- [ ] Event-driven snapshot writer + catch-up sweep — **GATED** on D2/`id:002a` evidence, do not build yet (D5) <!-- id:5284 -->
- [ ] `wrapup`/`handover`/`resume` skill-shape decisions — this meeting supersedes much of its open framing <!-- id:7e9a -->
