# id:abb6

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(filed 2026-08-18, `/relay human .`, owner-decided "Lift, and split ca9e author/run") — implement `cp -a --reflink=always` of the repo under `/home`, taken under the `git-lock-push.sh` flock, gated on a clean **TRACKED** tree (keep untracked gitignored build dirs — that warmth is the point), post-verified with `git fsck --connectivity-only`, followed by `git -C <copy> remote set-url --push origin NO_PUSH` (ratified H2 — the copy inherits `.git/config` verbatim including the credential, so "never touches origin" must be config, not prose). Exclude the untracked ride-alongs (`RELAY_STATUS.md`, `persona-events/`, `settings.local.json`, live lock files). Add the integrator's fetch-from-copy path and the rule-5b / `worktree-retire.sh` copy-analogues. **Ships DEFAULT-OFF behind an explicit flag; the worktree path stays the default** — this half must be inert until `id:ca9e`'s supervised round flips it. **Do NOT bump `contract vN`** — the marker is a compatibility handshake and publishing it for a transport no live round has exercised is precisely the failure it exists to prevent; the bump belongs to `id:ca9e`. Fallback `git clone --local --no-hardlinks` stays DOCUMENTED, not built (ratified D2). Acceptance: hermetic tests cover clean-tree refusal, push-URL neutering, the fsck gate and ride-along exclusion; full `make test` green with the flag OFF **and** ON. Design source: `docs/meeting-notes/2026-07-21-1518-who-may-write-realremotes-uid-scoping.md` D2/D3 + H2. <!-- children-of:ca9e --> <!-- id:abb6 -->
