# 2026-06-30 — Relay-side outcome of zkm B-topology (d097 follow-up)

**Started:** 2026-06-30 10:42
**Session:** 89940167-85c0-43ee-aa3f-4d8866d51b9d
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime lens)
**Topic:** Execute the dotclaude-skills relay-side outcome of the zkm per-plugin-TODO topology decision (zkm f98d → Option B), tracked here as `id:d097` / inbox `routed:2649`.

## Surfaced grounding (from setup)
- zkm meeting f98d (`~/src/zkm/docs/meeting-notes/2026-06-30-1004-per-plugin-todo-topology-revisited.md`) DECIDED **Option B**: each plugin owns its own `TODO.md`; central `zkm/TODO.md` keeps only core + cross-cutting. Migration already run zkm-side (MIG-1..5 ticked).
- Follow-up routed here as inbox `routed:2649`, tracked as TODO `d097` (`[HARD — meeting]`).
- The routed omnibus listed FOUR sub-tasks: (a) flip handoff C2 "central ledger by design"; (b) make `orphan-scan.sh` + `proj`/`projects` plugin-aware; (c) demote 69f4; (d) update the 2026-06-26 GH-issues policy line → "plugin's own TODO".
- Past-meetings audit clean: forward + cross-ledger orphan-scan on this repo returned no candidates.

## Pre-meeting verification (reshaped the task list)
- **(a) handoff C2:** `relay/references/handoff.md:35` already reads *"C2's FIRST check is the open `TODO.md` backlog"* of the repo being handed off — already repo-local. A full audit of `relay/` (handoff.md / review.md / conventions.md / SKILL.md, requested by Tobias before declaring no-op) found **no "central ledger by design" string anywhere**; the only monorepo machinery is the unrelated host-gate (id:43b9, multi-host *config* monorepos), and `gather-human-backlog.sh`/`scan-routed.sh` already resolve plugin repos via `# path:`. → **VERIFIED NO-OP.**
- **(d) GH-issues policy line:** lives in `~/src/zkm/CLAUDE.md:184–190`, NOT in dotclaude-skills, and already reads "route it into the **plugin's own `TODO.md`**" (rewritten in zkm MIG-4). → **already done, zkm-local, misrouted here.**
- **(c) proj/projects plugin-aware:** the scanner is `~/src/project_manager/scan.py` (separate repo); the `projects` skill is a thin `proj` caller. → **belongs in project_manager — re-route, don't build here.**
- **(b) orphan-scan.sh plugin-aware:** `meeting/orphan-scan.sh:47` builds its token union from `$ROOT/{TODO.md,TODO.archive.md,ROADMAP.md}` only. → **genuine dotclaude-skills build.** The zkm note's "Known transitional state" lists real false-orphan ids (ac55/b043/c89a/b99e/f40c/8d67) a `/meeting` in zkm root would mis-flag until this lands.

## Agenda
1. Triage the `routed:2649` omnibus — sort each sub-task by its true home.
2. Design orphan-scan.sh plugin-awareness (the one genuine local build).
3. Fate of 69f4 (demote / subsume into 2840 / close).

## Discussion

### Agenda 1 — Triage the omnibus
🏗️ **Archie:** The routed item reads like a four-item checklist, but three of four aren't dotclaude-skills work. Item (a) "central ledger by design" doesn't exist as a string in `relay/`; `handoff.md:35` has been repo-local all along. The phrase was a *description* in the d097 prose, not a hardcoded rule. Nothing to flip.

⚙️ **Sage:** Item (d) too — the 2026-06-26 GH-issues policy lives in `zkm/CLAUDE.md:184–190` and already says "plugin's own TODO" (zkm MIG-4). A zkm file, already correct.

✂️ **Petra:** Item (c) — the scanner is `~/src/project_manager/scan.py`; our `projects` skill just calls `proj`. Plugin-awareness for the dashboard belongs in project_manager. Building it here is scope-creep into the wrong repo → clean re-route to its inbox.

😈 **Riku:** So the omnibus collapses to one genuine local build (orphan-scan, item b) plus the 69f4 fate call (ours by ownership). The risk in "verified no-op" is a future session re-triaging `routed:2649` — record the verdicts with grep evidence and tick d097 with the full "1 built / 1 routed / 2 verified-noop" trail, or the dead-letter pattern (id:3947) bites.

🏗️ **Archie:** One guard before calling (a) a no-op: grep `review.md`/`conventions.md` for any central assumption, not just `handoff.md`. *(Done — clean.)*

**Decision 1 (Tobias):** Re-verify (a) harder first, then decompose as found. *(Audit run, clean — see Pre-meeting verification.)*

### Agenda 2 — orphan-scan.sh plugin-awareness
🏗️ **Archie:** Fix the union at `orphan-scan.sh:47`: when `$ROOT/plugins/` exists, also `cat plugins/*/{TODO.md,TODO.archive.md,ROADMAP.md}`. "Is this id tracked *anywhere* in this tree" is the right orphan question.

