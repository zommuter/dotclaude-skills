# Session handover -- 2026-09-11 (Opus 5, 1M context)

Successor to `docs/session-handover-2026-09-10.md` (1,251 lines, five stacked sections). That file
stays as the previous day's record. **Four of its claims were verified FALSE today and are corrected
below** -- read this file's corrections before acting on anything in it.

Point-in-time snapshot. Durable detail lives in the ledger items and `docs/ledger-notes/<id>.md`
files cited here; read those, and do not trust this doc where it disagrees with them.

## State at close

| | |
|---|---|
| `main` | `29db4baa`, clean, 0 unpushed |
| **Public GitHub** | **0 behind -- PUBLISHED 2026-09-11 on the owner's decision** (9 commits, `3541b328..29db4baa`) |
| Suite | **651 passed, 0 failed, 0 errored, 1 expected-red** -- re-run independently, not taken from an agent's report |
| **Parked orphans, fleet-wide** | **0 across 61 canonical repos** (was 6 real, which I had miscounted as 7) |
| **Leaked relay worktrees** | **0** (was 10). `~/.cache/relay/worktrees` is 1.8 MB |
| Shared inbox | 0 open |
| REVIEW_ME here | 86 open |
| `[MECHANICAL]` queue | `pending/` empty, `running/` empty, 12 unapproved drafts, daemon timer live |
| Relay pool | launching at close: `--afk --quota-7d 70 --once --execute-agent-type relay-implementer` |

## READ FIRST: the 650 k execute refusal was a MISATTRIBUTION, and yesterday's handover is wrong about it

Yesterday recorded this repo as *"structurally undispatchable on the execute lane"* at ~650,104 tok
against a 100,000 budget, and pointed at ledger size. **That is not the cause.**

`b437` was this repo's ONLY actionable `[ROUTINE]` id and it was orphan-suppressed. Suppression
drained the permitted set, an empty set means `dispatchItemFor` returns `''`, `sliceLedgerForUnit`
takes its no-item branch and produces NO slice, and the size gate then falls back to whole-ledger
sizing. A normal `b437` slice measures ~5.4 KB, roughly 67,900 tok, comfortably under the cap.
Verified live, and the repo dispatches execute again now that the orphan is gone.

**What IS structural, and worth keeping:** the two ledger FILES alone, every note excluded, are
297,675 B = 74,419 tok against a 35,000-tok payload budget -- **2.13x over**. The unsliced fallback
can never fit here, so any future empty-after-suppression round reproduces this identically. The
guard added under `id:c076` now says `This is NOT a ledger-size problem` so the next reader is not
sent to the archivers.

**`id:0d7c` CANNOT help this gate** (measured, now recorded on the item). The gate charges
`file size + every pointed-to note`, so relocating prose from a line into `docs/ledger-notes/<id>.md`
moves bytes between two charged columns: **net zero**, plus a per-note header. Notes are already
2,036,546 B, 78.3% of the estimate, and they got there by exactly this mechanism. This is the
`id:f3d2` optimism trap seen from the other side -- f3d2 correctly refused to let the shrink hide
bytes from the gate, and the necessary consequence is that the shrink cannot lower the number
either. `0d7c` remains worthwhile on its own merits; it is not a prompt-size lever.

## The four corrections to yesterday's handover

1. **`id:c076` fired SEVEN times, not five**, across **two distinct causes**. Confirmed against
   `~/.config/relay/relay-events.jsonl` (field is `kind`, NOT `event`), with 12 non-zero dispatches
   in the same run as the control. Cause A, 5 firings: the RECHAIN path (`relay-loop.js:4744`)
   pushes a hand-built 7-field unit literal that never went through the classifier -- `sig:""` on
   every one. **Still unfixed, deliberately out of scope.** Cause B, 2 firings: a fourth looser copy
   of the open-`[ROUTINE]` predicate. Fixed.
2. **project_manager's `M IDEAS.md` was NOT "a live concurrent session, explained, not a defect".**
   It is BYTE-IDENTICAL to orphan `execute-9a1b-0`'s committed `IDEAS.md`, and `main`'s `ideas.py`
   lacks the marker code, so nothing on main could have produced it. **The `id:aa93` guard refused to
   integrate a unit because that unit's own output was uncommitted in the target tree.** Merging the
   orphan cleared the tree and turned the suite green.
3. **`id:2b7a`'s `:190` predicate recurred**, exactly as that item predicted it would. Filed as
   `id:68e2` and FIXED (see below).
