# 2026-05-21 — Orphan-scan redesign: F-A vs F-B (hash ID)

**Started:** 2026-05-21 09:34
**Session:** 905f99b2-637f-4021-a325-923bf3364296
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing)
**Topic:** Decide which orphan-scan redesign (F-A auto-mark-archived, F-B hash-based item ID, both, or neither) ships so orphan-scan can be re-enabled with an acceptably low false-positive rate.

## Agenda
1. Root-cause confirmation — which FP sub-class dominates?
2. The fork — F-A vs F-B vs both vs neither
3. Legacy notes — 62 un-IDed action items across 26 notes
4. Frozen-record principle & ID textual form
5. ID generation mechanism + re-enable gate

## Empirical inputs
- Disable-point scan (2026-05-14 20:16): notes=21, unchecked=46, cand4=38 → ~83% candidate rate; user reported ~1/10 shown was genuine.
- cand5 ≥ cand4 in all rows → longer key is worse (4-word confirmed best previously).
- Current state: 26 meeting notes, 62 unchecked action items, TODO.archive.md present (15 KB).
- Two prior symptomatic fixes (union-read, output-cap) both failed → user disabled the feature.

## Discussion

### Agenda 1 — Root-cause confirmation
- **Archie:** scan emits a candidate only when the 4-word key misses the union (TODO.md + TODO.archive.md). Two FP sub-classes: (α) open-but-reworded in TODO.md; (β) closed-and-reworded in archive. Common factor = phrasing drift, not closure status.
- **Riku:** disable note confirms BOTH α and β. F-A's trigger ("found in archive") addresses β ONLY — leaves α (the recurring class) unaddressed.

### Agenda 2 — The fork
- **Riku/Archie:** F-B SUBSUMES F-A. Stable short IDs (`<!-- id:XXXX -->`) + exact-match scan kill both α and β, with NO meeting-note checkbox mutation. `archive-done.sh` moves whole lines so the ID citation survives archival.
- **Petra:** N=2 ok — fuzzy is empirically broken at 83% FP and got the feature killed. Not a speculative abstraction.
- **Riku (pre-emption — repeated-fix intolerance, high conf):** orphan-scan symptom-patched twice (union-read, output-cap), resurfaced both times, then disabled. F-A is structurally a third partial fix.
- **Sage:** with F-B adopted, F-A becomes largely redundant; only residual role is cosmetic legacy cleanup, which collides with the frozen-record principle.
- **Decision: F-B alone.**

### Agenda 3 — Legacy notes
- **Archie:** options: (a) backfill all 62 [mutates 26 frozen notes]; (b) clean cutover [scan ignores un-IDed lines]; (c) fuzzy fallback [REJECT — reintroduces 83% FP]. (b′) = one-time triage to rescue genuine orphans, then cutover.
- **Riku de-escalation:** 62 occurrences ≠ 62 problems; genuine residue ~0–2 (small-cardinality).
- **Empirical:** post-triage sweep found 0 genuine open orphans (all candidates in TODO.archive.md [x] or tracked under different phrasing).
- **Decision: triage once (confirming 0 genuine orphans), then clean cutover.**

### Agenda 4 — Frozen-record & ID form
- **Sage:** ID authored at creation = part of frozen record; no retrofitting needed. HTML comment `<!-- id:oa3f -->` matches existing `<!-- inline -->`/`<!-- tracked -->` convention (8 existing instances).
- **Riku:** ID must be a **stored opaque token**, frozen on write, never re-derived from mutable text. "Hash-based" was a misnomer.
- **Decision: HTML comment form `<!-- id:XXXX -->`.**

### Agenda 5 — ID generation + re-enable gate
- **Archie/Sage:** extend `append.sh` with `new-id` subcommand (collision-free, no new allowlist entry) rather than inline openssl (new allowlist + no check). Correctness belongs in script (77% prose-bypass).
- **Riku:** generator must check union notes+TODO.md+TODO.archive.md.
- **Petra:** remove dead 4-word/5-word key code (drift-aversion).
- **Re-enable gate:** completion checklist + observation period (advisory mode for N meetings; zero FP recurrence → fully trust).
- **Sage:** F-B must be applied to BOTH `meeting/SKILL.md` and `meeting-live/SKILL.md` (dual-surface).
- **Riku forward-flag:** F-B is now the canonical meeting↔TODO correlation primitive; moots hash-ID mention in F1–F3 GH-issue item.
- **Decisions: `append.sh new-id`; checklist + observation period.**

## Decisions

- **D1** — Adopt **F-B** (stored opaque `<!-- id:XXXX -->` frozen on write, exact-match scan). F-A not adopted; subsumed. Out of scope: 4-word fuzzy key for ID-bearing items.
- **D2** — Legacy: **one-time triage then clean cutover** (scan permanently skips un-IDed lines). Triage confirmed 0 genuine orphans. Out of scope: backfilling frozen notes; permanent fuzzy fallback.
- **D3** — ID form: **`<!-- id:XXXX -->`** at line end, consistent with existing comment convention. Same token in TODO.md mirror. Out of scope: visible inline tag.
- **D4** — ID generation: **`append.sh new-id` subcommand** (collision-checked against union). No new allowlist entry. Out of scope: inline openssl, separate script.
- **D5** — Re-enable gate: **completion checklist + observation period** (advisory mode → authoritative after N meetings with zero spurious candidates).

## Action items

- [x] **Add `new-id` subcommand to `append.sh`** — shipped 2026-05-21. <!-- id:a1c7 -->
- [x] **Rewrite `orphan-scan.sh` match logic** — exact ID match + un-IDed skip + dead code removed. Shipped 2026-05-21. <!-- id:b3e9 -->
- [x] **Update `meeting/SKILL.md` Step 5b** — ID minting required. Shipped 2026-05-21. <!-- id:c4f2 -->
- [x] **Mirror Step 5b into `meeting-live/SKILL.md`** — also fixed raw find → find-todos.sh. Shipped 2026-05-21. <!-- id:d8a5 -->
- [x] **One-time legacy triage** — 0 genuine open orphans; clean cutover confirmed. Done 2026-05-21. <!-- id:e6b1 -->
- [ ] **Orphan-scan observation window → trusted** — advisory mode active; drop ADVISORY caveat after N meetings with zero spurious candidates. <!-- id:f2d4 -->
- [x] **Close F-A + update F1–F3 TODO item** — done in TODO.md 2026-05-21. <!-- id:0c93 -->
