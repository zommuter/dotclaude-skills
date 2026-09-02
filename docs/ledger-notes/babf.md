# id:babf

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— found by the test-integrity review of the 2026-08-21 window (mutation testing, 11/12 mutations caught; these are the residuals). `tests/test_ledger_slice_dispatch_e68f.sh`'s two loop-side assertions grep `relay-loop.js` for the literals `ledger-slice.sh` and `slice_path`; `tests/test_suppression_demotes_bc2b.sh`'s loop-side half is `grep -q 'bc2b'` plus a `--exclude` regex. In both cases a script referenced only from DEAD code — or a marker comment plus an unrelated `--exclude` call — would pass. Both behavioural halves are strong (the reviewer confirmed `sliceLedgerForUnit()` at `relay-loop.js:3447` genuinely sets `unit.slice_path` before the gate, and killed `allow()`-returns-True in bc2b), so this is a hardening item, not a live defect. It is the [[relay-builtgreen-but-unreferenced]] class in test form: grepping for a NAME proves the string exists, not that the call is reached. Fix: assert the wiring behaviourally (drive the code path and observe the effect) rather than by literal match. **Related finding worth keeping:** mutation M10 — printing `slice-bytes:` BELOW the path instead of above — SURVIVED the e68f test (which only requires the path be "on stdout") and was caught ONLY by `tests/test_prompt_size_gate_slice_35b7.sh`. So 35b7's test is currently the SOLE guard of `ledger-slice.sh`'s last-line stdout contract; if that test is ever narrowed, the contract loses its only pin. <!-- id:babf -->
