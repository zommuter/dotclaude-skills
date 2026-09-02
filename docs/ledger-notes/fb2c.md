# id:fb2c

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— owner decision 2026-08-22 (`/relay human`, REVIEW_ME.md tier (b)). A wrapped tree-wide reset (`eval '<the reset form>'`, `bash -c '<the reset form>'`) is currently ALLOWED: it tokenises cleanly and `_split_git_commands` only starts a command at a bare `git` token, so the quoted payload is one opaque argument the guard never inspects. Correctly blocked today: the `-C`-redirected reset, `cd sub && git checkout -- .`, `git clean -fdx`, `git stash drop`. **Now load-bearing:** since the owner's 2026-08-22 ruling the five tree-wide forms are an UNCONDITIONAL deny, so an agent that hits the wall has a live incentive to reach for `bash -c` — precisely the routed-around-into-the-tree-wide-form failure the guard's own header warns about. **Scope is deliberately BOUNDED:** the command-substitution form (a `$(...)`-built subcommand) stays an ACCEPTED, documented boundary — the owner explicitly declined the fuller "close every wrapper form" option, because the guard is accident-prevention, not adversarial, and chasing substitution adds false-positive surface. Done-check: the three wrapper forms deny; the substitution form still passes (assert it, so the boundary is pinned rather than merely unimplemented); no regression in the 18 currently-allowed forms, path-scoped reverts included. **Related, observed 2026-08-22 during the very pass that filed this:** the guard fired on a Bash call whose only offence was QUOTING a destructive form inside a heredoc — the `id:9979` false-positive class, live and now twice-confirmed. <!-- id:fb2c -->
