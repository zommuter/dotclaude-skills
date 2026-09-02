# id:ebf9

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(filed 2026-08-18, `/relay human .`) — with the stack now ratified BOOT-PERSISTENT on zomni, the importer is expected to reach it unattended, and the failure mode that buys is silent: a down endpoint makes a stale board read as "the fleet has no new work" rather than "the import is down". Author `tracker/tracker-preflight.sh`: read the secrets file by INJECTION (`$TRACKER_SECRETS_ENV`, default under `~/.config/relay/`, never committed, never echoed), probe each configured tracker base URL, and exit non-zero **naming which target is unreachable**. `tracker/fleet-import.sh` and the `id:f116` timer call it first. It NEVER starts, stops or reconfigures a container — probing only. Hermetic test against a stub endpoint (up → exit 0; either down → non-zero naming that target). Keep host specifics OUT of this public repo, per the item's own standing rule. <!-- children-of:a532 --> <!-- id:ebf9 -->
