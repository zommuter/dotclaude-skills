# 2026-07-14 — Human-manual/interactive task handling (`@needs-auth`)

**Started:** 2026-07-14 11:35
**Session:** 5fb1a16f-8808-49cf-851e-e2def5300b77
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime)
**Topic:** Split the overloaded `[HARD — hands]` lane (id:1750), design the interactive-auth/secret queue (id:a505), and decide the offline no-AI walkthrough tool — resolved as one coherent design because they share the same predicate.

## Surfaced discoveries
- [2026-07-08 dotclaude-skills] polkit denies interactive-auth for a seatless service user by default (can't pamac/escalate); `claude -p` runs headless but cannot do interactive-auth → the root reason class-(i) tasks are irreducibly human.
- [2026-06-16 toesnail] Headless automation can't drive the subscription (ToS = interactive use) → the walkthrough tool must be genuinely AI-free.

## Agenda
1. Lane taxonomy — how to split `[HARD — hands]`?
2. The interactive-auth/secret queue carrier (a505).
3. The offline walkthrough tool (1750) — build what, if anything?
4. Scope / build order.

## Discussion

### Items 1 & 2 — they collapse to one decision
🏗️ Archie: the three "hands" sub-classes aren't symmetric. (ii) device-bound is already captured by `[host:X]` (and half are pool-on-that-host — 9321 hands→pool proved it); (iii) mis-laned MECHANICAL/INTENSIVE is a *tagging error* the db39 5-criterion re-lane fixes case-by-case. Only **(i) secret-gated is genuinely new**.
😈 Riku: then don't proliferate lanes — minting `[hands:secret]`/`[hands:device]` creates a parsing surface for 27 repos to encode what `[host:X]`+one marker already say. Minimum that changes an outcome: a single marker on class-(i).
✂️ Petra: name it so it does double duty. a505's membership set (sudo/askpass, polkit/pamac, ssh/login, gpg/credential, browser-OAuth) IS class-(i). So the lane marker = the queue-membership predicate. One marker, `@needs-auth`. Items 1 and 2 are the same decision.
⚙️ Sage: `@needs-auth` costs zero new carrier — `gather-human-backlog.sh` already sweeps every repo's `REVIEW_ME` for `/relay human --all`, so a flagged box surfaces cross-repo for free. That IS the "global queue" a505 asked for, assembled at read-time.
😈 Riku (self-challenge): why beat a505's proposed `~/.config/relay/auth-queue.md`?
🏗️ Archie: a new global file repeats the exact unversioned-destructive-store hazard 9fdb just fixed. A per-repo `REVIEW_ME` box is versioned, travels with the work, diffs in-repo, and `/relay human --all` aggregates it anyway. The file buys nothing and re-opens a solved problem.
✂️ Petra: N=2 — consumer (1) `/relay human` gather; consumer (2) the executor contract (a child hitting an auth wall writes a `@needs-auth` box + clean-continues instead of failing the whole unit). (2) dissolves the "strand the rest of the unit mid-session" failure a505 was filed on.
😈 Riku: accept, with the continuation rule pinned — the child judges separability and **defaults to clean-handback of the gated remainder** when unsure.

### Item 3 & 4 — the tool + scope
⚙️ Sage: the tool's only real differentiator is **AI-free** — `/relay human` surfaces these but costs a Claude session; a plain bash grep of `@needs-auth` boxes runs offline.
🏗️ Archie: don't fork a new script — extend `gather-human-backlog.sh` (already enumerates own repos + reads REVIEW_ME) with a `@needs-auth` filter + plain output. Reuse the enumeration.
✂️ Petra: stop at v1 (lister). The class-(i) backlog is real (e588/7364/ad81/c624/0b37, N=2 passes) so the lister earns its keep; "step through + tick the box" is gold-plating — defer to v2 gated on the lister being used.
😈 Riku: mechanize-first agrees; two failure modes to pin — (1) the convention MUST mandate what-secret/where/command/why or the offline human is stuck; (2) `@needs-auth` must stay orthogonal to `@manual` (auth = provide a secret; manual = run/verify).
⚙️ Sage: naming — `@needs-auth` as the umbrella with a **broad** definition (any human-held secret OR interactive-auth), not a second marker.

## Decisions
- **D1 — one `@needs-auth` marker.** A single `@needs-auth` marker serves BOTH the class-(i) hands-lane reason ("hands because a human-held secret/interactive-auth is required") AND the a505 auth-queue membership. **Broad definition:** any human-held secret OR interactive-auth — sudo/askpass, polkit/pamac, ssh/login, gpg/credential, browser-OAuth, a decryption passphrase, a private export. **Orthogonal to `@manual`** (run/verify) — an item may carry both. *Out of scope:* minting `[hands:secret]`/`[hands:device]` lane sub-tags (rejected — `[host:X]` already covers device-bound (ii), and sub-tags add a 27-repo parsing surface); class-(iii) mis-laned MECHANICAL/INTENSIVE is a **db39 re-audit**, not a taxonomy change.
- **D2 — carrier = per-repo `REVIEW_ME.md` `@needs-auth` box.** Aggregated cross-repo by `/relay human --all` (`gather-human-backlog.sh`). **No new global queue file** (rejected — repeats the 9fdb unversioned-destructive-store hazard; per-repo boxes are versioned, travel with the work, and already aggregate at read-time). The convention **mandates fields:** what-secret · where-it-goes · exact-command · why. *Out of scope:* `~/.config/relay/auth-queue.md`.
- **D3 — executor-contract rule.** A relay child that hits an interactive-auth/secret wall RECORDS a conforming `@needs-auth` REVIEW_ME box instead of failing the unit, then clean-continues the separable remainder, **defaulting to clean-handback of the gated remainder** when separability is uncertain. This is a **versioned executor-contract change** (bump `references/executor-contract.md` `vN` + the `## Relay contract` pointer). Dissolves the a505 "strand the rest of the unit mid-session" failure.
- **D4 — tool = v1 offline lister only.** Extend `gather-human-backlog.sh` with a `@needs-auth` filter + a plain, human-readable (non-TSV) output mode (repo · what · where · command), **AI-free** (pure bash, no Claude session). **Do NOT fork a new repo-walker** (reuse the enumeration). **Defer v2** (interactive step-through + tick-back via flock'd `md-merge.py`) — gated on v1 being used (observe-before-preventing). *Out of scope:* v2 tick-back now; browser-OAuth *automation* (it is merely an `@needs-auth` type).

## Action items
- [ ] **a505** (re-laned `[INPUT — meeting]`→`[HARD — pool]`): define + document the `@needs-auth` convention (mandatory fields what/where/command/why; broad definition; orthogonal to `@manual`) in a reference doc (`references/hard-lanes.md` or `conventions.md`), AND add the D3 executor-contract rule + bump the executor-contract `vN` and its pointer. Contract a future test verifies: a child hitting a simulated auth wall writes a conforming `@needs-auth` box + clean-handback of the gated remainder; `gather-human-backlog.sh`/roadmap-lint recognize `@needs-auth`. (this note) <!-- id:a505 -->
- [ ] **1750** (re-laned `[INPUT — meeting]`→`[HARD — pool]`): extend `gather-human-backlog.sh` with a `@needs-auth` filter + plain offline output (AI-free lister); retro-tag the existing class-(i) backlog (zkm-signal e588, zkm-threema 7364, zkm-chatgpt ad81, bahnbetAI c624, zkm 0b37) with conforming `@needs-auth` REVIEW_ME boxes so the lister has day-one content. Contract a future test verifies: the lister prints each tagged box with all four fields and runs with no network/AI. (this note) <!-- id:1750 -->
- [ ] v2 interactive step-through + REVIEW_ME tick-back (flock'd `md-merge.py`) — **DEFERRED**, gated on v1 lister usage (observe-before-preventing). Tracked under id:1750's acceptance, not a separate id yet.
