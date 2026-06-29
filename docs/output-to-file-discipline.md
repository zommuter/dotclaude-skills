# Output-to-file discipline

> Source: TODO id:ef77 — 2026-06-18 `/insights` findings (meeting id:f1a7,
> `docs/meeting-notes/2026-06-18-1829-insights-findings-triage.md`). Deliberately a
> relay-context note, **NOT** a global always-loaded `~/.claude/CLAUDE.md` rule —
> the failure mode is narrow (output-token-capped sessions), so a doc avoids paying
> per-prompt context cost for an edge case. Re-open to global CLAUDE.md only if it
> recurs outside capped sessions.

## The rule

When a response would be long — a generated report, a large table, a multi-file dump,
a verbose analysis — **write it to a file with the Write tool and reply with only a
short confirmation plus the path.** Do not stream the full long output into the chat.

```
✓  "Wrote the audit to docs/audits/2026-06-29-relay-econ.md (42 findings, 3 flagged)."
✗  <420 lines of the audit pasted into the reply>
```

## Why

The trigger was an output-token-capped configuration (the ~500-output-token cap): a long
reply gets truncated mid-stream, so the user receives a *partial* artifact and the work
is effectively lost. Writing to a file sidesteps the cap entirely — the file holds the
full content regardless of the reply budget, and the short confirmation always fits.

It also keeps the transcript readable and the context small: a path is cheap to carry
forward; 400 inlined lines are re-read on every subsequent turn.

## When it applies

- The natural answer is a document, not a sentence (reports, audits, migration plans,
  generated configs, large diffs, data dumps).
- You are in a capped/limited-output session (the original trigger).
- The output is something the user will want to keep, search, or diff later.

## When it does NOT apply

- Short, conversational answers — inline them as normal.
- Content the user explicitly asked to see *in the reply*.
- Code edits — those go through Edit/Write to the actual source file, not a sidecar doc.
