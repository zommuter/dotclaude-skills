# 2026-06-22 — Strong-model audit (id:401c Run 40)

**Window:** `3600642..HEAD` (HEAD = `10d837e`, checkpoint `relay-ckpt-20260622-1715`) —
Run 39's audit merge `3600642` to current HEAD. ~251 lines across 12 files.
**Mode:** Opus apex HARD-execute child (id:da26), 3-pass adversarial audit.
**Suite:** 82/0 test-files (unchanged file count; this run's regression guard is a new
assertion inside `test_gather_repo_state.sh`, taking it 17→18 internal cases).

## Window contents

First-seen code (`git diff --name-only 3600642..HEAD -- '*.sh' '*.py' '*.js'`):

- `relay/scripts/gather-repo-state.sh` — id:93cc ROADMAP discovery-view trimmer: emit OPEN
  items + section headers + preamble only, drop done `[x]` item-blocks (with a non-silent
  omission note) so a large ROADMAP's done history doesn't bloat the discovery shard.
- `relay/scripts/relay-loop.js` — id:7d1e finer-grained progress buckets: route each work
  unit to a per-verdict phase (Execute/Review/Hard/Handoff) and shunt support agents
  (quota/release/inject) to a "Support" bucket, instead of one crowded "Dispatch" group.
- `relay/scripts/loop-hint.sh` + `relay/SKILL.md` step 0a/4 — id:bde8 loop-hint resilience
  wording correction: `/loop` (and in-session cron) dies WITH the session; it is resilient
  only to relay's own early-exit (quota/seatbelt) within a LIVE session, NOT to a
  session/process kill. Removed the false "unattended outage resilience" promise.
- `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md` — design resolution for
  id:98f0/7809 (watchdog observe-first + auto-reconcile-on-restart) + the cheap fixes
  id:bde8/0994; retags 7809/98f0 `[HARD — meeting]`→`[HARD — hands]` post-meeting.
- Tests: `test_gather_repo_state.sh` (+7 trim cases), `test_relay_loop_structure.sh`
  (+1b per-verdict buckets), `test_loop_hint_resilience_wording.sh` (new, roadmap:bde8).

## Pass 1 — Code review

**1 forward-robustness defect FIXED INLINE** (the only inline change to production code):

The id:93cc trimmer in `gather-repo-state.sh` ran `python3 -c '…' 2>/dev/null || true`. On a
trimmer crash (any unexpected python error) this failed **CLOSED** to an EMPTY `roadmap`
field. An empty roadmap is not benign here: the discovery shard treats "roadmap missing/no
marker" as the **handoff** verdict (relay-loop.js ~L630) and would re-do the expensive C1/C2
handoff work, or mis-count open ROUTINE/HARD items. Changed to fail-**OPEN**:
`… 2>/dev/null || cat "$path/ROADMAP.md" 2>/dev/null || true` — on a trimmer error the FULL
(untrimmed) ROADMAP is emitted: bloated but correct, which always beats a silent empty one.
This aligns with the documented `feedback-mechanize-no-swallow-stderr` principle and the
sibling `discover-sig.sh` fail-open intent. Added a **non-vacuous** regression guard
(`test_gather_repo_state.sh` case 8): shadows `python3` with a stub that fails ONLY when
`ROADMAP_PATH` is set (so `emit()`'s JSON builder still works), asserts the roadmap field
falls back to the full ROADMAP. **Proven RED on the reverted form** (the `|| true` variant
produces empty → test fails) before re-applying the fix.

Otherwise CLEAN to a high bar:

- Trimmer block-parsing is correct: an item block runs from a `- [ ]`/`- [x]` line to the
  next item line OR a `## ` header; done blocks dropped, open blocks + headers + preamble
  kept; the omission note is appended only when something was dropped. Traced on a fixture.
- id:7d1e per-verdict buckets are a **pure display grouping** — `unitPhase(unit.verdict)`
  only changes the `phase:` label on each agent; zero behavioural change. Consistent with
  the pre-existing `Integrate` bucket (also display-only, declared in `meta.phases`, never a
  `phase()` progress marker). No agent still uses the monolithic `'Dispatch'` phase.
- loop-hint.sh is wording/doc only.

## Pass 2 — Security

CLEAN. `gaming-scan.sh . 3600642` → exit 0, no output. No injection surface introduced: the
trimmer reads a single env-passed file path (`ROADMAP_PATH`) inside a single-quoted
`python3 -c` body and the fallback `cat "$path/ROADMAP.md"` is quoted; `$path` is a
relay-controlled repo path. The relay-loop.js changes are JS object/string literals with no
input surface. No secrets, no path traversal, no permission assumptions.

## Pass 3 — Design coherence

CLEAN, with **2 ledger coherence drifts fixed inline** (the recurring d5e0/mirror class):

- The id:bde8 loop-hint correction is internally consistent and matches project memory
  `babysitter-durable-cron-no-op` ("in-session cron/loop/wakeup die with the session") and
  the new meeting note's Decision 1. No contradiction between SKILL.md step 0a, step 4,
  loop-hint.sh, and the meeting note.
- Verified the meeting note's claimed `[HARD — meeting]→[HARD — hands]` retag of id:7809 and
  id:98f0 ACTUALLY landed in ROADMAP (it did), and that new items id:e149 (foundation) and
  id:0994 are wired as `[HARD — hands]`. id:bde8 is correctly closed `[x] [ROUTINE]` (it is
  the code audited here).
- **Drift (a):** TODO d5e0 count line still read "5 open ROADMAP items, all HARD" and
  mislabelled 7809/98f0 as `[HARD — meeting]`. The live ROADMAP open-HARD set is now 7
  executable-or-gated (401c/3346/dba3/e149/7809/98f0/0994) + DEFERRED de4e (non-executable,
  the 8th `[ ]` line). Corrected the count 5→7, added e149/0994, fixed the 7809/98f0 lane.
- **Drift (b):** the TODO id:401c MIRROR line still read "Latest ✓ Run 39"; refreshed to
  Run 40 with this run's findings.

Cross-ledger coherent: 0 open ROUTINE / 7 open HARD (401c [pool] / 3346 [meeting] /
dba3 [decision-gate] / e149/7809/98f0/0994 [hands]); de4e DEFERRED non-executable; all open
in both ROADMAP+TODO. Pre-existing accepted (out of window): `orphan-scan --cross-ledger`
flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x] — the intended single-id-two-views shape
(accepted in Runs 37–39). Both tracked flakes id:16e9/id:05e8 did not recur.

## Findings summary

| # | Pass | Finding | Disposition |
|---|------|---------|-------------|
| 1 | Code | id:93cc trimmer failed CLOSED to empty roadmap on a crash → would misclassify repo as handoff | **FIXED INLINE** (fail-open `\|\| cat ROADMAP.md`) + non-vacuous regression guard |
| 2 | Design | TODO d5e0 count line stale (5→7, wrong lanes for 7809/98f0, missing e149/0994) | **FIXED INLINE** |
| 3 | Design | TODO id:401c mirror line stale ("Run 39") | **FIXED INLINE** (→ Run 40) |

No security defects. No findings silently dropped.
