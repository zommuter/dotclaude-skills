# 2026-07-20 — Privacy-gate log provenance (id:61b5)

**Started:** 2026-07-20 22:39
**Session:** f8ca6319-77a4-49d8-8e08-6e265f40c408
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity)
**Topic:** Add real provenance to privacy-gate findings so a leak can be attributed to a session/repo/host instead of being knowable only by luck.

## Context
`hooks/pre-push-privacy-gate.sh:167` writes findings as 5 positional TSV columns:
`ts ⇥ remote-url ⇥ ref ⇥ pattern ⇥ content`. `$REMOTE_URL` ($2) is the *resolved*
push target, which for the 10+ hermetic push-tests is a useless `/tmp/tmp.xxxx/remote.git`;
the responsible session is visible only when the leaked line itself embeds a session UUID.
Owner-tagged `[HARD — meeting]` (id:61b5). Sibling id:a8da (test-push log pollution) and
id:6c6e (askpass self-identify) share the "automated actions must self-identify" theme.

## Agenda
1. Which provenance fields, and are they available in a `pre-push` hook context?
2. Log-line format: how to extend the positional TSV without stranding the free-form `content` field?
3. Shared session-identity helper (61b5 ∩ 6c6e): build now, inline, or keep separate?

## Discussion
🏗️ **Archie:** The hook runs with cwd = the pushing repo, so `git rev-parse --show-toplevel`
yields the *real* source repo — the single field that fixes the useless-temp-path gap.
Capture `repo`, `sid=$CLAUDE_SESSION_ID`, `host`, `ppid` lazily inside the findings branch;
`$REMOTE_URL` stays (still true for real remotes).

😈 **Riku:** (a) `$CLAUDE_SESSION_ID` is present only for pushes from a Claude Bash shell —
systemd timers and manual pushes lack it; degrade to `-` and don't oversell the log as
always-attributing. (b) The hook's own `$$` is a throwaway subshell; `$PPID` (the git process)
is only marginally useful for same-second correlation — include, don't oversell. (c) Blindly
appending N loose columns turns every existing line into a "5-or-9 col" ambiguity — the same
positional-contract silent-break hazard the CLAUDE.md versioning table flags for classify.sh.

✂️ **Petra:** `content` is deliberately the *last* column at `:167` because it's free-form;
nothing added may strand it. On the helper: 6c6e is a different surface (an interactive
askpass prompt needing a reply channel, not a log field); overlap is ~3–4 env reads. N=2
wants two *real* consumers — 6c6e is on the roadmap but **undesigned**, so a shared helper now
is exactly the premature abstraction the determinism-gate rejects.

😈 **Riku:** Then make provenance a single self-describing `k=v;k=v` blob, not loose columns,
and insert it as col 5 so `content` stays trailing. That only "breaks" a positional parser —
and none is deployed (df87 block-mode/FP-calibration isn't built; today's only reader is human
eyeballs). Minimum evidence to prefer this: name one current 5-col consumer. There is none.

🏗️ **Archie:** New layout `ts ⇥ remote ⇥ ref ⇥ pattern ⇥ provenance ⇥ content`, provenance =
`repo=<top>;sid=<id-or->;host=<h>;ppid=<n>`. One capture block + a wider `printf` at `:167`,
plus a `from: <repo> (sid=…)` line in the human warning block (`:154-157`) so the loud print is
attributable too. Backward-tolerant, self-describing, `content` stays robustly last.

✂️ **Petra:** Explicitly out of scope: df87 block-mode; a8da test-hermeticity (the new `sid=`
merely *helps* it); building the 6c6e askpass helper; any edit to the private pattern file.
One hook + its tests.

## Decisions
- **D1 — Fields (ratified):** capture `repo` (`git rev-parse --show-toplevel`), `sid`
  (`$CLAUDE_SESSION_ID`), `host` (`hostname`), `ppid` (`$PPID`); each degrades to `-` when
  unavailable. Captured lazily inside the `if [[ -n "$findings" ]]` branch (cost only on a
  finding). *Out of scope:* `$PWD`/cwd (redundant with toplevel), any network lookup.
- **D2 — Format (ratified):** insert provenance as a single self-describing `k=v;k=v` blob at
  **column 5**, moving `content` to column 6, so `content` remains the free-form trailing
  field. Widen the log `printf` at `hooks/pre-push-privacy-gate.sh:167` and add an attributable
  `from: <repo> (sid=…)` line to the human warning block (`:154-157`). *Out of scope:* a full
  `key=value` rewrite of all fields (heavier than warranted; no deployed 5-col parser to justify
  the churn — df87 unbuilt).
- **D3 — No shared helper (ratified):** inline the ~4 env reads in the hook; do **not** build a
  shared session-identity helper. Leave a forward-flag on id:6c6e's design to reuse this
  capture shape when 6c6e is actually designed. Rationale: N=2 (6c6e undesigned → not yet a
  real second consumer) + determinism-gate (a 4-line env read is too small to mechanize).
  *Out of scope:* the 6c6e askpass helper itself.

## Action items
- [ ] Implement D1–D3 in `hooks/pre-push-privacy-gate.sh`: capture `repo/sid/host/ppid`
  (degrade to `-`) inside the findings branch; log line becomes
  `ts ⇥ remote ⇥ ref ⇥ pattern ⇥ repo=…;sid=…;host=…;ppid=… ⇥ content`; add a `from:` line to
  the warning block. Add/extend a test asserting the 6-column layout + that `sid` degrades to
  `-` when `$CLAUDE_SESSION_ID` is unset and to the real value when set. Design settled here —
  now `[ROUTINE]` executor work. <!-- id:61b5 -->
- [ ] Forward-flag: when id:6c6e (askpass self-identify) is designed, reuse this
  session-identity capture shape rather than re-deriving it. (Recorded on 6c6e in this note; no
  separate id — resolved by 6c6e's own design session.)
