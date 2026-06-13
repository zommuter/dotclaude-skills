# 2026-06-13 — Flag Opus-as-Fable-standin checkpoints for re-review (id:0420)

**Started:** 2026-06-13 08:59
**Session:** 66891536-a425-482e-bbbd-36fb77018a4c
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🔩 Gil (git plumbing — new)
**Topic:** When `/fables-turn` uses Opus as a Fable substitute during the Fable access outage, mark the resulting checkpoints so a future Fable session can find and re-audit them.

## Surfaced discoveries
None in discoveries.md intersect this specific topic (relay design lives in meeting notes, not the discovery log).

## Agenda
1. What actually triggers a "fable-standin" checkpoint, given `--fable-down` defers all strong work? (resolve the `STRONG_TIER=opus -d` contradiction in the item text)
2. Where does the marker live so it is durably grep-able when Fable returns?
3. Build-now vs defer: which half ships this session?
4. How does re-review surface in relay-loop.js once Fable is back? (defer — sketch only)

## Discussion

### Item 1 — what triggers a standin checkpoint

🏗️ **Archie:** The item says "`--fable-down` and Opus is used for review/handoff (i.e. `STRONG_TIER=opus -d`)". But that's not what the shipped code does. id:3737 made `-d` a *defer-everything* switch — `fableDownDeferred` pulls review and handoff out of the queue (`relay-loop.js:250–268`), and the zero-execute edge just exits. So under `-d`, no Opus agent ever runs. `STRONG_TIER=opus -d` produces zero Opus checkpoints. The two flags are orthogonal responses to the same outage, not a combination.

😈 **Riku:** Right. Two distinct outage strategies: **Substitute** (`STRONG_TIER=opus` without `-d`) — Opus does review/handoff *now*; these checkpoints are the real standin work a returning Fable should re-audit. **Defer** (`-d`) — skip strong work, accumulate review debt; when Fable returns the debt surfaces as normal `review` units (commits-after-last-ckpt). Nothing to re-review because nothing was reviewed. The marker belongs to the substitute path.

⚙️ **Sage:** `STRONG_TIER=opus` can also mean a deliberate Opus *pilot* (id:1ad7), so "opus checkpoint" conflates substitute vs pilot. Worth noting?

✂️ **Petra:** Don't discriminate — re-auditing a pilot checkpoint is harmless (Fable just confirms), missing a real standin is a permanent ledger gap. Asymmetric → mark every opus-strong review/handoff checkpoint, regardless of outage intent.

😈 **Riku:** Agreed. The label is a *re-review hint*, not a "Fable was provably down" assertion.

⚙️ **Sage:** Executor (Sonnet) checkpoints created during the outage are NOT standins — Sonnet is the normal executor tier. The marker must be scoped to review/handoff units only. That falls out naturally from where `STRONG_MODEL` is referenced (`relay-loop.js:357–359`).

### Item 2 — where the marker lives

🔩 **Gil:** Three candidate homes — RELAY_LOG.md heading (already has label, but correlating back to `fable-ckpt-*` tag needs timestamp matching); annotated **tag message** (currently summary-only, but the tag is the per-checkpoint object the discovery step already enumerates — natural key); relay.toml (mutable, append bloat). Tag message is the correct home.

🏗️ **Archie:** Make the token explicit (`fable-standin` literal) rather than relying on `claude-opus-4-8` string-matching — model IDs churn. A stable literal survives future Opus version bumps.

😈 **Riku:** Accepted. `fable-standin` means "strong tier was a non-Fable substitute," NOT a provenance claim about whether Fable was actually down.

**Code facts confirming the gap:** `ckpt-tag.sh:65` — `git tag -a "$tag" -m "$summary"` — drops `$label` entirely from the tag object. Label is only in the RELAY_LOG.md heading + integrator commit message. Fix: append `\n\n$label` to the tag message.

### Item 3 — build/defer

✂️ **Petra:** Marker recording is near-zero cost and lossy-if-deferred (outage checkpoints created now won't carry it retroactively) → build now. Discovery/re-review surfacing in relay-loop.js is high-blast-radius, untestable until a real standin tag exists, gated on "Fable returns" → defer with a tracked follow-up.

⚙️ **Sage:** Matches the "near-zero idle cost + naturally dormant ⟹ build the cheap recording half now" design heuristic (user profile, 2026-06-12).

### Item 4 — re-review surfacing (deferred sketch)

🏗️ **Archie:** When built: discovery classifier prompt gains a rule: "a repo whose latest `fable-ckpt-*` tag message contains `fable-standin` AND session is Fable-class ⟹ emit `review` with priority above normal unaudited-work review." Gated on Fable-class session so Opus runs don't re-review their own standin work. `git tag -l --format='%(contents)'` scan is cheap, no new state. Priority ordering decision deferred.

## Decisions

- **D1 — Trigger.** A "fable-standin" checkpoint is any review/handoff checkpoint where the strong tier was Opus (`STRONG_TIER=opus` without `-d`). The item's `STRONG_TIER=opus -d` phrasing is self-contradictory and rejected. Marker is a re-review hint, not a provenance assertion. All opus-strong review/handoff checkpoints get flagged (pilot + outage are not distinguished). Execute (Sonnet) units never flagged. **Out of scope:** intent discrimination.
- **D2 — Marker.** Explicit `fable-standin` token in the annotated tag message. `relay-loop.js` emits `reviewer (claude-opus-4-8, fable-standin, relay-loop)` when `STRONG_MODEL === 'claude-opus-4-8'` on non-execute units. `ckpt-tag.sh` carries the full label into the tag message (applies to all checkpoints; no standalone gate needed). Detection: `git tag -l --format='%(contents)' | grep fable-standin`. Stable across Opus model-ID churn. **Out of scope:** relay.toml listing, model-ID-only detection.
- **D3 — Scope.** Marker recording ships this session (lossy-if-deferred). Discovery/priority rule deferred, gated on "Fable access restored." **Out of scope this session:** classifier verdict-logic change.

## Action items

- [x] `relay-loop.js`: `standInSuffix` conditional appends `, fable-standin` to reviewer label when `STRONG_MODEL === 'claude-opus-4-8'`. Execute label unchanged. Done in-session. <!-- id:9f3f -->
- [x] `ckpt-tag.sh`: `git tag -a "$tag" -m "$summary\n\n$label"` — label now included in every annotated tag message. Done in-session. <!-- id:9f3f -->
- [x] `tests/test_fable_standin_marker.sh`: 8 static-grep checks, all PASS; `make test` 16/16 green. Done in-session. <!-- id:9f3f -->
- [ ] relay-loop.js discovery step: surface `fable-standin`-tagged checkpoints as priority `review` units when session is Fable-class. Gate: "Fable access restored." See TODO.md. <!-- id:9821 -->
