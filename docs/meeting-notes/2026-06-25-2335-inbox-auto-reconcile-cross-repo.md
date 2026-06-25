# 2026-06-25 — Inbox auto-reconcile on cross-repo activity (id:678e)

**Started:** 2026-06-25 23:35
**Session:** 75f745cb-2767-49cc-9f71-1f932b1d0aeb
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), 🔩 Gil (git plumbing / cross-repo write integrity)
**Topic:** Define the auto-mutation contract for reconciling the shared cross-project inbox (`~/.claude/todo-inbox.md`) during cross-repo `/relay`+`/meeting` activity, so the imminent conformance sweep can dogfood it — folds id:3947.

## Surfaced discoveries / prior art
- **id:b30b** (2026-06-11): the inbox was DELIBERATELY "surface-only at meeting step 7b + /projects; **no auto-write into any repo's TODO**." This meeting reconsiders that.
- Live evidence: **12** open `routed:` items target `dotclaude-skills`, NONE in its ledgers; ~12 token-less prose blocks `inbox-done` can't resolve.
- **routed:b257**: cross-repo routing is too coarse — polyrepo siblings sharing ONE central ledger (zkm) are NOT foreign; direct-write is correct there after a claim check.
- **routed:9a81**: constraint-archaeology candidate explicitly NAMES todo-inbox routing as possibly-overengineered — re-justify before extending.
- **Profile** (pre-emption-eligible, high): prefers a reversible, still-visible action over a hard auto-action; prefers manual merge over heuristic merge.
- Cross-ledger advisory (note only): id:a643 TODO:[ ] ROADMAP:[x] (pre-existing, unrelated).

## Agenda
1. The auto-fix boundary: what auto-MUTATES vs what only SURFACES (the reversibility line)?
2. Integration points + `--exclude` / public-private path injection.
3. Minimal build to ship NOW as the dogfood vehicle.

## Discussion

**Agenda 1 — auto-fix boundary.** 🏗️ Archie: substrate exists (`append.sh -t inbox`, `inbox-done`, `todo-conformance.sh --inbox`); the gap is a `scan-routed.sh` dead-letter detector; cheapest reversible action = an idempotent INBOUND stub keyed on `routed:XXXX`. 😈 Riku: three landmines — (1) this reverses id:b30b on purpose ("no auto-write"); (2) auto-filing into a private repo lands noise in its history; (3) the profile prefers reversible-and-visible — so prove surface-only FAILED and the write is reversible. ✂️ Petra: surface-only HAS failed (12 stranded items = the evidence b30b lacked); the fix is two classes — **(A)** conforming `routed:` + resolvable target → additive/idempotent/reversible stub; **(B)** token-less prose or unresolvable target → surface only, never guess (no third "parse the prose" tier — that's the fabrication the conformance tool already refuses). 🎛️ Orla: reconcile runs once per SWEEP, not per-repo-per-round. 🔩 Gil: write integrity is the bite — `claim.sh peek`-skip held targets, idempotency on the token via `md-merge.py`, its OWN commit, and polyrepo `# path:` target-resolution (b257) is the risky part. 😈 Riku: that resolution risk argues ship **detection now**, gate **auto-write** behind a second slice. 🏗️ Archie: make the surface ACTIONABLE — print the exact ready-to-run file command (reversible-and-visible). ✂️ Petra: scope fence — slice 1 = detector (report-only), slice 2 = class-A auto-write (gated), class B forever surfaced.

**Agenda 2 & 3 — integration + sequencing.** 🎛️ Orla: runs at the top of a cross-repo pass (pool prelude / `--all` / `--cross` / `relay-doctor --all`), honors `paused`+`--exclude`. 🏗️ Archie: path is `RELAY_INBOX` default `~/.claude/todo-inbox.md` + override, exactly like `RELAY_TOML`; a home path isn't a secret. ✂️ Petra: the real choice is dogfood sequence. 😈 Riku: the user said "meeting first, then dogfood the result" — the result IS slice-1, so build it before sweeping. 🎛️ Orla/🔩 Gil: per-repo Sonnet agents fix conformance + commit their own repo after a `claim.sh peek` skip; the inbox scan is one central strong-session pass; truncocraft + any held repo excluded from both.

## Decisions
- **D1.** Inbox reconcile is **detection-first**: slice 1 = `scan-routed.sh` detects dead-letters (conforming `routed:` item absent from its `[target]` repo) + non-conforming inbox entries, REPORT-ONLY, printing the ready-to-run file command. *Out of scope:* any auto-write.
- **D2.** Auto-write of the reversible INBOUND stub (class A: conforming token + resolvable target) is **slice 2**, gated on proven target-resolution (incl. polyrepo `# path:`, b257) + a `claim.sh peek` skip + idempotency keyed on `routed:XXXX`. Token-less prose / unresolvable target (class B) is **forever surface-only** — never guessed.
- **D3.** Reconcile runs **once per cross-repo sweep** (pool prelude / `/relay human --all` / `/meeting --cross` / `relay-doctor --all`), honoring `paused` + `--exclude`. Inbox path = `RELAY_INBOX` default `~/.claude/todo-inbox.md`. Reuses `todo-conformance.sh --inbox` for the grammar half.
- **D4.** This reverses id:b30b's "no auto-write" ONLY at the gated slice-2 boundary, only for the reversible additive stub. Re-justification vs routed:9a81: surface-only demonstrably failed (12 stranded); the stub is additive + idempotent + reversible + claim-guarded, not the silent clobber b30b feared.
- **D5.** Dogfood sequence: build slice-1 `scan-routed.sh` (TDD) FIRST, then ONE cross-repo sweep — per-repo `todo-conformance.sh --fix` via **Sonnet** agents (each commits its own repo after a `claim.sh peek` skip) + a single central `scan-routed.sh` pass in this strong session. **truncocraft and any claim-held repo are excluded.** *Out of scope:* slice-2 auto-write during the dogfood (the 12 dead-letters are surfaced for the user's call).

## Action items
- [ ] Build `relay/scripts/scan-routed.sh` (slice 1): report-only dead-letter + inbox-conformance detector; reuse `todo-conformance.sh --inbox`; honor `RELAY_INBOX`/`--exclude`/`paused`; print ready-to-run file command; TDD `tests/test_scan_routed.sh` (`# roadmap:678e`); wire into relay-doctor + /relay human + /meeting --cross + pool prelude. <!-- id:678e -->
- [ ] Slice 2 (gated): auto-file reversible INBOUND stub for class A — polyrepo `# path:` target-resolution + `claim.sh peek` skip + `routed:` idempotency. (id:678e, deps slice 1)
- [ ] Dogfood sweep: Sonnet agents run `todo-conformance.sh --fix` + report `unpromoted-scan`/`roadmap-lint` per own repo (claim-peek skip; **exclude truncocraft**), commit per repo; central `scan-routed.sh` surfaces inbox dead-letters. (folds the user's "scan+fix all repos" request)
