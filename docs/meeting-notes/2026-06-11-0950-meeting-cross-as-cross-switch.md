# 2026-06-11 — meeting-cross as a `--cross` switch?

**Started:** 2026-06-11 09:50
**Session:** f61a4c69-74ca-42fd-9e3b-2e60b2d9e5d9
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing per `meeting-style.md`)
**Topic:** Should `/meeting-cross` be collapsed into a `--cross` switch on the canonical `/meeting` skill?

## Surfaced discoveries
- [2026-06-03 dotclaude-skills] Shape-B lazy-spec pattern: WIP/opt-in behaviour extracted into a delta file (broker-mode.md) loaded only on the opt-in path — drift-proof, common case pays zero ctx tax.
- [2026-05-28 dotclaude-skills] MEETING_ROOT_OVERRIDE env-var dispatch pattern — invoke cwd-anchored skill against a different root without `cd`.
- [2026-05-14 dotclaude-skills] Every "mandatory after every prompt" / always-loaded skill is a per-prompt ctx multiplier.

## Agenda
1. Has the deciding context shifted since the 2026-05-28 β ratification? (broker-mode delta-file pattern shipped after it.)
2. Three live options: pure-α (inline `--cross` branch), status-quo β (separate skill), or α′ (`--cross` switch backed by a `cross-mode.md` delta-file). Which?
3. Migration / churn check — how to retire `/meeting-cross` and guard the misfire surface.

## Discussion

### Agenda 1+2 — Has the context shifted, and which of the three options now?

🏗️ **Archie:** The 2026-05-28 meeting ratified β — separate `/meeting-cross` skill composing with canonical via `classify.sh` + `MEETING_ROOT_OVERRIDE`. That's built and live: `meeting-cross/SKILL.md` exists, `classify.sh` is shared, and id:b427 (the 3-run cost gate) just closed. The question isn't "which architecture do we build" — it's "do we tear down working infrastructure and reverse a ratified decision." That bar is higher. The one thing that genuinely changed: when β was chosen, α was rejected for polluting the single-project read path with 30% novel cross logic gated by a flag. But the *broker-mode backmerge* shipped after that and proved a pattern we didn't have on the table then.

⚙️ **Sage:** Broker mode is the precedent — opt-in behaviour in `broker-mode.md`, loaded *only* when active; canonical says one line, common path pays zero ctx. Cross-mode is the same animal. The real menu is three, not two: α (pure inline, still rejected — taxes common path), β (status quo, zero tax but drift surface on duplicated setup 1–4), α′ (switch + delta-file: single entry AND zero tax).

✂️ **Petra:** What pain are we buying out of? meeting-cross works — 3 clean runs. N=2 concrete costs: (1) duplicated setup 1–4 = real drift hazard; (2) "which skill to type" = weak, descriptions route fine. One-and-a-half-cost problem → argues for the cheapest fix (de-dupe), not a re-architecture.

😈 **Riku:** α′ migration = retire /meeting-cross, add --cross arg parsing, extract cross-mode.md, re-point symlinks, rewrite allowlist, update routing spec. Broker backmerge itself shipped 3 defects needing cleanup. And a flag misfire reopens D7 contamination. Separate skill name is a hard wall; a flag is soft.

🏗️ **Archie:** Contamination wall is real but lower-weight — misfire is a testable parse bug, not an architectural leak. Migration cost is the stronger point. But β's duplicated setup is already drift-prone; α′ fixes it (delta-file states only the delta, like broker-mode.md).

⚙️ **Sage:** Broker defects argue for care, not never. Clean middle: fix the drift without touching entry points — lift setup 1–4 into a shared spec, keep both names. "β with shared setup" — a quarter-step.

✂️ **Petra:** Three options ascending cost: (1) Leave it. (2) De-dupe only (stay β) — kills drift, zero entry-point risk. (3) Go α′ — best ergonomics, highest cost, only one reopening contamination-misfire.

😈 **Riku:** Ranking 2 > 1 > 3. Option 2 fixes the only concrete cost at near-zero risk. Flip-to-3 evidence: a real wrong-skill incident — hasn't happened in 3 runs.

🏗️ **Archie:** α′ is architecturally "right" if cross-mode grows more options. If it stays thin, Option 2 is sufficient. Convergence: too thin today to warrant entry-point migration.

⚙️ **Sage:** Even Option 2 should single-source setup the broker-mode way — shared prelude file, not copy-paste, given the ~77% SKILL.md-bypass rate.

**Persona convergence:** Option 2 — Archie, Riku, Petra, Sage. α′ deferred to "if cross-mode accretes more branches."

**Zommuter decision (overrides convergence):** Go α′ — `--cross` switch + `cross-mode.md` delta-file. Single-entry-point ergonomics and correct delta-file shape are worth the migration.

### Agenda 3 — α′ migration shape and misfire guard

😈 **Riku:** `--cross` detection must be a literal flag token, never fuzzy inference. Cross branch is the first check after metadata capture; it reads `cross-mode.md` and hands off — no interleaving with single-project steps. Disjoint read-paths.

