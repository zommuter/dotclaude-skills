# id:aa0d -- a `gated-on:XXXX=<condition>` edge parses to EMPTY, so the gate is INVISIBLE and the item dispatches as ungated

Found 2026-09-10 by a `leAIrn2learn` execute child that was dispatched onto a gated item and
handed back rather than working it. **Fails in the dangerous direction**: a gate that should hold
dispatch back is silently not a gate at all.

## The mechanism, measured

`relay/scripts/lib-typed-edges.sh:20`:

    typed_edges_gated_of_line() { grep -oP '(?<=<!-- gated-on:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }

The lookahead requires ` -->` IMMEDIATELY after the token list, so any suffix breaks the whole
match rather than the suffix alone. Measured side by side:

    with =pass : []          <!-- gated-on:0d8e=pass -->
    plain      : [0d8e]      <!-- gated-on:0d8e -->

An empty result means NO GATE, so `classify-repo.sh`'s `gated-on:` executor-readiness check
(`id:65f5`) sees an ungated `[ROUTINE]` item and dispatches it.

## What it cost, live

Run `relay-20260910-114832-18641` dispatched an execute unit onto `leAIrn2learn` `id:89ef`, whose
line carries `<!-- gated-on:0d8e=pass -->` while `id:0d8e` (`ROADMAP.md:106`, an `[INPUT - author]`
item) is still open and unticked. The child correctly refused and handed back with
`workCreated:false`, naming the gap itself: *"a gated-on:XXXX edge blocks the item while target
XXXX's checkbox is open, so id:89ef was not actually executor-ready despite being the classifier's
only surfaced `[ROUTINE]` candidate."* One wasted dispatch, and the child's own judgment is the only
thing that prevented work on an item whose contract cannot be satisfied yet.

## Exposure -- concentrated, not fleet-wide

Swept every repo with a `ROADMAP.md`/`TODO.md` over the relay own-set plus `~/src`:

| repo | suffixed edges |
|---|---|
| leAIrn2learn | **11** |
| every other repo | 0 |

Conditions in use there: `=pass` (8), `=either` (2), and one more. **Seven of those sit on OPEN
items** (4 in `TODO.md`, 3 in `ROADMAP.md`), so seven gates are currently inert. The blast radius is
one repo today, which is why this is a defect rather than an emergency -- but the parser is fleet
shared, so any repo adopting the conditional spelling inherits it silently.

## The real question, and it is NOT just a regex fix

Someone deliberately wrote a CONDITION into the edge (`=pass`, `=either`). The vocabulary in
`relay/references/hard-lanes.md` and `lib-typed-edges.sh` defines `gated-on:a,b` with no condition
syntax, so either:

* the condition is **meaningful** and the vocabulary needs to grow a documented form (what does
  `=either` gate on -- either of two targets? a target passing OR being waived?); or
* it is **decorative** and those 11 edges should be rewritten to the plain form.

**Recommendation: treat the parse as a bug and the syntax as undecided.** Two separable steps:

1. **Make the parser FAIL LOUD on an unrecognised suffix** rather than silently yielding no gate.
   A `gated-on:` marker that the parser cannot fully understand must never degrade to "ungated" --
   that is the `id:d35a` silent-no-op shape, and here it authorises dispatch. Refusing loudly (or
   treating the item as gated-but-unparseable, the conservative direction) is strictly safer than
   today's behaviour regardless of what the syntax turns out to mean.
2. **Then decide the vocabulary** with whoever wrote those edges -- that is a `leAIrn2learn` owner
   question, not a dotclaude-skills one, and it should be routed there via the inbox rather than
   guessed at here.

Do NOT simply widen the regex to swallow `=[a-z]+` and discard the condition: that makes
`gated-on:X=pass` and `gated-on:X=either` behave identically, which silently picks one
interpretation of a syntax nobody has defined.

## Acceptance

* `<!-- gated-on:0d8e=pass -->` does NOT yield an empty gate set; it either resolves per a
  documented condition syntax, or is refused LOUDLY as unparseable.
* An item carrying an unparseable `gated-on:` marker is NEVER classified executor-actionable.
* The plain `<!-- gated-on:a,b -->` form is unchanged (regression guard).
* `leAIrn2learn`'s 11 edges are either migrated or validated against the new syntax, routed via the
  inbox to that repo.

## Related

`id:65f5` (the executor-readiness gate that consumes this), `id:46f6` (typed edges),
`id:d35a` (silent no-op), `relay/references/hard-lanes.md` (the lane + edge vocabulary),
`id:4e84` (the other classifier-side dispatch defect found today).
