# 2026-06-21 — Mechanization audit across all skills (id:415b)

**Started:** 2026-06-21 22:02
**Session:** 5ae77734-0d90-435e-86ef-005f74ba595b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime / TSV-contract design — new), 🔩 Gil (git plumbing / worktree isolation — amendment), 🎛️ Orla (worktree-per-agent isolation — amendment), 🔭 Otto (constraint-archaeology — amendment)
**Topic:** Decide the decision-rule and structure-rigidity tradeoffs for replacing per-turn LLM-judgment skill steps with deterministic scripts, then mint per-skill build sub-items.

## Surfaced context
- Directive 2026-06-21 (id:415b): "review as much mechanization as sensible, even at the expense of requiring more rigid structure of e.g. TODO.md".
- Memory `feedback-mechanize-no-swallow-stderr`: a per-turn LLM-judgment step is unrepeatable, untested, silently wrong on edge cases; the trigger was `/relay reconcile --all` improvising an LLM sweep that swallowed git errors and falsely reported "clean" → fixed mechanically as id:4e14.
- Profile (pre-emption-eligible): (a) *manual-merge-over-heuristic* — prefers manual review tooling over an algorithmic pass when the call is irreducibly ambiguous; (b) *evidence-based constraint validation* — challenges inherited safety rules against live state.
- Past-meetings audit at start surfaced two forward orphans (id:9297, id:e986) — handoff.md C3 items marked "done in-session" but never closed in the ledger; used as this meeting's T2 logged-cost evidence for item-3.

## Agenda
1. The mechanization decision-rule + how far to tighten data grammar (the central tradeoff).
2. Cross-cutting: ban silent error-swallowing — mechanism + scope.
3. Per-skill triage: which candidate steps mechanize-now / guard / keep-judgment / defer; mint sub-items + sequencing.

## Discussion

### DP1 — decision-rule + grammar rigidity
Archie anchored in the established pattern (classify.sh, orphan-scan.sh, append.sh, md-merge.py, `proj` already moved prose-judgment into scripted I/O contracts). Riku named the symmetric failure mode: the trigger case (id:4e14) was a silent false-negative from an LLM sweep, but a rigid grammar has the inverse hazard — a strict parser silently *dropping* a legitimately-formatted line, moving silent-wrong from the LLM to the parser. Sage reframed it: the distinction isn't rigid-vs-lenient parser, it's what the parser does with input it can't handle — accept / reject-loud / reject-silent; the directive bans reject-silent. Petra applied the N=2 rule: grammar tightening earns its keep only where ≥2 distinct skill steps consume the same structured field (the `<!-- id:XXXX -->` token has 3 consumers → warranted; a single-consumer section rule → defer). Riku pre-empted on the profile's *manual-merge-over-heuristic* trait: the gate must not quietly promote a *judgment* step to "deterministic" just because a script can be written — when T1 is arguable, default to a guard, not a replacement. Sage crystallized the three-tier output taxonomy (M/G/K).

**RATIFIED — "Determinism-gate + M/G/K + fail-loud":**
- **T1 (determinism):** output is a pure function of inspectable inputs with a single correct answer a test can assert.
- **T2 (warrant):** ≥2 distinct consumers share the structured field, OR a logged failure proves the manual cost (e.g. id:4e14).
- **(M)** Mechanize — replace with tested script (T1+T2); **(G)** Guard — keep the LLM/human step, wrap it in a deterministic linter that fails LOUD (T1 arguable, or T1-pass/T2-fail); **(K)** Keep — irreducible judgment (fails T1).
- Grammar tightening allowed only with **loud rejection** (exit non-zero + name the offending line), never silent skip.

