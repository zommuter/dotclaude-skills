# id:bfee

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

-- a working 3-class detector (satisfied-gate / stale-in-flight / spent-trigger) built on `relay/scripts/resolve-gates.sh`, which independently re-found it-infra `id:63b0`. It lives only in a session scratchpad today. Two false-positive classes were found and FIXED in it and MUST survive any rewrite: (1) a DECOMPOSED / `route:hard-split` container annotation is not a gate claim; (2) `resolve-gates.sh` reports DANGLING targets in a separate column, so filtering on `block=1` alone reads a dangling gate as satisfied. Measured precision after both fixes was still only 4 genuine of 10 -- the naive "gate satisfied + wears the construction sign" rule is weak because the `id:3801` `route:X` annotation carries the REAL blocker. Design + acceptance live in `id:4386`; this item is the script itself. <!-- id:bfee -->
