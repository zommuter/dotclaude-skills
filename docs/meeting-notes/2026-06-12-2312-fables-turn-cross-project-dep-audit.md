# 2026-06-12 — fables-turn review cross-project dependency audit (id:6a3c)

**Started:** 2026-06-12 23:12
**Session:** 03754c4d-93db-4794-973f-511e3dcd255b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🎛️ Orla (multi-agent orchestration)
**Topic:** Design how `/fables-turn review` should detect conflicting or coupled changes across related relay repos, instead of auditing each repo in isolation.

## Surfaced discoveries
- [2026-05-10 .claude] `git-lock-push.sh` accepts an optional `REPO_PATH` positional arg — relevant if the audit ever writes cross-repo.
- The shared inbox (`~/.claude/todo-inbox.md`, `routed:XXXX`) is the only durable cross-repo channel today; review step 5 already routes cross-repo follow-ups there via `append.sh -t inbox`.

## Agenda
1. Where does the audit run — review child, orchestrator post-barrier, or dedicated pass?
2. How is coupling between repos declared?
3. What does it check, and how do findings surface?
4. Trigger and MVP scope.

## Discussion

### Item 1 — Where the audit runs
🏗️ **Archie** laid out three options: (a) inside the review child (worktree-scoped to one repo); (b) in the orchestrator after all children return (post-barrier); (c) a dedicated standalone pass.

🎛️ **Orla** eliminated the child: a child runs in its own worktree for ONE repo (`review.md:1`), and integration is strictly sequential (SKILL.md invariant 5) — while child A reviews, repo B may be mid-integration or in a held worktree. Any cross-repo read from inside a child reads an inconsistent snapshot. The orchestrator is the only actor that holds a coherent cross-repo view after the barrier.

😈 **Riku** pushed on the dedicated-pass option: a third execution surface means a third maintenance surface. Minimum-evidence bar before adding one.

✂️ **Petra** resolved: no new execution mode — append a step to the existing post-children integration loop. Only compare coupled pairs where both were touched this wave. Out of scope: untouched repos (no diff window).

⚙️ **Sage** clarified mechanics: the orchestrator is Workflow JS with no filesystem access; "orchestrator does the audit" = spawns ONE audit agent after the barrier, handed the list of touched repos and their `roadmap_delta`s. That agent can read multiple repos.

🎛️ **Orla** tied off the no-op case: agent is spawned only when ≥2 repos in a declared coupling were both touched. One repo or no coupling → agent never spawns, zero cost.

### Item 2 — How coupling is declared
🏗️ **Archie** enumerated options: `relay.toml` field per repo (`coupled_with`), a richer `[[coupling]]` table, heuristic detection, or repo-local committed manifests.

⚙️ **Sage** argued for the central table: coupling is a property of the *pair*, not either repo individually. Per-repo manifests drift between the two ends. `relay.toml` is already the user-confirmed, single-writer relay registry.

😈 **Riku** pre-empted heuristic detection: FPs (a doc that merely mentions another repo), misses (the broker.py ↔ meeting-rpg coupling has no shared literal path string — the coupling is semantic). Consistent with the user's manual-over-heuristic preference for identity/relationship reasoning.

✂️ **Petra** applied the N=2 rule: exactly ONE coupling is known today (meeting-rpg ↔ dotclaude-skills/meeting/). Don't build a provenance graph for a single consumer. A flat `[[coupling]]` array with a surface-glob list is enough.

🎛️ **Orla** pushed back on going *too* minimal: the audit agent needs to know *what* to diff, or it diffs everything (noise) or nothing. A per-coupling glob list of the shared surface (broker.py, broker-mode.md, personas.md on the dotclaude side; launcher/web/config.json on the meeting-rpg side) is one table entry, not a graph.

⚙️ **Sage** synthesized the schema: `[[coupling]]` array in `relay.toml`, each entry `{repos = [a, b], surface = [globs], note = "..."}`.

😈 **Riku** accepted, conditional on the entry being real, not a placeholder — and the risk being real, not hypothetical. Observe-first posture warranted; drift not yet confirmed.

### Item 2b (amendment) — Second coupling axis: write-contention on dotclaude-skills
The user raised a related concern: `git-diary-workflow` always checks dotclaude-skills for changes and can accidentally commit another concurrent session's in-flight WIP.

