# id:d9ff -- `_own_marker_re` accepts a BACKTICK-QUOTED example marker as an owning marker; `id:1d83` made the hole ~7x bigger

PRE-EXISTING (the hole is inherited, not introduced), AMPLIFIED by `id:1d83`. Measured by the
`id:1d83` adversarial review, 2026-09-10.

## The hole

`relay/scripts/lib-anchored-id.sh`'s `_own_marker_re` form 1 matches an `<!-- id:XXXX -->` /
`<!-- routed:XXXX -->` comment **anywhere on a line**. It is not line-position-anchored. The
header's ownership claim holds for BARE tokens (a prose `routed:XXXX`, a longer hex string, a
`YYYY-MM-DD-HHMM` note timestamp are all correctly REJECTED) but NOT for a comment-wrapped one.
So a line that merely QUOTES a marker as an example, typically in backticks while explaining
another repo's ledger, reads as OWNING that token.

## The amplification, measured

Tokens whose ONLY match in this repo's ledgers is a backtick-quoted marker:

| predicate file set | false-accept population |
|---|---|
| `TODO.md` + `ROADMAP.md` (before `id:1d83`) | **2** (`3db4`, `e2c3`) |
| + `TODO.archive.md` + `ROADMAP.archive.md` (after) | **15** |

Thirteen new, every one quoted-only. Named, each quoting another repo's ledger line inside an
archived body: `77a6`, `2456` (both quote `~/src/chidiai/ROADMAP.md:349`), `1a30` (`zkm-pdf`),
`f4a7` (`isochrone`), `362f`, `306d`, `33b2`, `436c`, `6176`, `93ac`, `94b8`, plus fixture tokens.
Each verified individually: two-file REFUSE, four-file ACCEPT.

**Why the archives are the worst place to widen into, stated as the mechanism rather than the
number:** they are where retrospective EXPLANATORY prose accumulates, and explanatory prose is
exactly what quotes markers. 2.0 MB of archive against 0.26 MB live, and 68 multi-marker lines in
the archives against 59 live.

## Severity: MEDIUM, and why not HIGH

It guards an unrecoverable delete against a local-only store, and it is the same class
(`id:c97c`) that once DELETED three inbox items that had never been filed. But no currently-open
inbox token is among the 15, so nothing is mis-deletable today, and the hole predates the
widening.

## The fix, already measured

Reject a marker preceded by an ODD number of backticks on its line: kills **13 of 13** of the new
false accepts in measurement. It belongs in `_own_marker_re` itself, so every caller inherits it
-- NOT bolted onto either `id:1d83` call site.

Worth weighing at the same time: `unpromoted-scan.sh` already spans an archive (`routed:8b21`)
using a strictly STRONGER checkbox-anchored predicate, `^- \[[ x]\].*<!-- id:TOK -->`. The fleet
now has two archive-spanning twin checks at different strictness, **and the weaker one guards the
destructive operation.** Adopting the checkbox anchor in `_own_marker_re` may subsume the backtick
rule entirely; a quoted example is rarely the head of a checkbox line. That `routed:8b21`
precedent went uncited in `id:1d83`'s note and spec, and it is the closest prior art this repo
has -- exactly the "grep for the MECHANISM's nouns, not the topic's" check.

## Acceptance

* A fixture line quoting `` `<!-- id:XXXX -->` `` inside another item's body does NOT register as
  owning `XXXX`, for every `token_marker_*` consumer.
* The 13 tokens named above return to REFUSE under the four-file set.
* The genuine archive-only twin case (`id:1d83`'s spec, cases 1 and 2) stays GREEN -- this must
  narrow the predicate without undoing the widening.

## Related

`id:1d83` (the widening), `id:0246` (token extraction, the sibling anchoring gap), `id:c97c` /
`id:411d` (the incidents), `routed:8b21` (the stronger precedent).