⚙️ **Sage:** Mirrors broker-mode exactly. One conditional near top: if arg is `--cross` → read `cross-mode.md` and follow it; else proceed canonical. `cross-mode.md` holds everything novel (project discovery, per-project classify loop, global bucket synthesis, MEETING_ROOT_OVERRIDE, routing-trail) and restates none of setup 1–6.

🏗️ **Archie:** Disposition of existing `/meeting-cross`: (a) hard-delete, (b) 3-line deprecated alias reading `cross-mode.md`, (c) keep both fully. Reject (c). Between (a)/(b): (b) preserves muscle memory at near-zero cost.

✂️ **Petra:** Alias now so nothing breaks mid-migration, with explicit removal trigger — delete after `/meeting --cross` succeeds twice. Don't let "temporary" become permanent.

😈 **Riku:** The alias SKILL.md must read `cross-mode.md` — NOT carry its own copy of cross steps. Alias = pure forwarder or nothing.

⚙️ **Sage:** Allowlist-neutral — all helpers already covered. Only new symlink: add `cross-mode.md` to P2 set.

🏗️ **Archie:** Migration: (1) write `cross-mode.md` (move novel sections); (2) add `--cross` conditional to canonical; (3) shrink meeting-cross/SKILL.md to a 3-line forwarder + removal trigger; (4) keep MEETING_ROOT_OVERRIDE doc line. No allowlist churn. Contamination wall preserved by disjoint read-path, not skill name.

**Persona convergence:** α′ via `cross-mode.md` delta. `/meeting-cross` → time-boxed deprecated alias (pure forwarder), delete after 2 successful `/meeting --cross` runs.

**Zommuter decision:** Time-boxed alias confirmed.

## Decisions

- **D1 — Architecture: α′ (switch + delta-file), reversing 2026-05-28 D1 (β).** Cross-project mode becomes `/meeting --cross`. Canonical `meeting/SKILL.md` gains one conditional immediately after metadata capture: if the argument is `--cross`, read `~/.claude/skills/meeting/cross-mode.md` and follow it; otherwise proceed as canonical. Detection is a **literal `--cross` flag token**, never fuzzy inference. Read-paths are **disjoint** — single-project meeting loads zero cross logic. *Why the reversal:* broker-mode Shape-B delta-file pattern (2026-06-03) proves single-entry-point + zero-common-path-tax is achievable. *Out of scope:* pure-α inline, full β status quo, keeping both live entry points. **Provenance:** ratified by Zommuter (overriding persona convergence on de-dupe).

- **D2 — `cross-mode.md` content contract.** Delta-file holds only what's novel: include.toml project discovery, per-project `classify.sh` loop, global bucket synthesis + cross-connection surfacing, top-pick selection, MEETING_ROOT_OVERRIDE dispatch, routing-trail note + `cost-of.sh` instrumentation. Restates none of canonical setup steps 1–6 or meeting flow. Shared helpers unchanged. P2-symlink into `~/.claude/skills/meeting/`. *Out of scope:* duplicating any setup/flow prose. **Provenance:** ratified by Zommuter (decision 1).

- **D3 — `/meeting-cross` → time-boxed deprecated alias.** Shrink `meeting-cross/SKILL.md` to a pure forwarder reading `cross-mode.md` — no independent cross steps. Removal trigger: **delete after `/meeting --cross` has been used successfully twice.** *Out of scope:* hard-retiring now, keeping alias indefinitely. **Provenance:** ratified by Zommuter (decision 2).

- **D4 — Migration is allowlist-neutral.** All `cross-mode.md` helpers already allowlisted. Only new symlink: add `cross-mode.md` to P2 set. `MEETING_ROOT_OVERRIDE` doc line (id:8237) stays. **Provenance:** Sage; no objection.

## Action items

- [ ] Write `meeting/cross-mode.md` delta-file — move novel cross sections from `meeting-cross/SKILL.md` per D2. File: `~/src/dotclaude-skills/meeting/cross-mode.md` (new); P2-symlink into `~/.claude/skills/meeting/`. Contract: no setup-step-1–6 prose in cross-mode.md; self-contained for the cross path. <!-- id:5e5d -->

- [ ] Add `--cross` conditional to canonical `meeting/SKILL.md` — literal `--cross` token after metadata capture → read `cross-mode.md` and follow it; else proceed canonical. File: `~/src/dotclaude-skills/meeting/SKILL.md`. Contract: plain `/meeting` loads zero cross logic; `/meeting --cross` reads `cross-mode.md`. <!-- id:13f0 -->

- [ ] Shrink `meeting-cross/SKILL.md` to a pure forwarding alias — reads `cross-mode.md`, no independent cross logic; embed removal trigger comment. File: `~/src/dotclaude-skills/meeting-cross/SKILL.md`. Contract: alias body contains no project-discovery/classify/dispatch prose of its own. <!-- id:18bb -->

- [ ] Delete `/meeting-cross` after 2 successful `/meeting --cross` runs — remove dir, P2 symlink, any meeting-cross-specific allowlist entries. Contract: registry no longer lists `meeting-cross`; `/meeting --cross` is sole cross entry. <!-- id:4f5f -->
