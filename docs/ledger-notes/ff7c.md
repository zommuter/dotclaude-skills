# id:ff7c

Detail relocated out of the ledger by `tools/ledger-continuations.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

**This note is EDITABLE** (owner-ratified 2026-09-02). If a fleet rule is violated
in the prose below -- retired vocabulary, a lane delimiter, a banned token -- FIX IT
HERE and amend the line above to say what was changed. Notes are not immutable: an
unfixable violation keeps its guard red forever, and this prose gets copied back out
into new items. An undeclared edit makes the verbatim claim above a lie.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From ROADMAP

  - **Context**: `id:0d7c` ratified that the keep-set is "verified by a DIRECTIONAL round trip (a verdict may move only toward `spurious hit removed`, never toward `gate or lane lost`)". That validator was never built, and its absence is exactly how wave 1 shipped with 40 items whose decided-markers had gone dark while the gate reported SAFE TO LAND (`id:5f34`). Every trimming pass so far has been checked by running four separate tools by hand and comparing output by eye.
  - **Acceptance**: one runnable harness takes a ledger plus its notes corpus BEFORE and AFTER a pass and asserts, mechanically: (a) no `id:` marker is lost -- every id addressable before is addressable after, in the ledger or its note; (b) every item is still resolvable by `meeting/md-merge.py update-ids`, which is what makes it writable by tooling at all; (c) the lane and gate a detector COMPUTES per item are unchanged, using `classify-repo.sh` own predicates rather than a reimplementation; (d) the grammar finding set moves only toward conformance, never away; (e) `orphan-scan --cross-ledger` and `roadmap-lint` gain no finding. Any single failure is loud and non-zero.
  - **The trap it must not fall into**: a checker that derives its notion of correctness from the thing it checks cannot fail (loderite `id:dd44`, and `id:0b70` for the vacuous sibling). Do NOT borrow `ledger-shrink.py` own regexes to verify `ledger-shrink.py` output -- that is precisely how an earlier "0 lane changes" verification was never an independent check. Read lanes and gates through the DETECTORS that consume them.
  - **Tests**: hermetic fixtures for each of (a) to (e), each with a NEGATIVE case proving the assertion fires: an id dropped, a line made multi-marker so md-merge refuses it, a lane silently changed, a finding count moving the wrong way.
  - **Done-check**: replay the `id:f193` 401c relocation through the harness and get a clean directional verdict, then replay a deliberately corrupted variant and get a loud failure.