4. **The `id:3dea` null-verdict failure is NOT silent.** Every `verdicts.json` names its own failure
   in a machine-readable `parse_error` field; the acceptance check simply never READS it. That makes
   the fix far cheaper than "existence-only cannot tell success from failure" implies. Also FOUR
   files, not three, and NOT a regression -- the 2026-07-26 control is also null for an unrelated
   reason (the model emitted prose with zero `{`).

## What landed

* **`id:68e2` FIXED** -- `worktree-retire.sh` gated on a bare `git status --porcelain` with no
  `git diff` cross-check, so cosmetic git-annex pointer dirt read as residue. The `id:3016`
  predicate is now a SHARED `relay/scripts/lib-clean-tree.sh` sourced by BOTH `worktree-retire.sh`
  and `verify-isolation.sh` -- not a fourth copy. Verified against the ORIGINAL incident, not its
  own fixtures: 3 real false-dirty trees read CLEAN, a real modification reads DIRTY, an untracked
  file reads DIRTY. Proven on a genuine annex worktree with a symlinked `.git`.
  **Why this mattered:** `relay-reconcile.sh --all` correctly called those worktrees "no work at
  risk" and then recommended the one command the log shows refusing them 30 times in a day.
* **`id:c076` CLOSED** on the owner's dissolved-enough ruling. Predicate unified into
  `classify-repo.sh`; fail-closed dispatch guard added. **Upstream dissolution deliberately NOT
  done**, four verified blockers on the item, chief among them that `--no-reconcile` SKIPS the
  suppression source so the snapshot producer and the live loop would emit different verdicts for
  the same repo (the `id:4347` two-tools-disagree class). **Accepted residual: relay-doctor
  invariant I2 still sees the pre-suppression count.**
* **`id:6fda` BUILT and CLOSED** as the **`decision-brief`** skill (`decision-brief/SKILL.md` +
  `docket.sh`). Recommend-never-decide is MECHANICAL: exit 4 unconfirmed, **exit 5 unattended even
  WITH the flag**, the unattended refusal outranking the confirmation because a confirmation where
  no owner exists can only have been set by an agent. `calibrate()` runs ten both-polarity controls
  and exits 3 emitting nothing countable on failure. Both guards verified independently.
  **Stated weakness: `--owner-confirmed` is agent-settable in an ATTENDED session** -- forgery
  reduced to a deliberate act, not eliminated. Untested at fleet scale (only this repo scanned).
* **`id:b545` filed** -- `verify-isolation.sh`'s UNKNOWN-is-clean fail-open, preserved deliberately
  rather than bundled into the 68e2 fix.
* **`id:153f` filed** -- a lane tag placed AFTER an item's `-- detail:` pointer is invisible to every
  anchored reader. **Scope deliberately UNESTABLISHED**: the collector found 9 in its candidate set,
  a crude grep says ~32, and a bare grep over-reports on this corpus.
* **6 orphans merged across 4 repos.** THREE were implementations for RED specs their own repo was
  already failing on -- project_manager `id:9a1b` (4 failed -> 305 passed), loderite `roadmap:d450`
  (9 failed -> 4 failed, 5 fixed 0 broken, measured against a pre-merge baseline worktree),
  mathematical-writing `id:f8d5`. Plus code.lawless `a736` (CloakNet watcher) and a Playwright probe
  salvaged into the `id:2004` doc. **The orphan mechanism was hiding finished work AND suppressing
  the items that work belonged to.**
* **ai-codebench: 3 of 5 judge verdicts recovered**, backup verified at
  `~/.cache/ai-codebench-output-backup-2026-09-11/`, `judged_in` back-populated on 9 manifests.

## OWNER RULINGS recorded today

1. **`id:c076`: dissolved-enough, CLOSE it.** Do not pursue the upstream `actionable_routine_open`
   change; demote-vs-drop stays undecided and would be an `--exclude` (`id:bc2b`) question.
2. **`id:6fda`: BUILD it**, full version with propose-then-confirm, not the narrow read-only variant.
3. **PUBLISH** dotclaude-skills after the audit. Done.
4. **`id:f8d5`: merge and leave it OPEN with its one red test as the spec.**
5. **`b437`: discard** (stale), **`truncocraft` symlink: removed**, **code.lawless dup doc: discard**.
6. **HANDS OFF the git-diary skill's public-remote list.** loderite is CLOSED SOURCE and its GitHub
   repo is issue-tracking only, so its absence from a public-CODE list is CORRECT. **My "the list has
   rotted again" finding was WRONG and is withdrawn.** Do not re-raise it.
7. **Next pool: `--once` with `relay-implementer`, then CONSIDER making it the default.**

## Needs the owner

