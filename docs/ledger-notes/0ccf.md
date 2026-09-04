# id:0ccf

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

**What actually happened**: every earlier figure was taken while an unrelated `lake build` of mathlib saturated all 8 cores for ~90 minutes (load 32), so "35s at HEAD / 50s in-tree" and the apparent hang were load artifacts. The methodological error was reading a fired `timeout N` as "blocked forever" without establishing an upper bound, then sampling `ps` on the bash WRAPPER rather than the scanner. **MEASURED ON A QUIET BOX (load 5.4), 3 runs each**: HEAD **5.3-5.5s**; working tree **11.2s**. So the archive-union fix (`routed:42c9`/`8b21`) costs **+107%, not the +43% first filed** — the load inflation had masked how large the real regression is. **It still buys correctness** (row count 250 → 246: four archived items no longer falsely reported as `promote`, confirmed on real repo data, which is exactly the `8b21` defect) — but it is a doubling on a script that **82 of 439 tests invoke and which accounts for 61% of total suite CPU**, so it is not a free correctness win. **FIX AVAILABLE, MEASURED 8.1x, not yet applied**: precompute the ROADMAP twin-id set once into an associative array (today line 351 re-greps the entire 245 KB roadmap ONCE PER OPEN ITEM — 476 items today) and replace three per-item `grep` forks with bash-native `[[ ]]`. Live repo 11.4s → **1.4s**, **stdout byte-identical**, equivalence proven against a purpose-built edge-case ledger (ROADMAP twin, ROADMAP.archive twin, gated twin with trailing note, `ref:` pointer, `Relay:` rollup, two markers on one line, and the `id:1312` prose-mention-is-not-a-twin guard). Patch and full optimised file are in this session's scratchpad `prof/`. Forks are NOT the main cost (476 forks = 0.3s; 476 × 245 KB greps = 2.2s). **Cost scales as O(open TODO items × ROADMAP bytes)**, so the suite gets measurably slower every time the ledger grows — a live degradation path independent of any test change. **Blast radius**: `classify-repo.sh` calls it; `relay-doctor.sh` → `classify-repo.sh` → `unpromoted-scan.sh` inherits the whole cost. <!-- id:0ccf -->

## Original title (verbatim, before the `id:64f9` rewrite)

**`unpromoted-scan.sh` is the suite's dominant cost, and the 2026-08-14 archive-union change DOUBLED it. THIRD REVISION — the two earlier framings ("hangs", "blocked not spinning") were BOTH WRONG and are retracted.**
