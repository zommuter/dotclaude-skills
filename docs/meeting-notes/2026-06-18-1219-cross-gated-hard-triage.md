# 2026-06-18 — Cross-project gated-[HARD] backlog triage

**Started:** 2026-06-18 12:19
**Session:** 8d4be212-e466-44c5-9cd1-4fe177cd6bd5
**Mode:** /meeting --cross — portfolio triage of the ~40 gated-[HARD] items surfaced by `/relay human --all`

Constraints from the user: triage as much as feasible autonomously; apply ALARA to the
decisions actually needed; 80-20 order (highest-leverage first); resumable (postpone the tail).

## Method

Four read-only Explore agents worked up the backlog by cluster (zomni; zkm scanned-only +
related; isochrone/puzzle/chidiai/ai-codebench; defer-set gate verification). Each item sorted
into PARKED (gate genuinely unmet), EXECUTABLE (no decision — just dispatch/hands), or
NEEDS-DECISION (genuine user choice). Only 4 of 40 needed a decision this round.

## PARKED — gate verified still closed (no decision)

- **zomni**: id:560c (waits on 1d14 + fievel `@zport` rule; ordering gate now satisfied by the
  1d14 decision below), id:6e27 (needs running DBH game), id:7cf2 (live mem-logger: 0 OOM-kills,
  PSI-full=0.00), id:c7f7 (superseded by firewall id:1fb1 + loopback bind id:f6fc — correctly closed)
- **zkm**: id:f103 (gated on a core retract-merge-mode `/meeting` first — data-loss risk), id:8740/62cb/a711 (Gated Phase 3 — WebUI/amender), id:107 (demand gate: no concrete 3rd-provider export)
- **meeting-rpg**: id:383b (blocked on user action id:ec51 — configure opencode model), id:1e36 (needs n=3-5 human-run meetings, none collected)
- **proton-moresync** id:5cc5 (no first external user), **project_manager** id:007b (verified: history.jsonl = zomni only), **chidiai** id:1e77 (design ratified, gated on ≥50 outcome rows — zero on disk), **ai-codebench** id:efc2 (gated on the 244b GPU matrix run)
- **dotclaude-skills**: id:de4e (already-decided-deferred 2026-06-17 on quota economics; only a cosmetic stale "DECISION GATE" label remains — see action item), id:3346 (gated on opencode port + a >200k-ctx meeting)

## EXECUTABLE — no decision, needs dispatch or human hands

zomni id:fd1e (CF app, needs secret; sequence after 1d14/560c), id:935e (done; live gaming test
is [HUMAN]), id:9321 + id:fd30 (INTENSIVE GPU), id:7bef (etckeeper sudo); isochrone id:3fcb
(decided D6) + id:7b35 (zomni/JVM-gated); dotclaude-skills id:401c (recurring strong audit) +
id:dba3 (investigation + offline probe runnable now; live-seed gated behind d0c0); puzzle-pwa
id:7590 defensive snap-guard (ships regardless of the semantics decision).

## Decisions

### D1 — zomni id:1d14 off-LAN transport (LEVERAGE: unblocks 560c + fd1e)
**Decided: prefer CF private-network (ZTNA), conditional.** Adopt ZTNA only if it (a) works on
Cloudflare's **free tier** and (b) exposes the route **only to fievel** (not publicly). First build
step = that verification. If either fails → **fall back to the SSH reverse-proxy hop**
(`cloudflared access ssh`). Ungates id:560c (ordering gate satisfied).

### D2 — zkm id:02bd (subsumes id:9475) unified scanned-only routing (LEVERAGE: closes 2 HARD; fixes latent correctness bug)
**Decided: one `zkm.pdftext` core helper** (canonical char count, zkm-pdf's `.strip()`+skip-empty
semantics) consumed by both plugins via a single shared `pdf_text_threshold` key → cross-plugin
drift (PDF processed by neither) impossible by construction. **Discriminator: PILOT a per-page
density / text-coverage ratio; fall back to an evidence-backed char-count default** (calibrate from
`zkm-pdf-skipped.jsonl`) if the pilot doesn't beat it. zkm-scan `min_text_chars=10` OCR floor stays
separate. Old keys = deprecated aliases one release. Build still HARD (coordinated 3-repo).

### D3 — puzzle-pwa id:7590 copy-paste freeze (LEVERAGE: live freeze bug)
**Decided: fresh group ids + preserve internal layout + offset clearing ALL existing board
geometry (not just the source group), plus the defensive snap-guard (ships regardless).** Now
bounded → retagged `[ROUTINE]`.

### D4 — isochrone id:f4a7 vectorized contours PRIORITY (LEVERAGE: root-cause visual fix)
**Decided: hold a focused design pass** (mirror id:b104→sized-children) to emit a bounded item
with Acceptance + RED golden test, deciding retire-vs-keep raster + fold-honesty contract. Cheap
(substrate already landed). Next action = a `/meeting` design pass in isochrone, NOT executor dispatch.

## Finding — gate-resolution detection gap (user side-question)

`gather-human-backlog.sh` re-derives gated items by grepping ROADMAP every run (nothing goes
stale), and the relay pool's `discover-sig.sh` re-classifies when a repo's signature changes. BUT
there is **no active "external gate now satisfied → surface as actionable" detection**: gates that
resolve *outside* the repo (data volume accumulating → chidiai 1e77; first external user → proton
5cc5; an OOM event → zomni 7cf2; the 244b GPU run finishing → ai-codebench efc2) change nothing
in-repo, so they keep re-emitting as "needs a /meeting" until a human notices. → action item id:7ace.

## Postponed agenda (tail — resumable)

- zkm-ner id:7b4e (scrub/cache coherence — 3 named alternatives; data-integrity, medium leverage)
- puzzle-pwa id:6bef (custom n-gon: Z⁸ integer vs float coexistence — recommend reject-unsupported-n + defer free-placement)
- meeting-rpg id:5d27 (portrait license — real legal/cost decision, but deferrable until a public release is actually planned)

## Action items

- [ ] Gate-resolution detection: design a way for externally-resolving gates (data volume / first-user / OOM-event / GPU-run-done) to surface a parked [HARD] item as *actionable* once its condition is met, instead of re-emitting "needs a /meeting" until a human notices. Candidates: a per-item machine-checkable gate predicate the collector/discovery can evaluate, or a periodic "gate re-check" pass. See this note's Finding. <!-- id:7ace -->
- [ ] Relabel dotclaude-skills ROADMAP id:de4e: its "DECISION GATE" / "Needs a /meeting" heading is cosmetically stale (the meeting was held 2026-06-17; it is already-decided-deferred on quota economics). Adjust the label so a future dispatcher/triage doesn't read it as an owed decision. <!-- id:9c92 -->
- [ ] Postponed cross-triage tail (zkm-ner id:7b4e, puzzle-pwa id:6bef, meeting-rpg id:5d27) — resume in a follow-up /meeting when ready. <!-- routed-to-self, tracked here -->
