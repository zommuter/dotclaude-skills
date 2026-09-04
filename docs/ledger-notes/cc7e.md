# id:cc7e

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From ROADMAP

ORIGINAL SPEC (now retired): resolve an item's OWN id as the LAST `<!-- id:XXXX -->` on the line, never the first. That spec CONFLICTED with the already-shipped id:6059 design — `meeting/md-merge.py` REFUSES any line carrying multiple anchored `id` markers (raises `AmbiguousOwnId`) rather than resolving own-id positionally at all, so the old test case (A) (a write aimed at the line's trailing OWN id must APPLY) could never pass against the intended behaviour. The executor correctly BLOCKED rather than gaming it (relay-ckpt-20260819-1449). **OWNER DECIDED 2026-08-20: option (2) REDEFINE, not close** — the refusal is currently pinned only by md-merge.py's own code, with no spec asserting it is deliberate rather than incidental; cc7e now owns that assertion. NEW CONTRACT: author a fresh RED spec asserting that `update-ids` RAISES `AmbiguousOwnId` (and writes nothing) for a line bearing >1 anchored `<!-- id:XXXX -->` marker, and that a single-marker line still applies normally; retire/replace `tests/test_md_merge_own_id_last.sh`, whose current assertions encode the retired spec. Re-lane [INPUT — decision] → [ROUTINE]: with the direction decided this is ordinary executor work. Re-checkable: `grep -n AmbiguousOwnId meeting/md-merge.py`; the new spec must be RED before the assertion exists and GREEN after. <!-- id:cc7e --> (archived — see ROADMAP.archive.md)
