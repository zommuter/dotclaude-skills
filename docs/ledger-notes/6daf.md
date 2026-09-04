# id:6daf

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

Verified 2026-08-10 (review of id:8066): `classify-repo.sh:289` sets `base["unpromoted"] = {"promote": …, "surface": …}` in `assembled.json`, but the `--emit unit` builder (`:371` onward) never copies it, so the emitted unit's 20 keys contain no `unpromoted` (`--emit unit` on this repo → `unpromoted: ABSENT`). Consequence, hit live by `control-board.sh`: an "items awaiting promotion" board column would have to re-run `unpromoted-scan.sh` itself, i.e. become a SECOND producer of a number the classifier already has — which is why id:8066 correctly OMITTED the column rather than re-deriving it. Same passthrough shape as `actionable_routine_open`/`actionable_routine_ids` (id:b09e) and, like those, must be folded AFTER `classify-verdict.sh` so the id:82c4 Lean shadow-parity surface stays untouched. Contract: `--emit unit` carries `unpromoted`; a test asserts the unit's counts equal the `--emit` default mode's for the same fixture repo; `control-board.sh` gains the column without invoking `unpromoted-scan.sh`. <!-- children-of:8066 --> <!-- id:6daf -->
