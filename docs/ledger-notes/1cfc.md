# id:1cfc

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— split out of `id:17ac`, whose own stated hypothesis ("the lint skips sourced `lib-` files") was REFUTED there: `tests/lint-pipefail-sigpipe.py` walks `relay/scripts/lib-private-remote.sh` fine and exits 0, and `iter_shell_files` prunes only nested git checkouts (id:b818). The lint tokenizes on `|` and classifies stage 2, so a consumer fed by a PROCESS SUBSTITUTION redirect has no pipeline for it to see — yet an early `return`/`break` out of that loop closes the read end exactly as `grep -q` does, and the producer's next write takes SIGPIPE. `id:17ac` is the proof this is a LIVE shape, not a hypothetical: it shipped in a load-bearing predicate, survived the `id:81d5` sweep, and printed into every push transcript for two days. **Scope:** find every `done < <(…)` / `< <(…)` -fed loop containing `return`/`break`/`exit` and decide per site (drain via `mapfile`, or accept). **Guard against the known lint weaknesses first** — `id:2e8a` already documents two false negatives, two unhatched false positives and a `--heredoc` docstring/code drift in this same file; a new detector bolted onto a parser with those holes inherits them. Sequence `id:2e8a` before or with this. Relates `id:17ac`, `id:81d5`, `id:2e8a`, `id:7518`, `id:4347` (a detector that misses its own class is the no-silent-swallow anti-pattern). <!-- relates:17ac --> <!-- id:1cfc -->
