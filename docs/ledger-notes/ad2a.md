# id:ad2a

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From REVIEW_ME

`id:1a03`'s own declared done-check, quoted verbatim in the now-closed `id:32f9` line (`ROADMAP.archive.md`), is a naive `git grep -nE` for an em-dash-delimited lane bracket over `relay/scripts/*.js *.mjs *.py`. MEASURED this review: the count fell 53 -> 49 across this window (the S5b emitter flip), and I read all 49 remaining hits individually -- every one is PROSE: docstrings and `#` comments in `handback-followup.py`(3), `backtest-historical.py`(6), `tracker/ledger-map.py`(5, incl. two `%s` error-message templates that quote the offending raw tag back to the user), `drain.mjs`(1), and log/prompt/refusal-reason string literals in `relay-loop.js`(32) + `handback-guard.mjs`(2) that deliberately name the RETIRED spelling so a child does not sweep for it (the id:7517/routed:2d94 failure). ZERO are ledger emitters. So no emit-side work is owed and `id:32f9` is genuinely closed. S10 (`id:da55`) already gates on the right thing -- `lane-delimiter-scan.sh --live-only` over the ledgers, which exits 0 here -- so nothing is broken; the risk is purely that the stale grep reads as an unfinished migration. Owner's call: correct the recorded done-check in `docs/migration-em-dash-delimiter.md` to cite the scanner, or leave it and accept the re-file risk. <!-- id:ad2a -->