1. **Evaluate the `--once` pool that launched at close** and decide whether `relay-implementer`
   becomes the DEFAULT execute agent type. What to measure: did any execute child die
   `Prompt is too long`? Last run 4 did, with the flag unset. **Zero deaths in one round is NOT
   proof** -- `id:3846` is explicitly recorded as promising-and-unproven, and this repo's own
   pilot-sample rule says n=10 cannot separate rates within ~10pp.
2. **`id:153f` scope** needs a real count via `leading_lane_run` + a POPULATED `lane_vocab_scrape`,
   not a grep.
3. **`id:3dea`'s remaining half**: should the recipe schema gain a content PREDICATE (a jq
   expression, a non-null field) so a well-formed-but-empty artifact fails loudly? Not built.
4. **`id:b545`**: make `verify-isolation.sh` fail closed on UNKNOWN? It is a dispatch-behaviour
   change and needs its own test.
5. **12 unapproved `[MECHANICAL]` drafts** in `recipes/drafts/`, including `bde7` (decision-gated GPU
   run) and `11c3` (a gated container). **Promoting a draft to `pending/` unattended would run
   exactly the work that is gated.**
6. **`id:5fe2` on code.lawless** was already reconciled by two later checkpoints -- **no supervised
   re-merge is needed**, contrary to yesterday's list. Verified: `866b226a` is on `origin/main`,
   `relay.toml last_ckpt` matches the latest tag.

## Method notes -- traps that cost time today, several of them documented and walked into anyway

* **NEVER enumerate repos with a `~/src/*` glob.** `relay.toml` is THE own-repo + path source; use
  `relay/scripts/lib-own-repos.sh`'s `own_repos` with `$RELAY_TOML` and `$SRC_DIR` set, **and check
  its exit status explicitly** -- a bare `while ...; done < <(own_repos)` DISCARDS the status and
  silently yields zero repos (`id:0fa0`). The glob is blind to all **17 zkm plugins** under
  `~/src/zkm/plugins/` and followed `~/src/truncocraft`, a legacy symlink to loderite, so it was
  wrong in BOTH directions at once. The owner caught this, not me.
* **In zsh the variable `path` is TIED to `PATH`.** A loop variable named `path` destroyed the
  environment mid-sweep and every subsequent `git` silently failed, producing a confident
  **"61 repos checked, 0 orphans"**. This is in yesterday's Method notes and I walked into it anyway.
* **`/tmp` is tmpfs and CANNOT reflink.** Staging a test worktree in the scratchpad made
  mathematical-writing's reflink tests report **"14 skipped"**, which reads as clean. Their own skip
  message says `environmental skip, NOT a pass`. Run them on a btrfs path.
* **A merge-base delta CANNOT see what the other side did in parallel.** "Additive from merge-base"
  is NOT "safe to merge": it produced an add/add conflict on code.lawless, and on `b437` would have
  REVERTED 7 items across 228 commits. **Internal-quality verification of a branch says nothing about
  whether its TARGET still looks like it did.** Always diff the branch's touched files against
  today's `main`, not only against its merge-base.
* **A bare grep over-reports on this corpus, because the corpus discusses what you are grepping
  for.** Three instances today: lane-after-pointer 87 then 32 against a true 9 in scope;
  `[MECHANICAL]` 9 against a true 3. Resolve lanes with `leading_lane_run` + `lane_vocab_scrape`.
* **And that lane probe FAILS SILENTLY:** sourcing `lib-lane-anchor.sh` alone leaves `all_lane_tags`
  EMPTY, so a standalone probe returns "no lane" for every line on earth. **Calibrate on a known-good
  line and REFUSE to report a count if the control comes back empty.**
* **`mechanical-daemon.log` is 99.8% test-harness fixtures** (12,265 of 12,293 lines are
  `demo-repo`/`my-repo`/`/tmp/tmp.*`). Same contamination class as `relay-worktree-retire.log`.
  Filter before counting anything.
* **The privacy GATE and the privacy AUDIT have different SCOPES and can look contradictory.** The
  gate is DIFF-scoped and flags an entire changed line including text already on it; the audit counts
  OCCURRENCES. A gate WARN on a line you edited, with an unchanged audit count, means the hit was
  already there. Today's WARN was the substring inside the ordinary English word "Evidence", already
  on public GitHub.
* **Publishing evidence should be a CONTROLLED BEFORE/AFTER, not a judgement.** Build a worktree at
  `github/main`, run `tools/privacy-audit.sh` there, and diff it against HEAD's report. Today both
  were byte-identical -- 8 indices, 307 occurrences, 220 file-hits -- so the delta added zero new
  occurrences in zero new files. Capture the audit's OWN exit code, never a wrapper's.
