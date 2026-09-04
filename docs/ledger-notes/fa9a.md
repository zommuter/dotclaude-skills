# id:fa9a

Authored directly, not relocated by `tools/ledger-shrink.py`. Conventions:
`docs/ledger-notes/README.md`.

## From TODO

Owner asked 2026-09-03: *"where should we declare the trimmed TODO/ROADMAP format properly?
global CLAUDE.md?"* This is the answer and the work it implies.

### NOT global CLAUDE.md, and the reason is on the record

`relay/references/hard-lanes.md` is the lane-vocabulary SSOT, and the standing rule about it
is *"ALWAYS enumerate lanes from `relay/references/hard-lanes.md`, never a restatement."*
That rule exists because a CLAUDE.md restatement of the lane list **was wrong** -- it named
three `[INPUT]` lanes where there are four, so any exclusion list built from it silently
missed `[INPUT - author]`.

A ledger grammar restated in a file loaded into every session in every repo is the
highest-exposure possible place to put a restatement. Three drifted restatements were found
in this one session:

- `d05d`'s note asserted an archive stub and its archived copy were "byte-identical" -- true
  of `id:5f34`, FALSE of `id:b8ae` (189 vs 281 bytes).
- Both archivers, plus `d05d` and `cd9c`, said `orphan-scan --cross-ledger` "reads ONLY the
  live file" -- stale since `routed:42c9` widened it to the archive union.
- `2d17`'s own acceptance cited `id:0d7c`'s ratchet as its model; that ratchet provably
  cannot catch the incident `2d17` was filed for.

Global CLAUDE.md also multiplies its size by every prompt in every repo -- the standing
per-prompt ctx-budget heuristic argues against putting an enumeration there on cost alone.

### Where it goes

| layer | content |
|---|---|
| `relay/references/ledger-grammar.md` | **the SSOT** -- shapes, budgets, note format, anchor/`relates:` rules. Carries a `<!-- ledger-grammar vN -->` marker. |
| global `~/.claude/CLAUDE.md` | ONE line pointing there. No enumeration. |
| this repo's `CLAUDE.md` | one line in Conventions, same pointer |
| `relay/references/conventions.md` | reuse its existing "thin versioned pointer" pattern, already used for `executor-contract.md` |

**Why it needs a version marker:** `id:03a3` makes this a contract surface across 46 repos,
and this repo's own Versioning table says markers belong exactly where "a stale copy causes
*silent* breakage". A repo migrating against grammar v1 while the fleet moved to v2 fails
silently -- no error, just a ledger nobody's tooling agrees about.

### THE TRAP, and it is the substance of this item

**`relay/scripts/todo-conformance.sh` already IS the grammar** -- it implements it. A prose
doc beside it is a SECOND description of the same thing, which is precisely the `id:4983`
shape ("hand-mirrored in three places; make ONE source serve both the actor and the
checker"). That defect bit twice on 2026-09-03 alone: `STUB_SUFFIX` spelled independently in
`roadmap-archive.sh:114` and `archive-closed.sh:107`, and the lane grammar before `4983`
closed it.

So the doc must NOT be a parallel prose copy. Either:

- **generate** the shape list from the checker's own class names, or
- have the **checker read** the doc, or
- at minimum, ship a TEST asserting the doc's enumerated shapes and the checker's classes
  agree, so a divergence is loud.

Without one of those, in three weeks the doc says five shapes and the checker enforces six,
and the 46-repo migration will have been run against the doc.

### Sequencing

Downstream of `id:800f`'s outcome. The owner AMENDED that ruling on 2026-09-03 -- section
preamble is to be REMOVED rather than legalised -- so "section preamble" is NOT a shape and
must not be written into the SSOT as one. Wait for that removal to land before fixing the
shape list, or the first version of the SSOT is wrong on its first line.

Also downstream of `id:14e5` in spirit: if the `id:` marker becomes positional and typed
edges stop being HTML comments, every shape in this doc changes. Do not mint `v1` and then
immediately need `v2`; either wait for `14e5`'s decision or write the doc so the marker
SPELLING is cited from one place rather than inlined into every shape.

- **Acceptance**: `relay/references/ledger-grammar.md` exists with a `vN` marker; global and
  project CLAUDE.md carry a POINTER and no enumeration; and the doc/checker agreement is
  mechanically enforced rather than asserted.

- **Done-check**: the agreement test fails when a shape is added to the checker and not the
  doc (verify by adding one), and `grep -c` finds no shape enumeration in either CLAUDE.md.
