# id:fa7e

Authored directly, not relocated by `tools/ledger-shrink.py`. Conventions:
`docs/ledger-notes/README.md`.

## From TODO

### The gap

Every correlation mechanism in this ecosystem matches on an EXACT TOKEN. `orphan-scan.sh`
correlates meeting items against the ledger by exact `id:` match; `scan-routed.sh` resolves
inbox twins by exact `routed:` match; `lib-typed-edges.sh` walks `gated-on:`/`children:`
edges. All of it is precise and all of it is blind to the case that actually costs time:
**the same question re-opened in different words, carrying no shared token.**

That failure has a signature -- "we have discussed and decided this five times already" --
and it is not hypothetical here. Recent instances, all of them costing a real turn:

- `id:0d7c`'s format was ratified, then a derived doc's restatement drifted from it.
- The retire-vs-resolve semantics were reasoned out wrongly, corrected, and the superseded
  recommendation then sat live in the note below its own correction.
- The venue-keyed lane rename was refused on a historical-record argument, overruled, then
  found to have been out of scope after all.
- The em-dash ban was written into CLAUDE.md and violated by its author within hours, twice.

None of these would be caught by token matching, because none of them reuses a token.

### The proposal

Embed the decision corpus and query it for semantic near-duplicates when a new item is
filed or a meeting opens a topic:

- `TODO.md`, `ROADMAP.md`, `REVIEW_ME.md` (and their archives -- a decision does not stop
  being a decision when it is archived, and the archive is where the "we already did this"
  evidence usually lives)
- `docs/meeting-notes/**` -- the actual decision record
- `docs/ledger-notes/<id>.md` -- newly valuable, see below
- possibly session transcripts -- see the privacy constraint below

### Reuse zkm's stack; do not build a second one

`zkm` already runs exactly this: **bge-m3** dense embeddings plus BM25 in a hybrid index,
served through llama-swap on the Arc iGPU (no CUDA), with `gemma4-e4b` for bilingual EN/DE
query expansion, chunk aggregation for long documents, ~56k docs at schema v4. See
`~/src/zkm/docs/hybrid-search.md` and `docs/field-test-bge-m3.md` there.

So the question is NOT which embedding model. It is whether this is a zkm plugin, a zkm
store over a different corpus, or a thin consumer of the same index -- and the answer
should come from whoever owns zkm, not from re-deriving a stack that already works. The
no-not-invented-here rule applies directly.

### Why now is a better moment than before

The `id:0d7c` / `id:40c0` trimming just produced a clean per-id corpus: one
`docs/ledger-notes/<id>.md` per item, holding the item's full prose, addressable by its id.
Before that, an item's body was an arbitrary run of continuation lines with no stable
boundary. Chunking a corpus of per-id files is a much better-posed problem than chunking a
1,700-line ledger, and the ids give every chunk a natural, already-meaningful key.

### The failure direction that decides the design

A false "you already decided this" is WORSE than a miss. A miss costs a re-litigated
decision; a false positive suppresses genuine new work, and it does so with the authority
of a machine. So:

- Optimise for PRECISION, not recall.
- The output SURFACES candidates with their evidence for a human or an apex model to judge.
  It must never auto-suppress, auto-close, or auto-merge an item. That is the mechanize-first
  rule's "reserve the LLM for the loud failures" shape, and the `id:4347` no-silent-swallow
  ban applies.
- It is a retrieval aid, not an authority. A decision is settled by the owner, and this
  changes nothing about that.

### Privacy constraint, load-bearing

This repo is PUBLIC. Session transcripts contain personal identity strings and live under
`~/.claude/projects/`. If transcripts are indexed at all, the index and anything derived
from it must live OUTSIDE any git-tracked public tree, in the same class as
`~/.config/dotclaude-skills/privacy-patterns.txt` and the `tracker/` homonym worksheets
whose output is deliberately written outside every repo. Do not commit an index, an
embedding cache, or a similarity report into this repo.

### Survey before designing

The owner flagged **Hermes** and other agent-memory systems as prior art worth reading
before committing to a shape. Treat that as a required survey step, not an optional one:
this is a well-trodden problem, and the interesting question is which of the existing
designs fits a corpus that is small, highly structured, id-keyed, and already has an exact-
match layer that works. Cross-check against the existing auto-memory system here
(`tools/memory-index.py`, `id:2e6d`), which is the closest thing already in the fleet.

### Open questions for the design session

1. Corpus: ledgers only, plus meeting notes, plus per-id notes, plus transcripts? Each
   addition raises recall and lowers precision.
2. Trigger: on filing a new item, on `/meeting` open, as a periodic sweep, or all three?
3. Where does it run -- a zkm plugin, a standalone tool, or a relay hop?
4. Fleet or per-repo? A decision re-litigated across repos (the loderite/dotclaude-skills
   pattern, which recurred repeatedly today) is exactly the case a per-repo index misses.
