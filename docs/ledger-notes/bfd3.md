# id:bfd3

Authored directly (not relocated by `tools/ledger-shrink.py`).

## From TODO

Found by the `id:1447` untraced analysis, 2026-09-04. Noise reduction, orthogonal to the
corpus-side narrowing `1447` built.

### The measurement

**28 of 50 refusal sites (56%), including 3 of the 6 `ledger`-traced ones, come from
constructs that carry NO ledger-distinguishing content**: `.endswith('\n')`, `.rstrip('\n')`,
`sed 's/^/    /'`, `line.startswith("{")`. The pattern literal is a newline, a run of spaces,
a lone brace, or a bare metacharacter class.

They are matched because `CONSTRUCT_RE` treats every `.endswith(` / `.startswith(` as a
content-matching construct, and every such call's argument as a search pattern.

### Why this is a DIFFERENT lever from `id:1447`

`1447` narrowed on the CORPUS axis: whose text is this pattern applied to. This is the
PATTERN axis: could this literal ever discriminate ledger content at all. The two are
independent, and this one would halve the noise in BOTH tiers without touching the untraced
question `1447` settled.

It is also the lever that would most improve the `ledger` tier's credibility. Today 3 of its 6
members are `\n` artifacts, which is exactly why the `1447` amendment had to say in the output
that the tier boundary is PROVENANCE and not PRIORITY.

### The trap this must not fall into

**A pattern-side filter is a HEURISTIC boundary, so the `id:cb3e` argument must be run against
it before adoption.** "This literal cannot encode ledger semantics" is a judgement, and the
moment it is wrong it produces a SILENT clear -- the same failure class `1447` exists to
close, arriving through the other axis. The filter must therefore either be provably
non-discriminating (a pattern that matches every non-empty line cannot single out a body) or
it must refuse rather than clear when unsure.

Related, same file, same review: `extract_patterns`'s `.match(` / `.endswith(` branch grabs
`.rstrip('\n')`'s argument AS a search pattern, which is what makes `archive-done.sh:164`,
`archive-closed.sh:381` and `roadmap-archive.sh:405` show up as `ledger`-traced consumers with
pattern `\n`. Their corpus verdict is CORRECT; the pattern is the artifact.

- **Acceptance**: a construct whose pattern literal provably cannot discriminate ledger
  content is not reported as a consumer; the exclusion is argued against `id:cb3e` in the code
  with a written reason; and an unsure case REFUSES rather than clears.

- **Done-check**: the `\n` and whitespace-only sites disappear from both tiers on the restored
  `id:6b35` fixture, the `ledger` tier's remaining members are all genuine, and every
  `id:1447` and `id:9ce0` floor property still holds including both halves of the self-test.
