# id:fb2c

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED ON RELOCATION (2026-09-02, `id:40c0`) -- the verbatim claim above is amended
for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any
prose already in that section arrived by an earlier pass and is untouched here.** Fleet-rule violations found in the relocated
prose were FIXED here rather than parked: 6 punctuation em dashes became `--`. Nothing else changed: no word, figure, marker or line break was
altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation
included.

DELIBERATELY LEFT, declared rather than silently kept. 1 em dash inside BACKTICK code spans is NOT converted. A backticked span here
quotes something whose spelling is the point -- a lane tag, a heading that still
carries that character, a `path:line-range`, or live tool output -- so rewriting it
would make the quotation false.
The lane tag `[INPUT — meeting]` is NOT converted, neither delimiter nor name. Every lane tag in
this section is REFERENTIAL -- prose MENTIONING the vocabulary, inside backticks --
not the DECLARATIVE lane of any item, which stays on the ledger line. Rewriting a
referential tag corrupts a record of what a past run classified or of which
spelling a migration is about.

## From TODO

— owner decision 2026-08-22 (`/relay human`, REVIEW_ME.md tier (b)). A wrapped tree-wide reset (`eval '<the reset form>'`, `bash -c '<the reset form>'`) is currently ALLOWED: it tokenises cleanly and `_split_git_commands` only starts a command at a bare `git` token, so the quoted payload is one opaque argument the guard never inspects. Correctly blocked today: the `-C`-redirected reset, `cd sub && git checkout -- .`, `git clean -fdx`, `git stash drop`. **Now load-bearing:** since the owner's 2026-08-22 ruling the five tree-wide forms are an UNCONDITIONAL deny, so an agent that hits the wall has a live incentive to reach for `bash -c` — precisely the routed-around-into-the-tree-wide-form failure the guard's own header warns about. **Scope is deliberately BOUNDED:** the command-substitution form (a `$(...)`-built subcommand) stays an ACCEPTED, documented boundary — the owner explicitly declined the fuller "close every wrapper form" option, because the guard is accident-prevention, not adversarial, and chasing substitution adds false-positive surface. Done-check: the three wrapper forms deny; the substitution form still passes (assert it, so the boundary is pinned rather than merely unimplemented); no regression in the 18 currently-allowed forms, path-scoped reverts included. **Related, observed 2026-08-22 during the very pass that filed this:** the guard fired on a Bash call whose only offence was QUOTING a destructive form inside a heredoc — the `id:9979` false-positive class, live and now twice-confirmed. <!-- id:fb2c -->

  - **Decide before building (this is why the lane is `[INPUT — meeting]`, not `[ROUTINE]`):** (a) ONE skill with three modes or THREE skills -- they share a state model but differ in direction (wrapup = *close cleanly*, handover = *write what the next session must know*, resume = *read it back*), and the `meeting-cross`→`/meeting --cross` deprecation (`id:4f5f`) is the local precedent that separate alias-skills rot; (b) what the handover artifact IS and where it lives -- a file in the repo, an entry in the diary, `~/.config/`, or nothing durable at all (note the diary already records *what was done*; the gap is *what is still open and what the next session must not re-derive*); (c) what belongs in it -- open threads, decisions awaiting the owner, in-flight background agents/pool runs, uncommitted or parked work, and explicitly-rejected paths so they are not re-proposed; (d) overlap with the existing mandatory post-prompt pair -- `git-diary-workflow` + `todo-update` already run per prompt and already commit/push/record, so wrapup must NOT duplicate them, and per the standing ctx-budget heuristic these new skills should be **explicitly opt-in, never mandatory-per-prompt** (a per-prompt skill multiplies its SKILL.md size by prompt count); (e) whether `resume` is even a skill rather than just the harness's own context restoration -- check before building, since a skill that duplicates a harness feature is a vestige on arrival (constraint archaeology).
  - **Mechanize-first, with the LLM only where it must be:** the sweep is a pure-function check over git/filesystem/log state and should be a tested script that FAILS LOUDLY on each unclean condition; reserve the LLM for composing the handover prose (what is open, what was decided, what was deliberately not done). A detector whose resolution silently no-ops is the recorded anti-pattern -- so if the sweep finds a dirty tree or a live agent, it must surface and block the "clean wrapup" claim, not print and continue.
  - **Do NOT auto-act on findings.** Disposal of parked work stays human-invoked (`id:a4e9`), and stopping a pool is an owner decision. The skill reports; the human decides.

