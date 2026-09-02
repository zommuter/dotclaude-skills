# id:ebbe

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

**EDITED ON RELOCATION (2026-09-02, `id:40c0`) -- the verbatim claim above is amended
for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any
prose already in that section arrived by an earlier pass and is untouched here.** Fleet-rule violations found in the relocated
prose were FIXED here rather than parked: 3 punctuation em dashes became `--`. Nothing else changed: no word, figure, marker or line break was
altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation
included.

DELIBERATELY LEFT, declared rather than silently kept. 1 em dash inside BACKTICK code spans is NOT converted. A backticked span here
quotes something whose spelling is the point -- a lane tag, a heading that still
carries that character, a `path:line-range`, or live tool output -- so rewriting it
would make the quotation false.
The lane tag `[HARD — pool]` is NOT converted, neither delimiter nor name. Every lane tag in
this section is REFERENTIAL -- prose MENTIONING the vocabulary, inside backticks --
not the DECLARATIVE lane of any item, which stays on the ledger line. Rewriting a
referential tag corrupts a record of what a past run classified or of which
spelling a migration is about.

## From TODO

— **[RE-FRAMED 2026-07-24, owner-directed: reborn as Workflow-pool `pipeline()` fan-out (id:1f4f) since the off-Workflow drain driver was retired (id:93fe); the disjoint-greenlight children id:5367/2062 are substrate-agnostic and stand; off-Workflow live-residue id:7fae is moot.]** DECIDED 2026-07-19 (meeting 2026-07-19-2035-relay-drain-parallel-contract, D4/D5/D6). Fan out N executors within a drain round via **one-writer-to-main**: executors produce code+reports in their OWN worktrees only; the single driver holds the lease, merges each --no-ff serially, ticks checkboxes itself. **Mechanical fail-closed disjoint-path greenlight**: concurrent only if declared file-sets (RED spec # roadmap:XXXX / item Context) are disjoint+non-empty; re-enforce at merge (2nd worktree touched-paths vs 1st merged diff; intersection→handback, never auto-resolve); undeclarable/unknown-overlap→serial. Gated-on id:0534 (mechanical-daemon lease hole — LANDED this session, 154aa15). Route to handoff to spec (2d20). Relates id:5a39 (sibling one-writer pattern for /meeting), id:93fe, id:dc5b. **DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669):** worktree-verifiable children id:5367 (disjoint-path greenlight, RED `tests/test_disjoint_greenlight.sh`) + id:2062 (serial one-writer integrator, RED `tests/test_drain_serial_integrator.sh`) in ROADMAP.md; live-only residue id:7fae (N>1 concurrent fan-out — needs real parallel executor agents) surfaced-as-blocked, never auto-executed. Parent = tracking line; stays open until the children close. <!-- gated-on:0534 --> **GATED-ON id:ae08 as of 2026-07-26** (meeting 2026-07-26-1922): the greenlight + one-writer integrator this item needs are built but UNREFERENCED by the engine (`grep -c` → 0), so id:ae08 must wire them first. **Re-evaluation note:** if id:cc90 (bounded serial execute→execute rechain, K≤3) delivers the single-repo drain win, concurrent fan-out may never be worth building — its remaining marginal value is wall-clock only, against a declaration discipline + four re-keyed sites + a lease change. Before deciding that retirement, check the depth-vs-width distinction (`--fabled` F7): cc90 reduces LATENCY BETWEEN DEPENDENT units, ebbe buys THROUGHPUT ACROSS INDEPENDENT ones — one substitutes for the other only on a mostly-dependent queue, which nobody has measured. <!-- gated-on:ae08 --> <!-- id:ebbe -->

## From ROADMAP

🚧 @container DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669) — TRACKING LINE ONLY, work the children: verifiable id:5367 (disjoint-path greenlight) + id:2062 (serial one-writer integrator) below. Tick this parent only when the children are closed. Full context TODO.md. <!-- id:ebbe -->

  - **DEAD GATE DROPPED 2026-07-31** -- this line carried `<!-- gated-on:0534 -->`, but `id:0534` is `[x]` archived at `TODO.archive.md:432` (a `[HARD — pool]` mechanical-daemon lease item) and was **never** a ROADMAP item, so the gate was PERMANENT and could never open. Found by `roadmap-lint` rule 3(d) DEAD-GATE (`id:49e0`) within minutes of that rule existing -- the fourth instance of the trap in one day, after `a955`→`87f5`, `8123`→`1a34` and `f6d5`→`8ba1`. **Dropped rather than re-targeted** because this line is an `@container` DECOMPOSED tracking entry with `children:` -- it is not dispatchable in the first place, so a gate on it is meaningless twice over. Its children carry their own gates.

