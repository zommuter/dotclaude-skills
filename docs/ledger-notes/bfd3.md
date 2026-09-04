# id:bfd3

Authored directly, not relocated by `tools/ledger-shrink.py`. Conventions:
`docs/ledger-notes/README.md`.

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

## DROPPED AS PROPOSED 2026-09-04 -- owner-ratified after the `id:cb3e` argument was run

**The proposal's central premise is FACTUALLY WRONG about what the tool holds, and the rule as
written produces a live silent clear.** Successors filed on the EXTRACTION axis: `id:ddcb` and
`id:962b`.

### The premise that fails

`bfd3` claims the flagship `\n` class "carries no ledger-distinguishing content". It does.
`extract_patterns` reads SOURCE TEXT and does not decode the reader language's string escapes,
so `existing.endswith('\n')` yields the **two-character literal backslash-n**, compiled
literally. Verified directly:

```
extracted literal: '\\n'   len= 2
```

Measured over the live ledgers that is ~0.15% of lines -- **more selective than 40 of the 49
sites**. The pattern this item calls junk is one of the most discriminating in the set.

### The silent clear, demonstrated rather than argued

A reader was PLANTED whose entire pattern is `\n`:

```sh
roadmap="$ROOT/ROADMAP.md"
if ! grep -qF '\n' "$roadmap"; then echo "FAIL: the fence example lost its escape sequence" >&2; exit 1; fi
```

The tool scores it `[ledger]`, names it a cited-body consumer of `id:6b35`, and the lint was
verified to PASS before the move and FAIL after. So the filter as proposed clears a real
breakage, silently -- the `id:1447` harm class arriving by the other axis, exactly as this
note's own warning predicted.

### Three further findings, any one of which would be sufficient

1. **Only 9 of 28 sites meet this item's OWN bar.** Nine patterns are universal over the block
   grammar (`^ `, `^  `, `^[ \t]` at 100%); the other 19 merely look harmless.
2. **ZERO verdict change** in either fixture. The payoff is report noise -- 28 fewer printed
   lines in the single-block shape, 12 in the batch -- which does not justify a heuristic
   clearing boundary. On the single-block fixture it empties the `ledger` tier 6 -> 0, the tier
   it set out to make credible.
3. **It would silently re-suppress what `id:0176` exists to surface.** In the batch shape the
   whitespace family is already cancelled by `elsewhere_lines`; once `0176` evaluates that
   escape against the POST-batch ledger those sites correctly reappear, because after migration
   `ROADMAP.md` holds no indented line at all. Two stacked silent-clearing mechanisms, only one
   ever argued.

### The conceptual error worth keeping

**Universality does not imply safety, and this item conflated them.** `cited_by` already
requires a pattern to match inside the block AND nowhere in the surviving ledger, so a
universally-matching pattern reaches the site list ONLY when the block is the last carrier of a
match. The escape has therefore already proved the match is unique; filtering on universality
would override the very evidence that made it a hit. "Cannot single out a body" and "cannot be
broken by the move" are different predicates.

### On the `cb3e` questions, for the record

Keyed on a VALUE re-derived every run, so the literal grandfathering trap does not bite. But it is
not a ratchet either. It is a frozen static classifier that inherits the MEMBERSHIP half of the
hazard: a construct minted tomorrow whose literal falls in the class is cleared without ever
having been seen, with no expiry and no counter.

- **Done-check**: the `\n` and whitespace-only sites disappear from both tiers on the restored
  `id:6b35` fixture, the `ledger` tier's remaining members are all genuine, and every
  `id:1447` and `id:9ce0` floor property still holds including both halves of the self-test.