✂️ **Petra:** Gate on `[[ -d "$ROOT/plugins" ]]` + glob `plugins/*/` — generic, zkm-specific by accident only. Touch **forward only**; cross-ledger/promotion are intra-ledger comparisons (per-plugin granularity is the plugin's own run).

😈 **Riku:** Token collision across plugins is harmless for forward (presence anywhere = not-orphan). Zero regression for dotclaude-skills (no `plugins/` dir → gate off). Want a test: plugin-local id not flagged; absent id still flagged.

⚙️ **Sage:** Don't walk plugin *meeting-notes* from the root — those are covered when `/meeting` runs in the plugin. Union the plugin *ledgers* only; leave note-discovery at `$ROOT/docs/meeting-notes`.

**Decision 2 (Tobias):** Forward-union plugin ledgers, auto-gated on `$ROOT/plugins/`.

### Agenda 3 — Fate of 69f4
🏗️ **Archie:** 69f4 = cross-PROJECT mirrored-id sync. B dissolves its strongest (zkm-polyrepo, systematic) case — that's now intra-repo, caught by `--cross-ledger`. But genuine cross-*project* one-offs survive (toesnail+mw `6ab8`, toesnail+zkm `4159`), and id:2840 lists cross-project in scope — 69f4 may be subsumed, not built standalone.

😈 **Riku:** In zkm I argued, and Tobias ratified (zkm D7), **demote not close**: the triad case survives but must not be built now (the urgent pressure is gone). Strike the systematic justification, narrow to triad, flag subsumed-by-2840.

✂️ **Petra:** Standalone build is now N=1 (rare one-offs, handled by inline manual-sync) — below the bar. Demote-and-gate-on-2840 is the honest state; keep the pointer so it isn't re-filed.

**Decision 3 (Tobias):** Demote + gate on 2840.

## Decisions
- **D1 — `routed:2649` decomposes to 1 local build + 1 reroute + 2 verified-noop.** (a) handoff-C2 "central ledger by design" = VERIFIED NO-OP (grep of all `relay/`: no such assumption; `handoff.md:35` already repo-local). (d) GH-issues policy = ALREADY DONE zkm-local (`zkm/CLAUDE.md:189`). (c) proj/projects plugin-aware = RE-ROUTE to project_manager (scanner is `~/src/project_manager/scan.py`). (b) orphan-scan plugin-aware = GENUINE LOCAL BUILD (see D2). *Out of scope:* re-deciding zkm topology (settled f98d); editing zkm/project_manager files from this session (route only).
- **D2 — orphan-scan.sh plugin-awareness: union blob auto-gated on `$ROOT/plugins/`.** Forward + reverse (both consume the union blob) become plugin-aware; cross-ledger + promotion build their own intra-ledger maps and stay per-(plugin-or-root) by design. Auto-detect, no flag, no caller change. Zero behaviour change for plugins-less repos. *Out of scope:* walking plugin meeting-notes from the root; plugin-aware cross-ledger/promotion; per-plugin collision detection.
- **D3 — 69f4: DEMOTE + gate on 2840** (matches zkm D7). Strike the zkm-polyrepo systematic justification (cite f98d), narrow to the triad one-off case (`6ab8`/`4159`), flag likely-subsumed by id:2840 → do-not-build-standalone-now; revisit on recurrence or when 2840 lands. *Out of scope:* closing 69f4; building cross-project sync now.

## Action items
- [x] **AI-1 (D2).** `meeting/orphan-scan.sh:47` — union blob includes `plugins/*/{TODO.md,TODO.archive.md,ROADMAP.md}` when `$ROOT/plugins/` exists. Done this session. <!-- id:d097 -->
- [x] **AI-2 (D2).** `tests/test_orphan_scan_plugin_aware.sh` — plugin-local id not flagged, absent id flagged, plugins-less control unchanged. `make test` 124 passed / 0 failed. Done this session. <!-- id:d097 -->
- [x] **AI-3 (D3).** `id:69f4` body rewritten (demote + 2840 gate, cite f98d) via flock'd `md-merge.py --commit`. Done this session.
- [x] **AI-4 (D1c).** Re-routed proj/scan.py plugin-walk to project_manager inbox → `routed:c38a`.
- [x] **AI-5 (D1).** Closed `id:d097` `[x]` with the decomposition trail; `append.sh inbox-done 2649`.
- [x] **AI-6.** This note (records the (a)/(d) verified-noop evidence so a future session doesn't re-triage).

## Verification
- `make test`: **124 passed, 0 failed, 0 expected-red.**
- `meeting/orphan-scan.sh ~/src/zkm`: transitional false-orphans `ac55`/`b043`/`c89a`/`b99e`/`f40c`/`8d67` confirmed **no longer flagged** (resolve via `plugins/*/TODO.md`).
- This repo's own orphan-scan: unchanged (no `plugins/` dir, gate off).
- Inbox: `routed:2649` resolved `[x]`; `routed:c38a` (project_manager) queued.