* **A denied destructive op is a HANDBACK, not a puzzle.** `branch -D` and `worktree remove --force`
  were both denied today and correctly so. Where the work needed preserving, tag it and hand the
  owner the command (`salvage/b437-stale-shrink-20260909` -> `9e88be64`).

## Sentinel litter

One stale STOP sentinel remains in `~/.config/relay/`. Harmless (keyed to a run id, so it cannot
false-stop another pool -- that scoping is what `id:cd94` bought) but nothing reaps them. Still
unfiled, as it was yesterday.

---

# AFTERNOON -- same session, two pool runs and the predicate class closed. THIS IS THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `c4871d74`, clean, 0 unpushed |
| **Public GitHub** | **0 behind -- published twice today** (`3541b328..29db4baa`, then `..c4871d74`) |
| Suite | **653 passed, 0 failed, 0 errored, 1 expected-red** -- re-run independently |
| Parked orphans, fleet-wide | **0** across 61 canonical repos |
| Leaked relay worktrees | **0** |
| Shared inbox | **0 open** |
| REVIEW_ME here | 86 open |
| 7d quota | 62%, never the stopper today (two pool runs cost ~3 points total) |

## READ FIRST: the bare-porcelain predicate class is CLOSED, all four instances

One shared helper, `relay/scripts/lib-clean-tree.sh`, sourced by every site. No fifth copy.

| id | site | note |
|---|---|---|
| `id:3016` | `verify-isolation.sh` main path | pre-existing |
| `id:68e2` | `worktree-retire.sh` | created the shared helper |
| `id:0fad` | `verify-isolation.sh` id:1b13 breach branch | the fix landed in that FILE without reaching that BRANCH |
| `id:fac7` | `gather-repo-state.sh:191` | the last one; was mis-routed to relay-core first, see below |

**Proven end-to-end, not just by fixtures:** the code.lawless annex worktree that handed back
`handbackCode=21 breach-shaped` in the morning retired force-free in the afternoon. Each fix was
also checked against a GENUINE dirty tree and an UNTRACKED-only tree, both of which must still
read dirty -- that control matters more than the happy path, because inverting it destroys work.

**`id:fac7` carries ONE owner-ratified change beyond its scope:** `rc=2` (git status itself
failed) now reads DIRTY where it used to read clean. Consequence on the record: **a bare repo now
classifies `blocked`.** The `-n "$porcelain"` arms on both `dirty_lock_only` and
`dirty_untracked_only` are LOAD-BEARING for that and must not be removed -- on rc=2 the porcelain
is empty, which would make both exemptions vacuously true and hand the fail-safe straight back out.

## The correction that matters most: I mis-routed a fix on a stale memory

I routed `gather-repo-state.sh:191` to relay-core as `routed:b062`, on a memory saying relay-core's
shadow binary reimplements both `classify-verdict.sh` and `gather-repo-state.sh`. **The second half
is false.** relay-core contains no `gather-repo-state.sh` at all, and `RelayCore/ClassifyVerdict.lean`
branches on DERIVED COUNTS from assembled JSON -- every ROADMAP/porcelain string in it is a comment
or a reason string, and `grep -c primary_lane` is 0. A delegated handoff agent caught it; I verified
against the code before accepting.

**The distinction that makes it hold, and the reason the memory is now narrowed rather than
deleted:** `gather-repo-state.sh` produces the SHARED INPUT both sides consume, so changing its
internals feeds both the same new value and parity cannot diverge. Only a DERIVATION the shadow
re-implements can. `classify-verdict.sh` derivations ARE shadowed and still need cross-repo routing.

Cost: the routing became a relay-core stub for a file that repo does not contain, was resolved out
of the inbox, and briefly left the bash half with no home. Re-filed as `id:fac7`, `id:0fad`'s
instruction corrected in place, memory `classify-shadow-parity` narrowed.

## Two pool runs

**`relay-20260911-103808-7255`** (`--once --execute-agent-type relay-implementer`): 4 integrated,
4 handbacks, 1 round. **`relay-20260911-130708-23209`** (`--only relay-core --afk`): 1 integrated,
**0 handbacks, 0 agent errors, `stopReason: drained`** -- the first fully clean run of the day.

**`f8d5` was finished BY the pool**, hours after being merged with one red test as a documented
spec. mathematical-writing went 204/1-failed to 205/0. Leaving a precisely-scoped red as the spec
is what made that possible.

**relay-core went blocked -> human -> hard -> drained in one session**, each step a different
problem: nine-day-old uncommitted stubs, then no lanes, then one apex unit, then closed. Its
`id:1841` resolved the way its verify-first DoD was designed to allow -- the executor re-derived
the premise, found both greps 0, **ported nothing**, and pinned the tolerance with 912 probes over
228 fixtures, parity 228/228.

