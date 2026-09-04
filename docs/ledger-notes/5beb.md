# id:5beb

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— observed live 2026-08-22 (meeting D8). Clustered misses, NOT permanent disarm. TWO competing hypotheses, both testable against `~/.claude/logs/meeting-question-guard.log` timestamps: (1) the `stop_hook_active` loop guard at `main()` — it is the ONE exit that returns with no log line at all, so a suppressed check is indistinguishable from 'the hook never ran'; (2) **owner's hypothesis** — background task-notification entries interleaving into the transcript confuse `trailing_segment()`'s notion of 'this turn', which fits the clustering better since the misses coincided with agent/pool completions. Fix regardless of cause: make the loop-guard path LOG before returning — a silent return is the `id:4347` no-silent-swallow anti-pattern, in a file whose own docstring warns about exactly that class one level up. <!-- id:5beb -->
