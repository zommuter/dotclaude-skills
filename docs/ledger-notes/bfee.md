# id:bfee

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

**EDITED ON RELOCATION (2026-09-02, `id:40c0`) -- the verbatim claim above is amended
for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any
prose already in that section arrived by an earlier pass and is untouched here.** Fleet-rule violations found in the relocated
prose were FIXED here rather than parked: 7 punctuation em dashes became `--`. Nothing else changed: no word, figure, marker or line break was
altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation
included.

## From TODO

-- a working 3-class detector (satisfied-gate / stale-in-flight / spent-trigger) built on `relay/scripts/resolve-gates.sh`, which independently re-found it-infra `id:63b0`. It lives only in a session scratchpad today. Two false-positive classes were found and FIXED in it and MUST survive any rewrite: (1) a DECOMPOSED / `route:hard-split` container annotation is not a gate claim; (2) `resolve-gates.sh` reports DANGLING targets in a separate column, so filtering on `block=1` alone reads a dangling gate as satisfied. Measured precision after both fixes was still only 4 genuine of 10 -- the naive "gate satisfied + wears the construction sign" rule is weak because the `id:3801` `route:X` annotation carries the REAL blocker. Design + acceptance live in `id:4386`; this item is the script itself. <!-- id:bfee -->

  **(a) CONSUMED-STATE** -- work that is DONE or UNBLOCKED but still reads as pending. Three classes seen: **A** an open item wearing blocked prose whose typed gate targets are all closed; **B** an item whose body still claims a run is IN FLIGHT when it finished (it-infra `id:5a51`'s attended run completed 2026-08-23 12:40 and sat unharvested EIGHT DAYS); **C** a spent pre-registration (lean4btc's lane-policy re-check had fired -- `a63e`+`c4c3` landed hard-execute -- and nobody noticed).
  **⚠ Build class A on the REAL rule, not the naive one.** The naive signal ("typed gate satisfied AND item wears `🚧`") is WEAK: measured on the fleet it gave **10 hits of which only 4 were genuine**. The `🚧 GATED (auto, id:3801; route:X)` annotation carries the ACTUAL blocker and it is usually NOT the typed edge -- six items were correctly parked on a compute budget, an owner decision, a design conflict, a deferred sibling, or a false premise. One even carried `<!-- gated-on:30eb=pass -->`, recording the pass explicitly. **The rule that works: the gate is satisfied AND the `🚧` annotation names THAT gate.** Two further false-positive classes were found and fixed during the session and must be in the tests: a DECOMPOSED/`route:hard-split` container annotation is not a gate claim, and `resolve-gates.sh` reports DANGLING targets in a separate column -- filtering only on `block=1` reads a dangling gate as satisfied.
  **Compose, do not reimplement**: `relay/scripts/resolve-gates.sh` is the canonical `gated-on:` resolver (id:65f5) and already spans BOTH archives; an item it does not report at all has every target resolved AND closed.
  **(b) CROSS-LEDGER DRIFT** -- `meeting/orphan-scan.sh --cross-ledger` already exists and is correct; it is simply never run fleet-wide. A 57-repo sweep found **7 drifted ids in 4 repos** (ai-codebench `b874`, escapement `dbb6`, lodelore `49bf`, zkWhale `e05d`/`be4b`/`2913`/`509e`), every one the same direction -- `TODO:[ ]` while `ROADMAP:[x]`. Wrap it in a fleet loop honoring `relay.toml` (`# path:` overrides) and `--exclude`.
  **Acceptance**: both sweeps runnable per-repo and fleet-wide, read-only, with tests covering the false-positive classes named above; surfaced in `/relay human`'s gather output. **Done-check**: the tests reproduce the 4-of-10 precision result on fixtures, and a clean repo emits nothing.
  **Related**: the `routed:de8f` inbox item (roadmap-lint's DEAD-GATE is archive-blind, which is what made a satisfied gate read as dead during this very session).

