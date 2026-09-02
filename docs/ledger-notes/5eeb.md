# id:5eeb

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From REVIEW_ME

MEASURED (apex review, 2026-08-26): the 300,000 B threshold is crossed at transcript line **95** of `execute-repo`, whose first `Edit` was at line **133** — 38 lines of headroom, **zero commits**. `handback-followup.py:181` makes `route == "none"` a literal no-op, and the RELAY_LOG `HANDBACK:` prose line has **no machine reader** (`grep -rn 'HANDBACK:' relay/scripts/` = 1 hit, a comment). So re-dispatch reproduces the same investigation and the same empty handback, forever, with no accumulating signal. Rule 2c has no zero-commit branch. Note the pre-first-edit check point — the one the 63.9%/76.8% measurement demands — is precisely what GUARANTEES the empty handback in the case it was designed for. Owner's call: **(a)** distinct greppable zero-commit `HANDBACK:` form + escalate to `route="hard-split"` on the second occurrence (no new enum, no `handback-followup.py` change), or **(b)** make the PRE-FIRST-EDIT `warn` — which fires with 34 / 74 lines of headroom in both observed units — the actionable narrow-scope signal instead. NOT a defect in the delivered unit; the spec did not ask for it. <!-- id:5eeb -->

## From REVIEW_ME

(pre-satisfied by the v12 contract, so they can never fail): `*heckpoint*` (1 hit in the OLD contract) and the `*'route'*'none'*` glob (matches anywhere across a 250-line document, in any order). **Consequence: the `route="none"` disposition — the exact thing the livelock finding turns on — is NOT pinned by the spec**; a future edit could delete it with the suite still green. The contract itself states it correctly today, so this is latent, not a present defect. Tighten to a phrase-level match. Handoff-authored, untouched by the executor. <!-- id:5eeb -->
