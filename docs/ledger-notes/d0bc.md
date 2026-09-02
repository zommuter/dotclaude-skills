# id:d0bc

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— sentinel check at the top of `relay/scripts/quota-stop.sh`: `[[ -f ~/.config/relay/STOP ]] && { echo "quota-stop: manual STOP sentinel" >&2; exit 1; }`. Because the gate re-invokes the script before *every* unit dispatch, `touch ~/.config/relay/STOP` makes a running pool stop filling at the next gate check and drain gracefully (in-flight children finish, integration debt drains, undispatched repos listed in RELAY_STATUS) — same path the automatic 90% threshold uses. Remove the sentinel after the drain (or have relay-loop's front door warn if it pre-exists, so a stale STOP can't silently no-op a future run). Document in SKILL.md config-knobs table + `docs/relay.md`. Add a scratch test alongside the existing quota-stop coverage. Surfaced 2026-06-12 during live pool run (five_hour hit the 90% gate mid-run; user asked for a pre-threshold manual stop). <!-- id:d0bc -->
