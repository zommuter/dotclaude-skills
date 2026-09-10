# id:3dea -- a `[MECHANICAL]` recipe's `acceptance_artifact` is checked for EXISTENCE only, so a run that produced zero usable data is filed as success

Inbound `routed:82ec` from an `ai-codebench` relay review, 2026-09-10. **Verified here before
ingesting**, and it is a correction to this session's own work -- recorded that way on purpose.

## The defect

The mechanical daemon checks that a recipe's declared `acceptance_artifact` EXISTS. It does not
check that the artifact contains anything usable. So a run can exit 0, write a well-formed file
with no actual result in it, be filed into `done/`, and be reported as a success.

## Measured

`ai-codebench` `id:0ce2` (the `local-llm` judge run of 2026-09-09) exited 0, wrote its artifact,
was filed `done/`, and reached a handover commit as *"SUCCEEDED -- 3 verdicts.json verified"*.
Re-checked today, all three verdict files carry:

    20260909T225433-7f821b  ->  verdict = None   (7 keys present)
    20260909T225525-d1f12f  ->  verdict = None
    20260909T225737-198c59  ->  verdict = None

Seven keys, well-formed JSON, correct schema, and **no judgment in any of them**.

## Why this note names its own author

The "verified" claim in that handover was mine. What I actually did was parse one file and confirm
the record carried `schema_version`, `judge`, `judge_run_id`, `prompt`, `label_map`, `verdict` -- I
checked that the `verdict` FIELD EXISTED and never looked at its VALUE. The diagnostic this fleet
already uses for exactly this pathology is *"if this were broken, would this check look different?"*
Mine would not have: a null verdict and a real verdict produce identical output under a
field-presence check. That is `flow without signal` (a defect of **T** that inverts **G** in the
inflownistration grammar), committed in a handover as evidence.

So the daemon-side gap and the human-side gap are the same shape, one layer apart. Fixing only the
daemon leaves the reviewer free to repeat it; this note exists partly so the next reader sees both.

## The proposal, from the inbound report

Let a recipe declare an optional CONTENT predicate the daemon must pass before filing `done/` --
e.g. `acceptance_check: jq -e '.verdict != null'`. Existence stays the default (most artifacts are
logs with no machine-checkable success criterion), and a recipe that CAN state a predicate must.

Design points worth settling while building it:

* **Fail CLOSED on a declared predicate.** If `acceptance_check` is declared and cannot be
  evaluated (tool missing, artifact unparseable), that is a FAILURE, not a pass -- otherwise the
  predicate becomes the thing that silently cannot fail, which is the bug one level up.
* **Do NOT infer a predicate.** Guessing "a JSON artifact must have a non-null `verdict`" would
  misfire on every artifact whose schema differs. Declared or absent.
* **Report the predicate's verdict in the done/ record**, so a later reader can tell "passed a real
  check" from "existence only" without re-running anything. Today those two outcomes are
  indistinguishable after the fact, which is how the null verdicts survived a handover.
* A stale sibling `.error` file in `done/` already caused a near-false-failure report on this same
  recipe the same night (recorded in `docs/session-handover-2026-09-09.md`). `done/` accumulates
  per-id files across runs with nothing in the filename distinguishing attempts -- worth fixing in
  the same pass, since both defects make `done/` unreadable as evidence.

## Acceptance

* A recipe declaring `acceptance_check` is filed `done/` only if the predicate passes.
* A declared-but-unevaluable predicate FAILS the run loudly.
* A recipe with no `acceptance_check` behaves exactly as today (existence only).
* The `done/` record distinguishes "content-checked" from "existence-only".
* Replaying `id:0ce2`'s three null-verdict artifacts against a `jq -e '.verdict != null'` predicate
  reports FAILURE.

## Related

`routed:82ec` (the inbound report), `id:b477`/`id:b965` (the `[MECHANICAL]` OCR collector and its
gate), `id:3f59` (silence is not an answer -- the same family at the session level),
`id:5f6a` (a detector reporting its own diagnostic outcome as green), the it-infra
`checks-that-cannot-fail-visibly` memory.
