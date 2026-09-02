# id:fab9

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

🚧 GATED — filed 2026-08-18 (`/relay human .`) as the precondition `id:a532`'s own text makes for closing it ("if this ever closes, that finding needs its own id first"). **Not actionable yet, and deliberately so: there is ZERO coupling today** — verified 2026-08-18, no relay script or the loop references a tracker, and `tracker/fleet-import.sh`'s header states the ratified D4 boundary ("produces JSON on the local filesystem and stops"). So no dispatch path can currently be blocked by a dead board, and building a guard now would guard a dependency that does not exist (observe-before-preventing). It becomes real the moment `id:f116` lands its recurring import timer. **The fix is already shaped by precedent, not novel:** `tools/relay-watchdog.sh` has exactly two liveness domains — the dispatch loop (`heartbeat.sh dead-runs --prefix 'relay-*'`) and the mechanical discovery producer (fixed runId, its own TTL) — and domain 2 exists for precisely this failure ("it can die while the dispatch loop is perfectly healthy, which would otherwise read as 'no work' rather than 'discovery is down'"). A third domain is a copy of domain 2 with a distinct fixed runId, a TTL derived from the import cadence plus one missed run, its own de-dup state and its own evidence tag. Contract: when `id:f116` builds the timer, that timer beats a fixed runId and the watchdog gains the third domain **in the same change** — not as a follow-up. <!-- gated-on:f116 --> <!-- children-of:a532 --> <!-- id:fab9 -->
