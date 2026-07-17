# 2026-07-17 — The acc7 phantom: append.sh files unvalidated text and lets callers invent the receipt

**Started:** 2026-07-17 14:50
**Session:** 4b11c740-39f0-4db9-aef8-20562124bb79
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime lens)
**Topic:** `routed:acc7` was minted, reported as filed, and never written — what to repair, and what structurally prevents the class.

## Agenda

1. Repair: acc7's inbox entry carries a literal `$ID`; loderite cites `routed:acc7`. Adopt acc7 or re-mint?
2. Prevention: how does `append.sh` guarantee the entry it writes carries the token it reports?
3. Scope: what else in the cluster is real, and what is a separate item?

## Findings (verified pre-meeting)

- `routed:acc7` existed in **no** inbox and no repo. `todo-inbox.md:143` carried the literal marker
  `<!-- routed:$ID -->`.
- Cause — the loderite hand-run (`relay-manual-20260717-110236-21`) at 14:44 local ran:

  ```bash
  ID=$(append.sh new-id); append.sh -t inbox -e "… <!-- routed:\$ID -->" 2>&1 | tail -1; echo "filed routed:$ID"
  ```

  `$ID` is **escaped** in the payload and **unescaped** in the echo. Bash wrote the literal `$ID`;
  the echo reported `acc7`. The session believed its own receipt and moved on.
- `append.sh` prints **nothing** on success (`meeting/append.sh:283-287`) — so "filed routed:acc7"
  was the caller's own invention, computed from a variable with no causal link to the bytes on disk.
- `todo-conformance.sh --inbox` flagged line 143 as `orphan` — the sole non-conformer of 13. It is
  reachable only via `scan-routed.sh` (report-only) or a manual CLAUDE.md step; **no routine flow ran it.**
- Blast radius: `loderite/TODO.md:40` (`id:0c54`) cited `routed:acc7` — a dangling reference.
- 12 well-formed own-markers in the inbox at meeting start; **no** token collisions.
- The inbox store is git-tracked and healthy (`claude-sessions-backup.timer`, `git add -A`). A bad edit
  is recoverable — which softens the "unrecoverable" framing the `todo-routing` memory carries for this store.
- **Falsified hypothesis, recorded deliberately:** an initial read of "last inbox commit 12:02, now 14:50,
  file modified" suggested the backup timer had stopped. It had not. The jsonl timestamp `12:44:24Z` is
  **UTC**; local CEST is 14:44, i.e. *after* the 14:03 backup run. The backup is healthy. Checking beat asserting.

## Discussion

### Item 1 — Repair

🏗️ **Archie:** The content of line 143 is fine — a detailed, well-formed item. Only its marker is broken.
So this is a one-token edit, not a re-file. And I'd adopt `acc7` rather than mint fresh: it *was*
legitimately minted by `append.sh new-id` against loderite's ledger, `loderite/TODO.md:40` already cites
it, and nothing else claims it. Re-minting buys nothing and costs a cross-repo edit to fix `id:0c54`.

😈 **Riku:** Check the premise before adopting it. `new-id` collision-checks against `scan_ids <root>` —
`grep -rho 'id:[0-9a-f]\{4\}'` over loderite's meeting-notes, TODO, TODO.archive, ROADMAP
(`append.sh:176-185`). It does **not** scan the inbox, and `routed:acc7` doesn't match the `id:` pattern
anyway. acc7 was never checked against the namespace it was destined for.

🏗️ **Archie:** Fair — but I checked the outcome rather than trusting the mechanism. Twelve own-markers,
zero collisions, `acc7` not among them.

😈 **Riku:** Then say it that way. Adopting acc7 is safe **because it was verified**, not because the mint
was sound. Those are different claims and only one is true.

✂️ **Petra:** Adopt. One edit to one local file; the dangling citation fixes itself retroactively. The
alternative is two writes plus a cross-repo edit for zero benefit.

