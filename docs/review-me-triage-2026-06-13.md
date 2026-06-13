# REVIEW_ME triage — divide-and-conquer + 80-20, 2026-06-13

**88 open REVIEW_ME items** across the relay-managed repos, tiered so the ~87-item wall
collapses to a handful of decisions. (Several repos are already clean: dotclaude-skills,
cyclotomic, llm-from-scratch, project_manager, proton-moresync, puzzle-pwa, recurheb,
trAIdBTC, linguistic-universals.)

| Tier | Count | What | How to clear |
|---|---|--:|---|
| **R1 trivial-confirm** | 38 | low-risk interpretation where the default is clearly right | **batch-confirm** (one approval → tick all with "confirmed: <default>") |
| **R2 genuine-judgment** | 25 | real product/domain/taste calls | the user decides (top-12 below) |
| **R3 blocked/deferred** | 18 | gated on a [HARD] design or hardware/fixture | leave gated; don't queue for executors |
| **stale** | 7 | already resolved/contradicted | prune |

**80-20:** approving the **R1 batch (38) + 7 group rulings** closes **~45 items with one sitting**; the 25 R2 are the only ones genuinely needing per-item thought, and the **top-12** below are the high-leverage subset of those.

## Group rulings (decide once → closes many)
1. **zkm-plugin RuntimeError error-contract** (zkm-notmuch + social + claude-ai, +core doc) — "plugins raise RuntimeError; core amender catches → one-line WARN." Record in zkm core ARCHITECTURE.md → closes 3 boxes + pre-answers future plugins.
2. **zkm-plugin version-derivation** (all 11 plugins) — "canonical version = pyproject; PLUGIN_VERSION via importlib.metadata + plugin.yaml fallback." One ruling (zkm-ner df05) store-wide.
3. **zkm-plugin social-handle URLs** (zkm-social + zkm-vcard) — handle entity values are full URLs, mirroring zkm-vcard convention.
4. **zkm RFC/format defaults** (calendar 4 + eml + scan + pdf ≈ 12) — RFC-faithful low-ambiguity readings; single batch-confirm.
5. **Android-SDK / build-env gated** (droidclaw + rawrora, 5) — standing ruling: unverified until run in Docker-on-fievel / Termux / on-device; not passes.
6. **HARD design items stay blocked** (collaib 948d/aaaf, zomAI bcb8 adapter, claude-organizer 32fc, meeting-rpg broker) — executors must not guess; each needs a design session.
7. **On-device/ROM confirmation** (rawrora gyro axis/sign, romtrans visual) — stay open, hardware-gated; executor can't close unilaterally.

## Top-12 (80-20 — the high-leverage R2 calls; do these first)
1. **zkm core 1098** — `ZKM_BYPASS_RUN_GUARD` bypasses BOTH guards (one switch)? *Widest blast radius — affects every plugin user.* (R2)
2. **zkm-ner df05** — pyproject-canonical version store-wide? *One ruling → all 11 plugins.* (R2)
3. **zkm-notmuch (group 1)** — RuntimeError contract → ARCHITECTURE.md. *Closes 3 + prevents recurrence.* (R1)
4. **zkm-calendar (group 4)** — batch-confirm the 4 RFC-5545 readings. *4 executor items in one pass.* (R1)
5. **zkm-scan + zkm-pdf (group 4)** — batch-confirm 4 OCR/threshold defaults. (R1)
6. **droidclaw dd73** — delete the dormant `:gateway` module, or keep doc-only? *Executor blocked; opposite deliverables.* (R2)
7. **ai-codebench bisect difficulty (3484)** — does the bisect test reject a full revert as intended? *Guards the benchmark task tier.* (R2)
8. **zkWhale fb27** — P2PKH/bip137 honest label (confirm label, defer entry flow). (R1)
9. **zkWhale 815a** — remove the stale testnet4 deploy from public/. (R1)
10. **zkm-eml d206** — README strictness: forbid retired EML_* vars even in a migration note? (R2)
11. **zkm-social 204c** — LinkedIn headline 15-char abbreviation threshold (taste). (R2)
12. **meeting-rpg 0951** — broker replay-flag protocol shape (cross-repo w/ dotclaude-skills inbox; hard to change post-ship). (R2)

## Recommendation
1. **One batch-confirm pass** over the 38 R1 + the 7 group rulings (≈45 items) — the relay can tick them with "confirmed: <default>" notes once you approve the batch (same flow as the 2026-06-13-1751 meeting). 2. **Prune the 7 stale.** 3. **You decide the 25 R2**, starting with the top-12 (1098 + df05 first — widest blast radius, block the whole zkm-* cluster). 4. **Leave the 18 R3 gated** (marked [HARD]/ENV-GATED so executors skip them). Full per-repo breakdown: the triage agent output in this session's transcript.
