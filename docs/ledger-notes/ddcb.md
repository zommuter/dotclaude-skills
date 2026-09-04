# id:ddcb

Authored directly, not relocated by `tools/ledger-shrink.py`. Conventions:
`docs/ledger-notes/README.md`.

## From TODO

Successor to `id:bfd3`, which was DROPPED as proposed after the `id:cb3e` argument was run.
This is one of the two mechanical replacements: an EXTRACTION-axis fix, not a heuristic
pattern filter.

### The defect

`extract_patterns` binds a quoted literal to the WRONG call. `CONSTRUCT_RE` matches a
content-matching construct such as `.match(`, then `QUOTED_RE` takes the first quoted literal
in the remainder -- which may belong to a DIFFERENT, nested call.

Worked example, `todo-update/archive-done.sh:164`:

```python
HEADING_RE.match(line.rstrip('\n'))
```

The construct is `.match(`, but the literal grabbed is `rstrip`'s `'\n'`, not `match`'s
pattern. The site is then reported as a consumer whose search pattern is `\n`, which it is not.

Same shape at `meeting/md-merge.py:258`, `:319` and `meeting/append.sh:286`.

### Why this is the right axis

`bfd3` proposed filtering these out by judging the literal's SHAPE. That was refuted: the
extracted `\n` is a two-character literal that matches ~0.15% of ledger lines, so it is one of
the most SELECTIVE patterns in the set, and a rule calling it junk produced a demonstrated
silent clear.

The real defect is that the literal was never `match`'s argument at all. Fixing the binding is
mechanical, has a right answer, and fails LOUD: a parser that cannot associate a literal with
its call leaves the site IN, so it over-reports rather than clearing.

### What to build

Bind the literal to the call whose parentheses it sits inside. Track nesting rather than taking
the first quoted string in the remainder.

**When association is ambiguous, keep the site.** Over-reporting is the safe direction here and
the whole reason this is preferable to `bfd3` -- an extraction fix must never become a clearing
mechanism by the back door.

- **Acceptance**: a literal that is an argument to a NESTED call is not attributed to the outer
  content-matching construct; `archive-done.sh:164`, `md-merge.py:258`/`:319` and
  `append.sh:286` stop reporting `\n` as their search pattern; an ambiguous association keeps
  the site rather than dropping it; and every `id:9ce0` and `id:1447` floor property still
  holds, both halves of the self-test included.

- **Done-check**: the four named sites disappear from the refusal on the restored `id:6b35`
  fixture, the ledger tier loses its `\n` artifacts, and no site that was ledger-traced for a
  correctly-associated pattern is lost.
