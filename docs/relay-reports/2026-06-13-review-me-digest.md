# REVIEW_ME digest — 2026-06-13

Cross-repo consolidation of open human-review boxes from the fables-turn relay.
Each box is a **judgment call encoded in a red test** — the reviewer baked an
interpretation into a failing spec and is asking you to *confirm or correct* it.
Source: the per-repo `REVIEW_ME.md` files (budget ~15 min/repo).

## Snapshot

**~94 open boxes across 18 repos.** Most are cheap confirmations; the minority that
are genuine forks are listed under "Decisions, not confirmations" — start there.

| Repo | Open | Repo | Open | Repo | Open |
|---|---|---|---|---|---|
| zkWhale | 8 | zkm | 7 | zkm-social | 8 |
| helferli | 7 | meeting-rpg | 5 | zkm-whatsapp | 6 |
| zelegator | 1 | isochrone | 2 | zkm-calendar | 6 |
| zkm-ner | 6 | zkm-scan | 6 | zkm-eml | 5 |
| zkm-claude-ai | 5 | zkm-claude-code | 5 | zkm-vcard | 5 |
| zkm-photo | 5 | zkm-pdf | 4 | zkm-notmuch | 3 |

(dotclaude-skills and trAIdBTC have a REVIEW_ME.md but 0 open boxes.)

## Owner-action items (blocking / external — not just a confirm)

- **zkWhale `DONATION_ADDRESS` is a placeholder** (roadmap:b0a8) — you must supply the
  real donation address **before deploy**.
- **zkWhale percentile dataset** (roadmap:73c0) — BitInfoCharts rich-list chosen as the
  citable source; it is a static snapshot (zero network calls), so refresh the band
  table + `asOf` periodically and spot-check two band counts against the source.
- **zkWhale HARD ordering** (ROADMAP) — paste-sig (id:9356) ranked above the percentile
  tile; G1 items proceed while **Matt's veto (TODO id:613e) is still formally pending**.

## Cross-cutting themes (decide once, applies to many repos)

1. **Naive-EXIF timezone → assume system-local.** zkm-scan (aae8) and zkm-photo (33e5)
   both attach the machine's local TZ to timezone-naive EXIF dates, and **both flag the
   same limitation: wrong for photos taken while travelling.** Decide store-wide: accept
   local-TZ default, or add a per-store configured TZ.
2. **Independently-added frontmatter scalars** — schema-collision risk worth a shared
   vocabulary: `status:` (zkm-calendar bdfb lowercase; zkm-whatsapp w11 `system`),
   `subject:` + keyword→`tags:` merge (zkm-pdf 03c2, zkm-scan), `recurrence_id:`
   (zkm-calendar 92ce), `project:` (zkm-claude-ai 303a), `ocr_confidence:` (zkm-scan 5d7d).
3. **`sha256:` field semantics diverge** — zkm-social (297a) stores a URL hash, not the
   file-content hash used elsewhere; blessed in ARCHITECTURE §Dedup. Confirm the
   divergence is acceptable long-term.
4. **Plugin error contract** — zkm-notmuch (1af4) raises `RuntimeError` specifically so
   core's amender loop catches it and prints a one-line WARN (not a traceback);
   zkm-claude-ai (fa28) pins `ValueError` *message text*. GitHub stays fail-fast (143c)
   while LinkedIn warns-and-continues (intentional: GitHub names are user-typed). Worth
   ratifying "raise RuntimeError, core catches+WARNs" as the canonical plugin contract.
5. **Updated docs re-enter amender/auto-commit scope** — zkm-vcard (05a9), zkm-calendar
   (92ce): re-running NER on updated docs is a deliberate cost so amendments don't go
   stale. Confirm the recompute cost is intended.
6. **Skip-ledger dedup keyed by (sha, reason, threshold)** — zkm-pdf (2abf), zkm-scan
   (8810): a threshold change re-logs / re-OCRs prior skips (experiments stay auditable).
   Consistent pattern across both.
7. **Observe-before-preventing (matches your design heuristic)** — deliberately inert
   counters/gates awaiting evidence: `ocr_confidence` observe-only (zkm-scan 5d7d),
   `valid:false` census opt-in (zkm 1a6f), RMS energy gate default-disabled (helferli
   6bc4). No action unless you want to flip a default.
8. **"Wrong entity worse than no entity" (FP minimization)** — LinkedIn drops the broad
   employer fallback (204c), NER currency allowlist is ISO-4217 ∪ {BTC, ETH} only (4352),
   lowercase IBANs gated by the mod-97 checksum (b081).

## Decisions, not confirmations (genuine forks — spend your time here)

- **helferli session-log ON by default** (0aaa) — writes voice-audio blobs to a
  gitignored dir on *every* local session (D6 "capture-always" discipline). Privacy/disk
  vs discipline: flip to opt-in?
- **helferli energy gate default** (6bc4) — enabling-by-default + a threshold needs
  captured-session evidence first.
- **zkm Phase 2 "done" definition** (roadmap prose) — "γ shipped + rm/gc + 14-day
  zero-intervention window" vs an NER-FP-rate target. Confirm the window and that FP
  targets stay out.
- **zkm-eml reprocess preserves foreign frontmatter keys** (9255) — multi-producer
  frontmatter vs "reprocess invalidates enrichment, re-run NER." Reviewer chose preserve.
- **zkWhale `signature_kind: 'bip137'`** new union member (fb27) + external-signing entry
  gate decoupled from `SUPPORTED_ADDRESS_TYPES` (9356).
- **zkm-claude-code queued-message dedup is lossy-but-simple** (dc2c) — confirm the
  false-positive/false-negative trade-off.
- **zkm-whatsapp duplicates message text into frontmatter** (w6f) — lossless rewrite +
  self-contained files vs storage cost; pre-fix files are not healed.
- **zkm-pdf empty-password encrypted PDFs are imported** (58d7); non-empty-password ones
  skipped with reason "encrypted" (not handed to zkm-scan).

## @manual smoke checks still pending

- **meeting-rpg** — live-meeting reload restores scrollback + pending question (gated on
  the id:0951 broker-ring + frontend backlog render); phone-on-LAN single-column layout;
  broker idle self-shutdown after `MEETING_BROKER_IDLE`.
- **zkWhale** — verify a proof in-browser and eyeball the percentile tile (sparkline,
  band dot, citation link).
- **zkm-photo** — real-camera HEIC EXIF extraction (deferred to the BDD scenario; unit
  fixture is a placeholder ftyp box).

## Already resolved (context)

- **isochrone** — all 8 boxes from the 2026-06-12 batch were ratified at the REVIEW_ME
  walkthrough (7 confirmed, f6d5 corrected → re-specced as roadmap:f154); the 2 open
  boxes are the new f154/f26d items.