### DP2 — cross-cutting: ban silent error-swallowing
Archie: the clearest deterministic deliverable, and a Guard not a Mechanize — a grep over skill `*.sh`/`*.py` for `2>/dev/null` / `|| true` / `|| :`, in `tests/`. Riku's two objections: (1) legitimate swallowing exists (`command -v foo 2>/dev/null`, `rm -f`, repo-probing `git rev-parse 2>/dev/null`) — a blanket ban rots into reflexive escapes; (2) observe-before-preventing argues against a day-one hard gate — but here frequency is *knowable* (grep + the id:4e14 incident), so accept a gate conditioned on an inline justification + an advisory sizing pass. Sage matched the existing suite idiom (`# roadmap:XXXX` headers): a match is a violation unless it carries `# swallow-ok: <reason>`. Petra scoped it to this repo's skill tree (NOT a global pre-push hook — id:ebd0's domain) and demanded size-before-gate. Riku's final concession: an empty `# swallow-ok:` reason must itself fail (no rubber-stamp).

**RATIFIED — "Advisory first, then hard gate":** `tests/test_no_silent_swallow.sh`; violation unless inline `# swallow-ok: <non-empty reason>`; ship advisory → size + annotate legitimate swallows → flip to suite-failing. First build item (it protects every other mechanization from reintroducing the id:4e14 regression).

### DP3 — per-skill triage
Archie ran the six-skill list through T1/T2. Headline: **relay is already the most-mechanized skill** (discover-repos.sh, discover-sig.sh, gather-repo-state.sh, gaming-scan.sh, claim.sh, relay-econ.py all deterministic; residual LLM bits tracked by id:23fe, id:cfa9, id:7ace, id:4e14-done) → cross-reference, don't re-mint. Riku fought the git-diary row: "mine vs not-mine" attribution is the judgment call that, done wrong, commits a sibling session's WIP (id:3558 recurrences are real) — do NOT mechanize it into an ownership-guessing heuristic (manual-merge stance); the **G** guard (loudly surface, refuse silent inclusion) is correct, full **M** gated on id:3558. Sage upgraded the meeting-mirroring row: `orphan-scan.sh` forward mode IS the deterministic linter the directive asks for — the gap is it runs as a meeting-*start* advisory, not a hard *write-back* assertion; this very session's two forward orphans are the T2 logged cost. Petra's T2 gate collapsed the six-skill sprawl to ~5 items and rejected speculative relay/hooks mints.

M/G/K verdicts:
- **todo-update:** TODO.md grammar + scripted add/dedup/mark-done = **M** (own /meeting — chewy fail-loud-parser design); done-verification (tests-green ∨ confirm) = **G**.
- **meeting:** action-item↔ledger mirroring (Step 5b) = **G** (wire existing orphan-scan as a hard write-back assertion); classify.sh/id-mint/append = **M done**, C1 "design covers item" = **K**; persona-dup = **G** (= existing id:d44d).
- **git-diary:** Step 1c attribution = **G now / M gated on id:3558**.
- **relay:** mostly done/tracked — cross-ref only; acceptable-dirt = **K**.
- **projects:** dashboard sort = **G (low)**; `proj` = the deterministic model.
- **hooks/statusline/tools:** **K/clean** — DP2 covers the cross-cutting risk.

**RATIFIED — "mint focused set, keep id:415b as umbrella; build #1 now"** (user directive "1 for now").

### AMENDMENT — "upgrade diary etc. to worktrees" + "much of diary's design is historical (permission-avoidance) and may be vestigial now"
Gil: worktree-per-session *structurally dissolves* project-repo ownership-questioning (separate tree/index/HEAD → no shared dirty tree to disambiguate), strictly better than any attribution heuristic — but the session must *launch* in the worktree (git-diary can't retrofit at commit time). Orla: that IS id:3558/D5; cost catalogued under id:e79b (per-worktree dep dup, launch friction). Gil's shape distinction: worktrees fit the **work repo** (disjoint trees, branch-per-session, flock'd merge) but NOT the **shared diary file** (`~/src/claude-diary` `DIARY.md` — one append file, N sessions → contention just moves to merge time); diary-file contention stays a flock problem = id:3b18 (manifest-mode silent no-op). Riku: the redirect re-points existing items, it doesn't replace the guard — worktree-per-session is the durable fix, the guard stays interim (most sessions aren't launched in worktrees today, and id:3558 has been open since June with real recurrences). Orla: the audit just produced a *second independent* argument for id:3558 — it makes a whole class of mechanization (file-attribution) unnecessary; the cheapest mechanization is the one you delete.

Otto (constraint-archaeology), on the user's second point: much of git-diary's machinery (manifest mode, the flock dance, the Step 1c attribution prose) was built defensively against **edit-mode permission-prompt avoidance** + **pre-auto-mode parallel-edit fears**; auto-mode + Claude Code updates may have mitigated those reasons. Building new guards on possibly-vestigial scaffolding is premature → a **re-justification audit** (per mechanism: what constraint did this dodge; does it still bind under the current harness?) should *gate* the diary-touching guards. Riku: this is the profile's *evidence-based-constraint-validation* trait firing; cheap to check, prevents mechanizing a vestige.

**RATIFIED (option 1):** git-diary guard = explicit interim; re-point id:3558 (+ second motivation + shape distinction); diary-file contention = id:3b18; mint a re-justification audit that gates the diary-touching guards.

## Decisions
- **D1 (DP1):** Mechanize a step only via the **determinism-gate**: T1 (pure function of inspectable inputs, single correct answer a test asserts) + T2 (≥2 consumers OR a logged failure-cost). Tag every candidate **M / G / K**. Grammar tightening permitted ONLY with **loud rejection** (exit non-zero + name the line), never silent skip. Arguable-T1 → **Guard**, not replacement. *Out of scope:* a cross-skill grammar DSL; rewriting all skills at once.
- **D2 (DP2):** Ban silent error-swallowing via `tests/test_no_silent_swallow.sh` (greps `2>/dev/null` / `|| true` / `|| :`; violation unless inline `# swallow-ok: <non-empty reason>`). **Advisory first → size+annotate → flip to suite-failing.** Scope = this repo's skill tree only. *Out of scope:* global pre-push hook (id:ebd0).
- **D3 (DP3):** Mint the **focused set** below; **relay = cross-reference only** (already mechanized); **id:415b stays OPEN as the tracking umbrella**. Build #1 now; #2–#6 tracked. *Out of scope:* per-skill /meeting decomposition for relay/hooks (fail T2).
- **D4 (amendment):** git-diary attribution guard is an **interim**; **id:3558 (worktree-per-session)** is the durable fix and gains a second motivation + Gil's work-repo-vs-shared-diary-file shape distinction; diary-file contention = **id:3b18** (flock). *Out of scope:* a new worktree-launch item (id:3558/D5 owns it).
- **D5 (amendment):** A **re-justification audit** of git-diary/diary defensive machinery against current harness behavior **gates** the diary-touching guards (#4/#5) — don't mechanize a vestige.

## Action items
1. **[build NOW] `tests/test_no_silent_swallow.sh`** — swallow-ban, advisory→hard-gate, `# swallow-ok:<reason>` annotation (empty fails). Contract: flags un-annotated `2>/dev/null`/`|| true`/`|| :` in skill `*.sh`/`*.py`; advisory exit-0 prints count; documented flip path. (D2) <!-- id:4347 -->
2. **[/meeting] todo-update: formalize TODO.md grammar + fail-loud parser + scripted add/dedup/mark-done.** Contract: a `todo-lint.sh` that rejects-and-surfaces non-conforming lines; add/dedup/mark-done become script ops. (D1/D3 — own session) <!-- id:9b13 -->
3. **[G] meeting: end-of-meeting write-back assertion.** Contract: at Step 2b/2e, invoke existing `orphan-scan.sh` and **fail loud** if any just-minted action-item `id:` did not land in TODO. (D3 — logged cost: id:9297/id:e986) <!-- id:69a3 -->
4. **[G interim, gated] git-diary Step 1c: attribution-surface guard.** Contract: loudly surface dirty files not in the session's edit-set + refuse silent inclusion. Explicit INTERIM until id:3558. **Gated on #6 (id:8aba).** (D3/D4) <!-- id:3c4c -->
5. **[G, gated] todo-update: done-verification guard.** Contract: block an `[x]` flip unless tests-green or explicit confirm. **Gated on #6 (id:8aba)** where it touches diary machinery. (D3) <!-- id:eb92 -->
6. **[audit] Re-justify git-diary/diary defensive machinery against current harness.** Contract: per mechanism (manifest mode, flock dance, Step 1c prose), record the constraint it dodged + whether it still binds under auto-mode + current Claude Code; output gates #4/#5. (D5) <!-- id:8aba -->

Cross-references (noted on existing items, NOT minted): id:3558 (+2nd motivation, shape distinction), id:3b18 (diary-file flock bug), id:23fe/id:cfa9/id:7ace/id:4e14 (relay already-tracked), id:d44d (= item-3-adjacent persona-dup guard).
