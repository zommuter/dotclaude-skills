# id:9ccd

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Filed 2026-08-26 alongside `id:c80e`. After the 11 `git -C *` rules were removed, exactly five entries of the same syntactic class remain: `diary-append.sh -m * -p * -f .diary-entry.*` (×2 path forms), `meeting/append.sh -t * -e *`, `meeting/append.sh -t * -f *`, and `jq -r * /tmp/meeting-rpg/*/broker.json`. **The harness did NOT flag these, and the initial read is that they are materially safer:** the command position holds a FIXED script or binary rather than `git`, so an injected flag is bounded by what that program accepts, and none of them has an arbitrary-execution primitive like git's `-c`. `jq` cannot shell out at all in its default build. **But that is a shape argument, and the owner declined to settle it on one** — which is right, because it is exactly the reasoning that made the `git -C *` rules look acceptable for months. **The actual question to answer, per script:** can a flag injected through one of those wildcards make `append.sh` or `diary-append.sh` write outside its intended target, execute anything, or bypass its own flock? Both are ours, both parse with `getopts`, and both take a `-f FILE` — so the concrete probe is whether an injected second `-f`, a `--`-terminated payload, or a path traversal in the `-e`/`-m` value changes where bytes land. **Weigh removal against real cost:** these sit on the MANDATORY post-prompt diary/append path, so tightening them adds friction to every session — the reason to leave them if the probe comes back clean. **Deliverable:** a per-entry verdict with the command that proves it, and either a tightened entry set or a recorded "safe, and here is why". Relates id:c80e, id:9320. <!-- id:9ccd -->
