# id:ac8a

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— `plan` keys a `declare -A seen` on each declared path and flags overlap only on an exact repeat (`disjoint-greenlight.sh:74`); `merge-check` intersects touched-vs-merged by exact line (`:113/:119`), and `drain-integrate.sh` (id:2062) re-enforces via the same `merge-check`, inheriting the blind spot. Two concurrent units with declared sets `{"relay/scripts/"}` and `{"relay/scripts/relay-loop.js"}` (or `{"a/b"}` vs `{"a/b/c"}`) are greenlit "concurrent" despite containment. Both scripts are built-but-UNWIRED (id:ae08 is the wiring child), so this is a latent gap to close before they go live, not an active incident. Severity is bounded by an unverified premise (hence tracked, not urgent): the hole only bites if a declared/touched file-set can contain a directory path — `git diff --name-only` emits leaf files, but the seam `file:` declarations `plan` consumes are not asserted leaf-only anywhere. **Resolve alongside id:ae08**: either (a) document + enforce a leaf-file-only contract on declared sets (reject a directory/extensionless declared path, fail-closed on ambiguity) — smaller and more fail-closed — or (b) make disjointness containment-aware (prefix-normalize sets, treat `a/b` vs `a/b/c` as overlapping). Relates id:5367, id:2062, id:ae08, id:1f4f. <!-- gated-on:ae08 --> <!-- id:ac8a -->
