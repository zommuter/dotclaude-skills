# id:ef8a

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

[Fable] — currently the `## Relay contract` pointer is written into each managed repo's own `CLAUDE.md` by handoff C1. Alternative: a single entry in `~/.claude/CLAUDE.md` that fires for all sessions, with repo-local opt-in/opt-out markers. Required failsafes before doing this: (a) non-personal repos (upstream forks, checked-out third-party code) must not silently inherit relay rules; (b) repos not yet handed over (no `fable-ckpt-*` tag, no ROADMAP.md) must not confuse executors with a dangling pointer; (c) the global entry must not add noise to sessions where no relay work is happening. Candidate design: global CLAUDE.md carries a conditional ("if this repo has a `RELAY_LOG.md` or `fable-ckpt-*` tag, load `/relay executor`") rather than an unconditional pointer — keeps the passive guarantee without per-repo embedding. Requires Fable judgment: global CLAUDE.md changes affect every session's context budget and trust surface. **Gate met 2026-06-12** (≥3 relay repos active: 7 handed-off/active in relay.toml after this wave). <!-- id:ef8a -->