⚙️ **Sage:** One wrinkle on *how*. The global CLAUDE.md says the inbox is written via `append.sh`, never
by hand — but there is no verb for "fix a marker". `inbox-done` won't do it either: it would match
`routed:\$ID`, then correctly **refuse** (exit 3) because no twin exists in dotclaude-skills. That guard
works as designed. So the repair is necessarily a line-scoped edit under the inbox flock. Recoverable —
the store is committed — but outside the stated contract, and we should name that rather than pretend
`append.sh` covers it.

### Item 2 — Prevention

⚙️ **Sage:** The deeper failure isn't the escaping. It's that `append.sh -t inbox` accepts arbitrary text,
validates nothing, and prints nothing on success. The caller invented its receipt.

😈 **Riku:** Which is the punchline. The item being filed — the `@manual` structural hole — is *about*
proxies that pass while requirements fail. It cites `id:1735`, self-reported summaries. The act of filing
it committed the exact defect it describes. Not irony: evidence the class is systemic.

🏗️ **Archie:** Two candidates. **(A) Validate on write** — reject any `-t inbox` entry not matching
`^- \[[ x]\] \[[^]]+\] .* <!-- routed:[0-9a-f]{4} -->$`. Five lines; would have caught this, since literal
`$ID` fails the regex. **(B) Mint inside append** — `--route-to <repo>` mints the token, builds the
conforming line, writes it, echoes the token. The caller never interpolates; reported token equals written
token *by construction*, same variable.

✂️ **Petra:** N=2 on (B): `/meeting` step 2b's routing sub-step, relay handoff filing cross-repo items, and
ad-hoc hand-runs like today's. Three real consumers. Passes.

😈 **Riku:** (B) alone leaves the raw `-e` form unguarded, and it must stay — discoveries and personas use
it. (B) without (A) moves the hole rather than closing it.

🏗️ **Archie:** Then both, plus the piece that actually kills the receipt problem: **`-t inbox` always echoes
the routed token it truly wrote** — for `--route-to`, the one it minted; for raw `-e`, the one it *parses
back out of the line it appended*. Either way stdout is ground truth, so `filed routed:$(append.sh …)`
cannot lie.

⚙️ **Sage:** And there's precedent — `new-children` already emits its own marker line (`append.sh:206-221`)
rather than making the caller build it. (B) is that pattern extended, not a new idea.

### Item 3 — Scope

✂️ **Petra:** The **routed-namespace collision-check** folds in: we're writing the mint site anyway, and
checking the inbox's own-markers plus the target's `routed:` citations is three lines inside a loop we're
already touching.

😈 **Riku:** Agreed, but bound the claim. Twelve tokens over 65536 — collision probability today is ~0.1%.
Nobody should sell this as a live hazard. The reason to do it is that it is nearly free *in this edit*.

⚙️ **Sage:** The **conformance-lint wiring** is a different file and a different skill; once (A) validates
on write, the detector's remaining job is legacy entries and other `RELAY_INBOX` writers. Real but shrinking.

✂️ **Petra:** The **escaping instinct** — someone will want to ask why `$ID` was escaped, probably an
over-application of the CLAUDE.md `${VAR:-default}` permission-prompt gotcha, which doesn't apply to a bare
`$ID` in a payload.

😈 **Riku:** Don't. That motive is unreadable from the transcript, and (A) catches the effect regardless.
Designing a doc change on an inferred motive is precisely the drift CLAUDE.md warns about. Drop it.

🏗️ **Archie:** Last question, and not a formality: who builds it. `routed:6fd5` was filed **six minutes
before this meeting opened**. It says the orchestrator in a relay-managed repo does not implement in the
foreground — it files, hands off, dispatches, and reviews what it did not write. It exists because the owner
caught exactly that today: *"I didn't ask you to implement that now in foreground — you were supposed to do
the proper TODO/handoff/execute/review way!"*

