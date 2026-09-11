# id:ee5e

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

Step 1, measurement: run the head-length and shape-prose ratchets WITH baselines present and record the true finding count. The 216 currently reported is inflated by the failure itself -- the installed path (`~/.claude/skills/relay/...`), which is the path every repo actually uses via `relay-doctor` and the review flow, cannot find its baseline files because the install manifest never copies them, so it fails OPEN and reports regrowth for everything. Judging the fix against 216 would be judging it against an artefact of the bug. Step 2, once the real number exists: fix ALL THREE dimensions together -- (a) the install manifest, (b) the baseline key's missing per-repo dimension, which lets identical-looking ids collide across repos, and (c) the locale-dependent length metric (char vs byte count under `LC_ALL=C`). The reviewer's explicit warning stands and is the reason this is not a one-line change: **a fix for any two still ships the failure by the third route.** Blast radius is 46 repos, which is why the number comes first. <!-- relates:4839 --> <!-- id:ee5e -->
