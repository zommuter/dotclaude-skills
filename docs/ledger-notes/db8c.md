# id:db8c -- the `id:5355` date guard is UNREACHABLE through the sanctioned writer: `md-merge append` puts the date BEFORE the id marker, `archive-done.sh` requires it at END OF LINE

Found 2026-09-10 by walking into it, minutes after closing `id:1d83`. Two conventions that each
look right and cannot both be satisfied by the same line.

## The collision

* `meeting/md-merge.py`'s APPEND verb (`id:0af4`) is documented as adding text **"before its id
  marker"**, deliberately, so the `<!-- id:XXXX -->` marker stays trailing and marker anchoring
  keeps working (`id:411d`, `id:6059`).
* `todo-update/archive-done.sh:69` matches the date as
  `re.compile(r' on (\d{4}-\d{2}-\d{2})\.?\s*$')` -- **anchored to END OF LINE.**

So a date written through `md-merge append` lands as

    ... <!-- relates:1975 --> on 2026-09-10 <!-- id:1d83 -->

`date_re` does not match, `own_date` is `None`, and the line falls straight through to the
prior-commit branch and is archived. **The `id:5355` protection is silently absent for every line
dated through the sanctioned flock'd writer.**

## Observed, both directions, same session

| line | how the date was written | archiver verdict |
|---|---|---|
| `id:1975` | hand-composed, date AFTER the id marker | NOT archived (protection worked) |
| `id:1d83` | `md-merge append` -- date BEFORE the marker | ARCHIVED within a minute, despite the date |

The `id:1d83` sweep was harmless (its line carries no owning `routed:` twin; the `routed:` in its
title is prose). The point is that the protection did not apply, and nothing said so.

## Why this is the worst shape of bug

The path a careful author is TOLD to use is the one that silently does not work. CLAUDE.md routes
shared non-union ledger writes through `md-merge.py` specifically to avoid clobbering, and doing
that correctly is what removes the date protection. The only spelling that works is the hand-built
one the tool-choice rule steers away from. That is the `mechanize-first` principle inverted: the
mechanical path is the unsafe one.

Note that a date AFTER the marker is legitimate and not a hack -- trailing prose after an id
marker is explicitly supported (`id:798d`, e.g. `<!-- id:XXXX --> -- GATED (auto, id:3801)`), which
is precisely why `archive-done.sh` could anchor on end-of-line in the first place.

## Candidate fixes

1. **Relax `date_re`** to find ` on YYYY-MM-DD` anywhere after the title, not only at end of line.
   Smallest change, and it makes BOTH spellings work. Risk to check: a date inside an item's prose
   (e.g. "observed on 2026-08-13") would then read as a completion date and protect a line that
   was never dated. That risk is real and is the reason the anchor exists, so this cannot be a
   blind loosening -- scope it to the region after the last marker, or require it to be the last
   non-marker token.
2. **Teach `md-merge append` a mode that appends AFTER the trailing marker.** Keeps `date_re`
   strict, but adds a second spelling to a tool whose whole point is that one call does one safe
   thing, and every existing caller of `append` still lands before the marker.
3. **Mint the date in the line itself** when ticking, rather than appending it as a second op.
   Avoids the collision entirely for the common case but does nothing for the general one.

**Recommendation: (1), scoped rather than blind** -- it fixes every already-mis-dated line at once
and removes the trap instead of adding a second way to avoid it. The scoping question (how to
reject a prose date) is the part that needs judgment, and it is worth getting right because the
failure direction of a blind fix is "protects lines nobody dated", which re-grows the live ledger.

## Acceptance

* A line dated through `md-merge append` (date before the trailing marker) is NOT archived while
  its date is newer than the cutoff.
* A line dated by hand (date after the marker) keeps working.
* A line whose only `on YYYY-MM-DD` is inside explanatory PROSE is still archivable -- i.e. the
  fix does not turn every narrative date into a shield.
* `id:5355`'s own test still passes.

## Related

`id:5355` (the guard this defeats), `id:0af4` (the append verb), `id:798d` (trailing prose after a
marker is legal), `id:1d83` / `id:1975` (the two observations), `id:206e` (the archiver-side
invariant still unbuilt).
