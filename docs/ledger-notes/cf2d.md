# id:cf2d

Detail relocated out of the ledger by `tools/ledger-continuations.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

**This note is EDITABLE** (owner-ratified 2026-09-02). If a fleet rule is violated
in the prose below -- retired vocabulary, a lane delimiter, a banned token -- FIX IT
HERE and amend the line above to say what was changed. Notes are not immutable: an
unfixable violation keeps its guard red forever, and this prose gets copied back out
into new items. An undeclared edit makes the verbatim claim above a lie.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

**EDITED ON RELOCATION (2026-09-02, `id:40c0`) -- the verbatim claim above is amended
for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any
prose already in that section arrived by an earlier pass and is untouched here.** Fleet-rule violations found in the relocated
prose were FIXED here rather than parked: 10 punctuation em dashes became `--`. Nothing else changed: no word, figure, marker or line break was
altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation
included.

## From ROADMAP

  - **Context -- the defect this closes out.** The `Stop` hook shipped 2026-08-13 for `routed:29bc`/`id:2419` **blocked nothing for six days**: `~/.claude/logs/meeting-question-guard.log` held 50 firings, every one `WARN … trailing segment is empty`, with **zero BLOCK and zero SKIP**. Cause: the Stop hook chain runs **before** the harness appends the just-ended turn's assistant lines to the session JSONL, so `trailing_segment()` was structurally always `[]`. Measured on a live session transcript (2026-08-19): the cost logger -- first in the same Stop chain -- recorded `wc -l` = 83, and line 83 was the `attachment` following a `user` tool_result; the turn's own 3159-char assistant `text` was line **84**, appended afterwards. On a second live transcript the same ordering hid a **7515-char bare-prose meeting turn** -- exactly the defect the hook exists to block.
  - **Why the green suite missed it.** Every fixture in `tests/test_meeting_question_guard_29bc.sh` writes the trailing assistant entry **before** invoking the hook -- a state the live harness never presents at Stop time. 16/16 green tested a premise, not the environment.
  - **Fix (LANDED this session).** `await_trailing_segment()` in `hooks/meeting-question-guard.py` polls until the turn appears and settles (`DEFAULT_WAIT_SECS=3.0`, `POLL_SECS=0.05`, `SETTLE_SECS=0.30`, budget overridable via `MEETING_STOP_GUARD_WAIT`). A turn that never appears is logged at a distinct **`NOFLUSH`** level and fails open -- loudly, never silently (`id:4347`). The meeting-open check runs **twice**: cheaply on the first read so a non-meeting Stop pays no wait, and again on the settled entries so the turn that WRITES the meeting note is not judged as still inside the window. `tests/test_meeting_question_guard_flush.sh` is the missing negative control (6 tests; verified to FAIL 3/6 against the pre-fix hook, reproducing the production `WARN … trailing segment is empty` line).
  - **What is NOT yet established, and is the whole point of this item.** The tests prove the wait works when a writer appends **concurrently**. They do **not** prove the live harness appends the turn while a Stop hook is still running rather than strictly **after** all Stop hooks return. If it is the latter, every meeting turn pays the 3 s budget and the guard is still a no-op -- it would just say so at `NOFLUSH` instead of `WARN`. That premise could not be settled from existing data (both orderings are consistent with the second-precision timestamps available) and was deliberately **not assumed**.
  - **`@owner-verify` because it is an observability claim, not a code claim** (global CLAUDE.md §"Poolability is decided by observability"): it can only be produced by exercising a real `/meeting`, which the pool cannot manufacture.
  - **Acceptance** -- after the next real `/meeting` on a non-Fable session:
    - GIVEN `~/.claude/logs/meeting-question-guard.log` WHEN grepped for that session THEN it contains at least one `OK` or `BLOCK` line (the turn became visible) -- and **no** `NOFLUSH` line for a turn that did end.
    - GIVEN a `NOFLUSH` line IS present THEN the poll premise is REFUTED for this harness: do **not** raise the budget blindly -- reopen with the measured `waited` value and route the redesign to the owner (a Stop hook may simply be unable to see its own turn, in which case the guard needs a different event or a deferred-by-one-turn design, both of which are behaviour changes).
    - GIVEN a non-meeting session THEN no wait is paid (already covered mechanically by `tests/test_meeting_question_guard_flush.sh` test 5, <1000 ms).
  - **Done-check**: record the observed log lines in this item, tick the checkbox, then `tests/run-tests.sh` fully green.