✂️ **Petra** named two distinct axes. **Axis A (artifact divergence):** two repos hold two ends of a shared contract that can drift apart — the broker/persona case. **Axis B (write-contention):** dotclaude-skills is the canonical host for symlinked skill files; any session's diary run can scoop another in-flight session's uncommitted changes. Axis B couples dotclaude-skills to *every concurrent session*, not just one sibling.

🎛️ **Orla** noted Axis B already fired three times on 2026-06-12 (see id:3558). This is exactly what `id:3558` (flock'd merge-to-canonical) + `id:ebfb` (cross-session reservation) exist to *prevent*.

😈 **Riku** drew the structural line: an audit is post-hoc *detection* — it cannot prevent a scooped commit. Don't let `id:6a3c` absorb a job it structurally can't do. Prevention is `id:3558`/`id:ebfb`.

🏗️ **Archie** acknowledged the audit *can* add cheap detection (flag checkpoint-window hunks that don't match the committing session's declared work) — valuable while prevention isn't shipped. But…

⚙️ **Sage** identified the dependency: Axis-B detection needs the *other worktrees* to compare against — held worktrees under `~/.cache/fables-turn/worktrees/` are exactly `id:ebfb`'s reservation signal. Without `id:ebfb`'s mechanism, the audit has nothing reliable to compare. Axis-B detection is parasitic on `id:ebfb`.

🎛️ **Orla** gave the clean dependency order: Axis-B detection in the audit is gated on `id:ebfb`/`id:3558` landing first. `id:6a3c` NOW = Axis A only.

✂️ **Petra** closed it: ship Axis-A, record Axis B as a named forward-flag citing `id:ebfb`/`id:3558` so the audit doesn't silently reabsorb it.

😈 **Riku** accepted on condition: the cross-link must be explicit and durable.

### Item 3 — What it checks + how findings surface
🏗️ **Archie** defined the check: for a coupled pair where both repos were touched, diff the surface globs across each repo's `$LAST..HEAD` and ask — did one side change the shared contract without the other?

😈 **Riku** raised the heuristic concern: "contract changed without update" is a judgment call. Flag-every-surface-change = noise; semantic LLM judgment = fallible. False-flag cost?

🎛️ **Orla** answered: false-flag cost is low *if* findings go to a human-review sink (inbox / REVIEW_ME), not auto-action. The audit never auto-edits either repo.

⚙️ **Sage** named the two existing output channels the TODO requires: (1) a line in the RELAY_LOG checkpoint paragraph (explicitly required by `id:6a3c`); (2) a `routed:XXXX` shared-inbox entry for follow-up. No new artifact.

✂️ **Petra** solved the noise problem with a two-tier design. **Tier 1 (mechanical):** deterministic asymmetry flag — one coupled repo's surface globs changed in the wave, the other's didn't. **Tier 2 (only if T1 fires):** the agent reads the actual diff and writes one sentence on whether it looks contract-affecting. This bounds LLM judgment to cases with a prior mechanical signal.

🎛️ **Orla** added: both-sides-changed in the same wave = probably a coordinated update → low-priority note, no alarm. Asymmetric = the alarming case.

🏗️ **Archie** resolved the per-repo vs. per-pair output question: write the *same* symmetric one-liner in **both** repos' checkpoint paragraphs, so the finding appears whichever RELAY_LOG the human reads.

😈 **Riku** insisted: the inbox token is minted ONLY on actual asymmetric drift. Tier-1-gates-Tier-2-gates-inbox. A clean wave → nothing written, nothing minted.

### Item 4 — Trigger and MVP scope
⚙️ **Sage** clarified the trigger is already met (24 registered repos), but per-wave firing is narrower: the audit agent spawns only when a `[[coupling]]` entry has both repos touched. Dormant until a wave touches both dotclaude-skills + meeting-rpg.

✂️ **Petra** scoped the MVP: (1) `[[coupling]]` schema + one entry; (2) post-barrier step in `relay-loop.js`; (3) audit-agent prompt (two-tier); (4) findings wired to `ckpt-tag.sh` RELAY_LOG line + inbox. One hermetic scratch-repo test.

😈 **Riku** raised observe-first: drift has not been observed (Sage couldn't confirm broker had drifted). Honest MVP = spec-only, gated on first real incident (the id:3558 pattern)?

🎛️ **Orla** countered: the two-tier design IS conservative at runtime — T1 is pure mechanical observation, FP cost = one inbox line. A separate log-only phase is ceremony.

🏗️ **Archie** proposed a build-gate: build schema + agent, but gate the live entry on first manually diffing the broker surface to confirm real drift risk. If stable, keep schema with no entry until a second coupling appears (N=2).

The user chose: build schema + post-barrier check + audit-agent prompt now, with the one `[[coupling]]` entry present but naturally dormant (fires only when a wave touches both repos). Not spec-only; not manual-diff-gated.

## Decisions

- **D1 — Location:** The orchestrator (`relay-loop.js`) spawns ONE post-barrier audit agent after all review children return, and only when ≥2 repos in a `[[coupling]]` entry were both touched this wave. Not inside the review child (single-repo worktree, inconsistent mid-wave snapshots). **Out of scope:** a third standalone execution mode.
- **D2 — Coupling declaration:** A `[[coupling]]` array in `~/.config/fables-turn/relay.toml`, each entry `{repos = [a, b], surface = [globs], note = "..."}`. One entry today (meeting-rpg ↔ dotclaude-skills, surface = `meeting/broker.py`, `meeting/broker-mode.md`, `meeting/personas.md` on the dotclaude side; `launcher` + `web/config.json` on the meeting-rpg side). Human-declared, like repo classification. **Out of scope:** heuristic coupling detection; per-repo committed manifests.
- **D2b — Two axes:** Axis A (artifact divergence) = this build. Axis B (write-contention detection on the canonical skill host) = forward-flag gated on `id:ebfb`/`id:3558` landing first — its detection needs `id:ebfb`'s worktree-reservation signal. **Out of scope for id:6a3c:** any write *prevention* (owned by `id:3558`/`id:ebfb`); Axis-B detection before those land.
- **D3 — Check + surfacing:** Two-tier. T1 deterministic asymmetry flag (one side's surface globs changed in `$LAST..HEAD`, the other's didn't). T2 fires only if T1 fires: one-sentence LLM impact note. Findings surface as (a) the SAME symmetric one-liner in BOTH repos' RELAY_LOG checkpoint paragraphs (via review return contract → `ckpt-tag.sh`), and (b) a `routed:XXXX` inbox entry minted ONLY on asymmetric drift. Both-sides-changed = low-priority note, no inbox token. **Out of scope:** auto-editing either repo's tree; minting tokens on clean waves.
- **D4 — Build scope:** Build schema + post-barrier step + audit-agent prompt + surfacing now. One `[[coupling]]` entry present, naturally dormant until a wave touches both repos.

## Action items

- [ ] Add `[[coupling]]` schema + one entry to `~/.config/fables-turn/relay.toml` (meeting-rpg ↔ dotclaude-skills, surface globs, note). Contract: relay.toml parses; entry has `repos`/`surface`/`note` fields. See `fables-turn/SKILL.md` for relay.toml schema context. <!-- id:4f21 -->
- [ ] Add post-barrier coupling-audit step to `fables-turn/scripts/relay-loop.js`: after the review barrier, check `[[coupling]]` entries; if both repos in an entry were touched this wave, spawn ONE audit agent (two-tier prompt); else skip. Document in `fables-turn/references/review.md` and SKILL.md. Contract: no agent spawned when <2 coupled repos touched; symmetric RELAY_LOG one-liner + `routed:` inbox entry only on asymmetric drift; both-sides-changed = low-priority note only. <!-- id:14c1 -->
- [ ] Add scratch-repo test `tests/test_coupling_audit.sh` (`# roadmap:6a3c`): (1) asymmetric surface change → one flag + one inbox entry; (2) symmetric change → low-priority note, no inbox token; (3) only one coupled repo touched → audit no-ops. Hermetic (`mktemp`, no `~/.config/` or `~/.claude/`). <!-- id:045a -->
- [ ] **Forward-flag (Axis B):** write-contention detection on canonical skill host — gated on `id:ebfb` (cross-session reservation) + `id:3558` (flock'd merge) landing; detection reads the worktree-reservation signal to flag checkpoint hunks not matching the committing session's declared work. Do NOT reabsorb into `id:6a3c` / Axis A before those land. <!-- id:6b81 -->