## `EXECUTE_AGENT_TYPE`: the question is answered, and the flag is not the lever

One execute child still died `Prompt is too long` WITH `relay-implementer` set. **The death was
MID-RUN, not at dispatch** -- proven by its own `id:f272` residue commit containing 24 completed
shrink pairs, which a child dying at dispatch could not have produced. `id:c3c1` trims a fixed
~82k preamble; this is unbounded growth during work in a repo with a 266 KB `TODO.md`. Filed as
**`id:677b`**, which front-loads the question that must come first: executor-contract rule 2c's
budget check ALREADY EXISTS, fails OPEN to `unknown`, and did not prevent this. Establish whether
it fired before building a second mechanism around it.

Flag stays ON, unpromoted. 1-of-5 versus 4-of-6 is encouraging and is a SMALLER sample than the
run that already failed to settle `id:3846`.

## Filed today, unworked

* **`id:677b`** -- mid-run context death (above).
* **`id:8ab8`** -- `inbox-done`'s twin guard checks the target file ON DISK, not whether it is
  COMMITTED. Observed live: two routings survived only as a nine-day-old uncommitted edit, their
  inbox lines already deleted. **Second, independent cost:** an uncommitted ledger edit makes
  `classify-repo.sh` return `blocked`, so resolving an inbox item is what left the tree dirty --
  the guard's success condition and the repo's health were in direct conflict.
* **`id:153f`** -- a lane tag after an item's `-- detail:` pointer is invisible to anchored readers.
  Scope deliberately UNESTABLISHED: 9 in the collector's candidate set, ~32 by a crude grep, and a
  bare grep over-reports on this corpus.
* **`id:b545`** -- `verify-isolation.sh`'s UNKNOWN-is-clean fail-open, deliberately NOT bundled.

## Method notes -- additions from this half

* **A flagged risk is a CLAIM TO CHECK, not a finding to inherit.** An agent warned that a marker
  had lost line-finality and that anchored tooling might break. It had not -- `md-merge.py` places
  an appended note BEFORE the marker by design. One command disposed of it; inheriting it would
  have produced a phantom item.
* **The privacy GATE and the privacy AUDIT have different SCOPES and look contradictory when both
  are right.** The gate is DIFF-scoped and flags a whole changed line including text already on it;
  the audit counts OCCURRENCES. Today's publish moved the audit's `#2` count +1 across +2 files --
  reconciled exactly: the ledger shrink RELOCATED one occurrence out of `TODO.md` (4 -> 3) into a
  note, and the handover added one. **Zero whole-word matches in the entire delta**; every hit was
  inside the word "Evidence". Prose moving between files changes per-file counts without changing
  exposure.
* **`check-install-drift.sh` earns its keep the first launch after a NEW shared lib lands.** It
  caught `lib-clean-tree.sh` uninstalled; `verify-isolation.sh` resolves
  `dirname "${BASH_SOURCE[0]}"`, which through the installed SYMLINK is `~/.claude/skills/...`, so
  it died outright. That script is invariant 5's isolation gate -- EVERY unit would have failed to
  integrate. A `realpath`-based source would be robust; the current form breaks precisely because
  the install is a symlink.
* **Sequence an agent that edits a live relay script against a running pool.** Installed relay
  scripts are per-file symlinks, so an edit is live mid-round. `gather-repo-state.sh` is read by
  discovery every round; the `id:fac7` fix was held until the relay-core pool could follow it.
* **Backticks inside a double-quoted `git commit -m` are COMMAND SUBSTITUTION.** zsh ran `path`
  and ate the word. The git-diary skill mandates a quoted heredoc for exactly this. Use
  `git commit -F <file>`. It cost one mangled (already-pushed, not amended) commit message.
* **A bare grep over-reported FOUR times today**, always on a corpus that discusses what is being
  searched for: `[MECHANICAL]` 9 vs a true 3; lane-after-pointer 87 then 32 vs 9 in scope; and an
  old-vocab lane-tag check that flagged 4 hits, every one of them a deliberately-broken citation or
  a quoted COUNT rather than a lane tag. The pre-commit ratchet was right and my grep was wrong.
* **A deliberately-broken token citation is the sanctioned way past the vocab ratchet** -- NOT
  `--no-verify`, and NOT rewriting the citation into the new vocabulary, which destroys the meaning
  of a sentence whose subject IS the old spelling. Follow the `id:c076` precedent and declare the
  edit in the commit message.