😈 **Riku:** This repo has a `ROADMAP.md`. If I implement (A)+(B) in this session I write the code, write my
own tests for it, and self-verify — the precise shape rejected this morning.

⚙️ **Sage:** Status honestly, though: `routed:6fd5` is an **open inbox item**, not a ratified rule. Treating
it as binding is inheriting a solo verdict — the thing the owner is on record rejecting.

😈 **Riku:** Which cuts *toward* asking. Not ratified, so I don't apply it unilaterally; not refuted, so I
don't ignore it unilaterally. Owner's call. The acc7 repair is separable regardless — a ledger fix, not a
roadmap item.

**Tobias:** Ratified D1 "Adopt acc7 in place", D2 "Validate + mint-inside + echo", D3 "Fold in lint wiring
too", D4 "File to ROADMAP for the relay".

## Decisions

- **D1 — Repair by adopting acc7 in place.** Fix the marker `$ID` → `acc7` via a line-scoped edit under the
  inbox flock. Justified by *verification* (acc7 collides with none of the 12 existing own-markers), not by
  the soundness of the mint. loderite's `id:0c54` citation becomes correct retroactively.
  **Out of scope:** re-minting; any cross-repo edit to loderite; adding an `append.sh` verb for marker fixes.
- **D2 — `append.sh` gets validate + mint-inside + echo.** (A) `-t inbox` rejects a non-conforming line;
  (B) `--route-to <repo>` mints, builds and writes the line itself; and `-t inbox` **always echoes the token
  it actually wrote** — minted for `--route-to`, parsed back from the appended line for raw `-e`.
  **Out of scope:** removing or restricting the raw `-e` form (discoveries/personas depend on it); applying
  validation to the `discoveries`/`personas` targets.
- **D3 — Both fold-ins are in scope:** the routed-namespace collision-check (inside `--route-to`'s mint) and
  wiring `todo-conformance.sh --inbox` into `/meeting` step 7b. **Out of scope:** the "why was `$ID` escaped"
  CLAUDE.md question (dropped — unverifiable motive); a general dangling-`routed:`-citation detector.
- **D4 — This session does not implement.** It repairs the ledger, writes this note, and files ROADMAP items
  with RED specs; a separate executor implements and a separate review verifies. This honors the shape
  `routed:6fd5` proposes **without** ratifying that open proposal on the owner's behalf.
  **Out of scope:** treating `routed:6fd5` as settled; foreground implementation of `id:34c2`/`id:de36`.

## Action items

- [x] Repair `todo-inbox.md:143` marker `$ID` → `acc7` under the inbox flock; verify `todo-conformance.sh
  --inbox` reports no `orphan` and `routed:acc7` appears exactly once. *(Done in-session 2026-07-17;
  conformance clean, 13 own-markers, no collisions.)*
- [ ] `[ROUTINE]` **append.sh inbox write-path integrity** — `meeting/append.sh`. (A) `-t inbox` rejects a
  line not matching the conforming form; (B) `--route-to <repo>` mints + builds + appends the line; echo
  returns the token **actually written**; the mint collision-checks the routed namespace (inbox own-markers
  + target's `routed:` citations). Contract a test verifies: a payload containing a literal `$ID` is
  **rejected non-zero and not appended**; `--route-to` stdout equals the token present in the file.
  See `docs/meeting-notes/2026-07-17-1450-acc7-phantom-append-write-integrity.md`. <!-- id:34c2 -->
- [ ] `[ROUTINE]` **Conformance lint at the inbox surface** — `meeting/SKILL.md` step 7b runs
  `todo-conformance.sh --inbox` and surfaces non-conformers alongside the routed items. Contract a test
  verifies: SKILL.md step 7b invokes the lint; a seeded non-conforming entry is surfaced.
  See `docs/meeting-notes/2026-07-17-1450-acc7-phantom-append-write-integrity.md`. <!-- id:de36 -->
