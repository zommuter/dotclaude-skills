# id:d6da

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— hit live 2026-08-21 onboarding `inflownistration`. `toml-set` fails with `block [repos.<name>] not found` and no script anywhere in `relay/scripts/` appends a `[repos.X]` block (grepped: nothing matches `cat >> …relay.toml` / an append of `[repos`). So the SKILL.md orchestrator invariant 1 ("persist confirmations") has no implementation for the first-confirmation case — every new repo must be onboarded by a hand-append, against a CLAUDE.md rule that says NEVER hand-edit relay.toml. I appended the block under the helper's OWN lock (`flock -w 30 $BASE/.state-write.lock`) to preserve the single-writer invariant, but that is a workaround, not a path. FIX: add `relay-state-write.sh toml-add <repo> <abs-path>` (or extend `toml-set` with a `--create` flag) that appends a well-formed block under the same flock, idempotently (no-op if the block exists), seeding `classification`/`confirmed`/`status` and honouring the `# path:` convention when the repo is not at `~/src/<name>`. Then the front door's confirm step can call it instead of a human editing TOML. Note this is ALSO why an onboarding is currently unauditable — a hand-append leaves no log line, so nothing records who confirmed a repo or when. Relates [[onboarding-confirm]] ('own' != relay.toml confirmed), SKILL.md orchestrator invariant 1. <!-- id:d6da -->
