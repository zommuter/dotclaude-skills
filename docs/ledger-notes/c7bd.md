# id:c7bd

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

Meeting 2026-08-22-1402 established that multiple concurrent Lean toolchain pins are LEGITIMATE, not drift — ~/.cache/mathlib is a content-addressed multi-rev store (16,936 .ltar, 850 MB) that serves several revs at once, and the bump-together cadence has been retired. So a majority-comparison check would flag correct states as errors. INVERTED fix for relay-doctor.sh check 13 (id:50c4): ask 'is each consumer's pin backed by a tree the store can actually SERVE?' — verified LOCALLY (ltars present, or a live extracted tree on that rev), not by comparing repos to each other. Two riders: (a) a repo-root-only glob misses the divergent pins — lodelore's is at lean/lean-toolchain and toesnail's at verify/lean-toolchain; (b) per the fleet's mechanize-first rule a failing check must FORCE a resolution, not silently no-op. Still true and unfixed: the check currently compares only mathematical-writing <-> relay-core and is blind to lodelore, physlib and lean4btc. <!-- id:c7bd -->
